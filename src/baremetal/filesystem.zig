// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const builtin = @import("builtin");
const abi = @import("abi.zig");
const storage_backend = @import("storage_backend.zig");
const tool_layout = @import("tool_layout.zig");
const mount_table = @import("mount_table.zig");
const tmpfs = @import("tmpfs.zig");
const virtual_fs = @import("virtual_fs.zig");
const vfs = @import("vfs.zig");

pub const max_entries: usize = 128;
// Keep filesystem paths large enough for hosted absolute temp/workspace roots while
// still leaving each persisted entry at a tidy 256-byte ABI footprint.
pub const max_path_len: usize = 224;
pub const superblock_lba: u32 = tool_layout.slot_data_lba + @as(u32, tool_layout.slot_count * tool_layout.slot_block_capacity);
pub const entry_table_lba: u32 = superblock_lba + 1;

var state: abi.BaremetalFilesystemState = undefined;
var entries: [max_entries]abi.BaremetalFilesystemEntry = std.mem.zeroes([max_entries]abi.BaremetalFilesystemEntry);
var deferred_persist_depth: u32 = 0;

const entry_table_bytes = @sizeOf(@TypeOf(entries));
const mount_registry_root = "/runtime/mounts";
const mount_registry_extension = ".txt";
comptime {
    if (entry_table_bytes % storage_backend.block_size != 0) {
        @compileError("filesystem entry table must be block aligned");
    }
}

pub const entry_table_block_count: u32 = @as(u32, entry_table_bytes / storage_backend.block_size);
pub const data_lba: u32 = entry_table_lba + entry_table_block_count;

const NormalizedPath = struct {
    buf: [max_path_len]u8 = undefined,
    len: usize = 0,

    fn slice(self: *const @This()) []const u8 {
        return self.buf[0..self.len];
    }
};

const ResolvedPath = struct {
    buf: [max_path_len]u8 = undefined,
    len: usize = 0,
    is_mount_root: bool = false,

    fn slice(self: *const @This()) []const u8 {
        if (self.is_mount_root) return mount_table.mount_root;
        return self.buf[0..self.len];
    }
};

pub const Error = storage_backend.Error || std.mem.Allocator.Error || error{
    InvalidPath,
    FileNotFound,
    FileTooBig,
    NotDirectory,
    IsDirectory,
    ReadOnlyPath,
    NoSpace,
    ResponseTooLarge,
    CorruptFilesystem,
};

pub const SimpleStat = vfs.SimpleStat;

const PersistentOps = struct {
    pub fn createDirPath(_: @This(), path: []const u8) Error!void {
        return createPersistentDirPath(path);
    }

    pub fn writeFile(_: @This(), path: []const u8, data: []const u8, tick: u64) Error!void {
        return writePersistentFile(path, data, tick);
    }

    pub fn deleteFile(_: @This(), path: []const u8, tick: u64) Error!void {
        return deletePersistentFile(path, tick);
    }

    pub fn deleteTree(_: @This(), path: []const u8, tick: u64) Error!void {
        return deletePersistentTree(path, tick);
    }

    pub fn readFileAlloc(_: @This(), allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) Error![]u8 {
        return readPersistentFileAlloc(allocator, path, max_bytes);
    }

    pub fn readFile(_: @This(), path: []const u8, buffer: []u8) Error![]const u8 {
        return readPersistentFile(path, buffer);
    }

    pub fn listDirectoryAlloc(_: @This(), allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) Error![]u8 {
        return listPersistentDirectoryAlloc(allocator, path, max_bytes);
    }

    pub fn listRootDirectoryAlloc(_: @This(), allocator: std.mem.Allocator, max_bytes: usize) Error![]u8 {
        return listMergedRootDirectoryAlloc(allocator, max_bytes);
    }

    pub fn statSummary(_: @This(), path: []const u8) Error!SimpleStat {
        return statPersistentSummary(path);
    }

    pub fn beforeStat(_: @This()) void {
        state.stat_count +%= 1;
    }
};

fn resetPersistentState() void {
    state = .{
        .magic = abi.filesystem_magic,
        .api_version = abi.api_version,
        .max_entries = @as(u16, max_entries),
        .formatted = 0,
        .mounted = 0,
        .dirty = 0,
        .active_backend = abi.storage_backend_ram_disk,
        .superblock_lba = superblock_lba,
        .entry_table_lba = entry_table_lba,
        .entry_table_block_count = entry_table_block_count,
        .data_lba = data_lba,
        .used_entries = 0,
        .dir_entries = 0,
        .file_entries = 0,
        .reserved0 = 0,
        .format_count = 0,
        .create_dir_count = 0,
        .write_count = 0,
        .read_count = 0,
        .stat_count = 0,
        .last_entry_id = 0,
        .last_data_lba = data_lba,
        .reserved1 = 0,
        .last_modified_tick = 0,
    };
    @memset(&entries, std.mem.zeroes(abi.BaremetalFilesystemEntry));
    deferred_persist_depth = 0;
    mount_table.clear();
}

pub fn resetForTest() void {
    resetPersistentState();
    mount_table.resetForTest();
    tmpfs.resetForTest();
}

pub fn invalidateForBackendChange() void {
    resetPersistentState();
    mount_table.resetForTest();
    tmpfs.resetForTest();
}

pub fn init() Error!void {
    storage_backend.init();
    if (state.mounted != 0 and state.formatted != 0 and state.active_backend == storage_backend.activeBackend()) {
        return;
    }
    if (try loadExisting()) return;
    try format();
}

pub fn formatActiveBackend() Error!void {
    storage_backend.init();
    try format();
}

pub fn statePtr() *const abi.BaremetalFilesystemState {
    return &state;
}

pub fn mountCount() usize {
    return mount_table.count();
}

pub fn mountEntry(index: usize) ?mount_table.Entry {
    return mount_table.entry(index);
}

pub fn bindMount(name: []const u8, target: []const u8, tick: u64) Error!void {
    try init();
    mount_table.validateName(name) catch return error.InvalidPath;
    mount_table.validateTarget(target) catch return error.InvalidPath;
    try createDirPath(mount_registry_root);

    var path_buf: [max_path_len]u8 = undefined;
    const registry_path = try mountRegistryPath(name, path_buf[0..]);
    try writeFile(registry_path, target, tick);
}

pub fn removeMount(name: []const u8, tick: u64) Error!void {
    try init();
    mount_table.validateName(name) catch return error.InvalidPath;

    var path_buf: [max_path_len]u8 = undefined;
    const registry_path = try mountRegistryPath(name, path_buf[0..]);
    deleteFile(registry_path, tick) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };
}

pub fn mountTarget(name: []const u8, buffer: []u8) ?[]const u8 {
    const target = mount_table.targetForName(name) orelse return null;
    if (target.len > buffer.len) return null;
    @memcpy(buffer[0..target.len], target);
    return buffer[0..target.len];
}

pub fn beginDeferredPersist() Error!void {
    try init();
    deferred_persist_depth +%= 1;
}

pub fn endDeferredPersist() Error!void {
    if (deferred_persist_depth == 0) return;
    deferred_persist_depth -= 1;
    if (deferred_persist_depth == 0 and state.dirty != 0) {
        try persistAll();
    }
}

pub fn entry(index: u32) abi.BaremetalFilesystemEntry {
    if (index >= max_entries) return std.mem.zeroes(abi.BaremetalFilesystemEntry);
    return entries[@as(usize, @intCast(index))];
}

pub fn createDirPath(path: []const u8) Error!void {
    try init();
    var normalized_buf: [max_path_len]u8 = undefined;
    var resolved_buf: [max_path_len]u8 = undefined;
    try vfs.createDirPath(PersistentOps{}, path, normalized_buf[0..], resolved_buf[0..]);
}

pub fn writeFile(path: []const u8, data: []const u8, tick: u64) Error!void {
    try init();
    var normalized_buf: [max_path_len]u8 = undefined;
    var resolved_buf: [max_path_len]u8 = undefined;
    try vfs.writeFile(PersistentOps{}, path, data, tick, normalized_buf[0..], resolved_buf[0..]);
}

pub fn deleteFile(path: []const u8, tick: u64) Error!void {
    try init();
    var normalized_buf: [max_path_len]u8 = undefined;
    var resolved_buf: [max_path_len]u8 = undefined;
    try vfs.deleteFile(PersistentOps{}, path, tick, normalized_buf[0..], resolved_buf[0..]);
}

pub fn deleteTree(path: []const u8, tick: u64) Error!void {
    try init();
    var normalized_buf: [max_path_len]u8 = undefined;
    var resolved_buf: [max_path_len]u8 = undefined;
    try vfs.deleteTree(PersistentOps{}, path, tick, normalized_buf[0..], resolved_buf[0..]);
}

pub fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) Error![]u8 {
    try init();
    var normalized_buf: [max_path_len]u8 = undefined;
    var resolved_buf: [max_path_len]u8 = undefined;
    return vfs.readFileAlloc(PersistentOps{}, allocator, path, max_bytes, normalized_buf[0..], resolved_buf[0..]);
}

pub fn readFile(path: []const u8, buffer: []u8) Error![]const u8 {
    try init();
    var normalized_buf: [max_path_len]u8 = undefined;
    var resolved_buf: [max_path_len]u8 = undefined;
    return vfs.readFile(PersistentOps{}, path, buffer, normalized_buf[0..], resolved_buf[0..]);
}

const DirectoryChild = struct {
    name: [max_path_len]u8 = undefined,
    name_len: usize,
    kind: u8,
    size: u32,
};

pub fn listDirectoryAlloc(allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) Error![]u8 {
    try init();
    var normalized_buf: [max_path_len]u8 = undefined;
    var resolved_buf: [max_path_len]u8 = undefined;
    return vfs.listDirectoryAlloc(PersistentOps{}, allocator, path, max_bytes, normalized_buf[0..], resolved_buf[0..]);
}

fn dirStatInode(value: u64) @TypeOf(@as(std.Io.Dir.Stat, undefined).inode) {
    const T = @TypeOf(@as(std.Io.Dir.Stat, undefined).inode);
    if (T == void) return {};
    return @as(T, @intCast(value));
}

fn dirStatNlink(value: u64) @TypeOf(@as(std.Io.Dir.Stat, undefined).nlink) {
    const T = @TypeOf(@as(std.Io.Dir.Stat, undefined).nlink);
    if (T == void) return {};
    return @as(T, @intCast(value));
}

fn dirStatBlockSize(value: u32) @TypeOf(@as(std.Io.Dir.Stat, undefined).block_size) {
    const T = @TypeOf(@as(std.Io.Dir.Stat, undefined).block_size);
    if (T == void) return {};
    return @as(T, @intCast(value));
}

pub fn statNoFollow(path: []const u8) Error!std.Io.Dir.Stat {
    const summary = try statSummary(path);
    return .{
        .inode = dirStatInode(summary.entry_id),
        .nlink = dirStatNlink(1),
        .size = summary.size,
        .permissions = if (summary.kind == .directory) .default_dir else .default_file,
        .kind = summary.kind,
        .atime = null,
        .mtime = std.Io.Timestamp.fromNanoseconds(@as(i96, @intCast(summary.modified_tick))),
        .ctime = std.Io.Timestamp.fromNanoseconds(@as(i96, @intCast(summary.modified_tick))),
        .block_size = dirStatBlockSize(storage_backend.block_size),
    };
}

pub fn statSummary(path: []const u8) Error!SimpleStat {
    try init();
    var normalized_buf: [max_path_len]u8 = undefined;
    var resolved_buf: [max_path_len]u8 = undefined;
    return vfs.statSummary(PersistentOps{}, path, normalized_buf[0..], resolved_buf[0..]);
}

fn createPersistentDirPath(full: []const u8) Error!void {
    if (full.len == 1) return;

    var index: usize = 1;
    while (index <= full.len) : (index += 1) {
        const at_end = index == full.len;
        if (!at_end and full[index] != '/') continue;

        const prefix = full[0..index];
        if (prefix.len == 0 or (prefix.len == 1 and prefix[0] == '/')) continue;

        const existing = findEntryIndex(prefix);
        if (existing) |entry_index| {
            if (entries[entry_index].kind != abi.filesystem_kind_directory) return error.NotDirectory;
            continue;
        }
        const free_index = try findFreeEntryIndex();
        entries[free_index] = makeEntry(prefix, abi.filesystem_kind_directory, 0, 0, 0, 0, 0);
        state.create_dir_count +%= 1;
        state.dirty = 1;
    }

    recountState();
    if (isMountRegistryPath(full)) try reloadMountTable();
    try maybePersistAll();
}

fn writePersistentFile(full: []const u8, data: []const u8, tick: u64) Error!void {
    if (full.len == 1) return error.InvalidPath;

    const parent = parentSlice(full);
    if (parent.len > 1) {
        const parent_index = findEntryIndex(parent) orelse return error.FileNotFound;
        if (entries[parent_index].kind != abi.filesystem_kind_directory) return error.NotDirectory;
    }

    const block_count_needed = blockCountForBytes(data.len);
    if (findEntryIndex(full)) |entry_index| {
        if (entries[entry_index].kind != abi.filesystem_kind_file) return error.IsDirectory;
        try updateFileEntry(entry_index, data, block_count_needed, tick);
    } else {
        const free_index = try findFreeEntryIndex();
        const start_lba = try allocateExtent(block_count_needed, null);
        try writeExtent(start_lba, block_count_needed, data);
        entries[free_index] = makeEntry(full, abi.filesystem_kind_file, start_lba, @as(u32, @intCast(block_count_needed)), @as(u32, @intCast(data.len)), checksumBytes(data), tick);
    }

    state.write_count +%= 1;
    state.last_modified_tick = tick;
    state.dirty = 1;
    recountState();
    if (isMountRegistryPath(full)) try reloadMountTable();
    try maybePersistAll();
}

fn deletePersistentFile(full: []const u8, tick: u64) Error!void {
    if (full.len == 1) return error.InvalidPath;

    const entry_index = findEntryIndex(full) orelse return error.FileNotFound;
    const record = entries[entry_index];
    if (record.kind != abi.filesystem_kind_file) return error.IsDirectory;

    try zeroExtent(record.start_lba, record.block_count);
    entries[entry_index] = std.mem.zeroes(abi.BaremetalFilesystemEntry);

    state.write_count +%= 1;
    state.last_modified_tick = tick;
    state.dirty = 1;
    recountState();
    if (isMountRegistryPath(full)) try reloadMountTable();
    try maybePersistAll();
}

fn deletePersistentTree(full: []const u8, tick: u64) Error!void {
    if (full.len == 1) return error.InvalidPath;
    _ = findEntryIndex(full) orelse return error.FileNotFound;

    var removed_any = false;
    for (&entries) |*record| {
        if (record.kind == 0) continue;
        const record_path = record.path[0..record.path_len];
        if (!pathMatchesTree(full, record_path)) continue;

        if (record.kind == abi.filesystem_kind_file) {
            try zeroExtent(record.start_lba, record.block_count);
        }
        record.* = std.mem.zeroes(abi.BaremetalFilesystemEntry);
        removed_any = true;
    }
    if (!removed_any) return error.FileNotFound;

    state.write_count +%= 1;
    state.last_modified_tick = tick;
    state.dirty = 1;
    recountState();
    if (isMountRegistryPath(full)) try reloadMountTable();
    try maybePersistAll();
}

fn readPersistentFileAlloc(allocator: std.mem.Allocator, full: []const u8, max_bytes: usize) Error![]u8 {
    const entry_index = findEntryIndex(full) orelse return error.FileNotFound;
    const record = &entries[entry_index];
    if (record.kind != abi.filesystem_kind_file) return error.IsDirectory;
    if (record.byte_len > max_bytes) return error.FileTooBig;

    const byte_len = @as(usize, record.byte_len);
    const buffer = try allocator.alloc(u8, byte_len);
    errdefer allocator.free(buffer);
    if (byte_len == 0) return buffer;

    var scratch = [_]u8{0} ** storage_backend.block_size;
    var remaining = byte_len;
    var out_offset: usize = 0;
    var block_index: u32 = 0;
    while (remaining > 0) : (block_index += 1) {
        try storage_backend.readBlocks(record.start_lba + block_index, scratch[0..]);
        const copy_len = @min(remaining, storage_backend.block_size);
        @memcpy(buffer[out_offset .. out_offset + copy_len], scratch[0..copy_len]);
        out_offset += copy_len;
        remaining -= copy_len;
    }

    state.read_count +%= 1;
    return buffer;
}

fn readPersistentFile(full: []const u8, buffer: []u8) Error![]const u8 {
    const entry_index = findEntryIndex(full) orelse return error.FileNotFound;
    const record = &entries[entry_index];
    if (record.kind != abi.filesystem_kind_file) return error.IsDirectory;
    if (record.byte_len > buffer.len) return error.FileTooBig;

    const byte_len = @as(usize, record.byte_len);
    if (byte_len == 0) {
        state.read_count +%= 1;
        return buffer[0..0];
    }

    var scratch = [_]u8{0} ** storage_backend.block_size;
    var remaining = byte_len;
    var out_offset: usize = 0;
    var block_index: u32 = 0;
    while (remaining > 0) : (block_index += 1) {
        try storage_backend.readBlocks(record.start_lba + block_index, scratch[0..]);
        const copy_len = @min(remaining, storage_backend.block_size);
        @memcpy(buffer[out_offset .. out_offset + copy_len], scratch[0..copy_len]);
        out_offset += copy_len;
        remaining -= copy_len;
    }

    state.read_count +%= 1;
    return buffer[0..byte_len];
}

fn listPersistentDirectoryAlloc(allocator: std.mem.Allocator, full: []const u8, max_bytes: usize) Error![]u8 {
    if (!std.mem.eql(u8, full, "/")) {
        const entry_index = findEntryIndex(full) orelse return error.FileNotFound;
        if (entries[entry_index].kind != abi.filesystem_kind_directory) return error.NotDirectory;
    }

    var children: [max_entries]DirectoryChild = undefined;
    var child_count: usize = 0;

    for (&entries) |*record| {
        if (record.kind == 0) continue;
        const record_path = record.path[0..record.path_len];
        const child_name = directChildName(full, record_path) orelse continue;

        var existing_index: ?usize = null;
        for (children[0..child_count], 0..) |existing, index| {
            if (existing.name_len != child_name.len) continue;
            if (std.mem.eql(u8, existing.name[0..existing.name_len], child_name)) {
                existing_index = index;
                break;
            }
        }

        if (existing_index) |index| {
            if (record.kind == abi.filesystem_kind_directory) {
                children[index].kind = abi.filesystem_kind_directory;
                children[index].size = 0;
            }
            continue;
        }

        children[child_count] = .{
            .name_len = child_name.len,
            .kind = record.kind,
            .size = if (record.kind == abi.filesystem_kind_file) record.byte_len else 0,
        };
        @memcpy(children[child_count].name[0..child_name.len], child_name);
        child_count += 1;
    }

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    for (children[0..child_count]) |child| {
        const line = if (child.kind == abi.filesystem_kind_directory)
            try std.fmt.allocPrint(allocator, "dir {s}\n", .{child.name[0..child.name_len]})
        else
            try std.fmt.allocPrint(allocator, "file {s} {d}\n", .{ child.name[0..child.name_len], child.size });
        defer allocator.free(line);
        if (out.items.len + line.len > max_bytes) return error.ResponseTooLarge;
        try out.appendSlice(allocator, line);
    }
    return out.toOwnedSlice(allocator);
}

fn listMergedRootDirectoryAlloc(allocator: std.mem.Allocator, max_bytes: usize) Error![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    const persistent_listing = try listPersistentDirectoryAlloc(allocator, "/", max_bytes);
    defer allocator.free(persistent_listing);
    try out.appendSlice(allocator, persistent_listing);

    if (mount_table.hasEntries()) {
        const line = "dir mnt\n";
        if (out.items.len + line.len > max_bytes) return error.ResponseTooLarge;
        try out.appendSlice(allocator, line);
    }
    if (!persistentHasDirectChild("/", "tmp")) {
        const line = "dir tmp\n";
        if (out.items.len + line.len > max_bytes) return error.ResponseTooLarge;
        try out.appendSlice(allocator, line);
    }

    const remaining = max_bytes -| out.items.len;
    const virtual_listing = try virtual_fs.listDirectoryAlloc(allocator, "/", remaining);
    defer allocator.free(virtual_listing);
    if (out.items.len + virtual_listing.len > max_bytes) return error.ResponseTooLarge;
    try out.appendSlice(allocator, virtual_listing);

    return out.toOwnedSlice(allocator);
}

fn statPersistentSummary(full: []const u8) Error!SimpleStat {
    if (std.mem.eql(u8, full, "/")) {
        return .{
            .size = 0,
            .checksum = 0,
            .kind = .directory,
            .modified_tick = 0,
            .entry_id = 0,
        };
    }

    const entry_index = findEntryIndex(full) orelse return error.FileNotFound;
    const record = &entries[entry_index];
    return .{
        .size = record.byte_len,
        .checksum = record.checksum,
        .kind = if (record.kind == abi.filesystem_kind_directory) .directory else .file,
        .modified_tick = record.modified_tick,
        .entry_id = record.entry_id,
    };
}

fn persistentHasDirectChild(parent: []const u8, child_name: []const u8) bool {
    for (&entries) |*record| {
        if (record.kind == 0) continue;
        const record_path = record.path[0..record.path_len];
        const direct = directChildName(parent, record_path) orelse continue;
        if (std.mem.eql(u8, direct, child_name)) return true;
    }
    return false;
}

fn updateFileEntry(entry_index: usize, data: []const u8, block_count_needed: usize, tick: u64) Error!void {
    const record = &entries[entry_index];
    if (record.block_count > 0 and (block_count_needed == 0 or block_count_needed > record.block_count)) {
        try zeroExtent(record.start_lba, record.block_count);
    }

    var start_lba: u32 = 0;
    if (block_count_needed == 0) {
        start_lba = 0;
    } else if (record.block_count >= block_count_needed and record.start_lba != 0) {
        start_lba = record.start_lba;
        try writeExtent(start_lba, block_count_needed, data);
        if (record.block_count > block_count_needed) {
            try zeroExtent(start_lba + @as(u32, @intCast(block_count_needed)), record.block_count - @as(u32, @intCast(block_count_needed)));
        }
    } else {
        start_lba = try allocateExtent(block_count_needed, entry_index);
        try writeExtent(start_lba, block_count_needed, data);
    }

    entries[entry_index] = makeEntry(record.path[0..record.path_len], abi.filesystem_kind_file, start_lba, @as(u32, @intCast(block_count_needed)), @as(u32, @intCast(data.len)), checksumBytes(data), tick);
    entries[entry_index].entry_id = record.entry_id;
}

fn format() Error!void {
    resetPersistentState();
    state.format_count +%= 1;
    state.formatted = 1;
    state.mounted = 1;
    state.active_backend = storage_backend.activeBackend();
    recountState();
    try persistAll();
}

fn loadExisting() Error!bool {
    var header_block = [_]u8{0} ** storage_backend.block_size;
    try storage_backend.readBlocks(superblock_lba, header_block[0..]);

    var persisted: abi.BaremetalFilesystemState = undefined;
    @memcpy(std.mem.asBytes(&persisted), header_block[0..@sizeOf(abi.BaremetalFilesystemState)]);
    if (persisted.magic != abi.filesystem_magic) return false;
    if (persisted.api_version != abi.api_version or
        persisted.max_entries != max_entries or
        persisted.superblock_lba != superblock_lba or
        persisted.entry_table_lba != entry_table_lba or
        persisted.entry_table_block_count != entry_table_block_count or
        persisted.data_lba != data_lba)
    {
        return error.CorruptFilesystem;
    }

    var entry_bytes = [_]u8{0} ** entry_table_bytes;
    var block_index: u32 = 0;
    while (block_index < entry_table_block_count) : (block_index += 1) {
        const offset = @as(usize, @intCast(block_index)) * storage_backend.block_size;
        try storage_backend.readBlocks(entry_table_lba + block_index, entry_bytes[offset .. offset + storage_backend.block_size]);
    }

    state = persisted;
    @memcpy(std.mem.sliceAsBytes(entries[0..]), entry_bytes[0..entry_table_bytes]);
    state.formatted = 1;
    state.mounted = 1;
    state.active_backend = storage_backend.activeBackend();
    state.dirty = 0;
    recountState();
    try reloadMountTable();
    return true;
}

fn persistAll() Error!void {
    state.formatted = 1;
    state.mounted = 1;
    state.active_backend = storage_backend.activeBackend();
    state.dirty = 0;
    try persistState();
    try persistEntries();
    try storage_backend.flush();
}

fn maybePersistAll() Error!void {
    if (deferred_persist_depth != 0) return;
    try persistAll();
}

fn persistState() Error!void {
    var block = [_]u8{0} ** storage_backend.block_size;
    @memcpy(block[0..@sizeOf(abi.BaremetalFilesystemState)], std.mem.asBytes(&state));
    try storage_backend.writeBlocks(superblock_lba, block[0..]);
}

fn persistEntries() Error!void {
    const bytes = std.mem.sliceAsBytes(entries[0..]);
    var block_index: u32 = 0;
    while (block_index < entry_table_block_count) : (block_index += 1) {
        const offset = @as(usize, @intCast(block_index)) * storage_backend.block_size;
        try storage_backend.writeBlocks(entry_table_lba + block_index, bytes[offset .. offset + storage_backend.block_size]);
    }
}

fn resolvePath(path: []const u8) Error!ResolvedPath {
    var resolved: ResolvedPath = .{};
    if (std.mem.eql(u8, path, mount_table.mount_root)) {
        resolved.is_mount_root = true;
        return resolved;
    }

    if (mount_table.resolve(path, resolved.buf[0..])) |aliased| {
        resolved.len = aliased.len;
        return resolved;
    }
    if (isMountPath(path)) return error.FileNotFound;

    resolved.len = path.len;
    @memcpy(resolved.buf[0..path.len], path);
    return resolved;
}

fn isMountPath(path: []const u8) bool {
    if (!std.mem.startsWith(u8, path, mount_table.mount_root)) return false;
    return path.len == mount_table.mount_root.len or
        (path.len > mount_table.mount_root.len and path[mount_table.mount_root.len] == '/');
}

fn isMountRegistryPath(path: []const u8) bool {
    if (!std.mem.startsWith(u8, path, mount_registry_root)) return false;
    return path.len == mount_registry_root.len or
        (path.len > mount_registry_root.len and path[mount_registry_root.len] == '/');
}

fn mountRegistryPath(name: []const u8, out: []u8) Error![]const u8 {
    const needed = mount_registry_root.len + 1 + name.len + mount_registry_extension.len;
    if (needed > out.len) return error.InvalidPath;
    @memcpy(out[0..mount_registry_root.len], mount_registry_root);
    out[mount_registry_root.len] = '/';
    @memcpy(out[mount_registry_root.len + 1 .. mount_registry_root.len + 1 + name.len], name);
    @memcpy(
        out[mount_registry_root.len + 1 + name.len .. needed],
        mount_registry_extension,
    );
    return out[0..needed];
}

fn mountAliasFromRegistryPath(path: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, path, mount_registry_root)) return null;
    if (path.len <= mount_registry_root.len or path[mount_registry_root.len] != '/') return null;
    const child = path[mount_registry_root.len + 1 ..];
    if (child.len == 0 or std.mem.indexOfScalar(u8, child, '/') != null) return null;
    if (!std.mem.endsWith(u8, child, mount_registry_extension)) return null;
    const alias = child[0 .. child.len - mount_registry_extension.len];
    mount_table.validateName(alias) catch return null;
    return alias;
}

fn reloadMountTable() Error!void {
    mount_table.clear();
    for (&entries) |*record| {
        if (record.kind != abi.filesystem_kind_file) continue;
        const alias = mountAliasFromRegistryPath(record.path[0..record.path_len]) orelse continue;
        var target_buf: [mount_table.max_target_len]u8 = undefined;
        const target = try readRecord(record, target_buf[0..]);
        mount_table.set(alias, target, record.modified_tick) catch return error.CorruptFilesystem;
    }
}

fn readRecord(record: *const abi.BaremetalFilesystemEntry, buffer: []u8) Error![]const u8 {
    if (record.kind != abi.filesystem_kind_file) return error.IsDirectory;
    if (record.byte_len > buffer.len) return error.FileTooBig;

    const byte_len = @as(usize, record.byte_len);
    if (byte_len == 0) return buffer[0..0];

    var scratch = [_]u8{0} ** storage_backend.block_size;
    var remaining = byte_len;
    var out_offset: usize = 0;
    var block_index: u32 = 0;
    while (remaining > 0) : (block_index += 1) {
        try storage_backend.readBlocks(record.start_lba + block_index, scratch[0..]);
        const copy_len = @min(remaining, storage_backend.block_size);
        @memcpy(buffer[out_offset .. out_offset + copy_len], scratch[0..copy_len]);
        out_offset += copy_len;
        remaining -= copy_len;
    }
    return buffer[0..byte_len];
}

fn listMountDirectoryAlloc(allocator: std.mem.Allocator, max_bytes: usize) Error![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var index: usize = 0;
    while (index < mount_table.max_mounts) : (index += 1) {
        const record = mount_table.entry(index) orelse continue;
        const line = try std.fmt.allocPrint(allocator, "dir {s}\n", .{record.name[0..record.name_len]});
        defer allocator.free(line);
        if (out.items.len + line.len > max_bytes) return error.ResponseTooLarge;
        try out.appendSlice(allocator, line);
    }

    return out.toOwnedSlice(allocator);
}

fn normalizePath(path: []const u8) Error!NormalizedPath {
    if (path.len == 0) return error.InvalidPath;
    var normalized: NormalizedPath = .{};
    normalized.buf[0] = '/';
    normalized.len = 1;

    var index: usize = 0;
    while (index < path.len and path[index] == '/') : (index += 1) {}
    if (index == path.len) return normalized;

    while (index < path.len) {
        const start = index;
        while (index < path.len and path[index] != '/') : (index += 1) {}
        const segment = path[start..index];
        if (segment.len == 0) continue;
        if (std.mem.eql(u8, segment, ".") or std.mem.eql(u8, segment, "..")) return error.InvalidPath;

        if (normalized.len != 1) {
            if (normalized.len >= max_path_len) return error.InvalidPath;
            normalized.buf[normalized.len] = '/';
            normalized.len += 1;
        }
        if (normalized.len + segment.len > max_path_len) return error.InvalidPath;
        @memcpy(normalized.buf[normalized.len .. normalized.len + segment.len], segment);
        normalized.len += segment.len;

        while (index < path.len and path[index] == '/') : (index += 1) {}
    }

    return normalized;
}

fn findEntryIndex(path: []const u8) ?usize {
    for (&entries, 0..) |*record, index| {
        if (record.kind == 0 or record.path_len != path.len) continue;
        if (std.mem.eql(u8, record.path[0..record.path_len], path)) return index;
    }
    return null;
}

fn findFreeEntryIndex() Error!usize {
    for (&entries, 0..) |*record, index| {
        if (record.kind == 0) return index;
    }
    return error.NoSpace;
}

fn makeEntry(path: []const u8, kind: u8, start_lba: u32, block_count_value: u32, byte_len: u32, checksum: u32, tick: u64) abi.BaremetalFilesystemEntry {
    var record = std.mem.zeroes(abi.BaremetalFilesystemEntry);
    state.last_entry_id +%= 1;
    record.entry_id = state.last_entry_id;
    record.path_len = @as(u16, @intCast(path.len));
    record.kind = kind;
    record.flags = 0;
    record.start_lba = start_lba;
    record.block_count = block_count_value;
    record.byte_len = byte_len;
    record.checksum = checksum;
    record.modified_tick = tick;
    @memcpy(record.path[0..path.len], path);
    return record;
}

fn recountState() void {
    var used_entries: u16 = 0;
    var dir_entries: u16 = 0;
    var file_entries: u16 = 0;
    var last_lba = data_lba;

    for (&entries) |*record| {
        if (record.kind == 0) continue;
        used_entries += 1;
        if (record.kind == abi.filesystem_kind_directory) {
            dir_entries += 1;
            continue;
        }
        file_entries += 1;
        if (record.block_count > 0) {
            const record_last = record.start_lba + record.block_count - 1;
            if (record_last > last_lba) last_lba = record_last;
        }
    }

    state.used_entries = used_entries;
    state.dir_entries = dir_entries;
    state.file_entries = file_entries;
    state.last_data_lba = last_lba;
}

fn blockCountForBytes(byte_len: usize) usize {
    if (byte_len == 0) return 0;
    return ((byte_len - 1) / storage_backend.block_size) + 1;
}

fn allocateExtent(blocks_needed: usize, skip_index: ?usize) Error!u32 {
    if (blocks_needed == 0) return 0;
    const total_blocks = @as(u32, @intCast(storage_backend.block_count));
    const needed_u32 = @as(u32, @intCast(blocks_needed));
    if (total_blocks <= data_lba or total_blocks - data_lba < needed_u32) return error.NoSpace;

    var candidate = data_lba;
    const final_start = total_blocks - needed_u32;
    while (candidate <= final_start) : (candidate += 1) {
        var overlaps = false;
        for (&entries, 0..) |*record, index| {
            if (skip_index != null and index == skip_index.?) continue;
            if (record.kind != abi.filesystem_kind_file or record.block_count == 0) continue;
            const other_start = record.start_lba;
            const other_end = record.start_lba + record.block_count;
            const candidate_end = candidate + needed_u32;
            if (candidate < other_end and candidate_end > other_start) {
                overlaps = true;
                break;
            }
        }
        if (!overlaps) return candidate;
    }
    return error.NoSpace;
}

fn writeExtent(start_lba: u32, block_count_value: usize, data: []const u8) Error!void {
    if (block_count_value == 0) return;
    var scratch = [_]u8{0} ** storage_backend.block_size;
    var remaining = data.len;
    var input_offset: usize = 0;
    var block_index: usize = 0;
    while (block_index < block_count_value) : (block_index += 1) {
        @memset(scratch[0..], 0);
        const copy_len = @min(remaining, storage_backend.block_size);
        if (copy_len > 0) {
            @memcpy(scratch[0..copy_len], data[input_offset .. input_offset + copy_len]);
            remaining -= copy_len;
            input_offset += copy_len;
        }
        try storage_backend.writeBlocks(start_lba + @as(u32, @intCast(block_index)), scratch[0..]);
    }
}

fn zeroExtent(start_lba: u32, block_count_value: u32) Error!void {
    if (block_count_value == 0) return;
    var zero_block = [_]u8{0} ** storage_backend.block_size;
    var block_index: u32 = 0;
    while (block_index < block_count_value) : (block_index += 1) {
        try storage_backend.writeBlocks(start_lba + block_index, zero_block[0..]);
    }
}

fn checksumBytes(bytes: []const u8) u32 {
    var total: u32 = 0;
    for (bytes) |byte| total +%= byte;
    return total;
}

fn parentSlice(path: []const u8) []const u8 {
    if (path.len <= 1) return "/";
    if (std.mem.lastIndexOfScalar(u8, path[1..], '/')) |relative_index| {
        return path[0 .. relative_index + 1];
    }
    return "/";
}

fn directChildName(parent: []const u8, candidate: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, parent, "/")) {
        if (candidate.len <= 1 or candidate[0] != '/') return null;
        const rest = candidate[1..];
        const end_index = std.mem.indexOfScalar(u8, rest, '/') orelse rest.len;
        if (end_index == 0) return null;
        return rest[0..end_index];
    }

    if (!std.mem.startsWith(u8, candidate, parent)) return null;
    if (candidate.len <= parent.len or candidate[parent.len] != '/') return null;

    const rest = candidate[parent.len + 1 ..];
    if (rest.len == 0) return null;
    const end_index = std.mem.indexOfScalar(u8, rest, '/') orelse rest.len;
    if (end_index == 0) return null;
    return rest[0..end_index];
}

fn pathMatchesTree(root: []const u8, candidate: []const u8) bool {
    if (!std.mem.startsWith(u8, candidate, root)) return false;
    if (candidate.len == root.len) return true;
    return candidate[root.len] == '/';
}

test "filesystem persists path-based files on the ram disk" {
    storage_backend.resetForTest();
    resetForTest();
    try init();

    try createDirPath("/runtime/state");
    try writeFile("/runtime/state/agent.json", "{\"ok\":true}", 77);
    const stat = try statNoFollow("/runtime/state/agent.json");
    try std.testing.expectEqual(@as(std.Io.File.Kind, .file), stat.kind);
    try std.testing.expectEqual(@as(u64, 11), stat.size);
    try std.testing.expectEqual(@as(u16, 2), state.dir_entries);
    try std.testing.expectEqual(@as(u16, 1), state.file_entries);

    const content = try readFileAlloc(std.testing.allocator, "/runtime/state/agent.json", 64);
    defer std.testing.allocator.free(content);
    try std.testing.expectEqualStrings("{\"ok\":true}", content);

    resetForTest();
    try init();
    const reloaded = try readFileAlloc(std.testing.allocator, "/runtime/state/agent.json", 64);
    defer std.testing.allocator.free(reloaded);
    try std.testing.expectEqualStrings("{\"ok\":true}", reloaded);
}

test "filesystem persists path-based files on the ata backend" {
    storage_backend.resetForTest();
    resetForTest();
    @import("ata_pio_disk.zig").testEnableMockDevice(8192);
    @import("ata_pio_disk.zig").testInstallMockMbrPartition(2048, 4096, 0x83);
    defer @import("ata_pio_disk.zig").testDisableMockDevice();

    try init();
    try createDirPath("/tools/cache");
    try writeFile("/tools/cache/tool.txt", "edge", 99);
    try std.testing.expectEqual(@as(u8, abi.storage_backend_ata_pio), state.active_backend);
    try std.testing.expectEqual(@as(u32, 2048), @import("ata_pio_disk.zig").logicalBaseLba());

    const content = try readFileAlloc(std.testing.allocator, "/tools/cache/tool.txt", 64);
    defer std.testing.allocator.free(content);
    try std.testing.expectEqualStrings("edge", content);

    resetForTest();
    try init();
    const stat = try statNoFollow("/tools/cache/tool.txt");
    try std.testing.expectEqual(@as(std.Io.File.Kind, .file), stat.kind);
    try std.testing.expectEqual(@as(u64, 4), stat.size);
}

test "filesystem init preserves deferred in-memory state on the active backend" {
    storage_backend.resetForTest();
    resetForTest();
    @import("ata_pio_disk.zig").testEnableMockDevice(8192);
    @import("ata_pio_disk.zig").testInstallMockMbrPartition(2048, 4096, 0x83);
    defer @import("ata_pio_disk.zig").testDisableMockDevice();

    try init();
    try beginDeferredPersist();
    defer endDeferredPersist() catch {};
    try createDirPath("/runtime/state");
    try writeFile("/runtime/state/deferred.txt", "edge", 101);
    try std.testing.expectEqual(@as(u8, 1), state.dirty);

    try init();
    const before_flush = try readFileAlloc(std.testing.allocator, "/runtime/state/deferred.txt", 64);
    defer std.testing.allocator.free(before_flush);
    try std.testing.expectEqualStrings("edge", before_flush);
    try std.testing.expectEqual(@as(u8, 1), state.dirty);

    try endDeferredPersist();
    resetForTest();
    try init();
    const reloaded = try readFileAlloc(std.testing.allocator, "/runtime/state/deferred.txt", 64);
    defer std.testing.allocator.free(reloaded);
    try std.testing.expectEqualStrings("edge", reloaded);
}

test "filesystem lists direct child entries only" {
    storage_backend.resetForTest();
    resetForTest();
    try init();

    try createDirPath("/packages/demo/bin");
    try createDirPath("/packages/demo/meta");
    try writeFile("/packages/demo/bin/main.oc", "edge", 7);
    try writeFile("/packages/demo/meta/package.txt", "meta", 7);

    const root_listing = try listDirectoryAlloc(std.testing.allocator, "/", 64);
    defer std.testing.allocator.free(root_listing);
    try std.testing.expectEqualStrings("dir packages\ndir tmp\ndir dev\ndir proc\ndir sys\n", root_listing);

    const packages_listing = try listDirectoryAlloc(std.testing.allocator, "/packages", 64);
    defer std.testing.allocator.free(packages_listing);
    try std.testing.expectEqualStrings("dir demo\n", packages_listing);

    const demo_listing = try listDirectoryAlloc(std.testing.allocator, "/packages/demo", 64);
    defer std.testing.allocator.free(demo_listing);
    try std.testing.expectEqualStrings("dir bin\ndir meta\n", demo_listing);

    const bin_listing = try listDirectoryAlloc(std.testing.allocator, "/packages/demo/bin", 64);
    defer std.testing.allocator.free(bin_listing);
    try std.testing.expectEqualStrings("file main.oc 4\n", bin_listing);
}

test "filesystem exposes virtual proc sys and dev overlays" {
    storage_backend.resetForTest();
    resetForTest();
    try init();

    var runtime = try @import("runtime_bridge.zig").initRuntime(std.testing.allocator);
    defer runtime.deinit();

    var exec_result = try runtime.execRunFromFrame(
        std.testing.allocator,
        "{\"id\":\"proc-exec\",\"method\":\"exec.run\",\"params\":{\"sessionId\":\"sess-proc\",\"command\":\"echo proc-ready\",\"timeoutMs\":1000}}",
    );
    defer exec_result.deinit(std.testing.allocator);
    try std.testing.expect(exec_result.ok);

    const proc_root_listing = try listDirectoryAlloc(std.testing.allocator, "/proc", 256);
    defer std.testing.allocator.free(proc_root_listing);
    try std.testing.expect(std.mem.indexOf(u8, proc_root_listing, "dir runtime\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, proc_root_listing, "file version ") != null);

    const sessions_listing = try listDirectoryAlloc(std.testing.allocator, "/proc/runtime/sessions", 256);
    defer std.testing.allocator.free(sessions_listing);
    try std.testing.expect(std.mem.indexOf(u8, sessions_listing, "file sess-proc ") != null);

    const snapshot = try readFileAlloc(std.testing.allocator, "/proc/runtime/snapshot", 512);
    defer std.testing.allocator.free(snapshot);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "state_path=/runtime/state/runtime-state.json") != null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "sessions=1") != null);

    const session_info = try readFileAlloc(std.testing.allocator, "/proc/runtime/sessions/sess-proc", 512);
    defer std.testing.allocator.free(session_info);
    try std.testing.expect(std.mem.indexOf(u8, session_info, "id=sess-proc") != null);
    try std.testing.expect(std.mem.indexOf(u8, session_info, "last_message=echo proc-ready") != null);

    const storage_state = try readFileAlloc(std.testing.allocator, "/sys/storage/state", 512);
    defer std.testing.allocator.free(storage_state);
    try std.testing.expect(std.mem.indexOf(u8, storage_state, "backend=ram_disk") != null);
    try std.testing.expect(std.mem.indexOf(u8, storage_state, "detected_filesystem=zarfs") != null);

    const dev_listing = try listDirectoryAlloc(std.testing.allocator, "/dev", 256);
    defer std.testing.allocator.free(dev_listing);
    try std.testing.expect(std.mem.indexOf(u8, dev_listing, "dir storage\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, dev_listing, "dir display\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, dev_listing, "dir net\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, dev_listing, "file null 0\n") != null);

    const dev_storage_state = try readFileAlloc(std.testing.allocator, "/dev/storage/state", 512);
    defer std.testing.allocator.free(dev_storage_state);
    try std.testing.expect(std.mem.indexOf(u8, dev_storage_state, "backend=ram_disk") != null);

    const dev_storage_listing = try listDirectoryAlloc(std.testing.allocator, "/dev/storage", 256);
    defer std.testing.allocator.free(dev_storage_listing);
    try std.testing.expect(std.mem.indexOf(u8, dev_storage_listing, "file backends ") != null);
    try std.testing.expect(std.mem.indexOf(u8, dev_storage_listing, "file filesystems ") != null);
    try std.testing.expect(std.mem.indexOf(u8, dev_storage_listing, "file registry ") != null);

    const dev_storage_backends = try readFileAlloc(std.testing.allocator, "/dev/storage/backends", 1024);
    defer std.testing.allocator.free(dev_storage_backends);
    try std.testing.expect(std.mem.indexOf(u8, dev_storage_backends, "backend[0]=name=ram_disk backend=ram_disk available=1 selected=1 mounted=1") != null);

    const dev_storage_filesystems = try readFileAlloc(std.testing.allocator, "/dev/storage/filesystems", 512);
    defer std.testing.allocator.free(dev_storage_filesystems);
    try std.testing.expect(std.mem.indexOf(u8, dev_storage_filesystems, "filesystem=ext2 detect=1 mount=0 write=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, dev_storage_filesystems, "filesystem=fat32 detect=1 mount=0 write=0") != null);

    const dev_display_state = try readFileAlloc(std.testing.allocator, "/dev/display/state", 512);
    defer std.testing.allocator.free(dev_display_state);
    try std.testing.expect(std.mem.indexOf(u8, dev_display_state, "outputs=") != null);

    const sys_listing = try listDirectoryAlloc(std.testing.allocator, "/sys", 256);
    defer std.testing.allocator.free(sys_listing);
    try std.testing.expect(std.mem.indexOf(u8, sys_listing, "dir kernel\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, sys_listing, "dir storage\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, sys_listing, "dir display\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, sys_listing, "dir net\n") != null);

    const sys_storage_listing = try listDirectoryAlloc(std.testing.allocator, "/sys/storage", 256);
    defer std.testing.allocator.free(sys_storage_listing);
    try std.testing.expect(std.mem.indexOf(u8, sys_storage_listing, "file backends ") != null);
    try std.testing.expect(std.mem.indexOf(u8, sys_storage_listing, "file filesystems ") != null);
    try std.testing.expect(std.mem.indexOf(u8, sys_storage_listing, "file registry ") != null);

    const sys_storage_backends = try readFileAlloc(std.testing.allocator, "/sys/storage/backends", 1024);
    defer std.testing.allocator.free(sys_storage_backends);
    try std.testing.expect(std.mem.indexOf(u8, sys_storage_backends, "filesystem=zarfs") != null);

    const sys_storage_filesystems = try readFileAlloc(std.testing.allocator, "/sys/storage/filesystems", 512);
    defer std.testing.allocator.free(sys_storage_filesystems);
    try std.testing.expect(std.mem.indexOf(u8, sys_storage_filesystems, "filesystem=zarfs detect=1 mount=1 write=1") != null);

    const proc_stat = try statSummary("/proc/runtime/snapshot");
    try std.testing.expectEqual(@as(std.Io.File.Kind, .file), proc_stat.kind);
    try std.testing.expect(proc_stat.size != 0);

    const sys_stat = try statSummary("/sys");
    try std.testing.expectEqual(@as(std.Io.File.Kind, .directory), sys_stat.kind);
}

test "filesystem rejects writes under virtual proc and sys trees" {
    storage_backend.resetForTest();
    resetForTest();
    try init();

    try std.testing.expectError(error.ReadOnlyPath, createDirPath("/dev/net/new"));
    try std.testing.expectError(error.ReadOnlyPath, createDirPath("/proc/runtime/new"));
    try std.testing.expectError(error.ReadOnlyPath, writeFile("/dev/storage/state", "nope", 0));
    try std.testing.expectError(error.ReadOnlyPath, writeFile("/sys/net/state", "nope", 0));
    try std.testing.expectError(error.ReadOnlyPath, deleteFile("/dev/null", 0));
    try std.testing.expectError(error.ReadOnlyPath, deleteFile("/proc/version", 0));
    try std.testing.expectError(error.ReadOnlyPath, deleteTree("/dev/display", 0));
    try std.testing.expectError(error.ReadOnlyPath, deleteTree("/sys/display", 0));
}

test "filesystem routes /tmp through bounded non-persistent tmpfs" {
    storage_backend.resetForTest();
    resetForTest();
    try init();

    const root_listing = try listDirectoryAlloc(std.testing.allocator, "/", 128);
    defer std.testing.allocator.free(root_listing);
    try std.testing.expect(std.mem.indexOf(u8, root_listing, "dir tmp\n") != null);

    try createDirPath("/tmp/cache");
    try writeFile("/tmp/cache/demo.txt", "ephemeral", 11);

    const content = try readFileAlloc(std.testing.allocator, "/tmp/cache/demo.txt", 64);
    defer std.testing.allocator.free(content);
    try std.testing.expectEqualStrings("ephemeral", content);

    const listing = try listDirectoryAlloc(std.testing.allocator, "/tmp/cache", 64);
    defer std.testing.allocator.free(listing);
    try std.testing.expectEqualStrings("file demo.txt 9\n", listing);
}

test "filesystem tmpfs state does not survive reset and re-init" {
    storage_backend.resetForTest();
    resetForTest();
    try init();

    try createDirPath("/tmp/cache");
    try writeFile("/tmp/cache/demo.txt", "volatile", 1);

    resetForTest();
    try init();
    try std.testing.expectError(error.FileNotFound, statSummary("/tmp/cache/demo.txt"));
}

test "filesystem deletes files and persists the removal" {
    storage_backend.resetForTest();
    resetForTest();
    try init();

    try createDirPath("/runtime/state");
    try writeFile("/runtime/state/delete-me.txt", "edge", 7);
    try deleteFile("/runtime/state/delete-me.txt", 9);
    try std.testing.expectError(error.FileNotFound, readFileAlloc(std.testing.allocator, "/runtime/state/delete-me.txt", 64));

    resetForTest();
    try init();
    try std.testing.expectError(error.FileNotFound, readFileAlloc(std.testing.allocator, "/runtime/state/delete-me.txt", 64));
}

test "filesystem recursively deletes directory trees and persists the removal" {
    storage_backend.resetForTest();
    resetForTest();
    try init();

    try createDirPath("/packages/demo/bin");
    try createDirPath("/packages/demo/assets/config");
    try writeFile("/packages/demo/bin/main.oc", "echo demo", 7);
    try writeFile("/packages/demo/assets/config/app.json", "{\"mode\":\"tcp\"}", 8);

    try deleteTree("/packages/demo", 9);
    try std.testing.expectError(error.FileNotFound, statSummary("/packages/demo"));
    try std.testing.expectError(error.FileNotFound, readFileAlloc(std.testing.allocator, "/packages/demo/bin/main.oc", 64));
    try std.testing.expectError(error.FileNotFound, readFileAlloc(std.testing.allocator, "/packages/demo/assets/config/app.json", 64));

    const packages_listing = try listDirectoryAlloc(std.testing.allocator, "/packages", 64);
    defer std.testing.allocator.free(packages_listing);
    try std.testing.expectEqualStrings("", packages_listing);

    resetForTest();
    try init();
    try std.testing.expectError(error.FileNotFound, statSummary("/packages/demo"));
    const reloaded_listing = try listDirectoryAlloc(std.testing.allocator, "/packages", 64);
    defer std.testing.allocator.free(reloaded_listing);
    try std.testing.expectEqualStrings("", reloaded_listing);
}

test "filesystem accepts longer hosted-style absolute paths within budget" {
    storage_backend.resetForTest();
    resetForTest();
    try init();

    const long_path =
        "/home/runner/work/ZAR-Zig-Agent-Runtime/ZAR-Zig-Agent-Runtime/.zig-cache/runtime-state/sessions/sess-phase3/runtime-file.txt";
    try createDirPath("/home/runner/work/ZAR-Zig-Agent-Runtime/ZAR-Zig-Agent-Runtime/.zig-cache/runtime-state/sessions/sess-phase3");
    try writeFile(long_path, "phase3-data", 11);

    const content = try readFileAlloc(std.testing.allocator, long_path, 64);
    defer std.testing.allocator.free(content);
    try std.testing.expectEqualStrings("phase3-data", content);
}

test "filesystem binds mounted aliases and exposes the /mnt root" {
    storage_backend.resetForTest();
    resetForTest();
    try init();

    try createDirPath("/boot");
    try writeFile("/boot/loader.cfg", "loader=edge", 12);
    try bindMount("boot", "/boot", 13);

    const root_listing = try listDirectoryAlloc(std.testing.allocator, "/", 128);
    defer std.testing.allocator.free(root_listing);
    try std.testing.expect(std.mem.indexOf(u8, root_listing, "dir mnt\n") != null);

    const mount_listing = try listDirectoryAlloc(std.testing.allocator, "/mnt", 128);
    defer std.testing.allocator.free(mount_listing);
    try std.testing.expectEqualStrings("dir boot\n", mount_listing);

    const mounted = try readFileAlloc(std.testing.allocator, "/mnt/boot/loader.cfg", 64);
    defer std.testing.allocator.free(mounted);
    try std.testing.expectEqualStrings("loader=edge", mounted);

    const mounted_stat = try statSummary("/mnt/boot");
    try std.testing.expectEqual(@as(std.Io.File.Kind, .directory), mounted_stat.kind);
}

test "filesystem persists mount aliases across reset and re-init" {
    storage_backend.resetForTest();
    resetForTest();
    @import("virtio_block.zig").testEnableMockDevice(8192);
    defer @import("virtio_block.zig").testDisableMockDevice();
    try init();

    try createDirPath("/runtime/state");
    try writeFile("/runtime/state/mounted.txt", "persisted", 20);
    try bindMount("runtime", "/runtime", 21);

    resetForTest();
    try init();

    var target_buf: [mount_table.max_target_len]u8 = undefined;
    const target = mountTarget("runtime", target_buf[0..]).?;
    try std.testing.expectEqualStrings("/runtime", target);

    const mounted = try readFileAlloc(std.testing.allocator, "/mnt/runtime/state/mounted.txt", 64);
    defer std.testing.allocator.free(mounted);
    try std.testing.expectEqualStrings("persisted", mounted);
}

test "filesystem vfs routes root, tmpfs, virtual trees, and mounted aliases together" {
    resetForTest();
    try init();

    try createDirPath("/boot");
    try writeFile("/boot/loader.cfg", "loader=edge", 1);
    try createDirPath("/tmp/cache");
    try writeFile("/tmp/cache/state.txt", "volatile", 2);
    try bindMount("cache", "/tmp/cache", 3);

    const root_listing = try listDirectoryAlloc(std.testing.allocator, "/", 256);
    defer std.testing.allocator.free(root_listing);
    try std.testing.expect(std.mem.indexOf(u8, root_listing, "dir tmp\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, root_listing, "dir mnt\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, root_listing, "dir proc\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, root_listing, "dir dev\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, root_listing, "dir sys\n") != null);

    const mounted = try readFileAlloc(std.testing.allocator, "/mnt/cache/state.txt", 64);
    defer std.testing.allocator.free(mounted);
    try std.testing.expectEqualStrings("volatile", mounted);

    const proc_version = try readFileAlloc(std.testing.allocator, "/proc/version", 256);
    defer std.testing.allocator.free(proc_version);
    try std.testing.expect(std.mem.indexOf(u8, proc_version, "project=ZAR-Zig-Agent-Runtime") != null);

    const cache_stat = try statSummary("/mnt/cache");
    try std.testing.expectEqual(@as(std.Io.File.Kind, .directory), cache_stat.kind);
}
