const builtin = @import("builtin");
const std = @import("std");

pub const RunCapture = struct {
    term: std.process.Child.Term,
    stdout: []u8,
    stderr: []u8,

    pub fn deinit(self: *RunCapture, allocator: std.mem.Allocator) void {
        allocator.free(self.stdout);
        allocator.free(self.stderr);
    }
};

pub fn timeoutFromMs(timeout_ms: u32) std.Io.Timeout {
    return switch (builtin.os.tag) {
        .windows => .none,
        else => .{
            .duration = .{
                .clock = .awake,
                .raw = std.Io.Duration.fromMilliseconds(timeout_ms),
            },
        },
    };
}

pub fn runCapture(
    allocator: std.mem.Allocator,
    io: std.Io,
    argv: []const []const u8,
    timeout_ms: u32,
    stdout_limit: usize,
    stderr_limit: usize,
) !RunCapture {
    const run_result = try std.process.run(allocator, io, .{
        .argv = argv,
        .timeout = timeoutFromMs(timeout_ms),
        .stdout_limit = .limited(stdout_limit),
        .stderr_limit = .limited(stderr_limit),
    });
    return .{
        .term = run_result.term,
        .stdout = run_result.stdout,
        .stderr = run_result.stderr,
    };
}

pub fn termExitCode(term: std.process.Child.Term) i32 {
    return switch (term) {
        .exited => |code| code,
        .signal => |sig| -@as(i32, @intCast(@intFromEnum(sig))),
        .stopped, .unknown => -1,
    };
}

pub fn isCommandAllowed(command: []const u8, allowlist_csv: []const u8) bool {
    const trimmed_command = std.mem.trim(u8, command, " \t\r\n");
    if (trimmed_command.len == 0) return false;
    const trimmed_allowlist = std.mem.trim(u8, allowlist_csv, " \t\r\n");
    if (trimmed_allowlist.len == 0) return true;

    var it = std.mem.tokenizeAny(u8, trimmed_allowlist, ",;");
    while (it.next()) |entry_raw| {
        const entry = std.mem.trim(u8, entry_raw, " \t\r\n");
        if (entry.len == 0) continue;
        if (std.ascii.startsWithIgnoreCase(trimmed_command, entry)) return true;
    }
    return false;
}

test "isCommandAllowed supports empty and prefixed allowlists" {
    try std.testing.expect(isCommandAllowed("printf hello", ""));
    try std.testing.expect(isCommandAllowed("printf hello", "printf"));
    try std.testing.expect(!isCommandAllowed("uname -a", "printf,echo"));
}
