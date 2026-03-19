// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const abi = @import("abi.zig");

pub const max_edid_bytes: usize = 1024;
pub const max_output_entries: usize = 16;
pub const OutputEntry = abi.BaremetalDisplayOutputEntry;

pub const BgaUpdate = struct {
    vendor_id: u16 = 0,
    device_id: u16 = 0,
    pci_bus: u8 = 0,
    pci_device: u8 = 0,
    pci_function: u8 = 0,
    hardware_backed: bool = false,
    connected: bool = false,
    width: u16,
    height: u16,
};

pub const VirtioGpuUpdate = struct {
    vendor_id: u16,
    device_id: u16,
    pci_bus: u8,
    pci_device: u8,
    pci_function: u8,
    hardware_backed: bool,
    connected: bool,
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
    edid: []const u8,
    scanouts: []const VirtioGpuScanoutUpdate = &.{},
};

pub const VirtioGpuScanoutUpdate = struct {
    connected: bool,
    scanout_index: u8,
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

var state: abi.BaremetalDisplayOutputState = undefined;
var edid_bytes: [max_edid_bytes]u8 = [_]u8{0} ** max_edid_bytes;
pub export var oc_display_output_entry_count_data: u16 = 0;
pub export var oc_display_output_entries_data: [max_output_entries]OutputEntry = [_]OutputEntry{zeroOutputEntry()} ** max_output_entries;

fn zeroOutputEntry() OutputEntry {
    return .{
        .connected = 0,
        .scanout_index = 0,
        .connector_type = abi.display_connector_none,
        .edid_present = 0,
        .current_width = 0,
        .current_height = 0,
        .preferred_width = 0,
        .preferred_height = 0,
        .physical_width_mm = 0,
        .physical_height_mm = 0,
        .manufacturer_id = 0,
        .product_code = 0,
        .capability_flags = 0,
        .edid_length = 0,
        .serial_number = 0,
    };
}

fn clearOutputEntries() void {
    oc_display_output_entry_count_data = 0;
    for (&oc_display_output_entries_data) |*entry| {
        entry.* = zeroOutputEntry();
    }
}

fn initState() void {
    state = .{
        .magic = abi.display_output_magic,
        .api_version = abi.api_version,
        .backend = abi.display_backend_none,
        .controller = abi.display_controller_none,
        .connector_type = abi.display_connector_none,
        .hardware_backed = 0,
        .connected = 0,
        .edid_present = 0,
        .scanout_count = 0,
        .active_scanout = 0,
        .pci_bus = 0,
        .pci_device = 0,
        .pci_function = 0,
        .reserved0 = 0,
        .vendor_id = 0,
        .device_id = 0,
        .current_width = 0,
        .current_height = 0,
        .preferred_width = 0,
        .preferred_height = 0,
        .physical_width_mm = 0,
        .physical_height_mm = 0,
        .manufacturer_id = 0,
        .product_code = 0,
        .serial_number = 0,
        .edid_length = 0,
        .capability_flags = 0,
    };
    clearOutputEntries();
}

pub fn resetForTest() void {
    initState();
    @memset(&edid_bytes, 0);
}

pub fn statePtr() *const abi.BaremetalDisplayOutputState {
    return &state;
}

pub fn outputCount() u16 {
    return oc_display_output_entry_count_data;
}

pub fn outputEntry(index: u16) OutputEntry {
    const idx: usize = @intCast(index);
    if (idx >= oc_display_output_entry_count_data or idx >= oc_display_output_entries_data.len) return zeroOutputEntry();
    return oc_display_output_entries_data[idx];
}

fn applyEntryToState(entry: OutputEntry) void {
    state.connector_type = entry.connector_type;
    state.connected = entry.connected;
    state.edid_present = entry.edid_present;
    state.active_scanout = entry.scanout_index;
    state.current_width = entry.current_width;
    state.current_height = entry.current_height;
    state.preferred_width = entry.preferred_width;
    state.preferred_height = entry.preferred_height;
    state.physical_width_mm = entry.physical_width_mm;
    state.physical_height_mm = entry.physical_height_mm;
    state.manufacturer_id = entry.manufacturer_id;
    state.product_code = entry.product_code;
    state.serial_number = entry.serial_number;
    state.capability_flags = entry.capability_flags;
    state.edid_length = entry.edid_length;
}

fn applyModeToEntry(entry: *OutputEntry, width: u16, height: u16) void {
    entry.current_width = width;
    entry.current_height = height;
}

pub fn selectOutputConnector(connector_type: u8) bool {
    var index: usize = 0;
    while (index < oc_display_output_entry_count_data and index < oc_display_output_entries_data.len) : (index += 1) {
        const entry = oc_display_output_entries_data[index];
        if (entry.connected == 0 or entry.connector_type != connector_type) continue;
        applyEntryToState(entry);
        return true;
    }
    return false;
}

pub fn selectOutputIndex(index: u16) bool {
    const idx: usize = @intCast(index);
    if (idx >= oc_display_output_entry_count_data or idx >= oc_display_output_entries_data.len) return false;
    const entry = oc_display_output_entries_data[idx];
    if (entry.connected == 0) return false;
    applyEntryToState(entry);
    return true;
}

pub fn setOutputMode(index: u16, width: u16, height: u16) bool {
    const idx: usize = @intCast(index);
    if (idx >= oc_display_output_entry_count_data or idx >= oc_display_output_entries_data.len) return false;
    const entry = &oc_display_output_entries_data[idx];
    if (entry.connected == 0) return false;
    if (width == 0 or height == 0) return false;
    if (width > entry.current_width or height > entry.current_height) return false;
    applyModeToEntry(entry, width, height);
    applyEntryToState(entry.*);
    return true;
}

pub fn edidByte(index: u16) u8 {
    const idx: usize = @intCast(index);
    if (idx >= state.edid_length or idx >= edid_bytes.len) return 0;
    return edid_bytes[idx];
}

pub fn updateFromBga(update: BgaUpdate) void {
    initState();
    state.backend = abi.display_backend_bga;
    state.controller = abi.display_controller_bochs_bga;
    state.connector_type = abi.display_connector_virtual;
    state.hardware_backed = if (update.hardware_backed) 1 else 0;
    state.connected = if (update.connected) 1 else 0;
    state.scanout_count = 1;
    state.active_scanout = 0;
    state.pci_bus = update.pci_bus;
    state.pci_device = update.pci_device;
    state.pci_function = update.pci_function;
    state.vendor_id = update.vendor_id;
    state.device_id = update.device_id;
    state.current_width = update.width;
    state.current_height = update.height;
    state.preferred_width = update.width;
    state.preferred_height = update.height;
    oc_display_output_entry_count_data = 1;
    oc_display_output_entries_data[0] = .{
        .connected = if (update.connected) 1 else 0,
        .scanout_index = 0,
        .connector_type = abi.display_connector_virtual,
        .edid_present = 0,
        .current_width = update.width,
        .current_height = update.height,
        .preferred_width = update.width,
        .preferred_height = update.height,
        .physical_width_mm = 0,
        .physical_height_mm = 0,
        .manufacturer_id = 0,
        .product_code = 0,
        .capability_flags = 0,
        .edid_length = 0,
        .serial_number = 0,
    };
}

pub fn inferConnectorType(capability_flags: u16) u8 {
    if ((capability_flags & abi.display_capability_hdmi_vendor_data) != 0) {
        return abi.display_connector_hdmi;
    }
    if ((capability_flags & abi.display_capability_displayid_extension) != 0) {
        return abi.display_connector_displayport;
    }
    return abi.display_connector_virtual;
}

pub fn updateFromVirtioGpu(update: VirtioGpuUpdate) void {
    initState();
    state.backend = abi.display_backend_virtio_gpu;
    state.controller = abi.display_controller_virtio_gpu;
    state.connector_type = inferConnectorType(update.capability_flags);
    state.hardware_backed = if (update.hardware_backed) 1 else 0;
    state.connected = if (update.connected) 1 else 0;
    state.edid_present = if (update.edid.len > 0) 1 else 0;
    state.scanout_count = update.scanout_count;
    state.active_scanout = update.active_scanout;
    state.pci_bus = update.pci_bus;
    state.pci_device = update.pci_device;
    state.pci_function = update.pci_function;
    state.vendor_id = update.vendor_id;
    state.device_id = update.device_id;
    state.current_width = update.current_width;
    state.current_height = update.current_height;
    state.preferred_width = update.preferred_width;
    state.preferred_height = update.preferred_height;
    state.physical_width_mm = update.physical_width_mm;
    state.physical_height_mm = update.physical_height_mm;
    state.manufacturer_id = update.manufacturer_id;
    state.product_code = update.product_code;
    state.serial_number = update.serial_number;
    state.capability_flags = update.capability_flags;

    const edid_len = @min(update.edid.len, edid_bytes.len);
    @memset(&edid_bytes, 0);
    if (edid_len > 0) {
        std.mem.copyForwards(u8, edid_bytes[0..edid_len], update.edid[0..edid_len]);
    }
    state.edid_length = @intCast(edid_len);

    const scanout_len = @min(update.scanouts.len, oc_display_output_entries_data.len);
    if (scanout_len == 0) {
        oc_display_output_entry_count_data = 1;
        oc_display_output_entries_data[0] = .{
            .connected = if (update.connected) 1 else 0,
            .scanout_index = update.active_scanout,
            .connector_type = state.connector_type,
            .edid_present = state.edid_present,
            .current_width = update.current_width,
            .current_height = update.current_height,
            .preferred_width = update.preferred_width,
            .preferred_height = update.preferred_height,
            .physical_width_mm = update.physical_width_mm,
            .physical_height_mm = update.physical_height_mm,
            .manufacturer_id = update.manufacturer_id,
            .product_code = update.product_code,
            .capability_flags = update.capability_flags,
            .edid_length = @intCast(edid_len),
            .serial_number = update.serial_number,
        };
        return;
    }

    oc_display_output_entry_count_data = @intCast(scanout_len);
    for (update.scanouts[0..scanout_len], 0..) |scanout, index| {
        oc_display_output_entries_data[index] = .{
            .connected = if (scanout.connected) 1 else 0,
            .scanout_index = scanout.scanout_index,
            .connector_type = if (scanout.connected) inferConnectorType(scanout.capability_flags) else abi.display_connector_none,
            .edid_present = if (scanout.edid_length > 0) 1 else 0,
            .current_width = scanout.current_width,
            .current_height = scanout.current_height,
            .preferred_width = scanout.preferred_width,
            .preferred_height = scanout.preferred_height,
            .physical_width_mm = scanout.physical_width_mm,
            .physical_height_mm = scanout.physical_height_mm,
            .manufacturer_id = scanout.manufacturer_id,
            .product_code = scanout.product_code,
            .capability_flags = scanout.capability_flags,
            .edid_length = scanout.edid_length,
            .serial_number = scanout.serial_number,
        };
    }
}

test "display output state updates from bga metadata" {
    resetForTest();
    updateFromBga(.{
        .vendor_id = 0x1234,
        .device_id = 0x1111,
        .pci_bus = 0,
        .pci_device = 1,
        .pci_function = 0,
        .hardware_backed = true,
        .connected = true,
        .width = 1280,
        .height = 720,
    });
    const output = statePtr();
    try std.testing.expectEqual(@as(u32, abi.display_output_magic), output.magic);
    try std.testing.expectEqual(@as(u8, abi.display_backend_bga), output.backend);
    try std.testing.expectEqual(@as(u8, abi.display_controller_bochs_bga), output.controller);
    try std.testing.expectEqual(@as(u8, abi.display_connector_virtual), output.connector_type);
    try std.testing.expectEqual(@as(u8, 1), output.connected);
    try std.testing.expectEqual(@as(u16, 1280), output.current_width);
    try std.testing.expectEqual(@as(u16, 720), output.current_height);
    try std.testing.expectEqual(@as(u16, 1), outputCount());
    const entry = outputEntry(0);
    try std.testing.expectEqual(@as(u8, 1), entry.connected);
    try std.testing.expectEqual(@as(u8, abi.display_connector_virtual), entry.connector_type);
    try std.testing.expectEqual(@as(u16, 1280), entry.current_width);
}

test "display output state copies virtio gpu edid payload" {
    resetForTest();
    const edid = [_]u8{ 0x00, 0xFF, 0xFF, 0xFF };
    updateFromVirtioGpu(.{
        .vendor_id = 0x1AF4,
        .device_id = 0x1050,
        .pci_bus = 0,
        .pci_device = 2,
        .pci_function = 0,
        .hardware_backed = true,
        .connected = true,
        .scanout_count = 1,
        .active_scanout = 0,
        .current_width = 1280,
        .current_height = 800,
        .preferred_width = 1280,
        .preferred_height = 800,
        .physical_width_mm = 300,
        .physical_height_mm = 190,
        .manufacturer_id = 0x1234,
        .product_code = 0x5678,
        .serial_number = 0xCAFEBABE,
        .capability_flags = abi.display_capability_digital_input | abi.display_capability_preferred_timing,
        .edid = &edid,
        .scanouts = &.{
            .{
                .connected = true,
                .scanout_index = 0,
                .current_width = 1280,
                .current_height = 800,
                .preferred_width = 1280,
                .preferred_height = 800,
                .physical_width_mm = 300,
                .physical_height_mm = 190,
                .manufacturer_id = 0x1234,
                .product_code = 0x5678,
                .serial_number = 0xCAFEBABE,
                .capability_flags = abi.display_capability_digital_input | abi.display_capability_preferred_timing,
                .edid_length = edid.len,
            },
        },
    });
    const output = statePtr();
    try std.testing.expectEqual(@as(u8, abi.display_backend_virtio_gpu), output.backend);
    try std.testing.expectEqual(@as(u8, abi.display_controller_virtio_gpu), output.controller);
    try std.testing.expectEqual(@as(u8, abi.display_connector_virtual), output.connector_type);
    try std.testing.expectEqual(@as(u16, 4), output.edid_length);
    try std.testing.expectEqual(@as(u16, abi.display_capability_digital_input | abi.display_capability_preferred_timing), output.capability_flags);
    try std.testing.expectEqual(@as(u8, 0xFF), edidByte(1));
    try std.testing.expectEqual(@as(u16, 1), outputCount());
    const entry = outputEntry(0);
    try std.testing.expectEqual(@as(u8, 0), entry.scanout_index);
    try std.testing.expectEqual(@as(u8, abi.display_connector_virtual), entry.connector_type);
    try std.testing.expectEqual(@as(u16, 1280), entry.current_width);
}

test "display output infers connector type from edid capability flags" {
    try std.testing.expectEqual(@as(u8, abi.display_connector_hdmi), inferConnectorType(abi.display_capability_hdmi_vendor_data));
    try std.testing.expectEqual(@as(u8, abi.display_connector_displayport), inferConnectorType(abi.display_capability_displayid_extension));
    try std.testing.expectEqual(@as(u8, abi.display_connector_virtual), inferConnectorType(abi.display_capability_digital_input));
}

test "display output state stores multiple virtio scanout entries" {
    resetForTest();
    updateFromVirtioGpu(.{
        .vendor_id = 0x1AF4,
        .device_id = 0x1050,
        .pci_bus = 0,
        .pci_device = 2,
        .pci_function = 0,
        .hardware_backed = true,
        .connected = true,
        .scanout_count = 2,
        .active_scanout = 1,
        .current_width = 1920,
        .current_height = 1080,
        .preferred_width = 1920,
        .preferred_height = 1080,
        .physical_width_mm = 520,
        .physical_height_mm = 320,
        .manufacturer_id = 0x1111,
        .product_code = 0x2222,
        .serial_number = 0x33334444,
        .capability_flags = abi.display_capability_displayid_extension | abi.display_capability_preferred_timing,
        .edid = &.{ 0x00, 0xFF, 0xFF, 0xFF },
        .scanouts = &.{
            .{
                .connected = false,
                .scanout_index = 0,
                .current_width = 0,
                .current_height = 0,
                .preferred_width = 0,
                .preferred_height = 0,
                .physical_width_mm = 0,
                .physical_height_mm = 0,
                .manufacturer_id = 0,
                .product_code = 0,
                .serial_number = 0,
                .capability_flags = 0,
                .edid_length = 0,
            },
            .{
                .connected = true,
                .scanout_index = 1,
                .current_width = 1920,
                .current_height = 1080,
                .preferred_width = 1920,
                .preferred_height = 1080,
                .physical_width_mm = 520,
                .physical_height_mm = 320,
                .manufacturer_id = 0x1111,
                .product_code = 0x2222,
                .serial_number = 0x33334444,
                .capability_flags = abi.display_capability_displayid_extension | abi.display_capability_preferred_timing,
                .edid_length = 256,
            },
        },
    });

    try std.testing.expectEqual(@as(u16, 2), outputCount());
    const disconnected = outputEntry(0);
    try std.testing.expectEqual(@as(u8, 0), disconnected.connected);
    try std.testing.expectEqual(@as(u8, abi.display_connector_none), disconnected.connector_type);
    const connected = outputEntry(1);
    try std.testing.expectEqual(@as(u8, 1), connected.connected);
    try std.testing.expectEqual(@as(u8, 1), connected.scanout_index);
    try std.testing.expectEqual(@as(u8, abi.display_connector_displayport), connected.connector_type);
    try std.testing.expectEqual(@as(u16, 1920), connected.current_width);
}

test "display output can retarget active connector from stored entries" {
    resetForTest();
    updateFromVirtioGpu(.{
        .vendor_id = 0x1AF4,
        .device_id = 0x1050,
        .pci_bus = 0,
        .pci_device = 2,
        .pci_function = 0,
        .hardware_backed = true,
        .connected = true,
        .scanout_count = 2,
        .active_scanout = 0,
        .current_width = 1280,
        .current_height = 720,
        .preferred_width = 1280,
        .preferred_height = 720,
        .physical_width_mm = 300,
        .physical_height_mm = 190,
        .manufacturer_id = 0x1111,
        .product_code = 0x2222,
        .serial_number = 0x33334444,
        .capability_flags = abi.display_capability_hdmi_vendor_data | abi.display_capability_preferred_timing,
        .edid = &.{ 0x00, 0xFF, 0xFF, 0xFF },
        .scanouts = &.{
            .{
                .connected = true,
                .scanout_index = 0,
                .current_width = 1280,
                .current_height = 720,
                .preferred_width = 1280,
                .preferred_height = 720,
                .physical_width_mm = 300,
                .physical_height_mm = 190,
                .manufacturer_id = 0x1111,
                .product_code = 0x2222,
                .serial_number = 0x33334444,
                .capability_flags = abi.display_capability_hdmi_vendor_data | abi.display_capability_preferred_timing,
                .edid_length = 128,
            },
            .{
                .connected = true,
                .scanout_index = 1,
                .current_width = 1920,
                .current_height = 1080,
                .preferred_width = 1920,
                .preferred_height = 1080,
                .physical_width_mm = 520,
                .physical_height_mm = 320,
                .manufacturer_id = 0xAAAA,
                .product_code = 0xBBBB,
                .serial_number = 0xCCCCDDDD,
                .capability_flags = abi.display_capability_displayid_extension | abi.display_capability_preferred_timing,
                .edid_length = 128,
            },
        },
    });

    try std.testing.expect(selectOutputConnector(abi.display_connector_displayport));
    const output = statePtr();
    try std.testing.expectEqual(@as(u8, abi.display_connector_displayport), output.connector_type);
    try std.testing.expectEqual(@as(u8, 1), output.active_scanout);
    try std.testing.expectEqual(@as(u16, 1920), output.current_width);
    try std.testing.expectEqual(@as(u16, 1080), output.current_height);
    try std.testing.expect(!selectOutputConnector(abi.display_connector_embedded_displayport));
}

test "display output can retarget active output index from stored entries" {
    resetForTest();
    updateFromVirtioGpu(.{
        .vendor_id = 0x1AF4,
        .device_id = 0x1050,
        .pci_bus = 0,
        .pci_device = 2,
        .pci_function = 0,
        .hardware_backed = true,
        .connected = true,
        .scanout_count = 2,
        .active_scanout = 0,
        .current_width = 1280,
        .current_height = 720,
        .preferred_width = 1280,
        .preferred_height = 720,
        .physical_width_mm = 300,
        .physical_height_mm = 190,
        .manufacturer_id = 0x1111,
        .product_code = 0x2222,
        .serial_number = 0x33334444,
        .capability_flags = abi.display_capability_hdmi_vendor_data | abi.display_capability_preferred_timing,
        .edid = &.{ 0x00, 0xFF, 0xFF, 0xFF },
        .scanouts = &.{
            .{
                .connected = true,
                .scanout_index = 0,
                .current_width = 1280,
                .current_height = 720,
                .preferred_width = 1280,
                .preferred_height = 720,
                .physical_width_mm = 300,
                .physical_height_mm = 190,
                .manufacturer_id = 0x1111,
                .product_code = 0x2222,
                .serial_number = 0x33334444,
                .capability_flags = abi.display_capability_hdmi_vendor_data | abi.display_capability_preferred_timing,
                .edid_length = 128,
            },
            .{
                .connected = true,
                .scanout_index = 1,
                .current_width = 1920,
                .current_height = 1080,
                .preferred_width = 1920,
                .preferred_height = 1080,
                .physical_width_mm = 520,
                .physical_height_mm = 320,
                .manufacturer_id = 0xAAAA,
                .product_code = 0xBBBB,
                .serial_number = 0xCCCCDDDD,
                .capability_flags = abi.display_capability_displayid_extension | abi.display_capability_preferred_timing,
                .edid_length = 128,
            },
        },
    });

    try std.testing.expect(selectOutputIndex(1));
    const output = statePtr();
    try std.testing.expectEqual(@as(u8, abi.display_connector_displayport), output.connector_type);
    try std.testing.expectEqual(@as(u8, 1), output.active_scanout);
    try std.testing.expectEqual(@as(u16, 1920), output.current_width);
    try std.testing.expectEqual(@as(u16, 1080), output.current_height);
    try std.testing.expect(!selectOutputIndex(2));
}

test "display output can retarget active output mode from stored entries" {
    resetForTest();
    updateFromVirtioGpu(.{
        .vendor_id = 0x1AF4,
        .device_id = 0x1050,
        .pci_bus = 0,
        .pci_device = 2,
        .pci_function = 0,
        .hardware_backed = true,
        .connected = true,
        .scanout_count = 2,
        .active_scanout = 0,
        .current_width = 1280,
        .current_height = 720,
        .preferred_width = 1280,
        .preferred_height = 720,
        .physical_width_mm = 300,
        .physical_height_mm = 190,
        .manufacturer_id = 0x1111,
        .product_code = 0x2222,
        .serial_number = 0x33334444,
        .capability_flags = abi.display_capability_hdmi_vendor_data | abi.display_capability_preferred_timing,
        .edid = &.{ 0x00, 0xFF, 0xFF, 0xFF },
        .scanouts = &.{
            .{
                .connected = true,
                .scanout_index = 0,
                .current_width = 1280,
                .current_height = 720,
                .preferred_width = 1280,
                .preferred_height = 720,
                .physical_width_mm = 300,
                .physical_height_mm = 190,
                .manufacturer_id = 0x1111,
                .product_code = 0x2222,
                .serial_number = 0x33334444,
                .capability_flags = abi.display_capability_hdmi_vendor_data | abi.display_capability_preferred_timing,
                .edid_length = 128,
            },
            .{
                .connected = true,
                .scanout_index = 1,
                .current_width = 1920,
                .current_height = 1080,
                .preferred_width = 1920,
                .preferred_height = 1080,
                .physical_width_mm = 520,
                .physical_height_mm = 320,
                .manufacturer_id = 0xAAAA,
                .product_code = 0xBBBB,
                .serial_number = 0xCCCCDDDD,
                .capability_flags = abi.display_capability_displayid_extension | abi.display_capability_preferred_timing,
                .edid_length = 128,
            },
        },
    });

    try std.testing.expect(setOutputMode(1, 1024, 768));
    const output = statePtr();
    try std.testing.expectEqual(@as(u8, abi.display_connector_displayport), output.connector_type);
    try std.testing.expectEqual(@as(u8, 1), output.active_scanout);
    try std.testing.expectEqual(@as(u16, 1024), output.current_width);
    try std.testing.expectEqual(@as(u16, 768), output.current_height);
    try std.testing.expectEqual(@as(u16, 1920), output.preferred_width);
    try std.testing.expectEqual(@as(u16, 1080), output.preferred_height);
    try std.testing.expectEqual(@as(u16, 1024), outputEntry(1).current_width);
    try std.testing.expectEqual(@as(u16, 768), outputEntry(1).current_height);
    try std.testing.expect(!setOutputMode(1, 2560, 1440));
    try std.testing.expect(!setOutputMode(2, 800, 600));
}
