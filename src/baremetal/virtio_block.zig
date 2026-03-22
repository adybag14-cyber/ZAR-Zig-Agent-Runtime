// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const builtin = @import("builtin");
const abi = @import("abi.zig");
const pci = @import("pci.zig");

const virtio_f_version_1_mask: u32 = 1 << 0;

const virtio_status_acknowledge: u8 = 1;
const virtio_status_driver: u8 = 2;
const virtio_status_driver_ok: u8 = 4;
const virtio_status_features_ok: u8 = 8;

const virtio_desc_flag_next: u16 = 1;
const virtio_desc_flag_write: u16 = 2;
const queue_capacity: u16 = 8;
const request_timeout_iterations: usize = 2_000_000;
const request_type_in: u32 = 0;
const request_type_out: u32 = 1;
const request_type_flush: u32 = 4;
const response_status_ok: u8 = 0;
const response_status_ioerr: u8 = 1;
const response_status_unsupported: u8 = 2;
const max_transfer_bytes: usize = 4096;
const max_mock_blocks: usize = 1024;
const default_block_size: u32 = 512;

pub const Error = error{
    UnsupportedPlatform,
    DeviceNotFound,
    MissingVersion1,
    FeaturesRejected,
    QueueUnavailable,
    QueueTooSmall,
    RequestTimedOut,
    InvalidBufferSize,
    BufferTooLarge,
    SectorOutOfRange,
    NotInitialized,
    IoError,
    UnsupportedRequest,
};

const VirtioPciCommonCfg = extern struct {
    device_feature_select: u32,
    device_feature: u32,
    driver_feature_select: u32,
    driver_feature: u32,
    config_msix_vector: u16,
    num_queues: u16,
    device_status: u8,
    config_generation: u8,
    queue_select: u16,
    queue_size: u16,
    queue_msix_vector: u16,
    queue_enable: u16,
    queue_notify_off: u16,
    queue_desc: u64,
    queue_driver: u64,
    queue_device: u64,
    queue_notify_data: u16,
    queue_reset: u16,
    admin_queue_index: u16,
    admin_queue_num: u16,
};

const VirtioBlkConfig = extern struct {
    capacity: u64,
    size_max: u32,
    seg_max: u32,
    geometry_cylinders: u16,
    geometry_heads: u8,
    geometry_sectors: u8,
    blk_size: u32,
};

const VirtqDesc = extern struct {
    addr: u64,
    len: u32,
    flags: u16,
    next: u16,
};

const VirtqAvail = extern struct {
    flags: u16,
    idx: u16,
    ring: [queue_capacity]u16,
    used_event: u16,
};

const VirtqUsedElem = extern struct {
    id: u32,
    len: u32,
};

const VirtqUsed = extern struct {
    flags: u16,
    idx: u16,
    ring: [queue_capacity]VirtqUsedElem,
    avail_event: u16,
};

const RequestHeader = extern struct {
    type: u32,
    reserved: u32,
    sector: u64,
};

var state: abi.BaremetalStorageState = undefined;
var active_device: ?pci.VirtioBlockDevice = null;
var active_queue_notify_off: u16 = 0;
var mock_enabled = false;
var mock_block_count: u32 = 0;
var mock_disk: [max_mock_blocks * 512]u8 align(4096) = [_]u8{0} ** (max_mock_blocks * 512);
var read_byte_scratch: [max_transfer_bytes]u8 align(4096) = [_]u8{0} ** max_transfer_bytes;

var queue_desc: [queue_capacity]VirtqDesc align(4096) = undefined;
var queue_avail: VirtqAvail align(4096) = undefined;
var queue_used: VirtqUsed align(4096) = undefined;
var request_header: RequestHeader align(16) = undefined;
var request_status: u8 align(16) = 0;
var last_avail_idx: u16 = 0;
var last_used_idx: u16 = 0;

fn hardwareBacked() bool {
    return builtin.os.tag == .freestanding and builtin.cpu.arch == .x86_64;
}

pub fn statePtr() *const abi.BaremetalStorageState {
    return &state;
}

pub fn resetForTest() void {
    resetState();
    active_device = null;
    active_queue_notify_off = 0;
    mock_enabled = false;
    mock_block_count = 0;
    @memset(&mock_disk, 0);
    @memset(&read_byte_scratch, 0);
    @memset(&queue_desc, std.mem.zeroes(VirtqDesc));
    queue_avail = std.mem.zeroes(VirtqAvail);
    queue_used = std.mem.zeroes(VirtqUsed);
    request_header = std.mem.zeroes(RequestHeader);
    request_status = 0;
    last_avail_idx = 0;
    last_used_idx = 0;
}

pub fn init() void {
    _ = initDetailed() catch {};
}

pub fn testEnableMockDevice(block_count: u32) void {
    if (!builtin.is_test) return;
    resetForTest();
    mock_enabled = true;
    mock_block_count = @min(block_count, max_mock_blocks);
}

pub fn testDisableMockDevice() void {
    if (!builtin.is_test) return;
    resetForTest();
}

pub fn testReadMockByteRaw(lba: u32, offset: u32) u8 {
    if (!builtin.is_test) return 0;
    if (lba >= mock_block_count or offset >= 512) return 0;
    return mock_disk[(@as(usize, lba) * 512) + offset];
}

pub fn initDetailed() Error!void {
    if (mock_enabled) {
        return initMock();
    }
    if (!hardwareBacked()) return error.UnsupportedPlatform;

    const device = pci.discoverVirtioBlockDevice() orelse return error.DeviceNotFound;
    pci.enableVirtioBlockMemoryAndBusMaster(device.location);
    const queue_notify_off = try initTransport(device);
    const cfg = deviceCfg(device);
    const block_size = if (cfg.blk_size == 0) @as(u32, 512) else cfg.blk_size;
    const capacity = cfg.capacity;
    if (capacity > std.math.maxInt(u32)) return error.SectorOutOfRange;

    active_device = device;
    active_queue_notify_off = queue_notify_off;
    state = .{
        .magic = abi.storage_magic,
        .api_version = abi.api_version,
        .backend = abi.storage_backend_virtio_block,
        .mounted = 1,
        .block_size = block_size,
        .block_count = @intCast(capacity),
        .read_ops = 0,
        .write_ops = 0,
        .flush_ops = 0,
        .last_lba = 0,
        .last_block_count = 0,
        .dirty = 0,
        .reserved0 = .{ 0, 0, 0 },
        .bytes_read = 0,
        .bytes_written = 0,
    };
}

pub fn readBlocks(start_lba: u32, buffer: []u8) Error!void {
    try ensureInitialized();
    const block_size = state.block_size;
    if (buffer.len == 0) return;
    if (buffer.len > max_transfer_bytes) return error.BufferTooLarge;
    if (block_size == 0 or buffer.len % block_size != 0) return error.InvalidBufferSize;
    const block_count: u32 = @intCast(buffer.len / block_size);
    try ensureRange(start_lba, block_count);

    if (mock_enabled) {
        copyMockRangeOut(start_lba, buffer);
    } else {
        const device = active_device orelse return error.NotInitialized;
        try submitRequest(device, active_queue_notify_off, request_type_in, start_lba, @intFromPtr(buffer.ptr), buffer.len, true);
    }
    state.read_ops +%= 1;
    state.last_lba = start_lba;
    state.last_block_count = block_count;
    state.bytes_read +%= buffer.len;
}

pub fn writeBlocks(start_lba: u32, data: []const u8) Error!void {
    try ensureInitialized();
    const block_size = state.block_size;
    if (data.len == 0) return;
    if (data.len > max_transfer_bytes) return error.BufferTooLarge;
    if (block_size == 0 or data.len % block_size != 0) return error.InvalidBufferSize;
    const block_count: u32 = @intCast(data.len / block_size);
    try ensureRange(start_lba, block_count);

    if (mock_enabled) {
        copyMockRangeIn(start_lba, data);
    } else {
        const device = active_device orelse return error.NotInitialized;
        try submitRequest(device, active_queue_notify_off, request_type_out, start_lba, @intFromPtr(data.ptr), data.len, false);
    }
    state.write_ops +%= 1;
    state.last_lba = start_lba;
    state.last_block_count = block_count;
    state.bytes_written +%= data.len;
    state.dirty = 1;
}

pub fn flush() Error!void {
    try ensureInitialized();
    if (!mock_enabled) {
        const device = active_device orelse return error.NotInitialized;
        try submitRequest(device, active_queue_notify_off, request_type_flush, 0, 0, 0, false);
    }
    state.flush_ops +%= 1;
    state.dirty = 0;
}

pub fn readByte(lba: u32, offset: u32) u8 {
    if (state.mounted == 0) return 0;
    if (offset >= state.block_size) return 0;

    if (mock_enabled) {
        if (lba >= mock_block_count) return 0;
        return mock_disk[(@as(usize, lba) * @as(usize, state.block_size)) + @as(usize, offset)];
    }

    const scratch_len: usize = @intCast(state.block_size);
    if (scratch_len == 0 or scratch_len > read_byte_scratch.len) return 0;
    ensureRange(lba, 1) catch return 0;
    const device = active_device orelse return 0;
    submitRequest(
        device,
        active_queue_notify_off,
        request_type_in,
        lba,
        @intFromPtr(read_byte_scratch[0..scratch_len].ptr),
        scratch_len,
        true,
    ) catch return 0;
    return read_byte_scratch[@as(usize, offset)];
}

fn initMock() Error!void {
    state = .{
        .magic = abi.storage_magic,
        .api_version = abi.api_version,
        .backend = abi.storage_backend_virtio_block,
        .mounted = 1,
        .block_size = default_block_size,
        .block_count = mock_block_count,
        .read_ops = 0,
        .write_ops = 0,
        .flush_ops = 0,
        .last_lba = 0,
        .last_block_count = 0,
        .dirty = 0,
        .reserved0 = .{ 0, 0, 0 },
        .bytes_read = 0,
        .bytes_written = 0,
    };
}

fn ensureInitialized() Error!void {
    if (state.mounted == 0) return error.NotInitialized;
}

fn ensureRange(start_lba: u32, block_count: u32) Error!void {
    if (block_count == 0) return;
    const end_lba = @as(u64, start_lba) + @as(u64, block_count);
    if (end_lba > state.block_count) return error.SectorOutOfRange;
}

fn copyMockRangeOut(start_lba: u32, buffer: []u8) void {
    const start = @as(usize, start_lba) * 512;
    @memcpy(buffer, mock_disk[start .. start + buffer.len]);
}

fn copyMockRangeIn(start_lba: u32, data: []const u8) void {
    const start = @as(usize, start_lba) * 512;
    @memcpy(mock_disk[start .. start + data.len], data);
}

fn resetState() void {
    state = .{
        .magic = abi.storage_magic,
        .api_version = abi.api_version,
        .backend = abi.storage_backend_virtio_block,
        .mounted = 0,
        .block_size = default_block_size,
        .block_count = 0,
        .read_ops = 0,
        .write_ops = 0,
        .flush_ops = 0,
        .last_lba = 0,
        .last_block_count = 0,
        .dirty = 0,
        .reserved0 = .{ 0, 0, 0 },
        .bytes_read = 0,
        .bytes_written = 0,
    };
}

fn commonCfg(device: pci.VirtioBlockDevice) *volatile VirtioPciCommonCfg {
    return @as(*volatile VirtioPciCommonCfg, @ptrFromInt(@as(usize, @intCast(device.common_cfg.address))));
}

fn deviceCfg(device: pci.VirtioBlockDevice) *volatile VirtioBlkConfig {
    return @as(*volatile VirtioBlkConfig, @ptrFromInt(@as(usize, @intCast(device.device_cfg.address))));
}

fn notifyAddress(device: pci.VirtioBlockDevice, queue_notify_off: u16) u64 {
    return device.notify_cfg.address + (@as(u64, queue_notify_off) * @as(u64, device.notify_off_multiplier));
}

fn notifyQueue(device: pci.VirtioBlockDevice, queue_notify_off: u16) void {
    const notify_ptr = @as(*volatile u16, @ptrFromInt(@as(usize, @intCast(notifyAddress(device, queue_notify_off)))));
    notify_ptr.* = 0;
}

fn fence() void {
    asm volatile ("" ::: .{ .memory = true });
}

fn pause() void {
    asm volatile ("pause" ::: .{ .memory = true });
}

fn readDeviceFeature(device: pci.VirtioBlockDevice, select: u32) u32 {
    const common = commonCfg(device);
    common.device_feature_select = select;
    fence();
    return common.device_feature;
}

fn writeDriverFeature(device: pci.VirtioBlockDevice, select: u32, value: u32) void {
    const common = commonCfg(device);
    common.driver_feature_select = select;
    common.driver_feature = value;
    fence();
}

fn setStatus(common: *volatile VirtioPciCommonCfg, status_bits: u8) void {
    common.device_status = status_bits;
    fence();
}

fn appendStatus(common: *volatile VirtioPciCommonCfg, status_bits: u8) void {
    setStatus(common, common.device_status | status_bits);
}

fn initQueue(device: pci.VirtioBlockDevice) Error!u16 {
    const common = commonCfg(device);
    common.queue_select = 0;
    fence();
    const offered_size = common.queue_size;
    if (offered_size == 0) return error.QueueUnavailable;
    if (offered_size < 3) return error.QueueTooSmall;

    const queue_size: u16 = @min(offered_size, queue_capacity);
    @memset(&queue_desc, std.mem.zeroes(VirtqDesc));
    queue_avail = std.mem.zeroes(VirtqAvail);
    queue_used = std.mem.zeroes(VirtqUsed);
    last_avail_idx = 0;
    last_used_idx = 0;

    common.queue_size = queue_size;
    common.queue_desc = @intFromPtr(&queue_desc[0]);
    common.queue_driver = @intFromPtr(&queue_avail);
    common.queue_device = @intFromPtr(&queue_used);
    common.queue_enable = 1;
    fence();
    return common.queue_notify_off;
}

fn initTransport(device: pci.VirtioBlockDevice) Error!u16 {
    const common = commonCfg(device);
    setStatus(common, 0);
    appendStatus(common, virtio_status_acknowledge);
    appendStatus(common, virtio_status_driver);

    const device_features1 = readDeviceFeature(device, 1);
    if ((device_features1 & virtio_f_version_1_mask) == 0) return error.MissingVersion1;

    writeDriverFeature(device, 0, 0);
    writeDriverFeature(device, 1, virtio_f_version_1_mask);
    appendStatus(common, virtio_status_features_ok);
    if ((common.device_status & virtio_status_features_ok) == 0) return error.FeaturesRejected;

    const queue_notify_off = try initQueue(device);
    appendStatus(common, virtio_status_driver_ok);
    return queue_notify_off;
}

fn submitRequest(device: pci.VirtioBlockDevice, queue_notify_off: u16, request_type: u32, sector: u32, data_addr: u64, data_len: usize, device_writes_data: bool) Error!void {
    request_header = .{
        .type = request_type,
        .reserved = 0,
        .sector = sector,
    };
    request_status = 0xFF;

    if (data_len == 0) {
        queue_desc[0] = .{
            .addr = @intFromPtr(&request_header),
            .len = @sizeOf(RequestHeader),
            .flags = virtio_desc_flag_next,
            .next = 1,
        };
        queue_desc[1] = .{
            .addr = @intFromPtr(&request_status),
            .len = 1,
            .flags = virtio_desc_flag_write,
            .next = 0,
        };
    } else {
        queue_desc[0] = .{
            .addr = @intFromPtr(&request_header),
            .len = @sizeOf(RequestHeader),
            .flags = virtio_desc_flag_next,
            .next = 1,
        };
        queue_desc[1] = .{
            .addr = data_addr,
            .len = @intCast(data_len),
            .flags = (if (device_writes_data) virtio_desc_flag_write else 0) | virtio_desc_flag_next,
            .next = 2,
        };
        queue_desc[2] = .{
            .addr = @intFromPtr(&request_status),
            .len = 1,
            .flags = virtio_desc_flag_write,
            .next = 0,
        };
    }

    queue_avail.ring[last_avail_idx % queue_capacity] = 0;
    fence();
    last_avail_idx +%= 1;
    queue_avail.idx = last_avail_idx;
    fence();
    notifyQueue(device, queue_notify_off);

    var spin: usize = 0;
    while (spin < request_timeout_iterations) : (spin += 1) {
        if (queue_used.idx != last_used_idx) {
            last_used_idx = queue_used.idx;
            return switch (request_status) {
                response_status_ok => {},
                response_status_ioerr => error.IoError,
                response_status_unsupported => error.UnsupportedRequest,
                else => error.IoError,
            };
        }
        pause();
    }
    return error.RequestTimedOut;
}

test "virtio block mock read write flush updates state" {
    testEnableMockDevice(64);
    defer testDisableMockDevice();

    try initDetailed();
    const initial = statePtr();
    try std.testing.expectEqual(@as(u8, abi.storage_backend_virtio_block), initial.backend);
    try std.testing.expectEqual(@as(u8, 1), initial.mounted);
    try std.testing.expectEqual(@as(u32, 64), initial.block_count);
    try std.testing.expectEqual(@as(u32, 512), initial.block_size);

    var write_buffer: [1024]u8 = undefined;
    for (&write_buffer, 0..) |*byte, index| byte.* = @as(u8, @truncate(0x61 + index));
    try writeBlocks(4, &write_buffer);
    try flush();

    var read_buffer: [1024]u8 = [_]u8{0} ** 1024;
    try readBlocks(4, &read_buffer);
    try std.testing.expectEqualSlices(u8, &write_buffer, &read_buffer);
    try std.testing.expectEqual(@as(u8, 0x61), testReadMockByteRaw(4, 0));
    try std.testing.expectEqual(@as(u8, 0x62), testReadMockByteRaw(4, 1));
    try std.testing.expectEqual(@as(u8, @truncate(0x61 + 512)), testReadMockByteRaw(5, 0));
    try std.testing.expectEqual(@as(u32, 1), state.read_ops);
    try std.testing.expectEqual(@as(u32, 1), state.write_ops);
    try std.testing.expectEqual(@as(u32, 1), state.flush_ops);
    try std.testing.expectEqual(@as(u8, 0), state.dirty);
    try std.testing.expectEqual(@as(u64, 1024), state.bytes_read);
    try std.testing.expectEqual(@as(u64, 1024), state.bytes_written);
}

test "virtio block mock rejects invalid range and size" {
    testEnableMockDevice(8);
    defer testDisableMockDevice();

    try initDetailed();

    var short_buffer: [17]u8 = [_]u8{0} ** 17;
    try std.testing.expectError(error.InvalidBufferSize, writeBlocks(0, &short_buffer));

    var full_block: [512]u8 = [_]u8{0} ** 512;
    try std.testing.expectError(error.SectorOutOfRange, readBlocks(8, &full_block));
}
