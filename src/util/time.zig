const builtin = @import("builtin");
const std = @import("std");

const windows_epoch_offset_ms_f64: f64 = 11_644_473_600_000.0;

pub fn nowMs() i64 {
    if (builtin.os.tag == .windows) {
        const raw_100ns: i64 = std.os.windows.ntdll.RtlGetSystemTimePrecise();
        const unix_ms_f64 = @as(f64, @floatFromInt(raw_100ns)) * 0.0001 - windows_epoch_offset_ms_f64;
        return @as(i64, @intFromFloat(unix_ms_f64));
    }
    return std.Io.Clock.real.now(std.Io.Threaded.global_single_threaded.io()).toMilliseconds();
}
