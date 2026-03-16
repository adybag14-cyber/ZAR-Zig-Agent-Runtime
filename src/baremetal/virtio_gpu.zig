// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const builtin = @import("builtin");
const pci = @import("pci.zig");
const edid = @import("edid.zig");
const display_output = @import("display_output.zig");

const virtio_f_version_1_word: u32 = 1;
const virtio_f_version_1_mask: u32 = 1 << 0;
const virtio_gpu_f_edid: u32 = 1 << 1;

const virtio_status_acknowledge: u8 = 1;
const virtio_status_driver: u8 = 2;
const virtio_status_driver_ok: u8 = 4;
const virtio_status_features_ok: u8 = 8;
const virtio_status_failed: u8 = 128;

const virtio_desc_flag_next: u16 = 1;
const virtio_desc_flag_write: u16 = 2;
const queue_capacity: u16 = 8;
const max_scanouts: usize = 16;
const ctrl_queue_index: u16 = 0;
const request_timeout_iterations: usize = 2_000_000;
const max_present_width: usize = 1280;
const max_present_height: usize = 1024;
const present_pixel_count: usize = max_present_width * max_present_height;
const resource_id_scanout: u32 = 1;
const format_b8g8r8x8_unorm: u32 = 2;

const cmd_get_display_info: u32 = 0x0100;
const cmd_resource_create_2d: u32 = 0x0101;
const cmd_resource_unref: u32 = 0x0102;
const cmd_set_scanout: u32 = 0x0103;
const cmd_resource_flush: u32 = 0x0104;
const cmd_transfer_to_host_2d: u32 = 0x0105;
const cmd_resource_attach_backing: u32 = 0x0106;
const cmd_resource_detach_backing: u32 = 0x0107;
const cmd_get_edid: u32 = 0x010A;
const resp_ok_nodata: u32 = 0x1100;
const resp_ok_display_info: u32 = 0x1101;
const resp_ok_edid: u32 = 0x1104;

pub const ProbeError = error{
    UnsupportedPlatform,
    DeviceNotFound,
    MissingCapabilities,
    MissingVersion1,
    MissingEdidFeature,
    FeaturesRejected,
    QueueUnavailable,
    QueueTooSmall,
    RequestTimedOut,
    InvalidDisplayInfoResponse,
    InvalidEdidResponse,
    NoConnectedScanout,
    InvalidEdid,
    InvalidControlResponse,
    FramebufferTooLarge,
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

const VirtioGpuConfig = extern struct {
    events_read: u32,
    events_clear: u32,
    num_scanouts: u32,
    num_capsets: u32,
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

const CtrlHdr = extern struct {
    type: u32,
    flags: u32,
    fence_id: u64,
    ctx_id: u32,
    ring_idx: u8,
    padding: [3]u8,
};

const Rect = extern struct {
    x: u32,
    y: u32,
    width: u32,
    height: u32,
};

const DisplayOne = extern struct {
    rect: Rect,
    enabled: u32,
    flags: u32,
};

const RespDisplayInfo = extern struct {
    hdr: CtrlHdr,
    pmodes: [max_scanouts]DisplayOne,
};

const CmdGetEdid = extern struct {
    hdr: CtrlHdr,
    scanout: u32,
    padding: u32,
};

const CmdResourceCreate2d = extern struct {
    hdr: CtrlHdr,
    resource_id: u32,
    format: u32,
    width: u32,
    height: u32,
};

const CmdResourceUnref = extern struct {
    hdr: CtrlHdr,
    resource_id: u32,
    padding: u32,
};

const CmdSetScanout = extern struct {
    hdr: CtrlHdr,
    rect: Rect,
    scanout_id: u32,
    resource_id: u32,
};

const CmdTransferToHost2d = extern struct {
    hdr: CtrlHdr,
    rect: Rect,
    offset: u64,
    resource_id: u32,
    padding: u32,
};

const CmdResourceFlush = extern struct {
    hdr: CtrlHdr,
    rect: Rect,
    resource_id: u32,
    padding: u32,
};

const MemEntry = extern struct {
    addr: u64,
    length: u32,
    padding: u32,
};

const CmdResourceAttachBackingOne = extern struct {
    hdr: CtrlHdr,
    resource_id: u32,
    nr_entries: u32,
    entry: MemEntry,
};

const RespEdid = extern struct {
    hdr: CtrlHdr,
    size: u32,
    padding: u32,
    edid: [display_output.max_edid_bytes]u8,
};

pub const ProbeResult = struct {
    vendor_id: u16,
    device_id: u16,
    pci_bus: u8,
    pci_device: u8,
    pci_function: u8,
    scanout_count: u8,
    active_scanout: u8,
    current_width: u16,
    current_height: u16,
    preferred_width: u16,
    preferred_height: u16,
    physical_width_mm: u16,
    physical_height_mm: u16,
    manufacturer_id: u16,
    product_code: u16,
    serial_number: u32,
    capability_flags: u16,
    edid_length: u16,
};

pub const PresentStats = struct {
    resource_create_count: u32 = 0,
    resource_unref_count: u32 = 0,
    attach_backing_count: u32 = 0,
    scanout_set_count: u32 = 0,
    transfer_count: u32 = 0,
    flush_count: u32 = 0,
    width: u16 = 0,
    height: u16 = 0,
};

var ctrl_desc: [queue_capacity]VirtqDesc align(4096) = undefined;
var ctrl_avail: VirtqAvail align(4096) = undefined;
var ctrl_used: VirtqUsed align(4096) = undefined;
var ctrl_request: CmdGetEdid align(16) = undefined;
var ctrl_request_create2d: CmdResourceCreate2d align(16) = undefined;
var ctrl_request_unref: CmdResourceUnref align(16) = undefined;
var ctrl_request_set_scanout: CmdSetScanout align(16) = undefined;
var ctrl_request_transfer: CmdTransferToHost2d align(16) = undefined;
var ctrl_request_flush: CmdResourceFlush align(16) = undefined;
var ctrl_request_attach_backing: CmdResourceAttachBackingOne align(16) = undefined;
var ctrl_response_edid: RespEdid align(16) = undefined;
var ctrl_response_display: RespDisplayInfo align(16) = undefined;
var ctrl_response_nodata: CtrlHdr align(16) = undefined;
var scanout_pixels: [present_pixel_count]u32 align(4096) = [_]u32{0} ** present_pixel_count;
var last_present_stats: PresentStats = .{};
var last_avail_idx: u16 = 0;
var last_used_idx: u16 = 0;

fn hardwareBacked() bool {
    return builtin.os.tag == .freestanding and builtin.cpu.arch == .x86_64;
}

fn commonCfg(device: pci.VirtioGpuDevice) *volatile VirtioPciCommonCfg {
    return @as(*volatile VirtioPciCommonCfg, @ptrFromInt(@as(usize, @intCast(device.common_cfg.address))));
}

fn deviceCfg(device: pci.VirtioGpuDevice) *volatile VirtioGpuConfig {
    return @as(*volatile VirtioGpuConfig, @ptrFromInt(@as(usize, @intCast(device.device_cfg.address))));
}

fn notifyAddress(device: pci.VirtioGpuDevice, queue_notify_off: u16) u64 {
    return device.notify_cfg.address + (@as(u64, queue_notify_off) * @as(u64, device.notify_off_multiplier));
}

fn notifyQueue(device: pci.VirtioGpuDevice, queue_notify_off: u16) void {
    const notify_ptr = @as(*volatile u16, @ptrFromInt(@as(usize, @intCast(notifyAddress(device, queue_notify_off)))));
    notify_ptr.* = ctrl_queue_index;
}

fn fence() void {
    asm volatile ("" ::: "memory");
}

fn pause() void {
    asm volatile ("pause" ::: "memory");
}

fn readDeviceFeature(device: pci.VirtioGpuDevice, select: u32) u32 {
    const common = commonCfg(device);
    common.device_feature_select = select;
    fence();
    return common.device_feature;
}

fn writeDriverFeature(device: pci.VirtioGpuDevice, select: u32, value: u32) void {
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

fn initQueue(device: pci.VirtioGpuDevice) ProbeError!u16 {
    const common = commonCfg(device);
    common.queue_select = ctrl_queue_index;
    fence();
    const offered_size = common.queue_size;
    if (offered_size == 0) return error.QueueUnavailable;
    if (offered_size < 2) return error.QueueTooSmall;

    const queue_size: u16 = @min(offered_size, queue_capacity);
    @memset(&ctrl_desc, std.mem.zeroes(VirtqDesc));
    ctrl_avail = std.mem.zeroes(VirtqAvail);
    ctrl_used = std.mem.zeroes(VirtqUsed);
    last_avail_idx = 0;
    last_used_idx = 0;

    common.queue_size = queue_size;
    common.queue_desc = @intFromPtr(&ctrl_desc[0]);
    common.queue_driver = @intFromPtr(&ctrl_avail);
    common.queue_device = @intFromPtr(&ctrl_used);
    common.queue_enable = 1;
    fence();
    return common.queue_notify_off;
}

fn submitDescriptors(device: pci.VirtioGpuDevice, queue_notify_off: u16, request_addr: u64, request_len: usize, response_addr: u64, response_len: usize) ProbeError!void {
    ctrl_desc[0] = .{
        .addr = request_addr,
        .len = @intCast(request_len),
        .flags = virtio_desc_flag_next,
        .next = 1,
    };
    ctrl_desc[1] = .{
        .addr = response_addr,
        .len = @intCast(response_len),
        .flags = virtio_desc_flag_write,
        .next = 0,
    };

    ctrl_avail.ring[last_avail_idx % queue_capacity] = 0;
    fence();
    last_avail_idx +%= 1;
    ctrl_avail.idx = last_avail_idx;
    fence();
    notifyQueue(device, queue_notify_off);

    var spin: usize = 0;
    while (spin < request_timeout_iterations) : (spin += 1) {
        if (ctrl_used.idx != last_used_idx) {
            last_used_idx = ctrl_used.idx;
            return;
        }
        pause();
    }
    return error.RequestTimedOut;
}

fn initTransport(device: pci.VirtioGpuDevice) ProbeError!u16 {
    const common = commonCfg(device);
    setStatus(common, 0);
    appendStatus(common, virtio_status_acknowledge);
    appendStatus(common, virtio_status_driver);

    const device_features0 = readDeviceFeature(device, 0);
    const device_features1 = readDeviceFeature(device, 1);
    if ((device_features1 & virtio_f_version_1_mask) == 0) return error.MissingVersion1;
    if ((device_features0 & virtio_gpu_f_edid) == 0) return error.MissingEdidFeature;

    writeDriverFeature(device, 0, virtio_gpu_f_edid);
    writeDriverFeature(device, 1, virtio_f_version_1_mask);
    appendStatus(common, virtio_status_features_ok);
    if ((common.device_status & virtio_status_features_ok) == 0) return error.FeaturesRejected;

    const queue_notify_off = try initQueue(device);
    appendStatus(common, virtio_status_driver_ok);
    return queue_notify_off;
}

fn sendGetDisplayInfo(device: pci.VirtioGpuDevice, queue_notify_off: u16) ProbeError!RespDisplayInfo {
    ctrl_request = .{
        .hdr = .{
            .type = cmd_get_display_info,
            .flags = 0,
            .fence_id = 0,
            .ctx_id = 0,
            .ring_idx = 0,
            .padding = .{ 0, 0, 0 },
        },
        .scanout = 0,
        .padding = 0,
    };
    ctrl_response_display = std.mem.zeroes(RespDisplayInfo);
    try submitDescriptors(device, queue_notify_off, @intFromPtr(&ctrl_request), @sizeOf(CtrlHdr), @intFromPtr(&ctrl_response_display), @sizeOf(RespDisplayInfo));
    if (ctrl_response_display.hdr.type != resp_ok_display_info) return error.InvalidDisplayInfoResponse;
    return ctrl_response_display;
}

fn sendGetEdid(device: pci.VirtioGpuDevice, queue_notify_off: u16, scanout: u32) ProbeError!RespEdid {
    ctrl_request = .{
        .hdr = .{
            .type = cmd_get_edid,
            .flags = 0,
            .fence_id = 0,
            .ctx_id = 0,
            .ring_idx = 0,
            .padding = .{ 0, 0, 0 },
        },
        .scanout = scanout,
        .padding = 0,
    };
    ctrl_response_edid = std.mem.zeroes(RespEdid);
    try submitDescriptors(device, queue_notify_off, @intFromPtr(&ctrl_request), @sizeOf(CmdGetEdid), @intFromPtr(&ctrl_response_edid), @sizeOf(RespEdid));
    if (ctrl_response_edid.hdr.type != resp_ok_edid) return error.InvalidEdidResponse;
    return ctrl_response_edid;
}

fn sendControlNoData(device: pci.VirtioGpuDevice, queue_notify_off: u16, request_addr: u64, request_len: usize) ProbeError!void {
    ctrl_response_nodata = std.mem.zeroes(CtrlHdr);
    try submitDescriptors(device, queue_notify_off, request_addr, request_len, @intFromPtr(&ctrl_response_nodata), @sizeOf(CtrlHdr));
    if (ctrl_response_nodata.type != resp_ok_nodata) return error.InvalidControlResponse;
}

fn sendResourceCreate2d(device: pci.VirtioGpuDevice, queue_notify_off: u16, width: u16, height: u16) ProbeError!void {
    ctrl_request_create2d = .{
        .hdr = .{
            .type = cmd_resource_create_2d,
            .flags = 0,
            .fence_id = 0,
            .ctx_id = 0,
            .ring_idx = 0,
            .padding = .{ 0, 0, 0 },
        },
        .resource_id = resource_id_scanout,
        .format = format_b8g8r8x8_unorm,
        .width = width,
        .height = height,
    };
    try sendControlNoData(device, queue_notify_off, @intFromPtr(&ctrl_request_create2d), @sizeOf(CmdResourceCreate2d));
    last_present_stats.resource_create_count +%= 1;
}

fn sendResourceUnref(device: pci.VirtioGpuDevice, queue_notify_off: u16) ProbeError!void {
    ctrl_request_unref = .{
        .hdr = .{
            .type = cmd_resource_unref,
            .flags = 0,
            .fence_id = 0,
            .ctx_id = 0,
            .ring_idx = 0,
            .padding = .{ 0, 0, 0 },
        },
        .resource_id = resource_id_scanout,
        .padding = 0,
    };
    try sendControlNoData(device, queue_notify_off, @intFromPtr(&ctrl_request_unref), @sizeOf(CmdResourceUnref));
    last_present_stats.resource_unref_count +%= 1;
}

fn sendResourceAttachBacking(device: pci.VirtioGpuDevice, queue_notify_off: u16, width: u16, height: u16) ProbeError!void {
    ctrl_request_attach_backing = .{
        .hdr = .{
            .type = cmd_resource_attach_backing,
            .flags = 0,
            .fence_id = 0,
            .ctx_id = 0,
            .ring_idx = 0,
            .padding = .{ 0, 0, 0 },
        },
        .resource_id = resource_id_scanout,
        .nr_entries = 1,
        .entry = .{
            .addr = @intFromPtr(&scanout_pixels[0]),
            .length = @intCast(@as(usize, width) * @as(usize, height) * @sizeOf(u32)),
            .padding = 0,
        },
    };
    try sendControlNoData(device, queue_notify_off, @intFromPtr(&ctrl_request_attach_backing), @sizeOf(CmdResourceAttachBackingOne));
    last_present_stats.attach_backing_count +%= 1;
}

fn sendSetScanout(device: pci.VirtioGpuDevice, queue_notify_off: u16, scanout_id: u8, width: u16, height: u16) ProbeError!void {
    ctrl_request_set_scanout = .{
        .hdr = .{
            .type = cmd_set_scanout,
            .flags = 0,
            .fence_id = 0,
            .ctx_id = 0,
            .ring_idx = 0,
            .padding = .{ 0, 0, 0 },
        },
        .rect = .{
            .x = 0,
            .y = 0,
            .width = width,
            .height = height,
        },
        .scanout_id = scanout_id,
        .resource_id = resource_id_scanout,
    };
    try sendControlNoData(device, queue_notify_off, @intFromPtr(&ctrl_request_set_scanout), @sizeOf(CmdSetScanout));
    last_present_stats.scanout_set_count +%= 1;
}

fn sendTransferToHost2d(device: pci.VirtioGpuDevice, queue_notify_off: u16, width: u16, height: u16) ProbeError!void {
    ctrl_request_transfer = .{
        .hdr = .{
            .type = cmd_transfer_to_host_2d,
            .flags = 0,
            .fence_id = 0,
            .ctx_id = 0,
            .ring_idx = 0,
            .padding = .{ 0, 0, 0 },
        },
        .rect = .{
            .x = 0,
            .y = 0,
            .width = width,
            .height = height,
        },
        .offset = 0,
        .resource_id = resource_id_scanout,
        .padding = 0,
    };
    try sendControlNoData(device, queue_notify_off, @intFromPtr(&ctrl_request_transfer), @sizeOf(CmdTransferToHost2d));
    last_present_stats.transfer_count +%= 1;
}

fn sendResourceFlush(device: pci.VirtioGpuDevice, queue_notify_off: u16, width: u16, height: u16) ProbeError!void {
    ctrl_request_flush = .{
        .hdr = .{
            .type = cmd_resource_flush,
            .flags = 0,
            .fence_id = 0,
            .ctx_id = 0,
            .ring_idx = 0,
            .padding = .{ 0, 0, 0 },
        },
        .rect = .{
            .x = 0,
            .y = 0,
            .width = width,
            .height = height,
        },
        .resource_id = resource_id_scanout,
        .padding = 0,
    };
    try sendControlNoData(device, queue_notify_off, @intFromPtr(&ctrl_request_flush), @sizeOf(CmdResourceFlush));
    last_present_stats.flush_count +%= 1;
}

fn fillProbePattern(width: u16, height: u16) void {
    const active_width: usize = width;
    const active_height: usize = height;
    @memset(&scanout_pixels, 0);

    var y: usize = 0;
    while (y < @min(active_height, 24)) : (y += 1) {
        var x: usize = 0;
        while (x < @min(active_width, 96)) : (x += 1) {
            scanout_pixels[(y * max_present_width) + x] = if ((x + y) % 2 == 0) 0x0000FF00 else 0x00FFFFFF;
        }
    }

    var diag: usize = 0;
    while (diag < @min(active_width, active_height) and diag < 64) : (diag += 1) {
        scanout_pixels[(diag * max_present_width) + diag] = 0x00FF0000;
    }

    last_present_stats.width = width;
    last_present_stats.height = height;
}

pub fn lastPresentStats() PresentStats {
    return last_present_stats;
}

pub fn scanoutPixel(x: u16, y: u16) u32 {
    if (x >= max_present_width or y >= max_present_height) return 0;
    return scanout_pixels[(@as(usize, y) * max_present_width) + @as(usize, x)];
}

fn selectConnectedScanout(response: RespDisplayInfo, scanout_limit: u32) ?struct { index: u8, width: u16, height: u16 } {
    var idx: usize = 0;
    while (idx < @min(@as(usize, scanout_limit), max_scanouts)) : (idx += 1) {
        const mode = response.pmodes[idx];
        if (mode.enabled == 0) continue;
        return .{
            .index = @intCast(idx),
            .width = @intCast(@min(mode.rect.width, std.math.maxInt(u16))),
            .height = @intCast(@min(mode.rect.height, std.math.maxInt(u16))),
        };
    }
    return null;
}

pub fn probeDisplay() ProbeError!ProbeResult {
    if (!hardwareBacked()) return error.UnsupportedPlatform;
    const device = pci.discoverVirtioGpuDevice() orelse return error.DeviceNotFound;
    const queue_notify_off = try initTransport(device);
    const scanout_limit = @min(deviceCfg(device).num_scanouts, @as(u32, max_scanouts));
    const display_info = try sendGetDisplayInfo(device, queue_notify_off);
    const active = selectConnectedScanout(display_info, scanout_limit) orelse return error.NoConnectedScanout;
    const edid_response = try sendGetEdid(device, queue_notify_off, active.index);
    const edid_size = @min(edid_response.size, @as(u32, display_output.max_edid_bytes));
    if (edid_size < edid.block_len) return error.InvalidEdidResponse;

    const parsed = edid.parse(edid_response.edid[0..edid_size]) catch return error.InvalidEdid;
    return .{
        .vendor_id = device.vendor_id,
        .device_id = device.device_id,
        .pci_bus = device.location.bus,
        .pci_device = device.location.device,
        .pci_function = device.location.function,
        .scanout_count = @intCast(scanout_limit),
        .active_scanout = active.index,
        .current_width = active.width,
        .current_height = active.height,
        .preferred_width = if (parsed.preferred_timing) |timing| timing.h_active else active.width,
        .preferred_height = if (parsed.preferred_timing) |timing| timing.v_active else active.height,
        .physical_width_mm = parsed.physical_width_mm,
        .physical_height_mm = parsed.physical_height_mm,
        .manufacturer_id = parsed.manufacturer_id,
        .product_code = parsed.product_code,
        .serial_number = parsed.serial_number,
        .capability_flags = parsed.capability_flags,
        .edid_length = @intCast(edid_size),
    };
}

pub fn probeAndPublish() ProbeError!ProbeResult {
    const result = try probeDisplay();
    const device = pci.discoverVirtioGpuDevice() orelse return error.DeviceNotFound;
    const queue_notify_off = try initTransport(device);
    const edid_response = try sendGetEdid(device, queue_notify_off, result.active_scanout);
    const edid_len = @min(@as(usize, @intCast(edid_response.size)), display_output.max_edid_bytes);
    display_output.updateFromVirtioGpu(.{
        .vendor_id = result.vendor_id,
        .device_id = result.device_id,
        .pci_bus = result.pci_bus,
        .pci_device = result.pci_device,
        .pci_function = result.pci_function,
        .hardware_backed = true,
        .connected = true,
        .scanout_count = result.scanout_count,
        .active_scanout = result.active_scanout,
        .current_width = result.current_width,
        .current_height = result.current_height,
        .preferred_width = result.preferred_width,
        .preferred_height = result.preferred_height,
        .physical_width_mm = result.physical_width_mm,
        .physical_height_mm = result.physical_height_mm,
        .manufacturer_id = result.manufacturer_id,
        .product_code = result.product_code,
        .serial_number = result.serial_number,
        .capability_flags = result.capability_flags,
        .edid = edid_response.edid[0..edid_len],
    });
    return result;
}

pub fn probeAndPresentPattern() ProbeError!ProbeResult {
    if (!hardwareBacked()) return error.UnsupportedPlatform;
    last_present_stats = .{};
    @memset(&scanout_pixels, 0);

    const device = pci.discoverVirtioGpuDevice() orelse return error.DeviceNotFound;
    const queue_notify_off = try initTransport(device);
    const scanout_limit = @min(deviceCfg(device).num_scanouts, @as(u32, max_scanouts));
    const display_info = try sendGetDisplayInfo(device, queue_notify_off);
    const active = selectConnectedScanout(display_info, scanout_limit) orelse return error.NoConnectedScanout;
    if (active.width > max_present_width or active.height > max_present_height) return error.FramebufferTooLarge;

    const edid_response = try sendGetEdid(device, queue_notify_off, active.index);
    const edid_size = @min(edid_response.size, @as(u32, display_output.max_edid_bytes));
    if (edid_size < edid.block_len) return error.InvalidEdidResponse;

    const parsed = edid.parse(edid_response.edid[0..edid_size]) catch return error.InvalidEdid;
    fillProbePattern(active.width, active.height);
    try sendResourceCreate2d(device, queue_notify_off, active.width, active.height);
    errdefer sendResourceUnref(device, queue_notify_off) catch {};
    try sendResourceAttachBacking(device, queue_notify_off, active.width, active.height);
    try sendSetScanout(device, queue_notify_off, active.index, active.width, active.height);
    try sendTransferToHost2d(device, queue_notify_off, active.width, active.height);
    try sendResourceFlush(device, queue_notify_off, active.width, active.height);

    const result: ProbeResult = .{
        .vendor_id = device.vendor_id,
        .device_id = device.device_id,
        .pci_bus = device.location.bus,
        .pci_device = device.location.device,
        .pci_function = device.location.function,
        .scanout_count = @intCast(scanout_limit),
        .active_scanout = active.index,
        .current_width = active.width,
        .current_height = active.height,
        .preferred_width = if (parsed.preferred_timing) |timing| timing.h_active else active.width,
        .preferred_height = if (parsed.preferred_timing) |timing| timing.v_active else active.height,
        .physical_width_mm = parsed.physical_width_mm,
        .physical_height_mm = parsed.physical_height_mm,
        .manufacturer_id = parsed.manufacturer_id,
        .product_code = parsed.product_code,
        .serial_number = parsed.serial_number,
        .capability_flags = parsed.capability_flags,
        .edid_length = @intCast(edid_size),
    };
    display_output.updateFromVirtioGpu(.{
        .vendor_id = result.vendor_id,
        .device_id = result.device_id,
        .pci_bus = result.pci_bus,
        .pci_device = result.pci_device,
        .pci_function = result.pci_function,
        .hardware_backed = true,
        .connected = true,
        .scanout_count = result.scanout_count,
        .active_scanout = result.active_scanout,
        .current_width = result.current_width,
        .current_height = result.current_height,
        .preferred_width = result.preferred_width,
        .preferred_height = result.preferred_height,
        .physical_width_mm = result.physical_width_mm,
        .physical_height_mm = result.physical_height_mm,
        .manufacturer_id = result.manufacturer_id,
        .product_code = result.product_code,
        .serial_number = result.serial_number,
        .capability_flags = result.capability_flags,
        .edid = edid_response.edid[0..edid_size],
    });
    return result;
}

test "virtio gpu scanout selector chooses first enabled output" {
    var response = std.mem.zeroes(RespDisplayInfo);
    response.pmodes[0].enabled = 0;
    response.pmodes[1].enabled = 1;
    response.pmodes[1].rect.width = 1280;
    response.pmodes[1].rect.height = 720;

    const selected = selectConnectedScanout(response, 2) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u8, 1), selected.index);
    try std.testing.expectEqual(@as(u16, 1280), selected.width);
    try std.testing.expectEqual(@as(u16, 720), selected.height);
}

test "virtio gpu probe pattern paints scanout pixels" {
    last_present_stats = .{};
    fillProbePattern(128, 64);
    try std.testing.expectEqual(@as(u16, 128), last_present_stats.width);
    try std.testing.expectEqual(@as(u16, 64), last_present_stats.height);
    try std.testing.expect(scanoutPixel(0, 0) != 0);
    try std.testing.expect(scanoutPixel(8, 8) != 0);
}
