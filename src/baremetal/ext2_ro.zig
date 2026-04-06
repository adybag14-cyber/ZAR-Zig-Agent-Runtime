// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const storage_backend = @import("storage_backend.zig");

pub const test_file_name = "HELLO.TXT";
pub const test_file_payload = "hello-from-ext2";

const block_size_bytes: u32 = 1024;
const inode_size_bytes: u32 = 128;
const total_blocks: u32 = 16;
const total_sectors: u32 = (total_blocks * block_size_bytes) / 512;
const superblock_offset: u32 = 1024;
const group_desc_offset: u32 = 2048;
const inode_table_block: u32 = 5;
const root_dir_block: u32 = 6;
const file_data_block: u32 = 7;
const root_inode_number: u32 = 2;
const file_inode_number: u32 = 3;
const max_root_entries: usize = 16;

pub const Error = std.mem.Allocator.Error || storage_backend.Error || error{
    InvalidFilesystem,
    FileNotFound,
    FileTooBig,
    IsDirectory,
    NotDirectory,
    ResponseTooLarge,
    UnsupportedPath,
};

pub const SimpleStat = struct {
    kind: std.Io.File.Kind,
    size: u64,
    checksum: u32,
    modified_tick: u64,
    entry_id: u64,
};

const RootEntry = struct {
    inode: u32,
    kind: std.Io.File.Kind,
    size: u32,
    name_len: usize,
    name: [64]u8 = [_]u8{0} ** 64,

    fn nameSlice(self: *const @This()) []const u8 {
        return self.name[0..self.name_len];
    }
};

const Superblock = struct {
    block_size: u32,
    inode_size: u16,
    inodes_per_group: u32,
    inode_table_block: u32,
};

const Inode = struct {
    mode: u16,
    size: u32,
    direct_blocks: [12]u32,

    fn kind(self: *const @This()) std.Io.File.Kind {
        return if ((self.mode & 0xF000) == 0x4000) .directory else .file;
    }
};

pub fn seedTestImage() Error!void {
    storage_backend.init();
    const state = storage_backend.statePtr();
    if (state.mounted == 0 or state.block_size != 512 or state.block_count < total_sectors) return error.InvalidFilesystem;

    var image = [_]u8{0} ** (total_sectors * 512);

    writeU32(image[superblockOffset() + 0 ..][0..4], 16);
    writeU32(image[superblockOffset() + 4 ..][0..4], total_blocks);
    writeU32(image[superblockOffset() + 20 ..][0..4], 1);
    writeU32(image[superblockOffset() + 24 ..][0..4], 0);
    writeU32(image[superblockOffset() + 32 ..][0..4], total_blocks);
    writeU32(image[superblockOffset() + 40 ..][0..4], 16);
    writeU16(image[superblockOffset() + 56 ..][0..2], 0xEF53);
    writeU32(image[superblockOffset() + 76 ..][0..4], 1);
    writeU32(image[superblockOffset() + 84 ..][0..4], 11);
    writeU16(image[superblockOffset() + 88 ..][0..2], @as(u16, @intCast(inode_size_bytes)));

    writeU32(image[group_desc_offset + 0 ..][0..4], 3);
    writeU32(image[group_desc_offset + 4 ..][0..4], 4);
    writeU32(image[group_desc_offset + 8 ..][0..4], inode_table_block);

    writeInode(image[inodeOffset(root_inode_number)..][0..inode_size_bytes], 0x41ED, block_size_bytes, &.{ root_dir_block });
    writeInode(image[inodeOffset(file_inode_number)..][0..inode_size_bytes], 0x81A4, test_file_payload.len, &.{ file_data_block });

    var dir_block = image[blockOffset(root_dir_block) .. blockOffset(root_dir_block) + block_size_bytes];
    writeDirEntry(dir_block[0..12], root_inode_number, 12, ".", 2);
    writeDirEntry(dir_block[12..24], root_inode_number, 12, "..", 2);
    writeDirEntry(dir_block[24..block_size_bytes], file_inode_number, block_size_bytes - 24, test_file_name, 1);

    @memcpy(image[blockOffset(file_data_block) .. blockOffset(file_data_block) + test_file_payload.len], test_file_payload);

    var sector: u32 = 0;
    while (sector < total_sectors) : (sector += 1) {
        const start = sector * 512;
        try storage_backend.writeBlocks(sector, image[start .. start + 512]);
    }
    try storage_backend.flush();
}

pub fn listRootAlloc(allocator: std.mem.Allocator, max_bytes: usize) Error![]u8 {
    var entries: [max_root_entries]RootEntry = undefined;
    const count = try scanRoot(&entries);

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    for (entries[0..count]) |entry| {
        const line = if (entry.kind == .directory)
            try std.fmt.allocPrint(allocator, "dir {s}\n", .{entry.nameSlice()})
        else
            try std.fmt.allocPrint(allocator, "file {s} {d}\n", .{ entry.nameSlice(), entry.size });
        defer allocator.free(line);
        if (out.items.len + line.len > max_bytes) return error.ResponseTooLarge;
        try out.appendSlice(allocator, line);
    }
    return out.toOwnedSlice(allocator);
}

pub fn readFileAlloc(allocator: std.mem.Allocator, relative_path: []const u8, max_bytes: usize) Error![]u8 {
    var scratch: [4096]u8 = undefined;
    const file = try readFile(relative_path, scratch[0..]);
    if (file.len > max_bytes) return error.FileTooBig;
    return allocator.dupe(u8, file);
}

pub fn readFile(relative_path: []const u8, buffer: []u8) Error![]const u8 {
    const entry = try findRootEntry(relative_path);
    if (entry.kind == .directory) return error.IsDirectory;
    if (entry.size > buffer.len) return error.FileTooBig;

    const superblock = try readSuperblock();
    const inode = try readInode(superblock, entry.inode);
    return readInodeData(inode, buffer[0..entry.size]);
}

pub fn statSummary(relative_path: []const u8) Error!SimpleStat {
    if (relative_path.len == 0 or std.mem.eql(u8, relative_path, "/")) {
        return .{ .kind = .directory, .size = 0, .checksum = 0, .modified_tick = 0, .entry_id = 1 };
    }
    const entry = try findRootEntry(relative_path);
    return .{
        .kind = entry.kind,
        .size = entry.size,
        .checksum = checksumBytes(entry.nameSlice()),
        .modified_tick = 0,
        .entry_id = entry.inode,
    };
}

fn findRootEntry(relative_path: []const u8) Error!RootEntry {
    const component = normalizeRelativePath(relative_path) orelse return error.UnsupportedPath;
    var entries: [max_root_entries]RootEntry = undefined;
    const count = try scanRoot(&entries);
    for (entries[0..count]) |entry| {
        if (std.mem.eql(u8, entry.nameSlice(), component)) return entry;
    }
    return error.FileNotFound;
}

fn scanRoot(entries_out: *[max_root_entries]RootEntry) Error!usize {
    const superblock = try readSuperblock();
    const root = try readInode(superblock, root_inode_number);
    if (root.kind() != .directory) return error.InvalidFilesystem;

    var block = [_]u8{0} ** block_size_bytes;
    _ = try readInodeData(root, block[0..]);

    var count: usize = 0;
    var offset: usize = 0;
    while (offset + 8 <= block.len) {
        const inode = readLeU32(block[offset..][0..4]);
        const rec_len = readLeU16(block[offset + 4 ..][0..2]);
        const name_len = block[offset + 6];
        const file_type = block[offset + 7];
        if (inode == 0 or rec_len == 0) break;
        if (offset + rec_len > block.len) return error.InvalidFilesystem;
        if (name_len != 0 and offset + 8 + name_len <= block.len) {
            const name = block[offset + 8 .. offset + 8 + name_len];
            if (!std.mem.eql(u8, name, ".") and !std.mem.eql(u8, name, "..")) {
                if (count >= max_root_entries) return error.ResponseTooLarge;
                const inode_data = try readInode(superblock, inode);
                entries_out[count] = .{
                    .inode = inode,
                    .kind = if (file_type == 2 or inode_data.kind() == .directory) .directory else .file,
                    .size = inode_data.size,
                    .name_len = name.len,
                };
                @memcpy(entries_out[count].name[0..name.len], name);
                count += 1;
            }
        }
        offset += rec_len;
    }
    return count;
}

fn readSuperblock() Error!Superblock {
    var bytes: [1024]u8 = undefined;
    try readBackendBytes(superblock_offset, bytes[0..]);
    if (readLeU16(bytes[56..58]) != 0xEF53) return error.InvalidFilesystem;
    const log_block_size = readLeU32(bytes[24..28]);
    if (log_block_size != 0) return error.InvalidFilesystem;
    const inode_size = readLeU16(bytes[88..90]);
    if (inode_size < inode_size_bytes) return error.InvalidFilesystem;

    var group_desc: [32]u8 = undefined;
    try readBackendBytes(group_desc_offset, group_desc[0..]);

    return .{
        .block_size = block_size_bytes,
        .inode_size = inode_size,
        .inodes_per_group = readLeU32(bytes[40..44]),
        .inode_table_block = readLeU32(group_desc[8..12]),
    };
}

fn readInode(superblock: Superblock, inode_number: u32) Error!Inode {
    if (inode_number == 0) return error.InvalidFilesystem;
    const inode_index = inode_number - 1;
    const inode_offset_bytes = blockOffset(superblock.inode_table_block) + inode_index * superblock.inode_size;
    var bytes: [inode_size_bytes]u8 = undefined;
    try readBackendBytes(@as(u32, @intCast(inode_offset_bytes)), bytes[0..]);

    var direct_blocks: [12]u32 = [_]u32{0} ** 12;
    var index: usize = 0;
    while (index < direct_blocks.len) : (index += 1) {
        const start = 40 + (index * 4);
        direct_blocks[index] = readLeU32(bytes[start .. start + 4]);
    }

    return .{
        .mode = readLeU16(bytes[0..2]),
        .size = readLeU32(bytes[4..8]),
        .direct_blocks = direct_blocks,
    };
}

fn readInodeData(inode: Inode, out: []u8) Error![]const u8 {
    var copied: usize = 0;
    var block = [_]u8{0} ** block_size_bytes;
    for (inode.direct_blocks) |data_block| {
        if (copied >= out.len) break;
        if (data_block == 0) break;
        try readBackendBytes(@as(u32, @intCast(blockOffset(data_block))), block[0..]);
        const copy_len = @min(out.len - copied, block.len);
        @memcpy(out[copied .. copied + copy_len], block[0..copy_len]);
        copied += copy_len;
    }
    if (copied < out.len) return error.InvalidFilesystem;
    return out[0..copied];
}

fn readBackendBytes(byte_offset: u32, out: []u8) Error!void {
    const state = storage_backend.statePtr();
    if (state.mounted == 0 or state.block_size != 512) return error.InvalidFilesystem;
    var scratch = [_]u8{0} ** 512;
    var copied: usize = 0;
    while (copied < out.len) {
        const absolute = byte_offset + copied;
        const lba = absolute / 512;
        const intra = absolute % 512;
        try storage_backend.readBlocks(@as(u32, @intCast(lba)), scratch[0..]);
        const remaining_in_sector = 512 - intra;
        const copy_len = @min(out.len - copied, remaining_in_sector);
        @memcpy(out[copied .. copied + copy_len], scratch[intra .. intra + copy_len]);
        copied += copy_len;
    }
}

fn normalizeRelativePath(relative_path: []const u8) ?[]const u8 {
    if (relative_path.len == 0 or std.mem.eql(u8, relative_path, "/")) return null;
    if (relative_path[0] != '/') return null;
    const tail = relative_path[1..];
    if (tail.len == 0 or std.mem.indexOfScalar(u8, tail, '/') != null) return null;
    return tail;
}

fn writeInode(out: []u8, mode: u16, size: usize, direct_blocks: []const u32) void {
    @memset(out, 0);
    writeU16(out[0..2], mode);
    writeU32(out[4..8], @as(u32, @intCast(size)));
    writeU16(out[26..28], 1);
    const sector_blocks = @as(u32, @intCast(((size + 511) / 512)));
    writeU32(out[28..32], sector_blocks);
    for (direct_blocks, 0..) |block_number, index| {
        writeU32(out[40 + (index * 4) ..][0..4], block_number);
    }
}

fn writeDirEntry(out: []u8, inode: u32, rec_len: u16, name: []const u8, file_type: u8) void {
    @memset(out, 0);
    writeU32(out[0..4], inode);
    writeU16(out[4..6], rec_len);
    out[6] = @as(u8, @intCast(name.len));
    out[7] = file_type;
    @memcpy(out[8 .. 8 + name.len], name);
}

fn checksumBytes(bytes: []const u8) u32 {
    return std.hash.Crc32.hash(bytes);
}

fn superblockOffset() usize {
    return @as(usize, superblock_offset);
}

fn blockOffset(block_index: u32) usize {
    return @as(usize, block_index * block_size_bytes);
}

fn inodeOffset(inode_number: u32) usize {
    return blockOffset(inode_table_block) + @as(usize, (inode_number - 1) * inode_size_bytes);
}

fn writeU16(out: []u8, value: u16) void {
    out[0] = @as(u8, @truncate(value));
    out[1] = @as(u8, @truncate(value >> 8));
}

fn writeU32(out: []u8, value: u32) void {
    out[0] = @as(u8, @truncate(value));
    out[1] = @as(u8, @truncate(value >> 8));
    out[2] = @as(u8, @truncate(value >> 16));
    out[3] = @as(u8, @truncate(value >> 24));
}

fn readLeU16(bytes: []const u8) u16 {
    return @as(u16, bytes[0]) |
        (@as(u16, bytes[1]) << 8);
}

fn readLeU32(bytes: []const u8) u32 {
    return @as(u32, bytes[0]) |
        (@as(u32, bytes[1]) << 8) |
        (@as(u32, bytes[2]) << 16) |
        (@as(u32, bytes[3]) << 24);
}

test "ext2 ro seeds and reads bounded root file" {
    storage_backend.resetForTest();
    @import("virtio_block.zig").testEnableMockDevice(256);
    defer @import("virtio_block.zig").testDisableMockDevice();
    storage_backend.init();

    try seedTestImage();

    const listing = try listRootAlloc(std.testing.allocator, 256);
    defer std.testing.allocator.free(listing);
    try std.testing.expectEqualStrings("file HELLO.TXT 15\n", listing);

    const file = try readFileAlloc(std.testing.allocator, "/HELLO.TXT", 64);
    defer std.testing.allocator.free(file);
    try std.testing.expectEqualStrings(test_file_payload, file);

    const stat = try statSummary("/HELLO.TXT");
    try std.testing.expectEqual(@as(std.Io.File.Kind, .file), stat.kind);
    try std.testing.expectEqual(@as(u64, test_file_payload.len), stat.size);
}
