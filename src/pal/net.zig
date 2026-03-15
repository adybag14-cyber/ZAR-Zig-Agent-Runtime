const std = @import("std");
const builtin = @import("builtin");
const time_util = @import("../util/time.zig");
const abi = @import("../baremetal/abi.zig");
const rtl8139 = @import("../baremetal/rtl8139.zig");
const ethernet = @import("../protocol/ethernet.zig");
const arp = @import("../protocol/arp.zig");
const dhcp = @import("../protocol/dhcp.zig");
const dns = @import("../protocol/dns.zig");
const ipv4 = @import("../protocol/ipv4.zig");
const tcp = @import("../protocol/tcp.zig");
const udp = @import("../protocol/udp.zig");

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
pub const ArpPacket = arp.Packet;
pub const ArpError = rtl8139.Error || arp.Error;
pub const DhcpError = rtl8139.Error || ethernet.Error || ipv4.Error || udp.Error || dhcp.Error;
pub const DnsError = rtl8139.Error || ethernet.Error || ipv4.Error || udp.Error || dns.Error;
pub const Ipv4Error = rtl8139.Error || ethernet.Error || ipv4.Error;
pub const TcpError = rtl8139.Error || ethernet.Error || ipv4.Error || tcp.Error;
pub const UdpError = rtl8139.Error || ethernet.Error || ipv4.Error || udp.Error;
pub const RouteError = error{
    RouteUnconfigured,
    MissingLeaseIp,
    MissingSubnetMask,
    AddressUnresolved,
};
pub const RoutedUdpError = UdpError || RouteError;
pub const StrictDhcpPollError = rtl8139.Error || ethernet.Error || ipv4.Error || udp.Error || dhcp.Error || error{ NotIpv4, NotUdp, NotDhcp };
pub const StrictDnsPollError = rtl8139.Error || ethernet.Error || ipv4.Error || udp.Error || dns.Error || error{ NotIpv4, NotUdp, NotDns };
pub const StrictIpv4PollError = rtl8139.Error || ethernet.Error || ipv4.Error || error{NotIpv4};
pub const StrictTcpPollError = rtl8139.Error || ethernet.Error || ipv4.Error || tcp.Error || error{ NotIpv4, NotTcp };
pub const StrictUdpPollError = rtl8139.Error || ethernet.Error || ipv4.Error || udp.Error || error{ NotIpv4, NotUdp };
pub const max_frame_len: usize = 2048;
pub const max_ipv4_payload_len: usize = max_frame_len - ethernet.header_len - ipv4.header_len;
pub const max_tcp_payload_len: usize = max_ipv4_payload_len - tcp.header_len;
pub const max_udp_payload_len: usize = max_ipv4_payload_len - udp.header_len;
pub const max_dhcp_parameter_request_list_len: usize = 64;
pub const max_dhcp_client_identifier_len: usize = 32;
pub const max_dhcp_hostname_len: usize = 64;
pub const max_dhcp_dns_servers: usize = 2;
pub const max_dns_name_len: usize = dns.max_name_len;
pub const max_dns_answers: usize = dns.max_answers;
pub const max_dns_answer_data_len: usize = dns.max_answer_data_len;
pub const arp_cache_capacity: usize = 8;

pub const Ipv4Packet = struct {
    ethernet_destination: [ethernet.mac_len]u8,
    ethernet_source: [ethernet.mac_len]u8,
    header: ipv4.Header,
    total_len: u16,
    payload_len: usize,
    payload: [max_ipv4_payload_len]u8,
};

pub const UdpPacket = struct {
    ethernet_destination: [ethernet.mac_len]u8,
    ethernet_source: [ethernet.mac_len]u8,
    ipv4_header: ipv4.Header,
    source_port: u16,
    destination_port: u16,
    checksum_value: u16,
    payload_len: usize,
    payload: [max_udp_payload_len]u8,
};

pub const TcpPacket = struct {
    ethernet_destination: [ethernet.mac_len]u8,
    ethernet_source: [ethernet.mac_len]u8,
    ipv4_header: ipv4.Header,
    source_port: u16,
    destination_port: u16,
    sequence_number: u32,
    acknowledgment_number: u32,
    flags: u16,
    window_size: u16,
    checksum_value: u16,
    urgent_pointer: u16,
    payload_len: usize,
    payload: [max_tcp_payload_len]u8,
};

pub const DhcpPacket = struct {
    ethernet_destination: [ethernet.mac_len]u8,
    ethernet_source: [ethernet.mac_len]u8,
    ipv4_header: ipv4.Header,
    source_port: u16,
    destination_port: u16,
    udp_checksum_value: u16,
    op: u8,
    transaction_id: u32,
    flags: u16,
    client_ip: [4]u8,
    your_ip: [4]u8,
    server_ip: [4]u8,
    gateway_ip: [4]u8,
    client_mac: [ethernet.mac_len]u8,
    message_type: ?u8,
    subnet_mask_valid: bool,
    subnet_mask: [4]u8,
    router_valid: bool,
    router: [4]u8,
    requested_ip_valid: bool,
    requested_ip: [4]u8,
    server_identifier_valid: bool,
    server_identifier: [4]u8,
    lease_time_valid: bool,
    lease_time_seconds: u32,
    max_message_size_valid: bool,
    max_message_size: u16,
    dns_server_count: usize,
    dns_servers: [max_dhcp_dns_servers][4]u8,
    parameter_request_list_len: usize,
    parameter_request_list: [max_dhcp_parameter_request_list_len]u8,
    client_identifier_len: usize,
    client_identifier: [max_dhcp_client_identifier_len]u8,
    hostname_len: usize,
    hostname: [max_dhcp_hostname_len]u8,
    options_len: usize,
    options: [max_udp_payload_len]u8,
};

pub const DnsPacket = struct {
    ethernet_destination: [ethernet.mac_len]u8,
    ethernet_source: [ethernet.mac_len]u8,
    ipv4_header: ipv4.Header,
    source_port: u16,
    destination_port: u16,
    udp_checksum_value: u16,
    id: u16,
    flags: u16,
    question_count: u16,
    answer_count_total: u16,
    authority_count: u16,
    additional_count: u16,
    question_name_len: usize,
    question_name: [max_dns_name_len]u8,
    question_type: u16,
    question_class: u16,
    answer_count: usize,
    answers: [max_dns_answers]dns.Answer,
};

pub const ArpCacheEntry = struct {
    valid: bool,
    ip: [4]u8,
    mac: [ethernet.mac_len]u8,
};

pub const RouteDecision = struct {
    next_hop_ip: [4]u8,
    used_gateway: bool,
};

pub const RouteState = struct {
    configured: bool,
    local_ip: [4]u8,
    subnet_mask_valid: bool,
    subnet_mask: [4]u8,
    gateway_valid: bool,
    gateway: [4]u8,
    last_next_hop: [4]u8,
    last_used_gateway: bool,
    last_cache_hit: bool,
    pending_resolution: bool,
    pending_ip: [4]u8,
    cache_entry_count: usize,
    cache: [arp_cache_capacity]ArpCacheEntry,
};

fn defaultRouteState() RouteState {
    return .{
        .configured = false,
        .local_ip = [_]u8{ 0, 0, 0, 0 },
        .subnet_mask_valid = false,
        .subnet_mask = [_]u8{ 0, 0, 0, 0 },
        .gateway_valid = false,
        .gateway = [_]u8{ 0, 0, 0, 0 },
        .last_next_hop = [_]u8{ 0, 0, 0, 0 },
        .last_used_gateway = false,
        .last_cache_hit = false,
        .pending_resolution = false,
        .pending_ip = [_]u8{ 0, 0, 0, 0 },
        .cache_entry_count = 0,
        .cache = [_]ArpCacheEntry{.{
            .valid = false,
            .ip = [_]u8{ 0, 0, 0, 0 },
            .mac = [_]u8{ 0, 0, 0, 0, 0, 0 },
        }} ** arp_cache_capacity,
    };
}

const DnsState = struct {
    server_count: usize,
    servers: [max_dhcp_dns_servers][4]u8,
    next_query_id: u16,
};

fn defaultDnsState() DnsState {
    return .{
        .server_count = 0,
        .servers = [_][4]u8{
            [_]u8{ 0, 0, 0, 0 },
            [_]u8{ 0, 0, 0, 0 },
        },
        .next_query_id = 1,
    };
}

var route_state: RouteState = defaultRouteState();
var route_cache_insert_index: usize = 0;
var dns_state: DnsState = defaultDnsState();
var next_tcp_local_port: u16 = 49152;

fn ipv4IsZero(ip: [4]u8) bool {
    return std.mem.eql(u8, ip[0..], &[_]u8{ 0, 0, 0, 0 });
}

fn macIsZero(mac: [ethernet.mac_len]u8) bool {
    return std.mem.eql(u8, mac[0..], &[_]u8{ 0, 0, 0, 0, 0, 0 });
}

fn sameSubnet(local_ip: [4]u8, destination_ip: [4]u8, subnet_mask: [4]u8) bool {
    var index: usize = 0;
    while (index < 4) : (index += 1) {
        if ((local_ip[index] & subnet_mask[index]) != (destination_ip[index] & subnet_mask[index])) return false;
    }
    return true;
}

fn arpCacheIndexFor(ip: [4]u8) ?usize {
    var index: usize = 0;
    while (index < route_state.cache.len) : (index += 1) {
        if (route_state.cache[index].valid and std.mem.eql(u8, route_state.cache[index].ip[0..], ip[0..])) {
            return index;
        }
    }
    return null;
}

fn arpCacheUpsert(ip: [4]u8, mac: [ethernet.mac_len]u8) void {
    if (arpCacheIndexFor(ip)) |existing_index| {
        route_state.cache[existing_index].mac = mac;
        return;
    }

    const insert_index = route_cache_insert_index;
    const was_valid = route_state.cache[insert_index].valid;
    route_state.cache[insert_index] = .{
        .valid = true,
        .ip = ip,
        .mac = mac,
    };
    if (!was_valid and route_state.cache_entry_count < route_state.cache.len) {
        route_state.cache_entry_count += 1;
    }
    route_cache_insert_index = (route_cache_insert_index + 1) % route_state.cache.len;
}

pub fn clearRouteState() void {
    route_state = defaultRouteState();
    route_cache_insert_index = 0;
    dns_state = defaultDnsState();
    next_tcp_local_port = 49152;
}

pub fn clearRouteStateForTest() void {
    if (!builtin.is_test) return;
    clearRouteState();
}

pub fn routeStatePtr() *const RouteState {
    return &route_state;
}

pub fn configureIpv4Route(local_ip: [4]u8, subnet_mask: ?[4]u8, gateway: ?[4]u8) void {
    route_state.configured = true;
    route_state.local_ip = local_ip;
    route_state.subnet_mask_valid = subnet_mask != null;
    route_state.subnet_mask = subnet_mask orelse [_]u8{ 0, 0, 0, 0 };
    route_state.gateway_valid = gateway != null and !ipv4IsZero(gateway.?);
    route_state.gateway = gateway orelse [_]u8{ 0, 0, 0, 0 };
    route_state.last_next_hop = [_]u8{ 0, 0, 0, 0 };
    route_state.last_used_gateway = false;
    route_state.last_cache_hit = false;
    route_state.pending_resolution = false;
    route_state.pending_ip = [_]u8{ 0, 0, 0, 0 };
}

pub fn configureDnsServers(servers: []const [4]u8) void {
    dns_state.server_count = @min(servers.len, dns_state.servers.len);
    var index: usize = 0;
    while (index < dns_state.servers.len) : (index += 1) {
        dns_state.servers[index] = if (index < dns_state.server_count) servers[index] else [_]u8{ 0, 0, 0, 0 };
    }
}

pub fn configureDnsServersFromDhcp(packet: *const DhcpPacket) void {
    configureDnsServers(packet.dns_servers[0..packet.dns_server_count]);
}

pub fn configureIpv4RouteFromDhcp(packet: *const DhcpPacket) RouteError!void {
    if (ipv4IsZero(packet.your_ip)) return error.MissingLeaseIp;
    if (!packet.subnet_mask_valid) return error.MissingSubnetMask;
    const gateway: ?[4]u8 = if (packet.router_valid and !ipv4IsZero(packet.router)) packet.router else null;
    configureIpv4Route(packet.your_ip, packet.subnet_mask, gateway);
}

pub fn resolveNextHop(destination_ip: [4]u8) RouteError!RouteDecision {
    if (!route_state.configured) return error.RouteUnconfigured;

    const used_gateway = route_state.subnet_mask_valid and route_state.gateway_valid and
        !sameSubnet(route_state.local_ip, destination_ip, route_state.subnet_mask);
    const next_hop_ip = if (used_gateway) route_state.gateway else destination_ip;
    route_state.last_next_hop = next_hop_ip;
    route_state.last_used_gateway = used_gateway;
    route_state.last_cache_hit = false;
    return .{
        .next_hop_ip = next_hop_ip,
        .used_gateway = used_gateway,
    };
}

pub fn lookupArpCache(ip: [4]u8) ?[ethernet.mac_len]u8 {
    if (arpCacheIndexFor(ip)) |index| {
        route_state.last_cache_hit = true;
        return route_state.cache[index].mac;
    }
    route_state.last_cache_hit = false;
    return null;
}

pub fn learnArpPacket(packet: ArpPacket) bool {
    if (ipv4IsZero(packet.sender_ip) or macIsZero(packet.sender_mac)) return false;
    if (route_state.configured and
        std.mem.eql(u8, route_state.local_ip[0..], packet.sender_ip[0..]) and
        std.mem.eql(u8, macAddress()[0..], packet.sender_mac[0..]))
    {
        return false;
    }

    arpCacheUpsert(packet.sender_ip, packet.sender_mac);
    if (std.mem.eql(u8, route_state.pending_ip[0..], packet.sender_ip[0..])) {
        route_state.pending_resolution = false;
    }
    return true;
}

pub fn sendUdpPacketRouted(
    destination_ip: [4]u8,
    source_port: u16,
    destination_port: u16,
    payload: []const u8,
) RoutedUdpError!u32 {
    const route = try resolveNextHop(destination_ip);
    if (lookupArpCache(route.next_hop_ip)) |destination_mac| {
        return try sendUdpPacket(
            destination_mac,
            route_state.local_ip,
            destination_ip,
            source_port,
            destination_port,
            payload,
        );
    }

    _ = sendArpRequest(route_state.local_ip, route.next_hop_ip) catch |err| switch (err) {
        error.BufferTooSmall => unreachable,
        error.NotAvailable => return error.NotAvailable,
        error.NotInitialized => return error.NotInitialized,
        error.Timeout => return error.Timeout,
        error.HardwareFault => return error.HardwareFault,
        else => return error.HardwareFault,
    };
    route_state.pending_resolution = true;
    route_state.pending_ip = route.next_hop_ip;
    return error.AddressUnresolved;
}

pub fn post(
    allocator: std.mem.Allocator,
    url: []const u8,
    payload: []const u8,
    headers: []const std.http.Header,
) !Response {
    if (builtin.os.tag == .freestanding) {
        return postFreestanding(allocator, url, payload, headers);
    }

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

const PostScheme = enum {
    http,
    https,
};

const ParsedPostUrl = struct {
    scheme: PostScheme,
    host: []const u8,
    port: u16,
    path: []const u8,
};

const HttpResponseMeta = struct {
    status_code: u16,
    body_offset: usize,
};

const post_poll_limit: usize = 4096;
const post_retransmit_ticks: u64 = 32;

fn postFreestanding(
    allocator: std.mem.Allocator,
    url: []const u8,
    payload: []const u8,
    headers: []const std.http.Header,
) !Response {
    const parsed = try parsePostUrl(url);
    if (parsed.scheme != .http) return error.UnsupportedScheme;
    if (!route_state.configured or ipv4IsZero(route_state.local_ip)) return error.RouteUnconfigured;

    const destination_ip = try resolveHostIpv4(parsed.host);
    const destination_mac = try resolveNextHopMac(destination_ip);
    const local_port = allocateTcpLocalPort();
    const request_bytes = try buildHttpPostRequest(allocator, parsed, payload, headers);
    defer allocator.free(request_bytes);
    if (request_bytes.len > max_tcp_payload_len) return error.PayloadTooLarge;

    var client = tcp.Session.initClient(local_port, parsed.port, 0x0C10_0000 +% @as(u32, local_port), 4096);
    const started_ms = time_util.nowMs();
    const syn = try client.buildSynWithTimeout(0, post_retransmit_ticks);
    try sendTcpOutbound(destination_mac, route_state.local_ip, destination_ip, client, syn);

    var poll_tick: u64 = 0;
    while (true) : (poll_tick += 1) {
        if (poll_tick >= post_poll_limit) return error.Timeout;

        if (try handlePostHandshakePacket(destination_mac, destination_ip, &client)) break;
        if (client.pollRetransmit(poll_tick)) |retry_syn| {
            try sendTcpOutbound(destination_mac, route_state.local_ip, destination_ip, client, retry_syn);
        }
    }

    const request_packet = try client.buildPayloadWithTimeout(request_bytes, poll_tick, post_retransmit_ticks);
    try sendTcpOutbound(destination_mac, route_state.local_ip, destination_ip, client, request_packet);

    var response_bytes: std.ArrayList(u8) = .empty;
    defer response_bytes.deinit(allocator);
    var remote_closed = false;

    while (!remote_closed) : (poll_tick += 1) {
        if (poll_tick >= post_poll_limit) return error.Timeout;

        var packet: TcpPacket = undefined;
        const received = pollTcpPacketStrictInto(&packet) catch |err| switch (err) {
            error.NotIpv4, error.NotTcp => false,
            else => return err,
        };
        if (received and tcpPacketMatchesFlow(packet, destination_ip, route_state.local_ip, parsed.port, local_port)) {
            const view = tcpPacketView(&packet);
            if (view.flags == (tcp.flag_fin | tcp.flag_ack)) {
                const ack = try client.acceptFin(view);
                try sendTcpOutbound(destination_mac, route_state.local_ip, destination_ip, client, ack);
                remote_closed = true;
                continue;
            }
            if (view.flags == tcp.flag_ack and view.payload.len == 0) {
                try client.acceptAck(view);
                continue;
            }
            if (view.flags == (tcp.flag_ack | tcp.flag_psh) and view.payload.len != 0) {
                try client.acceptPayload(view);
                try response_bytes.appendSlice(allocator, view.payload);
                const ack = try client.buildAck();
                try sendTcpOutbound(destination_mac, route_state.local_ip, destination_ip, client, ack);
                continue;
            }
        }

        if (client.retransmit.kind == .payload) {
            if (client.pollRetransmit(poll_tick)) |retry_payload| {
                try sendTcpOutbound(destination_mac, route_state.local_ip, destination_ip, client, retry_payload);
            }
        }
    }

    const response_meta = try parseHttpResponseMeta(response_bytes.items);
    return .{
        .status_code = response_meta.status_code,
        .body = try allocator.dupe(u8, response_bytes.items[response_meta.body_offset..]),
        .latency_ms = time_util.nowMs() - started_ms,
    };
}

fn parsePostUrl(url: []const u8) !ParsedPostUrl {
    const trimmed = std.mem.trim(u8, url, " \t\r\n");
    const scheme_sep = std.mem.indexOf(u8, trimmed, "://") orelse return error.UnsupportedUrl;
    const scheme_text = trimmed[0..scheme_sep];
    const remainder = trimmed[scheme_sep + 3 ..];
    if (remainder.len == 0) return error.UnsupportedUrl;

    const scheme: PostScheme = if (std.ascii.eqlIgnoreCase(scheme_text, "http"))
        .http
    else if (std.ascii.eqlIgnoreCase(scheme_text, "https"))
        .https
    else
        return error.UnsupportedScheme;

    const path_start = std.mem.indexOfScalar(u8, remainder, '/') orelse remainder.len;
    const authority = remainder[0..path_start];
    if (authority.len == 0) return error.UnsupportedUrl;

    const path = if (path_start < remainder.len) remainder[path_start..] else "/";
    const colon_index = std.mem.lastIndexOfScalar(u8, authority, ':');
    const host = if (colon_index) |idx| authority[0..idx] else authority;
    if (host.len == 0) return error.UnsupportedUrl;

    const port = if (colon_index) |idx|
        std.fmt.parseUnsigned(u16, authority[idx + 1 ..], 10) catch return error.UnsupportedUrl
    else switch (scheme) {
        .http => @as(u16, 80),
        .https => @as(u16, 443),
    };

    return .{
        .scheme = scheme,
        .host = host,
        .port = port,
        .path = path,
    };
}

fn parseIpv4Literal(text: []const u8) error{InvalidIpLiteral}![4]u8 {
    var result = [_]u8{ 0, 0, 0, 0 };
    var part_index: usize = 0;
    var cursor: usize = 0;
    while (part_index < result.len) : (part_index += 1) {
        if (cursor >= text.len) return error.InvalidIpLiteral;
        const next_dot = std.mem.indexOfScalarPos(u8, text, cursor, '.') orelse text.len;
        const component = text[cursor..next_dot];
        if (component.len == 0) return error.InvalidIpLiteral;
        const value = std.fmt.parseUnsigned(u8, component, 10) catch return error.InvalidIpLiteral;
        result[part_index] = value;
        cursor = next_dot + 1;
        if (next_dot == text.len) break;
    }
    if (part_index != result.len - 1 or cursor <= text.len) {
        if (cursor != text.len + 1) return error.InvalidIpLiteral;
    }
    if (std.mem.count(u8, text, ".") != 3) return error.InvalidIpLiteral;
    return result;
}

fn nextDnsQueryId() u16 {
    const id = dns_state.next_query_id;
    dns_state.next_query_id +%= 1;
    if (dns_state.next_query_id == 0) dns_state.next_query_id = 1;
    return if (id == 0) 1 else id;
}

fn allocateTcpLocalPort() u16 {
    const port = next_tcp_local_port;
    next_tcp_local_port +%= 1;
    if (next_tcp_local_port < 49152) next_tcp_local_port = 49152;
    return port;
}

fn resolveHostIpv4(host: []const u8) ![4]u8 {
    return parseIpv4Literal(host) catch {
        if (dns_state.server_count == 0) return error.MissingDnsServer;
        const dns_server = dns_state.servers[0];
        const dns_mac = try resolveNextHopMac(dns_server);
        const query_id = nextDnsQueryId();
        const source_port = allocateTcpLocalPort();
        _ = try sendDnsQuery(dns_mac, route_state.local_ip, dns_server, source_port, query_id, host, dns.type_a);

        var attempts: usize = 0;
        while (attempts < post_poll_limit) : (attempts += 1) {
            var packet: DnsPacket = undefined;
            const received = pollDnsPacketStrictInto(&packet) catch |err| switch (err) {
                error.NotIpv4, error.NotUdp, error.NotDns => false,
                else => return err,
            };
            if (!received) continue;
            if (packet.id != query_id) continue;
            if (packet.source_port != dns.default_port or packet.destination_port != source_port) continue;
            if (!std.mem.eql(u8, packet.question_name[0..packet.question_name_len], host)) continue;

            var answer_index: usize = 0;
            while (answer_index < packet.answer_count) : (answer_index += 1) {
                const answer = packet.answers[answer_index];
                if (answer.rr_type == dns.type_a and answer.rr_class == dns.class_in and answer.data_len == 4) {
                    return .{ answer.data[0], answer.data[1], answer.data[2], answer.data[3] };
                }
            }
            return error.NoAnswer;
        }

        return error.Timeout;
    };
}

fn resolveNextHopMac(destination_ip: [4]u8) ![ethernet.mac_len]u8 {
    const route = try resolveNextHop(destination_ip);
    if (lookupArpCache(route.next_hop_ip)) |destination_mac| {
        return destination_mac;
    }

    _ = try sendArpRequest(route_state.local_ip, route.next_hop_ip);
    var attempts: usize = 0;
    while (attempts < post_poll_limit) : (attempts += 1) {
        if (lookupArpCache(route.next_hop_ip)) |destination_mac| return destination_mac;
        const packet_opt = try pollArpPacket();
        if (packet_opt) |packet| {
            _ = learnArpPacket(packet);
        }
    }
    return error.Timeout;
}

fn buildHttpPostRequest(
    allocator: std.mem.Allocator,
    parsed: ParsedPostUrl,
    payload: []const u8,
    headers: []const std.http.Header,
) ![]u8 {
    var request: std.ArrayList(u8) = .empty;
    errdefer request.deinit(allocator);
    const request_line = try std.fmt.allocPrint(allocator, "POST {s} HTTP/1.1\r\n", .{parsed.path});
    defer allocator.free(request_line);
    try request.appendSlice(allocator, request_line);
    const host_line = if (parsed.port == 80)
        try std.fmt.allocPrint(allocator, "Host: {s}\r\n", .{parsed.host})
    else
        try std.fmt.allocPrint(allocator, "Host: {s}:{d}\r\n", .{ parsed.host, parsed.port });
    defer allocator.free(host_line);
    try request.appendSlice(allocator, host_line);
    const content_length_line = try std.fmt.allocPrint(allocator, "Content-Length: {d}\r\n", .{payload.len});
    defer allocator.free(content_length_line);
    try request.appendSlice(allocator, content_length_line);
    try request.appendSlice(allocator, "Connection: close\r\n");
    for (headers) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, "host") or
            std.ascii.eqlIgnoreCase(header.name, "content-length") or
            std.ascii.eqlIgnoreCase(header.name, "connection"))
        {
            return error.UnsupportedHeader;
        }
        const header_line = try std.fmt.allocPrint(allocator, "{s}: {s}\r\n", .{ header.name, header.value });
        defer allocator.free(header_line);
        try request.appendSlice(allocator, header_line);
    }
    try request.appendSlice(allocator, "\r\n");
    try request.appendSlice(allocator, payload);
    return request.toOwnedSlice(allocator);
}

fn handlePostHandshakePacket(
    destination_mac: [ethernet.mac_len]u8,
    destination_ip: [4]u8,
    client: *tcp.Session,
) !bool {
    var packet: TcpPacket = undefined;
    const received = pollTcpPacketStrictInto(&packet) catch |err| switch (err) {
        error.NotIpv4, error.NotTcp => false,
        else => return err,
    };
    if (!received) return false;
    if (!tcpPacketMatchesFlow(packet, destination_ip, route_state.local_ip, client.remote_port, client.local_port)) {
        return false;
    }
    const ack = try client.acceptSynAck(tcpPacketView(&packet));
    try sendTcpOutbound(destination_mac, route_state.local_ip, destination_ip, client.*, ack);
    return true;
}

fn sendTcpOutbound(
    destination_mac: [ethernet.mac_len]u8,
    source_ip: [4]u8,
    destination_ip: [4]u8,
    session: tcp.Session,
    outbound: tcp.Outbound,
) !void {
    _ = try sendTcpPacket(
        destination_mac,
        source_ip,
        destination_ip,
        session.local_port,
        session.remote_port,
        outbound.sequence_number,
        outbound.acknowledgment_number,
        outbound.flags,
        outbound.window_size,
        outbound.payload,
    );
}

fn parseHttpResponseMeta(response: []const u8) !HttpResponseMeta {
    const header_end = std.mem.indexOf(u8, response, "\r\n\r\n") orelse return error.ResponseMalformed;
    const line_end = std.mem.indexOf(u8, response[0..header_end], "\r\n") orelse return error.ResponseMalformed;
    const status_line = response[0..line_end];
    const first_space = std.mem.indexOfScalar(u8, status_line, ' ') orelse return error.ResponseMalformed;
    if (first_space + 4 > status_line.len) return error.ResponseMalformed;
    const status_code = std.fmt.parseUnsigned(u16, status_line[first_space + 1 .. first_space + 4], 10) catch return error.ResponseMalformed;
    return .{
        .status_code = status_code,
        .body_offset = header_end + 4,
    };
}

fn tcpPacketMatchesFlow(
    packet: TcpPacket,
    source_ip: [4]u8,
    destination_ip: [4]u8,
    source_port: u16,
    destination_port: u16,
) bool {
    return std.mem.eql(u8, packet.ipv4_header.source_ip[0..], source_ip[0..]) and
        std.mem.eql(u8, packet.ipv4_header.destination_ip[0..], destination_ip[0..]) and
        packet.source_port == source_port and
        packet.destination_port == destination_port;
}

fn tcpPacketView(packet: *const TcpPacket) tcp.Packet {
    return .{
        .source_port = packet.source_port,
        .destination_port = packet.destination_port,
        .sequence_number = packet.sequence_number,
        .acknowledgment_number = packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = packet.flags,
        .window_size = packet.window_size,
        .checksum_value = packet.checksum_value,
        .urgent_pointer = packet.urgent_pointer,
        .payload = packet.payload[0..packet.payload_len],
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

pub fn sendArpRequest(sender_ip: [4]u8, target_ip: [4]u8) ArpError!u32 {
    if (!initDevice()) return error.NotAvailable;
    var frame: [arp.frame_len]u8 = undefined;
    const frame_len = try arp.encodeRequestFrame(frame[0..], macAddress(), sender_ip, target_ip);
    try sendFrame(frame[0..frame_len]);
    return @as(u32, @intCast(frame_len));
}

pub fn pollArpPacket() ArpError!?ArpPacket {
    const rx_len = try pollReceive();
    if (rx_len == 0) return null;

    var frame: [256]u8 = undefined;
    const copy_len = @min(frame.len, @as(usize, @intCast(rx_len)));
    var index: usize = 0;
    while (index < copy_len) : (index += 1) {
        frame[index] = rxByte(@as(u32, @intCast(index)));
    }

    return arp.decodeFrame(frame[0..copy_len]) catch |err| switch (err) {
        error.NotArp => null,
        else => return err,
    };
}

pub fn sendIpv4Frame(
    destination_mac: [ethernet.mac_len]u8,
    source_ip: [4]u8,
    destination_ip: [4]u8,
    protocol: u8,
    payload: []const u8,
) Ipv4Error!u32 {
    if (!initDevice()) return error.NotAvailable;

    var frame: [max_frame_len]u8 = undefined;
    const eth_header = ethernet.Header{
        .destination = destination_mac,
        .source = macAddress(),
        .ether_type = ethernet.ethertype_ipv4,
    };
    _ = try eth_header.encode(frame[0..ethernet.header_len]);

    const ip_header = ipv4.Header{
        .protocol = protocol,
        .source_ip = source_ip,
        .destination_ip = destination_ip,
    };
    const ip_header_len = try ip_header.encode(frame[ethernet.header_len .. ethernet.header_len + ipv4.header_len], payload.len);
    std.mem.copyForwards(u8, frame[ethernet.header_len + ip_header_len .. ethernet.header_len + ip_header_len + payload.len], payload);

    const frame_len = ethernet.header_len + ip_header_len + payload.len;
    try sendFrame(frame[0..frame_len]);
    return @as(u32, @intCast(frame_len));
}

pub fn pollIpv4Packet() Ipv4Error!?Ipv4Packet {
    return pollIpv4PacketStrict() catch |err| switch (err) {
        error.NotIpv4 => null,
        error.NotAvailable => return error.NotAvailable,
        error.NotInitialized => return error.NotInitialized,
        error.FrameTooLarge => return error.FrameTooLarge,
        error.HardwareFault => return error.HardwareFault,
        error.Timeout => return error.Timeout,
        error.BufferTooSmall => return error.BufferTooSmall,
        error.PacketTooShort => return error.PacketTooShort,
        error.InvalidVersion => return error.InvalidVersion,
        error.UnsupportedOptions => return error.UnsupportedOptions,
        error.InvalidTotalLength => return error.InvalidTotalLength,
        error.PayloadTooLarge => return error.PayloadTooLarge,
        error.HeaderChecksumMismatch => return error.HeaderChecksumMismatch,
        error.FrameTooShort => return error.FrameTooShort,
    };
}

pub fn pollIpv4PacketStrict() StrictIpv4PollError!?Ipv4Packet {
    const rx_len = try pollReceive();
    if (rx_len == 0) return null;

    var frame: [max_frame_len]u8 = undefined;
    const copy_len = @min(frame.len, @as(usize, @intCast(rx_len)));
    var index: usize = 0;
    while (index < copy_len) : (index += 1) {
        frame[index] = rxByte(@as(u32, @intCast(index)));
    }
    if (copy_len < ethernet.header_len) return error.FrameTooShort;

    const eth_header = try ethernet.Header.decode(frame[0..copy_len]);
    if (eth_header.ether_type != ethernet.ethertype_ipv4) return error.NotIpv4;

    const packet = try ipv4.decode(frame[ethernet.header_len..copy_len]);
    if (packet.payload.len > max_ipv4_payload_len) return error.PayloadTooLarge;

    var result = Ipv4Packet{
        .ethernet_destination = eth_header.destination,
        .ethernet_source = eth_header.source,
        .header = packet.header,
        .total_len = packet.total_len,
        .payload_len = packet.payload.len,
        .payload = [_]u8{0} ** max_ipv4_payload_len,
    };
    std.mem.copyForwards(u8, result.payload[0..packet.payload.len], packet.payload);
    return result;
}

pub fn sendUdpPacket(
    destination_mac: [ethernet.mac_len]u8,
    source_ip: [4]u8,
    destination_ip: [4]u8,
    source_port: u16,
    destination_port: u16,
    payload: []const u8,
) UdpError!u32 {
    if (!initDevice()) return error.NotAvailable;

    var segment: [max_ipv4_payload_len]u8 = undefined;
    const udp_header = udp.Header{
        .source_port = source_port,
        .destination_port = destination_port,
    };
    const segment_len = try udp_header.encode(segment[0..], payload, source_ip, destination_ip);
    return try sendIpv4Frame(destination_mac, source_ip, destination_ip, ipv4.protocol_udp, segment[0..segment_len]);
}

pub fn sendDhcpDiscover(
    transaction_id: u32,
    client_mac: [ethernet.mac_len]u8,
    parameter_request_list: []const u8,
) DhcpError!u32 {
    return sendDhcpDiscoverWithEnvelope(
        ethernet.broadcast_mac,
        .{ 0, 0, 0, 0 },
        .{ 255, 255, 255, 255 },
        transaction_id,
        client_mac,
        parameter_request_list,
    );
}

pub fn sendDhcpDiscoverWithEnvelope(
    destination_mac: [ethernet.mac_len]u8,
    source_ip: [4]u8,
    destination_ip: [4]u8,
    transaction_id: u32,
    client_mac: [ethernet.mac_len]u8,
    parameter_request_list: []const u8,
) DhcpError!u32 {
    if (!initDevice()) return error.NotAvailable;

    var segment: [max_ipv4_payload_len]u8 = undefined;
    const segment_len = try dhcp.encodeDiscover(segment[0..], client_mac, transaction_id, parameter_request_list);
    return try sendUdpPacket(
        destination_mac,
        source_ip,
        destination_ip,
        dhcp.client_port,
        dhcp.server_port,
        segment[0..segment_len],
    );
}

pub fn sendDnsQuery(
    destination_mac: [ethernet.mac_len]u8,
    source_ip: [4]u8,
    destination_ip: [4]u8,
    source_port: u16,
    id: u16,
    name: []const u8,
    qtype: u16,
) DnsError!u32 {
    if (!initDevice()) return error.NotAvailable;

    var segment: [max_ipv4_payload_len]u8 = undefined;
    const segment_len = try dns.encodeQuery(segment[0..], id, name, qtype);
    return try sendUdpPacket(destination_mac, source_ip, destination_ip, source_port, dns.default_port, segment[0..segment_len]);
}

pub fn sendTcpPacket(
    destination_mac: [ethernet.mac_len]u8,
    source_ip: [4]u8,
    destination_ip: [4]u8,
    source_port: u16,
    destination_port: u16,
    sequence_number: u32,
    acknowledgment_number: u32,
    flags: u16,
    window_size: u16,
    payload: []const u8,
) TcpError!u32 {
    if (!initDevice()) return error.NotAvailable;

    var segment: [max_ipv4_payload_len]u8 = undefined;
    const tcp_header = tcp.Header{
        .source_port = source_port,
        .destination_port = destination_port,
        .sequence_number = sequence_number,
        .acknowledgment_number = acknowledgment_number,
        .flags = flags,
        .window_size = window_size,
    };
    const segment_len = try tcp_header.encode(segment[0..], payload, source_ip, destination_ip);
    return try sendIpv4Frame(destination_mac, source_ip, destination_ip, ipv4.protocol_tcp, segment[0..segment_len]);
}

pub fn pollUdpPacket() UdpError!?UdpPacket {
    return pollUdpPacketStrict() catch |err| switch (err) {
        error.NotIpv4, error.NotUdp => null,
        error.NotAvailable => return error.NotAvailable,
        error.NotInitialized => return error.NotInitialized,
        error.FrameTooLarge => return error.FrameTooLarge,
        error.HardwareFault => return error.HardwareFault,
        error.Timeout => return error.Timeout,
        error.BufferTooSmall => return error.BufferTooSmall,
        error.PacketTooShort => return error.PacketTooShort,
        error.InvalidVersion => return error.InvalidVersion,
        error.UnsupportedOptions => return error.UnsupportedOptions,
        error.InvalidTotalLength => return error.InvalidTotalLength,
        error.PayloadTooLarge => return error.PayloadTooLarge,
        error.HeaderChecksumMismatch => return error.HeaderChecksumMismatch,
        error.FrameTooShort => return error.FrameTooShort,
        error.InvalidLength => return error.InvalidLength,
        error.ChecksumMismatch => return error.ChecksumMismatch,
    };
}

pub fn pollUdpPacketStrictInto(result: *UdpPacket) StrictUdpPollError!bool {
    var packet_opt = try pollIpv4PacketStrict();
    if (packet_opt) |*packet| {
        if (packet.header.protocol != ipv4.protocol_udp) return error.NotUdp;

        const decoded = try udp.decode(packet.payload[0..packet.payload_len], packet.header.source_ip, packet.header.destination_ip);
        if (decoded.payload.len > max_udp_payload_len) return error.PayloadTooLarge;

        result.* = .{
            .ethernet_destination = packet.ethernet_destination,
            .ethernet_source = packet.ethernet_source,
            .ipv4_header = packet.header,
            .source_port = decoded.source_port,
            .destination_port = decoded.destination_port,
            .checksum_value = decoded.checksum_value,
            .payload_len = decoded.payload.len,
            .payload = [_]u8{0} ** max_udp_payload_len,
        };
        std.mem.copyForwards(u8, result.payload[0..decoded.payload.len], decoded.payload);
        return true;
    }
    return false;
}

pub fn pollTcpPacket() TcpError!?TcpPacket {
    return pollTcpPacketStrict() catch |err| switch (err) {
        error.NotIpv4, error.NotTcp => null,
        error.NotAvailable => return error.NotAvailable,
        error.NotInitialized => return error.NotInitialized,
        error.FrameTooLarge => return error.FrameTooLarge,
        error.HardwareFault => return error.HardwareFault,
        error.Timeout => return error.Timeout,
        error.BufferTooSmall => return error.BufferTooSmall,
        error.PacketTooShort => return error.PacketTooShort,
        error.InvalidVersion => return error.InvalidVersion,
        error.UnsupportedOptions => return error.UnsupportedOptions,
        error.InvalidTotalLength => return error.InvalidTotalLength,
        error.PayloadTooLarge => return error.PayloadTooLarge,
        error.WindowExceeded => return error.WindowExceeded,
        error.HeaderChecksumMismatch => return error.HeaderChecksumMismatch,
        error.FrameTooShort => return error.FrameTooShort,
        error.InvalidDataOffset => return error.InvalidDataOffset,
        error.ChecksumMismatch => return error.ChecksumMismatch,
        error.EmptyPayload => return error.EmptyPayload,
        error.InvalidState => return error.InvalidState,
        error.UnexpectedFlags => return error.UnexpectedFlags,
        error.PortMismatch => return error.PortMismatch,
        error.SequenceMismatch => return error.SequenceMismatch,
        error.AcknowledgmentMismatch => return error.AcknowledgmentMismatch,
    };
}

pub fn pollDnsPacket() DnsError!?DnsPacket {
    return pollDnsPacketStrict() catch |err| switch (err) {
        error.NotIpv4, error.NotUdp, error.NotDns => null,
        error.NotAvailable => return error.NotAvailable,
        error.NotInitialized => return error.NotInitialized,
        error.FrameTooLarge => return error.FrameTooLarge,
        error.HardwareFault => return error.HardwareFault,
        error.Timeout => return error.Timeout,
        error.BufferTooSmall => return error.BufferTooSmall,
        error.PacketTooShort => return error.PacketTooShort,
        error.InvalidVersion => return error.InvalidVersion,
        error.UnsupportedOptions => return error.UnsupportedOptions,
        error.InvalidTotalLength => return error.InvalidTotalLength,
        error.PayloadTooLarge => return error.PayloadTooLarge,
        error.HeaderChecksumMismatch => return error.HeaderChecksumMismatch,
        error.FrameTooShort => return error.FrameTooShort,
        error.InvalidLength => return error.InvalidLength,
        error.ChecksumMismatch => return error.ChecksumMismatch,
        error.InvalidLabelLength => return error.InvalidLabelLength,
        error.InvalidPointer => return error.InvalidPointer,
        error.UnsupportedLabelType => return error.UnsupportedLabelType,
        error.NameTooLong => return error.NameTooLong,
        error.CompressionLoop => return error.CompressionLoop,
        error.UnsupportedQuestionCount => return error.UnsupportedQuestionCount,
        error.ResourceDataTooLarge => return error.ResourceDataTooLarge,
    };
}

pub fn pollDhcpPacket() DhcpError!?DhcpPacket {
    return pollDhcpPacketStrict() catch |err| switch (err) {
        error.NotIpv4, error.NotUdp, error.NotDhcp => null,
        error.NotAvailable => return error.NotAvailable,
        error.NotInitialized => return error.NotInitialized,
        error.FrameTooLarge => return error.FrameTooLarge,
        error.HardwareFault => return error.HardwareFault,
        error.Timeout => return error.Timeout,
        error.BufferTooSmall => return error.BufferTooSmall,
        error.PacketTooShort => return error.PacketTooShort,
        error.InvalidVersion => return error.InvalidVersion,
        error.UnsupportedOptions => return error.UnsupportedOptions,
        error.InvalidTotalLength => return error.InvalidTotalLength,
        error.PayloadTooLarge => return error.PayloadTooLarge,
        error.HeaderChecksumMismatch => return error.HeaderChecksumMismatch,
        error.FrameTooShort => return error.FrameTooShort,
        error.InvalidLength => return error.InvalidLength,
        error.ChecksumMismatch => return error.ChecksumMismatch,
        error.InvalidOperation => return error.InvalidOperation,
        error.InvalidHardwareType => return error.InvalidHardwareType,
        error.InvalidHardwareLength => return error.InvalidHardwareLength,
        error.InvalidMagicCookie => return error.InvalidMagicCookie,
        error.OptionTruncated => return error.OptionTruncated,
        error.FieldLengthMismatch => return error.FieldLengthMismatch,
    };
}

pub fn pollDnsPacketStrictInto(result: *DnsPacket) StrictDnsPollError!bool {
    var packet: UdpPacket = undefined;
    if (!(try pollUdpPacketStrictInto(&packet))) return false;
    if (!(packet.source_port == dns.default_port or packet.destination_port == dns.default_port)) return error.NotDns;

    const decoded = try dns.decode(packet.payload[0..packet.payload_len]);

    result.ethernet_destination = packet.ethernet_destination;
    result.ethernet_source = packet.ethernet_source;
    result.ipv4_header = packet.ipv4_header;
    result.source_port = packet.source_port;
    result.destination_port = packet.destination_port;
    result.udp_checksum_value = packet.checksum_value;
    result.id = decoded.id;
    result.flags = decoded.flags;
    result.question_count = decoded.question_count;
    result.answer_count_total = decoded.answer_count_total;
    result.authority_count = decoded.authority_count;
    result.additional_count = decoded.additional_count;
    result.question_name_len = decoded.question_name_len;
    result.question_name = [_]u8{0} ** max_dns_name_len;
    if (decoded.question_name_len > 0) {
        std.mem.copyForwards(u8, result.question_name[0..decoded.question_name_len], decoded.question_name[0..decoded.question_name_len]);
    }
    result.question_type = decoded.question_type;
    result.question_class = decoded.question_class;
    result.answer_count = decoded.answer_count;

    var answer_index: usize = 0;
    while (answer_index < max_dns_answers) : (answer_index += 1) {
        if (answer_index < decoded.answer_count) {
            result.answers[answer_index] = decoded.answers[answer_index];
        } else {
            result.answers[answer_index] = std.mem.zeroes(dns.Answer);
        }
    }
    return true;
}

pub fn pollDhcpPacketStrictInto(result: *DhcpPacket) StrictDhcpPollError!bool {
    const packet_opt = try pollUdpPacketStrict();
    if (packet_opt) |packet| {
        if (!((packet.source_port == dhcp.client_port and packet.destination_port == dhcp.server_port) or
            (packet.source_port == dhcp.server_port and packet.destination_port == dhcp.client_port)))
        {
            return error.NotDhcp;
        }

        const decoded = try dhcp.decode(packet.payload[0..packet.payload_len]);
        if (decoded.parameter_request_list.len > max_dhcp_parameter_request_list_len) return error.PayloadTooLarge;
        if (decoded.client_identifier.len > max_dhcp_client_identifier_len) return error.PayloadTooLarge;
        if (decoded.hostname.len > max_dhcp_hostname_len) return error.PayloadTooLarge;
        if (decoded.options.len > max_udp_payload_len) return error.PayloadTooLarge;

        result.* = .{
            .ethernet_destination = packet.ethernet_destination,
            .ethernet_source = packet.ethernet_source,
            .ipv4_header = packet.ipv4_header,
            .source_port = packet.source_port,
            .destination_port = packet.destination_port,
            .udp_checksum_value = packet.checksum_value,
            .op = decoded.op,
            .transaction_id = decoded.transaction_id,
            .flags = decoded.flags,
            .client_ip = decoded.client_ip,
            .your_ip = decoded.your_ip,
            .server_ip = decoded.server_ip,
            .gateway_ip = decoded.gateway_ip,
            .client_mac = decoded.client_mac,
            .message_type = decoded.message_type,
            .subnet_mask_valid = decoded.subnet_mask != null,
            .subnet_mask = decoded.subnet_mask orelse [_]u8{ 0, 0, 0, 0 },
            .router_valid = decoded.router != null,
            .router = decoded.router orelse [_]u8{ 0, 0, 0, 0 },
            .requested_ip_valid = decoded.requested_ip != null,
            .requested_ip = decoded.requested_ip orelse [_]u8{ 0, 0, 0, 0 },
            .server_identifier_valid = decoded.server_identifier != null,
            .server_identifier = decoded.server_identifier orelse [_]u8{ 0, 0, 0, 0 },
            .lease_time_valid = decoded.lease_time_seconds != null,
            .lease_time_seconds = decoded.lease_time_seconds orelse 0,
            .max_message_size_valid = decoded.max_message_size != null,
            .max_message_size = decoded.max_message_size orelse 0,
            .dns_server_count = decoded.dns_server_count,
            .dns_servers = [_][4]u8{
                [_]u8{ 0, 0, 0, 0 },
                [_]u8{ 0, 0, 0, 0 },
            },
            .parameter_request_list_len = decoded.parameter_request_list.len,
            .parameter_request_list = [_]u8{0} ** max_dhcp_parameter_request_list_len,
            .client_identifier_len = decoded.client_identifier.len,
            .client_identifier = [_]u8{0} ** max_dhcp_client_identifier_len,
            .hostname_len = decoded.hostname.len,
            .hostname = [_]u8{0} ** max_dhcp_hostname_len,
            .options_len = decoded.options.len,
            .options = [_]u8{0} ** max_udp_payload_len,
        };
        if (decoded.dns_server_count > 0) {
            std.mem.copyForwards([4]u8, result.dns_servers[0..decoded.dns_server_count], decoded.dns_servers[0..decoded.dns_server_count]);
        }
        std.mem.copyForwards(u8, result.parameter_request_list[0..decoded.parameter_request_list.len], decoded.parameter_request_list);
        std.mem.copyForwards(u8, result.client_identifier[0..decoded.client_identifier.len], decoded.client_identifier);
        std.mem.copyForwards(u8, result.hostname[0..decoded.hostname.len], decoded.hostname);
        std.mem.copyForwards(u8, result.options[0..decoded.options.len], decoded.options);
        return true;
    }
    return false;
}

pub fn pollTcpPacketStrictInto(result: *TcpPacket) StrictTcpPollError!bool {
    var packet_opt = try pollIpv4PacketStrict();
    if (packet_opt) |*packet| {
        if (packet.header.protocol != ipv4.protocol_tcp) return error.NotTcp;

        const decoded = try tcp.decode(packet.payload[0..packet.payload_len], packet.header.source_ip, packet.header.destination_ip);
        if (decoded.payload.len > max_tcp_payload_len) return error.PayloadTooLarge;

        result.* = .{
            .ethernet_destination = packet.ethernet_destination,
            .ethernet_source = packet.ethernet_source,
            .ipv4_header = packet.header,
            .source_port = decoded.source_port,
            .destination_port = decoded.destination_port,
            .sequence_number = decoded.sequence_number,
            .acknowledgment_number = decoded.acknowledgment_number,
            .flags = decoded.flags,
            .window_size = decoded.window_size,
            .checksum_value = decoded.checksum_value,
            .urgent_pointer = decoded.urgent_pointer,
            .payload_len = decoded.payload.len,
            .payload = [_]u8{0} ** max_tcp_payload_len,
        };
        std.mem.copyForwards(u8, result.payload[0..decoded.payload.len], decoded.payload);
        return true;
    }
    return false;
}

pub fn pollTcpPacketStrict() StrictTcpPollError!?TcpPacket {
    var result: TcpPacket = undefined;
    if (try pollTcpPacketStrictInto(&result)) {
        return result;
    }
    return null;
}

pub fn pollDnsPacketStrict() StrictDnsPollError!?DnsPacket {
    var result: DnsPacket = undefined;
    if (try pollDnsPacketStrictInto(&result)) {
        return result;
    }
    return null;
}

pub fn pollDhcpPacketStrict() StrictDhcpPollError!?DhcpPacket {
    var result: DhcpPacket = undefined;
    if (try pollDhcpPacketStrictInto(&result)) {
        return result;
    }
    return null;
}

pub fn pollUdpPacketStrict() StrictUdpPollError!?UdpPacket {
    var result: UdpPacket = undefined;
    if (try pollUdpPacketStrictInto(&result)) {
        return result;
    }
    return null;
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

test "baremetal net pal sends and parses arp request through rtl8139 mock device" {
    rtl8139.testEnableMockDevice();
    defer rtl8139.testDisableMockDevice();

    try std.testing.expect(initDevice());
    const sender_ip = [4]u8{ 192, 168, 56, 10 };
    const target_ip = [4]u8{ 192, 168, 56, 1 };

    try std.testing.expectEqual(@as(u32, arp.frame_len), try sendArpRequest(sender_ip, target_ip));
    const packet = (try pollArpPacket()).?;

    try std.testing.expectEqual(arp.operation_request, packet.operation);
    try std.testing.expectEqualSlices(u8, ethernet.broadcast_mac[0..], packet.ethernet_destination[0..]);
    try std.testing.expectEqualSlices(u8, macAddress()[0..], packet.ethernet_source[0..]);
    try std.testing.expectEqualSlices(u8, macAddress()[0..], packet.sender_mac[0..]);
    try std.testing.expectEqualSlices(u8, sender_ip[0..], packet.sender_ip[0..]);
    try std.testing.expectEqualSlices(u8, target_ip[0..], packet.target_ip[0..]);
}

test "baremetal net pal sends and parses ipv4 frame through rtl8139 mock device" {
    rtl8139.testEnableMockDevice();
    defer rtl8139.testDisableMockDevice();

    try std.testing.expect(initDevice());
    const source_ip = [4]u8{ 192, 168, 56, 10 };
    const destination_ip = [4]u8{ 192, 168, 56, 1 };
    const payload = "PING";

    try std.testing.expectEqual(
        @as(u32, ethernet.header_len + ipv4.header_len + payload.len),
        try sendIpv4Frame(macAddress(), source_ip, destination_ip, ipv4.protocol_udp, payload),
    );

    const packet = (try pollIpv4Packet()).?;
    try std.testing.expectEqual(ipv4.protocol_udp, packet.header.protocol);
    try std.testing.expectEqualSlices(u8, macAddress()[0..], packet.ethernet_destination[0..]);
    try std.testing.expectEqualSlices(u8, macAddress()[0..], packet.ethernet_source[0..]);
    try std.testing.expectEqualSlices(u8, source_ip[0..], packet.header.source_ip[0..]);
    try std.testing.expectEqualSlices(u8, destination_ip[0..], packet.header.destination_ip[0..]);
    try std.testing.expectEqualSlices(u8, payload, packet.payload[0..packet.payload_len]);
}

test "baremetal net pal strict ipv4 poll reports non-ipv4 frame" {
    rtl8139.testEnableMockDevice();
    defer rtl8139.testDisableMockDevice();

    try std.testing.expect(initDevice());
    const sender_ip = [4]u8{ 192, 168, 56, 10 };
    const target_ip = [4]u8{ 192, 168, 56, 1 };
    _ = try sendArpRequest(sender_ip, target_ip);

    try std.testing.expectError(error.NotIpv4, pollIpv4PacketStrict());
}

test "baremetal net pal sends and parses udp packet through rtl8139 mock device" {
    rtl8139.testEnableMockDevice();
    defer rtl8139.testDisableMockDevice();

    try std.testing.expect(initDevice());
    const source_ip = [4]u8{ 192, 168, 56, 10 };
    const destination_ip = [4]u8{ 192, 168, 56, 1 };
    const payload = "OPENCLAW-UDP";

    _ = try sendUdpPacket(macAddress(), source_ip, destination_ip, 4321, 9001, payload);

    const packet = (try pollUdpPacket()).?;
    try std.testing.expectEqual(@as(u16, 4321), packet.source_port);
    try std.testing.expectEqual(@as(u16, 9001), packet.destination_port);
    try std.testing.expectEqual(ipv4.protocol_udp, packet.ipv4_header.protocol);
    try std.testing.expectEqualSlices(u8, source_ip[0..], packet.ipv4_header.source_ip[0..]);
    try std.testing.expectEqualSlices(u8, destination_ip[0..], packet.ipv4_header.destination_ip[0..]);
    try std.testing.expectEqualSlices(u8, payload, packet.payload[0..packet.payload_len]);
    try std.testing.expect(packet.checksum_value != 0);
}

test "baremetal net pal strict udp poll reports non-udp ipv4 frame" {
    rtl8139.testEnableMockDevice();
    defer rtl8139.testDisableMockDevice();

    try std.testing.expect(initDevice());
    const source_ip = [4]u8{ 192, 168, 56, 10 };
    const destination_ip = [4]u8{ 192, 168, 56, 1 };
    const payload = "PING";

    _ = try sendIpv4Frame(macAddress(), source_ip, destination_ip, 1, payload);
    try std.testing.expectError(error.NotUdp, pollUdpPacketStrict());
}

test "baremetal net pal sends and parses tcp packet through rtl8139 mock device" {
    rtl8139.testEnableMockDevice();
    defer rtl8139.testDisableMockDevice();

    try std.testing.expect(initDevice());
    const source_ip = [4]u8{ 192, 168, 56, 10 };
    const destination_ip = [4]u8{ 192, 168, 56, 1 };
    const payload = "OPENCLAW-TCP";

    _ = try sendTcpPacket(macAddress(), source_ip, destination_ip, 4321, 443, 0x0102_0304, 0xA0B0_C0D0, tcp.flag_ack | tcp.flag_psh, 8192, payload);

    const packet = (try pollTcpPacket()).?;
    try std.testing.expectEqual(@as(u16, 4321), packet.source_port);
    try std.testing.expectEqual(@as(u16, 443), packet.destination_port);
    try std.testing.expectEqual(@as(u32, 0x0102_0304), packet.sequence_number);
    try std.testing.expectEqual(@as(u32, 0xA0B0_C0D0), packet.acknowledgment_number);
    try std.testing.expectEqual(ipv4.protocol_tcp, packet.ipv4_header.protocol);
    try std.testing.expectEqual(tcp.flag_ack | tcp.flag_psh, packet.flags);
    try std.testing.expectEqual(@as(u16, 8192), packet.window_size);
    try std.testing.expectEqualSlices(u8, source_ip[0..], packet.ipv4_header.source_ip[0..]);
    try std.testing.expectEqualSlices(u8, destination_ip[0..], packet.ipv4_header.destination_ip[0..]);
    try std.testing.expectEqualSlices(u8, payload, packet.payload[0..packet.payload_len]);
}

test "baremetal net pal completes tcp handshake and payload exchange through rtl8139 mock device" {
    rtl8139.testEnableMockDevice();
    defer rtl8139.testDisableMockDevice();

    try std.testing.expect(initDevice());
    const client_ip = [4]u8{ 192, 168, 56, 10 };
    const server_ip = [4]u8{ 192, 168, 56, 1 };
    const destination_mac = macAddress();
    const payload = "OPENCLAW-TCP-HANDSHAKE";

    var client = tcp.Session.initClient(4321, 443, 0x0102_0304, 4096);
    var server = tcp.Session.initServer(443, 4321, 0xA0B0_C0D0, 8192);

    const syn = try client.buildSyn();
    _ = try sendTcpPacket(destination_mac, client_ip, server_ip, client.local_port, client.remote_port, syn.sequence_number, syn.acknowledgment_number, syn.flags, syn.window_size, syn.payload);
    const syn_packet = (try pollTcpPacketStrict()).?;
    const syn_ack = try server.acceptSyn(.{
        .source_port = syn_packet.source_port,
        .destination_port = syn_packet.destination_port,
        .sequence_number = syn_packet.sequence_number,
        .acknowledgment_number = syn_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = syn_packet.flags,
        .window_size = syn_packet.window_size,
        .checksum_value = syn_packet.checksum_value,
        .urgent_pointer = syn_packet.urgent_pointer,
        .payload = syn_packet.payload[0..syn_packet.payload_len],
    });

    _ = try sendTcpPacket(destination_mac, server_ip, client_ip, server.local_port, server.remote_port, syn_ack.sequence_number, syn_ack.acknowledgment_number, syn_ack.flags, syn_ack.window_size, syn_ack.payload);
    const syn_ack_packet = (try pollTcpPacketStrict()).?;
    const ack = try client.acceptSynAck(.{
        .source_port = syn_ack_packet.source_port,
        .destination_port = syn_ack_packet.destination_port,
        .sequence_number = syn_ack_packet.sequence_number,
        .acknowledgment_number = syn_ack_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = syn_ack_packet.flags,
        .window_size = syn_ack_packet.window_size,
        .checksum_value = syn_ack_packet.checksum_value,
        .urgent_pointer = syn_ack_packet.urgent_pointer,
        .payload = syn_ack_packet.payload[0..syn_ack_packet.payload_len],
    });

    _ = try sendTcpPacket(destination_mac, client_ip, server_ip, client.local_port, client.remote_port, ack.sequence_number, ack.acknowledgment_number, ack.flags, ack.window_size, ack.payload);
    const ack_packet = (try pollTcpPacketStrict()).?;
    try server.acceptAck(.{
        .source_port = ack_packet.source_port,
        .destination_port = ack_packet.destination_port,
        .sequence_number = ack_packet.sequence_number,
        .acknowledgment_number = ack_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = ack_packet.flags,
        .window_size = ack_packet.window_size,
        .checksum_value = ack_packet.checksum_value,
        .urgent_pointer = ack_packet.urgent_pointer,
        .payload = ack_packet.payload[0..ack_packet.payload_len],
    });

    const data = try client.buildPayload(payload);
    _ = try sendTcpPacket(destination_mac, client_ip, server_ip, client.local_port, client.remote_port, data.sequence_number, data.acknowledgment_number, data.flags, data.window_size, data.payload);
    const data_packet = (try pollTcpPacketStrict()).?;
    try server.acceptPayload(.{
        .source_port = data_packet.source_port,
        .destination_port = data_packet.destination_port,
        .sequence_number = data_packet.sequence_number,
        .acknowledgment_number = data_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = data_packet.flags,
        .window_size = data_packet.window_size,
        .checksum_value = data_packet.checksum_value,
        .urgent_pointer = data_packet.urgent_pointer,
        .payload = data_packet.payload[0..data_packet.payload_len],
    });

    try std.testing.expectEqual(tcp.State.established, client.state);
    try std.testing.expectEqual(tcp.State.established, server.state);
    try std.testing.expectEqual(@as(u32, 0x0102_0305 + payload.len), client.send_next);
    try std.testing.expectEqual(@as(u32, 0x0102_0305 + payload.len), server.recv_next);
}

test "baremetal net pal surfaces tcp handshake acknowledgment mismatch through rtl8139 mock device" {
    rtl8139.testEnableMockDevice();
    defer rtl8139.testDisableMockDevice();

    try std.testing.expect(initDevice());
    const client_ip = [4]u8{ 192, 168, 56, 10 };
    const server_ip = [4]u8{ 192, 168, 56, 1 };
    const destination_mac = macAddress();

    var client = tcp.Session.initClient(4321, 443, 0x0102_0304, 4096);
    _ = try client.buildSyn();

    _ = try sendTcpPacket(destination_mac, server_ip, client_ip, 443, 4321, 0xA0B0_C0D0, client.send_next +% 1, tcp.flag_syn | tcp.flag_ack, 8192, "");
    const syn_ack_packet = (try pollTcpPacketStrict()).?;
    try std.testing.expectError(error.AcknowledgmentMismatch, client.acceptSynAck(.{
        .source_port = syn_ack_packet.source_port,
        .destination_port = syn_ack_packet.destination_port,
        .sequence_number = syn_ack_packet.sequence_number,
        .acknowledgment_number = syn_ack_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = syn_ack_packet.flags,
        .window_size = syn_ack_packet.window_size,
        .checksum_value = syn_ack_packet.checksum_value,
        .urgent_pointer = syn_ack_packet.urgent_pointer,
        .payload = syn_ack_packet.payload[0..syn_ack_packet.payload_len],
    }));
}

test "baremetal net pal retransmits dropped syn and establishes tcp session through rtl8139 mock device" {
    rtl8139.testEnableMockDevice();
    defer rtl8139.testDisableMockDevice();

    try std.testing.expect(initDevice());
    const client_ip = [4]u8{ 192, 168, 56, 10 };
    const server_ip = [4]u8{ 192, 168, 56, 1 };
    const destination_mac = macAddress();
    const payload = "OPENCLAW-TCP-RETRY";

    var client = tcp.Session.initClient(4321, 443, 0x0102_0304, 4096);
    var server = tcp.Session.initServer(443, 4321, 0xA0B0_C0D0, 8192);

    const syn = try client.buildSynWithTimeout(0, 4);
    _ = try sendTcpPacket(destination_mac, client_ip, server_ip, client.local_port, client.remote_port, syn.sequence_number, syn.acknowledgment_number, syn.flags, syn.window_size, syn.payload);
    const first_syn_packet = (try pollTcpPacketStrict()).?;
    try std.testing.expectEqual(tcp.flag_syn, first_syn_packet.flags);
    try std.testing.expectEqual(syn.sequence_number, first_syn_packet.sequence_number);
    try std.testing.expectEqual(@as(?tcp.Outbound, null), client.pollRetransmit(3));

    const retry_syn = client.pollRetransmit(4).?;
    try std.testing.expectEqual(syn.sequence_number, retry_syn.sequence_number);
    try std.testing.expectEqual(syn.flags, retry_syn.flags);
    try std.testing.expectEqual(@as(u32, 1), client.retransmit.attempts);
    _ = try sendTcpPacket(destination_mac, client_ip, server_ip, client.local_port, client.remote_port, retry_syn.sequence_number, retry_syn.acknowledgment_number, retry_syn.flags, retry_syn.window_size, retry_syn.payload);
    const retry_syn_packet = (try pollTcpPacketStrict()).?;
    const syn_ack = try server.acceptSyn(.{
        .source_port = retry_syn_packet.source_port,
        .destination_port = retry_syn_packet.destination_port,
        .sequence_number = retry_syn_packet.sequence_number,
        .acknowledgment_number = retry_syn_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = retry_syn_packet.flags,
        .window_size = retry_syn_packet.window_size,
        .checksum_value = retry_syn_packet.checksum_value,
        .urgent_pointer = retry_syn_packet.urgent_pointer,
        .payload = retry_syn_packet.payload[0..retry_syn_packet.payload_len],
    });

    _ = try sendTcpPacket(destination_mac, server_ip, client_ip, server.local_port, server.remote_port, syn_ack.sequence_number, syn_ack.acknowledgment_number, syn_ack.flags, syn_ack.window_size, syn_ack.payload);
    const syn_ack_packet = (try pollTcpPacketStrict()).?;
    const ack = try client.acceptSynAck(.{
        .source_port = syn_ack_packet.source_port,
        .destination_port = syn_ack_packet.destination_port,
        .sequence_number = syn_ack_packet.sequence_number,
        .acknowledgment_number = syn_ack_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = syn_ack_packet.flags,
        .window_size = syn_ack_packet.window_size,
        .checksum_value = syn_ack_packet.checksum_value,
        .urgent_pointer = syn_ack_packet.urgent_pointer,
        .payload = syn_ack_packet.payload[0..syn_ack_packet.payload_len],
    });

    try std.testing.expect(!client.retransmit.armed());
    _ = try sendTcpPacket(destination_mac, client_ip, server_ip, client.local_port, client.remote_port, ack.sequence_number, ack.acknowledgment_number, ack.flags, ack.window_size, ack.payload);
    const ack_packet = (try pollTcpPacketStrict()).?;
    try server.acceptAck(.{
        .source_port = ack_packet.source_port,
        .destination_port = ack_packet.destination_port,
        .sequence_number = ack_packet.sequence_number,
        .acknowledgment_number = ack_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = ack_packet.flags,
        .window_size = ack_packet.window_size,
        .checksum_value = ack_packet.checksum_value,
        .urgent_pointer = ack_packet.urgent_pointer,
        .payload = ack_packet.payload[0..ack_packet.payload_len],
    });

    const data = try client.buildPayload(payload);
    _ = try sendTcpPacket(destination_mac, client_ip, server_ip, client.local_port, client.remote_port, data.sequence_number, data.acknowledgment_number, data.flags, data.window_size, data.payload);
    const data_packet = (try pollTcpPacketStrict()).?;
    try server.acceptPayload(.{
        .source_port = data_packet.source_port,
        .destination_port = data_packet.destination_port,
        .sequence_number = data_packet.sequence_number,
        .acknowledgment_number = data_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = data_packet.flags,
        .window_size = data_packet.window_size,
        .checksum_value = data_packet.checksum_value,
        .urgent_pointer = data_packet.urgent_pointer,
        .payload = data_packet.payload[0..data_packet.payload_len],
    });

    try std.testing.expectEqual(tcp.State.established, client.state);
    try std.testing.expectEqual(tcp.State.established, server.state);
    try std.testing.expectEqual(@as(u32, 0x0102_0305 + payload.len), client.send_next);
    try std.testing.expectEqual(@as(u32, 0x0102_0305 + payload.len), server.recv_next);
}

test "baremetal net pal retransmits dropped payload and clears timer on ack through rtl8139 mock device" {
    rtl8139.testEnableMockDevice();
    defer rtl8139.testDisableMockDevice();

    try std.testing.expect(initDevice());
    const client_ip = [4]u8{ 192, 168, 56, 10 };
    const server_ip = [4]u8{ 192, 168, 56, 1 };
    const destination_mac = macAddress();
    const payload = "OPENCLAW-TCP-PAYLOAD-RETRY";

    var client = tcp.Session.initClient(4321, 443, 0x0102_0304, 4096);
    var server = tcp.Session.initServer(443, 4321, 0xA0B0_C0D0, 8192);

    const syn = try client.buildSyn();
    _ = try sendTcpPacket(destination_mac, client_ip, server_ip, client.local_port, client.remote_port, syn.sequence_number, syn.acknowledgment_number, syn.flags, syn.window_size, syn.payload);
    const syn_packet = (try pollTcpPacketStrict()).?;
    const syn_ack = try server.acceptSyn(.{
        .source_port = syn_packet.source_port,
        .destination_port = syn_packet.destination_port,
        .sequence_number = syn_packet.sequence_number,
        .acknowledgment_number = syn_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = syn_packet.flags,
        .window_size = syn_packet.window_size,
        .checksum_value = syn_packet.checksum_value,
        .urgent_pointer = syn_packet.urgent_pointer,
        .payload = syn_packet.payload[0..syn_packet.payload_len],
    });

    _ = try sendTcpPacket(destination_mac, server_ip, client_ip, server.local_port, server.remote_port, syn_ack.sequence_number, syn_ack.acknowledgment_number, syn_ack.flags, syn_ack.window_size, syn_ack.payload);
    const syn_ack_packet = (try pollTcpPacketStrict()).?;
    const ack = try client.acceptSynAck(.{
        .source_port = syn_ack_packet.source_port,
        .destination_port = syn_ack_packet.destination_port,
        .sequence_number = syn_ack_packet.sequence_number,
        .acknowledgment_number = syn_ack_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = syn_ack_packet.flags,
        .window_size = syn_ack_packet.window_size,
        .checksum_value = syn_ack_packet.checksum_value,
        .urgent_pointer = syn_ack_packet.urgent_pointer,
        .payload = syn_ack_packet.payload[0..syn_ack_packet.payload_len],
    });

    _ = try sendTcpPacket(destination_mac, client_ip, server_ip, client.local_port, client.remote_port, ack.sequence_number, ack.acknowledgment_number, ack.flags, ack.window_size, ack.payload);
    const ack_packet = (try pollTcpPacketStrict()).?;
    try server.acceptAck(.{
        .source_port = ack_packet.source_port,
        .destination_port = ack_packet.destination_port,
        .sequence_number = ack_packet.sequence_number,
        .acknowledgment_number = ack_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = ack_packet.flags,
        .window_size = ack_packet.window_size,
        .checksum_value = ack_packet.checksum_value,
        .urgent_pointer = ack_packet.urgent_pointer,
        .payload = ack_packet.payload[0..ack_packet.payload_len],
    });

    const data = try client.buildPayloadWithTimeout(payload, 10, 4);
    _ = try sendTcpPacket(destination_mac, client_ip, server_ip, client.local_port, client.remote_port, data.sequence_number, data.acknowledgment_number, data.flags, data.window_size, data.payload);
    const first_data_packet = (try pollTcpPacketStrict()).?;
    try std.testing.expectEqual(data.sequence_number, first_data_packet.sequence_number);
    try std.testing.expectEqualStrings(payload, first_data_packet.payload[0..first_data_packet.payload_len]);
    try std.testing.expectEqual(@as(?tcp.Outbound, null), client.pollRetransmit(13));

    const retry_data = client.pollRetransmit(14).?;
    try std.testing.expectEqual(data.sequence_number, retry_data.sequence_number);
    try std.testing.expectEqual(data.acknowledgment_number, retry_data.acknowledgment_number);
    try std.testing.expectEqual(data.flags, retry_data.flags);
    try std.testing.expectEqual(data.window_size, retry_data.window_size);
    try std.testing.expectEqualStrings(payload, retry_data.payload);
    try std.testing.expectEqual(@as(u32, 1), client.retransmit.attempts);
    _ = try sendTcpPacket(destination_mac, client_ip, server_ip, client.local_port, client.remote_port, retry_data.sequence_number, retry_data.acknowledgment_number, retry_data.flags, retry_data.window_size, retry_data.payload);
    const retry_data_packet = (try pollTcpPacketStrict()).?;
    try server.acceptPayload(.{
        .source_port = retry_data_packet.source_port,
        .destination_port = retry_data_packet.destination_port,
        .sequence_number = retry_data_packet.sequence_number,
        .acknowledgment_number = retry_data_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = retry_data_packet.flags,
        .window_size = retry_data_packet.window_size,
        .checksum_value = retry_data_packet.checksum_value,
        .urgent_pointer = retry_data_packet.urgent_pointer,
        .payload = retry_data_packet.payload[0..retry_data_packet.payload_len],
    });

    const payload_ack = try server.buildAck();
    _ = try sendTcpPacket(destination_mac, server_ip, client_ip, server.local_port, server.remote_port, payload_ack.sequence_number, payload_ack.acknowledgment_number, payload_ack.flags, payload_ack.window_size, payload_ack.payload);
    const payload_ack_packet = (try pollTcpPacketStrict()).?;
    try client.acceptAck(.{
        .source_port = payload_ack_packet.source_port,
        .destination_port = payload_ack_packet.destination_port,
        .sequence_number = payload_ack_packet.sequence_number,
        .acknowledgment_number = payload_ack_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = payload_ack_packet.flags,
        .window_size = payload_ack_packet.window_size,
        .checksum_value = payload_ack_packet.checksum_value,
        .urgent_pointer = payload_ack_packet.urgent_pointer,
        .payload = payload_ack_packet.payload[0..payload_ack_packet.payload_len],
    });

    try std.testing.expectEqual(tcp.State.established, client.state);
    try std.testing.expectEqual(tcp.State.established, server.state);
    try std.testing.expectEqual(@as(u32, 0x0102_0305 + payload.len), client.send_next);
    try std.testing.expectEqual(@as(u32, 0x0102_0305 + payload.len), server.recv_next);
    try std.testing.expect(!client.retransmit.armed());
}

test "baremetal net pal streams payload across remote window through rtl8139 mock device" {
    rtl8139.testEnableMockDevice();
    defer rtl8139.testDisableMockDevice();

    try std.testing.expect(initDevice());
    const client_ip = [4]u8{ 192, 168, 56, 10 };
    const server_ip = [4]u8{ 192, 168, 56, 1 };
    const destination_mac = macAddress();
    const payload = "OPENCLAW-TCP-WINDOWED-PAYLOAD";

    var client = tcp.Session.initClient(4321, 443, 0x0102_0304, 4096);
    var server = tcp.Session.initServer(443, 4321, 0xA0B0_C0D0, 6);

    const syn = try client.buildSyn();
    _ = try sendTcpPacket(destination_mac, client_ip, server_ip, client.local_port, client.remote_port, syn.sequence_number, syn.acknowledgment_number, syn.flags, syn.window_size, syn.payload);
    const syn_packet = (try pollTcpPacketStrict()).?;
    const syn_ack = try server.acceptSyn(.{
        .source_port = syn_packet.source_port,
        .destination_port = syn_packet.destination_port,
        .sequence_number = syn_packet.sequence_number,
        .acknowledgment_number = syn_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = syn_packet.flags,
        .window_size = syn_packet.window_size,
        .checksum_value = syn_packet.checksum_value,
        .urgent_pointer = syn_packet.urgent_pointer,
        .payload = syn_packet.payload[0..syn_packet.payload_len],
    });

    _ = try sendTcpPacket(destination_mac, server_ip, client_ip, server.local_port, server.remote_port, syn_ack.sequence_number, syn_ack.acknowledgment_number, syn_ack.flags, syn_ack.window_size, syn_ack.payload);
    const syn_ack_packet = (try pollTcpPacketStrict()).?;
    const ack = try client.acceptSynAck(.{
        .source_port = syn_ack_packet.source_port,
        .destination_port = syn_ack_packet.destination_port,
        .sequence_number = syn_ack_packet.sequence_number,
        .acknowledgment_number = syn_ack_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = syn_ack_packet.flags,
        .window_size = syn_ack_packet.window_size,
        .checksum_value = syn_ack_packet.checksum_value,
        .urgent_pointer = syn_ack_packet.urgent_pointer,
        .payload = syn_ack_packet.payload[0..syn_ack_packet.payload_len],
    });

    _ = try sendTcpPacket(destination_mac, client_ip, server_ip, client.local_port, client.remote_port, ack.sequence_number, ack.acknowledgment_number, ack.flags, ack.window_size, ack.payload);
    const ack_packet = (try pollTcpPacketStrict()).?;
    try server.acceptAck(.{
        .source_port = ack_packet.source_port,
        .destination_port = ack_packet.destination_port,
        .sequence_number = ack_packet.sequence_number,
        .acknowledgment_number = ack_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = ack_packet.flags,
        .window_size = ack_packet.window_size,
        .checksum_value = ack_packet.checksum_value,
        .urgent_pointer = ack_packet.urgent_pointer,
        .payload = ack_packet.payload[0..ack_packet.payload_len],
    });

    var payload_offset: usize = 0;
    while (payload_offset < payload.len) {
        const outbound = try client.buildPayloadChunk(payload[payload_offset..]);
        _ = try sendTcpPacket(destination_mac, client_ip, server_ip, client.local_port, client.remote_port, outbound.sequence_number, outbound.acknowledgment_number, outbound.flags, outbound.window_size, outbound.payload);
        const outbound_packet = (try pollTcpPacketStrict()).?;

        const expected_chunk = payload[payload_offset .. payload_offset + outbound.payload.len];
        try std.testing.expectEqualStrings(expected_chunk, outbound.payload);
        try std.testing.expectEqualStrings(expected_chunk, outbound_packet.payload[0..outbound_packet.payload_len]);

        try server.acceptPayload(.{
            .source_port = outbound_packet.source_port,
            .destination_port = outbound_packet.destination_port,
            .sequence_number = outbound_packet.sequence_number,
            .acknowledgment_number = outbound_packet.acknowledgment_number,
            .data_offset_bytes = tcp.header_len,
            .flags = outbound_packet.flags,
            .window_size = outbound_packet.window_size,
            .checksum_value = outbound_packet.checksum_value,
            .urgent_pointer = outbound_packet.urgent_pointer,
            .payload = outbound_packet.payload[0..outbound_packet.payload_len],
        });

        payload_offset += outbound.payload.len;

        const payload_ack = try server.buildAck();
        _ = try sendTcpPacket(destination_mac, server_ip, client_ip, server.local_port, server.remote_port, payload_ack.sequence_number, payload_ack.acknowledgment_number, payload_ack.flags, payload_ack.window_size, payload_ack.payload);
        const payload_ack_packet = (try pollTcpPacketStrict()).?;
        try client.acceptAck(.{
            .source_port = payload_ack_packet.source_port,
            .destination_port = payload_ack_packet.destination_port,
            .sequence_number = payload_ack_packet.sequence_number,
            .acknowledgment_number = payload_ack_packet.acknowledgment_number,
            .data_offset_bytes = tcp.header_len,
            .flags = payload_ack_packet.flags,
            .window_size = payload_ack_packet.window_size,
            .checksum_value = payload_ack_packet.checksum_value,
            .urgent_pointer = payload_ack_packet.urgent_pointer,
            .payload = payload_ack_packet.payload[0..payload_ack_packet.payload_len],
        });
    }

    try std.testing.expectEqual(@as(usize, payload.len), payload_offset);
    try std.testing.expectEqual(tcp.State.established, client.state);
    try std.testing.expectEqual(tcp.State.established, server.state);
    try std.testing.expectEqual(@as(u32, 0x0102_0305 + payload.len), client.send_next);
    try std.testing.expectEqual(@as(u32, 0x0102_0305 + payload.len), server.recv_next);
}

test "baremetal net pal accepts cumulative ack after two in-flight chunks through rtl8139 mock device" {
    rtl8139.testEnableMockDevice();
    defer rtl8139.testDisableMockDevice();

    try std.testing.expect(initDevice());
    const client_ip = [4]u8{ 192, 168, 56, 10 };
    const server_ip = [4]u8{ 192, 168, 56, 1 };
    const destination_mac = macAddress();

    var client = tcp.Session.initClient(4321, 443, 0x0102_0304, 4096);
    var server = tcp.Session.initServer(443, 4321, 0xA0B0_C0D0, 8);

    const syn = try client.buildSyn();
    _ = try sendTcpPacket(destination_mac, client_ip, server_ip, client.local_port, client.remote_port, syn.sequence_number, syn.acknowledgment_number, syn.flags, syn.window_size, syn.payload);
    const syn_packet = (try pollTcpPacketStrict()).?;
    const syn_ack = try server.acceptSyn(.{
        .source_port = syn_packet.source_port,
        .destination_port = syn_packet.destination_port,
        .sequence_number = syn_packet.sequence_number,
        .acknowledgment_number = syn_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = syn_packet.flags,
        .window_size = syn_packet.window_size,
        .checksum_value = syn_packet.checksum_value,
        .urgent_pointer = syn_packet.urgent_pointer,
        .payload = syn_packet.payload[0..syn_packet.payload_len],
    });

    _ = try sendTcpPacket(destination_mac, server_ip, client_ip, server.local_port, server.remote_port, syn_ack.sequence_number, syn_ack.acknowledgment_number, syn_ack.flags, syn_ack.window_size, syn_ack.payload);
    const syn_ack_packet = (try pollTcpPacketStrict()).?;
    const ack = try client.acceptSynAck(.{
        .source_port = syn_ack_packet.source_port,
        .destination_port = syn_ack_packet.destination_port,
        .sequence_number = syn_ack_packet.sequence_number,
        .acknowledgment_number = syn_ack_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = syn_ack_packet.flags,
        .window_size = syn_ack_packet.window_size,
        .checksum_value = syn_ack_packet.checksum_value,
        .urgent_pointer = syn_ack_packet.urgent_pointer,
        .payload = syn_ack_packet.payload[0..syn_ack_packet.payload_len],
    });

    _ = try sendTcpPacket(destination_mac, client_ip, server_ip, client.local_port, client.remote_port, ack.sequence_number, ack.acknowledgment_number, ack.flags, ack.window_size, ack.payload);
    const ack_packet = (try pollTcpPacketStrict()).?;
    try server.acceptAck(.{
        .source_port = ack_packet.source_port,
        .destination_port = ack_packet.destination_port,
        .sequence_number = ack_packet.sequence_number,
        .acknowledgment_number = ack_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = ack_packet.flags,
        .window_size = ack_packet.window_size,
        .checksum_value = ack_packet.checksum_value,
        .urgent_pointer = ack_packet.urgent_pointer,
        .payload = ack_packet.payload[0..ack_packet.payload_len],
    });

    const first_chunk = try client.buildPayloadChunk("ABCD");
    _ = try sendTcpPacket(destination_mac, client_ip, server_ip, client.local_port, client.remote_port, first_chunk.sequence_number, first_chunk.acknowledgment_number, first_chunk.flags, first_chunk.window_size, first_chunk.payload);
    const first_packet = (try pollTcpPacketStrict()).?;
    try std.testing.expectEqualStrings("ABCD", first_packet.payload[0..first_packet.payload_len]);
    try server.acceptPayload(.{
        .source_port = first_packet.source_port,
        .destination_port = first_packet.destination_port,
        .sequence_number = first_packet.sequence_number,
        .acknowledgment_number = first_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = first_packet.flags,
        .window_size = first_packet.window_size,
        .checksum_value = first_packet.checksum_value,
        .urgent_pointer = first_packet.urgent_pointer,
        .payload = first_packet.payload[0..first_packet.payload_len],
    });

    const second_chunk = try client.buildPayloadChunk("EFGH");
    _ = try sendTcpPacket(destination_mac, client_ip, server_ip, client.local_port, client.remote_port, second_chunk.sequence_number, second_chunk.acknowledgment_number, second_chunk.flags, second_chunk.window_size, second_chunk.payload);
    const second_packet = (try pollTcpPacketStrict()).?;
    try std.testing.expectEqualStrings("EFGH", second_packet.payload[0..second_packet.payload_len]);
    try server.acceptPayload(.{
        .source_port = second_packet.source_port,
        .destination_port = second_packet.destination_port,
        .sequence_number = second_packet.sequence_number,
        .acknowledgment_number = second_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = second_packet.flags,
        .window_size = second_packet.window_size,
        .checksum_value = second_packet.checksum_value,
        .urgent_pointer = second_packet.urgent_pointer,
        .payload = second_packet.payload[0..second_packet.payload_len],
    });

    try std.testing.expectEqual(@as(u32, 8), client.bytesInFlight());
    try std.testing.expectError(error.WindowExceeded, client.buildPayloadChunk("I"));

    const payload_ack = try server.buildAck();
    _ = try sendTcpPacket(destination_mac, server_ip, client_ip, server.local_port, server.remote_port, payload_ack.sequence_number, payload_ack.acknowledgment_number, payload_ack.flags, payload_ack.window_size, payload_ack.payload);
    const payload_ack_packet = (try pollTcpPacketStrict()).?;
    try client.acceptAck(.{
        .source_port = payload_ack_packet.source_port,
        .destination_port = payload_ack_packet.destination_port,
        .sequence_number = payload_ack_packet.sequence_number,
        .acknowledgment_number = payload_ack_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = payload_ack_packet.flags,
        .window_size = payload_ack_packet.window_size,
        .checksum_value = payload_ack_packet.checksum_value,
        .urgent_pointer = payload_ack_packet.urgent_pointer,
        .payload = payload_ack_packet.payload[0..payload_ack_packet.payload_len],
    });

    try std.testing.expectEqual(@as(u32, 0), client.bytesInFlight());
    try std.testing.expectEqual(@as(u32, 0x0102_0305 + 8), client.send_next);
    try std.testing.expectEqual(@as(u32, 0x0102_0305 + 8), client.send_unacked);
    try std.testing.expectEqual(@as(u32, 0x0102_0305 + 8), server.recv_next);
}

test "baremetal net pal retransmits dropped fins and completes tcp teardown through rtl8139 mock device" {
    rtl8139.testEnableMockDevice();
    defer rtl8139.testDisableMockDevice();

    try std.testing.expect(initDevice());
    const client_ip = [4]u8{ 192, 168, 56, 10 };
    const server_ip = [4]u8{ 192, 168, 56, 1 };
    const destination_mac = macAddress();
    const payload = "OPENCLAW-TCP-FIN";
    const retransmit_interval_ticks: u64 = 5;

    var client = tcp.Session.initClient(4321, 443, 0x0102_0304, 4096);
    var server = tcp.Session.initServer(443, 4321, 0xA0B0_C0D0, 8192);

    const syn = try client.buildSyn();
    _ = try sendTcpPacket(destination_mac, client_ip, server_ip, client.local_port, client.remote_port, syn.sequence_number, syn.acknowledgment_number, syn.flags, syn.window_size, syn.payload);
    const syn_packet = (try pollTcpPacketStrict()).?;
    const syn_ack = try server.acceptSyn(.{
        .source_port = syn_packet.source_port,
        .destination_port = syn_packet.destination_port,
        .sequence_number = syn_packet.sequence_number,
        .acknowledgment_number = syn_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = syn_packet.flags,
        .window_size = syn_packet.window_size,
        .checksum_value = syn_packet.checksum_value,
        .urgent_pointer = syn_packet.urgent_pointer,
        .payload = syn_packet.payload[0..syn_packet.payload_len],
    });

    _ = try sendTcpPacket(destination_mac, server_ip, client_ip, server.local_port, server.remote_port, syn_ack.sequence_number, syn_ack.acknowledgment_number, syn_ack.flags, syn_ack.window_size, syn_ack.payload);
    const syn_ack_packet = (try pollTcpPacketStrict()).?;
    const ack = try client.acceptSynAck(.{
        .source_port = syn_ack_packet.source_port,
        .destination_port = syn_ack_packet.destination_port,
        .sequence_number = syn_ack_packet.sequence_number,
        .acknowledgment_number = syn_ack_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = syn_ack_packet.flags,
        .window_size = syn_ack_packet.window_size,
        .checksum_value = syn_ack_packet.checksum_value,
        .urgent_pointer = syn_ack_packet.urgent_pointer,
        .payload = syn_ack_packet.payload[0..syn_ack_packet.payload_len],
    });

    _ = try sendTcpPacket(destination_mac, client_ip, server_ip, client.local_port, client.remote_port, ack.sequence_number, ack.acknowledgment_number, ack.flags, ack.window_size, ack.payload);
    const ack_packet = (try pollTcpPacketStrict()).?;
    try server.acceptAck(.{
        .source_port = ack_packet.source_port,
        .destination_port = ack_packet.destination_port,
        .sequence_number = ack_packet.sequence_number,
        .acknowledgment_number = ack_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = ack_packet.flags,
        .window_size = ack_packet.window_size,
        .checksum_value = ack_packet.checksum_value,
        .urgent_pointer = ack_packet.urgent_pointer,
        .payload = ack_packet.payload[0..ack_packet.payload_len],
    });

    const data = try client.buildPayload(payload);
    _ = try sendTcpPacket(destination_mac, client_ip, server_ip, client.local_port, client.remote_port, data.sequence_number, data.acknowledgment_number, data.flags, data.window_size, data.payload);
    const data_packet = (try pollTcpPacketStrict()).?;
    try server.acceptPayload(.{
        .source_port = data_packet.source_port,
        .destination_port = data_packet.destination_port,
        .sequence_number = data_packet.sequence_number,
        .acknowledgment_number = data_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = data_packet.flags,
        .window_size = data_packet.window_size,
        .checksum_value = data_packet.checksum_value,
        .urgent_pointer = data_packet.urgent_pointer,
        .payload = data_packet.payload[0..data_packet.payload_len],
    });

    const payload_ack = try server.buildAck();
    _ = try sendTcpPacket(destination_mac, server_ip, client_ip, server.local_port, server.remote_port, payload_ack.sequence_number, payload_ack.acknowledgment_number, payload_ack.flags, payload_ack.window_size, payload_ack.payload);
    const payload_ack_packet = (try pollTcpPacketStrict()).?;
    try client.acceptAck(.{
        .source_port = payload_ack_packet.source_port,
        .destination_port = payload_ack_packet.destination_port,
        .sequence_number = payload_ack_packet.sequence_number,
        .acknowledgment_number = payload_ack_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = payload_ack_packet.flags,
        .window_size = payload_ack_packet.window_size,
        .checksum_value = payload_ack_packet.checksum_value,
        .urgent_pointer = payload_ack_packet.urgent_pointer,
        .payload = payload_ack_packet.payload[0..payload_ack_packet.payload_len],
    });

    const client_fin = try client.buildFinWithTimeout(100, retransmit_interval_ticks);
    try std.testing.expect(client.retransmit.armed());
    try std.testing.expectEqual(tcp.RetransmitKind.fin, client.retransmit.kind);
    try std.testing.expectEqual(@as(?tcp.Outbound, null), client.pollRetransmit(104));
    const retry_client_fin = client.pollRetransmit(105) orelse unreachable;
    try std.testing.expectEqual(client_fin.sequence_number, retry_client_fin.sequence_number);
    try std.testing.expectEqual(client_fin.acknowledgment_number, retry_client_fin.acknowledgment_number);
    try std.testing.expectEqual(client_fin.flags, retry_client_fin.flags);
    try std.testing.expectEqual(client_fin.window_size, retry_client_fin.window_size);
    try std.testing.expectEqual(@as(u32, 1), client.retransmit.attempts);

    _ = try sendTcpPacket(destination_mac, client_ip, server_ip, client.local_port, client.remote_port, retry_client_fin.sequence_number, retry_client_fin.acknowledgment_number, retry_client_fin.flags, retry_client_fin.window_size, retry_client_fin.payload);
    const client_fin_packet = (try pollTcpPacketStrict()).?;
    const fin_ack = try server.acceptFin(.{
        .source_port = client_fin_packet.source_port,
        .destination_port = client_fin_packet.destination_port,
        .sequence_number = client_fin_packet.sequence_number,
        .acknowledgment_number = client_fin_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = client_fin_packet.flags,
        .window_size = client_fin_packet.window_size,
        .checksum_value = client_fin_packet.checksum_value,
        .urgent_pointer = client_fin_packet.urgent_pointer,
        .payload = client_fin_packet.payload[0..client_fin_packet.payload_len],
    });

    _ = try sendTcpPacket(destination_mac, server_ip, client_ip, server.local_port, server.remote_port, fin_ack.sequence_number, fin_ack.acknowledgment_number, fin_ack.flags, fin_ack.window_size, fin_ack.payload);
    const fin_ack_packet = (try pollTcpPacketStrict()).?;
    try client.acceptAck(.{
        .source_port = fin_ack_packet.source_port,
        .destination_port = fin_ack_packet.destination_port,
        .sequence_number = fin_ack_packet.sequence_number,
        .acknowledgment_number = fin_ack_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = fin_ack_packet.flags,
        .window_size = fin_ack_packet.window_size,
        .checksum_value = fin_ack_packet.checksum_value,
        .urgent_pointer = fin_ack_packet.urgent_pointer,
        .payload = fin_ack_packet.payload[0..fin_ack_packet.payload_len],
    });
    try std.testing.expect(!client.retransmit.armed());

    const server_fin = try server.buildFinWithTimeout(200, retransmit_interval_ticks);
    try std.testing.expect(server.retransmit.armed());
    try std.testing.expectEqual(tcp.RetransmitKind.fin, server.retransmit.kind);
    try std.testing.expectEqual(@as(?tcp.Outbound, null), server.pollRetransmit(204));
    const retry_server_fin = server.pollRetransmit(205) orelse unreachable;
    try std.testing.expectEqual(server_fin.sequence_number, retry_server_fin.sequence_number);
    try std.testing.expectEqual(server_fin.acknowledgment_number, retry_server_fin.acknowledgment_number);
    try std.testing.expectEqual(server_fin.flags, retry_server_fin.flags);
    try std.testing.expectEqual(server_fin.window_size, retry_server_fin.window_size);
    try std.testing.expectEqual(@as(u32, 1), server.retransmit.attempts);

    _ = try sendTcpPacket(destination_mac, server_ip, client_ip, server.local_port, server.remote_port, retry_server_fin.sequence_number, retry_server_fin.acknowledgment_number, retry_server_fin.flags, retry_server_fin.window_size, retry_server_fin.payload);
    const server_fin_packet = (try pollTcpPacketStrict()).?;
    const final_ack = try client.acceptFin(.{
        .source_port = server_fin_packet.source_port,
        .destination_port = server_fin_packet.destination_port,
        .sequence_number = server_fin_packet.sequence_number,
        .acknowledgment_number = server_fin_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = server_fin_packet.flags,
        .window_size = server_fin_packet.window_size,
        .checksum_value = server_fin_packet.checksum_value,
        .urgent_pointer = server_fin_packet.urgent_pointer,
        .payload = server_fin_packet.payload[0..server_fin_packet.payload_len],
    });

    _ = try sendTcpPacket(destination_mac, client_ip, server_ip, client.local_port, client.remote_port, final_ack.sequence_number, final_ack.acknowledgment_number, final_ack.flags, final_ack.window_size, final_ack.payload);
    const final_ack_packet = (try pollTcpPacketStrict()).?;
    try server.acceptAck(.{
        .source_port = final_ack_packet.source_port,
        .destination_port = final_ack_packet.destination_port,
        .sequence_number = final_ack_packet.sequence_number,
        .acknowledgment_number = final_ack_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = final_ack_packet.flags,
        .window_size = final_ack_packet.window_size,
        .checksum_value = final_ack_packet.checksum_value,
        .urgent_pointer = final_ack_packet.urgent_pointer,
        .payload = final_ack_packet.payload[0..final_ack_packet.payload_len],
    });
    try std.testing.expect(!server.retransmit.armed());

    try std.testing.expectEqual(tcp.State.closed, client.state);
    try std.testing.expectEqual(tcp.State.closed, server.state);
    try std.testing.expectEqual(@as(u32, 0x0102_0306 + payload.len), client.send_next);
    try std.testing.expectEqual(@as(u32, 0x0102_0306 + payload.len), server.recv_next);
    try std.testing.expectEqual(@as(u32, 0xA0B0_C0D2), client.recv_next);
    try std.testing.expectEqual(@as(u32, 0xA0B0_C0D2), server.send_next);
}

test "baremetal net pal manages two tcp sessions independently through rtl8139 mock device" {
    rtl8139.testEnableMockDevice();
    defer rtl8139.testDisableMockDevice();

    try std.testing.expect(initDevice());
    const client_ip = [4]u8{ 192, 168, 56, 10 };
    const server_ip = [4]u8{ 192, 168, 56, 1 };
    const destination_mac = macAddress();
    const flow_a = tcp.FlowKey{
        .local_ip = client_ip,
        .remote_ip = server_ip,
        .local_port = 4321,
        .remote_port = 443,
    };
    const flow_b = tcp.FlowKey{
        .local_ip = client_ip,
        .remote_ip = server_ip,
        .local_port = 4322,
        .remote_port = 444,
    };

    var table = tcp.SessionTable(2).init();
    const client_a = try table.createClient(flow_a, 0x0102_0304, 4096);
    const client_b = try table.createClient(flow_b, 0x1112_1314, 4096);
    var server_a = tcp.Session.initServer(flow_a.remote_port, flow_a.local_port, 0xA0B0_C0D0, 8192);
    var server_b = tcp.Session.initServer(flow_b.remote_port, flow_b.local_port, 0xB0C0_D0E0, 6144);

    const syn_a = try client_a.buildSyn();
    _ = try sendTcpPacket(destination_mac, client_ip, server_ip, client_a.local_port, client_a.remote_port, syn_a.sequence_number, syn_a.acknowledgment_number, syn_a.flags, syn_a.window_size, syn_a.payload);
    const syn_a_packet = (try pollTcpPacketStrict()).?;
    const syn_ack_a = try server_a.acceptSyn(.{
        .source_port = syn_a_packet.source_port,
        .destination_port = syn_a_packet.destination_port,
        .sequence_number = syn_a_packet.sequence_number,
        .acknowledgment_number = syn_a_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = syn_a_packet.flags,
        .window_size = syn_a_packet.window_size,
        .checksum_value = syn_a_packet.checksum_value,
        .urgent_pointer = syn_a_packet.urgent_pointer,
        .payload = syn_a_packet.payload[0..syn_a_packet.payload_len],
    });

    const syn_b = try client_b.buildSyn();
    _ = try sendTcpPacket(destination_mac, client_ip, server_ip, client_b.local_port, client_b.remote_port, syn_b.sequence_number, syn_b.acknowledgment_number, syn_b.flags, syn_b.window_size, syn_b.payload);
    const syn_b_packet = (try pollTcpPacketStrict()).?;
    const syn_ack_b = try server_b.acceptSyn(.{
        .source_port = syn_b_packet.source_port,
        .destination_port = syn_b_packet.destination_port,
        .sequence_number = syn_b_packet.sequence_number,
        .acknowledgment_number = syn_b_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = syn_b_packet.flags,
        .window_size = syn_b_packet.window_size,
        .checksum_value = syn_b_packet.checksum_value,
        .urgent_pointer = syn_b_packet.urgent_pointer,
        .payload = syn_b_packet.payload[0..syn_b_packet.payload_len],
    });

    _ = try sendTcpPacket(destination_mac, server_ip, client_ip, server_a.local_port, server_a.remote_port, syn_ack_a.sequence_number, syn_ack_a.acknowledgment_number, syn_ack_a.flags, syn_ack_a.window_size, syn_ack_a.payload);
    const syn_ack_a_packet = (try pollTcpPacketStrict()).?;
    const mapped_a = table.findByInboundPacket(server_ip, client_ip, .{
        .source_port = syn_ack_a_packet.source_port,
        .destination_port = syn_ack_a_packet.destination_port,
        .sequence_number = syn_ack_a_packet.sequence_number,
        .acknowledgment_number = syn_ack_a_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = syn_ack_a_packet.flags,
        .window_size = syn_ack_a_packet.window_size,
        .checksum_value = syn_ack_a_packet.checksum_value,
        .urgent_pointer = syn_ack_a_packet.urgent_pointer,
        .payload = syn_ack_a_packet.payload[0..syn_ack_a_packet.payload_len],
    }).?;
    try std.testing.expect(mapped_a == client_a);
    const ack_a = try mapped_a.acceptSynAck(.{
        .source_port = syn_ack_a_packet.source_port,
        .destination_port = syn_ack_a_packet.destination_port,
        .sequence_number = syn_ack_a_packet.sequence_number,
        .acknowledgment_number = syn_ack_a_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = syn_ack_a_packet.flags,
        .window_size = syn_ack_a_packet.window_size,
        .checksum_value = syn_ack_a_packet.checksum_value,
        .urgent_pointer = syn_ack_a_packet.urgent_pointer,
        .payload = syn_ack_a_packet.payload[0..syn_ack_a_packet.payload_len],
    });
    _ = try sendTcpPacket(destination_mac, client_ip, server_ip, client_a.local_port, client_a.remote_port, ack_a.sequence_number, ack_a.acknowledgment_number, ack_a.flags, ack_a.window_size, ack_a.payload);
    const ack_a_packet = (try pollTcpPacketStrict()).?;
    try server_a.acceptAck(.{
        .source_port = ack_a_packet.source_port,
        .destination_port = ack_a_packet.destination_port,
        .sequence_number = ack_a_packet.sequence_number,
        .acknowledgment_number = ack_a_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = ack_a_packet.flags,
        .window_size = ack_a_packet.window_size,
        .checksum_value = ack_a_packet.checksum_value,
        .urgent_pointer = ack_a_packet.urgent_pointer,
        .payload = ack_a_packet.payload[0..ack_a_packet.payload_len],
    });

    _ = try sendTcpPacket(destination_mac, server_ip, client_ip, server_b.local_port, server_b.remote_port, syn_ack_b.sequence_number, syn_ack_b.acknowledgment_number, syn_ack_b.flags, syn_ack_b.window_size, syn_ack_b.payload);
    const syn_ack_b_packet = (try pollTcpPacketStrict()).?;
    const mapped_b = table.findByInboundPacket(server_ip, client_ip, .{
        .source_port = syn_ack_b_packet.source_port,
        .destination_port = syn_ack_b_packet.destination_port,
        .sequence_number = syn_ack_b_packet.sequence_number,
        .acknowledgment_number = syn_ack_b_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = syn_ack_b_packet.flags,
        .window_size = syn_ack_b_packet.window_size,
        .checksum_value = syn_ack_b_packet.checksum_value,
        .urgent_pointer = syn_ack_b_packet.urgent_pointer,
        .payload = syn_ack_b_packet.payload[0..syn_ack_b_packet.payload_len],
    }).?;
    try std.testing.expect(mapped_b == client_b);
    const ack_b = try mapped_b.acceptSynAck(.{
        .source_port = syn_ack_b_packet.source_port,
        .destination_port = syn_ack_b_packet.destination_port,
        .sequence_number = syn_ack_b_packet.sequence_number,
        .acknowledgment_number = syn_ack_b_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = syn_ack_b_packet.flags,
        .window_size = syn_ack_b_packet.window_size,
        .checksum_value = syn_ack_b_packet.checksum_value,
        .urgent_pointer = syn_ack_b_packet.urgent_pointer,
        .payload = syn_ack_b_packet.payload[0..syn_ack_b_packet.payload_len],
    });
    _ = try sendTcpPacket(destination_mac, client_ip, server_ip, client_b.local_port, client_b.remote_port, ack_b.sequence_number, ack_b.acknowledgment_number, ack_b.flags, ack_b.window_size, ack_b.payload);
    const ack_b_packet = (try pollTcpPacketStrict()).?;
    try server_b.acceptAck(.{
        .source_port = ack_b_packet.source_port,
        .destination_port = ack_b_packet.destination_port,
        .sequence_number = ack_b_packet.sequence_number,
        .acknowledgment_number = ack_b_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = ack_b_packet.flags,
        .window_size = ack_b_packet.window_size,
        .checksum_value = ack_b_packet.checksum_value,
        .urgent_pointer = ack_b_packet.urgent_pointer,
        .payload = ack_b_packet.payload[0..ack_b_packet.payload_len],
    });

    const payload_b = "FLOW-B";
    const data_b = try client_b.buildPayload(payload_b);
    _ = try sendTcpPacket(destination_mac, client_ip, server_ip, client_b.local_port, client_b.remote_port, data_b.sequence_number, data_b.acknowledgment_number, data_b.flags, data_b.window_size, data_b.payload);
    const data_b_packet = (try pollTcpPacketStrict()).?;
    try server_b.acceptPayload(.{
        .source_port = data_b_packet.source_port,
        .destination_port = data_b_packet.destination_port,
        .sequence_number = data_b_packet.sequence_number,
        .acknowledgment_number = data_b_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = data_b_packet.flags,
        .window_size = data_b_packet.window_size,
        .checksum_value = data_b_packet.checksum_value,
        .urgent_pointer = data_b_packet.urgent_pointer,
        .payload = data_b_packet.payload[0..data_b_packet.payload_len],
    });
    const payload_ack_b = try server_b.buildAck();
    _ = try sendTcpPacket(destination_mac, server_ip, client_ip, server_b.local_port, server_b.remote_port, payload_ack_b.sequence_number, payload_ack_b.acknowledgment_number, payload_ack_b.flags, payload_ack_b.window_size, payload_ack_b.payload);
    const payload_ack_b_packet = (try pollTcpPacketStrict()).?;
    try table.findByInboundPacket(server_ip, client_ip, .{
        .source_port = payload_ack_b_packet.source_port,
        .destination_port = payload_ack_b_packet.destination_port,
        .sequence_number = payload_ack_b_packet.sequence_number,
        .acknowledgment_number = payload_ack_b_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = payload_ack_b_packet.flags,
        .window_size = payload_ack_b_packet.window_size,
        .checksum_value = payload_ack_b_packet.checksum_value,
        .urgent_pointer = payload_ack_b_packet.urgent_pointer,
        .payload = payload_ack_b_packet.payload[0..payload_ack_b_packet.payload_len],
    }).?.acceptAck(.{
        .source_port = payload_ack_b_packet.source_port,
        .destination_port = payload_ack_b_packet.destination_port,
        .sequence_number = payload_ack_b_packet.sequence_number,
        .acknowledgment_number = payload_ack_b_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = payload_ack_b_packet.flags,
        .window_size = payload_ack_b_packet.window_size,
        .checksum_value = payload_ack_b_packet.checksum_value,
        .urgent_pointer = payload_ack_b_packet.urgent_pointer,
        .payload = payload_ack_b_packet.payload[0..payload_ack_b_packet.payload_len],
    });

    const payload_a = "FLOW-A";
    const data_a = try client_a.buildPayload(payload_a);
    _ = try sendTcpPacket(destination_mac, client_ip, server_ip, client_a.local_port, client_a.remote_port, data_a.sequence_number, data_a.acknowledgment_number, data_a.flags, data_a.window_size, data_a.payload);
    const data_a_packet = (try pollTcpPacketStrict()).?;
    try server_a.acceptPayload(.{
        .source_port = data_a_packet.source_port,
        .destination_port = data_a_packet.destination_port,
        .sequence_number = data_a_packet.sequence_number,
        .acknowledgment_number = data_a_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = data_a_packet.flags,
        .window_size = data_a_packet.window_size,
        .checksum_value = data_a_packet.checksum_value,
        .urgent_pointer = data_a_packet.urgent_pointer,
        .payload = data_a_packet.payload[0..data_a_packet.payload_len],
    });
    const payload_ack_a = try server_a.buildAck();
    _ = try sendTcpPacket(destination_mac, server_ip, client_ip, server_a.local_port, server_a.remote_port, payload_ack_a.sequence_number, payload_ack_a.acknowledgment_number, payload_ack_a.flags, payload_ack_a.window_size, payload_ack_a.payload);
    const payload_ack_a_packet = (try pollTcpPacketStrict()).?;
    try table.findByInboundPacket(server_ip, client_ip, .{
        .source_port = payload_ack_a_packet.source_port,
        .destination_port = payload_ack_a_packet.destination_port,
        .sequence_number = payload_ack_a_packet.sequence_number,
        .acknowledgment_number = payload_ack_a_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = payload_ack_a_packet.flags,
        .window_size = payload_ack_a_packet.window_size,
        .checksum_value = payload_ack_a_packet.checksum_value,
        .urgent_pointer = payload_ack_a_packet.urgent_pointer,
        .payload = payload_ack_a_packet.payload[0..payload_ack_a_packet.payload_len],
    }).?.acceptAck(.{
        .source_port = payload_ack_a_packet.source_port,
        .destination_port = payload_ack_a_packet.destination_port,
        .sequence_number = payload_ack_a_packet.sequence_number,
        .acknowledgment_number = payload_ack_a_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = payload_ack_a_packet.flags,
        .window_size = payload_ack_a_packet.window_size,
        .checksum_value = payload_ack_a_packet.checksum_value,
        .urgent_pointer = payload_ack_a_packet.urgent_pointer,
        .payload = payload_ack_a_packet.payload[0..payload_ack_a_packet.payload_len],
    });

    const client_fin_a = try client_a.buildFin();
    _ = try sendTcpPacket(destination_mac, client_ip, server_ip, client_a.local_port, client_a.remote_port, client_fin_a.sequence_number, client_fin_a.acknowledgment_number, client_fin_a.flags, client_fin_a.window_size, client_fin_a.payload);
    const client_fin_a_packet = (try pollTcpPacketStrict()).?;
    const fin_ack_a = try server_a.acceptFin(.{
        .source_port = client_fin_a_packet.source_port,
        .destination_port = client_fin_a_packet.destination_port,
        .sequence_number = client_fin_a_packet.sequence_number,
        .acknowledgment_number = client_fin_a_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = client_fin_a_packet.flags,
        .window_size = client_fin_a_packet.window_size,
        .checksum_value = client_fin_a_packet.checksum_value,
        .urgent_pointer = client_fin_a_packet.urgent_pointer,
        .payload = client_fin_a_packet.payload[0..client_fin_a_packet.payload_len],
    });
    _ = try sendTcpPacket(destination_mac, server_ip, client_ip, server_a.local_port, server_a.remote_port, fin_ack_a.sequence_number, fin_ack_a.acknowledgment_number, fin_ack_a.flags, fin_ack_a.window_size, fin_ack_a.payload);
    const fin_ack_a_packet = (try pollTcpPacketStrict()).?;
    try table.findByInboundPacket(server_ip, client_ip, .{
        .source_port = fin_ack_a_packet.source_port,
        .destination_port = fin_ack_a_packet.destination_port,
        .sequence_number = fin_ack_a_packet.sequence_number,
        .acknowledgment_number = fin_ack_a_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = fin_ack_a_packet.flags,
        .window_size = fin_ack_a_packet.window_size,
        .checksum_value = fin_ack_a_packet.checksum_value,
        .urgent_pointer = fin_ack_a_packet.urgent_pointer,
        .payload = fin_ack_a_packet.payload[0..fin_ack_a_packet.payload_len],
    }).?.acceptAck(.{
        .source_port = fin_ack_a_packet.source_port,
        .destination_port = fin_ack_a_packet.destination_port,
        .sequence_number = fin_ack_a_packet.sequence_number,
        .acknowledgment_number = fin_ack_a_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = fin_ack_a_packet.flags,
        .window_size = fin_ack_a_packet.window_size,
        .checksum_value = fin_ack_a_packet.checksum_value,
        .urgent_pointer = fin_ack_a_packet.urgent_pointer,
        .payload = fin_ack_a_packet.payload[0..fin_ack_a_packet.payload_len],
    });

    const server_fin_a = try server_a.buildFin();
    _ = try sendTcpPacket(destination_mac, server_ip, client_ip, server_a.local_port, server_a.remote_port, server_fin_a.sequence_number, server_fin_a.acknowledgment_number, server_fin_a.flags, server_fin_a.window_size, server_fin_a.payload);
    const server_fin_a_packet = (try pollTcpPacketStrict()).?;
    const final_ack_a = try table.findByInboundPacket(server_ip, client_ip, .{
        .source_port = server_fin_a_packet.source_port,
        .destination_port = server_fin_a_packet.destination_port,
        .sequence_number = server_fin_a_packet.sequence_number,
        .acknowledgment_number = server_fin_a_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = server_fin_a_packet.flags,
        .window_size = server_fin_a_packet.window_size,
        .checksum_value = server_fin_a_packet.checksum_value,
        .urgent_pointer = server_fin_a_packet.urgent_pointer,
        .payload = server_fin_a_packet.payload[0..server_fin_a_packet.payload_len],
    }).?.acceptFin(.{
        .source_port = server_fin_a_packet.source_port,
        .destination_port = server_fin_a_packet.destination_port,
        .sequence_number = server_fin_a_packet.sequence_number,
        .acknowledgment_number = server_fin_a_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = server_fin_a_packet.flags,
        .window_size = server_fin_a_packet.window_size,
        .checksum_value = server_fin_a_packet.checksum_value,
        .urgent_pointer = server_fin_a_packet.urgent_pointer,
        .payload = server_fin_a_packet.payload[0..server_fin_a_packet.payload_len],
    });
    _ = try sendTcpPacket(destination_mac, client_ip, server_ip, client_a.local_port, client_a.remote_port, final_ack_a.sequence_number, final_ack_a.acknowledgment_number, final_ack_a.flags, final_ack_a.window_size, final_ack_a.payload);
    const final_ack_a_packet = (try pollTcpPacketStrict()).?;
    try server_a.acceptAck(.{
        .source_port = final_ack_a_packet.source_port,
        .destination_port = final_ack_a_packet.destination_port,
        .sequence_number = final_ack_a_packet.sequence_number,
        .acknowledgment_number = final_ack_a_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = final_ack_a_packet.flags,
        .window_size = final_ack_a_packet.window_size,
        .checksum_value = final_ack_a_packet.checksum_value,
        .urgent_pointer = final_ack_a_packet.urgent_pointer,
        .payload = final_ack_a_packet.payload[0..final_ack_a_packet.payload_len],
    });

    try std.testing.expectEqual(tcp.State.closed, client_a.state);
    try std.testing.expectEqual(tcp.State.closed, server_a.state);
    try std.testing.expectEqual(tcp.State.established, client_b.state);
    try std.testing.expectEqual(tcp.State.established, server_b.state);

    const payload_b2 = "FLOW-B-LIVE";
    const data_b2 = try client_b.buildPayload(payload_b2);
    _ = try sendTcpPacket(destination_mac, client_ip, server_ip, client_b.local_port, client_b.remote_port, data_b2.sequence_number, data_b2.acknowledgment_number, data_b2.flags, data_b2.window_size, data_b2.payload);
    const data_b2_packet = (try pollTcpPacketStrict()).?;
    try server_b.acceptPayload(.{
        .source_port = data_b2_packet.source_port,
        .destination_port = data_b2_packet.destination_port,
        .sequence_number = data_b2_packet.sequence_number,
        .acknowledgment_number = data_b2_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = data_b2_packet.flags,
        .window_size = data_b2_packet.window_size,
        .checksum_value = data_b2_packet.checksum_value,
        .urgent_pointer = data_b2_packet.urgent_pointer,
        .payload = data_b2_packet.payload[0..data_b2_packet.payload_len],
    });
    const payload_b2_ack = try server_b.buildAck();
    _ = try sendTcpPacket(destination_mac, server_ip, client_ip, server_b.local_port, server_b.remote_port, payload_b2_ack.sequence_number, payload_b2_ack.acknowledgment_number, payload_b2_ack.flags, payload_b2_ack.window_size, payload_b2_ack.payload);
    const payload_b2_ack_packet = (try pollTcpPacketStrict()).?;
    const mapped_b2 = table.findByInboundPacket(server_ip, client_ip, .{
        .source_port = payload_b2_ack_packet.source_port,
        .destination_port = payload_b2_ack_packet.destination_port,
        .sequence_number = payload_b2_ack_packet.sequence_number,
        .acknowledgment_number = payload_b2_ack_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = payload_b2_ack_packet.flags,
        .window_size = payload_b2_ack_packet.window_size,
        .checksum_value = payload_b2_ack_packet.checksum_value,
        .urgent_pointer = payload_b2_ack_packet.urgent_pointer,
        .payload = payload_b2_ack_packet.payload[0..payload_b2_ack_packet.payload_len],
    }).?;
    try std.testing.expect(mapped_b2 == client_b);
    try mapped_b2.acceptAck(.{
        .source_port = payload_b2_ack_packet.source_port,
        .destination_port = payload_b2_ack_packet.destination_port,
        .sequence_number = payload_b2_ack_packet.sequence_number,
        .acknowledgment_number = payload_b2_ack_packet.acknowledgment_number,
        .data_offset_bytes = tcp.header_len,
        .flags = payload_b2_ack_packet.flags,
        .window_size = payload_b2_ack_packet.window_size,
        .checksum_value = payload_b2_ack_packet.checksum_value,
        .urgent_pointer = payload_b2_ack_packet.urgent_pointer,
        .payload = payload_b2_ack_packet.payload[0..payload_b2_ack_packet.payload_len],
    });

    try std.testing.expectEqual(@as(usize, 2), table.entryCount());
    try std.testing.expectEqual(tcp.State.established, client_b.state);
}

test "baremetal net pal sends and parses dhcp discover through rtl8139 mock device" {
    rtl8139.testEnableMockDevice();
    defer rtl8139.testDisableMockDevice();

    try std.testing.expect(initDevice());
    const client_mac = macAddress();
    const parameter_request_list = [_]u8{
        dhcp.option_subnet_mask,
        dhcp.option_router,
        dhcp.option_dns_server,
        dhcp.option_hostname,
    };

    _ = try sendDhcpDiscover(0x1234_5678, client_mac, parameter_request_list[0..]);

    const packet = (try pollDhcpPacket()).?;
    try std.testing.expectEqual(@as(u16, dhcp.client_port), packet.source_port);
    try std.testing.expectEqual(@as(u16, dhcp.server_port), packet.destination_port);
    try std.testing.expectEqual(ipv4.protocol_udp, packet.ipv4_header.protocol);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0, 0, 0, 0 }, packet.ipv4_header.source_ip[0..]);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 255, 255, 255, 255 }, packet.ipv4_header.destination_ip[0..]);
    try std.testing.expectEqualSlices(u8, ethernet.broadcast_mac[0..], packet.ethernet_destination[0..]);
    try std.testing.expectEqualSlices(u8, client_mac[0..], packet.ethernet_source[0..]);
    try std.testing.expectEqual(@as(u8, dhcp.boot_request), packet.op);
    try std.testing.expectEqual(@as(u32, 0x1234_5678), packet.transaction_id);
    try std.testing.expectEqual(@as(u16, dhcp.flags_broadcast), packet.flags);
    try std.testing.expectEqual(dhcp.message_type_discover, packet.message_type.?);
    try std.testing.expectEqualSlices(u8, client_mac[0..], packet.client_mac[0..]);
    try std.testing.expectEqualSlices(u8, parameter_request_list[0..], packet.parameter_request_list[0..packet.parameter_request_list_len]);
    try std.testing.expect(packet.max_message_size_valid);
    try std.testing.expectEqual(@as(u16, 1500), packet.max_message_size);
    try std.testing.expect(packet.udp_checksum_value != 0);
}

test "baremetal net pal configures route state from dhcp lease" {
    clearRouteStateForTest();
    defer clearRouteStateForTest();

    var packet: DhcpPacket = std.mem.zeroes(DhcpPacket);
    packet.your_ip = .{ 192, 168, 56, 10 };
    packet.subnet_mask_valid = true;
    packet.subnet_mask = .{ 255, 255, 255, 0 };
    packet.router_valid = true;
    packet.router = .{ 192, 168, 56, 1 };

    try configureIpv4RouteFromDhcp(&packet);

    const state = routeStatePtr().*;
    try std.testing.expect(state.configured);
    try std.testing.expect(state.subnet_mask_valid);
    try std.testing.expect(state.gateway_valid);
    try std.testing.expectEqualSlices(u8, packet.your_ip[0..], state.local_ip[0..]);
    try std.testing.expectEqualSlices(u8, packet.subnet_mask[0..], state.subnet_mask[0..]);
    try std.testing.expectEqualSlices(u8, packet.router[0..], state.gateway[0..]);
}

test "baremetal net pal routes off-subnet udp via learned gateway arp entry" {
    rtl8139.testEnableMockDevice();
    defer rtl8139.testDisableMockDevice();
    clearRouteStateForTest();
    defer clearRouteStateForTest();

    try std.testing.expect(initDevice());
    const local_ip = [4]u8{ 192, 168, 56, 10 };
    const remote_ip = [4]u8{ 1, 1, 1, 1 };
    const gateway_ip = [4]u8{ 192, 168, 56, 1 };
    const gateway_mac = [6]u8{ 0x02, 0xAA, 0xBB, 0xCC, 0xDD, 0x01 };
    const payload = "ROUTED-UDP";
    configureIpv4Route(local_ip, .{ 255, 255, 255, 0 }, gateway_ip);

    try std.testing.expectError(error.AddressUnresolved, sendUdpPacketRouted(remote_ip, 54000, 53, payload));
    const request_packet = (try pollArpPacket()).?;
    try std.testing.expectEqual(arp.operation_request, request_packet.operation);
    try std.testing.expectEqualSlices(u8, gateway_ip[0..], request_packet.target_ip[0..]);
    try std.testing.expectEqualSlices(u8, local_ip[0..], request_packet.sender_ip[0..]);
    try std.testing.expect(!learnArpPacket(request_packet));

    var reply_frame: [arp.frame_len]u8 = undefined;
    const reply_len = try arp.encodeReplyFrame(reply_frame[0..], gateway_mac, gateway_ip, macAddress(), local_ip);
    try sendFrame(reply_frame[0..reply_len]);
    const reply_packet = (try pollArpPacket()).?;
    try std.testing.expectEqual(arp.operation_reply, reply_packet.operation);
    try std.testing.expect(learnArpPacket(reply_packet));

    const expected_wire_len: u32 = ethernet.header_len + ipv4.header_len + udp.header_len + payload.len;
    try std.testing.expectEqual(expected_wire_len, try sendUdpPacketRouted(remote_ip, 54000, 53, payload));

    const packet = (try pollUdpPacketStrict()).?;
    try std.testing.expectEqualSlices(u8, gateway_mac[0..], packet.ethernet_destination[0..]);
    try std.testing.expectEqualSlices(u8, local_ip[0..], packet.ipv4_header.source_ip[0..]);
    try std.testing.expectEqualSlices(u8, remote_ip[0..], packet.ipv4_header.destination_ip[0..]);
    try std.testing.expectEqualSlices(u8, payload, packet.payload[0..packet.payload_len]);
    try std.testing.expect(routeStatePtr().last_used_gateway);
    try std.testing.expect(routeStatePtr().last_cache_hit);
    try std.testing.expect(!routeStatePtr().pending_resolution);
    try std.testing.expectEqual(@as(usize, 1), routeStatePtr().cache_entry_count);
}

test "baremetal net pal routes local-subnet udp directly after arp learning" {
    rtl8139.testEnableMockDevice();
    defer rtl8139.testDisableMockDevice();
    clearRouteStateForTest();
    defer clearRouteStateForTest();

    try std.testing.expect(initDevice());
    const local_ip = [4]u8{ 192, 168, 56, 10 };
    const peer_ip = [4]u8{ 192, 168, 56, 77 };
    const peer_mac = [6]u8{ 0x02, 0x10, 0x20, 0x30, 0x40, 0x50 };
    const gateway_ip = [4]u8{ 192, 168, 56, 1 };
    const payload = "DIRECT-UDP";
    configureIpv4Route(local_ip, .{ 255, 255, 255, 0 }, gateway_ip);

    var reply_frame: [arp.frame_len]u8 = undefined;
    const reply_len = try arp.encodeReplyFrame(reply_frame[0..], peer_mac, peer_ip, macAddress(), local_ip);
    try sendFrame(reply_frame[0..reply_len]);
    const reply_packet = (try pollArpPacket()).?;
    try std.testing.expect(learnArpPacket(reply_packet));

    const expected_wire_len: u32 = ethernet.header_len + ipv4.header_len + udp.header_len + payload.len;
    try std.testing.expectEqual(expected_wire_len, try sendUdpPacketRouted(peer_ip, 54001, 9001, payload));

    const packet = (try pollUdpPacketStrict()).?;
    try std.testing.expectEqualSlices(u8, peer_mac[0..], packet.ethernet_destination[0..]);
    try std.testing.expectEqualSlices(u8, local_ip[0..], packet.ipv4_header.source_ip[0..]);
    try std.testing.expectEqualSlices(u8, peer_ip[0..], packet.ipv4_header.destination_ip[0..]);
    try std.testing.expectEqualSlices(u8, payload, packet.payload[0..packet.payload_len]);
    try std.testing.expect(!routeStatePtr().last_used_gateway);
    try std.testing.expect(routeStatePtr().last_cache_hit);
}

test "baremetal net pal sends and parses dns query through rtl8139 mock device" {
    rtl8139.testEnableMockDevice();
    defer rtl8139.testDisableMockDevice();

    try std.testing.expect(initDevice());
    const source_ip = [4]u8{ 192, 168, 56, 10 };
    const destination_ip = [4]u8{ 192, 168, 56, 1 };
    const source_port: u16 = 53000;
    const query_name = "openclaw.local";

    _ = try sendDnsQuery(macAddress(), source_ip, destination_ip, source_port, 0x1234, query_name, dns.type_a);

    const packet = (try pollDnsPacket()).?;
    try std.testing.expectEqual(@as(u16, source_port), packet.source_port);
    try std.testing.expectEqual(@as(u16, dns.default_port), packet.destination_port);
    try std.testing.expectEqual(ipv4.protocol_udp, packet.ipv4_header.protocol);
    try std.testing.expectEqual(@as(u16, 0x1234), packet.id);
    try std.testing.expectEqual(dns.flags_standard_query, packet.flags);
    try std.testing.expectEqual(@as(u16, 1), packet.question_count);
    try std.testing.expectEqualStrings(query_name, packet.question_name[0..packet.question_name_len]);
    try std.testing.expectEqual(dns.type_a, packet.question_type);
    try std.testing.expectEqual(dns.class_in, packet.question_class);
    try std.testing.expectEqual(@as(usize, 0), packet.answer_count);
    try std.testing.expect(packet.udp_checksum_value != 0);
}

test "baremetal net pal sends and parses dns A response through rtl8139 mock device" {
    rtl8139.testEnableMockDevice();
    defer rtl8139.testDisableMockDevice();

    try std.testing.expect(initDevice());
    const server_ip = [4]u8{ 192, 168, 56, 1 };
    const client_ip = [4]u8{ 192, 168, 56, 10 };
    const client_port: u16 = 53000;
    const query_name = "openclaw.local";
    const address = [4]u8{ 192, 168, 56, 1 };

    var payload: [max_ipv4_payload_len]u8 = undefined;
    const payload_len = try dns.encodeAResponse(payload[0..], 0xBEEF, query_name, 300, address);
    _ = try sendUdpPacket(macAddress(), server_ip, client_ip, dns.default_port, client_port, payload[0..payload_len]);

    const packet = (try pollDnsPacket()).?;
    try std.testing.expectEqual(@as(u16, dns.default_port), packet.source_port);
    try std.testing.expectEqual(@as(u16, client_port), packet.destination_port);
    try std.testing.expectEqual(@as(u16, 0xBEEF), packet.id);
    try std.testing.expectEqual(dns.flags_standard_success_response, packet.flags);
    try std.testing.expectEqualStrings(query_name, packet.question_name[0..packet.question_name_len]);
    try std.testing.expectEqual(@as(u16, 1), packet.answer_count_total);
    try std.testing.expectEqual(@as(usize, 1), packet.answer_count);
    try std.testing.expectEqualStrings(query_name, packet.answers[0].nameSlice());
    try std.testing.expectEqual(dns.type_a, packet.answers[0].rr_type);
    try std.testing.expectEqual(dns.class_in, packet.answers[0].rr_class);
    try std.testing.expectEqual(@as(u32, 300), packet.answers[0].ttl);
    try std.testing.expectEqualSlices(u8, address[0..], packet.answers[0].dataSlice());
}

test "baremetal net pal strict dns poll reports non-dns udp frame" {
    rtl8139.testEnableMockDevice();
    defer rtl8139.testDisableMockDevice();

    try std.testing.expect(initDevice());
    const source_ip = [4]u8{ 192, 168, 56, 10 };
    const destination_ip = [4]u8{ 192, 168, 56, 1 };
    const payload = "OPENCLAW-UDP";

    _ = try sendUdpPacket(macAddress(), source_ip, destination_ip, 4321, 9001, payload);
    try std.testing.expectError(error.NotDns, pollDnsPacketStrict());
}

test "baremetal net pal strict dhcp poll reports non-dhcp udp frame" {
    rtl8139.testEnableMockDevice();
    defer rtl8139.testDisableMockDevice();

    try std.testing.expect(initDevice());
    const source_ip = [4]u8{ 192, 168, 56, 10 };
    const destination_ip = [4]u8{ 192, 168, 56, 1 };
    const payload = "OPENCLAW-UDP";

    _ = try sendUdpPacket(macAddress(), source_ip, destination_ip, 4321, 9001, payload);
    try std.testing.expectError(error.NotDhcp, pollDhcpPacketStrict());
}

test "baremetal net pal strict tcp poll reports non-tcp ipv4 frame" {
    rtl8139.testEnableMockDevice();
    defer rtl8139.testDisableMockDevice();

    try std.testing.expect(initDevice());
    const source_ip = [4]u8{ 192, 168, 56, 10 };
    const destination_ip = [4]u8{ 192, 168, 56, 1 };
    const payload = "OPENCLAW-UDP";

    _ = try sendUdpPacket(macAddress(), source_ip, destination_ip, 4321, 9001, payload);
    try std.testing.expectError(error.NotTcp, pollTcpPacketStrict());
}

const PostHarness = struct {
    client_ip: [4]u8 = .{ 192, 168, 56, 10 },
    server_ip: [4]u8 = .{ 192, 168, 56, 1 },
    dns_ip: [4]u8 = .{ 192, 168, 56, 53 },
    host_name: []const u8 = "post.openclaw.local",
    path: []const u8 = "/botdemo/sendMessage",
    expected_payload: []const u8 = "{\"text\":\"zig\"}",
    response_body: []const u8 = "{\"ok\":true}",
    server_port: u16 = 8080,
    client_port: u16 = 0,
    server: tcp.Session = tcp.Session.initServer(8080, 0, 0xA0B0_C0D0, 512),
    request_storage: [1024]u8 = [_]u8{0} ** 1024,
    request_len: usize = 0,
    response_storage: [512]u8 = [_]u8{0} ** 512,
    response_len: usize = 0,
    response_offset: usize = 0,
    response_started: bool = false,
    fin_sent: bool = false,

    fn handleOutgoingFrame(self: *PostHarness, frame: []const u8) !void {
        const eth = ethernet.Header.decode(frame) catch return;
        switch (eth.ether_type) {
            ethernet.ethertype_arp => {
                const packet = arp.decodeFrame(frame) catch return;
                if (packet.operation != arp.operation_request) return;
                if (std.mem.eql(u8, packet.target_ip[0..], self.server_ip[0..]) or
                    std.mem.eql(u8, packet.target_ip[0..], self.dns_ip[0..]))
                {
                    try self.injectArpReply(packet.target_ip, packet.sender_ip);
                }
            },
            ethernet.ethertype_ipv4 => {
                const ip_packet = ipv4.decode(frame[ethernet.header_len..]) catch return;
                switch (ip_packet.header.protocol) {
                    ipv4.protocol_udp => try self.handleUdp(ip_packet),
                    ipv4.protocol_tcp => try self.handleTcp(ip_packet),
                    else => {},
                }
            },
            else => {},
        }
    }

    fn handleUdp(self: *PostHarness, ip_packet: ipv4.Packet) !void {
        const packet = udp.decode(ip_packet.payload, ip_packet.header.source_ip, ip_packet.header.destination_ip) catch return;
        if (packet.destination_port != dns.default_port) return;
        if (!std.mem.eql(u8, ip_packet.header.destination_ip[0..], self.dns_ip[0..])) return;

        const query = dns.decode(packet.payload) catch return;
        if (!std.mem.eql(u8, query.question_name[0..query.question_name_len], self.host_name)) return;

        var response_payload: [max_ipv4_payload_len]u8 = undefined;
        const response_len = try dns.encodeAResponse(response_payload[0..], query.id, self.host_name, 60, self.server_ip);
        try self.injectUdp(self.dns_ip, self.client_ip, dns.default_port, packet.source_port, response_payload[0..response_len]);
    }

    fn handleTcp(self: *PostHarness, ip_packet: ipv4.Packet) !void {
        const packet = tcp.decode(ip_packet.payload, ip_packet.header.source_ip, ip_packet.header.destination_ip) catch return;
        if (!std.mem.eql(u8, ip_packet.header.destination_ip[0..], self.server_ip[0..])) return;
        if (packet.destination_port != self.server_port) return;

        if (packet.flags == tcp.flag_syn) {
            self.client_port = packet.source_port;
            self.server = tcp.Session.initServer(self.server_port, self.client_port, 0xA0B0_C0D0, 512);
            const syn_ack = try self.server.acceptSyn(packet);
            try self.injectTcp(self.server_ip, self.client_ip, syn_ack);
            return;
        }

        if (packet.flags == tcp.flag_ack and packet.payload.len == 0) {
            if (self.server.state == .syn_received) {
                try self.server.acceptAck(packet);
                return;
            }
            if (self.fin_sent) {
                try self.server.acceptAck(packet);
                return;
            }
            if (self.response_started) {
                try self.server.acceptAck(packet);
                if (self.response_offset < self.response_len) {
                    try self.sendNextResponseChunk();
                } else if (!self.fin_sent) {
                    const fin = try self.server.buildFin();
                    self.fin_sent = true;
                    try self.injectTcp(self.server_ip, self.client_ip, fin);
                }
            }
            return;
        }

        if (packet.flags == (tcp.flag_ack | tcp.flag_psh) and packet.payload.len != 0) {
            try self.server.acceptPayload(packet);
            if (self.request_len + packet.payload.len > self.request_storage.len) return error.ResponseTooLarge;
            std.mem.copyForwards(u8, self.request_storage[self.request_len .. self.request_len + packet.payload.len], packet.payload);
            self.request_len += packet.payload.len;

            if (self.requestComplete()) {
                try self.prepareResponse();
                try self.sendNextResponseChunk();
            } else {
                const ack = try self.server.buildAck();
                try self.injectTcp(self.server_ip, self.client_ip, ack);
            }
        }
    }

    fn requestComplete(self: *const PostHarness) bool {
        const request = self.request_storage[0..self.request_len];
        const header_end = std.mem.indexOf(u8, request, "\r\n\r\n") orelse return false;
        if (!std.mem.startsWith(u8, request, "POST ")) return false;
        if (std.mem.indexOf(u8, request[0..header_end], "Content-Length: ")) |index| {
            const line = request[index + "Content-Length: ".len .. header_end];
            const line_end = std.mem.indexOf(u8, line, "\r\n") orelse return false;
            const content_length = std.fmt.parseUnsigned(usize, std.mem.trim(u8, line[0..line_end], " "), 10) catch return false;
            return request.len >= header_end + 4 + content_length;
        }
        return false;
    }

    fn prepareResponse(self: *PostHarness) !void {
        if (self.response_len != 0) return;
        const request = self.request_storage[0..self.request_len];
        try std.testing.expect(std.mem.indexOf(u8, request, self.path) != null);
        try std.testing.expect(std.mem.indexOf(u8, request, "Host: post.openclaw.local:8080\r\n") != null);
        try std.testing.expect(std.mem.indexOf(u8, request, "content-type: application/json\r\n") != null or std.mem.indexOf(u8, request, "Content-Type: application/json\r\n") != null or std.mem.indexOf(u8, request, "content-type: application/json\r\n") != null or std.mem.indexOf(u8, request, "Content-type: application/json\r\n") != null);
        const body_offset = (std.mem.indexOf(u8, request, "\r\n\r\n") orelse return error.InvalidDataOffset) + 4;
        try std.testing.expectEqualStrings(self.expected_payload, request[body_offset..]);

        const response = try std.fmt.bufPrint(
            &self.response_storage,
            "HTTP/1.1 200 OK\r\nContent-Length: {d}\r\nConnection: close\r\nContent-Type: application/json\r\n\r\n{s}",
            .{ self.response_body.len, self.response_body },
        );
        self.response_len = response.len;
        self.response_offset = 0;
    }

    fn sendNextResponseChunk(self: *PostHarness) !void {
        if (self.response_offset >= self.response_len) return;
        const outbound = try self.server.buildPayloadChunk(self.response_storage[self.response_offset..self.response_len]);
        self.response_started = true;
        self.response_offset += outbound.payload.len;
        try self.injectTcp(self.server_ip, self.client_ip, outbound);
    }

    fn injectArpReply(self: *PostHarness, sender_ip: [4]u8, target_ip: [4]u8) !void {
        _ = self;
        var frame: [arp.frame_len]u8 = undefined;
        const local_mac = macAddress();
        const frame_len = try arp.encodeReplyFrame(frame[0..], local_mac, sender_ip, local_mac, target_ip);
        rtl8139.testInstallMockSendHook(null);
        defer rtl8139.testInstallMockSendHook(postHarnessHook);
        try sendFrame(frame[0..frame_len]);
    }

    fn injectUdp(self: *PostHarness, source_ip: [4]u8, destination_ip: [4]u8, source_port: u16, destination_port: u16, payload: []const u8) !void {
        _ = self;
        rtl8139.testInstallMockSendHook(null);
        defer rtl8139.testInstallMockSendHook(postHarnessHook);
        _ = try sendUdpPacket(macAddress(), source_ip, destination_ip, source_port, destination_port, payload);
    }

    fn injectTcp(self: *PostHarness, source_ip: [4]u8, destination_ip: [4]u8, outbound: tcp.Outbound) !void {
        rtl8139.testInstallMockSendHook(null);
        defer rtl8139.testInstallMockSendHook(postHarnessHook);
        _ = try sendTcpPacket(
            macAddress(),
            source_ip,
            destination_ip,
            self.server.local_port,
            self.server.remote_port,
            outbound.sequence_number,
            outbound.acknowledgment_number,
            outbound.flags,
            outbound.window_size,
            outbound.payload,
        );
    }
};

var post_harness_instance: ?*PostHarness = null;

fn postHarnessHook(frame: []const u8) void {
    if (post_harness_instance) |harness| {
        harness.handleOutgoingFrame(frame) catch @panic("post harness failure");
    }
}

test "baremetal net pal freestanding post rejects unsupported https scheme" {
    try std.testing.expectError(
        error.UnsupportedScheme,
        postFreestanding(std.testing.allocator, "https://api.telegram.org/bottest/sendMessage", "{}", &.{}),
    );
}

test "baremetal net pal freestanding post resolves dns and exchanges plain http through rtl8139 mock device" {
    rtl8139.testEnableMockDevice();
    defer rtl8139.testDisableMockDevice();
    clearRouteState();
    defer clearRouteState();

    try std.testing.expect(initDevice());
    configureIpv4Route(.{ 192, 168, 56, 10 }, .{ 255, 255, 255, 0 }, null);
    configureDnsServers(&.{.{ 192, 168, 56, 53 }});

    var harness = PostHarness{};
    post_harness_instance = &harness;
    rtl8139.testInstallMockSendHook(postHarnessHook);
    defer {
        rtl8139.testInstallMockSendHook(null);
        post_harness_instance = null;
    }

    var response = try postFreestanding(
        std.testing.allocator,
        "http://post.openclaw.local:8080/botdemo/sendMessage",
        harness.expected_payload,
        &.{.{ .name = "content-type", .value = "application/json" }},
    );
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u16, 200), response.status_code);
    try std.testing.expectEqualStrings(harness.response_body, response.body);
    try std.testing.expect(response.latency_ms >= 0);
}
