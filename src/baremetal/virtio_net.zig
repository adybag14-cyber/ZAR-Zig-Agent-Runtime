// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const builtin = @import("builtin");
const abi = @import("abi.zig");
const pci = @import("pci.zig");

pub const Error = error{
    NotAvailable,
    NotInitialized,
    FrameTooLarge,
    Timeout,
    HardwareFault,
};

pub const InitError = error{
    UnsupportedPlatform,
    DeviceNotFound,
    MissingVersion1,
    MissingMacFeature,
    FeaturesRejected,
    QueueUnavailable,
    QueueTooSmall,
    QueueInitFailed,
    MacReadFailed,
};

const virtio_f_version_1_word: u32 = 1;
const virtio_f_version_1_mask: u32 = 1 << 0;
const virtio_net_f_mac: u32 = 1 << 5;
const virtio_net_f_status: u32 = 1 << 16;
const virtio_net_s_link_up: u16 = 1;

const virtio_status_acknowledge: u8 = 1;
const virtio_status_driver: u8 = 2;
const virtio_status_driver_ok: u8 = 4;
const virtio_status_features_ok: u8 = 8;

const virtio_desc_flag_next: u16 = 1;
const virtio_desc_flag_write: u16 = 2;
const queue_index_rx: u16 = 0;
const queue_index_tx: u16 = 1;
const queue_capacity: u16 = 8;
const queue_slot_count: usize = queue_capacity / 2;
const frame_buffer_capacity: usize = 2048;
const rx_snapshot_capacity: usize = 2048;
const min_frame_len: usize = 60;
const request_timeout_iterations: usize = 2_000_000;

const default_mock_mac = [6]u8{ 0x52, 0x54, 0x00, 0xA2, 0x00, 0x01 };

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

const VirtioNetConfig = extern struct {
    mac: [6]u8,
    status: u16,
    max_virtqueue_pairs: u16,
    mtu: u16,
    speed: u32,
    duplex: u8,
    rss_max_key_size: u8,
    rss_max_indirection_table_length: u16,
    supported_hash_types: u32,
};

const VirtioNetHdr = extern struct {
    flags: u8,
    gso_type: u8,
    hdr_len: u16,
    gso_size: u16,
    csum_start: u16,
    csum_offset: u16,
    num_buffers: u16,
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

fn defaultState() abi.BaremetalEthernetState {
    return .{
        .magic = abi.ethernet_magic,
        .api_version = abi.api_version,
        .backend = abi.ethernet_backend_none,
        .initialized = 0,
        .hardware_backed = 0,
        .tx_enabled = 0,
        .rx_enabled = 0,
        .loopback_enabled = 0,
        .link_up = 0,
        .pci_bus = 0,
        .pci_device = 0,
        .pci_function = 0,
        .irq_line = 0,
        .reserved0 = .{ 0, 0, 0 },
        .io_base = 0,
        .tx_packets = 0,
        .rx_packets = 0,
        .tx_errors = 0,
        .rx_errors = 0,
        .rx_overflows = 0,
        .last_tx_len = 0,
        .last_rx_len = 0,
        .last_tx_status = 0,
        .last_rx_status = 0,
        .tx_index = 0,
        .reserved1 = .{ 0, 0, 0 },
        .mac = .{ 0, 0, 0, 0, 0, 0 },
        .reserved2 = .{ 0, 0 },
        .rx_consumer_offset = 0,
    };
}

var state: abi.BaremetalEthernetState = defaultState();
var active_device: ?pci.VirtioNetDevice = null;
var active_rx_queue_notify_off: u16 = 0;
var active_tx_queue_notify_off: u16 = 0;

var rx_desc: [queue_capacity]VirtqDesc align(4096) = undefined;
var rx_avail: VirtqAvail align(4096) = undefined;
var rx_used: VirtqUsed align(4096) = undefined;
var tx_desc: [queue_capacity]VirtqDesc align(4096) = undefined;
var tx_avail: VirtqAvail align(4096) = undefined;
var tx_used: VirtqUsed align(4096) = undefined;

var rx_headers: [queue_slot_count]VirtioNetHdr align(16) = [_]VirtioNetHdr{std.mem.zeroes(VirtioNetHdr)} ** queue_slot_count;
var tx_headers: [queue_slot_count]VirtioNetHdr align(16) = [_]VirtioNetHdr{std.mem.zeroes(VirtioNetHdr)} ** queue_slot_count;
var rx_buffers: [queue_slot_count][frame_buffer_capacity]u8 align(16) = [_][frame_buffer_capacity]u8{[_]u8{0} ** frame_buffer_capacity} ** queue_slot_count;
var tx_buffers: [queue_slot_count][frame_buffer_capacity]u8 align(16) = [_][frame_buffer_capacity]u8{[_]u8{0} ** frame_buffer_capacity} ** queue_slot_count;
var rx_snapshot: [rx_snapshot_capacity]u8 = [_]u8{0} ** rx_snapshot_capacity;
var tx_snapshot: [frame_buffer_capacity]u8 = [_]u8{0} ** frame_buffer_capacity;

var rx_posted_idx: u16 = 0;
var rx_last_used_idx: u16 = 0;
var tx_avail_idx: u16 = 0;
var tx_last_used_idx: u16 = 0;

var mock_enabled: bool = false;
var mock_pending_rx_len: u32 = 0;
var mock_pending_rx_status: u32 = 0;
const SendHook = *const fn (frame: []const u8) void;
var mock_send_hook: ?SendHook = null;
var probe_send_hook: ?SendHook = null;
var probe_pending_rx_len: u32 = 0;
var probe_pending_rx_status: u32 = 0;

pub fn resetForTest() void {
    resetState();
    @memset(&rx_desc, std.mem.zeroes(VirtqDesc));
    rx_avail = std.mem.zeroes(VirtqAvail);
    rx_used = std.mem.zeroes(VirtqUsed);
    @memset(&tx_desc, std.mem.zeroes(VirtqDesc));
    tx_avail = std.mem.zeroes(VirtqAvail);
    tx_used = std.mem.zeroes(VirtqUsed);
    @memset(&rx_headers, std.mem.zeroes(VirtioNetHdr));
    @memset(&tx_headers, std.mem.zeroes(VirtioNetHdr));
    @memset(&rx_buffers, [_]u8{0} ** frame_buffer_capacity);
    @memset(&tx_buffers, [_]u8{0} ** frame_buffer_capacity);
    @memset(&rx_snapshot, 0);
    @memset(&tx_snapshot, 0);
    rx_posted_idx = 0;
    rx_last_used_idx = 0;
    tx_avail_idx = 0;
    tx_last_used_idx = 0;
    mock_enabled = false;
    mock_pending_rx_len = 0;
    mock_pending_rx_status = 0;
    mock_send_hook = null;
    probe_send_hook = null;
    probe_pending_rx_len = 0;
    probe_pending_rx_status = 0;
}

pub fn testEnableMockDevice() void {
    if (!builtin.is_test) return;
    resetForTest();
    mock_enabled = true;
}

pub fn enableSyntheticDeviceForBenchmark() void {
    resetForTest();
    mock_enabled = true;
}

pub fn testDisableMockDevice() void {
    if (!builtin.is_test) return;
    resetForTest();
}

pub fn disableSyntheticDeviceForBenchmark() void {
    resetForTest();
}

pub fn testInstallMockSendHook(hook: ?SendHook) void {
    if (!builtin.is_test) return;
    mock_send_hook = hook;
}

pub fn installProbeSendHook(hook: ?SendHook) void {
    probe_send_hook = hook;
}

pub fn injectProbeReceive(frame: []const u8) void {
    const rx_len: usize = @min(frame.len, rx_snapshot_capacity);
    std.mem.copyForwards(u8, rx_snapshot[0..rx_len], frame[0..rx_len]);
    probe_pending_rx_len = @as(u32, @intCast(rx_len));
    probe_pending_rx_status = 1;
}

pub fn statePtr() *const abi.BaremetalEthernetState {
    return &state;
}

pub fn init() bool {
    initDetailed() catch return false;
    return true;
}

pub fn initDetailed() InitError!void {
    if (state.magic != abi.ethernet_magic or state.api_version != abi.api_version) {
        resetState();
    }
    if (state.initialized != 0) return;

    resetState();
    if (mockAvailable()) {
        initMock();
        return;
    }
    if (!hardwareBacked()) return error.UnsupportedPlatform;

    const nic = pci.discoverVirtioNetDevice() orelse return error.DeviceNotFound;
    pci.enableVirtioNetMemoryAndBusMaster(nic.location);

    const device_features0 = readDeviceFeature(nic, 0);
    const transport = try initTransport(nic, device_features0);
    const cfg = deviceCfg(nic);

    active_device = nic;
    active_rx_queue_notify_off = transport.rx_queue_notify_off;
    active_tx_queue_notify_off = transport.tx_queue_notify_off;

    state.backend = abi.ethernet_backend_virtio_net;
    state.initialized = 1;
    state.hardware_backed = 1;
    state.tx_enabled = 1;
    state.rx_enabled = 1;
    state.link_up = transport.link_up;
    state.pci_bus = nic.location.bus;
    state.pci_device = nic.location.device;
    state.pci_function = nic.location.function;
    state.irq_line = nic.irq_line;
    state.io_base = @as(u32, @truncate(nic.common_cfg.address));
    state.tx_index = 0;
    state.rx_consumer_offset = 0;
    state.mac = cfg.mac;
    if (macIsZero(state.mac)) return error.MacReadFailed;

    notifyQueue(nic, active_rx_queue_notify_off, queue_index_rx);
}

pub fn macByte(index: u32) u8 {
    if (index >= state.mac.len) return 0;
    return state.mac[index];
}

pub fn sendPattern(byte_len: u32, seed: u8) Error!u32 {
    if (state.initialized == 0 and !init()) return error.NotAvailable;
    const requested_len: usize = @intCast(byte_len);
    const send_len = @min(frame_buffer_capacity, @max(min_frame_len, requested_len));
    var frame = [_]u8{0} ** frame_buffer_capacity;
    buildPatternFrame(frame[0..send_len], seed, state.mac);
    try sendFrame(frame[0..send_len]);
    return @as(u32, @intCast(send_len));
}

pub fn sendFrame(frame: []const u8) Error!void {
    if (state.initialized == 0 and !init()) return error.NotAvailable;
    if (frame.len > frame_buffer_capacity) return error.FrameTooLarge;

    const send_len: usize = @max(min_frame_len, frame.len);
    const tx_slot: usize = @as(usize, @intCast(state.tx_index % queue_slot_count));
    const tx_buf = tx_buffers[tx_slot][0..send_len];
    @memset(tx_buf, 0);
    std.mem.copyForwards(u8, tx_buf[0..frame.len], frame);
    std.mem.copyForwards(u8, tx_snapshot[0..send_len], tx_buf[0..send_len]);
    tx_headers[tx_slot] = std.mem.zeroes(VirtioNetHdr);
    state.last_tx_len = @as(u32, @intCast(send_len));
    state.last_tx_status = 0;

    if (probe_send_hook) |hook| hook(tx_buf[0..send_len]);

    if (mockAvailable()) {
        if (mock_send_hook) |hook| {
            hook(tx_buf[0..send_len]);
        } else {
            queueMockReceive(tx_buf[0..send_len]);
        }
        state.tx_packets +%= 1;
        state.last_tx_status = 1;
        state.tx_index = @as(u8, @intCast((tx_slot + 1) % queue_slot_count));
        return;
    }

    const device = active_device orelse return error.NotInitialized;
    waitForTxDrain() catch {
        state.tx_errors +%= 1;
        return error.Timeout;
    };

    const head = txHeadIndexForSlot(tx_slot);
    const data_index = head + 1;
    tx_desc[head] = .{
        .addr = @intFromPtr(&tx_headers[tx_slot]),
        .len = @sizeOf(VirtioNetHdr),
        .flags = virtio_desc_flag_next,
        .next = data_index,
    };
    tx_desc[data_index] = .{
        .addr = @intFromPtr(tx_buf.ptr),
        .len = @as(u32, @intCast(send_len)),
        .flags = 0,
        .next = 0,
    };

    tx_avail.ring[tx_avail_idx % queue_capacity] = head;
    fence();
    tx_avail_idx +%= 1;
    tx_avail.idx = tx_avail_idx;
    fence();
    notifyQueue(device, active_tx_queue_notify_off, queue_index_tx);
    waitForTxDrain() catch {
        state.tx_errors +%= 1;
        return error.Timeout;
    };

    state.tx_packets +%= 1;
    state.last_tx_status = 1;
    state.tx_index = @as(u8, @intCast((tx_slot + 1) % queue_slot_count));
}

pub fn pollReceive() Error!u32 {
    if (state.initialized == 0 and !init()) return error.NotAvailable;

    if (probe_pending_rx_len != 0) {
        state.last_rx_len = probe_pending_rx_len;
        state.last_rx_status = probe_pending_rx_status;
        state.rx_packets +%= 1;
        probe_pending_rx_len = 0;
        probe_pending_rx_status = 0;
        return state.last_rx_len;
    }

    if (mockAvailable()) {
        if (mock_pending_rx_len == 0) return 0;
        state.last_rx_len = mock_pending_rx_len;
        state.last_rx_status = mock_pending_rx_status;
        state.rx_packets +%= 1;
        mock_pending_rx_len = 0;
        mock_pending_rx_status = 0;
        return state.last_rx_len;
    }

    const device = active_device orelse return error.NotInitialized;
    if (rx_used.idx == rx_last_used_idx) return 0;

    const used_index: usize = @as(usize, @intCast(rx_last_used_idx % queue_capacity));
    const used_entry = rx_used.ring[used_index];
    rx_last_used_idx +%= 1;

    const head: u16 = @as(u16, @intCast(used_entry.id));
    if (head >= queue_capacity or (head & 1) != 0) {
        state.rx_errors +%= 1;
        return error.HardwareFault;
    }

    const slot = rxSlotForHead(head);
    if (used_entry.len < @sizeOf(VirtioNetHdr)) {
        state.rx_errors +%= 1;
        try rearmRxSlot(device, slot);
        return error.HardwareFault;
    }

    const frame_len: usize = @min(@as(usize, used_entry.len) - @sizeOf(VirtioNetHdr), rx_snapshot_capacity);
    std.mem.copyForwards(u8, rx_snapshot[0..frame_len], rx_buffers[slot][0..frame_len]);
    state.last_rx_len = @as(u32, @intCast(frame_len));
    state.last_rx_status = 1;
    state.rx_packets +%= 1;
    state.rx_consumer_offset = @as(u32, @intCast((slot + 1) % queue_slot_count));
    try rearmRxSlot(device, slot);
    return state.last_rx_len;
}

pub fn rxByte(index: u32) u8 {
    if (index >= state.last_rx_len or index >= rx_snapshot_capacity) return 0;
    return rx_snapshot[index];
}

pub fn txByte(index: u32) u8 {
    if (index >= state.last_tx_len or index >= frame_buffer_capacity) return 0;
    return tx_snapshot[index];
}

fn resetState() void {
    state = defaultState();
    active_device = null;
    active_rx_queue_notify_off = 0;
    active_tx_queue_notify_off = 0;
}

fn initMock() void {
    state = defaultState();
    state.backend = abi.ethernet_backend_virtio_net;
    state.initialized = 1;
    state.hardware_backed = 0;
    state.tx_enabled = 1;
    state.rx_enabled = 1;
    state.link_up = 1;
    state.io_base = 0xC300;
    state.mac = default_mock_mac;
}

fn mockAvailable() bool {
    return mock_enabled;
}

fn hardwareBacked() bool {
    return builtin.os.tag == .freestanding and (builtin.cpu.arch == .x86 or builtin.cpu.arch == .x86_64);
}

fn commonCfg(device: pci.VirtioNetDevice) *volatile VirtioPciCommonCfg {
    return @as(*volatile VirtioPciCommonCfg, @ptrFromInt(@as(usize, @intCast(device.common_cfg.address))));
}

fn deviceCfg(device: pci.VirtioNetDevice) *volatile VirtioNetConfig {
    return @as(*volatile VirtioNetConfig, @ptrFromInt(@as(usize, @intCast(device.device_cfg.address))));
}

fn notifyAddress(device: pci.VirtioNetDevice, queue_notify_off: u16) u64 {
    return device.notify_cfg.address + (@as(u64, queue_notify_off) * @as(u64, device.notify_off_multiplier));
}

fn notifyQueue(device: pci.VirtioNetDevice, queue_notify_off: u16, queue_index: u16) void {
    const notify_ptr = @as(*volatile u16, @ptrFromInt(@as(usize, @intCast(notifyAddress(device, queue_notify_off)))));
    notify_ptr.* = queue_index;
}

fn fence() void {
    asm volatile ("" ::: .{ .memory = true });
}

fn pause() void {
    asm volatile ("pause" ::: .{ .memory = true });
}

fn readDeviceFeature(device: pci.VirtioNetDevice, select: u32) u32 {
    const common = commonCfg(device);
    common.device_feature_select = select;
    fence();
    return common.device_feature;
}

fn writeDriverFeature(device: pci.VirtioNetDevice, select: u32, value: u32) void {
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

const TransportInit = struct {
    rx_queue_notify_off: u16,
    tx_queue_notify_off: u16,
    link_up: u8,
};

fn initTransport(device: pci.VirtioNetDevice, device_features0: u32) InitError!TransportInit {
    const common = commonCfg(device);
    setStatus(common, 0);
    appendStatus(common, virtio_status_acknowledge);
    appendStatus(common, virtio_status_driver);

    const device_features1 = readDeviceFeature(device, virtio_f_version_1_word);
    if ((device_features1 & virtio_f_version_1_mask) == 0) return error.MissingVersion1;
    if ((device_features0 & virtio_net_f_mac) == 0) return error.MissingMacFeature;

    const requested_features0 = virtio_net_f_mac | (if ((device_features0 & virtio_net_f_status) != 0) virtio_net_f_status else 0);
    writeDriverFeature(device, 0, requested_features0);
    writeDriverFeature(device, virtio_f_version_1_word, virtio_f_version_1_mask);
    appendStatus(common, virtio_status_features_ok);
    if ((common.device_status & virtio_status_features_ok) == 0) return error.FeaturesRejected;

    const rx_queue_notify_off = try initQueue(device, queue_index_rx, &rx_desc, &rx_avail, &rx_used);
    const tx_queue_notify_off = try initQueue(device, queue_index_tx, &tx_desc, &tx_avail, &tx_used);
    configureRxDescriptors();
    configureTxDescriptors();
    appendStatus(common, virtio_status_driver_ok);

    const link_up: u8 = if ((requested_features0 & virtio_net_f_status) != 0 and
        (deviceCfg(device).status & virtio_net_s_link_up) == 0) 0 else 1;
    return .{
        .rx_queue_notify_off = rx_queue_notify_off,
        .tx_queue_notify_off = tx_queue_notify_off,
        .link_up = link_up,
    };
}

fn initQueue(device: pci.VirtioNetDevice, queue_index: u16, desc: *[queue_capacity]VirtqDesc, avail: *VirtqAvail, used: *VirtqUsed) InitError!u16 {
    const common = commonCfg(device);
    common.queue_select = queue_index;
    fence();
    const offered_size = common.queue_size;
    if (offered_size == 0) return error.QueueUnavailable;
    if (offered_size < queue_capacity) return error.QueueTooSmall;

    @memset(desc, std.mem.zeroes(VirtqDesc));
    avail.* = std.mem.zeroes(VirtqAvail);
    used.* = std.mem.zeroes(VirtqUsed);

    common.queue_size = queue_capacity;
    common.queue_desc = @intFromPtr(&desc[0]);
    common.queue_driver = @intFromPtr(avail);
    common.queue_device = @intFromPtr(used);
    common.queue_enable = 1;
    fence();
    if (common.queue_enable == 0) return error.QueueInitFailed;
    return common.queue_notify_off;
}

fn configureRxDescriptors() void {
    rx_posted_idx = 0;
    rx_last_used_idx = 0;
    var slot: usize = 0;
    while (slot < queue_slot_count) : (slot += 1) {
        const head = rxHeadIndexForSlot(slot);
        const data_index = head + 1;
        rx_headers[slot] = std.mem.zeroes(VirtioNetHdr);
        rx_desc[head] = .{
            .addr = @intFromPtr(&rx_headers[slot]),
            .len = @sizeOf(VirtioNetHdr),
            .flags = virtio_desc_flag_next | virtio_desc_flag_write,
            .next = data_index,
        };
        rx_desc[data_index] = .{
            .addr = @intFromPtr(&rx_buffers[slot]),
            .len = frame_buffer_capacity,
            .flags = virtio_desc_flag_write,
            .next = 0,
        };
        rx_avail.ring[slot] = head;
        rx_posted_idx +%= 1;
    }
    rx_avail.idx = rx_posted_idx;
    fence();
}

fn configureTxDescriptors() void {
    tx_avail_idx = 0;
    tx_last_used_idx = 0;
}

fn rearmRxSlot(device: pci.VirtioNetDevice, slot: usize) Error!void {
    if (slot >= queue_slot_count) return error.HardwareFault;
    const head = rxHeadIndexForSlot(slot);
    rx_headers[slot] = std.mem.zeroes(VirtioNetHdr);
    rx_avail.ring[rx_posted_idx % queue_capacity] = head;
    fence();
    rx_posted_idx +%= 1;
    rx_avail.idx = rx_posted_idx;
    fence();
    notifyQueue(device, active_rx_queue_notify_off, queue_index_rx);
}

fn waitForTxDrain() Error!void {
    var spin: usize = 0;
    while (spin < request_timeout_iterations) : (spin += 1) {
        if (tx_used.idx == tx_avail_idx) {
            tx_last_used_idx = tx_used.idx;
            return;
        }
        pause();
    }
    return error.Timeout;
}

fn rxHeadIndexForSlot(slot: usize) u16 {
    return @as(u16, @intCast(slot * 2));
}

fn txHeadIndexForSlot(slot: usize) u16 {
    return @as(u16, @intCast(slot * 2));
}

fn rxSlotForHead(head: u16) usize {
    return @as(usize, @intCast(head / 2));
}

fn queueMockReceive(frame: []const u8) void {
    const rx_len: usize = @min(frame.len, rx_snapshot_capacity);
    std.mem.copyForwards(u8, rx_snapshot[0..rx_len], frame[0..rx_len]);
    mock_pending_rx_len = @as(u32, @intCast(rx_len));
    mock_pending_rx_status = 1;
}

fn buildPatternFrame(frame: []u8, seed: u8, mac: [6]u8) void {
    const dest = frame[0..6];
    const src = frame[6..12];
    std.mem.copyForwards(u8, dest, mac[0..]);
    std.mem.copyForwards(u8, src, mac[0..]);
    frame[12] = 0x88;
    frame[13] = 0xB7;
    var index: usize = 14;
    while (index < frame.len) : (index += 1) {
        frame[index] = seed +% @as(u8, @truncate(index - 14));
    }
}

fn macIsZero(mac: [6]u8) bool {
    for (mac) |byte| {
        if (byte != 0) return false;
    }
    return true;
}

test "virtio net mock init and loopback send path exports stable state" {
    testEnableMockDevice();
    defer testDisableMockDevice();

    try initDetailed();
    const eth = statePtr();
    try std.testing.expectEqual(@as(u8, abi.ethernet_backend_virtio_net), eth.backend);
    try std.testing.expectEqual(@as(u8, 1), eth.initialized);
    try std.testing.expectEqual(@as(u8, 1), eth.tx_enabled);
    try std.testing.expectEqual(@as(u8, 1), eth.rx_enabled);
    try std.testing.expectEqual(@as(u8, 1), eth.link_up);
    try std.testing.expectEqual(default_mock_mac, eth.mac);

    _ = try sendPattern(64, 0x51);
    const rx_len = try pollReceive();
    try std.testing.expectEqual(@as(u32, 64), rx_len);
    try std.testing.expectEqual(@as(u32, 1), eth.tx_packets);
    try std.testing.expectEqual(@as(u32, 1), eth.rx_packets);
    try std.testing.expectEqual(@as(u8, 0x88), txByte(12));
    try std.testing.expectEqual(@as(u8, 0xB7), txByte(13));
    try std.testing.expectEqual(@as(u8, 0x88), rxByte(12));
    try std.testing.expectEqual(@as(u8, 0xB7), rxByte(13));
}

test "virtio net mock send hook sees transmitted frame" {
    testEnableMockDevice();
    defer testDisableMockDevice();

    var captured_len: usize = 0;
    var captured_first: u8 = 0;
    const Hook = struct {
        var len: *usize = undefined;
        var first: *u8 = undefined;
        fn capture(frame: []const u8) void {
            len.* = frame.len;
            first.* = frame[0];
        }
    };
    Hook.len = &captured_len;
    Hook.first = &captured_first;

    testInstallMockSendHook(Hook.capture);
    defer testInstallMockSendHook(null);

    try initDetailed();
    _ = try sendPattern(60, 0x61);
    try std.testing.expectEqual(@as(usize, 60), captured_len);
    try std.testing.expectEqual(default_mock_mac[0], captured_first);
}
