// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const storage_backend = @import("storage_backend.zig");
const virtio_block = @import("virtio_block.zig");

pub const test_file_name = "HELLO.TXT";
pub const test_file_payload = "hello-from-fat32";

const sector_size_bytes: u32 = 512;
const total_sectors: u32 = 32;
const reserved_sector_count: u16 = 1;
const fat_sector_count: u32 = 1;
const sectors_per_cluster: u8 = 1;
const root_cluster: u32 = 2;
const file_cluster: u32 = 3;
const max_root_entries: usize = 16;

pub const Error = std.mem.Allocator.Error || storage_backend.Error || error{
    InvalidFilesystem,
    FileNotFound,
    FileTooBig,
    IsDirectory,
    NotDirectory,
    ResponseTooLarge,
    UnsupportedPath,
    NoSpace,
};

pub const SimpleStat = struct {
    kind: std.Io.File.Kind,
    size: u64,
    checksum: u32,
    modified_tick: u64,
    entry_id: u64,
};

const BiosParameterBlock = struct {
    bytes_per_sector: u16,
    sectors_per_cluster: u8,
    reserved_sector_count: u16,
    num_fats: u8,
    fat_size_sectors: u32,
    root_cluster: u32,
    total_sectors: u32,

    fn firstDataSector(self: @This()) u32 {
        return self.reserved_sector_count + (@as(u32, self.num_fats) * self.fat_size_sectors);
    }

    fn clusterToSector(self: @This(), cluster: u32) u32 {
        return self.firstDataSector() + ((cluster - 2) * @as(u32, self.sectors_per_cluster));
    }
};

const RootEntry = struct {
    cluster: u32,
    kind: std.Io.File.Kind,
    size: u32,
    name_len: usize,
    name: [64]u8 = [_]u8{0} ** 64,

    fn nameSlice(self: *const @This()) []const u8 {
        return self.name[0..self.name_len];
    }
};

pub fn seedTestImage() Error!void {
    storage_backend.init();
    const state = storage_backend.statePtr();
    if (state.mounted == 0 or state.block_size != sector_size_bytes or state.block_count < total_sectors) return error.InvalidFilesystem;

    var image = [_]u8{0} ** (total_sectors * sector_size_bytes);

    image[0] = 0xEB;
    image[1] = 0x58;
    image[2] = 0x90;
    @memcpy(image[3..11], "MSDOS5.0");
    writeU16(image[11..13], sector_size_bytes);
    image[13] = sectors_per_cluster;
    writeU16(image[14..16], reserved_sector_count);
    image[16] = 1;
    writeU16(image[17..19], 0);
    writeU16(image[19..21], 0);
    image[21] = 0xF8;
    writeU16(image[22..24], 0);
    writeU16(image[24..26], 1);
    writeU16(image[26..28], 1);
    writeU32(image[28..32], 0);
    writeU32(image[32..36], total_sectors);
    writeU32(image[36..40], fat_sector_count);
    writeU16(image[40..42], 0);
    writeU16(image[42..44], 0);
    writeU32(image[44..48], root_cluster);
    writeU16(image[48..50], 1);
    writeU16(image[50..52], 6);
    image[64] = 0x80;
    image[66] = 0x29;
    writeU32(image[67..71], 0x12345678);
    @memcpy(image[71..82], "ZAR FAT32  ");
    @memcpy(image[82..90], "FAT32   ");
    image[510] = 0x55;
    image[511] = 0xAA;

    const fat_offset = sector_size_bytes * reserved_sector_count;
    writeU32(image[fat_offset + 0 .. fat_offset + 4], 0x0FFFFFF8);
    writeU32(image[fat_offset + 4 .. fat_offset + 8], 0xFFFFFFFF);
    writeU32(image[fat_offset + 8 .. fat_offset + 12], 0x0FFFFFFF);
    writeU32(image[fat_offset + 12 .. fat_offset + 16], 0x0FFFFFFF);

    const bpb = try readBpb(image[0..sector_size_bytes]);
    const root_sector = bpb.clusterToSector(root_cluster);
    const file_sector = bpb.clusterToSector(file_cluster);
    var root_dir = image[root_sector * sector_size_bytes ..][0..sector_size_bytes];
    writeShortEntry(root_dir[0..32], "HELLO   TXT", 0x20, file_cluster, test_file_payload.len);
    root_dir[32] = 0x00;

    @memcpy(image[file_sector * sector_size_bytes ..][0..test_file_payload.len], test_file_payload);

    var sector: u32 = 0;
    while (sector < total_sectors) : (sector += 1) {
        const start = @as(usize, sector) * sector_size_bytes;
        try storage_backend.writeBlocks(sector, image[start .. start + sector_size_bytes]);
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

    const bpb = try loadBpb();
    return readClusterChain(bpb, entry.cluster, buffer[0..entry.size]);
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
        .entry_id = entry.cluster,
    };
}

pub fn writeFile(relative_path: []const u8, data: []const u8, tick: u64) Error!void {
    _ = tick;
    const component = normalizeRelativePath(relative_path) orelse return error.UnsupportedPath;

    var raw_name: [11]u8 = undefined;
    try encodeShortName(component, raw_name[0..]);

    const bpb = try loadBpb();
    var root = [_]u8{0} ** sector_size_bytes;
    _ = try readClusterChain(bpb, bpb.root_cluster, root[0..]);

    var entry_offset: ?usize = null;
    var free_offset: ?usize = null;
    var existing: ?RootEntry = null;

    var offset: usize = 0;
    while (offset + 32 <= root.len) : (offset += 32) {
        const dirent = root[offset..][0..32];
        const first = dirent[0];
        if (first == 0x00) {
            if (free_offset == null) free_offset = offset;
            break;
        }
        if (first == 0xE5) {
            if (free_offset == null) free_offset = offset;
            continue;
        }
        if (dirent[11] == 0x0F) continue;
        if (std.mem.eql(u8, dirent[0..11], raw_name[0..])) {
            entry_offset = offset;
            existing = .{
                .cluster = readDirentCluster(dirent),
                .kind = if ((dirent[11] & 0x10) != 0) .directory else .file,
                .size = readLeU32(dirent[28..32]),
                .name_len = 0,
            };
            break;
        }
    }

    if (existing) |entry| {
        if (entry.kind == .directory) return error.IsDirectory;
        if (entry.cluster >= 2) try freeClusterChain(bpb, entry.cluster);
    }

    const write_offset = entry_offset orelse free_offset orelse return error.NoSpace;
    const first_cluster: u32 = if (data.len == 0)
        0
    else
        try allocateClusterChain(bpb, requiredClusterCount(bpb, data.len));
    errdefer if (first_cluster >= 2) freeClusterChain(bpb, first_cluster) catch {};

    if (data.len != 0) try writeClusterChain(bpb, first_cluster, data);

    writeShortEntry(root[write_offset .. write_offset + 32], raw_name[0..], 0x20, first_cluster, data.len);
    try writeRootDirectory(bpb, root[0..]);
}

pub fn deleteFile(relative_path: []const u8) Error!void {
    const component = normalizeRelativePath(relative_path) orelse return error.UnsupportedPath;

    var raw_name: [11]u8 = undefined;
    try encodeShortName(component, raw_name[0..]);

    const bpb = try loadBpb();
    var root = [_]u8{0} ** sector_size_bytes;
    _ = try readClusterChain(bpb, bpb.root_cluster, root[0..]);

    var offset: usize = 0;
    while (offset + 32 <= root.len) : (offset += 32) {
        const dirent = root[offset..][0..32];
        const first = dirent[0];
        if (first == 0x00) break;
        if (first == 0xE5 or dirent[11] == 0x0F) continue;
        if (!std.mem.eql(u8, dirent[0..11], raw_name[0..])) continue;
        if ((dirent[11] & 0x10) != 0) return error.IsDirectory;

        const cluster = readDirentCluster(dirent);
        if (cluster >= 2) try freeClusterChain(bpb, cluster);
        @memset(dirent, 0);
        dirent[0] = 0xE5;
        try writeRootDirectory(bpb, root[0..]);
        return;
    }

    return error.FileNotFound;
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
    const bpb = try loadBpb();
    var root = [_]u8{0} ** sector_size_bytes;
    _ = try readClusterChain(bpb, bpb.root_cluster, root[0..]);

    var count: usize = 0;
    var offset: usize = 0;
    while (offset + 32 <= root.len) : (offset += 32) {
        const entry = root[offset..][0..32];
        const first = entry[0];
        if (first == 0x00) break;
        if (first == 0xE5 or entry[11] == 0x0F) continue;

        const kind: std.Io.File.Kind = if ((entry[11] & 0x10) != 0) .directory else .file;
        const cluster_high = readLeU16(entry[20..22]);
        const cluster_low = readLeU16(entry[26..28]);
        const cluster = (@as(u32, cluster_high) << 16) | cluster_low;
        const file_size = readLeU32(entry[28..32]);
        if (count >= max_root_entries) return error.ResponseTooLarge;
        entries_out[count] = .{
            .cluster = cluster,
            .kind = kind,
            .size = file_size,
            .name_len = 0,
        };
        entries_out[count].name_len = formatShortName(entry[0..11], entries_out[count].name[0..]);
        count += 1;
    }
    return count;
}

fn loadBpb() Error!BiosParameterBlock {
    var sector = [_]u8{0} ** sector_size_bytes;
    try readBackendBytes(0, sector[0..]);
    return readBpb(sector[0..]);
}

fn readBpb(bytes: []const u8) Error!BiosParameterBlock {
    if (bytes.len < sector_size_bytes) return error.InvalidFilesystem;
    if (bytes[510] != 0x55 or bytes[511] != 0xAA) return error.InvalidFilesystem;
    if (!std.mem.eql(u8, bytes[82..90], "FAT32   ")) return error.InvalidFilesystem;
    const bytes_per_sector = readLeU16(bytes[11..13]);
    const spc = bytes[13];
    const reserved = readLeU16(bytes[14..16]);
    const fats = bytes[16];
    const fat_size = readLeU32(bytes[36..40]);
    const root = readLeU32(bytes[44..48]);
    const total = readLeU32(bytes[32..36]);
    if (bytes_per_sector != sector_size_bytes or spc == 0 or fats == 0 or fat_size == 0 or root < 2 or total == 0) {
        return error.InvalidFilesystem;
    }
    return .{
        .bytes_per_sector = bytes_per_sector,
        .sectors_per_cluster = spc,
        .reserved_sector_count = reserved,
        .num_fats = fats,
        .fat_size_sectors = fat_size,
        .root_cluster = root,
        .total_sectors = total,
    };
}

fn readClusterChain(bpb: BiosParameterBlock, start_cluster: u32, out: []u8) Error![]const u8 {
    var scratch = [_]u8{0} ** sector_size_bytes;
    var copied: usize = 0;
    var cluster = start_cluster;
    while (copied < out.len) {
        if (cluster < 2) return error.InvalidFilesystem;
        const sector = bpb.clusterToSector(cluster);
        var sector_index: u32 = 0;
        while (sector_index < bpb.sectors_per_cluster and copied < out.len) : (sector_index += 1) {
            try readBackendBytes((sector + sector_index) * sector_size_bytes, scratch[0..]);
            const copy_len = @min(out.len - copied, scratch.len);
            @memcpy(out[copied .. copied + copy_len], scratch[0..copy_len]);
            copied += copy_len;
        }
        if (copied >= out.len) break;
        cluster = try nextCluster(bpb, cluster);
        if (isEndOfChain(cluster)) return error.InvalidFilesystem;
    }
    return out[0..copied];
}

fn nextCluster(bpb: BiosParameterBlock, cluster: u32) Error!u32 {
    const fat_offset = @as(u64, bpb.reserved_sector_count) * sector_size_bytes + (@as(u64, cluster) * 4);
    var bytes: [4]u8 = undefined;
    try readBackendBytes(@as(u32, @intCast(fat_offset)), bytes[0..]);
    return readLeU32(bytes[0..]) & 0x0FFFFFFF;
}

fn isEndOfChain(cluster: u32) bool {
    return cluster >= 0x0FFFFFF8;
}

fn readBackendBytes(byte_offset: u32, out: []u8) Error!void {
    const state = storage_backend.statePtr();
    if (state.mounted == 0 or state.block_size != sector_size_bytes) return error.InvalidFilesystem;
    var scratch = [_]u8{0} ** sector_size_bytes;
    var copied: usize = 0;
    while (copied < out.len) {
        const absolute = @as(usize, byte_offset) + copied;
        const lba = absolute / sector_size_bytes;
        const intra = absolute % sector_size_bytes;
        try storage_backend.readBlocks(@as(u32, @intCast(lba)), scratch[0..]);
        const remaining_in_sector = sector_size_bytes - intra;
        const copy_len = @min(out.len - copied, remaining_in_sector);
        @memcpy(out[copied .. copied + copy_len], scratch[intra .. intra + copy_len]);
        copied += copy_len;
    }
}

fn writeBackendBytes(byte_offset: u32, input: []const u8) Error!void {
    const state = storage_backend.statePtr();
    if (state.mounted == 0 or state.block_size != sector_size_bytes) return error.InvalidFilesystem;
    var scratch = [_]u8{0} ** sector_size_bytes;
    var copied: usize = 0;
    while (copied < input.len) {
        const absolute = @as(usize, byte_offset) + copied;
        const lba = absolute / sector_size_bytes;
        const intra = absolute % sector_size_bytes;
        try storage_backend.readBlocks(@as(u32, @intCast(lba)), scratch[0..]);
        const remaining_in_sector = sector_size_bytes - intra;
        const copy_len = @min(input.len - copied, remaining_in_sector);
        @memcpy(scratch[intra .. intra + copy_len], input[copied .. copied + copy_len]);
        try storage_backend.writeBlocks(@as(u32, @intCast(lba)), scratch[0..]);
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

fn encodeShortName(component: []const u8, out: []u8) Error!void {
    if (out.len < 11) return error.UnsupportedPath;
    @memset(out[0..11], ' ');

    const dot_index = std.mem.indexOfScalar(u8, component, '.');
    const base = if (dot_index) |index| component[0..index] else component;
    const ext = if (dot_index) |index|
        component[index + 1 ..]
    else
        "";

    if (base.len == 0 or base.len > 8 or ext.len > 3) return error.UnsupportedPath;
    for (base, 0..) |byte, index| out[index] = normalizeShortNameByte(byte) catch return error.UnsupportedPath;
    for (ext, 0..) |byte, index| out[8 + index] = normalizeShortNameByte(byte) catch return error.UnsupportedPath;
}

fn normalizeShortNameByte(byte: u8) Error!u8 {
    if (std.ascii.isLower(byte)) return std.ascii.toUpper(byte);
    if (std.ascii.isUpper(byte) or std.ascii.isDigit(byte) or byte == '_' or byte == '-') return byte;
    return error.UnsupportedPath;
}

fn requiredClusterCount(bpb: BiosParameterBlock, byte_len: usize) u32 {
    if (byte_len == 0) return 0;
    const cluster_bytes = @as(usize, bpb.bytes_per_sector) * @as(usize, bpb.sectors_per_cluster);
    return @as(u32, @intCast((byte_len + cluster_bytes - 1) / cluster_bytes));
}

fn clusterLimit(bpb: BiosParameterBlock) u32 {
    const data_sectors = bpb.total_sectors - bpb.firstDataSector();
    return 2 + (data_sectors / @as(u32, bpb.sectors_per_cluster));
}

fn readFatEntry(bpb: BiosParameterBlock, cluster: u32) Error!u32 {
    const fat_offset = @as(u32, bpb.reserved_sector_count) * sector_size_bytes + (cluster * 4);
    var bytes: [4]u8 = undefined;
    try readBackendBytes(fat_offset, bytes[0..]);
    return readLeU32(bytes[0..]) & 0x0FFFFFFF;
}

fn writeFatEntry(bpb: BiosParameterBlock, cluster: u32, value: u32) Error!void {
    var bytes: [4]u8 = undefined;
    writeU32(bytes[0..], value);
    const fat_offset = @as(u32, bpb.reserved_sector_count) * sector_size_bytes + (cluster * 4);
    try writeBackendBytes(fat_offset, bytes[0..]);
}

fn allocateClusterChain(bpb: BiosParameterBlock, cluster_count: u32) Error!u32 {
    if (cluster_count == 0) return 0;

    var first: u32 = 0;
    var previous: u32 = 0;
    var allocated: u32 = 0;
    var cluster: u32 = 2;
    while (cluster < clusterLimit(bpb)) : (cluster += 1) {
        if (try readFatEntry(bpb, cluster) != 0) continue;
        if (first == 0) first = cluster;
        if (previous != 0) try writeFatEntry(bpb, previous, cluster);
        previous = cluster;
        allocated += 1;
        if (allocated == cluster_count) break;
    }

    if (allocated != cluster_count) {
        if (first != 0) try freeClusterChain(bpb, first);
        return error.NoSpace;
    }

    try writeFatEntry(bpb, previous, 0x0FFFFFFF);
    return first;
}

fn freeClusterChain(bpb: BiosParameterBlock, start_cluster: u32) Error!void {
    var cluster = start_cluster;
    while (cluster >= 2 and cluster < 0x0FFFFFF8) {
        const next = try readFatEntry(bpb, cluster);
        try writeFatEntry(bpb, cluster, 0);
        if (next == 0 or next >= 0x0FFFFFF8) break;
        cluster = next;
    }
}

fn writeClusterChain(bpb: BiosParameterBlock, start_cluster: u32, data: []const u8) Error!void {
    var cluster = start_cluster;
    var copied: usize = 0;
    var scratch = [_]u8{0} ** sector_size_bytes;

    while (copied < data.len) {
        const sector = bpb.clusterToSector(cluster);
        var sector_index: u32 = 0;
        while (sector_index < bpb.sectors_per_cluster and copied < data.len) : (sector_index += 1) {
            @memset(scratch[0..], 0);
            const copy_len = @min(data.len - copied, scratch.len);
            @memcpy(scratch[0..copy_len], data[copied .. copied + copy_len]);
            try storage_backend.writeBlocks(sector + sector_index, scratch[0..]);
            copied += copy_len;
        }
        if (copied >= data.len) break;
        cluster = try nextCluster(bpb, cluster);
        if (isEndOfChain(cluster)) return error.InvalidFilesystem;
    }
}

fn writeRootDirectory(bpb: BiosParameterBlock, root: []const u8) Error!void {
    if (root.len != sector_size_bytes) return error.InvalidFilesystem;
    try storage_backend.writeBlocks(bpb.clusterToSector(bpb.root_cluster), root);
}

fn readDirentCluster(dirent: []const u8) u32 {
    const cluster_high = readLeU16(dirent[20..22]);
    const cluster_low = readLeU16(dirent[26..28]);
    return (@as(u32, cluster_high) << 16) | cluster_low;
}

fn writeShortEntry(out: []u8, raw_name: []const u8, attr: u8, cluster: u32, size: usize) void {
    @memset(out, 0);
    @memcpy(out[0..11], raw_name);
    out[11] = attr;
    writeU16(out[20..22], @as(u16, @intCast(cluster >> 16)));
    writeU16(out[26..28], @as(u16, @intCast(cluster & 0xFFFF)));
    writeU32(out[28..32], @as(u32, @intCast(size)));
}

fn formatShortName(raw_name: []const u8, out: []u8) usize {
    var len: usize = 0;
    var index: usize = 0;
    while (index < 8 and raw_name[index] != ' ') : (index += 1) {
        out[len] = raw_name[index];
        len += 1;
    }
    if (raw_name[8] != ' ') {
        out[len] = '.';
        len += 1;
        index = 8;
        while (index < 11 and raw_name[index] != ' ') : (index += 1) {
            out[len] = raw_name[index];
            len += 1;
        }
    }
    return len;
}

fn checksumBytes(bytes: []const u8) u32 {
    return std.hash.Crc32.hash(bytes);
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
    return @as(u16, bytes[0]) | (@as(u16, bytes[1]) << 8);
}

fn readLeU32(bytes: []const u8) u32 {
    return @as(u32, bytes[0]) |
        (@as(u32, bytes[1]) << 8) |
        (@as(u32, bytes[2]) << 16) |
        (@as(u32, bytes[3]) << 24);
}

test "fat32 ro seeds and reads bounded root file" {
    storage_backend.resetForTest();
    virtio_block.testEnableMockDevice(256);
    defer virtio_block.testDisableMockDevice();
    storage_backend.init();

    try seedTestImage();

    const listing = try listRootAlloc(std.testing.allocator, 256);
    defer std.testing.allocator.free(listing);
    try std.testing.expectEqualStrings("file HELLO.TXT 16\n", listing);

    const file = try readFileAlloc(std.testing.allocator, "/HELLO.TXT", 64);
    defer std.testing.allocator.free(file);
    try std.testing.expectEqualStrings(test_file_payload, file);

    const stat = try statSummary("/HELLO.TXT");
    try std.testing.expectEqual(@as(std.Io.File.Kind, .file), stat.kind);
    try std.testing.expectEqual(@as(u64, test_file_payload.len), stat.size);
}

test "fat32 bounded write overwrite and delete stays root-only" {
    storage_backend.resetForTest();
    virtio_block.testEnableMockDevice(256);
    defer virtio_block.testDisableMockDevice();
    storage_backend.init();

    try seedTestImage();
    try writeFile("/WRITE.TXT", "fat32-write", 1);

    var file = try readFileAlloc(std.testing.allocator, "/WRITE.TXT", 64);
    try std.testing.expectEqualStrings("fat32-write", file);
    std.testing.allocator.free(file);

    try writeFile("/WRITE.TXT", "fat32-overwrite", 2);
    file = try readFileAlloc(std.testing.allocator, "/WRITE.TXT", 64);
    defer std.testing.allocator.free(file);
    try std.testing.expectEqualStrings("fat32-overwrite", file);

    const listing = try listRootAlloc(std.testing.allocator, 256);
    defer std.testing.allocator.free(listing);
    try std.testing.expect(std.mem.indexOf(u8, listing, "file WRITE.TXT 15\n") != null);

    try deleteFile("/WRITE.TXT");
    try std.testing.expectEqual(error.FileNotFound, readFileAlloc(std.testing.allocator, "/WRITE.TXT", 64));
    try std.testing.expectError(error.UnsupportedPath, writeFile("/nested/WRITE.TXT", "x", 3));
}
