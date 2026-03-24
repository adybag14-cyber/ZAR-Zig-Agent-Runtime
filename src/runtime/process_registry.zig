const builtin = @import("builtin");
const std = @import("std");
const time_util = @import("../util/time.zig");

pub const ProcessRegistryError = error{
    ProcessNotFound,
    ProcessManagementUnsupported,
};

pub const LifecycleState = enum {
    running,
    exited,
    killed,
    failed,
};

pub fn lifecycleStateText(state: LifecycleState) []const u8 {
    return switch (state) {
        .running => "running",
        .exited => "exited",
        .killed => "killed",
        .failed => "failed",
    };
}

const ProcessEntry = struct {
    process_id: []u8,
    session_id: []u8,
    command: []u8,
    cwd: []u8,
    stdout_path: []u8,
    stderr_path: []u8,
    pid: i64,
    lifecycle_state: LifecycleState,
    started_at_ms: i64,
    updated_at_ms: i64,
    finished_at_ms: i64,
    exit_code: i32,
    has_exit_code: bool,

    fn deinit(self: *ProcessEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.process_id);
        allocator.free(self.session_id);
        allocator.free(self.command);
        allocator.free(self.cwd);
        allocator.free(self.stdout_path);
        allocator.free(self.stderr_path);
    }
};

pub const ProcessSnapshot = struct {
    process_id: []u8,
    session_id: []u8,
    command: []u8,
    cwd: []u8,
    stdout_path: []u8,
    stderr_path: []u8,
    pid: i64,
    lifecycle_state: LifecycleState,
    started_at_ms: i64,
    updated_at_ms: i64,
    finished_at_ms: i64,
    exit_code: i32,
    has_exit_code: bool,

    pub fn deinit(self: *ProcessSnapshot, allocator: std.mem.Allocator) void {
        allocator.free(self.process_id);
        allocator.free(self.session_id);
        allocator.free(self.command);
        allocator.free(self.cwd);
        allocator.free(self.stdout_path);
        allocator.free(self.stderr_path);
    }
};

pub const ProcessRegistry = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    mutex: std.Io.Mutex,
    entries: std.ArrayList(ProcessEntry),
    next_process_id: u64,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) ProcessRegistry {
        return .{
            .allocator = allocator,
            .io = io,
            .mutex = .init,
            .entries = .empty,
            .next_process_id = 1,
        };
    }

    pub fn deinit(self: *ProcessRegistry) void {
        if (builtin.os.tag != .windows and builtin.os.tag != .wasi and builtin.os.tag != .freestanding) {
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);
            for (self.entries.items) |*entry| {
                if (entry.lifecycle_state != .running or entry.pid <= 0) continue;
                const pid: std.posix.pid_t = @intCast(entry.pid);
                std.posix.kill(pid, .KILL) catch {};
                var status: c_int = 0;
                _ = std.posix.system.waitpid(pid, &status, 0);
            }
        }

        for (self.entries.items) |*entry| entry.deinit(self.allocator);
        self.entries.deinit(self.allocator);
    }

    pub fn addProcess(
        self: *ProcessRegistry,
        allocator: std.mem.Allocator,
        session_id: []const u8,
        command: []const u8,
        cwd: []const u8,
        stdout_path: []const u8,
        stderr_path: []const u8,
        pid: i64,
        started_at_ms: i64,
    ) !ProcessSnapshot {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        const process_id = try std.fmt.allocPrint(self.allocator, "proc-{d:0>6}", .{self.next_process_id});
        errdefer self.allocator.free(process_id);
        self.next_process_id += 1;

        const owned_session_id = try self.allocator.dupe(u8, session_id);
        errdefer self.allocator.free(owned_session_id);
        const owned_command = try self.allocator.dupe(u8, command);
        errdefer self.allocator.free(owned_command);
        const owned_cwd = try self.allocator.dupe(u8, cwd);
        errdefer self.allocator.free(owned_cwd);
        const owned_stdout_path = try self.allocator.dupe(u8, stdout_path);
        errdefer self.allocator.free(owned_stdout_path);
        const owned_stderr_path = try self.allocator.dupe(u8, stderr_path);
        errdefer self.allocator.free(owned_stderr_path);

        try self.entries.append(self.allocator, .{
            .process_id = process_id,
            .session_id = owned_session_id,
            .command = owned_command,
            .cwd = owned_cwd,
            .stdout_path = owned_stdout_path,
            .stderr_path = owned_stderr_path,
            .pid = pid,
            .lifecycle_state = .running,
            .started_at_ms = started_at_ms,
            .updated_at_ms = started_at_ms,
            .finished_at_ms = 0,
            .exit_code = 0,
            .has_exit_code = false,
        });

        return cloneEntry(allocator, &self.entries.items[self.entries.items.len - 1]);
    }

    pub fn getSnapshotOwned(
        self: *ProcessRegistry,
        allocator: std.mem.Allocator,
        process_id: []const u8,
    ) !ProcessSnapshot {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        const index = findIndexUnlocked(self, process_id) orelse return error.ProcessNotFound;
        try refreshEntryUnlocked(&self.entries.items[index]);
        return cloneEntry(allocator, &self.entries.items[index]);
    }

    pub fn listSnapshotsOwned(
        self: *ProcessRegistry,
        allocator: std.mem.Allocator,
        session_filter: ?[]const u8,
    ) ![]ProcessSnapshot {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        try refreshAllUnlocked(self);

        var match_count: usize = 0;
        for (self.entries.items) |*entry| {
            if (!matchesSessionFilter(entry.session_id, session_filter)) continue;
            match_count += 1;
        }

        var snapshots = try allocator.alloc(ProcessSnapshot, match_count);
        var out_index: usize = 0;
        errdefer {
            for (snapshots[0..out_index]) |*entry| entry.deinit(allocator);
            allocator.free(snapshots);
        }

        for (self.entries.items) |*entry| {
            if (!matchesSessionFilter(entry.session_id, session_filter)) continue;
            snapshots[out_index] = try cloneEntry(allocator, entry);
            out_index += 1;
        }

        std.mem.sort(ProcessSnapshot, snapshots, {}, struct {
            fn lessThan(_: void, lhs: ProcessSnapshot, rhs: ProcessSnapshot) bool {
                return lhs.started_at_ms > rhs.started_at_ms;
            }
        }.lessThan);

        return snapshots;
    }

    pub fn requestTerminate(
        self: *ProcessRegistry,
        allocator: std.mem.Allocator,
        process_id: []const u8,
        now_ms: i64,
    ) !ProcessSnapshot {
        if (builtin.os.tag == .windows or builtin.os.tag == .wasi or builtin.os.tag == .freestanding) {
            return error.ProcessManagementUnsupported;
        }

        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        const index = findIndexUnlocked(self, process_id) orelse return error.ProcessNotFound;
        var entry = &self.entries.items[index];
        try refreshEntryUnlocked(entry);
        if (entry.lifecycle_state == .running and entry.pid > 0) {
            const pid: std.posix.pid_t = @intCast(entry.pid);
            try std.posix.kill(pid, .TERM);
            entry.updated_at_ms = now_ms;
        }
        try refreshEntryUnlocked(entry);
        return cloneEntry(allocator, entry);
    }

    fn matchesSessionFilter(session_id: []const u8, session_filter: ?[]const u8) bool {
        const filter = session_filter orelse return true;
        return std.mem.eql(u8, session_id, filter);
    }

    fn cloneEntry(allocator: std.mem.Allocator, entry: *const ProcessEntry) !ProcessSnapshot {
        return .{
            .process_id = try allocator.dupe(u8, entry.process_id),
            .session_id = try allocator.dupe(u8, entry.session_id),
            .command = try allocator.dupe(u8, entry.command),
            .cwd = try allocator.dupe(u8, entry.cwd),
            .stdout_path = try allocator.dupe(u8, entry.stdout_path),
            .stderr_path = try allocator.dupe(u8, entry.stderr_path),
            .pid = entry.pid,
            .lifecycle_state = entry.lifecycle_state,
            .started_at_ms = entry.started_at_ms,
            .updated_at_ms = entry.updated_at_ms,
            .finished_at_ms = entry.finished_at_ms,
            .exit_code = entry.exit_code,
            .has_exit_code = entry.has_exit_code,
        };
    }

    fn findIndexUnlocked(self: *const ProcessRegistry, process_id: []const u8) ?usize {
        const normalized = std.mem.trim(u8, process_id, " \t\r\n");
        if (normalized.len == 0) return null;
        for (self.entries.items, 0..) |entry, idx| {
            if (std.ascii.eqlIgnoreCase(entry.process_id, normalized)) return idx;
        }
        return null;
    }

    fn refreshAllUnlocked(self: *ProcessRegistry) !void {
        for (self.entries.items) |*entry| {
            try refreshEntryUnlocked(entry);
        }
    }

    fn refreshEntryUnlocked(entry: *ProcessEntry) !void {
        if (entry.lifecycle_state != .running) return;
        if (entry.pid <= 0) return;
        if (builtin.os.tag == .windows or builtin.os.tag == .wasi or builtin.os.tag == .freestanding) return;

        var status: c_int = 0;
        const pid: std.posix.pid_t = @intCast(entry.pid);
        const rc = std.posix.system.waitpid(pid, &status, std.posix.W.NOHANG);
        if (rc == 0) return;

        switch (std.posix.errno(rc)) {
            .SUCCESS => applyTerm(entry, termFromWaitStatus(status), time_util.nowMs()),
            .INTR => {},
            .CHILD => {
                entry.lifecycle_state = .failed;
                entry.exit_code = -1;
                entry.has_exit_code = true;
                entry.updated_at_ms = time_util.nowMs();
                if (entry.finished_at_ms == 0) entry.finished_at_ms = entry.updated_at_ms;
            },
            else => {
                entry.lifecycle_state = .failed;
                entry.exit_code = -1;
                entry.has_exit_code = true;
                entry.updated_at_ms = time_util.nowMs();
                if (entry.finished_at_ms == 0) entry.finished_at_ms = entry.updated_at_ms;
            },
        }
    }

    fn applyTerm(entry: *ProcessEntry, term: std.process.Child.Term, now_ms: i64) void {
        entry.updated_at_ms = now_ms;
        entry.finished_at_ms = now_ms;
        switch (term) {
            .exited => |code| {
                entry.lifecycle_state = .exited;
                entry.exit_code = @intCast(code);
                entry.has_exit_code = true;
            },
            .signal => |sig| {
                entry.lifecycle_state = .killed;
                entry.exit_code = -@as(i32, @intCast(@intFromEnum(sig)));
                entry.has_exit_code = true;
            },
            .stopped, .unknown => {
                entry.lifecycle_state = .failed;
                entry.exit_code = -1;
                entry.has_exit_code = true;
            },
        }
    }

    fn termFromWaitStatus(status: c_int) std.process.Child.Term {
        const WaitStatusInt = std.meta.Int(.unsigned, @bitSizeOf(c_int));
        const raw: WaitStatusInt = @bitCast(status);
        return if (std.posix.W.IFEXITED(raw))
            .{ .exited = std.posix.W.EXITSTATUS(raw) }
        else if (std.posix.W.IFSIGNALED(raw))
            .{ .signal = std.posix.W.TERMSIG(raw) }
        else if (std.posix.W.IFSTOPPED(raw))
            .{ .stopped = std.posix.W.STOPSIG(raw) }
        else
            .{ .unknown = @intCast(raw) };
    }
};

test "process registry add list and complete lifecycle on hosted posix" {
    if (builtin.os.tag == .windows or builtin.os.tag == .wasi or builtin.os.tag == .freestanding) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const io = std.testing.io;
    var registry = ProcessRegistry.init(allocator, io);
    defer registry.deinit();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(root);
    const stdout_path = try std.fs.path.join(allocator, &.{ root, "proc.stdout.log" });
    defer allocator.free(stdout_path);
    const stderr_path = try std.fs.path.join(allocator, &.{ root, "proc.stderr.log" });
    defer allocator.free(stderr_path);

    var stdout_file = try std.Io.Dir.createFileAbsolute(io, stdout_path, .{});
    defer stdout_file.close(io);
    var stderr_file = try std.Io.Dir.createFileAbsolute(io, stderr_path, .{});
    defer stderr_file.close(io);

    const child = try std.process.spawn(io, .{
        .argv = &.{ "/bin/sh", "-lc", "echo registry-out; echo registry-err >&2" },
        .stdin = .ignore,
        .stdout = .{ .file = stdout_file },
        .stderr = .{ .file = stderr_file },
    });
    const pid = @as(i64, @intCast(child.id.?));

    var added = try registry.addProcess(allocator, "sess-registry", "echo registry", root, stdout_path, stderr_path, pid, time_util.nowMs());
    defer added.deinit(allocator);
    try std.testing.expect(std.mem.startsWith(u8, added.process_id, "proc-"));

    var settled = false;
    var attempt: usize = 0;
    while (attempt < 20) : (attempt += 1) {
        var snapshot = try registry.getSnapshotOwned(allocator, added.process_id);
        if (snapshot.lifecycle_state != .running) {
            snapshot.deinit(allocator);
            settled = true;
            break;
        }
        snapshot.deinit(allocator);
        try std.Io.sleep(io, std.Io.Duration.fromMilliseconds(50), .awake);
    }
    try std.testing.expect(settled);

    const listed = try registry.listSnapshotsOwned(allocator, "sess-registry");
    defer {
        for (listed) |*entry| entry.deinit(allocator);
        allocator.free(listed);
    }
    try std.testing.expectEqual(@as(usize, 1), listed.len);
}
