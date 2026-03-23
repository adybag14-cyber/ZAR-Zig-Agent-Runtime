// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const abi = @import("abi.zig");
const ata_pio_disk = @import("ata_pio_disk.zig");
const ram_disk = @import("ram_disk.zig");
const storage_backend = @import("storage_backend.zig");
const storage_registry = @import("storage_registry.zig");
const tool_layout = @import("tool_layout.zig");
const virtio_block = @import("virtio_block.zig");

pub const max_entries: usize = 3;
pub const max_name_len: usize = 24;
const max_render_bytes: usize = 4 * 1024;
const max_read_block_bytes: usize = storage_backend.block_size;
const no_partition_selected: u8 = std.math.maxInt(u8);
const zarfs_superblock_lba: u32 = tool_layout.slot_data_lba + @as(u32, tool_layout.slot_count * tool_layout.slot_block_capacity);

pub const Entry = struct {
    name_len: u8 = 0,
    backend: u8 = 0,
    available: u8 = 0,
    selected: u8 = 0,
    mounted: u8 = 0,
    preferred_order: u8 = 0,
    filesystem_kind: storage_registry.FilesystemKind = .unknown,
    block_size: u32 = 0,
    block_count: u32 = 0,
    logical_base_lba: u32 = 0,
    partition_count: u8 = 0,
    selected_partition: u8 = no_partition_selected,
    reserved0: [2]u8 = .{ 0, 0 },
    name: [max_name_len]u8 = std.mem.zeroes([max_name_len]u8),

    pub fn nameSlice(self: *const @This()) []const u8 {
        return self.name[0..self.name_len];
    }
};

pub fn entryCount() usize {
    return max_entries;
}

pub fn entry(index: usize) ?Entry {
    primeBackends();
    return switch (index) {
        0 => synthesizeEntry(abi.storage_backend_ram_disk, 0),
        1 => synthesizeEntry(abi.storage_backend_ata_pio, 1),
        2 => synthesizeEntry(abi.storage_backend_virtio_block, 2),
        else => null,
    };
}

pub fn renderAlloc(allocator: std.mem.Allocator, max_bytes: usize) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var index: usize = 0;
    while (index < entryCount()) : (index += 1) {
        const item = entry(index) orelse continue;
        const selected_partition_text = if (item.selected_partition == no_partition_selected)
            try allocator.dupe(u8, "none")
        else
            try std.fmt.allocPrint(allocator, "{d}", .{item.selected_partition});
        defer allocator.free(selected_partition_text);

        const line = try std.fmt.allocPrint(
            allocator,
            "backend[{d}]=name={s} backend={s} available={d} selected={d} mounted={d} preferred_order={d} filesystem={s} block_size={d} block_count={d} logical_base_lba={d} partition_count={d} selected_partition={s}\n",
            .{
                index,
                item.nameSlice(),
                storage_registry.backendName(item.backend),
                item.available,
                item.selected,
                item.mounted,
                item.preferred_order,
                storage_registry.filesystemKindName(item.filesystem_kind),
                item.block_size,
                item.block_count,
                item.logical_base_lba,
                item.partition_count,
                selected_partition_text,
            },
        );
        defer allocator.free(line);
        if (out.items.len + line.len > max_bytes) return error.ResponseTooLarge;
        try out.appendSlice(allocator, line);
    }

    return out.toOwnedSlice(allocator);
}

pub fn renderFilesystemSupportAlloc(allocator: std.mem.Allocator, max_bytes: usize) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    const rows = [_][]const u8{
        "filesystem=zarfs detect=1 mount=1 write=1 source=zar_native\n",
        "filesystem=tmpfs detect=synthetic mount=1 write=1 source=zar_native\n",
        "filesystem=ext2 detect=1 mount=1 write=0 source=zar_bounded_read_only\n",
        "filesystem=fat32 detect=1 mount=1 write=1 source=zar_bounded_writable_root_only\n",
    };
    for (rows) |row| {
        if (out.items.len + row.len > max_bytes) return error.ResponseTooLarge;
        try out.appendSlice(allocator, row);
    }
    return out.toOwnedSlice(allocator);
}

fn primeBackends() void {
    ata_pio_disk.init();
    virtio_block.init();
    ram_disk.init();
    storage_backend.init();
}

fn synthesizeEntry(backend: u8, preferred_order: u8) Entry {
    const state = backendState(backend);
    var result = Entry{
        .backend = backend,
        .available = if (backend == abi.storage_backend_ram_disk or state.mounted != 0) 1 else 0,
        .selected = if (storage_backend.activeBackend() == backend) 1 else 0,
        .mounted = state.mounted,
        .preferred_order = preferred_order,
        .filesystem_kind = detectFilesystemKind(backend),
        .block_size = state.block_size,
        .block_count = state.block_count,
        .logical_base_lba = switch (backend) {
            abi.storage_backend_ata_pio => ata_pio_disk.logicalBaseLba(),
            else => 0,
        },
        .partition_count = switch (backend) {
            abi.storage_backend_ata_pio => ata_pio_disk.partitionCount(),
            else => 0,
        },
        .selected_partition = switch (backend) {
            abi.storage_backend_ata_pio => ata_pio_disk.selectedPartitionIndex() orelse no_partition_selected,
            else => no_partition_selected,
        },
    };
    const name = storage_registry.backendName(backend);
    @memcpy(result.name[0..name.len], name);
    result.name_len = @as(u8, @intCast(name.len));
    return result;
}

fn backendState(backend: u8) *const abi.BaremetalStorageState {
    return switch (backend) {
        abi.storage_backend_ram_disk => ram_disk.statePtr(),
        abi.storage_backend_ata_pio => ata_pio_disk.statePtr(),
        abi.storage_backend_virtio_block => virtio_block.statePtr(),
        else => ram_disk.statePtr(),
    };
}

fn detectFilesystemKind(backend: u8) storage_registry.FilesystemKind {
    const state = backendState(backend);
    if (state.mounted == 0 or state.block_size == 0) return .unknown;
    if (probeZarfs(backend)) return .zarfs;
    if (probeFat32(backend)) return .fat32;
    if (probeExt2(backend)) return .ext2;
    return .unknown;
}

fn probeZarfs(backend: u8) bool {
    const state = backendState(backend);
    if (state.block_size == 0 or zarfs_superblock_lba >= state.block_count) return false;
    if (state.block_size > max_read_block_bytes) return false;

    var block = [_]u8{0} ** max_read_block_bytes;
    if (!readBlocks(backend, zarfs_superblock_lba, block[0..state.block_size])) return false;
    const magic = std.mem.readInt(u32, block[0..4], .little);
    return magic == abi.filesystem_magic;
}

fn probeFat32(backend: u8) bool {
    const state = backendState(backend);
    if (state.block_size < 512 or state.block_count == 0 or state.block_size > max_read_block_bytes) return false;

    var block = [_]u8{0} ** max_read_block_bytes;
    if (!readBlocks(backend, 0, block[0..state.block_size])) return false;
    if (block[510] != 0x55 or block[511] != 0xAA) return false;
    return std.mem.eql(u8, block[82..90], "FAT32   ");
}

fn probeExt2(backend: u8) bool {
    var magic_buf: [2]u8 = undefined;
    if (!readVolumeBytes(backend, 1024 + 56, magic_buf[0..])) return false;
    return magic_buf[0] == 0x53 and magic_buf[1] == 0xEF;
}

fn readBlocks(backend: u8, lba: u32, out: []u8) bool {
    switch (backend) {
        abi.storage_backend_ram_disk => ram_disk.readBlocks(lba, out) catch return false,
        abi.storage_backend_ata_pio => ata_pio_disk.readBlocks(lba, out) catch return false,
        abi.storage_backend_virtio_block => virtio_block.readBlocks(lba, out) catch return false,
        else => return false,
    }
    return true;
}

fn readVolumeBytes(backend: u8, byte_offset: u64, out: []u8) bool {
    const state = backendState(backend);
    if (state.mounted == 0 or state.block_size == 0 or state.block_size > max_read_block_bytes) return false;

    var scratch = [_]u8{0} ** max_read_block_bytes;
    const block_size = @as(u64, state.block_size);
    var copied: usize = 0;
    while (copied < out.len) {
        const absolute = byte_offset + copied;
        const lba = absolute / block_size;
        if (lba >= state.block_count) return false;
        const intra = @as(usize, @intCast(absolute % block_size));
        if (!readBlocks(backend, @as(u32, @intCast(lba)), scratch[0..state.block_size])) return false;
        const remaining_in_block = @as(usize, state.block_size) - intra;
        const copy_len = @min(out.len - copied, remaining_in_block);
        @memcpy(out[copied .. copied + copy_len], scratch[intra .. intra + copy_len]);
        copied += copy_len;
    }
    return true;
}

test "backend registry renders ram only baseline" {
    storage_backend.resetForTest();

    const rendered = try renderAlloc(std.testing.allocator, max_render_bytes);
    defer std.testing.allocator.free(rendered);

    try std.testing.expect(std.mem.indexOf(u8, rendered, "backend[0]=name=ram_disk backend=ram_disk available=1 selected=1 mounted=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "backend[1]=name=ata_pio backend=ata_pio available=0 selected=0 mounted=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "backend[2]=name=virtio_block backend=virtio_block available=0 selected=0 mounted=0") != null);
}

test "backend registry tracks ata selection and partition metadata" {
    storage_backend.resetForTest();
    ata_pio_disk.testEnableMockDevice(16384);
    ata_pio_disk.testInstallMockMbrPartition(2048, 4096, 0x83);
    defer ata_pio_disk.testDisableMockDevice();

    ata_pio_disk.init();
    var block = [_]u8{0} ** storage_backend.block_size;
    std.mem.writeInt(u32, block[0..4], abi.filesystem_magic, .little);
    try ata_pio_disk.writeBlocks(zarfs_superblock_lba, block[0..]);

    const rendered = try renderAlloc(std.testing.allocator, max_render_bytes);
    defer std.testing.allocator.free(rendered);

    try std.testing.expect(std.mem.indexOf(u8, rendered, "backend[1]=name=ata_pio backend=ata_pio available=1 selected=1 mounted=1 preferred_order=1 filesystem=zarfs") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "logical_base_lba=2048") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "partition_count=1 selected_partition=0") != null);
}

test "backend registry tracks virtio availability without changing ata precedence" {
    storage_backend.resetForTest();
    ata_pio_disk.testEnableMockDevice(8192);
    ata_pio_disk.testInstallMockMbrPartition(2048, 2048, 0x83);
    virtio_block.testEnableMockDevice(1024);
    defer ata_pio_disk.testDisableMockDevice();
    defer virtio_block.testDisableMockDevice();

    ata_pio_disk.init();
    var ata_block = [_]u8{0} ** storage_backend.block_size;
    std.mem.writeInt(u32, ata_block[0..4], abi.filesystem_magic, .little);
    try ata_pio_disk.writeBlocks(zarfs_superblock_lba, ata_block[0..]);
    virtio_block.init();
    var virt_block = [_]u8{0} ** storage_backend.block_size;
    std.mem.writeInt(u32, virt_block[0..4], abi.filesystem_magic, .little);
    try virtio_block.writeBlocks(zarfs_superblock_lba, virt_block[0..]);

    const rendered = try renderAlloc(std.testing.allocator, max_render_bytes);
    defer std.testing.allocator.free(rendered);

    try std.testing.expect(std.mem.indexOf(u8, rendered, "backend[1]=name=ata_pio backend=ata_pio available=1 selected=1 mounted=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "backend[2]=name=virtio_block backend=virtio_block available=1 selected=0 mounted=1 preferred_order=2 filesystem=zarfs") != null);
}

test "backend registry exposes filesystem support matrix" {
    const rendered = try renderFilesystemSupportAlloc(std.testing.allocator, 512);
    defer std.testing.allocator.free(rendered);

    try std.testing.expect(std.mem.indexOf(u8, rendered, "filesystem=zarfs detect=1 mount=1 write=1 source=zar_native") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "filesystem=ext2 detect=1 mount=1 write=0 source=zar_bounded_read_only") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "filesystem=fat32 detect=1 mount=1 write=1 source=zar_bounded_writable_root_only") != null);
}
