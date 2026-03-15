const std = @import("std");
const abi = @import("../baremetal/abi.zig");
const ata_pio_disk = @import("../baremetal/ata_pio_disk.zig");
const storage_backend = @import("../baremetal/storage_backend.zig");
const tool_layout = @import("../baremetal/tool_layout.zig");

pub const StorageState = abi.BaremetalStorageState;
pub const PartitionInfo = ata_pio_disk.PartitionInfo;
pub const ToolLayoutState = abi.BaremetalToolLayoutState;
pub const ToolSlot = abi.BaremetalToolSlot;
pub const Error = storage_backend.Error || tool_layout.Error;

pub fn init() Error!void {
    storage_backend.init();
    try tool_layout.init();
}

pub fn resetForTest() void {
    storage_backend.resetForTest();
    tool_layout.resetForTest();
}

pub fn storageStatePtr() *const StorageState {
    return storage_backend.statePtr();
}

pub fn logicalBaseLba() u32 {
    return storage_backend.logicalBaseLba();
}

pub fn partitionCount() u8 {
    return storage_backend.partitionCount();
}

pub fn selectedPartitionIndex() ?u8 {
    return storage_backend.selectedPartitionIndex();
}

pub fn partitionInfo(index: u8) ?PartitionInfo {
    return storage_backend.partitionInfo(index);
}

pub fn selectPartition(index: u8) Error!void {
    try storage_backend.selectPartition(index);
}

pub fn toolLayoutStatePtr() *const ToolLayoutState {
    return tool_layout.statePtr();
}

pub fn readByte(lba: u32, offset: u32) u8 {
    return storage_backend.readByte(lba, offset);
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

test "pal storage surface exposes ram-disk partition baseline" {
    storage_backend.resetForTest();
    tool_layout.resetForTest();

    try init();

    try std.testing.expectEqual(@as(u32, 0), logicalBaseLba());
    try std.testing.expectEqual(@as(u8, 0), partitionCount());
    try std.testing.expectEqual(@as(?u8, null), selectedPartitionIndex());
    try std.testing.expectEqual(@as(?PartitionInfo, null), partitionInfo(0));
}

test "pal storage surface exports and selects ata partitions" {
    storage_backend.resetForTest();
    tool_layout.resetForTest();
    ata_pio_disk.testEnableMockDevice(16384);
    ata_pio_disk.testInstallMockMbrPartition(2048, 4096, 0x83);
    ata_pio_disk.testInstallMockMbrPartitionAt(1, 8192, 2048, 0x83);
    defer ata_pio_disk.testDisableMockDevice();

    try init();

    try std.testing.expectEqual(@as(u8, abi.storage_backend_ata_pio), storageStatePtr().backend);
    try std.testing.expectEqual(@as(u8, 2), partitionCount());
    try std.testing.expectEqual(@as(?u8, 0), selectedPartitionIndex());
    try std.testing.expectEqual(@as(u32, 2048), logicalBaseLba());

    const primary = partitionInfo(0).?;
    const secondary = partitionInfo(1).?;
    try std.testing.expectEqual(ata_pio_disk.PartitionScheme.mbr, primary.scheme);
    try std.testing.expectEqual(@as(u32, 2048), primary.start_lba);
    try std.testing.expectEqual(@as(u32, 4096), primary.sector_count);
    try std.testing.expectEqual(ata_pio_disk.PartitionScheme.mbr, secondary.scheme);
    try std.testing.expectEqual(@as(u32, 8192), secondary.start_lba);
    try std.testing.expectEqual(@as(u32, 2048), secondary.sector_count);

    try selectPartition(1);
    try std.testing.expectEqual(@as(?u8, 1), selectedPartitionIndex());
    try std.testing.expectEqual(@as(u32, 8192), logicalBaseLba());
    try std.testing.expectEqual(@as(u32, 2048), storageStatePtr().block_count);
}
