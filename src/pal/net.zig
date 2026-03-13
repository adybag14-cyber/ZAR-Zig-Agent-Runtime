const std = @import("std");
const builtin = @import("builtin");
const time_util = @import("../util/time.zig");
const abi = @import("../baremetal/abi.zig");
const rtl8139 = @import("../baremetal/rtl8139.zig");

pub const Response = struct {
    status_code: u16,
    body: []u8,
    latency_ms: i64,

    pub fn deinit(self: *Response, allocator: std.mem.Allocator) void {
        allocator.free(self.body);
    }
};

pub const EthernetState = abi.BaremetalEthernetState;
pub const Error = rtl8139.Error;

pub fn post(
    allocator: std.mem.Allocator,
    url: []const u8,
    payload: []const u8,
    headers: []const std.http.Header,
) !Response {
    var client: std.http.Client = .{
        .allocator = allocator,
        .io = std.Io.Threaded.global_single_threaded.io(),
    };
    defer client.deinit();

    var response_body: std.Io.Writer.Allocating = .init(allocator);
    defer response_body.deinit();
    const started_ms = time_util.nowMs();

    const fetch_result = try client.fetch(.{
        .location = .{ .url = url },
        .method = .POST,
        .payload = payload,
        .keep_alive = false,
        .extra_headers = headers,
        .response_writer = &response_body.writer,
    });

    return .{
        .status_code = @as(u16, @intCast(@intFromEnum(fetch_result.status))),
        .body = try response_body.toOwnedSlice(),
        .latency_ms = time_util.nowMs() - started_ms,
    };
}

pub fn initDevice() bool {
    return rtl8139.init();
}

pub fn resetDeviceForTest() void {
    if (!builtin.is_test) return;
    rtl8139.resetForTest();
}

pub fn deviceState() *const EthernetState {
    return rtl8139.statePtr();
}

pub fn macAddress() [6]u8 {
    return rtl8139.statePtr().mac;
}

pub fn sendFrame(frame: []const u8) Error!void {
    try rtl8139.sendFrame(frame);
}

pub fn pollReceive() Error!u32 {
    return try rtl8139.pollReceive();
}

pub fn rxByte(index: u32) u8 {
    return rtl8139.rxByte(index);
}

test "baremetal net pal bridges rtl8139 mock device" {
    rtl8139.testEnableMockDevice();
    defer rtl8139.testDisableMockDevice();

    try std.testing.expect(initDevice());
    const mac = macAddress();
    try std.testing.expectEqual(@as(u8, 0x52), mac[0]);

    var frame = [_]u8{0} ** 64;
    std.mem.copyForwards(u8, frame[0..6], mac[0..]);
    std.mem.copyForwards(u8, frame[6..12], mac[0..]);
    frame[12] = 0x88;
    frame[13] = 0xB5;
    frame[14] = 0x41;
    try sendFrame(frame[0..]);

    const rx_len = try pollReceive();
    try std.testing.expectEqual(@as(u32, 64), rx_len);
    try std.testing.expectEqual(@as(u8, 0x88), rxByte(12));
    try std.testing.expectEqual(@as(u8, 0x41), rxByte(14));
}
