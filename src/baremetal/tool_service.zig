const std = @import("std");
const tool_exec = @import("tool_exec.zig");

pub const Error = tool_exec.Error || std.mem.Allocator.Error || error{
    EmptyRequest,
    InvalidFrame,
    ResponseTooLarge,
};

pub const FramedRequest = struct {
    request_id: u32,
    command: []const u8,
};

pub fn handleCommandRequest(
    allocator: std.mem.Allocator,
    request: []const u8,
    stdout_limit: usize,
    stderr_limit: usize,
    response_limit: usize,
) Error![]u8 {
    const trimmed = std.mem.trim(u8, request, " \t\r\n");
    if (trimmed.len == 0) return error.EmptyRequest;

    var result = try tool_exec.runCapture(allocator, trimmed, stdout_limit, stderr_limit);
    defer result.deinit(allocator);

    if (result.exit_code == 0 and result.stderr.len == 0) {
        if (result.stdout.len > response_limit) return error.ResponseTooLarge;
        return allocator.dupe(u8, result.stdout);
    }

    const detail = if (result.stderr.len != 0) result.stderr else result.stdout;
    const response = try std.fmt.allocPrint(allocator, "ERR exit={d}\n{s}", .{ result.exit_code, detail });
    errdefer allocator.free(response);
    if (response.len > response_limit) return error.ResponseTooLarge;
    return response;
}

pub fn parseFramedCommandRequest(request: []const u8) Error!FramedRequest {
    const trimmed = std.mem.trim(u8, request, " \t\r\n");
    if (trimmed.len == 0) return error.EmptyRequest;
    if (!std.mem.startsWith(u8, trimmed, "REQ ")) return error.InvalidFrame;

    const body = std.mem.trim(u8, trimmed["REQ ".len..], " \t");
    if (body.len == 0) return error.InvalidFrame;

    const separator_index = std.mem.indexOfAny(u8, body, " \t") orelse return error.InvalidFrame;
    const request_id_text = body[0..separator_index];
    const request_id = std.fmt.parseUnsigned(u32, request_id_text, 10) catch return error.InvalidFrame;
    const command = std.mem.trim(u8, body[separator_index + 1 ..], " \t");
    if (command.len == 0) return error.InvalidFrame;

    return .{
        .request_id = request_id,
        .command = command,
    };
}

pub fn handleFramedCommandRequest(
    allocator: std.mem.Allocator,
    request: []const u8,
    stdout_limit: usize,
    stderr_limit: usize,
    response_limit: usize,
) Error![]u8 {
    const framed = try parseFramedCommandRequest(request);
    const payload_limit = if (response_limit > 32) response_limit - 32 else response_limit;
    const payload = try handleCommandRequest(allocator, framed.command, stdout_limit, stderr_limit, payload_limit);
    defer allocator.free(payload);

    const response = try std.fmt.allocPrint(allocator, "RESP {d} {d}\n{s}", .{
        framed.request_id,
        payload.len,
        payload,
    });
    errdefer allocator.free(response);
    if (response.len > response_limit) return error.ResponseTooLarge;
    return response;
}

test "baremetal tool service returns stdout for successful commands" {
    const response = try handleCommandRequest(std.testing.allocator, "echo tcp-service-ok", 256, 256, 256);
    defer std.testing.allocator.free(response);

    try std.testing.expectEqualStrings("tcp-service-ok\n", response);
}

test "baremetal tool service wraps failing command responses" {
    const response = try handleCommandRequest(std.testing.allocator, "missing-command", 256, 256, 256);
    defer std.testing.allocator.free(response);

    try std.testing.expect(std.mem.startsWith(u8, response, "ERR exit=127\n"));
    try std.testing.expect(std.mem.indexOf(u8, response, "unknown command") != null);
}

test "baremetal tool service parses framed requests" {
    const framed = try parseFramedCommandRequest("REQ 7 echo tcp-service-ok");
    try std.testing.expectEqual(@as(u32, 7), framed.request_id);
    try std.testing.expectEqualStrings("echo tcp-service-ok", framed.command);
}

test "baremetal tool service rejects invalid framed requests" {
    try std.testing.expectError(error.InvalidFrame, parseFramedCommandRequest("echo tcp-service-ok"));
    try std.testing.expectError(error.InvalidFrame, parseFramedCommandRequest("REQ nope echo tcp-service-ok"));
    try std.testing.expectError(error.InvalidFrame, parseFramedCommandRequest("REQ 7"));
}

test "baremetal tool service returns framed responses for successful commands" {
    const response = try handleFramedCommandRequest(std.testing.allocator, "REQ 7 echo tcp-service-ok", 256, 256, 256);
    defer std.testing.allocator.free(response);

    try std.testing.expectEqualStrings("RESP 7 15\ntcp-service-ok\n", response);
}

test "baremetal tool service returns framed responses for failing commands" {
    const response = try handleFramedCommandRequest(std.testing.allocator, "REQ 9 missing-command", 256, 256, 256);
    defer std.testing.allocator.free(response);

    try std.testing.expect(std.mem.startsWith(u8, response, "RESP 9 "));
    try std.testing.expect(std.mem.indexOf(u8, response, "ERR exit=127\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "unknown command") != null);
}
