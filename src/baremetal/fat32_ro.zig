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

fn normalizeRelativePath(relative_path: []const u8) ?[]const u8 {
    if (relative_path.len == 0 or std.mem.eql(u8, relative_path, "/")) return null;
    if (relative_path[0] != '/') return null;
    const tail = relative_path[1..];
    if (tail.len == 0 or std.mem.indexOfScalar(u8, tail, '/') != null) return null;
    return tail;
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
