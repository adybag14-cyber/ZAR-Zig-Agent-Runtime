// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const dhcp = @import("protocol/dhcp.zig");
const dns = @import("protocol/dns.zig");
const tcp = @import("protocol/tcp.zig");
const udp = @import("protocol/udp.zig");
const filesystem = @import("baremetal/filesystem.zig");
const net = @import("pal/net.zig");
const runtime_state = @import("runtime/state.zig");
const codec = @import("baremetal/tool_service/codec.zig");

pub const RunOptions = struct {
    duration_ms: u64 = 125,
    warmup_ms: u64 = 25,
    filter: ?[]const u8 = null,
};

pub const Summary = struct {
    cases_run: usize,
    total_ops: u64,
    total_ns: u64,
};

pub const Case = struct {
    name: []const u8,
    description: []const u8,
    batch_iterations: usize,
    runFn: *const fn (iterations: usize) anyerror!u64,
};

pub const all_cases = [_]Case{
    .{
        .name = "protocol.dns_roundtrip",
        .description = "DNS query and A-response encode/decode roundtrip",
        .batch_iterations = 512,
        .runFn = benchDnsRoundtrip,
    },
    .{
        .name = "protocol.dhcp_discover",
        .description = "DHCP discover encode/decode roundtrip",
        .batch_iterations = 512,
        .runFn = benchDhcpDiscover,
    },
    .{
        .name = "protocol.tcp_handshake_payload",
        .description = "TCP handshake, payload, and ACK progression",
        .batch_iterations = 256,
        .runFn = benchTcpHandshakePayload,
    },
    .{
        .name = "runtime.state_queue_cycle",
        .description = "Runtime queue enqueue/dequeue/release churn",
        .batch_iterations = 256,
        .runFn = benchRuntimeStateQueueCycle,
    },
    .{
        .name = "tool_service.codec_parse",
        .description = "Typed tool-service frame parsing and batch prefix consumption",
        .batch_iterations = 1024,
        .runFn = benchToolServiceCodecParse,
    },
    .{
        .name = "filesystem.persistence_cycle",
        .description = "Bare-metal filesystem create/write/read/stat/delete churn on the active backend",
        .batch_iterations = 96,
        .runFn = benchFilesystemPersistenceCycle,
    },
    .{
        .name = "filesystem.overlay_read_cycle",
        .description = "Virtual /proc,/sys,/dev overlay list/read churn through the filesystem surface",
        .batch_iterations = 128,
        .runFn = benchFilesystemOverlayReadCycle,
    },
    .{
        .name = "network.rtl8139_udp_loopback",
        .description = "Synthetic RTL8139 UDP send/poll loopback through the PAL transport surface",
        .batch_iterations = 128,
        .runFn = benchRtl8139UdpLoopback,
    },
    .{
        .name = "network.e1000_udp_loopback",
        .description = "Synthetic E1000 UDP send/poll loopback through the PAL transport surface",
        .batch_iterations = 128,
        .runFn = benchE1000UdpLoopback,
    },
};

pub fn list(writer: anytype) !void {
    for (all_cases) |case| {
        try writer.print("{s}\t{s}\n", .{ case.name, case.description });
    }
}

pub fn run(writer: anytype, options: RunOptions) !Summary {
    try writer.print("BENCH:START duration_ms={d} warmup_ms={d}\n", .{ options.duration_ms, options.warmup_ms });

    var cases_run: usize = 0;
    var total_ops: u64 = 0;
    var total_ns: u64 = 0;

    for (all_cases) |case| {
        if (!matchesFilter(case.name, options.filter)) continue;

        const result = try runCase(case, options);
        try writer.print(
            "BENCH:CASE name={s} ops={d} total_ns={d} ns_per_op={d} checksum={d}\n",
            .{ case.name, result.ops, result.total_ns, result.ns_per_op, result.checksum },
        );
        cases_run += 1;
        total_ops += result.ops;
        total_ns += result.total_ns;
    }

    try writer.print("BENCH:END cases={d} total_ops={d} total_ns={d}\n", .{ cases_run, total_ops, total_ns });
    return .{
        .cases_run = cases_run,
        .total_ops = total_ops,
        .total_ns = total_ns,
    };
}

fn matchesFilter(name: []const u8, filter: ?[]const u8) bool {
    const value = filter orelse return true;
    if (value.len == 0) return true;
    return std.mem.indexOf(u8, name, value) != null;
}

const CaseResult = struct {
    ops: u64,
    total_ns: u64,
    ns_per_op: u64,
    checksum: u64,
};

fn runCase(case: Case, options: RunOptions) !CaseResult {
    try warmupCase(case, options.warmup_ms);

    const started_ns = benchNowNs();
    var ops: u64 = 0;
    var checksum: u64 = 0;
    const duration_ns = options.duration_ms * std.time.ns_per_ms;

    while (ops == 0 or benchNowNs() - started_ns < duration_ns) {
        checksum +%= try case.runFn(case.batch_iterations);
        ops += case.batch_iterations;
    }

    const total_ns = @as(u64, @intCast(benchNowNs() - started_ns));
    return .{
        .ops = ops,
        .total_ns = total_ns,
        .ns_per_op = if (ops == 0) 0 else total_ns / ops,
        .checksum = checksum,
    };
}

fn warmupCase(case: Case, warmup_ms: u64) !void {
    if (warmup_ms == 0) return;

    const started_ns = benchNowNs();
    const duration_ns = warmup_ms * std.time.ns_per_ms;
    const warmup_iterations = @max(@as(usize, 1), case.batch_iterations / 8);
    var checksum: u64 = 0;
    while (benchNowNs() - started_ns < duration_ns) {
        checksum +%= try case.runFn(warmup_iterations);
    }
    std.mem.doNotOptimizeAway(&checksum);
}

fn benchNowNs() i96 {
    return std.Io.Clock.awake.now(std.Io.Threaded.global_single_threaded.io()).nanoseconds;
}

fn benchDnsRoundtrip(iterations: usize) !u64 {
    const name = "bench.zar.local";
    var query_buffer: [512]u8 = undefined;
    var response_buffer: [512]u8 = undefined;
    var checksum: u64 = 0;

    for (0..iterations) |idx| {
        const id: u16 = @intCast(0x1000 + (idx % 0x0FFF));
        const query_len = try dns.encodeQuery(query_buffer[0..], id, name, dns.type_a);
        const query_packet = try dns.decode(query_buffer[0..query_len]);

        const address = [4]u8{ 192, 168, @as(u8, @intCast(idx & 0xFF)), 42 };
        const response_len = try dns.encodeAResponse(response_buffer[0..], id, name, 60, address);
        const response_packet = try dns.decode(response_buffer[0..response_len]);

        checksum +%= query_packet.id;
        checksum +%= query_packet.question_name_len;
        checksum +%= response_packet.id;
        checksum +%= response_packet.answer_count_total;
        checksum +%= response_packet.answers[0].ttl;
        checksum +%= response_packet.answers[0].data_len;
        checksum +%= response_packet.answers[0].data[3];
    }

    return checksum;
}

fn benchDhcpDiscover(iterations: usize) !u64 {
    const client_mac = [6]u8{ 0x52, 0x54, 0x00, 0x12, 0x34, 0x56 };
    const params = [_]u8{ dhcp.option_subnet_mask, dhcp.option_router, dhcp.option_dns_server, dhcp.option_lease_time, dhcp.option_server_identifier };
    var buffer: [512]u8 = undefined;
    var checksum: u64 = 0;

    for (0..iterations) |idx| {
        const xid: u32 = @intCast(0xA0B0_C000 + idx);
        const len = try dhcp.encodeDiscover(buffer[0..], client_mac, xid, params[0..]);
        const packet = try dhcp.decode(buffer[0..len]);

        checksum +%= packet.transaction_id;
        checksum +%= packet.flags;
        checksum +%= packet.parameter_request_list.len;
        checksum +%= packet.client_identifier.len;
        checksum +%= packet.options.len;
        checksum +%= packet.client_mac[5];
    }

    return checksum;
}

fn benchTcpHandshakePayload(iterations: usize) !u64 {
    const client_ip = [4]u8{ 192, 168, 56, 10 };
    const server_ip = [4]u8{ 192, 168, 56, 1 };
    const payload = "PING";
    var checksum: u64 = 0;

    for (0..iterations) |idx| {
        const initial_sequence: u32 = @intCast(0x0102_0304 + idx);
        const initial_server_sequence: u32 = @intCast(0xA0B0_C0D0 + idx);

        var client = tcp.Session.initClient(4321, 443, initial_sequence, 4096);
        var server = tcp.Session.initServer(443, 4321, initial_server_sequence, 8192);

        const syn = try client.buildSyn();
        var syn_segment: [tcp.header_len]u8 = undefined;
        const syn_len = try tcp.encodeOutboundSegment(client, syn, syn_segment[0..], client_ip, server_ip);
        const syn_packet = try tcp.decode(syn_segment[0..syn_len], client_ip, server_ip);

        const syn_ack = try server.acceptSyn(syn_packet);
        var syn_ack_segment: [tcp.header_len]u8 = undefined;
        const syn_ack_len = try tcp.encodeOutboundSegment(server, syn_ack, syn_ack_segment[0..], server_ip, client_ip);
        const syn_ack_packet = try tcp.decode(syn_ack_segment[0..syn_ack_len], server_ip, client_ip);

        const ack = try client.acceptSynAck(syn_ack_packet);
        var ack_segment: [tcp.header_len]u8 = undefined;
        const ack_len = try tcp.encodeOutboundSegment(client, ack, ack_segment[0..], client_ip, server_ip);
        const ack_packet = try tcp.decode(ack_segment[0..ack_len], client_ip, server_ip);
        try server.acceptAck(ack_packet);

        const outbound_payload = try client.buildPayload(payload);
        var payload_segment: [tcp.header_len + payload.len]u8 = undefined;
        const payload_len = try tcp.encodeOutboundSegment(client, outbound_payload, payload_segment[0..], client_ip, server_ip);
        const payload_packet = try tcp.decode(payload_segment[0..payload_len], client_ip, server_ip);
        try server.acceptPayload(payload_packet);

        const payload_ack = try server.buildAck();
        var payload_ack_segment: [tcp.header_len]u8 = undefined;
        const payload_ack_len = try tcp.encodeOutboundSegment(server, payload_ack, payload_ack_segment[0..], server_ip, client_ip);
        const payload_ack_packet = try tcp.decode(payload_ack_segment[0..payload_ack_len], server_ip, client_ip);
        try client.acceptAck(payload_ack_packet);

        checksum +%= client.send_next;
        checksum +%= server.recv_next;
        checksum +%= client.bytesInFlight();
        checksum +%= client.congestionWindowBytes();
        checksum +%= payload_packet.sequence_number;
    }

    return checksum;
}

fn benchRuntimeStateQueueCycle(iterations: usize) !u64 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var state = runtime_state.RuntimeState.init(allocator);
    defer state.deinit();

    var checksum: u64 = 0;
    for (0..iterations) |idx| {
        const session_id = try std.fmt.allocPrint(allocator, "bench-session-{d}", .{idx});
        const message = try std.fmt.allocPrint(allocator, "message-{d}", .{idx});
        try state.upsertSession(session_id, message, @as(i64, @intCast(1000 + idx)));

        _ = try state.enqueueJob(.exec, "{\"cmd\":\"echo bench\"}");
        _ = try state.enqueueJob(.file_read, "{\"path\":\"README.md\"}");

        const first = state.dequeueJob().?;
        checksum +%= first.id;
        checksum +%= @as(u64, @intFromEnum(first.kind));
        state.releaseJob(first);

        const second = state.dequeueJob().?;
        checksum +%= second.id;
        checksum +%= @as(u64, @intFromEnum(second.kind));
        state.releaseJob(second);

        checksum +%= state.sessionCount();
        checksum +%= state.queueDepth();
        checksum +%= state.leasedDepth();
    }

    return checksum;
}

fn benchToolServiceCodecParse(iterations: usize) !u64 {
    const command_frame = "REQ 7 CMD help\n";
    const batch_frames: []const u8 =
        "REQ 8 GET /runtime/state/runtime-state.json\n" ++
        "REQ 9 DISPLAYOUTPUTS\n" ++
        "REQ 10 WORKSPACEAUTORUNLIST\n";

    var checksum: u64 = 0;
    for (0..iterations) |_| {
        const framed = try codec.parseFramedRequest(command_frame);
        checksum +%= framed.request_id;
        switch (framed.operation) {
            .command => |value| checksum +%= value.len,
            else => return error.UnexpectedCodecShape,
        }

        var remaining: []const u8 = batch_frames;
        while (codec.trimLeftWhitespace(remaining).len != 0) {
            const consumed = try codec.parseFramedRequestPrefix(remaining);
            checksum +%= consumed.framed.request_id;
            checksum +%= consumed.consumed_len;
            remaining = remaining[consumed.consumed_len..];
        }
    }

    return checksum;
}

fn benchFilesystemPersistenceCycle(iterations: usize) !u64 {
    filesystem.resetForTest();
    try filesystem.init();

    var checksum: u64 = 0;
    var dir_buffer: [64]u8 = undefined;
    var file_buffer: [96]u8 = undefined;
    var payload_buffer: [64]u8 = undefined;

    for (0..iterations) |idx| {
        const tick: u64 = @intCast(idx + 1);
        const dir = try std.fmt.bufPrint(&dir_buffer, "/bench/{d}", .{idx % 16});
        const file = try std.fmt.bufPrint(&file_buffer, "{s}/state.txt", .{dir});
        const payload = try std.fmt.bufPrint(&payload_buffer, "bench-payload-{d}", .{idx});

        try filesystem.createDirPath(dir);
        try filesystem.writeFile(file, payload, tick);

        const stat = try filesystem.statSummary(file);
        const listing = try filesystem.listDirectoryAlloc(std.heap.page_allocator, dir, 256);
        defer std.heap.page_allocator.free(listing);
        const readback = try filesystem.readFileAlloc(std.heap.page_allocator, file, 256);
        defer std.heap.page_allocator.free(readback);

        checksum +%= stat.size;
        checksum +%= listing.len;
        checksum +%= readback.len;
        checksum +%= stat.entry_id;
        checksum +%= tick;

        try filesystem.deleteFile(file, tick + 1);
        try filesystem.deleteTree(dir, tick + 2);
    }

    return checksum;
}

fn benchFilesystemOverlayReadCycle(iterations: usize) !u64 {
    filesystem.resetForTest();
    try filesystem.init();

    var checksum: u64 = 0;
    for (0..iterations) |_| {
        const root_listing = try filesystem.listDirectoryAlloc(std.heap.page_allocator, "/", 256);
        defer std.heap.page_allocator.free(root_listing);
        const dev_listing = try filesystem.listDirectoryAlloc(std.heap.page_allocator, "/dev", 256);
        defer std.heap.page_allocator.free(dev_listing);
        const dev_storage = try filesystem.readFileAlloc(std.heap.page_allocator, "/dev/storage/state", 512);
        defer std.heap.page_allocator.free(dev_storage);
        const proc_runtime = try filesystem.readFileAlloc(std.heap.page_allocator, "/proc/runtime/snapshot", 1024);
        defer std.heap.page_allocator.free(proc_runtime);
        const sys_storage = try filesystem.readFileAlloc(std.heap.page_allocator, "/sys/storage/state", 512);
        defer std.heap.page_allocator.free(sys_storage);

        checksum +%= root_listing.len;
        checksum +%= dev_listing.len;
        checksum +%= dev_storage.len;
        checksum +%= proc_runtime.len;
        checksum +%= sys_storage.len;
    }

    return checksum;
}

fn benchRtl8139UdpLoopback(iterations: usize) !u64 {
    return benchNicUdpLoopback(iterations, .rtl8139);
}

fn benchE1000UdpLoopback(iterations: usize) !u64 {
    return benchNicUdpLoopback(iterations, .e1000);
}

fn benchNicUdpLoopback(iterations: usize, backend: net.Backend) !u64 {
    net.enableSyntheticBackendForBenchmark(backend);
    defer net.disableSyntheticBackendForBenchmark();

    const destination_mac = [_]u8{ 0x02, 0x5A, 0x52, 0x10, 0x00, switch (backend) { .rtl8139 => 0x39, .e1000 => 0x49 } };
    const source_ip = [_]u8{ 192, 168, 56, 10 };
    const destination_ip = [_]u8{ 192, 168, 56, 1 };
    const payload = "bench-udp";
    var checksum: u64 = 0;

    for (0..iterations) |idx| {
        const source_port: u16 = @intCast(32000 + (idx % 1024));
        const destination_port: u16 = @intCast(33000 + (idx % 1024));
        _ = try net.sendUdpPacket(destination_mac, source_ip, destination_ip, source_port, destination_port, payload);

        var packet: net.UdpPacket = undefined;
        const received = try net.pollUdpPacketStrictInto(&packet);
        if (!received) return error.BenchmarkLoopbackMissing;

        checksum +%= packet.source_port;
        checksum +%= packet.destination_port;
        checksum +%= packet.payload_len;
        checksum +%= packet.checksum_value;
        checksum +%= packet.payload[0];
        checksum +%= packet.ethernet_destination[5];
    }

    return checksum;
}

test "benchmark catalog includes expected protocol and runtime cases" {
    try std.testing.expect(findCase("protocol.dns_roundtrip") != null);
    try std.testing.expect(findCase("protocol.tcp_handshake_payload") != null);
    try std.testing.expect(findCase("runtime.state_queue_cycle") != null);
    try std.testing.expect(findCase("tool_service.codec_parse") != null);
    try std.testing.expect(findCase("filesystem.persistence_cycle") != null);
    try std.testing.expect(findCase("filesystem.overlay_read_cycle") != null);
    try std.testing.expect(findCase("network.rtl8139_udp_loopback") != null);
    try std.testing.expect(findCase("network.e1000_udp_loopback") != null);
}

test "benchmark suite writes markers for filtered run" {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();

    const summary = try run(&out.writer, .{
        .duration_ms = 1,
        .warmup_ms = 0,
        .filter = "protocol.dns_roundtrip",
    });
    try std.testing.expectEqual(@as(usize, 1), summary.cases_run);

    const payload = try out.toOwnedSlice();
    defer std.testing.allocator.free(payload);
    try std.testing.expect(std.mem.indexOf(u8, payload, "BENCH:START") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "BENCH:CASE name=protocol.dns_roundtrip") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "BENCH:END cases=1") != null);
}

test "benchmark case functions execute one batch" {
    for (all_cases) |case| {
        const checksum = try case.runFn(1);
        try std.testing.expect(checksum != 0);
    }
}

fn findCase(name: []const u8) ?Case {
    for (all_cases) |case| {
        if (std.mem.eql(u8, case.name, name)) return case;
    }
    return null;
}
