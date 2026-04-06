// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const abi = @import("abi.zig");
const boot_memory = @import("boot_memory.zig");

pub const page_capacity: usize = 262144;
const default_page_size: u32 = 4096;
const default_heap_base: u64 = 0x0010_0000;
const default_total_pages: u32 = 256;

pub const State = struct {
    window_base: u64,
    window_limit: u64,
    page_size: u32,
    total_pages: u32,
    usable_pages: u32,
    reserved_pages: u32,
    fallback_regions_used: u8,
    reserved0: [3]u8,
};

var state: State = zeroState();
var usable_bitmap: [page_capacity]u8 = std.mem.zeroes([page_capacity]u8);

fn zeroState() State {
    return .{
        .window_base = default_heap_base,
        .window_limit = default_heap_base + (@as(u64, default_total_pages) * default_page_size),
        .page_size = default_page_size,
        .total_pages = default_total_pages,
        .usable_pages = default_total_pages,
        .reserved_pages = 0,
        .fallback_regions_used = 1,
        .reserved0 = .{ 0, 0, 0 },
    };
}

pub fn resetForTest() void {
    state = zeroState();
    @memset(&usable_bitmap, 0);
}

pub fn statePtr() *const State {
    return &state;
}

pub fn isPageUsable(index: usize) bool {
    if (index >= state.total_pages or index >= page_capacity) return false;
    return usable_bitmap[index] != 0;
}

pub fn initFromBootMemory(kernel_image_end: u64, page_size: u32) abi.BaremetalAllocatorState {
    state = zeroState();
    @memset(&usable_bitmap, 0);

    const boot_state = boot_memory.statePtr().*;
    if ((boot_state.flags & abi.boot_memory_flag_heap_configured) == 0 or
        boot_state.heap_base == 0 or
        boot_state.heap_limit <= boot_state.heap_base or
        page_size == 0)
    {
        return initDefaultState();
    }

    const heap_size = @min(
        boot_state.heap_size,
        @as(u64, page_capacity) * @as(u64, page_size),
    );
    const heap_limit = boot_state.heap_base + heap_size;
    const total_pages = std.math.cast(u32, heap_size / page_size) orelse return initDefaultState();
    if (total_pages == 0) return initDefaultState();

    state.window_base = boot_state.heap_base;
    state.window_limit = heap_limit;
    state.page_size = page_size;
    state.total_pages = total_pages;
    state.usable_pages = 0;
    state.reserved_pages = 0;
    state.fallback_regions_used = if ((boot_state.flags & abi.boot_memory_flag_regions_synthesized) != 0) 1 else 0;

    var region_count = boot_memory.regionCount();
    if (region_count == 0) {
        region_count = 1;
        markRangeUsable(boot_state.heap_base, heap_size);
        state.fallback_regions_used = 1;
    } else {
        var index: u32 = 0;
        while (index < region_count) : (index += 1) {
            const entry = boot_memory.regionEntry(index);
            if ((entry.flags & abi.boot_memory_region_flag_usable) == 0) continue;
            markRangeUsable(entry.base, entry.size);
        }
    }

    const reserve_limit = std.mem.alignForward(u64, @max(kernel_image_end, state.window_base), page_size);
    reserveRange(state.window_base, reserve_limit);

    recount();

    return .{
        .heap_base = state.window_base,
        .heap_size = state.window_limit - state.window_base,
        .page_size = page_size,
        .total_pages = state.total_pages,
        .free_pages = state.usable_pages,
        .allocation_count = 0,
        .alloc_ops = 0,
        .free_ops = 0,
        .bytes_in_use = 0,
        .peak_bytes_in_use = 0,
        .last_alloc_ptr = 0,
        .last_alloc_size = 0,
        .last_free_ptr = 0,
        .last_free_size = 0,
    };
}

pub fn renderAlloc(allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "allocator_total_pages={d}\nallocator_usable_pages={d}\nallocator_reserved_pages={d}\nallocator_window_base=0x{x}\nallocator_window_limit=0x{x}\nallocator_fallback_regions_used={d}\n",
        .{
            state.total_pages,
            state.usable_pages,
            state.reserved_pages,
            state.window_base,
            state.window_limit,
            state.fallback_regions_used,
        },
    );
}

fn defaultAllocatorState() abi.BaremetalAllocatorState {
    return .{
        .heap_base = default_heap_base,
        .heap_size = @as(u64, default_total_pages) * default_page_size,
        .page_size = default_page_size,
        .total_pages = default_total_pages,
        .free_pages = default_total_pages,
        .allocation_count = 0,
        .alloc_ops = 0,
        .free_ops = 0,
        .bytes_in_use = 0,
        .peak_bytes_in_use = 0,
        .last_alloc_ptr = 0,
        .last_alloc_size = 0,
        .last_free_ptr = 0,
        .last_free_size = 0,
    };
}

fn initDefaultState() abi.BaremetalAllocatorState {
    state = zeroState();
    @memset(&usable_bitmap, 0);
    var index: usize = 0;
    while (index < default_total_pages and index < page_capacity) : (index += 1) {
        usable_bitmap[index] = 1;
    }
    return defaultAllocatorState();
}

fn markRangeUsable(base: u64, size: u64) void {
    if (size == 0 or state.window_limit <= state.window_base) return;
    const unclamped_end = std.math.add(u64, base, size) catch std.math.maxInt(u64);
    const start = @max(base, state.window_base);
    const limit = @min(unclamped_end, state.window_limit);
    if (limit <= start) return;
    const first_page = std.mem.alignForward(u64, start, state.page_size);
    const limit_page = std.mem.alignBackward(u64, limit, state.page_size);
    if (limit_page <= first_page) return;

    var index = pageIndexFor(first_page);
    const end_index = pageIndexFor(limit_page);
    while (index < end_index and index < page_capacity) : (index += 1) {
        usable_bitmap[index] = 1;
    }
}

fn reserveRange(base: u64, limit: u64) void {
    if (limit <= base or state.window_limit <= state.window_base) return;
    const start = @max(base, state.window_base);
    const end_limit = @min(limit, state.window_limit);
    if (end_limit <= start) return;
    const first_page = std.mem.alignBackward(u64, start, state.page_size);
    const limit_page = std.mem.alignForward(u64, end_limit, state.page_size);
    var index = pageIndexFor(first_page);
    const end_index = pageIndexFor(limit_page);
    while (index < end_index and index < page_capacity) : (index += 1) {
        usable_bitmap[index] = 0;
    }
}

fn recount() void {
    var usable: u32 = 0;
    var index: usize = 0;
    while (index < state.total_pages and index < page_capacity) : (index += 1) {
        if (usable_bitmap[index] != 0) usable += 1;
    }
    state.usable_pages = usable;
    state.reserved_pages = state.total_pages - usable;
}

fn pageIndexFor(address: u64) usize {
    return @as(usize, @intCast((address - state.window_base) / state.page_size));
}

test "physical memory maps usable regions and reserves kernel span" {
    boot_memory.resetForTest();
    resetForTest();

    var buffer = [_]u8{0} ** 88;
    std.mem.writeInt(u32, buffer[0..4], 88, .little);
    std.mem.writeInt(u32, buffer[4..8], 0, .little);
    std.mem.writeInt(u32, buffer[8..12], boot_memory.multiboot2_tag_type_memory_map, .little);
    std.mem.writeInt(u32, buffer[12..16], 64, .little);
    std.mem.writeInt(u32, buffer[16..20], 24, .little);
    std.mem.writeInt(u32, buffer[20..24], 0, .little);
    std.mem.writeInt(u64, buffer[24..32], 0x0010_0000, .little);
    std.mem.writeInt(u64, buffer[32..40], 0x0010_0000, .little);
    std.mem.writeInt(u32, buffer[40..44], abi.boot_memory_region_type_available, .little);
    std.mem.writeInt(u32, buffer[44..48], 0, .little);
    std.mem.writeInt(u64, buffer[48..56], 0x0030_0000, .little);
    std.mem.writeInt(u64, buffer[56..64], 0x0010_0000, .little);
    std.mem.writeInt(u32, buffer[64..68], abi.boot_memory_region_type_available, .little);
    std.mem.writeInt(u32, buffer[68..72], 0, .little);
    std.mem.writeInt(u32, buffer[72..76], boot_memory.multiboot2_tag_type_end, .little);
    std.mem.writeInt(u32, buffer[76..80], 8, .little);

    try std.testing.expect(boot_memory.parseMultiboot2Info(@intFromPtr(&buffer)));
    boot_memory.configureHeap(0x0018_0000, 4096);

    const allocator_state = initFromBootMemory(0x0018_0000, 4096);
    try std.testing.expectEqual(@as(u64, 0x0018_0000), allocator_state.heap_base);
    try std.testing.expectEqual(@as(u32, 640), allocator_state.total_pages);
    try std.testing.expectEqual(@as(u32, 384), allocator_state.free_pages);
    try std.testing.expect(isPageUsable(0));
    try std.testing.expect(isPageUsable(127));
    try std.testing.expect(!isPageUsable(128));
    try std.testing.expect(!isPageUsable(383));
    try std.testing.expect(isPageUsable(384));
}
