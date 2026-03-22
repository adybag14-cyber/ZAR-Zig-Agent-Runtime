// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const abi = @import("abi.zig");
const mount_table = @import("mount_table.zig");
const storage_backend = @import("storage_backend.zig");
const tool_layout = @import("tool_layout.zig");

pub const max_entries: usize = 5 + mount_table.max_mounts;
pub const max_name_len: usize = 32;
pub const max_path_len: usize = mount_table.max_target_len;
const max_render_bytes: usize = 8 * 1024;
const zarfs_superblock_lba: u32 = tool_layout.slot_data_lba + @as(u32, tool_layout.slot_count * tool_layout.slot_block_capacity);

pub const LayerKind = enum(u8) {
    persistent = 1,
    tmpfs = 2,
    virtual = 3,
};

pub const FilesystemKind = enum(u8) {
    unknown = 0,
    zarfs = 1,
    tmpfs = 2,
    virtual = 3,
    ext2 = 4,
    fat32 = 5,
};

pub const Entry = struct {
    name_len: u8 = 0,
    path_len: u16 = 0,
    target_len: u16 = 0,
    layer_kind: LayerKind = .persistent,
    filesystem_kind: FilesystemKind = .unknown,
    backend: u8 = 0,
    mounted: u8 = 0,
    block_size: u32 = 0,
    block_count: u32 = 0,
    logical_base_lba: u32 = 0,
    modified_tick: u64 = 0,
    name: [max_name_len]u8 = std.mem.zeroes([max_name_len]u8),
    path: [max_path_len]u8 = std.mem.zeroes([max_path_len]u8),
    target: [max_path_len]u8 = std.mem.zeroes([max_path_len]u8),

    pub fn nameSlice(self: *const @This()) []const u8 {
        return self.name[0..self.name_len];
    }

    pub fn pathSlice(self: *const @This()) []const u8 {
        return self.path[0..self.path_len];
    }

    pub fn targetSlice(self: *const @This()) []const u8 {
        return self.target[0..self.target_len];
    }
};

pub fn entryCount() usize {
    return 5 + mount_table.count();
}

pub fn entry(index: usize) ?Entry {
    ensureStorageReady();
    const persistent_kind = detectPersistentFilesystemKind();
    if (index < 5) {
        return switch (index) {
            0 => synthesizeEntry("root", "/", "/", .persistent, persistent_kind, 0),
            1 => synthesizeEntry("tmp", "/tmp", "/tmp", .tmpfs, .tmpfs, 0),
            2 => synthesizeEntry("proc", "/proc", "/proc", .virtual, .virtual, 0),
            3 => synthesizeEntry("dev", "/dev", "/dev", .virtual, .virtual, 0),
            4 => synthesizeEntry("sys", "/sys", "/sys", .virtual, .virtual, 0),
            else => null,
        };
    }

    const mount_index = index - 5;
    const record = mount_table.entry(mount_index) orelse return null;
    return synthesizeMountEntry(record, persistent_kind);
}

pub fn detectPersistentFilesystemKind() FilesystemKind {
    ensureStorageReady();
    const state = storage_backend.statePtr();
    if (state.mounted == 0 or state.block_size == 0) return .unknown;
    if (probeZarfs()) return .zarfs;
    if (probeFat32()) return .fat32;
    if (probeExt2()) return .ext2;
    return .unknown;
}

pub fn renderAlloc(allocator: std.mem.Allocator, max_bytes: usize) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var index: usize = 0;
    while (index < entryCount()) : (index += 1) {
        const item = entry(index) orelse continue;
        const line = try std.fmt.allocPrint(
            allocator,
            "entry[{d}]=name={s} path={s} target={s} layer={s} backend={s} filesystem={s} mounted={d} block_size={d} block_count={d} logical_base_lba={d}\n",
            .{
                index,
                item.nameSlice(),
                item.pathSlice(),
                item.targetSlice(),
                layerKindName(item.layer_kind),
                backendName(item.backend),
                filesystemKindName(item.filesystem_kind),
                item.mounted,
                item.block_size,
                item.block_count,
                item.logical_base_lba,
            },
        );
        defer allocator.free(line);
        if (out.items.len + line.len > max_bytes) return error.ResponseTooLarge;
        try out.appendSlice(allocator, line);
    }

    return out.toOwnedSlice(allocator);
}

pub fn filesystemKindName(kind: FilesystemKind) []const u8 {
    return switch (kind) {
        .unknown => "unknown",
        .zarfs => "zarfs",
        .tmpfs => "tmpfs",
        .virtual => "virtual",
        .ext2 => "ext2",
        .fat32 => "fat32",
    };
}

pub fn layerKindName(kind: LayerKind) []const u8 {
    return switch (kind) {
        .persistent => "persistent",
        .tmpfs => "tmpfs",
        .virtual => "virtual",
    };
}

pub fn backendName(backend: u8) []const u8 {
    return switch (backend) {
        abi.storage_backend_ram_disk => "ram_disk",
        abi.storage_backend_ata_pio => "ata_pio",
        abi.storage_backend_virtio_block => "virtio_block",
        else => "none",
    };
}

fn synthesizeEntry(
    name: []const u8,
    path: []const u8,
    target: []const u8,
    layer_kind: LayerKind,
    filesystem_kind: FilesystemKind,
    modified_tick: u64,
) Entry {
    var result = Entry{
        .layer_kind = layer_kind,
        .filesystem_kind = filesystem_kind,
        .modified_tick = modified_tick,
    };
    copyInto(result.name[0..], name, &result.name_len);
    copyInto(result.path[0..], path, &result.path_len);
    copyInto(result.target[0..], target, &result.target_len);

    if (layer_kind == .persistent) {
        const state = storage_backend.statePtr();
        result.backend = storage_backend.activeBackend();
        result.mounted = state.mounted;
        result.block_size = state.block_size;
        result.block_count = state.block_count;
        result.logical_base_lba = storage_backend.logicalBaseLba();
    } else {
        result.backend = 0;
        result.mounted = 1;
    }
    return result;
}

fn ensureStorageReady() void {
    const state = storage_backend.statePtr();
    if (state.magic == abi.storage_magic and state.mounted != 0) return;
    storage_backend.init();
}

fn synthesizeMountEntry(record: mount_table.Entry, persistent_kind: FilesystemKind) Entry {
    const alias = record.name[0..record.name_len];
    const target = record.target[0..record.target_len];
    const layer_kind = targetLayerKind(target);
    const filesystem_kind = switch (layer_kind) {
        .persistent => persistent_kind,
        .tmpfs => .tmpfs,
        .virtual => .virtual,
    };

    var mount_path_buf: [max_path_len]u8 = undefined;
    const mount_path = std.fmt.bufPrint(mount_path_buf[0..], "/mnt/{s}", .{alias}) catch "/mnt";

    return synthesizeEntry(alias, mount_path, target, layer_kind, filesystem_kind, record.modified_tick);
}

fn targetLayerKind(target: []const u8) LayerKind {
    if (std.mem.eql(u8, target, "/tmp") or std.mem.startsWith(u8, target, "/tmp/")) return .tmpfs;
    if (std.mem.eql(u8, target, "/proc") or std.mem.startsWith(u8, target, "/proc/")) return .virtual;
    if (std.mem.eql(u8, target, "/dev") or std.mem.startsWith(u8, target, "/dev/")) return .virtual;
    if (std.mem.eql(u8, target, "/sys") or std.mem.startsWith(u8, target, "/sys/")) return .virtual;
    return .persistent;
}

fn copyInto(dest: []u8, src: []const u8, len_out: anytype) void {
    @memcpy(dest[0..src.len], src);
    len_out.* = @as(@TypeOf(len_out.*), @intCast(src.len));
}

fn probeZarfs() bool {
    const state = storage_backend.statePtr();
    if (state.block_size == 0 or zarfs_superblock_lba >= state.block_count) return false;
    if (state.block_size > storage_backend.block_size) return false;

    var block = [_]u8{0} ** storage_backend.block_size;
    storage_backend.readBlocks(zarfs_superblock_lba, block[0..state.block_size]) catch return false;
    const magic = std.mem.readInt(u32, block[0..4], .little);
    return magic == abi.filesystem_magic;
}

fn probeFat32() bool {
    const state = storage_backend.statePtr();
    if (state.block_size < 512 or state.block_count == 0) return false;
    if (state.block_size > storage_backend.block_size) return false;

    var block = [_]u8{0} ** storage_backend.block_size;
    storage_backend.readBlocks(0, block[0..state.block_size]) catch return false;
    if (block[510] != 0x55 or block[511] != 0xAA) return false;
    return std.mem.eql(u8, block[82..90], "FAT32   ");
}

fn probeExt2() bool {
    var magic_buf: [2]u8 = undefined;
    if (!readVolumeBytes(1024 + 56, magic_buf[0..])) return false;
    return magic_buf[0] == 0x53 and magic_buf[1] == 0xEF;
}

fn readVolumeBytes(byte_offset: u64, out: []u8) bool {
    const state = storage_backend.statePtr();
    if (state.mounted == 0 or state.block_size == 0 or state.block_size > storage_backend.block_size) return false;

    var scratch = [_]u8{0} ** storage_backend.block_size;
    const block_size = @as(u64, state.block_size);
    var copied: usize = 0;
    while (copied < out.len) {
        const absolute = byte_offset + copied;
        const lba = absolute / block_size;
        if (lba >= state.block_count) return false;
        const intra = @as(usize, @intCast(absolute % block_size));
        storage_backend.readBlocks(@as(u32, @intCast(lba)), scratch[0..state.block_size]) catch return false;
        const remaining_in_block = @as(usize, state.block_size) - intra;
        const copy_len = @min(out.len - copied, remaining_in_block);
        @memcpy(out[copied .. copied + copy_len], scratch[intra .. intra + copy_len]);
        copied += copy_len;
    }
    return true;
}

test "storage registry detects zarfs on the active backend" {
    storage_backend.resetForTest();
    mount_table.resetForTest();
    storage_backend.init();

    var block = [_]u8{0} ** storage_backend.block_size;
    std.mem.writeInt(u32, block[0..4], abi.filesystem_magic, .little);
    try storage_backend.writeBlocks(zarfs_superblock_lba, block[0..]);

    try std.testing.expectEqual(FilesystemKind.zarfs, detectPersistentFilesystemKind());
}

test "storage registry detects fat32 signatures on the active backend" {
    storage_backend.resetForTest();
    mount_table.resetForTest();
    storage_backend.init();

    var block = [_]u8{0} ** storage_backend.block_size;
    block[0] = 0xEB;
    block[1] = 0x58;
    block[2] = 0x90;
    block[510] = 0x55;
    block[511] = 0xAA;
    @memcpy(block[82..90], "FAT32   ");
    try storage_backend.writeBlocks(0, block[0..]);

    try std.testing.expectEqual(FilesystemKind.fat32, detectPersistentFilesystemKind());
}

test "storage registry detects ext2 signatures on the active backend" {
    storage_backend.resetForTest();
    mount_table.resetForTest();
    storage_backend.init();

    var zero = [_]u8{0} ** storage_backend.block_size;
    try storage_backend.writeBlocks(2, zero[0..]);
    zero[56] = 0x53;
    zero[57] = 0xEF;
    try storage_backend.writeBlocks(2, zero[0..]);

    try std.testing.expectEqual(FilesystemKind.ext2, detectPersistentFilesystemKind());
}

test "storage registry renders synthetic and mounted layers" {
    storage_backend.resetForTest();
    mount_table.resetForTest();
    storage_backend.init();

    var block = [_]u8{0} ** storage_backend.block_size;
    std.mem.writeInt(u32, block[0..4], abi.filesystem_magic, .little);
    try storage_backend.writeBlocks(zarfs_superblock_lba, block[0..]);
    try mount_table.set("boot", "/boot", 10);
    try mount_table.set("cache", "/tmp/cache", 11);

    const rendered = try renderAlloc(std.testing.allocator, max_render_bytes);
    defer std.testing.allocator.free(rendered);

    try std.testing.expect(std.mem.indexOf(u8, rendered, "name=root path=/ target=/ layer=persistent backend=ram_disk filesystem=zarfs") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "name=tmp path=/tmp target=/tmp layer=tmpfs backend=none filesystem=tmpfs") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "name=boot path=/mnt/boot target=/boot layer=persistent backend=ram_disk filesystem=zarfs") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "name=cache path=/mnt/cache target=/tmp/cache layer=tmpfs backend=none filesystem=tmpfs") != null);
}
