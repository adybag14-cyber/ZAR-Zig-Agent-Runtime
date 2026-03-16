const std = @import("std");
const abi = @import("abi.zig");
const filesystem = @import("filesystem.zig");
const storage_backend = @import("storage_backend.zig");
const ata_pio_disk = @import("ata_pio_disk.zig");

pub const max_name_len: usize = 32;

pub const Error = filesystem.Error || std.mem.Allocator.Error || error{
    InvalidPackageName,
    InvalidPackagePath,
    PackageNotFound,
    ResponseTooLarge,
};

pub fn installScriptPackage(name: []const u8, script: []const u8, tick: u64) Error!void {
    try validatePackageName(name);

    var root_buf: [filesystem.max_path_len]u8 = undefined;
    var bin_buf: [filesystem.max_path_len]u8 = undefined;
    var meta_buf: [filesystem.max_path_len]u8 = undefined;
    var assets_buf: [filesystem.max_path_len]u8 = undefined;
    var entrypoint_buf: [filesystem.max_path_len]u8 = undefined;

    try filesystem.createDirPath(packageRootPath(name, &root_buf));
    try filesystem.createDirPath(packageBinPath(name, &bin_buf));
    try filesystem.createDirPath(packageMetaPath(name, &meta_buf));
    try filesystem.createDirPath(packageAssetsPath(name, &assets_buf));

    const entrypoint = try entrypointPath(name, &entrypoint_buf);
    try filesystem.writeFile(entrypoint, script, tick);
    try refreshManifest(name, tick);
}

pub fn entrypointPath(name: []const u8, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    try validatePackageName(name);
    return std.fmt.bufPrint(buffer, "/packages/{s}/bin/main.oc", .{name}) catch error.InvalidPath;
}

pub fn manifestPath(name: []const u8, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    try validatePackageName(name);
    return std.fmt.bufPrint(buffer, "/packages/{s}/meta/package.txt", .{name}) catch error.InvalidPath;
}

pub fn assetsPath(name: []const u8, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    try validatePackageName(name);
    return std.fmt.bufPrint(buffer, "/packages/{s}/assets", .{name}) catch error.InvalidPath;
}

pub fn assetPath(name: []const u8, relative_path: []const u8, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    try validatePackageName(name);
    try validatePackageRelativePath(relative_path);
    return std.fmt.bufPrint(buffer, "/packages/{s}/assets/{s}", .{ name, relative_path }) catch error.InvalidPath;
}

pub fn manifestAlloc(allocator: std.mem.Allocator, name: []const u8, max_bytes: usize) Error![]u8 {
    var manifest_buf: [filesystem.max_path_len]u8 = undefined;
    const manifest = try manifestPath(name, &manifest_buf);
    return filesystem.readFileAlloc(allocator, manifest, max_bytes);
}

pub fn installPackageAsset(name: []const u8, relative_path: []const u8, data: []const u8, tick: u64) Error!void {
    if (!try packageExists(name)) return error.PackageNotFound;

    var assets_buf: [filesystem.max_path_len]u8 = undefined;
    var asset_buf: [filesystem.max_path_len]u8 = undefined;
    const assets_root = try assetsPath(name, &assets_buf);
    const full_path = try assetPath(name, relative_path, &asset_buf);

    try filesystem.createDirPath(assets_root);
    try filesystem.createDirPath(parentSlice(full_path));
    try filesystem.writeFile(full_path, data, tick);
    try refreshManifest(name, tick);
}

pub fn readPackageAssetAlloc(
    allocator: std.mem.Allocator,
    name: []const u8,
    relative_path: []const u8,
    max_bytes: usize,
) Error![]u8 {
    var asset_buf: [filesystem.max_path_len]u8 = undefined;
    const full_path = try assetPath(name, relative_path, &asset_buf);
    return filesystem.readFileAlloc(allocator, full_path, max_bytes);
}

pub fn listPackageAssetsAlloc(allocator: std.mem.Allocator, name: []const u8, max_bytes: usize) Error![]u8 {
    if (!try packageExists(name)) return error.PackageNotFound;

    var assets_buf: [filesystem.max_path_len]u8 = undefined;
    const assets_root = try assetsPath(name, &assets_buf);
    return filesystem.listDirectoryAlloc(allocator, assets_root, max_bytes) catch |err| switch (err) {
        error.FileNotFound => allocator.alloc(u8, 0),
        else => err,
    };
}

pub fn listPackagesAlloc(allocator: std.mem.Allocator, max_bytes: usize) Error![]u8 {
    try filesystem.init();

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var idx: u32 = 0;
    while (idx < filesystem.max_entries) : (idx += 1) {
        const record = filesystem.entry(idx);
        if (record.kind != abi.filesystem_kind_file) continue;
        const path = record.path[0..record.path_len];
        const package_name = packageNameFromEntrypoint(path) orelse continue;

        const line = try std.fmt.allocPrint(allocator, "{s}\n", .{package_name});
        defer allocator.free(line);
        if (out.items.len + line.len > max_bytes) return error.ResponseTooLarge;
        try out.appendSlice(allocator, line);
    }

    return out.toOwnedSlice(allocator);
}

fn validatePackageName(name: []const u8) Error!void {
    if (name.len == 0 or name.len > max_name_len) return error.InvalidPackageName;
    for (name) |char| {
        if (std.ascii.isAlphanumeric(char) or char == '-' or char == '_' or char == '.') continue;
        return error.InvalidPackageName;
    }
}

fn validatePackageRelativePath(relative_path: []const u8) Error!void {
    if (relative_path.len == 0 or relative_path.len >= filesystem.max_path_len) return error.InvalidPackagePath;
    if (relative_path[0] == '/' or relative_path[relative_path.len - 1] == '/') return error.InvalidPackagePath;

    var segments = std.mem.splitScalar(u8, relative_path, '/');
    while (segments.next()) |segment| {
        if (segment.len == 0 or std.mem.eql(u8, segment, ".") or std.mem.eql(u8, segment, "..")) {
            return error.InvalidPackagePath;
        }
        for (segment) |char| {
            if (std.ascii.isAlphanumeric(char) or char == '-' or char == '_' or char == '.') continue;
            return error.InvalidPackagePath;
        }
    }
}

fn packageRootPath(name: []const u8, buffer: *[filesystem.max_path_len]u8) []const u8 {
    return std.fmt.bufPrint(buffer, "/packages/{s}", .{name}) catch unreachable;
}

fn packageBinPath(name: []const u8, buffer: *[filesystem.max_path_len]u8) []const u8 {
    return std.fmt.bufPrint(buffer, "/packages/{s}/bin", .{name}) catch unreachable;
}

fn packageMetaPath(name: []const u8, buffer: *[filesystem.max_path_len]u8) []const u8 {
    return std.fmt.bufPrint(buffer, "/packages/{s}/meta", .{name}) catch unreachable;
}

fn packageAssetsPath(name: []const u8, buffer: *[filesystem.max_path_len]u8) []const u8 {
    return std.fmt.bufPrint(buffer, "/packages/{s}/assets", .{name}) catch unreachable;
}

fn packageExists(name: []const u8) Error!bool {
    var entrypoint_buf: [filesystem.max_path_len]u8 = undefined;
    const entrypoint = try entrypointPath(name, &entrypoint_buf);
    _ = filesystem.statSummary(entrypoint) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    return true;
}

const AssetStats = struct {
    count: u32 = 0,
    bytes: u32 = 0,
};

fn packageAssetStats(name: []const u8) Error!AssetStats {
    var assets_buf: [filesystem.max_path_len]u8 = undefined;
    const assets_root = try assetsPath(name, &assets_buf);
    var stats: AssetStats = .{};

    var idx: u32 = 0;
    while (idx < filesystem.max_entries) : (idx += 1) {
        const record = filesystem.entry(idx);
        if (record.kind != abi.filesystem_kind_file) continue;
        const path = record.path[0..record.path_len];
        if (!std.mem.startsWith(u8, path, assets_root)) continue;
        if (path.len <= assets_root.len or path[assets_root.len] != '/') continue;
        stats.count +%= 1;
        stats.bytes +%= record.byte_len;
    }

    return stats;
}

fn refreshManifest(name: []const u8, tick: u64) Error!void {
    var root_buf: [filesystem.max_path_len]u8 = undefined;
    var entrypoint_buf: [filesystem.max_path_len]u8 = undefined;
    var manifest_buf: [filesystem.max_path_len]u8 = undefined;
    var assets_buf: [filesystem.max_path_len]u8 = undefined;

    const root = packageRootPath(name, &root_buf);
    const entrypoint = try entrypointPath(name, &entrypoint_buf);
    const manifest = try manifestPath(name, &manifest_buf);
    const assets_root = try assetsPath(name, &assets_buf);
    const script_stat = filesystem.statSummary(entrypoint) catch |err| switch (err) {
        error.FileNotFound => return error.PackageNotFound,
        else => return err,
    };
    const stats = try packageAssetStats(name);

    var metadata: [384]u8 = undefined;
    const manifest_body = std.fmt.bufPrint(
        &metadata,
        "name={s}\nroot={s}\nentrypoint={s}\nscript_bytes={d}\nasset_root={s}\nasset_count={d}\nasset_bytes={d}\n",
        .{
            name,
            root,
            entrypoint,
            script_stat.size,
            assets_root,
            stats.count,
            stats.bytes,
        },
    ) catch return error.InvalidPath;
    try filesystem.writeFile(manifest, manifest_body, tick);
}

fn parentSlice(path: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, path, '/')) |index| {
        if (index == 0) return "/";
        return path[0..index];
    }
    return "/";
}

fn packageNameFromEntrypoint(path: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, path, "/packages/")) return null;
    if (!std.mem.endsWith(u8, path, "/bin/main.oc")) return null;
    const name = path["/packages/".len .. path.len - "/bin/main.oc".len];
    if (name.len == 0 or std.mem.indexOfScalar(u8, name, '/') != null) return null;
    return name;
}

test "package store installs script packages into canonical layout" {
    storage_backend.resetForTest();
    filesystem.resetForTest();

    try installScriptPackage("demo", "echo package-ok", 7);

    var entrypoint_buf: [filesystem.max_path_len]u8 = undefined;
    var manifest_buf: [filesystem.max_path_len]u8 = undefined;
    const entrypoint = try entrypointPath("demo", &entrypoint_buf);
    const manifest = try manifestPath("demo", &manifest_buf);

    const script = try filesystem.readFileAlloc(std.testing.allocator, entrypoint, 64);
    defer std.testing.allocator.free(script);
    try std.testing.expectEqualStrings("echo package-ok", script);

    const metadata = try filesystem.readFileAlloc(std.testing.allocator, manifest, 256);
    defer std.testing.allocator.free(metadata);
    try std.testing.expect(std.mem.indexOf(u8, metadata, "name=demo") != null);
    try std.testing.expect(std.mem.indexOf(u8, metadata, "root=/packages/demo") != null);
    try std.testing.expect(std.mem.indexOf(u8, metadata, entrypoint) != null);
    try std.testing.expect(std.mem.indexOf(u8, metadata, "script_bytes=15") != null);
    try std.testing.expect(std.mem.indexOf(u8, metadata, "asset_root=/packages/demo/assets") != null);
    try std.testing.expect(std.mem.indexOf(u8, metadata, "asset_count=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, metadata, "asset_bytes=0") != null);

    const listing = try listPackagesAlloc(std.testing.allocator, 64);
    defer std.testing.allocator.free(listing);
    try std.testing.expectEqualStrings("demo\n", listing);
}

test "package store persists canonical layout on ata-backed storage" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    ata_pio_disk.testEnableMockDevice(8192);
    ata_pio_disk.testInstallMockMbrPartition(2048, 4096, 0x83);
    defer ata_pio_disk.testDisableMockDevice();

    try installScriptPackage("persisted", "echo persisted-package", 11);
    try std.testing.expectEqual(@as(u32, 2048), ata_pio_disk.logicalBaseLba());

    filesystem.resetForTest();

    var entrypoint_buf: [filesystem.max_path_len]u8 = undefined;
    const entrypoint = try entrypointPath("persisted", &entrypoint_buf);
    const script = try filesystem.readFileAlloc(std.testing.allocator, entrypoint, 64);
    defer std.testing.allocator.free(script);
    try std.testing.expectEqualStrings("echo persisted-package", script);

    const listing = try listPackagesAlloc(std.testing.allocator, 64);
    defer std.testing.allocator.free(listing);
    try std.testing.expectEqualStrings("persisted\n", listing);
}

test "package store reads persisted manifest metadata and tracks package assets" {
    storage_backend.resetForTest();
    filesystem.resetForTest();

    try installScriptPackage("info-demo", "echo info-demo", 5);
    try installPackageAsset("info-demo", "config/app.json", "{\"mode\":\"tcp\"}", 6);

    const manifest = try manifestAlloc(std.testing.allocator, "info-demo", 256);
    defer std.testing.allocator.free(manifest);

    try std.testing.expect(std.mem.indexOf(u8, manifest, "name=info-demo") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "root=/packages/info-demo") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "/packages/info-demo/bin/main.oc") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "script_bytes=14") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "asset_root=/packages/info-demo/assets") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "asset_count=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "asset_bytes=14") != null);

    const assets = try listPackageAssetsAlloc(std.testing.allocator, "info-demo", 64);
    defer std.testing.allocator.free(assets);
    try std.testing.expectEqualStrings("dir config\n", assets);

    const asset = try readPackageAssetAlloc(std.testing.allocator, "info-demo", "config/app.json", 64);
    defer std.testing.allocator.free(asset);
    try std.testing.expectEqualStrings("{\"mode\":\"tcp\"}", asset);
}
