// SPDX-License-Identifier: GPL-2.0-only
const abi = @import("../baremetal/abi.zig");
const display_output = @import("../baremetal/display_output.zig");
const framebuffer_console = @import("../baremetal/framebuffer_console.zig");
const virtio_gpu = @import("../baremetal/virtio_gpu.zig");

pub const State = abi.BaremetalFramebufferState;
pub const DisplayOutputState = abi.BaremetalDisplayOutputState;
pub const DisplayOutputEntry = abi.BaremetalDisplayOutputEntry;
pub const DisplayOutputMode = abi.BaremetalDisplayModeInfo;

pub fn init() bool {
    return framebuffer_console.init();
}

pub fn initMode(width: u16, height: u16) bool {
    return framebuffer_console.initMode(width, height);
}

pub fn clear() void {
    framebuffer_console.clear();
}

pub fn putByte(byte: u8) void {
    framebuffer_console.putByte(byte);
}

pub fn write(text: []const u8) void {
    framebuffer_console.write(text);
}

pub fn statePtr() *const State {
    return framebuffer_console.statePtr();
}

pub fn displayOutputStatePtr() *const DisplayOutputState {
    return display_output.statePtr();
}

pub fn displayOutputCount() u16 {
    return display_output.outputCount();
}

pub fn displayOutputEntry(index: u16) DisplayOutputEntry {
    return display_output.outputEntry(index);
}

pub fn displayOutputEdidByte(index: u16) u8 {
    return display_output.edidByte(index);
}

pub fn displayOutputModeCount(index: u16) u16 {
    return display_output.outputModeCount(index);
}

pub fn displayOutputMode(index: u16, mode_index: u16) ?DisplayOutputMode {
    return display_output.outputMode(index, mode_index);
}

pub fn activateDisplayOutput(index: u16) error{NotFound}!void {
    const display_state = display_output.statePtr();
    if (display_state.controller == abi.display_controller_virtio_gpu) {
        if (display_state.hardware_backed != 0) {
            _ = virtio_gpu.probeAndPresentPatternForOutputIndex(@intCast(index)) catch return error.NotFound;
            return;
        }
        if (!display_output.selectOutputIndex(index)) return error.NotFound;
        return;
    }
    if (!display_output.selectOutputIndex(index)) return error.NotFound;
}

pub fn activateDisplayConnectorPreferred(connector_type: u8) error{ NotFound, UnsupportedMode }!void {
    const display_state = display_output.statePtr();
    if (display_state.controller == abi.display_controller_virtio_gpu) {
        if (display_state.hardware_backed != 0) {
            _ = virtio_gpu.probeAndPresentPatternForConnectorPreferred(connector_type) catch |err| switch (err) {
                error.NoConnectedScanout => return error.NotFound,
                error.UnsupportedMode, error.FramebufferTooLarge => return error.UnsupportedMode,
                else => return error.NotFound,
            };
            return;
        }
        if (!display_output.selectOutputConnector(connector_type)) return error.NotFound;
        const active_index = display_output.statePtr().active_scanout;
        if (!display_output.setOutputPreferredMode(@as(u16, active_index))) return error.UnsupportedMode;
        return;
    }
    if (display_state.connector_type != connector_type) return error.NotFound;
    const mode = display_output.preferredMode(@as(u16, display_state.active_scanout)) orelse return error.UnsupportedMode;
    framebuffer_console.setMode(mode.width, mode.height) catch return error.UnsupportedMode;
}

pub fn activateDisplayOutputPreferred(index: u16) error{ NotFound, UnsupportedMode }!void {
    const display_state = display_output.statePtr();
    if (display_state.controller == abi.display_controller_virtio_gpu) {
        if (display_state.hardware_backed != 0) {
            _ = virtio_gpu.probeAndPresentPatternForOutputIndexPreferred(@intCast(index)) catch |err| switch (err) {
                error.NoConnectedScanout => return error.NotFound,
                error.UnsupportedMode, error.FramebufferTooLarge => return error.UnsupportedMode,
                else => return error.NotFound,
            };
            return;
        }
        if (!display_output.setOutputPreferredMode(index)) return error.UnsupportedMode;
        return;
    }
    if (index != 0) return error.NotFound;
    const mode = display_output.preferredMode(index) orelse return error.UnsupportedMode;
    framebuffer_console.setMode(mode.width, mode.height) catch return error.UnsupportedMode;
}

pub fn activateDisplayOutputMode(index: u16, mode_index: u16) error{ NotFound, UnsupportedMode }!void {
    const display_state = display_output.statePtr();
    if (display_state.controller == abi.display_controller_virtio_gpu) {
        if (display_state.hardware_backed != 0) {
            _ = virtio_gpu.probeAndPresentPatternForOutputIndexModeIndex(@intCast(index), @intCast(mode_index)) catch |err| switch (err) {
                error.NoConnectedScanout => return error.NotFound,
                error.UnsupportedMode, error.FramebufferTooLarge => return error.UnsupportedMode,
                else => return error.NotFound,
            };
            return;
        }
        const entry = display_output.outputEntry(index);
        if (index >= display_output.outputCount() or entry.connected == 0) return error.NotFound;
        if (!display_output.setOutputModeByIndex(index, mode_index)) return error.UnsupportedMode;
        return;
    }
    if (index != 0) return error.NotFound;
    const mode = display_output.outputMode(index, mode_index) orelse return error.UnsupportedMode;
    framebuffer_console.setMode(mode.width, mode.height) catch return error.UnsupportedMode;
}

pub fn setDisplayOutputMode(index: u16, width: u16, height: u16) error{ NotFound, UnsupportedMode }!void {
    const display_state = display_output.statePtr();
    if (display_state.controller == abi.display_controller_virtio_gpu) {
        if (display_state.hardware_backed != 0) {
            _ = virtio_gpu.probeAndPresentPatternForOutputIndexMode(@intCast(index), width, height) catch |err| switch (err) {
                error.NoConnectedScanout => return error.NotFound,
                error.UnsupportedMode, error.FramebufferTooLarge => return error.UnsupportedMode,
                else => return error.NotFound,
            };
            return;
        }
        const entry = display_output.outputEntry(index);
        if (index >= display_output.outputCount() or entry.connected == 0) return error.NotFound;
        if (!display_output.setOutputMode(index, width, height)) return error.UnsupportedMode;
        return;
    }
    if (index != 0) return error.NotFound;
    framebuffer_console.setMode(width, height) catch return error.UnsupportedMode;
}

pub fn pixel(index: u32) u32 {
    return framebuffer_console.pixel(index);
}

pub fn pixelAt(x: u32, y: u32) u32 {
    return framebuffer_console.pixelAt(x, y);
}

pub fn setMode(width: u16, height: u16) error{UnsupportedMode}!void {
    try framebuffer_console.setMode(width, height);
}

pub fn supportedModeCount() u16 {
    return framebuffer_console.supportedModeCount();
}

pub fn supportedModeWidth(index: u16) u16 {
    return framebuffer_console.supportedModeWidth(index);
}

pub fn supportedModeHeight(index: u16) u16 {
    return framebuffer_console.supportedModeHeight(index);
}

pub fn resetForTest() void {
    display_output.resetForTest();
    framebuffer_console.resetForTest();
}
