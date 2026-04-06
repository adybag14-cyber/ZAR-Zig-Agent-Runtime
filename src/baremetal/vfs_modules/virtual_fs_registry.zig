const proc_version_path = "/proc/version";
const proc_runtime_path = "/proc/runtime";
const proc_runtime_snapshot_path = "/proc/runtime/snapshot";
const proc_runtime_sessions_path = "/proc/runtime/sessions";
    return std.mem.eql(u8, path, "/proc") or
        std.mem.startsWith(u8, path, "/proc/") or
    if (std.mem.eql(u8, path, "/proc")) {
        try appendDirectoryLine(allocator, &out, "runtime", max_bytes);
        try appendFileLine(allocator, &out, "version", proc_version_path, max_bytes);
        return out.toOwnedSlice(allocator);
    }
    if (std.mem.eql(u8, path, proc_runtime_path)) {
        try appendFileLine(allocator, &out, "snapshot", proc_runtime_snapshot_path, max_bytes);
        try appendDirectoryLine(allocator, &out, "sessions", max_bytes);
        return out.toOwnedSlice(allocator);
    }
    if (std.mem.eql(u8, path, proc_runtime_sessions_path)) {
        try appendRuntimeSessionDirectory(allocator, &out, max_bytes);
        return out.toOwnedSlice(allocator);
    }
    if (std.mem.eql(u8, path, "/proc")) return true;
    if (std.mem.eql(u8, path, proc_runtime_path)) return true;
    if (std.mem.eql(u8, path, proc_runtime_sessions_path)) return true;
