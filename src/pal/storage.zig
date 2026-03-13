const abi = @import("../baremetal/abi.zig");
const ram_disk = @import("../baremetal/ram_disk.zig");
const tool_layout = @import("../baremetal/tool_layout.zig");

pub const StorageState = abi.BaremetalStorageState;
pub const ToolLayoutState = abi.BaremetalToolLayoutState;
pub const ToolSlot = abi.BaremetalToolSlot;
pub const Error = ram_disk.Error || tool_layout.Error;

pub fn init() Error!void {
    ram_disk.init();
    try tool_layout.init();
}

pub fn resetForTest() void {
    ram_disk.resetForTest();
    tool_layout.resetForTest();
}

pub fn storageStatePtr() *const StorageState {
    return ram_disk.statePtr();
}

pub fn toolLayoutStatePtr() *const ToolLayoutState {
    return tool_layout.statePtr();
}

pub fn readByte(lba: u32, offset: u32) u8 {
    return ram_disk.readByte(lba, offset);
}

pub fn writePattern(slot_id: u32, byte_len: u32, seed: u8, tick: u64) Error!void {
    try tool_layout.writePattern(slot_id, byte_len, seed, tick);
}

pub fn clearToolSlot(slot_id: u32, tick: u64) Error!void {
    try tool_layout.clearSlot(slot_id, tick);
}

pub fn toolSlot(index: u32) ToolSlot {
    return tool_layout.slot(index);
}

pub fn toolSlotByte(slot_id: u32, offset: u32) u8 {
    return tool_layout.readToolByte(slot_id, offset);
}
