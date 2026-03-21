// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const suite = @import("benchmark_suite.zig");

const CliOptions = struct {
    list: bool = false,
    duration_ms: u64 = 125,
    warmup_ms: u64 = 25,
    filter: ?[]const u8 = null,
};

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const io = init.io;

    const options = try parseArgs(allocator, init.minimal.args);

    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();

    if (options.list) {
        try suite.list(&out.writer);
    } else {
        const summary = try suite.run(&out.writer, .{
            .duration_ms = options.duration_ms,
            .warmup_ms = options.warmup_ms,
            .filter = options.filter,
        });
        if (summary.cases_run == 0) return error.NoBenchmarkCasesMatched;
    }

    const bytes = try out.toOwnedSlice();
    defer allocator.free(bytes);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.writeAll(bytes);
    try stdout.flush();
}

fn parseArgs(allocator: std.mem.Allocator, args: std.process.Args) !CliOptions {
    const slice = try args.toSlice(allocator);
    return parseArgsFromSlice(slice);
}

fn parseArgsFromSlice(args: []const []const u8) !CliOptions {
    var result: CliOptions = .{};
    if (args.len <= 1) return result;
    var idx: usize = 1;
    while (idx < args.len) {
        const arg = args[idx];
        if (std.mem.eql(u8, arg, "--list")) {
            result.list = true;
            idx += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--duration-ms")) {
            if (idx + 1 >= args.len) return error.MissingDurationValue;
            result.duration_ms = std.fmt.parseUnsigned(u64, args[idx + 1], 10) catch return error.InvalidDurationValue;
            idx += 2;
            continue;
        }
        if (std.mem.eql(u8, arg, "--warmup-ms")) {
            if (idx + 1 >= args.len) return error.MissingWarmupValue;
            result.warmup_ms = std.fmt.parseUnsigned(u64, args[idx + 1], 10) catch return error.InvalidWarmupValue;
            idx += 2;
            continue;
        }
        if (std.mem.eql(u8, arg, "--filter")) {
            if (idx + 1 >= args.len) return error.MissingFilterValue;
            result.filter = args[idx + 1];
            idx += 2;
            continue;
        }
        return error.UnknownArgument;
    }
    return result;
}

test "parseArgsFromSlice handles list and filter flags" {
    const parsed = try parseArgsFromSlice(&.{
        "openclaw-zig-bench",
        "--list",
        "--duration-ms",
        "9",
        "--warmup-ms",
        "3",
        "--filter",
        "protocol",
    });
    try std.testing.expect(parsed.list);
    try std.testing.expectEqual(@as(u64, 9), parsed.duration_ms);
    try std.testing.expectEqual(@as(u64, 3), parsed.warmup_ms);
    try std.testing.expect(std.mem.eql(u8, parsed.filter.?, "protocol"));
}
