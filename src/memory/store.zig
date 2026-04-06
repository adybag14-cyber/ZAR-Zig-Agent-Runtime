// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const time_util = @import("../util/time.zig");

pub const MessageView = struct {
    id: []const u8,
    sessionId: []const u8,
    channel: []const u8,
    method: []const u8,
    role: []const u8,
    text: []const u8,
    createdAtMs: i64,
};

pub const HistoryResult = struct {
    count: usize,
    items: []MessageView,

    pub fn deinit(self: *HistoryResult, allocator: std.mem.Allocator) void {
        allocator.free(self.items);
    }
};

pub const GraphEdge = struct {
    from: []u8,
    to: []u8,
    weight: u32,
};

pub const GraphNeighborsResult = struct {
    count: usize,
    items: []GraphEdge,

    pub fn deinit(self: *GraphNeighborsResult, allocator: std.mem.Allocator) void {
        for (self.items) |*entry| {
            allocator.free(entry.from);
            allocator.free(entry.to);
        }
        allocator.free(self.items);
    }
};

pub const RecallSynthesis = struct {
    query: []u8,
    semantic: HistoryResult,
    neighbors: GraphNeighborsResult,
    countSemantic: usize,
    countNeighbors: usize,

    pub fn deinit(self: *RecallSynthesis, allocator: std.mem.Allocator) void {
        allocator.free(self.query);
        self.semantic.deinit(allocator);
        self.neighbors.deinit(allocator);
    }
};

pub const StatsView = struct {
    entries: usize,
    vectors: usize,
    graphNodes: usize,
    graphEdges: usize,
    maxEntries: usize,
    unlimited: bool,
    persistent: bool,
    statePath: []const u8,
    lastError: []const u8,
};

const MessageEntry = struct {
    id: []u8,
    session_id: []u8,
    channel: []u8,
    method: []u8,
    role: []u8,
    text: []u8,
    created_at_ms: i64,

    fn deinit(self: *MessageEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.session_id);
        allocator.free(self.channel);
        allocator.free(self.method);
        allocator.free(self.role);
        allocator.free(self.text);
    }

    fn view(self: *const MessageEntry) MessageView {
        return .{
            .id = self.id,
            .sessionId = self.session_id,
            .channel = self.channel,
            .method = self.method,
            .role = self.role,
            .text = self.text,
            .createdAtMs = self.created_at_ms,
        };
    }
};

const PersistedEntry = struct {
    id: []const u8,
    sessionId: []const u8,
    channel: []const u8,
    method: []const u8,
    role: []const u8,
    text: []const u8,
    createdAtMs: i64,
};

const PersistedState = struct {
    nextId: u64 = 1,
    entries: []PersistedEntry = &.{},
};

const ScoredEntry = struct {
    index: usize,
    score: f64,
};

const NeighborTemp = struct {
    to: []const u8,
    weight: u32,
};

const EdgePair = struct {
    from: []const u8,
    to: []const u8,
};

const GraphStats = struct {
    nodes: usize,
    edges: usize,
};

const TokenVector = std.AutoHashMap(u64, f64);
const token_trim_chars = ".,!?;:\"'()[]{}<>";

pub const Store = struct {
    allocator: std.mem.Allocator,
    state_path: []u8,
    persistent: bool,
    max_entries: usize,
    unlimited: bool,
    next_id: u64,
    entries: std.ArrayList(MessageEntry),
    last_error: ?[]u8,

    pub fn init(allocator: std.mem.Allocator, state_root: []const u8, max_entries: usize) !Store {
        const resolved = try resolveStatePath(allocator, state_root);
        const unlimited = max_entries == 0;
        var out = Store{
            .allocator = allocator,
            .state_path = resolved,
            .persistent = shouldPersist(resolved),
            .max_entries = if (unlimited) 0 else max_entries,
            .unlimited = unlimited,
            .next_id = 1,
            .entries = .empty,
            .last_error = null,
        };
        if (out.persistent) {
            out.load() catch |err| {
                out.setLastError(err);
            };
        }
        return out;
    }

    pub fn deinit(self: *Store) void {
        for (self.entries.items) |*entry| entry.deinit(self.allocator);
        self.entries.deinit(self.allocator);
        self.allocator.free(self.state_path);
        self.clearLastError();
    }

    pub fn append(
        self: *Store,
        session_id: []const u8,
        channel: []const u8,
        method: []const u8,
        role: []const u8,
        text: []const u8,
    ) !void {
        const id = try std.fmt.allocPrint(self.allocator, "msg-{d}", .{self.next_id});
        self.next_id += 1;
        try self.entries.append(self.allocator, .{
            .id = id,
            .session_id = try self.allocator.dupe(u8, std.mem.trim(u8, session_id, " \t\r\n")),
            .channel = try self.allocator.dupe(u8, std.mem.trim(u8, channel, " \t\r\n")),
            .method = try self.allocator.dupe(u8, std.mem.trim(u8, method, " \t\r\n")),
            .role = try self.allocator.dupe(u8, std.mem.trim(u8, role, " \t\r\n")),
            .text = try self.allocator.dupe(u8, std.mem.trim(u8, text, " \t\r\n")),
            .created_at_ms = nowMs(),
        });

        if (!self.unlimited and self.max_entries > 0 and self.entries.items.len > self.max_entries) {
            _ = self.removeFrontEntries(self.entries.items.len - self.max_entries);
        }
        if (self.persistent) try self.persist();
    }

    pub fn historyBySession(self: *Store, allocator: std.mem.Allocator, session_id: []const u8, limit: usize) !HistoryResult {
        return self.historyByKey(allocator, "session", session_id, limit);
    }

    pub fn historyByChannel(self: *Store, allocator: std.mem.Allocator, channel: []const u8, limit: usize) !HistoryResult {
        return self.historyByKey(allocator, "channel", channel, limit);
    }

    pub fn semanticRecall(self: *Store, allocator: std.mem.Allocator, query: []const u8, limit: usize) !HistoryResult {
        const resolved_limit = if (limit == 0) 5 else limit;
        var query_vector = try embedText(allocator, query);
        defer query_vector.deinit();
        if (query_vector.count() == 0) {
            return .{
                .count = 0,
                .items = try allocator.alloc(MessageView, 0),
            };
        }

        var scored: std.ArrayList(ScoredEntry) = .empty;
        defer scored.deinit(allocator);

        for (self.entries.items, 0..) |entry, idx| {
            var entry_vector = try embedText(allocator, entry.text);
            defer entry_vector.deinit();
            if (entry_vector.count() == 0) continue;
            const score = cosineSimilarity(&query_vector, &entry_vector);
            if (score <= 0) continue;
            try scored.append(allocator, .{
                .index = idx,
                .score = score,
            });
        }

        if (scored.items.len == 0) {
            return .{
                .count = 0,
                .items = try allocator.alloc(MessageView, 0),
            };
        }

        sortScoredDescending(scored.items, self.entries.items);
        const keep = @min(resolved_limit, scored.items.len);
        var items = try allocator.alloc(MessageView, keep);
        for (0..keep) |idx| {
            items[idx] = self.entries.items[scored.items[idx].index].view();
        }
        return .{
            .count = keep,
            .items = items,
        };
    }

    pub fn graphNeighbors(self: *Store, allocator: std.mem.Allocator, node: []const u8, limit: usize) !GraphNeighborsResult {
        const resolved_limit = if (limit == 0) 10 else limit;
        const target_node = (try nodeKeyAlloc(allocator, "", node)) orelse {
            return .{
                .count = 0,
                .items = try allocator.alloc(GraphEdge, 0),
            };
        };
        defer allocator.free(target_node);

        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        var edges: std.ArrayList(EdgePair) = .empty;
        defer edges.deinit(arena_allocator);
        for (self.entries.items) |entry| {
            try emitGraphEdgesForEntry(arena_allocator, &edges, &entry);
        }

        var weights = std.StringHashMap(u32).init(arena_allocator);
        for (edges.items) |edge| {
            if (!std.mem.eql(u8, edge.from, target_node)) continue;
            const op = try weights.getOrPut(edge.to);
            if (op.found_existing) {
                op.value_ptr.* += 1;
            } else {
                op.value_ptr.* = 1;
            }
        }

        if (weights.count() == 0) {
            return .{
                .count = 0,
                .items = try allocator.alloc(GraphEdge, 0),
            };
        }

        var temp = try allocator.alloc(NeighborTemp, weights.count());
        defer allocator.free(temp);
        var idx: usize = 0;
        var it = weights.iterator();
        while (it.next()) |entry| : (idx += 1) {
            temp[idx] = .{
                .to = entry.key_ptr.*,
                .weight = entry.value_ptr.*,
            };
        }
        sortNeighborWeights(temp);

        const keep = @min(resolved_limit, temp.len);
        var items = try allocator.alloc(GraphEdge, keep);
        errdefer {
            for (items) |*edge| {
                allocator.free(edge.from);
                allocator.free(edge.to);
            }
            allocator.free(items);
        }
        for (0..keep) |edge_idx| {
            items[edge_idx] = .{
                .from = try allocator.dupe(u8, target_node),
                .to = try allocator.dupe(u8, temp[edge_idx].to),
                .weight = temp[edge_idx].weight,
            };
        }

        return .{
            .count = keep,
            .items = items,
        };
    }

    pub fn recallSynthesis(self: *Store, allocator: std.mem.Allocator, query: []const u8, limit: usize) !RecallSynthesis {
        const trimmed_query = std.mem.trim(u8, query, " \t\r\n");
        var semantic = try self.semanticRecall(allocator, trimmed_query, limit);
        errdefer semantic.deinit(allocator);

        var neighbors = GraphNeighborsResult{
            .count = 0,
            .items = try allocator.alloc(GraphEdge, 0),
        };
        errdefer neighbors.deinit(allocator);

        if (try firstSignificantTermAlloc(allocator, trimmed_query)) |term| {
            defer allocator.free(term);
            const node = try std.fmt.allocPrint(allocator, "term:{s}", .{term});
            defer allocator.free(node);
            neighbors.deinit(allocator);
            neighbors = try self.graphNeighbors(allocator, node, limit);
        }

        return .{
            .query = try allocator.dupe(u8, trimmed_query),
            .semantic = semantic,
            .neighbors = neighbors,
            .countSemantic = semantic.count,
            .countNeighbors = neighbors.count,
        };
    }

    pub fn stats(self: *Store) StatsView {
        const graph_stats = self.computeGraphStats();
        return .{
            .entries = self.entries.items.len,
            .vectors = self.computeVectorCount(),
            .graphNodes = graph_stats.nodes,
            .graphEdges = graph_stats.edges,
            .maxEntries = if (self.unlimited) 0 else self.max_entries,
            .unlimited = self.unlimited,
            .persistent = self.persistent,
            .statePath = self.state_path,
            .lastError = if (self.last_error) |value| value else "",
        };
    }

    pub fn count(self: *const Store) usize {
        return self.entries.items.len;
    }

    pub fn removeSession(self: *Store, session_id: []const u8) !usize {
        const needle = std.mem.trim(u8, session_id, " \t\r\n");
        if (needle.len == 0) return 0;

        var removed: usize = 0;
        var write_idx: usize = 0;
        var read_idx: usize = 0;
        while (read_idx < self.entries.items.len) : (read_idx += 1) {
            if (std.mem.eql(u8, self.entries.items[read_idx].session_id, needle)) {
                var entry = self.entries.items[read_idx];
                entry.deinit(self.allocator);
                removed += 1;
            } else {
                if (write_idx != read_idx) {
                    self.entries.items[write_idx] = self.entries.items[read_idx];
                }
                write_idx += 1;
            }
        }
        self.entries.items.len = write_idx;

        if (removed > 0 and self.persistent) try self.persist();
        return removed;
    }

    pub fn trim(self: *Store, limit: usize) !usize {
        if (self.entries.items.len <= limit) return 0;
        const removed = self.removeFrontEntries(self.entries.items.len - limit);
        if (removed > 0 and self.persistent) try self.persist();
        return removed;
    }

    fn removeFrontEntries(self: *Store, remove_count: usize) usize {
        if (remove_count == 0 or self.entries.items.len == 0) return 0;
        const to_remove = @min(remove_count, self.entries.items.len);
        for (self.entries.items[0..to_remove]) |*entry| entry.deinit(self.allocator);
        const remain = self.entries.items.len - to_remove;
        if (remain > 0) {
            std.mem.copyForwards(MessageEntry, self.entries.items[0..remain], self.entries.items[to_remove..]);
        }
        self.entries.items.len = remain;
        return to_remove;
    }

    fn historyByKey(self: *Store, allocator: std.mem.Allocator, key: []const u8, value: []const u8, limit: usize) !HistoryResult {
        const cap = if (limit == 0) 50 else limit;
        const max_matches = @min(cap, self.entries.items.len);
        var views = try allocator.alloc(MessageView, max_matches);
        var matched: usize = 0;
        const needle = std.mem.trim(u8, value, " \t\r\n");
        var index = self.entries.items.len;
        while (index > 0 and matched < views.len) : (index -= 1) {
            const entry = self.entries.items[index - 1];
            if (needle.len > 0) {
                if (std.ascii.eqlIgnoreCase(key, "session") and !std.mem.eql(u8, entry.session_id, needle)) continue;
                if (std.ascii.eqlIgnoreCase(key, "channel") and !std.ascii.eqlIgnoreCase(entry.channel, needle)) continue;
            }
            views[matched] = entry.view();
            matched += 1;
        }
        std.mem.reverse(MessageView, views[0..matched]);
        const result_items = try allocator.alloc(MessageView, matched);
        @memcpy(result_items, views[0..matched]);
        allocator.free(views);
        return .{
            .count = matched,
            .items = result_items,
        };
    }

    fn load(self: *Store) !void {
        const io = std.Io.Threaded.global_single_threaded.io();
        const raw = std.Io.Dir.cwd().readFileAlloc(io, self.state_path, self.allocator, .limited(8 * 1024 * 1024)) catch |err| switch (err) {
            error.FileNotFound => return,
            else => {
                self.setLastError(err);
                return err;
            },
        };
        defer self.allocator.free(raw);

        var parsed = std.json.parseFromSlice(PersistedState, self.allocator, raw, .{ .ignore_unknown_fields = true }) catch |err| {
            self.setLastError(err);
            return err;
        };
        defer parsed.deinit();
        var max_loaded_id: u64 = 0;
        for (parsed.value.entries) |entry| {
            try self.entries.append(self.allocator, .{
                .id = try self.allocator.dupe(u8, entry.id),
                .session_id = try self.allocator.dupe(u8, entry.sessionId),
                .channel = try self.allocator.dupe(u8, entry.channel),
                .method = try self.allocator.dupe(u8, entry.method),
                .role = try self.allocator.dupe(u8, entry.role),
                .text = try self.allocator.dupe(u8, entry.text),
                .created_at_ms = entry.createdAtMs,
            });
            const parsed_id = parseMessageNumericSuffix(entry.id);
            if (parsed_id > max_loaded_id) max_loaded_id = parsed_id;
        }
        if (!self.unlimited and self.max_entries > 0 and self.entries.items.len > self.max_entries) {
            _ = self.removeFrontEntries(self.entries.items.len - self.max_entries);
        }
        if (max_loaded_id >= self.next_id) self.next_id = max_loaded_id +| 1;
        if (parsed.value.nextId > self.next_id) self.next_id = parsed.value.nextId;
        if (self.next_id == 0) self.next_id = 1;
        self.clearLastError();
    }

    fn persist(self: *Store) !void {
        const io = std.Io.Threaded.global_single_threaded.io();
        if (std.fs.path.dirname(self.state_path)) |parent| {
            if (parent.len > 0) {
                std.Io.Dir.cwd().createDirPath(io, parent) catch |err| {
                    self.setLastError(err);
                    return err;
                };
            }
        }

        var out_entries = try self.allocator.alloc(PersistedEntry, self.entries.items.len);
        defer self.allocator.free(out_entries);
        for (self.entries.items, 0..) |entry, idx| {
            out_entries[idx] = .{
                .id = entry.id,
                .sessionId = entry.session_id,
                .channel = entry.channel,
                .method = entry.method,
                .role = entry.role,
                .text = entry.text,
                .createdAtMs = entry.created_at_ms,
            };
        }

        var out: std.Io.Writer.Allocating = .init(self.allocator);
        defer out.deinit();
        std.json.Stringify.value(.{
            .nextId = self.next_id,
            .entries = out_entries,
        }, .{}, &out.writer) catch |err| {
            self.setLastError(err);
            return err;
        };
        const payload = try out.toOwnedSlice();
        defer self.allocator.free(payload);

        std.Io.Dir.cwd().writeFile(io, .{
            .sub_path = self.state_path,
            .data = payload,
        }) catch |err| {
            self.setLastError(err);
            return err;
        };
        self.clearLastError();
    }

    fn computeVectorCount(self: *Store) usize {
        var vectors: usize = 0;
        for (self.entries.items) |entry| {
            if (textHasEmbeddingTokens(entry.text)) vectors += 1;
        }
        return vectors;
    }

    fn computeGraphStats(self: *Store) GraphStats {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        var all_edges: std.ArrayList(EdgePair) = .empty;
        defer all_edges.deinit(arena_allocator);
        for (self.entries.items) |entry| {
            emitGraphEdgesForEntry(arena_allocator, &all_edges, &entry) catch {
                return .{
                    .nodes = self.entries.items.len,
                    .edges = self.entries.items.len * 2,
                };
            };
        }

        var nodes = std.StringHashMap(void).init(arena_allocator);
        var edges = std.StringHashMap(void).init(arena_allocator);
        for (all_edges.items) |edge| {
            _ = nodes.getOrPut(edge.from) catch continue;
            _ = nodes.getOrPut(edge.to) catch continue;
            const edge_key = std.fmt.allocPrint(arena_allocator, "{s}|{s}", .{ edge.from, edge.to }) catch continue;
            _ = edges.getOrPut(edge_key) catch continue;
        }

        return .{
            .nodes = nodes.count(),
            .edges = edges.count(),
        };
    }

    fn setLastError(self: *Store, err: anytype) void {
        self.clearLastError();
        self.last_error = std.fmt.allocPrint(self.allocator, "{s}", .{@errorName(err)}) catch null;
    }

    fn clearLastError(self: *Store) void {
        if (self.last_error) |value| {
            self.allocator.free(value);
            self.last_error = null;
        }
    }
};

fn resolveStatePath(allocator: std.mem.Allocator, state_root: []const u8) ![]u8 {
    const trimmed = std.mem.trim(u8, state_root, " \t\r\n");
    if (trimmed.len == 0) return allocator.dupe(u8, "memory://openclaw-zig");
    if (isMemoryScheme(trimmed)) return allocator.dupe(u8, trimmed);
    if (std.mem.endsWith(u8, trimmed, ".json")) return allocator.dupe(u8, trimmed);
    return std.fs.path.join(allocator, &.{ trimmed, "memory.json" });
}

fn shouldPersist(path: []const u8) bool {
    return !isMemoryScheme(path);
}

fn isMemoryScheme(path: []const u8) bool {
    const prefix = "memory://";
    if (path.len < prefix.len) return false;
    return std.ascii.eqlIgnoreCase(path[0..prefix.len], prefix);
}

fn nowMs() i64 {
    return time_util.nowMs();
}

fn parseMessageNumericSuffix(id_raw: []const u8) u64 {
    const id = std.mem.trim(u8, id_raw, " \t\r\n");
    if (id.len <= 4) return 0;
    if (!std.ascii.startsWithIgnoreCase(id, "msg-")) return 0;
    const digits = id[4..];
    if (digits.len == 0) return 0;
    return std.fmt.parseInt(u64, digits, 10) catch 0;
}

fn sortScoredDescending(items: []ScoredEntry, entries: []const MessageEntry) void {
    if (items.len < 2) return;
    var idx: usize = 1;
    while (idx < items.len) : (idx += 1) {
        var walk = idx;
        while (walk > 0) {
            const prev = items[walk - 1];
            const curr = items[walk];
            const should_swap = curr.score > prev.score or
                (curr.score == prev.score and entries[curr.index].created_at_ms > entries[prev.index].created_at_ms);
            if (!should_swap) break;
            items[walk - 1] = curr;
            items[walk] = prev;
            walk -= 1;
        }
    }
}

fn sortNeighborWeights(items: []NeighborTemp) void {
    if (items.len < 2) return;
    var idx: usize = 1;
    while (idx < items.len) : (idx += 1) {
        var walk = idx;
        while (walk > 0) {
            const prev = items[walk - 1];
            const curr = items[walk];
            const should_swap = curr.weight > prev.weight or
                (curr.weight == prev.weight and std.mem.order(u8, curr.to, prev.to) == .lt);
            if (!should_swap) break;
            items[walk - 1] = curr;
            items[walk] = prev;
            walk -= 1;
        }
    }
}

fn embedText(allocator: std.mem.Allocator, text: []const u8) !TokenVector {
    var vector = TokenVector.init(allocator);

    var tokens = std.mem.tokenizeAny(u8, text, " \t\r\n");
    while (tokens.next()) |raw_token| {
        const trimmed = std.mem.trim(u8, raw_token, token_trim_chars);
        if (trimmed.len < 2) continue;
        const token_hash = hashLowerToken(trimmed);
        const op = try vector.getOrPut(token_hash);
        if (op.found_existing) {
            op.value_ptr.* += 1;
        } else {
            op.value_ptr.* = 1;
        }
    }

    if (vector.count() == 0) return vector;

    var norm: f64 = 0;
    var norm_it = vector.iterator();
    while (norm_it.next()) |entry| {
        norm += entry.value_ptr.* * entry.value_ptr.*;
    }
    norm = std.math.sqrt(norm);
    if (norm > 0) {
        var normalize_it = vector.iterator();
        while (normalize_it.next()) |entry| {
            entry.value_ptr.* /= norm;
        }
    }
    return vector;
}

fn hashLowerToken(token: []const u8) u64 {
    var hasher = std.hash.Wyhash.init(0);
    var single: [1]u8 = undefined;
    for (token) |ch| {
        single[0] = std.ascii.toLower(ch);
        hasher.update(&single);
    }
    return hasher.final();
}

fn cosineSimilarity(a: *const TokenVector, b: *const TokenVector) f64 {
    if (a.count() == 0 or b.count() == 0) return 0;
    var dot: f64 = 0;
    var it = a.iterator();
    while (it.next()) |entry| {
        if (b.get(entry.key_ptr.*)) |other| {
            dot += entry.value_ptr.* * other;
        }
    }
    return dot;
}

fn textHasEmbeddingTokens(text: []const u8) bool {
    var tokens = std.mem.tokenizeAny(u8, text, " \t\r\n");
    while (tokens.next()) |raw_token| {
        const trimmed = std.mem.trim(u8, raw_token, token_trim_chars);
        if (trimmed.len >= 2) return true;
    }
    return false;
}

fn firstSignificantTermAlloc(allocator: std.mem.Allocator, text: []const u8) !?[]u8 {
    var tokens = std.mem.tokenizeAny(u8, text, " \t\r\n");
    while (tokens.next()) |raw_token| {
        const trimmed = std.mem.trim(u8, raw_token, token_trim_chars);
        if (trimmed.len < 4) continue;
        var out = try allocator.alloc(u8, trimmed.len);
        for (trimmed, 0..) |ch, idx| out[idx] = std.ascii.toLower(ch);
        return out;
    }
    return null;
}

fn nodeKeyAlloc(allocator: std.mem.Allocator, prefix: []const u8, raw: []const u8) !?[]u8 {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len == 0) return null;
    var out = try allocator.alloc(u8, prefix.len + trimmed.len);
    @memcpy(out[0..prefix.len], prefix);
    for (trimmed, 0..) |ch, idx| out[prefix.len + idx] = std.ascii.toLower(ch);
    return out;
}

fn emitGraphEdgesForEntry(allocator: std.mem.Allocator, out_edges: *std.ArrayList(EdgePair), entry: *const MessageEntry) !void {
    if (try firstSignificantTermAlloc(allocator, entry.text)) |term| {
        if (try nodeKeyAlloc(allocator, "entry:", entry.id)) |entry_node| {
            if (try nodeKeyAlloc(allocator, "term:", term)) |term_node| {
                try out_edges.append(allocator, .{
                    .from = entry_node,
                    .to = term_node,
                });
            }
        }
    }

    if (try nodeKeyAlloc(allocator, "session:", entry.session_id)) |session_node| {
        if (try nodeKeyAlloc(allocator, "entry:", entry.id)) |entry_node| {
            try out_edges.append(allocator, .{
                .from = session_node,
                .to = entry_node,
            });
        }
        if (try nodeKeyAlloc(allocator, "channel:", entry.channel)) |channel_node| {
            try out_edges.append(allocator, .{
                .from = session_node,
                .to = channel_node,
            });
        }
    }

    if (try nodeKeyAlloc(allocator, "channel:", entry.channel)) |channel_node| {
        if (try nodeKeyAlloc(allocator, "method:", entry.method)) |method_node| {
            try out_edges.append(allocator, .{
                .from = channel_node,
                .to = method_node,
            });
        }
    }

    if (try nodeKeyAlloc(allocator, "role:", entry.role)) |role_node| {
        if (try nodeKeyAlloc(allocator, "method:", entry.method)) |method_node| {
            try out_edges.append(allocator, .{
                .from = role_node,
                .to = method_node,
            });
        }
    }
}

test "store append/history and persistence roundtrip" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.Io.Threaded.global_single_threaded.io();
    const root = try tmp.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(root);

    var store = try Store.init(allocator, root, 200);
    defer store.deinit();
    try store.append("s1", "telegram", "send", "user", "hello");
    try store.append("s1", "telegram", "send", "assistant", "hi");

    var history = try store.historyBySession(allocator, "s1", 10);
    defer history.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), history.count);
    try std.testing.expect(std.mem.eql(u8, history.items[0].text, "hello"));
    try std.testing.expect(std.mem.eql(u8, history.items[1].text, "hi"));

    var loaded = try Store.init(allocator, root, 200);
    defer loaded.deinit();
    var loaded_history = try loaded.historyBySession(allocator, "s1", 10);
    defer loaded_history.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), loaded_history.count);
}

test "store removeSession and trim keep ordering with linear compaction" {
    const allocator = std.testing.allocator;
    var store = try Store.init(allocator, "memory://opt-test", 32);
    defer store.deinit();

    try store.append("s1", "telegram", "send", "user", "a1");
    try store.append("s2", "telegram", "send", "user", "b1");
    try store.append("s1", "telegram", "send", "assistant", "a2");
    try store.append("s3", "telegram", "send", "user", "c1");

    const removed_s1 = try store.removeSession("s1");
    try std.testing.expectEqual(@as(usize, 2), removed_s1);
    try std.testing.expectEqual(@as(usize, 2), store.count());

    var s2_history = try store.historyBySession(allocator, "s2", 10);
    defer s2_history.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), s2_history.count);
    try std.testing.expect(std.mem.eql(u8, s2_history.items[0].text, "b1"));

    var all_before_trim = try store.historyBySession(allocator, "", 10);
    defer all_before_trim.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), all_before_trim.count);
    try std.testing.expect(std.mem.eql(u8, all_before_trim.items[0].text, "b1"));
    try std.testing.expect(std.mem.eql(u8, all_before_trim.items[1].text, "c1"));

    const trimmed = try store.trim(1);
    try std.testing.expectEqual(@as(usize, 1), trimmed);
    try std.testing.expectEqual(@as(usize, 1), store.count());

    var all_after_trim = try store.historyBySession(allocator, "", 10);
    defer all_after_trim.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), all_after_trim.count);
    try std.testing.expect(std.mem.eql(u8, all_after_trim.items[0].text, "c1"));
}

test "store semantic recall returns ranked oracle related hits" {
    const allocator = std.testing.allocator;
    var store = try Store.init(allocator, "memory://semantic", 200);
    defer store.deinit();

    try store.append("s1", "webchat", "chat.send", "user", "deploy oracle vm with gpt model");
    try store.append("s2", "telegram", "send", "assistant", "tts provider configured");
    try store.append("s3", "webchat", "chat.send", "user", "oracle migration checklist");

    var recall = try store.semanticRecall(allocator, "oracle vm migration", 2);
    defer recall.deinit(allocator);
    try std.testing.expect(recall.count > 0);
    const top_session = recall.items[0].sessionId;
    const top_is_oracle = std.mem.eql(u8, top_session, "s1") or std.mem.eql(u8, top_session, "s3");
    try std.testing.expect(top_is_oracle);
}

test "store graph neighbors and recall synthesis provide semantic and graph depth" {
    const allocator = std.testing.allocator;
    var store = try Store.init(allocator, "memory://graph", 200);
    defer store.deinit();

    try store.append("abc", "telegram", "send", "user", "enable telemetry alerts");
    try store.append("abc", "telegram", "send", "assistant", "telemetry alerts enabled");

    var neighbors = try store.graphNeighbors(allocator, "session:abc", 10);
    defer neighbors.deinit(allocator);
    try std.testing.expect(neighbors.count > 0);

    var synthesis = try store.recallSynthesis(allocator, "telemetry alerts", 3);
    defer synthesis.deinit(allocator);
    try std.testing.expect(synthesis.countSemantic > 0);
}

test "store stats include vector graph metadata and persistence recovery" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.Io.Threaded.global_single_threaded.io();
    const root = try tmp.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(root);

    var store = try Store.init(allocator, root, 100);
    defer store.deinit();
    try store.append("s1", "webchat", "chat.send", "user", "vector memory test");

    const stats = store.stats();
    try std.testing.expectEqual(@as(usize, 1), stats.entries);
    try std.testing.expect(stats.vectors >= 1);
    try std.testing.expect(stats.graphNodes >= 1);
    try std.testing.expect(stats.graphEdges >= 1);
    try std.testing.expect(!stats.unlimited);

    var loaded = try Store.init(allocator, root, 100);
    defer loaded.deinit();
    const loaded_stats = loaded.stats();
    try std.testing.expectEqual(@as(usize, 1), loaded_stats.entries);
    try std.testing.expect(loaded_stats.vectors >= 1);
}

test "store load enforces max entries and keeps newest multi-session history" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.Io.Threaded.global_single_threaded.io();
    const root = try tmp.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(root);

    {
        var seeded = try Store.init(allocator, root, 200);
        defer seeded.deinit();
        var idx: usize = 0;
        while (idx < 120) : (idx += 1) {
            const session_id = switch (idx % 3) {
                0 => "sA",
                1 => "sB",
                else => "sC",
            };
            const message = try std.fmt.allocPrint(allocator, "m-{d}", .{idx + 1});
            defer allocator.free(message);
            try seeded.append(session_id, "webchat", "send", "user", message);
        }
        try std.testing.expectEqual(@as(usize, 120), seeded.count());
    }

    var capped = try Store.init(allocator, root, 50);
    defer capped.deinit();
    try std.testing.expectEqual(@as(usize, 50), capped.count());

    var all_history = try capped.historyBySession(allocator, "", 500);
    defer all_history.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 50), all_history.count);
    try std.testing.expect(std.mem.eql(u8, all_history.items[0].text, "m-71"));
    try std.testing.expect(std.mem.eql(u8, all_history.items[all_history.count - 1].text, "m-120"));

    var session_a = try capped.historyBySession(allocator, "sA", 100);
    defer session_a.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 16), session_a.count);
    try std.testing.expect(std.mem.eql(u8, session_a.items[0].text, "m-73"));
    try std.testing.expect(std.mem.eql(u8, session_a.items[session_a.count - 1].text, "m-118"));
}

test "store load derives next id from entries when persisted nextId is stale" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.Io.Threaded.global_single_threaded.io();
    const root = try tmp.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(root);

    const state_path = try std.fs.path.join(allocator, &.{ root, "memory.json" });
    defer allocator.free(state_path);

    const seeded_json =
        \\{"nextId":1,"entries":[
        \\{"id":"msg-5","sessionId":"s-stale","channel":"webchat","method":"send","role":"user","text":"seed-1","createdAtMs":1700000000001},
        \\{"id":"msg-6","sessionId":"s-stale","channel":"webchat","method":"send","role":"assistant","text":"seed-2","createdAtMs":1700000000002}
        \\]}
    ;
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = state_path,
        .data = seeded_json,
    });

    var store = try Store.init(allocator, root, 32);
    defer store.deinit();
    try std.testing.expectEqual(@as(usize, 2), store.count());

    try store.append("s-stale", "webchat", "send", "user", "post-load");
    var history = try store.historyBySession(allocator, "s-stale", 10);
    defer history.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 3), history.count);
    try std.testing.expect(std.mem.eql(u8, history.items[history.count - 1].id, "msg-7"));
}

test "store unlimited retention keeps all entries and reports unlimited stats" {
    const allocator = std.testing.allocator;
    var store = try Store.init(allocator, "memory://unlimited", 0);
    defer store.deinit();

    var idx: usize = 0;
    while (idx < 180) : (idx += 1) {
        try store.append("s-unlimited", "webchat", "chat.send", "user", "entry");
    }
    try std.testing.expectEqual(@as(usize, 180), store.count());
    const stats = store.stats();
    try std.testing.expect(stats.unlimited);
    try std.testing.expectEqual(@as(usize, 0), stats.maxEntries);
}
