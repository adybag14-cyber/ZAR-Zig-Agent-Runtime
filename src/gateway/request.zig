// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const memory_store = @import("../memory/store.zig");
const response = @import("response.zig");

pub const HistoryParams = struct {
    scope: []u8,
    limit: usize,

    pub fn deinit(self: HistoryParams, allocator: std.mem.Allocator) void {
        allocator.free(self.scope);
    }
};

pub const SendMemoryEntry = struct {
    session_id: []u8,
    channel: []u8,
    message: []u8,

    pub fn deinit(self: SendMemoryEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.session_id);
        allocator.free(self.channel);
        allocator.free(self.message);
    }
};

pub const SessionSummary = struct {
    sessionId: []const u8,
    channel: []const u8,
    lastSeenAtMs: i64,
    authenticated: bool,
};

pub const UsageBucket = struct {
    bucketMs: i64,
    messages: usize,
};

pub fn parseHistoryParams(allocator: std.mem.Allocator, frame_json: []const u8) !HistoryParams {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, frame_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidParamsFrame;
    const params = parsed.value.object.get("params") orelse return HistoryParams{
        .scope = try allocator.dupe(u8, ""),
        .limit = 50,
    };
    if (params != .object) return HistoryParams{
        .scope = try allocator.dupe(u8, ""),
        .limit = 50,
    };

    var scope: []const u8 = "";
    if (params.object.get("sessionId")) |value| {
        if (value == .string) scope = std.mem.trim(u8, value.string, " \t\r\n");
    }
    if (scope.len == 0) {
        if (params.object.get("channel")) |value| {
            if (value == .string) scope = std.mem.trim(u8, value.string, " \t\r\n");
        }
    }

    var limit: usize = 50;
    if (params.object.get("limit")) |value| {
        limit = switch (value) {
            .integer => |raw| if (raw > 0) @as(usize, @intCast(raw)) else 50,
            .float => |raw| if (raw > 0) @as(usize, @intFromFloat(raw)) else 50,
            .string => |raw| blk: {
                const trimmed = std.mem.trim(u8, raw, " \t\r\n");
                if (trimmed.len == 0) break :blk 50;
                break :blk std.fmt.parseInt(usize, trimmed, 10) catch 50;
            },
            else => 50,
        };
    }
    return .{
        .scope = try allocator.dupe(u8, scope),
        .limit = std.math.clamp(limit, 1, 500),
    };
}

pub fn normalizeSendFrameChannelForDispatch(
    allocator: std.mem.Allocator,
    frame_json: []const u8,
    compat: anytype,
    memory: *memory_store.Store,
) ![]u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, frame_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return allocator.dupe(u8, frame_json);

    const params_value = parsed.value.object.getPtr("params") orelse return allocator.dupe(u8, frame_json);
    if (params_value.* != .object) return allocator.dupe(u8, frame_json);
    const params = &params_value.object;

    var explicit_channel: []const u8 = "";
    if (params.get("channel")) |value| {
        if (value == .string) explicit_channel = std.mem.trim(u8, value.string, " \t\r\n");
    }
    if (explicit_channel.len > 0) return allocator.dupe(u8, frame_json);

    const session_id = resolveSessionId(params.*);
    var resolved_channel: []const u8 = "";
    if (session_id.len > 0) {
        if (compat.getSessionChannel(session_id)) |session_state| {
            resolved_channel = std.mem.trim(u8, session_state.channel, " \t\r\n");
        }
        if (resolved_channel.len == 0) {
            if (try findSessionSummary(allocator, memory, compat, session_id)) |summary| {
                resolved_channel = std.mem.trim(u8, summary.channel, " \t\r\n");
            }
        }
    }
    if (resolved_channel.len == 0) resolved_channel = "webchat";

    try params.put("channel", .{ .string = resolved_channel });
    return response.stringifyJsonValue(allocator, parsed.value);
}

pub fn parseSendMemoryFromFrame(allocator: std.mem.Allocator, frame_json: []const u8) !?SendMemoryEntry {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, frame_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return null;
    const params = parsed.value.object.get("params") orelse return null;
    if (params != .object) return null;

    const message_value = params.object.get("message") orelse params.object.get("text") orelse return null;
    if (message_value != .string) return null;
    const message = std.mem.trim(u8, message_value.string, " \t\r\n");
    if (message.len == 0) return null;

    var session_id: []const u8 = "tg-chat-default";
    if (params.object.get("sessionId")) |value| {
        if (value == .string and std.mem.trim(u8, value.string, " \t\r\n").len > 0) {
            session_id = std.mem.trim(u8, value.string, " \t\r\n");
        }
    }
    var channel: []const u8 = "webchat";
    if (params.object.get("channel")) |value| {
        if (value == .string and std.mem.trim(u8, value.string, " \t\r\n").len > 0) {
            channel = std.mem.trim(u8, value.string, " \t\r\n");
        }
    }
    channel = normalizeSendMemoryChannel(channel);

    return SendMemoryEntry{
        .session_id = try allocator.dupe(u8, session_id),
        .channel = try allocator.dupe(u8, channel),
        .message = try allocator.dupe(u8, message),
    };
}

pub fn normalizeSendMemoryChannel(raw: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len == 0) return "telegram";
    if (std.ascii.eqlIgnoreCase(trimmed, "telegram") or std.ascii.eqlIgnoreCase(trimmed, "tg") or std.ascii.eqlIgnoreCase(trimmed, "tele")) return "telegram";
    if (std.ascii.eqlIgnoreCase(trimmed, "webchat") or std.ascii.eqlIgnoreCase(trimmed, "web")) return "webchat";
    if (std.ascii.eqlIgnoreCase(trimmed, "cli") or std.ascii.eqlIgnoreCase(trimmed, "console") or std.ascii.eqlIgnoreCase(trimmed, "terminal")) return "cli";
    return trimmed;
}

pub fn mergeConfigFromParams(
    allocator: std.mem.Allocator,
    compat: anytype,
    params: ?std.json.ObjectMap,
) !void {
    const object = if (params) |obj|
        if (obj.get("config")) |cfg|
            if (cfg == .object) cfg.object else obj
        else
            obj
    else
        return;

    var it = object.iterator();
    while (it.next()) |entry| {
        const key = std.mem.trim(u8, entry.key_ptr.*, " \t\r\n");
        if (key.len == 0) continue;
        if (std.ascii.eqlIgnoreCase(key, "sessionId") or std.ascii.eqlIgnoreCase(key, "id")) continue;

        const rendered = switch (entry.value_ptr.*) {
            .string => |raw| try allocator.dupe(u8, std.mem.trim(u8, raw, " \t\r\n")),
            else => try response.stringifyJsonValue(allocator, entry.value_ptr.*),
        };
        defer allocator.free(rendered);
        try compat.mergeConfigEntry(key, rendered);
    }
}

pub fn resolveSessionId(params: ?std.json.ObjectMap) []const u8 {
    const from_session = firstParamString(params, "sessionId", "");
    if (from_session.len > 0) return from_session;
    return firstParamString(params, "id", "");
}

pub fn countWords(text: []const u8) usize {
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    if (trimmed.len == 0) return 0;
    var count: usize = 0;
    var iter = std.mem.tokenizeAny(u8, trimmed, " \t\r\n");
    while (iter.next() != null) count += 1;
    return count;
}

pub fn collectSessionSummaries(
    allocator: std.mem.Allocator,
    memory: *memory_store.Store,
    compat: anytype,
    limit: usize,
) ![]SessionSummary {
    const stats = memory.stats();
    var history = try memory.historyBySession(allocator, "", stats.maxEntries);
    defer history.deinit(allocator);

    var summary_map = std.StringHashMap(SessionSummary).init(allocator);
    defer summary_map.deinit();

    for (history.items) |entry| {
        const sid = std.mem.trim(u8, entry.sessionId, " \t\r\n");
        if (sid.len == 0) continue;
        if (compat.isSessionDeleted(sid)) continue;
        if (summary_map.getPtr(sid)) |existing| {
            if (entry.createdAtMs > existing.lastSeenAtMs) {
                existing.lastSeenAtMs = entry.createdAtMs;
                if (entry.channel.len > 0) existing.channel = entry.channel;
            }
            continue;
        }
        try summary_map.put(sid, .{
            .sessionId = sid,
            .channel = entry.channel,
            .lastSeenAtMs = entry.createdAtMs,
            .authenticated = true,
        });
    }

    var session_it = compat.session_channels.iterator();
    while (session_it.next()) |entry| {
        const sid = std.mem.trim(u8, entry.key_ptr.*, " \t\r\n");
        if (sid.len == 0) continue;
        if (compat.isSessionDeleted(sid)) continue;
        if (summary_map.get(sid) != null) continue;
        try summary_map.put(sid, .{
            .sessionId = sid,
            .channel = entry.value_ptr.channel,
            .lastSeenAtMs = entry.value_ptr.updated_at_ms,
            .authenticated = true,
        });
    }

    var tmp: std.ArrayList(SessionSummary) = .empty;
    defer tmp.deinit(allocator);
    var it = summary_map.iterator();
    while (it.next()) |entry| try tmp.append(allocator, entry.value_ptr.*);

    var items = try tmp.toOwnedSlice(allocator);
    sortSessionSummariesByLastSeenDesc(items);
    if (limit > 0 and items.len > limit) {
        const trimmed = try allocator.alloc(SessionSummary, limit);
        @memcpy(trimmed, items[0..limit]);
        allocator.free(items);
        items = trimmed;
    }
    return items;
}

pub fn findSessionSummary(
    allocator: std.mem.Allocator,
    memory: *memory_store.Store,
    compat: anytype,
    session_id: []const u8,
) !?SessionSummary {
    const needle = std.mem.trim(u8, session_id, " \t\r\n");
    if (needle.len == 0) return null;
    if (compat.isSessionDeleted(needle)) return null;

    const stats = memory.stats();
    var history = try memory.historyBySession(allocator, needle, stats.maxEntries);
    defer history.deinit(allocator);
    if (history.count == 0) {
        if (compat.getSessionChannel(needle)) |state| {
            return SessionSummary{
                .sessionId = needle,
                .channel = state.channel,
                .lastSeenAtMs = state.updated_at_ms,
                .authenticated = true,
            };
        }
        return null;
    }
    const latest = history.items[history.count - 1];
    return SessionSummary{
        .sessionId = needle,
        .channel = if (latest.channel.len > 0) latest.channel else if (compat.getSessionChannel(needle)) |state| state.channel else latest.channel,
        .lastSeenAtMs = latest.createdAtMs,
        .authenticated = true,
    };
}

pub fn collectUsageTimeseries(
    allocator: std.mem.Allocator,
    items: []memory_store.MessageView,
) ![]UsageBucket {
    var buckets = std.AutoHashMap(i64, usize).init(allocator);
    defer buckets.deinit();

    for (items) |entry| {
        const bucket_ms: i64 = @divTrunc(entry.createdAtMs, @as(i64, 3_600_000)) * @as(i64, 3_600_000);
        const current = buckets.get(bucket_ms) orelse 0;
        try buckets.put(bucket_ms, current + 1);
    }

    var out: std.ArrayList(UsageBucket) = .empty;
    defer out.deinit(allocator);
    var it = buckets.iterator();
    while (it.next()) |entry| {
        try out.append(allocator, .{
            .bucketMs = entry.key_ptr.*,
            .messages = entry.value_ptr.*,
        });
    }
    const owned = try out.toOwnedSlice(allocator);
    sortUsageBucketsAsc(owned);
    return owned;
}

fn sortSessionSummariesByLastSeenDesc(items: []SessionSummary) void {
    var i: usize = 0;
    while (i < items.len) : (i += 1) {
        var j: usize = i + 1;
        while (j < items.len) : (j += 1) {
            if (items[j].lastSeenAtMs > items[i].lastSeenAtMs) {
                const tmp = items[i];
                items[i] = items[j];
                items[j] = tmp;
            }
        }
    }
}

fn sortUsageBucketsAsc(items: []UsageBucket) void {
    var i: usize = 0;
    while (i < items.len) : (i += 1) {
        var j: usize = i + 1;
        while (j < items.len) : (j += 1) {
            if (items[j].bucketMs < items[i].bucketMs) {
                const tmp = items[i];
                items[i] = items[j];
                items[j] = tmp;
            }
        }
    }
}

pub fn getParamsObjectOrNull(frame: std.json.Value) ?std.json.ObjectMap {
    if (frame != .object) return null;
    const params = frame.object.get("params") orelse return null;
    if (params != .object) return null;
    return params.object;
}

pub fn firstParamString(params: ?std.json.ObjectMap, key: []const u8, fallback: []const u8) []const u8 {
    if (params) |obj| {
        if (obj.get(key)) |value| {
            if (value == .string) {
                const trimmed = std.mem.trim(u8, value.string, " \t\r\n");
                if (trimmed.len > 0) return trimmed;
            }
        }
    }
    return fallback;
}

pub fn firstParamInt(params: ?std.json.ObjectMap, key: []const u8, fallback: i64) i64 {
    if (params) |obj| {
        if (obj.get(key)) |value| {
            return switch (value) {
                .integer => |raw| raw,
                .float => |raw| @as(i64, @intFromFloat(raw)),
                .string => |raw| blk: {
                    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
                    if (trimmed.len == 0) break :blk fallback;
                    break :blk std.fmt.parseInt(i64, trimmed, 10) catch fallback;
                },
                else => fallback,
            };
        }
    }
    return fallback;
}

pub fn firstParamFloat(params: ?std.json.ObjectMap, key: []const u8, fallback: f64) f64 {
    if (params) |obj| {
        if (obj.get(key)) |value| {
            return switch (value) {
                .integer => |raw| @as(f64, @floatFromInt(raw)),
                .float => |raw| raw,
                .string => |raw| blk: {
                    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
                    if (trimmed.len == 0) break :blk fallback;
                    break :blk std.fmt.parseFloat(f64, trimmed) catch fallback;
                },
                else => fallback,
            };
        }
    }
    return fallback;
}

pub fn firstParamBool(params: ?std.json.ObjectMap, key: []const u8, fallback: bool) bool {
    if (params) |obj| {
        if (obj.get(key)) |value| {
            return switch (value) {
                .bool => |raw| raw,
                .integer => |raw| raw != 0,
                .string => |raw| blk: {
                    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
                    if (trimmed.len == 0) break :blk fallback;
                    if (std.ascii.eqlIgnoreCase(trimmed, "true") or std.ascii.eqlIgnoreCase(trimmed, "yes") or std.mem.eql(u8, trimmed, "1") or std.ascii.eqlIgnoreCase(trimmed, "on")) break :blk true;
                    if (std.ascii.eqlIgnoreCase(trimmed, "false") or std.ascii.eqlIgnoreCase(trimmed, "no") or std.mem.eql(u8, trimmed, "0") or std.ascii.eqlIgnoreCase(trimmed, "off")) break :blk false;
                    break :blk fallback;
                },
                else => fallback,
            };
        }
    }
    return fallback;
}
