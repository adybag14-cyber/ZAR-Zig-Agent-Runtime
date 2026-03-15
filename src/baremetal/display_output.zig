const std = @import("std");
const abi = @import("abi.zig");

pub const max_edid_bytes: usize = 1024;

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
    edid: []const u8,
};

var state: abi.BaremetalDisplayOutputState = undefined;
var edid_bytes: [max_edid_bytes]u8 = [_]u8{0} ** max_edid_bytes;

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
        .reserved1 = 0,
    };
}

pub fn resetForTest() void {
    initState();
    @memset(&edid_bytes, 0);
}

pub fn statePtr() *const abi.BaremetalDisplayOutputState {
    return &state;
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
}

pub fn updateFromVirtioGpu(update: VirtioGpuUpdate) void {
    initState();
    state.backend = abi.display_backend_virtio_gpu;
    state.controller = abi.display_controller_virtio_gpu;
    state.connector_type = abi.display_connector_virtual;
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

    const edid_len = @min(update.edid.len, edid_bytes.len);
    @memset(&edid_bytes, 0);
    if (edid_len > 0) {
        std.mem.copyForwards(u8, edid_bytes[0..edid_len], update.edid[0..edid_len]);
    }
    state.edid_length = @intCast(edid_len);
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
        .edid = &edid,
    });
    const output = statePtr();
    try std.testing.expectEqual(@as(u8, abi.display_backend_virtio_gpu), output.backend);
    try std.testing.expectEqual(@as(u8, abi.display_controller_virtio_gpu), output.controller);
    try std.testing.expectEqual(@as(u16, 4), output.edid_length);
    try std.testing.expectEqual(@as(u8, 0xFF), edidByte(1));
}
