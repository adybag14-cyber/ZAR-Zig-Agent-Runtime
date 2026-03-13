const std = @import("std");
const abi = @import("abi.zig");

pub const block_size: usize = 512;
pub const block_count: usize = 2048;
pub const capacity_bytes: usize = block_size * block_count;

pub const Error = error{
    NotMounted,
    OutOfRange,
    UnalignedLength,
};

var data: [capacity_bytes]u8 = [_]u8{0} ** capacity_bytes;
var state: abi.BaremetalStorageState = undefined;

pub fn resetForTest() void {
    @memset(&data, 0);
    state = .{
        .magic = abi.storage_magic,
        .api_version = abi.api_version,
        .backend = abi.storage_backend_ram_disk,
        .mounted = 0,
        .block_size = @as(u32, block_size),
        .block_count = @as(u32, block_count),
        .read_ops = 0,
        .write_ops = 0,
        .flush_ops = 0,
        .last_lba = 0,
        .last_block_count = 0,
        .dirty = 0,
        .reserved0 = .{ 0, 0, 0 },
        .bytes_read = 0,
        .bytes_written = 0,
    };
}

pub fn init() void {
    if (state.magic != abi.storage_magic or state.block_size != @as(u32, block_size) or state.block_count != @as(u32, block_count)) {
        resetForTest();
    }
    state.mounted = 1;
}

pub fn statePtr() *const abi.BaremetalStorageState {
    return &state;
}

pub fn readBlocks(lba: u32, out: []u8) Error!void {
    try ensureMounted();
    if (out.len % block_size != 0) return error.UnalignedLength;
    const blocks: usize = out.len / block_size;
    const start_block: usize = @as(usize, lba);
    if (start_block + blocks > block_count) return error.OutOfRange;
    const start = start_block * block_size;
    const end = start + out.len;
    @memcpy(out, data[start..end]);
    state.read_ops +%= 1;
    state.last_lba = lba;
    state.last_block_count = @as(u32, @intCast(blocks));
    state.bytes_read +%= @as(u64, @intCast(out.len));
}

pub fn writeBlocks(lba: u32, input: []const u8) Error!void {
    try ensureMounted();
    if (input.len % block_size != 0) return error.UnalignedLength;
    const blocks: usize = input.len / block_size;
    const start_block: usize = @as(usize, lba);
    if (start_block + blocks > block_count) return error.OutOfRange;
    const start = start_block * block_size;
    const end = start + input.len;
    @memcpy(data[start..end], input);
    state.write_ops +%= 1;
    state.last_lba = lba;
    state.last_block_count = @as(u32, @intCast(blocks));
    state.bytes_written +%= @as(u64, @intCast(input.len));
    state.dirty = 1;
}

pub fn flush() Error!void {
    try ensureMounted();
    state.flush_ops +%= 1;
    state.dirty = 0;
}

pub fn readByte(lba: u32, offset: u32) u8 {
    if (state.mounted == 0) return 0;
    if (lba >= state.block_count or offset >= state.block_size) return 0;
    const index = (@as(usize, lba) * block_size) + @as(usize, offset);
    return data[index];
}

fn ensureMounted() Error!void {
    if (state.mounted == 0) return error.NotMounted;
}

test "ram disk read write and flush update storage state" {
    resetForTest();
    init();

    var write_block = [_]u8{0} ** block_size;
    for (&write_block, 0..) |*byte, idx| {
        byte.* = @as(u8, @truncate(idx));
    }
    try writeBlocks(2, write_block[0..]);
    try std.testing.expectEqual(@as(u8, 1), state.mounted);
    try std.testing.expectEqual(@as(u32, 1), state.write_ops);
    try std.testing.expectEqual(@as(u8, 1), state.dirty);
    try std.testing.expectEqual(@as(u8, 0), readByte(2, 0));
    try std.testing.expectEqual(@as(u8, 1), readByte(2, 1));

    var out = [_]u8{0} ** block_size;
    try readBlocks(2, out[0..]);
    try std.testing.expectEqualSlices(u8, write_block[0..], out[0..]);
    try std.testing.expectEqual(@as(u32, 1), state.read_ops);

    try flush();
    try std.testing.expectEqual(@as(u32, 1), state.flush_ops);
    try std.testing.expectEqual(@as(u8, 0), state.dirty);
}
