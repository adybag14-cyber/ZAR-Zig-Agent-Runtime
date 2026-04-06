// SPDX-License-Identifier: GPL-2.0-only
const builtin = @import("builtin");
const std = @import("std");

const windows_epoch_offset_ms_f64: f64 = 11_644_473_600_000.0;

pub fn nowMs() i64 {
    if (builtin.os.tag == .freestanding) {
        // The bare-metal slices currently use explicit tick/telemetry counters instead of a wall clock.
        // Returning a stable value keeps freestanding code paths buildable until a real clock source is wired in.
        return 0;
    }
    if (builtin.os.tag == .windows) {
        const raw_100ns: i64 = std.os.windows.ntdll.RtlGetSystemTimePrecise();
        const unix_ms_f64 = @as(f64, @floatFromInt(raw_100ns)) * 0.0001 - windows_epoch_offset_ms_f64;
        return @as(i64, @intFromFloat(unix_ms_f64));
    }
    return std.Io.Clock.real.now(std.Io.Threaded.global_single_threaded.io()).toMilliseconds();
}

pub fn unixMsToRfc3339Alloc(allocator: std.mem.Allocator, unix_ms: i64) ![]u8 {
    const total_seconds = @divFloor(unix_ms, @as(i64, 1000));
    const seconds_of_day: i64 = @mod(total_seconds, @as(i64, 86_400));
    const days = @divFloor(total_seconds, @as(i64, 86_400));

    const z = days + 719_468;
    const era = @divFloor(z, @as(i64, 146_097));
    const doe = z - era * 146_097;
    const yoe = @divFloor(doe - @divFloor(doe, @as(i64, 1_460)) + @divFloor(doe, @as(i64, 36_524)) - @divFloor(doe, @as(i64, 146_096)), @as(i64, 365));
    const y = yoe + era * 400;
    const doy = doe - (365 * yoe + @divFloor(yoe, @as(i64, 4)) - @divFloor(yoe, @as(i64, 100)));
    const mp = @divFloor(5 * doy + 2, @as(i64, 153));
    const day = doy - @divFloor(153 * mp + 2, @as(i64, 5)) + 1;
    const month = mp + (if (mp < 10) @as(i64, 3) else @as(i64, -9));
    const year = y + (if (month <= 2) @as(i64, 1) else @as(i64, 0));

    const hour = @divFloor(seconds_of_day, @as(i64, 3_600));
    const minute = @divFloor(@mod(seconds_of_day, @as(i64, 3_600)), @as(i64, 60));
    const second = @mod(seconds_of_day, @as(i64, 60));
    const year_u: u32 = @intCast(year);
    const month_u: u8 = @intCast(month);
    const day_u: u8 = @intCast(day);
    const hour_u: u8 = @intCast(hour);
    const minute_u: u8 = @intCast(minute);
    const second_u: u8 = @intCast(second);

    return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
        year_u,
        month_u,
        day_u,
        hour_u,
        minute_u,
        second_u,
    });
}

test "unixMsToRfc3339Alloc formats unix epoch" {
    const allocator = std.testing.allocator;
    const formatted = try unixMsToRfc3339Alloc(allocator, 0);
    defer allocator.free(formatted);
    try std.testing.expectEqualStrings("1970-01-01T00:00:00Z", formatted);
}

test "unixMsToRfc3339Alloc formats stable timestamp" {
    const allocator = std.testing.allocator;
    const formatted = try unixMsToRfc3339Alloc(allocator, 1_700_000_000_000);
    defer allocator.free(formatted);
    try std.testing.expectEqualStrings("2023-11-14T22:13:20Z", formatted);
}
