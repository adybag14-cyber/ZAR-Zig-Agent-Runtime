// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const builtin = @import("builtin");
const abi = @import("abi.zig");

pub export var oc_i386_boot_magic_raw: u32 = 0;
pub export var oc_i386_boot_info_ptr_raw: u32 = 0;

pub const multiboot2_boot_magic: u32 = 0x36D76289;
pub const multiboot2_tag_type_end: u32 = 0;
pub const multiboot2_tag_type_basic_meminfo: u32 = 4;
pub const multiboot2_tag_type_memory_map: u32 = 6;

const cmos_addr_port: u16 = 0x70;
const cmos_data_port: u16 = 0x71;
const cmos_reg_extended_low_kib_low: u8 = 0x30;
const cmos_reg_extended_low_kib_high: u8 = 0x31;
const cmos_reg_extended_high_64k_low: u8 = 0x34;
const cmos_reg_extended_high_64k_high: u8 = 0x35;

const one_gib: u64 = 1024 * 1024 * 1024;
const memory_map_entry_type_available: u32 = 1;
pub const region_capacity: usize = 64;

var state: abi.BaremetalBootMemoryState = zeroState();
var regions: [region_capacity]abi.BaremetalBootMemoryRegion = std.mem.zeroes([region_capacity]abi.BaremetalBootMemoryRegion);

fn zeroState() abi.BaremetalBootMemoryState {
    return .{
        .magic = abi.boot_memory_magic,
        .api_version = abi.api_version,
        .source = abi.boot_memory_source_none,
        .reserved0 = 0,
        .flags = 0,
        .mem_lower_kib = 0,
        .mem_upper_kib = 0,
        .total_bytes = 0,
        .usable_bytes = 0,
        .heap_base = 0,
        .heap_limit = 0,
        .heap_size = 0,
        .mmap_entry_count = 0,
        .usable_region_count = 0,
        .largest_usable_base = 0,
        .largest_usable_size = 0,
        .region_entry_count = 0,
        .reserved1 = 0,
    };
}

pub fn resetForTest() void {
    state = zeroState();
    @memset(&regions, std.mem.zeroes(abi.BaremetalBootMemoryRegion));
    oc_i386_boot_magic_raw = 0;
    oc_i386_boot_info_ptr_raw = 0;
}

pub fn statePtr() *const abi.BaremetalBootMemoryState {
    return &state;
}

pub fn regionCount() u32 {
    return state.region_entry_count;
}

pub fn regionEntry(index: u32) abi.BaremetalBootMemoryRegion {
    if (index >= state.region_entry_count or index >= region_capacity) {
        return std.mem.zeroes(abi.BaremetalBootMemoryRegion);
    }
    return regions[index];
}

pub fn init(kernel_image_end: u64, page_size: u32) void {
    state = zeroState();
    @memset(&regions, std.mem.zeroes(abi.BaremetalBootMemoryRegion));
    if (builtin.os.tag != .freestanding) {
        configureHeapFallback(kernel_image_end, page_size);
        return;
    }

    var parsed = false;
    if (builtin.cpu.arch == .x86 and oc_i386_boot_magic_raw == multiboot2_boot_magic and oc_i386_boot_info_ptr_raw != 0) {
        parsed = parseMultiboot2Info(@as(usize, oc_i386_boot_info_ptr_raw));
        if (parsed) state.flags |= abi.boot_memory_flag_has_multiboot_magic;
    }

    if (!parsed and (builtin.cpu.arch == .x86 or builtin.cpu.arch == .x86_64)) {
        parseCmosFallback();
    }

    configureHeap(kernel_image_end, page_size);
}

pub fn livePhysicalLimit() u64 {
    if (state.total_bytes == 0) return 0x08000000;
    return @min(state.total_bytes, one_gib);
}

pub fn renderAlloc(allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "source={d}\nflags=0x{x}\nmem_lower_kib={d}\nmem_upper_kib={d}\ntotal_bytes={d}\nusable_bytes={d}\nheap_base=0x{x}\nheap_limit=0x{x}\nheap_size={d}\nmmap_entry_count={d}\nusable_region_count={d}\nlargest_usable_base=0x{x}\nlargest_usable_size={d}\nregion_entry_count={d}\nregions_synthesized={d}\n",
        .{
            state.source,
            state.flags,
            state.mem_lower_kib,
            state.mem_upper_kib,
            state.total_bytes,
            state.usable_bytes,
            state.heap_base,
            state.heap_limit,
            state.heap_size,
            state.mmap_entry_count,
            state.usable_region_count,
            state.largest_usable_base,
            state.largest_usable_size,
            state.region_entry_count,
            if ((state.flags & abi.boot_memory_flag_regions_synthesized) != 0) @as(u32, 1) else @as(u32, 0),
        },
    );
}

pub fn renderMapAlloc(allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    const header = try std.fmt.allocPrint(allocator, "region_entry_count={d}\n", .{state.region_entry_count});
    defer allocator.free(header);
    try out.appendSlice(allocator, header);
    var index: u32 = 0;
    while (index < state.region_entry_count and index < region_capacity) : (index += 1) {
        const entry = regions[index];
        const line = try std.fmt.allocPrint(
            allocator,
            "region[{d}].base=0x{x}\nregion[{d}].size={d}\nregion[{d}].type={d}\nregion[{d}].flags=0x{x}\n",
            .{ index, entry.base, index, entry.size, index, entry.entry_type, index, entry.flags },
        );
        defer allocator.free(line);
        try out.appendSlice(allocator, line);
    }
    return out.toOwnedSlice(allocator);
}

pub fn parseMultiboot2Info(info_ptr: usize) bool {
    if (info_ptr == 0) return false;
    const base: [*]const u8 = @ptrFromInt(info_ptr);
    const total_size = readU32(base[0..4]);
    if (total_size < 16 or total_size > 64 * 1024) return false;
    const blob = base[0..total_size];

    state.source = abi.boot_memory_source_multiboot2;
    var cursor: usize = 8;
    while (cursor + 8 <= blob.len) {
        const tag_type = readU32(blob[cursor .. cursor + 4]);
        const tag_size = readU32(blob[cursor + 4 .. cursor + 8]);
        if (tag_type == multiboot2_tag_type_end) break;
        if (tag_size < 8 or cursor + tag_size > blob.len) return false;

        switch (tag_type) {
            multiboot2_tag_type_basic_meminfo => parseBasicMeminfoTag(blob[cursor .. cursor + tag_size]),
            multiboot2_tag_type_memory_map => parseMemoryMapTag(blob[cursor .. cursor + tag_size]),
            else => {},
        }
        cursor = std.mem.alignForward(usize, cursor + tag_size, 8);
    }
    if (state.region_entry_count == 0) synthesizeBasicUsableRegion();
    return state.mem_upper_kib != 0 or state.total_bytes != 0;
}

fn parseBasicMeminfoTag(tag: []const u8) void {
    if (tag.len < 16) return;
    state.flags |= abi.boot_memory_flag_has_basic_meminfo;
    state.mem_lower_kib = readU32(tag[8..12]);
    state.mem_upper_kib = readU32(tag[12..16]);
    const unclipped_total = @as(u64, (1024 + state.mem_upper_kib)) * 1024;
    if (unclipped_total > one_gib) state.flags |= abi.boot_memory_flag_heap_capped_1g;
    if (state.total_bytes == 0) {
        state.total_bytes = @min(one_gib, unclipped_total);
    }
    if (state.usable_bytes == 0) {
        state.usable_bytes = state.total_bytes;
    }
}

fn parseMemoryMapTag(tag: []const u8) void {
    if (tag.len < 16) return;
    const entry_size = readU32(tag[8..12]);
    if (entry_size < 24 or entry_size % 8 != 0) return;

    state.flags |= abi.boot_memory_flag_has_memory_map;
    var cursor: usize = 16;
    var capped_total: u64 = 0;
    var usable_total: u64 = 0;
    while (cursor + entry_size <= tag.len) : (cursor += entry_size) {
        const entry = tag[cursor .. cursor + entry_size];
        const base_addr = readU64(entry[0..8]);
        const length = readU64(entry[8..16]);
        const entry_type = readU32(entry[16..20]);
        if (length == 0) continue;
        const region_base = base_addr;
        const unclamped_end = std.math.add(u64, region_base, length) catch std.math.maxInt(u64);
        const region_end = @min(unclamped_end, one_gib);
        if (region_end <= region_base) continue;
        const clipped_len = region_end - region_base;
        var region_flags: u32 = 0;
        if (entry_type == memory_map_entry_type_available) region_flags |= abi.boot_memory_region_flag_usable;
        if (region_end != unclamped_end) {
            region_flags |= abi.boot_memory_region_flag_clipped;
            state.flags |= abi.boot_memory_flag_heap_capped_1g;
        }
        appendRegion(region_base, clipped_len, entry_type, region_flags);
        state.mmap_entry_count += 1;
        if (entry_type == memory_map_entry_type_available) {
            state.usable_region_count += 1;
            usable_total += clipped_len;
            if (clipped_len > state.largest_usable_size) {
                state.largest_usable_size = clipped_len;
                state.largest_usable_base = region_base;
            }
        }
        if (region_end > capped_total) capped_total = region_end;
    }

    if (capped_total != 0) state.total_bytes = capped_total;
    if (usable_total != 0) state.usable_bytes = usable_total;
}

fn parseCmosFallback() void {
    if (builtin.os.tag != .freestanding) return;
    if (!(builtin.cpu.arch == .x86 or builtin.cpu.arch == .x86_64)) return;

    state.source = abi.boot_memory_source_cmos_fallback;
    const mem_upper_kib = readExtendedMemoryKib();
    state.mem_lower_kib = 640;
    state.mem_upper_kib = mem_upper_kib;
    const unclipped_total = @as(u64, (1024 + mem_upper_kib)) * 1024;
    if (unclipped_total > one_gib) state.flags |= abi.boot_memory_flag_heap_capped_1g;
    state.total_bytes = @min(one_gib, unclipped_total);
    state.usable_bytes = state.total_bytes;
    synthesizeBasicUsableRegion();
}

fn synthesizeBasicUsableRegion() void {
    if (state.region_entry_count != 0 or state.usable_region_count != 0 or state.largest_usable_size != 0) return;
    const upper_base: u64 = 0x0010_0000;
    if (state.total_bytes <= upper_base) return;
    const upper_limit = @min(state.total_bytes, one_gib);
    if (upper_limit <= upper_base) return;
    appendRegion(
        upper_base,
        upper_limit - upper_base,
        abi.boot_memory_region_type_available,
        abi.boot_memory_region_flag_usable | abi.boot_memory_region_flag_synthesized,
    );
    state.usable_region_count = 1;
    state.largest_usable_base = upper_base;
    state.largest_usable_size = upper_limit - upper_base;
    state.flags |= abi.boot_memory_flag_regions_synthesized;
}

fn configureHeapFallback(kernel_image_end: u64, page_size: u32) void {
    const fallback_base = std.mem.alignForward(u64, @max(kernel_image_end, 0x0010_0000), page_size);
    const fallback_limit = fallback_base + (256 * @as(u64, page_size));
    state.heap_base = fallback_base;
    state.heap_limit = fallback_limit;
    state.heap_size = fallback_limit - fallback_base;
    state.flags |= abi.boot_memory_flag_heap_configured;
}

pub fn configureHeap(kernel_image_end: u64, page_size: u32) void {
    const heap_base = std.mem.alignForward(u64, @max(kernel_image_end, 0x0010_0000), page_size);
    if (state.region_entry_count == 0 or state.usable_region_count == 0) {
        configureHeapFallback(kernel_image_end, page_size);
        return;
    }

    var heap_limit: u64 = 0;
    var usable_found = false;
    var index: u32 = 0;
    while (index < state.region_entry_count and index < region_capacity) : (index += 1) {
        const entry = regions[index];
        if ((entry.flags & abi.boot_memory_region_flag_usable) == 0 or entry.size == 0) continue;
        const entry_end = entry.base + entry.size;
        const clipped_base = std.mem.alignForward(u64, @max(entry.base, heap_base), page_size);
        const clipped_end = std.mem.alignBackward(u64, @min(entry_end, one_gib), page_size);
        if (clipped_end <= clipped_base) continue;
        usable_found = true;
        if (clipped_end > heap_limit) heap_limit = clipped_end;
    }
    if (!usable_found) {
        configureHeapFallback(kernel_image_end, page_size);
        return;
    }
    if (heap_limit <= heap_base) {
        configureHeapFallback(kernel_image_end, page_size);
        return;
    }
    state.heap_base = heap_base;
    state.heap_limit = heap_limit;
    state.heap_size = heap_limit - heap_base;
    state.flags |= abi.boot_memory_flag_heap_configured;
}

fn appendRegion(base: u64, size: u64, entry_type: u32, flags: u32) void {
    if (size == 0) return;
    if (state.region_entry_count >= region_capacity) return;
    regions[state.region_entry_count] = .{
        .base = base,
        .size = size,
        .entry_type = entry_type,
        .flags = flags,
    };
    state.region_entry_count += 1;
    state.flags |= abi.boot_memory_flag_has_region_entries;
}

fn readExtendedMemoryKib() u32 {
    const upper_above_16m = (@as(u32, readCmosByte(cmos_reg_extended_high_64k_high)) << 8) | readCmosByte(cmos_reg_extended_high_64k_low);
    if (upper_above_16m != 0) {
        return (15 * 1024) + (upper_above_16m * 64);
    }
    const upper_legacy = (@as(u32, readCmosByte(cmos_reg_extended_low_kib_high)) << 8) | readCmosByte(cmos_reg_extended_low_kib_low);
    return upper_legacy;
}

fn readCmosByte(reg: u8) u8 {
    outb(cmos_addr_port, reg | 0x80);
    return inb(cmos_data_port);
}

fn runtimeCanProbe() bool {
    return builtin.os.tag == .freestanding and (builtin.cpu.arch == .x86 or builtin.cpu.arch == .x86_64);
}

fn inb(port: u16) u8 {
    if (!runtimeCanProbe()) return 0;
    return asm volatile ("inb %[dx], %[al]"
        : [al] "={al}" (-> u8),
        : [dx] "{dx}" (port),
        : .{ .memory = true });
}

fn outb(port: u16, value: u8) void {
    if (!runtimeCanProbe()) return;
    asm volatile ("outb %[al], %[dx]"
        :
        : [al] "{al}" (value),
          [dx] "{dx}" (port),
        : .{ .memory = true });
}

fn readU32(bytes: []const u8) u32 {
    return std.mem.readInt(u32, bytes[0..4], .little);
}

fn readU64(bytes: []const u8) u64 {
    return std.mem.readInt(u64, bytes[0..8], .little);
}

test "boot memory parses basic multiboot2 meminfo" {
    resetForTest();
    var buffer = [_]u8{0} ** 32;
    std.mem.writeInt(u32, buffer[0..4], 32, .little);
    std.mem.writeInt(u32, buffer[4..8], 0, .little);
    std.mem.writeInt(u32, buffer[8..12], multiboot2_tag_type_basic_meminfo, .little);
    std.mem.writeInt(u32, buffer[12..16], 16, .little);
    std.mem.writeInt(u32, buffer[16..20], 640, .little);
    std.mem.writeInt(u32, buffer[20..24], 1024 * 1023, .little);
    std.mem.writeInt(u32, buffer[24..28], multiboot2_tag_type_end, .little);
    std.mem.writeInt(u32, buffer[28..32], 8, .little);

    try std.testing.expect(parseMultiboot2Info(@intFromPtr(&buffer)));
    configureHeap(0x0018_0000, 4096);
    const parsed = statePtr().*;
    try std.testing.expectEqual(abi.boot_memory_source_multiboot2, parsed.source);
    try std.testing.expect((parsed.flags & abi.boot_memory_flag_has_basic_meminfo) != 0);
    try std.testing.expectEqual(@as(u64, one_gib), parsed.total_bytes);
    try std.testing.expectEqual(@as(u32, 1), parsed.usable_region_count);
    try std.testing.expectEqual(@as(u32, 1), parsed.region_entry_count);
    try std.testing.expectEqual(@as(u64, 0x0010_0000), parsed.largest_usable_base);
    try std.testing.expectEqual(@as(u64, one_gib - 0x0010_0000), parsed.largest_usable_size);
    const region0 = regionEntry(0);
    try std.testing.expectEqual(@as(u64, 0x0010_0000), region0.base);
    try std.testing.expectEqual(@as(u32, abi.boot_memory_region_type_available), region0.entry_type);
    try std.testing.expect((region0.flags & abi.boot_memory_region_flag_synthesized) != 0);
    try std.testing.expectEqual(std.mem.alignForward(u64, 0x0018_0000, 4096), parsed.heap_base);
    try std.testing.expect(parsed.heap_size > 0);
}

test "boot memory parses multiboot2 memory map and clips to 1g" {
    resetForTest();
    var buffer = [_]u8{0} ** 64;
    std.mem.writeInt(u32, buffer[0..4], 64, .little);
    std.mem.writeInt(u32, buffer[4..8], 0, .little);
    std.mem.writeInt(u32, buffer[8..12], multiboot2_tag_type_memory_map, .little);
    std.mem.writeInt(u32, buffer[12..16], 40, .little);
    std.mem.writeInt(u32, buffer[16..20], 24, .little);
    std.mem.writeInt(u32, buffer[20..24], 0, .little);
    std.mem.writeInt(u64, buffer[24..32], 0x0010_0000, .little);
    std.mem.writeInt(u64, buffer[32..40], one_gib, .little);
    std.mem.writeInt(u32, buffer[40..44], memory_map_entry_type_available, .little);
    std.mem.writeInt(u32, buffer[44..48], 0, .little);
    std.mem.writeInt(u32, buffer[48..52], multiboot2_tag_type_end, .little);
    std.mem.writeInt(u32, buffer[52..56], 8, .little);

    try std.testing.expect(parseMultiboot2Info(@intFromPtr(&buffer)));
    configureHeap(0x0020_0000, 4096);
    const parsed = statePtr().*;
    try std.testing.expect((parsed.flags & abi.boot_memory_flag_has_memory_map) != 0);
    try std.testing.expectEqual(@as(u32, 1), parsed.mmap_entry_count);
    try std.testing.expectEqual(@as(u32, 1), parsed.usable_region_count);
    try std.testing.expectEqual(@as(u32, 1), parsed.region_entry_count);
    try std.testing.expectEqual(@as(u64, one_gib), parsed.total_bytes);
    try std.testing.expectEqual(@as(u64, one_gib - std.mem.alignForward(u64, 0x0020_0000, 4096)), parsed.heap_size);
    const region0 = regionEntry(0);
    try std.testing.expectEqual(@as(u64, 0x0010_0000), region0.base);
    try std.testing.expect((region0.flags & abi.boot_memory_region_flag_usable) != 0);
    try std.testing.expect((region0.flags & abi.boot_memory_region_flag_clipped) != 0);
}
