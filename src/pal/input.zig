// SPDX-License-Identifier: GPL-2.0-only
const abi = @import("../baremetal/abi.zig");
const ps2_input = @import("../baremetal/ps2_input.zig");

pub const KeyboardState = abi.BaremetalKeyboardState;
pub const KeyboardEvent = abi.BaremetalKeyboardEvent;
pub const MouseState = abi.BaremetalMouseState;
pub const MousePacket = abi.BaremetalMousePacket;

pub fn init() void {
    ps2_input.init();
}

pub fn resetForTest() void {
    ps2_input.resetForTest();
}

pub fn keyboardStatePtr() *const KeyboardState {
    return ps2_input.keyboardStatePtr();
}

pub fn keyboardEvent(index: u32) KeyboardEvent {
    return ps2_input.keyboardEvent(index);
}

pub fn mouseStatePtr() *const MouseState {
    return ps2_input.mouseStatePtr();
}

pub fn mousePacket(index: u32) MousePacket {
    return ps2_input.mousePacket(index);
}

pub fn injectKeyboardScancode(scancode: u8) void {
    ps2_input.injectKeyboardScancode(scancode);
}

pub fn injectMousePacket(buttons: u8, dx: i16, dy: i16) void {
    ps2_input.injectMousePacket(buttons, dx, dy);
}
