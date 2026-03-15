const std = @import("std");
const abi = @import("abi.zig");
const storage_backend = @import("storage_backend.zig");

pub const slot_count: usize = 4;
pub const slot_block_capacity: usize = 32;
pub const superblock_lba: u32 = 0;
pub const slot_table_lba: u32 = 1;
pub const slot_data_lba: u32 = 2;
pub const tool_slot_flag_valid: u32 = 1 << 0;

const Header = extern struct {
    magic: u32,
    version: u16,
    slot_count: u16,
    superblock_lba: u32,
    slot_table_lba: u32,
    slot_data_lba: u32,
    slot_block_capacity: u32,
    reserved0: [12]u8,
};

pub const Error = storage_backend.Error || error{
    InvalidSlot,
    NoSpace,
    CorruptLayout,
};

var state: abi.BaremetalToolLayoutState = undefined;
var slots: [slot_count]abi.BaremetalToolSlot = std.mem.zeroes([slot_count]abi.BaremetalToolSlot);

pub fn resetForTest() void {
    state = .{
        .magic = abi.tool_layout_magic,
        .api_version = abi.api_version,
        .slot_count = @as(u16, slot_count),
        .formatted = 0,
        .reserved0 = .{ 0, 0, 0 },
        .superblock_lba = superblock_lba,
        .slot_table_lba = slot_table_lba,
        .slot_data_lba = slot_data_lba,
        .slot_block_capacity = @as(u32, slot_block_capacity),
        .format_count = 0,
        .write_count = 0,
        .clear_count = 0,
    };
    @memset(&slots, std.mem.zeroes(abi.BaremetalToolSlot));
}

pub fn invalidateForBackendChange() void {
    resetForTest();
}

pub fn init() Error!void {
    storage_backend.init();
    if (try loadExisting()) return;
    try format();
}

pub fn statePtr() *const abi.BaremetalToolLayoutState {
    return &state;
}

pub fn slot(index: u32) abi.BaremetalToolSlot {
    if (index >= slot_count) return std.mem.zeroes(abi.BaremetalToolSlot);
    return slots[@as(usize, @intCast(index))];
}

pub fn writePattern(slot_id: u32, byte_len: u32, seed: u8, tick: u64) Error!void {
    try init();
    if (slot_id >= slot_count) return error.InvalidSlot;
    const index = @as(usize, @intCast(slot_id));
    const max_bytes = slot_block_capacity * storage_backend.block_size;
    if (byte_len > max_bytes) return error.NoSpace;

    const total_blocks: usize = if (byte_len == 0) 0 else ((@as(usize, byte_len) - 1) / storage_backend.block_size) + 1;
    var scratch = [_]u8{0} ** storage_backend.block_size;

    var block_idx: usize = 0;
    while (block_idx < slot_block_capacity) : (block_idx += 1) {
        @memset(scratch[0..], 0);
        const global_start = block_idx * storage_backend.block_size;
        if (global_start < byte_len) {
            const remaining = @as(usize, byte_len) - global_start;
            const copy_len = @min(remaining, storage_backend.block_size);
            var offset: usize = 0;
            while (offset < copy_len) : (offset += 1) {
                scratch[offset] = seed +% @as(u8, @truncate(global_start + offset));
            }
        }
        try storage_backend.writeBlocks(slots[index].start_lba + @as(u32, @intCast(block_idx)), scratch[0..]);
    }

    slots[index].block_count = @as(u32, @intCast(total_blocks));
    slots[index].byte_len = byte_len;
    slots[index].flags = if (byte_len == 0) 0 else tool_slot_flag_valid;
    slots[index].checksum = patternChecksum(seed, byte_len);
    slots[index].last_write_tick = tick;
    state.write_count +%= 1;
    try persistSlots();
    try storage_backend.flush();
}

pub fn clearSlot(slot_id: u32, tick: u64) Error!void {
    _ = tick;
    try init();
    if (slot_id >= slot_count) return error.InvalidSlot;
    const index = @as(usize, @intCast(slot_id));
    var zero_block = [_]u8{0} ** storage_backend.block_size;
    var block_idx: usize = 0;
    while (block_idx < slot_block_capacity) : (block_idx += 1) {
        try storage_backend.writeBlocks(slots[index].start_lba + @as(u32, @intCast(block_idx)), zero_block[0..]);
    }
    slots[index].block_count = 0;
    slots[index].byte_len = 0;
    slots[index].flags = 0;
    slots[index].checksum = 0;
    slots[index].last_write_tick = 0;
    state.clear_count +%= 1;
    try persistSlots();
    try storage_backend.flush();
}

pub fn readToolByte(slot_id: u32, offset: u32) u8 {
    if (state.formatted == 0 or slot_id >= slot_count) return 0;
    const record = slots[@as(usize, @intCast(slot_id))];
    if (offset >= record.byte_len) return 0;
    const lba = record.start_lba + (offset / @as(u32, storage_backend.block_size));
    const block_offset = offset % @as(u32, storage_backend.block_size);
    return storage_backend.readByte(lba, block_offset);
}

pub fn format() Error!void {
    storage_backend.init();
    resetForTest();
    var idx: usize = 0;
    while (idx < slot_count) : (idx += 1) {
        slots[idx] = .{
            .slot_id = @as(u32, @intCast(idx)),
            .start_lba = slot_data_lba + @as(u32, @intCast(idx * slot_block_capacity)),
            .block_capacity = @as(u32, slot_block_capacity),
            .block_count = 0,
            .byte_len = 0,
            .flags = 0,
            .checksum = 0,
            .reserved0 = 0,
            .last_write_tick = 0,
        };
    }
    try persistHeader();
    try persistSlots();
    try storage_backend.flush();
    state.formatted = 1;
    state.format_count +%= 1;
}

fn loadExisting() Error!bool {
    var header_block = [_]u8{0} ** storage_backend.block_size;
    try storage_backend.readBlocks(superblock_lba, header_block[0..]);
    var header: Header = undefined;
    @memcpy(std.mem.asBytes(&header), header_block[0..@sizeOf(Header)]);
    if (header.magic != abi.tool_layout_magic) return false;
    if (header.version != abi.api_version or
        header.slot_count != slot_count or
        header.slot_table_lba != slot_table_lba or
        header.slot_data_lba != slot_data_lba or
        header.slot_block_capacity != slot_block_capacity)
    {
        return error.CorruptLayout;
    }

    var slot_block = [_]u8{0} ** storage_backend.block_size;
    try storage_backend.readBlocks(slot_table_lba, slot_block[0..]);
    @memcpy(std.mem.sliceAsBytes(slots[0..]), slot_block[0..@sizeOf(@TypeOf(slots))]);

    resetForTest();
    @memcpy(std.mem.sliceAsBytes(slots[0..]), slot_block[0..@sizeOf(@TypeOf(slots))]);
    state.formatted = 1;
    return true;
}

fn persistHeader() Error!void {
    var block = [_]u8{0} ** storage_backend.block_size;
    const header = Header{
        .magic = abi.tool_layout_magic,
        .version = abi.api_version,
        .slot_count = @as(u16, slot_count),
        .superblock_lba = superblock_lba,
        .slot_table_lba = slot_table_lba,
        .slot_data_lba = slot_data_lba,
        .slot_block_capacity = @as(u32, slot_block_capacity),
        .reserved0 = .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    };
    @memcpy(block[0..@sizeOf(Header)], std.mem.asBytes(&header));
    try storage_backend.writeBlocks(superblock_lba, block[0..]);
}

fn persistSlots() Error!void {
    var block = [_]u8{0} ** storage_backend.block_size;
    const bytes = std.mem.sliceAsBytes(slots[0..]);
    @memcpy(block[0..bytes.len], bytes);
    try storage_backend.writeBlocks(slot_table_lba, block[0..]);
}

fn patternChecksum(seed: u8, byte_len: u32) u32 {
    var checksum: u32 = 0;
    var idx: u32 = 0;
    while (idx < byte_len) : (idx += 1) {
        checksum +%= @as(u32, seed +% @as(u8, @truncate(idx)));
    }
    return checksum;
}

test "tool layout writes and clears slot payloads on the ram disk" {
    storage_backend.resetForTest();
    resetForTest();
    try init();

    try std.testing.expectEqual(@as(u8, 1), state.formatted);
    try std.testing.expectEqual(@as(u16, slot_count), state.slot_count);
    try std.testing.expectEqual(@as(u32, slot_data_lba), state.slot_data_lba);
    try std.testing.expectEqual(@as(u32, slot_block_capacity), state.slot_block_capacity);

    try writePattern(1, 1000, 0x30, 77);
    const record = slot(1);
    try std.testing.expectEqual(@as(u32, 1), state.write_count);
    try std.testing.expectEqual(@as(u32, 2), record.block_count);
    try std.testing.expectEqual(@as(u32, 1000), record.byte_len);
    try std.testing.expectEqual(tool_slot_flag_valid, record.flags);
    try std.testing.expectEqual(@as(u64, 77), record.last_write_tick);
    try std.testing.expectEqual(@as(u8, 0x30), readToolByte(1, 0));
    try std.testing.expectEqual(@as(u8, 0x31), readToolByte(1, 1));
    try std.testing.expectEqual(@as(u8, 0x30), readToolByte(1, 512));
    try std.testing.expectEqual(@as(u8, 0), readToolByte(1, 1500));

    try clearSlot(1, 80);
    const cleared = slot(1);
    try std.testing.expectEqual(@as(u32, 1), state.clear_count);
    try std.testing.expectEqual(@as(u32, 0), cleared.block_count);
    try std.testing.expectEqual(@as(u32, 0), cleared.byte_len);
    try std.testing.expectEqual(@as(u32, 0), cleared.flags);
    try std.testing.expectEqual(@as(u8, 0), readToolByte(1, 0));
}
