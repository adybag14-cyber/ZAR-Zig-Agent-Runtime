// SPDX-License-Identifier: GPL-2.0-only
const builtin = @import("builtin");
const std = @import("std");
const pal_fs = @import("../pal/fs.zig");

pub const Session = struct {
    created_unix_ms: i64,
    updated_unix_ms: i64,
    last_message: []u8,
};

pub const SessionSnapshot = struct {
    id: []const u8,
    created_unix_ms: i64,
    updated_unix_ms: i64,
    last_message: []const u8,
};

pub const Snapshot = struct {
    statePath: []const u8,
    persisted: bool,
    sessions: usize,
    pendingJobs: usize,
    leasedJobs: usize,
    recoveryBacklog: usize,
    nextJobId: u64,
};

pub const JobKind = enum {
    exec,
    file_read,
    file_write,
};

pub const Job = struct {
    id: u64,
    kind: JobKind,
    payload: []u8,
};

const PersistedSession = struct {
    id: []const u8,
    createdAtMs: i64,
    updatedAtMs: i64,
    lastMessage: []const u8,
};

const PersistedJob = struct {
    id: u64,
    kind: []const u8,
    payload: []const u8,
};

const PersistedState = struct {
    nextJobId: u64 = 1,
    sessions: []PersistedSession = &.{},
    pendingJobs: []PersistedJob = &.{},
    leasedJobs: []PersistedJob = &.{},
};

pub const RuntimeState = struct {
    allocator: std.mem.Allocator,
    sessions: std.StringHashMap(Session),
    pending_jobs: std.ArrayList(Job),
    leased_jobs: std.ArrayList(Job),
    pending_jobs_head: usize,
    next_job_id: u64,
    state_path: ?[]u8,
    persistent: bool,

    pub fn init(allocator: std.mem.Allocator) RuntimeState {
        return .{
            .allocator = allocator,
            .sessions = std.StringHashMap(Session).init(allocator),
            .pending_jobs = .empty,
            .leased_jobs = .empty,
            .pending_jobs_head = 0,
            .next_job_id = 1,
            .state_path = null,
            .persistent = false,
        };
    }

    pub fn deinit(self: *RuntimeState) void {
        self.clearState();
        self.sessions.deinit();
        self.pending_jobs.deinit(self.allocator);
        self.leased_jobs.deinit(self.allocator);
        if (self.state_path) |path| {
            self.allocator.free(path);
        }
        self.state_path = null;
        self.persistent = false;
    }

    pub fn configurePersistence(self: *RuntimeState, state_root: []const u8) !void {
        const resolved = try resolveStatePath(self.allocator, state_root);
        if (self.state_path) |existing| self.allocator.free(existing);
        self.state_path = resolved;
        self.persistent = shouldPersist(resolved);
        if (!self.persistent) return;

        // Persistence configuration is expected during runtime bootstrap.
        // If state already exists in memory, keep it untouched.
        if (self.sessions.count() == 0 and self.queueDepth() == 0 and self.leased_jobs.items.len == 0 and self.next_job_id == 1) {
            try self.load();
        }
    }

    pub fn upsertSession(
        self: *RuntimeState,
        session_id: []const u8,
        message: []const u8,
        now_unix_ms: i64,
    ) !void {
        if (self.sessions.getPtr(session_id)) |existing| {
            self.allocator.free(existing.last_message);
            existing.last_message = try self.allocator.dupe(u8, message);
            existing.updated_unix_ms = now_unix_ms;
            if (self.persistent) try self.persist();
            return;
        }

        const owned_key = try self.allocator.dupe(u8, session_id);
        errdefer self.allocator.free(owned_key);
        const owned_message = try self.allocator.dupe(u8, message);
        errdefer self.allocator.free(owned_message);

        try self.sessions.put(owned_key, .{
            .created_unix_ms = now_unix_ms,
            .updated_unix_ms = now_unix_ms,
            .last_message = owned_message,
        });
        if (self.persistent) try self.persist();
    }

    pub fn getSession(self: *const RuntimeState, session_id: []const u8) ?SessionSnapshot {
        const value = self.sessions.get(session_id) orelse return null;
        return .{
            .id = session_id,
            .created_unix_ms = value.created_unix_ms,
            .updated_unix_ms = value.updated_unix_ms,
            .last_message = value.last_message,
        };
    }

    pub fn enqueueJob(self: *RuntimeState, kind: JobKind, payload: []const u8) !u64 {
        const owned_payload = try self.allocator.dupe(u8, payload);
        const job_id = self.next_job_id;
        self.next_job_id += 1;
        try self.pending_jobs.append(self.allocator, .{
            .id = job_id,
            .kind = kind,
            .payload = owned_payload,
        });
        if (self.persistent) try self.persist();
        return job_id;
    }

    pub fn dequeueJob(self: *RuntimeState) ?Job {
        if (self.pending_jobs_head >= self.pending_jobs.items.len) return null;
        const job = self.pending_jobs.items[self.pending_jobs_head];
        self.leased_jobs.append(self.allocator, job) catch return null;
        self.pending_jobs_head += 1;
        self.compactPendingJobs();
        if (self.persistent) self.persist() catch {};
        return job;
    }

    pub fn releaseJob(self: *RuntimeState, job: Job) void {
        var idx: usize = 0;
        while (idx < self.leased_jobs.items.len) : (idx += 1) {
            if (self.leased_jobs.items[idx].id == job.id) {
                _ = self.leased_jobs.orderedRemove(idx);
                break;
            }
        }
        self.allocator.free(job.payload);
        if (self.persistent) self.persist() catch {};
    }

    pub fn queueDepth(self: *const RuntimeState) usize {
        return self.pending_jobs.items.len - self.pending_jobs_head;
    }

    pub fn leasedDepth(self: *const RuntimeState) usize {
        return self.leased_jobs.items.len;
    }

    pub fn sessionCount(self: *const RuntimeState) usize {
        return self.sessions.count();
    }

    pub fn snapshot(self: *const RuntimeState) Snapshot {
        const pending = self.queueDepth();
        const leased = self.leasedDepth();
        return .{
            .statePath = if (self.state_path) |path| path else "memory://runtime-state",
            .persisted = self.persistent,
            .sessions = self.sessionCount(),
            .pendingJobs = pending,
            .leasedJobs = leased,
            .recoveryBacklog = pending + leased,
            .nextJobId = self.next_job_id,
        };
    }

    fn compactPendingJobs(self: *RuntimeState) void {
        const len = self.pending_jobs.items.len;
        const head = self.pending_jobs_head;
        if (head == 0) return;
        if (head < 32 and head * 2 < len) return;

        const remaining = len - head;
        if (remaining > 0) {
            std.mem.copyForwards(Job, self.pending_jobs.items[0..remaining], self.pending_jobs.items[head..]);
        }
        self.pending_jobs.items.len = remaining;
        self.pending_jobs_head = 0;
    }

    fn clearState(self: *RuntimeState) void {
        var it = self.sessions.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.last_message);
        }
        self.sessions.clearRetainingCapacity();

        for (self.pending_jobs.items[self.pending_jobs_head..]) |job| {
            self.allocator.free(job.payload);
        }
        self.pending_jobs.clearRetainingCapacity();
        for (self.leased_jobs.items) |job| {
            self.allocator.free(job.payload);
        }
        self.leased_jobs.clearRetainingCapacity();
        self.pending_jobs_head = 0;
        self.next_job_id = 1;
    }

    fn load(self: *RuntimeState) !void {
        const path = self.state_path orelse return;
        const io = persistenceIo();
        const raw = pal_fs.readFileAlloc(io, self.allocator, path, 4 * 1024 * 1024) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return err,
        };
        defer self.allocator.free(raw);

        var parsed = try std.json.parseFromSlice(PersistedState, self.allocator, raw, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();
        const normalize_leased_jobs = parsed.value.leasedJobs.len > 0;

        self.clearState();
        var max_job_id: u64 = 0;

        for (parsed.value.sessions) |entry| {
            const key = try self.allocator.dupe(u8, std.mem.trim(u8, entry.id, " \t\r\n"));
            errdefer self.allocator.free(key);
            const message = try self.allocator.dupe(u8, entry.lastMessage);
            errdefer self.allocator.free(message);
            try self.sessions.put(key, .{
                .created_unix_ms = entry.createdAtMs,
                .updated_unix_ms = entry.updatedAtMs,
                .last_message = message,
            });
        }

        for (parsed.value.leasedJobs) |entry| {
            try self.appendRestoredPendingJob(entry);
            if (entry.id > max_job_id) max_job_id = entry.id;
        }

        for (parsed.value.pendingJobs) |entry| {
            try self.appendRestoredPendingJob(entry);
            if (entry.id > max_job_id) max_job_id = entry.id;
        }
        self.pending_jobs_head = 0;
        self.next_job_id = parsed.value.nextJobId;
        if (self.next_job_id <= max_job_id) self.next_job_id = max_job_id + 1;
        if (normalize_leased_jobs and self.persistent) {
            try self.persist();
        }
    }

    fn persist(self: *RuntimeState) !void {
        if (!self.persistent) return;
        const path = self.state_path orelse return;
        const io = persistenceIo();

        if (std.fs.path.dirname(path)) |parent| {
            if (parent.len > 0) try pal_fs.createDirPath(io, parent);
        }

        var persisted_sessions = try self.allocator.alloc(PersistedSession, self.sessions.count());
        defer self.allocator.free(persisted_sessions);
        var session_index: usize = 0;
        var it = self.sessions.iterator();
        while (it.next()) |entry| {
            const session = entry.value_ptr.*;
            persisted_sessions[session_index] = .{
                .id = entry.key_ptr.*,
                .createdAtMs = session.created_unix_ms,
                .updatedAtMs = session.updated_unix_ms,
                .lastMessage = session.last_message,
            };
            session_index += 1;
        }

        const pending_count = self.pending_jobs.items.len - self.pending_jobs_head;
        var persisted_jobs = try self.allocator.alloc(PersistedJob, pending_count);
        defer self.allocator.free(persisted_jobs);
        for (self.pending_jobs.items[self.pending_jobs_head..], 0..) |job, idx| {
            persisted_jobs[idx] = .{
                .id = job.id,
                .kind = formatJobKind(job.kind),
                .payload = job.payload,
            };
        }

        var persisted_leased_jobs = try self.allocator.alloc(PersistedJob, self.leased_jobs.items.len);
        defer self.allocator.free(persisted_leased_jobs);
        for (self.leased_jobs.items, 0..) |job, idx| {
            persisted_leased_jobs[idx] = .{
                .id = job.id,
                .kind = formatJobKind(job.kind),
                .payload = job.payload,
            };
        }

        var out: std.Io.Writer.Allocating = .init(self.allocator);
        defer out.deinit();
        try std.json.Stringify.value(.{
            .nextJobId = self.next_job_id,
            .sessions = persisted_sessions,
            .pendingJobs = persisted_jobs,
            .leasedJobs = persisted_leased_jobs,
        }, .{}, &out.writer);
        const payload = try out.toOwnedSlice();
        defer self.allocator.free(payload);

        try pal_fs.writeFile(io, path, payload);
    }

    fn appendRestoredPendingJob(self: *RuntimeState, entry: PersistedJob) !void {
        const kind = parseJobKind(entry.kind) orelse return;
        const payload = try self.allocator.dupe(u8, entry.payload);
        errdefer self.allocator.free(payload);
        try self.pending_jobs.append(self.allocator, .{
            .id = entry.id,
            .kind = kind,
            .payload = payload,
        });
    }
};

fn persistenceIo() std.Io {
    if (builtin.os.tag == .freestanding) return undefined;
    return std.Io.Threaded.global_single_threaded.io();
}

fn testingHostedIo() std.Io {
    if (builtin.os.tag == .freestanding) return undefined;
    return std.Io.Threaded.global_single_threaded.io();
}

fn resolveStatePath(allocator: std.mem.Allocator, state_root: []const u8) ![]u8 {
    const trimmed = std.mem.trim(u8, state_root, " \t\r\n");
    if (trimmed.len == 0) return allocator.dupe(u8, "memory://runtime-state");
    if (isMemoryScheme(trimmed)) return allocator.dupe(u8, trimmed);
    if (std.mem.endsWith(u8, trimmed, ".json")) return allocator.dupe(u8, trimmed);
    if (builtin.os.tag == .freestanding and std.mem.startsWith(u8, trimmed, "/")) {
        var logical_root = trimmed;
        while (logical_root.len > 1 and logical_root[logical_root.len - 1] == '/') {
            logical_root = logical_root[0 .. logical_root.len - 1];
        }
        return std.fmt.allocPrint(allocator, "{s}/runtime-state.json", .{
            if (logical_root.len == 0) "/" else logical_root,
        });
    }
    if (std.mem.startsWith(u8, trimmed, "/") and isBaremetalLogicalRoot(trimmed)) {
        var logical_root = trimmed;
        while (logical_root.len > 1 and logical_root[logical_root.len - 1] == '/') {
            logical_root = logical_root[0 .. logical_root.len - 1];
        }
        return std.fmt.allocPrint(allocator, "{s}/runtime-state.json", .{
            if (logical_root.len == 0) "/" else logical_root,
        });
    }
    return std.fs.path.join(allocator, &.{ trimmed, "runtime-state.json" });
}

fn shouldPersist(path: []const u8) bool {
    return !isMemoryScheme(path);
}

fn isMemoryScheme(path: []const u8) bool {
    const prefix = "memory://";
    if (path.len < prefix.len) return false;
    return std.ascii.eqlIgnoreCase(path[0..prefix.len], prefix);
}

fn isBaremetalLogicalRoot(path: []const u8) bool {
    return matchesBaremetalRoot(path, "/runtime") or
        matchesBaremetalRoot(path, "/packages") or
        matchesBaremetalRoot(path, "/pkg") or
        matchesBaremetalRoot(path, "/tools") or
        matchesBaremetalRoot(path, "/proc") or
        matchesBaremetalRoot(path, "/sys") or
        matchesBaremetalRoot(path, "/dev") or
        matchesBaremetalRoot(path, "/loader") or
        matchesBaremetalRoot(path, "/boot");
}

fn matchesBaremetalRoot(path: []const u8, root: []const u8) bool {
    if (!std.mem.startsWith(u8, path, root)) return false;
    return path.len == root.len or path[root.len] == '/';
}

fn formatJobKind(kind: JobKind) []const u8 {
    return switch (kind) {
        .exec => "exec",
        .file_read => "file_read",
        .file_write => "file_write",
    };
}

fn parseJobKind(value: []const u8) ?JobKind {
    if (std.ascii.eqlIgnoreCase(value, "exec")) return .exec;
    if (std.ascii.eqlIgnoreCase(value, "file_read")) return .file_read;
    if (std.ascii.eqlIgnoreCase(value, "file_write")) return .file_write;
    return null;
}

test "runtime state stores and updates sessions" {
    const allocator = std.testing.allocator;
    var state = RuntimeState.init(allocator);
    defer state.deinit();

    try state.upsertSession("session-a", "hello", 1000);
    var snap = state.getSession("session-a").?;
    try std.testing.expectEqual(@as(i64, 1000), snap.created_unix_ms);
    try std.testing.expect(std.mem.eql(u8, snap.last_message, "hello"));

    try state.upsertSession("session-a", "updated", 1500);
    snap = state.getSession("session-a").?;
    try std.testing.expectEqual(@as(i64, 1000), snap.created_unix_ms);
    try std.testing.expectEqual(@as(i64, 1500), snap.updated_unix_ms);
    try std.testing.expect(std.mem.eql(u8, snap.last_message, "updated"));
}

test "runtime state queue preserves order" {
    const allocator = std.testing.allocator;
    var state = RuntimeState.init(allocator);
    defer state.deinit();

    _ = try state.enqueueJob(.exec, "{\"cmd\":\"echo hi\"}");
    _ = try state.enqueueJob(.file_read, "{\"path\":\"README.md\"}");
    try std.testing.expectEqual(@as(usize, 2), state.queueDepth());

    const first = state.dequeueJob().?;
    defer state.releaseJob(first);
    try std.testing.expectEqual(@as(u64, 1), first.id);
    try std.testing.expectEqual(JobKind.exec, first.kind);

    const second = state.dequeueJob().?;
    defer state.releaseJob(second);
    try std.testing.expectEqual(@as(u64, 2), second.id);
    try std.testing.expectEqual(JobKind.file_read, second.kind);

    try std.testing.expect(state.dequeueJob() == null);
}

test "resolveStatePath keeps hosted absolute roots distinct from baremetal logical roots" {
    const allocator = std.testing.allocator;

    const hosted = try resolveStatePath(allocator, "/home/runner/work/tmp/runtime-state");
    defer allocator.free(hosted);
    const hosted_expected = try std.fs.path.join(allocator, &.{ "/home/runner/work/tmp/runtime-state", "runtime-state.json" });
    defer allocator.free(hosted_expected);
    try std.testing.expectEqualStrings(hosted_expected, hosted);

    const baremetal = try resolveStatePath(allocator, "/runtime/state");
    defer allocator.free(baremetal);
    try std.testing.expectEqualStrings("/runtime/state/runtime-state.json", baremetal);
}

test "runtime state queue depth stays correct across compaction cycles" {
    const allocator = std.testing.allocator;
    var state = RuntimeState.init(allocator);
    defer state.deinit();

    var idx: usize = 0;
    while (idx < 96) : (idx += 1) {
        _ = try state.enqueueJob(.exec, "{\"cmd\":\"echo hi\"}");
    }
    try std.testing.expectEqual(@as(usize, 96), state.queueDepth());

    idx = 0;
    while (idx < 80) : (idx += 1) {
        const job = state.dequeueJob().?;
        state.releaseJob(job);
    }
    try std.testing.expectEqual(@as(usize, 16), state.queueDepth());

    idx = 0;
    while (idx < 20) : (idx += 1) {
        _ = try state.enqueueJob(.file_read, "{\"path\":\"README.md\"}");
    }
    try std.testing.expectEqual(@as(usize, 36), state.queueDepth());

    var expected_id: u64 = 81;
    while (state.dequeueJob()) |job| {
        defer state.releaseJob(job);
        try std.testing.expectEqual(expected_id, job.id);
        expected_id += 1;
    }
    try std.testing.expectEqual(@as(u64, 117), expected_id);
    try std.testing.expectEqual(@as(usize, 0), state.queueDepth());
}

test "runtime state persistence roundtrip restores session and pending queue" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = testingHostedIo();
    const root = try tmp.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(root);

    {
        var state = RuntimeState.init(allocator);
        defer state.deinit();
        try state.configurePersistence(root);
        try state.upsertSession("persist-s1", "hello runtime", 1_000);
        _ = try state.enqueueJob(.file_read, "{\"path\":\"README.md\"}");
        _ = try state.enqueueJob(.exec, "{\"cmd\":\"echo hi\"}");
        const consumed = state.dequeueJob().?;
        state.releaseJob(consumed);
    }

    {
        var restored = RuntimeState.init(allocator);
        defer restored.deinit();
        try restored.configurePersistence(root);
        const snap = restored.getSession("persist-s1").?;
        try std.testing.expectEqual(@as(i64, 1_000), snap.created_unix_ms);
        try std.testing.expect(std.mem.eql(u8, snap.last_message, "hello runtime"));
        try std.testing.expectEqual(@as(usize, 1), restored.queueDepth());
        const queued = restored.dequeueJob().?;
        defer restored.releaseJob(queued);
        try std.testing.expectEqual(@as(u64, 2), queued.id);
        try std.testing.expectEqual(JobKind.exec, queued.kind);
        try std.testing.expectEqual(@as(usize, 0), restored.queueDepth());
    }
}

test "runtime state restart replay preserves leased jobs that were dequeued but not released" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = testingHostedIo();
    const root = try tmp.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(root);

    {
        var state = RuntimeState.init(allocator);
        defer state.deinit();
        try state.configurePersistence(root);
        _ = try state.enqueueJob(.exec, "{\"cmd\":\"echo replay-me\"}");
        _ = try state.enqueueJob(.file_read, "{\"path\":\"README.md\"}");
        _ = state.dequeueJob().?;
        try std.testing.expectEqual(@as(usize, 1), state.queueDepth());
    }

    {
        var restored = RuntimeState.init(allocator);
        defer restored.deinit();
        try restored.configurePersistence(root);
        try std.testing.expectEqual(@as(usize, 2), restored.queueDepth());
        try std.testing.expectEqual(@as(usize, 0), restored.leasedDepth());

        const normalized_path = try std.fs.path.join(allocator, &.{ root, "runtime-state.json" });
        defer allocator.free(normalized_path);
        const raw = try pal_fs.readFileAlloc(io, allocator, normalized_path, 4 * 1024 * 1024);
        defer allocator.free(raw);

        var parsed = try std.json.parseFromSlice(PersistedState, allocator, raw, .{});
        defer parsed.deinit();
        try std.testing.expectEqual(@as(usize, 0), parsed.value.leasedJobs.len);
        try std.testing.expectEqual(@as(usize, 2), parsed.value.pendingJobs.len);

        const first = restored.dequeueJob().?;
        defer restored.releaseJob(first);
        try std.testing.expectEqual(@as(u64, 1), first.id);
        try std.testing.expectEqual(JobKind.exec, first.kind);

        const second = restored.dequeueJob().?;
        defer restored.releaseJob(second);
        try std.testing.expectEqual(@as(u64, 2), second.id);
        try std.testing.expectEqual(JobKind.file_read, second.kind);

        try std.testing.expectEqual(@as(usize, 0), restored.queueDepth());
    }
}
