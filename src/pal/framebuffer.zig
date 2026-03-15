const abi = @import("../baremetal/abi.zig");
const display_output = @import("../baremetal/display_output.zig");
const framebuffer_console = @import("../baremetal/framebuffer_console.zig");

pub const State = abi.BaremetalFramebufferState;
pub const DisplayOutputState = abi.BaremetalDisplayOutputState;

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

pub fn displayOutputEdidByte(index: u16) u8 {
    return display_output.edidByte(index);
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
