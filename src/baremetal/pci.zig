// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const builtin = @import("builtin");

const config_address_port: u16 = 0xCF8;
const config_data_port: u16 = 0xCFC;
const max_bus_count: usize = 256;
const max_device_count: usize = 32;
const max_function_count: usize = 8;
const pci_capability_id_vendor_specific: u8 = 0x09;
const virtio_vendor_id: u16 = 0x1AF4;
const virtio_block_device_id: u16 = 0x1042;
const virtio_gpu_device_id: u16 = 0x1050;
const virtio_pci_cap_common_cfg: u8 = 1;
const virtio_pci_cap_notify_cfg: u8 = 2;
const virtio_pci_cap_isr_cfg: u8 = 3;
const virtio_pci_cap_device_cfg: u8 = 4;

pub const DeviceLocation = struct {
    bus: u8,
    device: u8,
    function: u8,
};

pub const Rtl8139Device = struct {
    location: DeviceLocation,
    io_base: u16,
    irq_line: u8,
};

pub const E1000Device = struct {
    location: DeviceLocation,
    mmio_base: u64,
    io_base: u16,
    irq_line: u8,
    device_id: u16,
};

pub const DisplayDevice = struct {
    location: DeviceLocation,
    framebuffer_bar: u64,
    vendor_id: u16,
    device_id: u16,
    class_code: u8,
    subclass: u8,
};

pub const MmioRegion = struct {
    bar: u8,
    address: u64,
    offset: u32,
    length: u32,
};

pub const VirtioGpuDevice = struct {
    location: DeviceLocation,
    vendor_id: u16,
    device_id: u16,
    common_cfg: MmioRegion,
    notify_cfg: MmioRegion,
    notify_off_multiplier: u32,
    isr_cfg: MmioRegion,
    device_cfg: MmioRegion,
};

pub const VirtioBlockDevice = struct {
    location: DeviceLocation,
    vendor_id: u16,
    device_id: u16,
    common_cfg: MmioRegion,
    notify_cfg: MmioRegion,
    notify_off_multiplier: u32,
    isr_cfg: MmioRegion,
    device_cfg: MmioRegion,
};

const MockEntry = struct {
    bus: u8,
    device: u8,
    function: u8,
    regs: [64]u32 = [_]u32{0xFFFF_FFFF} ** 64,
};

const mock_entry_capacity: usize = 16;
var mock_entries: [mock_entry_capacity]MockEntry = undefined;
var mock_entry_count: usize = 0;
var mock_enabled: bool = false;

fn hardwareBacked() bool {
    return builtin.os.tag == .freestanding and builtin.cpu.arch == .x86_64;
}

fn readPort32(port: u16) u32 {
    if (!hardwareBacked() and !(builtin.is_test and mock_enabled)) return 0xFFFF_FFFF;
    return asm volatile ("inl %[dx], %[eax]"
        : [eax] "={eax}" (-> u32),
        : [dx] "{dx}" (port),
        : .{ .memory = true });
}

fn writePort32(port: u16, value: u32) void {
    if (!hardwareBacked() and !(builtin.is_test and mock_enabled)) return;
    asm volatile ("outl %[eax], %[dx]"
        :
        : [dx] "{dx}" (port),
          [eax] "{eax}" (value),
        : .{ .memory = true });
}

fn configAddress(bus: u8, device: u8, function: u8, offset: u8) u32 {
    return 0x8000_0000 |
        (@as(u32, bus) << 16) |
        (@as(u32, device) << 11) |
        (@as(u32, function) << 8) |
        @as(u32, offset & 0xFC);
}

fn mockEntry(bus: u8, device: u8, function: u8) ?*MockEntry {
    if (!builtin.is_test or !mock_enabled) return null;
    var index: usize = 0;
    while (index < mock_entry_count) : (index += 1) {
        const entry = &mock_entries[index];
        if (entry.bus == bus and entry.device == device and entry.function == function) {
            return entry;
        }
    }
    return null;
}

fn ensureMockEntry(bus: u8, device: u8, function: u8) *MockEntry {
    if (mockEntry(bus, device, function)) |entry| return entry;
    std.debug.assert(mock_entry_count < mock_entry_capacity);
    const entry = &mock_entries[mock_entry_count];
    mock_entry_count += 1;
    entry.* = .{
        .bus = bus,
        .device = device,
        .function = function,
    };
    return entry;
}

fn readConfig32(bus: u8, device: u8, function: u8, offset: u8) u32 {
    if (builtin.is_test and mock_enabled) {
        if (mockEntry(bus, device, function)) |entry| {
            return entry.regs[offset / 4];
        }
        return 0xFFFF_FFFF;
    }
    if (!hardwareBacked()) return 0xFFFF_FFFF;
    writePort32(config_address_port, configAddress(bus, device, function, offset));
    return readPort32(config_data_port);
}

fn writeConfig32(bus: u8, device: u8, function: u8, offset: u8, value: u32) void {
    if (builtin.is_test and mock_enabled) {
        const entry = ensureMockEntry(bus, device, function);
        entry.regs[offset / 4] = value;
        return;
    }
    if (!hardwareBacked()) return;
    writePort32(config_address_port, configAddress(bus, device, function, offset));
    writePort32(config_data_port, value);
}

fn readConfig16(bus: u8, device: u8, function: u8, offset: u8) u16 {
    const value = readConfig32(bus, device, function, offset);
    const shift: u5 = @intCast((offset & 0x2) * 8);
    return @as(u16, @truncate(value >> shift));
}

fn readConfig8(bus: u8, device: u8, function: u8, offset: u8) u8 {
    const value = readConfig32(bus, device, function, offset);
    const shift: u5 = @intCast((offset & 0x3) * 8);
    return @as(u8, @truncate(value >> shift));
}

fn writeConfig16(bus: u8, device: u8, function: u8, offset: u8, value: u16) void {
    const aligned = offset & 0xFC;
    const current = readConfig32(bus, device, function, aligned);
    const shift: u5 = @intCast((offset & 0x2) * 8);
    const mask = ~(@as(u32, 0xFFFF) << shift);
    const updated = (current & mask) | (@as(u32, value) << shift);
    writeConfig32(bus, device, function, aligned, updated);
}

fn vendorId(bus: u8, device: u8, function: u8) u16 {
    return @as(u16, @truncate(readConfig32(bus, device, function, 0x00)));
}

fn deviceId(bus: u8, device: u8, function: u8) u16 {
    return @as(u16, @truncate(readConfig32(bus, device, function, 0x00) >> 16));
}

fn classCode(bus: u8, device: u8, function: u8) u8 {
    return @as(u8, @truncate(readConfig32(bus, device, function, 0x08) >> 24));
}

fn subclass(bus: u8, device: u8, function: u8) u8 {
    return @as(u8, @truncate(readConfig32(bus, device, function, 0x08) >> 16));
}

fn headerType(bus: u8, device: u8, function: u8) u8 {
    return @as(u8, @truncate(readConfig32(bus, device, function, 0x0C) >> 16));
}

fn firstFramebufferMemoryBar(bus: u8, device: u8, function: u8) ?u64 {
    var bar_index: u8 = 0;
    while (bar_index < 6) : (bar_index += 1) {
        const offset: u8 = 0x10 + (bar_index * 4);
        const low = readConfig32(bus, device, function, offset);
        if (low == 0 or low == 0xFFFF_FFFF) continue;
        if ((low & 0x1) != 0) continue;

        const mem_type = (low >> 1) & 0x3;
        if (mem_type == 0x2 and bar_index + 1 < 6) {
            const high = readConfig32(bus, device, function, offset + 4);
            const addr = (@as(u64, high) << 32) | @as(u64, low & 0xFFFF_FFF0);
            if (addr != 0) return addr;
            bar_index += 1;
            continue;
        }

        const addr = @as(u64, low & 0xFFFF_FFF0);
        if (addr != 0) return addr;
    }
    return null;
}

fn memoryBarAtIndex(bus: u8, device: u8, function: u8, bar_index: u8) ?u64 {
    if (bar_index >= 6) return null;
    const offset: u8 = 0x10 + (bar_index * 4);
    const low = readConfig32(bus, device, function, offset);
    if (low == 0 or low == 0xFFFF_FFFF or (low & 0x1) != 0) return null;

    const mem_type = (low >> 1) & 0x3;
    if (mem_type == 0x2) {
        if (bar_index + 1 >= 6) return null;
        const high = readConfig32(bus, device, function, offset + 4);
        const addr = (@as(u64, high) << 32) | @as(u64, low & 0xFFFF_FFF0);
        return if (addr == 0) null else addr;
    }

    const addr = @as(u64, low & 0xFFFF_FFF0);
    return if (addr == 0) null else addr;
}

fn capabilityRegion(location: DeviceLocation, cap_ptr: u8) ?MmioRegion {
    const bar = readConfig8(location.bus, location.device, location.function, cap_ptr + 4);
    const offset = readConfig32(location.bus, location.device, location.function, cap_ptr + 8);
    const length = readConfig32(location.bus, location.device, location.function, cap_ptr + 12);
    const bar_addr = memoryBarAtIndex(location.bus, location.device, location.function, bar) orelse return null;
    return .{
        .bar = bar,
        .address = bar_addr + offset,
        .offset = offset,
        .length = length,
    };
}

fn enableMemoryAndIoDecode(location: DeviceLocation) void {
    const command = readConfig16(location.bus, location.device, location.function, 0x04);
    const wanted = command | 0x3;
    if (wanted != command) {
        writeConfig16(location.bus, location.device, location.function, 0x04, wanted);
    }
}

fn enableIoAndBusMaster(location: DeviceLocation) void {
    const command = readConfig16(location.bus, location.device, location.function, 0x04);
    const wanted = command | 0x5;
    if (wanted != command) {
        writeConfig16(location.bus, location.device, location.function, 0x04, wanted);
    }
}

fn enableMemoryAndBusMaster(location: DeviceLocation) void {
    const command = readConfig16(location.bus, location.device, location.function, 0x04);
    const wanted = command | 0x6;
    if (wanted != command) {
        writeConfig16(location.bus, location.device, location.function, 0x04, wanted);
    }
}

fn firstIoBar(bus: u8, device: u8, function: u8) ?u16 {
    var bar_index: u8 = 0;
    while (bar_index < 6) : (bar_index += 1) {
        const offset: u8 = 0x10 + (bar_index * 4);
        const value = readConfig32(bus, device, function, offset);
        if (value == 0 or value == 0xFFFF_FFFF) continue;
        if ((value & 0x1) == 0) continue;
        const addr = value & 0xFFFF_FFFC;
        if (addr != 0 and addr <= 0xFFFF) {
            return @as(u16, @intCast(addr));
        }
    }
    return null;
}

pub fn discoverDisplayDevice() ?DisplayDevice {
    if (!hardwareBacked() and !(builtin.is_test and mock_enabled)) return null;

    var preferred: ?DisplayDevice = null;
    var fallback: ?DisplayDevice = null;

    var bus: usize = 0;
    while (bus < max_bus_count) : (bus += 1) {
        var device: usize = 0;
        while (device < max_device_count) : (device += 1) {
            const bus_id: u8 = @intCast(bus);
            const device_id0: u8 = @intCast(device);
            const first_vendor = vendorId(bus_id, device_id0, 0);
            if (first_vendor == 0xFFFF) continue;

            const function_limit: usize = if ((headerType(bus_id, device_id0, 0) & 0x80) != 0) max_function_count else 1;
            var function: usize = 0;
            while (function < function_limit) : (function += 1) {
                const function_id: u8 = @intCast(function);
                const vendor = vendorId(bus_id, device_id0, function_id);
                if (vendor == 0xFFFF) continue;
                if (classCode(bus_id, device_id0, function_id) != 0x03) continue;

                const location: DeviceLocation = .{
                    .bus = bus_id,
                    .device = device_id0,
                    .function = function_id,
                };
                enableMemoryAndIoDecode(location);

                const bar = firstFramebufferMemoryBar(bus_id, device_id0, function_id) orelse continue;
                const device_word = deviceId(bus_id, device_id0, function_id);
                const sub = subclass(bus_id, device_id0, function_id);
                const display: DisplayDevice = .{
                    .location = location,
                    .framebuffer_bar = bar,
                    .vendor_id = vendor,
                    .device_id = device_word,
                    .class_code = classCode(bus_id, device_id0, function_id),
                    .subclass = sub,
                };

                if (vendor == 0x1234 and (device_word == 0x1111 or device_word == 0x1110)) {
                    return display;
                }
                if (preferred == null and sub == 0x00) preferred = display;
                if (fallback == null) fallback = display;
            }
        }
    }

    return preferred orelse fallback;
}

pub fn discoverDisplayFramebufferBar() ?u64 {
    const display = discoverDisplayDevice() orelse return null;
    return display.framebuffer_bar;
}

pub fn discoverVirtioGpuDevice() ?VirtioGpuDevice {
    if (!hardwareBacked() and !(builtin.is_test and mock_enabled)) return null;

    var bus: usize = 0;
    while (bus < max_bus_count) : (bus += 1) {
        var device: usize = 0;
        while (device < max_device_count) : (device += 1) {
            const bus_id: u8 = @intCast(bus);
            const device_id0: u8 = @intCast(device);
            const first_vendor = vendorId(bus_id, device_id0, 0);
            if (first_vendor == 0xFFFF) continue;

            const function_limit: usize = if ((headerType(bus_id, device_id0, 0) & 0x80) != 0) max_function_count else 1;
            var function: usize = 0;
            while (function < function_limit) : (function += 1) {
                const function_id: u8 = @intCast(function);
                const vendor = vendorId(bus_id, device_id0, function_id);
                if (vendor != virtio_vendor_id or deviceId(bus_id, device_id0, function_id) != virtio_gpu_device_id) continue;

                const location: DeviceLocation = .{
                    .bus = bus_id,
                    .device = device_id0,
                    .function = function_id,
                };
                enableMemoryAndIoDecode(location);

                var common_cfg: ?MmioRegion = null;
                var notify_cfg: ?MmioRegion = null;
                var notify_off_multiplier: u32 = 0;
                var isr_cfg: ?MmioRegion = null;
                var device_cfg: ?MmioRegion = null;

                var capability_ptr = readConfig8(bus_id, device_id0, function_id, 0x34);
                var visited: usize = 0;
                while (capability_ptr >= 0x40 and capability_ptr != 0 and visited < 64) : (visited += 1) {
                    const cap_id = readConfig8(bus_id, device_id0, function_id, capability_ptr);
                    const next_ptr = readConfig8(bus_id, device_id0, function_id, capability_ptr + 1);
                    if (cap_id == pci_capability_id_vendor_specific) {
                        const cfg_type = readConfig8(bus_id, device_id0, function_id, capability_ptr + 3);
                        const region = capabilityRegion(location, capability_ptr);
                        switch (cfg_type) {
                            virtio_pci_cap_common_cfg => common_cfg = region,
                            virtio_pci_cap_notify_cfg => {
                                notify_cfg = region;
                                notify_off_multiplier = readConfig32(bus_id, device_id0, function_id, capability_ptr + 16);
                            },
                            virtio_pci_cap_isr_cfg => isr_cfg = region,
                            virtio_pci_cap_device_cfg => device_cfg = region,
                            else => {},
                        }
                    }
                    capability_ptr = next_ptr;
                }

                if (common_cfg != null and notify_cfg != null and isr_cfg != null and device_cfg != null) {
                    return .{
                        .location = location,
                        .vendor_id = vendor,
                        .device_id = virtio_gpu_device_id,
                        .common_cfg = common_cfg.?,
                        .notify_cfg = notify_cfg.?,
                        .notify_off_multiplier = notify_off_multiplier,
                        .isr_cfg = isr_cfg.?,
                        .device_cfg = device_cfg.?,
                    };
                }
            }
        }
    }

    return null;
}

pub fn discoverVirtioBlockDevice() ?VirtioBlockDevice {
    if (!hardwareBacked() and !(builtin.is_test and mock_enabled)) return null;

    var bus: usize = 0;
    while (bus < max_bus_count) : (bus += 1) {
        var device: usize = 0;
        while (device < max_device_count) : (device += 1) {
            const bus_id: u8 = @intCast(bus);
            const device_id0: u8 = @intCast(device);
            const first_vendor = vendorId(bus_id, device_id0, 0);
            if (first_vendor == 0xFFFF) continue;

            const function_limit: usize = if ((headerType(bus_id, device_id0, 0) & 0x80) != 0) max_function_count else 1;
            var function: usize = 0;
            while (function < function_limit) : (function += 1) {
                const function_id: u8 = @intCast(function);
                const vendor = vendorId(bus_id, device_id0, function_id);
                if (vendor != virtio_vendor_id or deviceId(bus_id, device_id0, function_id) != virtio_block_device_id) continue;

                const location: DeviceLocation = .{
                    .bus = bus_id,
                    .device = device_id0,
                    .function = function_id,
                };
                enableMemoryAndIoDecode(location);

                var common_cfg: ?MmioRegion = null;
                var notify_cfg: ?MmioRegion = null;
                var notify_off_multiplier: u32 = 0;
                var isr_cfg: ?MmioRegion = null;
                var device_cfg: ?MmioRegion = null;

                var capability_ptr = readConfig8(bus_id, device_id0, function_id, 0x34);
                var visited: usize = 0;
                while (capability_ptr >= 0x40 and capability_ptr != 0 and visited < 64) : (visited += 1) {
                    const cap_id = readConfig8(bus_id, device_id0, function_id, capability_ptr);
                    const next_ptr = readConfig8(bus_id, device_id0, function_id, capability_ptr + 1);
                    if (cap_id == pci_capability_id_vendor_specific) {
                        const cfg_type = readConfig8(bus_id, device_id0, function_id, capability_ptr + 3);
                        const region = capabilityRegion(location, capability_ptr);
                        switch (cfg_type) {
                            virtio_pci_cap_common_cfg => common_cfg = region,
                            virtio_pci_cap_notify_cfg => {
                                notify_cfg = region;
                                notify_off_multiplier = readConfig32(bus_id, device_id0, function_id, capability_ptr + 16);
                            },
                            virtio_pci_cap_isr_cfg => isr_cfg = region,
                            virtio_pci_cap_device_cfg => device_cfg = region,
                            else => {},
                        }
                    }
                    capability_ptr = next_ptr;
                }

                if (common_cfg != null and notify_cfg != null and isr_cfg != null and device_cfg != null) {
                    return .{
                        .location = location,
                        .vendor_id = vendor,
                        .device_id = virtio_block_device_id,
                        .common_cfg = common_cfg.?,
                        .notify_cfg = notify_cfg.?,
                        .notify_off_multiplier = notify_off_multiplier,
                        .isr_cfg = isr_cfg.?,
                        .device_cfg = device_cfg.?,
                    };
                }
            }
        }
    }

    return null;
}

pub fn discoverRtl8139() ?Rtl8139Device {
    if (!hardwareBacked() and !(builtin.is_test and mock_enabled)) return null;

    var bus: usize = 0;
    while (bus < max_bus_count) : (bus += 1) {
        var device: usize = 0;
        while (device < max_device_count) : (device += 1) {
            const bus_id: u8 = @intCast(bus);
            const device_id0: u8 = @intCast(device);
            const first_vendor = vendorId(bus_id, device_id0, 0);
            if (first_vendor == 0xFFFF) continue;

            const function_limit: usize = if ((headerType(bus_id, device_id0, 0) & 0x80) != 0) max_function_count else 1;
            var function: usize = 0;
            while (function < function_limit) : (function += 1) {
                const function_id: u8 = @intCast(function);
                const vendor = vendorId(bus_id, device_id0, function_id);
                if (vendor == 0xFFFF) continue;
                if (vendor != 0x10EC or deviceId(bus_id, device_id0, function_id) != 0x8139) continue;
                const io_base = firstIoBar(bus_id, device_id0, function_id) orelse continue;
                return .{
                    .location = .{
                        .bus = bus_id,
                        .device = device_id0,
                        .function = function_id,
                    },
                    .io_base = io_base,
                    .irq_line = readConfig8(bus_id, device_id0, function_id, 0x3C),
                };
            }
        }
    }

    return null;
}

pub fn enableRtl8139IoAndBusMaster(location: DeviceLocation) void {
    enableIoAndBusMaster(location);
}

pub fn discoverE1000() ?E1000Device {
    if (!hardwareBacked() and !(builtin.is_test and mock_enabled)) return null;

    var bus: usize = 0;
    while (bus < max_bus_count) : (bus += 1) {
        var device: usize = 0;
        while (device < max_device_count) : (device += 1) {
            const bus_id: u8 = @intCast(bus);
            const device_id0: u8 = @intCast(device);
            const first_vendor = vendorId(bus_id, device_id0, 0);
            if (first_vendor == 0xFFFF) continue;

            const function_limit: usize = if ((headerType(bus_id, device_id0, 0) & 0x80) != 0) max_function_count else 1;
            var function: usize = 0;
            while (function < function_limit) : (function += 1) {
                const function_id: u8 = @intCast(function);
                const vendor = vendorId(bus_id, device_id0, function_id);
                if (vendor == 0xFFFF) continue;

                const device_word = deviceId(bus_id, device_id0, function_id);
                if (vendor != 0x8086 or device_word != 0x100E) continue;

                const mmio_base = memoryBarAtIndex(bus_id, device_id0, function_id, 0) orelse continue;
                const io_base = firstIoBar(bus_id, device_id0, function_id) orelse continue;
                return .{
                    .location = .{
                        .bus = bus_id,
                        .device = device_id0,
                        .function = function_id,
                    },
                    .mmio_base = mmio_base,
                    .io_base = io_base,
                    .irq_line = readConfig8(bus_id, device_id0, function_id, 0x3C),
                    .device_id = device_word,
                };
            }
        }
    }

    return null;
}

pub fn enableE1000MemoryAndBusMaster(location: DeviceLocation) void {
    const command = readConfig16(location.bus, location.device, location.function, 0x04);
    const wanted = command | 0x7;
    if (wanted != command) {
        writeConfig16(location.bus, location.device, location.function, 0x04, wanted);
    }
}

pub fn enableVirtioBlockMemoryAndBusMaster(location: DeviceLocation) void {
    const command = readConfig16(location.bus, location.device, location.function, 0x04);
    const wanted = command | 0x7;
    if (wanted != command) {
        writeConfig16(location.bus, location.device, location.function, 0x04, wanted);
    }
}

pub fn testResetForTest() void {
    if (!builtin.is_test) return;
    mock_enabled = false;
    mock_entry_count = 0;
}

pub fn testSetConfig32(bus: u8, device: u8, function: u8, offset: u8, value: u32) void {
    if (!builtin.is_test) return;
    mock_enabled = true;
    const entry = ensureMockEntry(bus, device, function);
    entry.regs[offset / 4] = value;
}

test "pci display scan finds bochs-style framebuffer bar and enables decode" {
    testResetForTest();
    defer testResetForTest();

    testSetConfig32(0, 1, 0, 0x00, 0x1111_1234);
    testSetConfig32(0, 1, 0, 0x04, 0x0000_0000);
    testSetConfig32(0, 1, 0, 0x08, 0x0300_0000);
    testSetConfig32(0, 1, 0, 0x0C, 0x0000_0000);
    testSetConfig32(0, 1, 0, 0x10, 0xFD00_0000);

    const display = discoverDisplayDevice() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u64, 0xFD00_0000), display.framebuffer_bar);
    try std.testing.expectEqual(@as(u16, 0x1234), display.vendor_id);
    try std.testing.expectEqual(@as(u16, 0x1111), display.device_id);
    try std.testing.expectEqual(@as(u8, 0), display.location.bus);
    try std.testing.expectEqual(@as(u8, 1), display.location.device);
    try std.testing.expectEqual(@as(u8, 0), display.location.function);
    try std.testing.expectEqual(@as(u16, 0x3), readConfig16(0, 1, 0, 0x04) & 0x3);
}

test "pci rtl8139 scan finds io bar and interrupt line and enables bus master" {
    testResetForTest();
    defer testResetForTest();

    testSetConfig32(0, 3, 0, 0x00, 0x8139_10EC);
    testSetConfig32(0, 3, 0, 0x04, 0x0000_0000);
    testSetConfig32(0, 3, 0, 0x0C, 0x0000_0000);
    testSetConfig32(0, 3, 0, 0x10, 0x0000_C101);
    testSetConfig32(0, 3, 0, 0x3C, 0x0000_000B);

    const nic = discoverRtl8139() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u8, 0), nic.location.bus);
    try std.testing.expectEqual(@as(u8, 3), nic.location.device);
    try std.testing.expectEqual(@as(u16, 0xC100), nic.io_base);
    try std.testing.expectEqual(@as(u8, 0x0B), nic.irq_line);

    enableRtl8139IoAndBusMaster(nic.location);
    try std.testing.expectEqual(@as(u16, 0x5), readConfig16(0, 3, 0, 0x04) & 0x5);
}

test "pci e1000 scan finds mmio and io bars and enables bus master" {
    testResetForTest();
    defer testResetForTest();

    testSetConfig32(0, 4, 0, 0x00, 0x100E_8086);
    testSetConfig32(0, 4, 0, 0x04, 0x0000_0000);
    testSetConfig32(0, 4, 0, 0x0C, 0x0000_0000);
    testSetConfig32(0, 4, 0, 0x10, 0xFEBC_0000);
    testSetConfig32(0, 4, 0, 0x14, 0x0000_C001);
    testSetConfig32(0, 4, 0, 0x3C, 0x0000_000B);

    const nic = discoverE1000() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u8, 0), nic.location.bus);
    try std.testing.expectEqual(@as(u8, 4), nic.location.device);
    try std.testing.expectEqual(@as(u64, 0xFEBC_0000), nic.mmio_base);
    try std.testing.expectEqual(@as(u16, 0xC000), nic.io_base);
    try std.testing.expectEqual(@as(u8, 0x0B), nic.irq_line);
    try std.testing.expectEqual(@as(u16, 0x100E), nic.device_id);

    enableE1000MemoryAndBusMaster(nic.location);
    try std.testing.expectEqual(@as(u16, 0x7), readConfig16(0, 4, 0, 0x04) & 0x7);
}

test "pci virtio gpu scan finds modern capability regions" {
    testResetForTest();
    defer testResetForTest();

    testSetConfig32(0, 2, 0, 0x00, 0x1050_1AF4);
    testSetConfig32(0, 2, 0, 0x04, 0x0000_0010);
    testSetConfig32(0, 2, 0, 0x0C, 0x0000_0000);
    testSetConfig32(0, 2, 0, 0x20, 0xFE00_0000);
    testSetConfig32(0, 2, 0, 0x34, 0x0000_0040);

    testSetConfig32(0, 2, 0, 0x40, 0x0110_5009);
    testSetConfig32(0, 2, 0, 0x44, 0x0000_0004);
    testSetConfig32(0, 2, 0, 0x48, 0x0000_1000);
    testSetConfig32(0, 2, 0, 0x4C, 0x0000_0100);

    testSetConfig32(0, 2, 0, 0x50, 0x0210_7009);
    testSetConfig32(0, 2, 0, 0x54, 0x0000_0004);
    testSetConfig32(0, 2, 0, 0x58, 0x0000_2000);
    testSetConfig32(0, 2, 0, 0x5C, 0x0000_0100);
    testSetConfig32(0, 2, 0, 0x60, 0x0000_0004);

    testSetConfig32(0, 2, 0, 0x70, 0x0310_8009);
    testSetConfig32(0, 2, 0, 0x74, 0x0000_0004);
    testSetConfig32(0, 2, 0, 0x78, 0x0000_3000);
    testSetConfig32(0, 2, 0, 0x7C, 0x0000_0020);

    testSetConfig32(0, 2, 0, 0x80, 0x0410_0009);
    testSetConfig32(0, 2, 0, 0x84, 0x0000_0004);
    testSetConfig32(0, 2, 0, 0x88, 0x0000_4000);
    testSetConfig32(0, 2, 0, 0x8C, 0x0000_0100);

    const gpu = discoverVirtioGpuDevice() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u16, 0x1AF4), gpu.vendor_id);
    try std.testing.expectEqual(@as(u16, 0x1050), gpu.device_id);
    try std.testing.expectEqual(@as(u64, 0xFE00_1000), gpu.common_cfg.address);
    try std.testing.expectEqual(@as(u64, 0xFE00_2000), gpu.notify_cfg.address);
    try std.testing.expectEqual(@as(u32, 4), gpu.notify_off_multiplier);
    try std.testing.expectEqual(@as(u64, 0xFE00_3000), gpu.isr_cfg.address);
    try std.testing.expectEqual(@as(u64, 0xFE00_4000), gpu.device_cfg.address);
    try std.testing.expectEqual(@as(u16, 0x3), readConfig16(0, 2, 0, 0x04) & 0x3);
}

test "pci virtio block scan finds modern capability regions" {
    testResetForTest();
    defer testResetForTest();

    testSetConfig32(0, 5, 0, 0x00, 0x1042_1AF4);
    testSetConfig32(0, 5, 0, 0x04, 0x0000_0010);
    testSetConfig32(0, 5, 0, 0x0C, 0x0000_0000);
    testSetConfig32(0, 5, 0, 0x20, 0xFE10_0000);
    testSetConfig32(0, 5, 0, 0x34, 0x0000_0040);

    testSetConfig32(0, 5, 0, 0x40, 0x0110_5009);
    testSetConfig32(0, 5, 0, 0x44, 0x0000_0004);
    testSetConfig32(0, 5, 0, 0x48, 0x0000_1000);
    testSetConfig32(0, 5, 0, 0x4C, 0x0000_0100);

    testSetConfig32(0, 5, 0, 0x50, 0x0210_7009);
    testSetConfig32(0, 5, 0, 0x54, 0x0000_0004);
    testSetConfig32(0, 5, 0, 0x58, 0x0000_2000);
    testSetConfig32(0, 5, 0, 0x5C, 0x0000_0100);
    testSetConfig32(0, 5, 0, 0x60, 0x0000_0004);

    testSetConfig32(0, 5, 0, 0x70, 0x0310_8009);
    testSetConfig32(0, 5, 0, 0x74, 0x0000_0004);
    testSetConfig32(0, 5, 0, 0x78, 0x0000_3000);
    testSetConfig32(0, 5, 0, 0x7C, 0x0000_0020);

    testSetConfig32(0, 5, 0, 0x80, 0x0410_0009);
    testSetConfig32(0, 5, 0, 0x84, 0x0000_0004);
    testSetConfig32(0, 5, 0, 0x88, 0x0000_4000);
    testSetConfig32(0, 5, 0, 0x8C, 0x0000_0100);

    const block = discoverVirtioBlockDevice() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u16, 0x1AF4), block.vendor_id);
    try std.testing.expectEqual(@as(u16, 0x1042), block.device_id);
    try std.testing.expectEqual(@as(u64, 0xFE10_1000), block.common_cfg.address);
    try std.testing.expectEqual(@as(u64, 0xFE10_2000), block.notify_cfg.address);
    try std.testing.expectEqual(@as(u32, 4), block.notify_off_multiplier);
    try std.testing.expectEqual(@as(u64, 0xFE10_3000), block.isr_cfg.address);
    try std.testing.expectEqual(@as(u64, 0xFE10_4000), block.device_cfg.address);
    enableVirtioBlockMemoryAndBusMaster(block.location);
    try std.testing.expectEqual(@as(u16, 0x7), readConfig16(0, 5, 0, 0x04) & 0x7);
}
