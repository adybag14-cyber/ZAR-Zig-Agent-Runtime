// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const abi = @import("abi.zig");
const filesystem = @import("filesystem.zig");
const storage_backend = @import("storage_backend.zig");
const ata_pio_disk = @import("ata_pio_disk.zig");
const trust_store = @import("trust_store.zig");

pub const max_name_len: usize = 32;
pub const max_release_len: usize = 32;
pub const max_channel_len: usize = 32;
pub const default_display_width: u16 = 640;
pub const default_display_height: u16 = 400;
pub const default_connector_type: u8 = abi.display_connector_none;
const release_list_scan_max_bytes: usize = storage_backend.block_size * 4;
const release_copy_max_bytes: usize = storage_backend.block_size * 8;

pub const Error = filesystem.Error || trust_store.Error || std.mem.Allocator.Error || error{
    InvalidPackageName,
    InvalidReleaseName,
    InvalidChannelName,
    InvalidPackagePath,
    InvalidPackageMetadata,
    InvalidDisplayConnector,
    PackageNotFound,
    PackageReleaseNotFound,
    PackageReleaseAlreadyExists,
    PackageChannelNotFound,
    ResponseTooLarge,
};

pub const LaunchProfile = struct {
    entrypoint: []const u8,
    display_width: u16,
    display_height: u16,
    connector_type: u8 = default_connector_type,
    trust_bundle_len: u8 = 0,
    trust_bundle_storage: [trust_store.max_name_len]u8 = [_]u8{0} ** trust_store.max_name_len,

    pub fn trustBundle(self: *const LaunchProfile) []const u8 {
        return self.trust_bundle_storage[0..self.trust_bundle_len];
    }
};

pub const VerifyResult = struct {
    ok: bool,
    payload: []u8,

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(self.payload);
        self.* = undefined;
    }
};

pub const ReleasePruneResult = struct {
    kept_count: u32,
    deleted_count: u32,
};

const ManifestInfo = struct {
    root: []const u8 = "",
    entrypoint: []const u8 = "",
    app_manifest: []const u8 = "",
    script_bytes: u32 = 0,
    script_checksum: u32 = 0,
    app_manifest_checksum: u32 = 0,
    asset_root: []const u8 = "",
    asset_count: u32 = 0,
    asset_bytes: u32 = 0,
    asset_tree_checksum: u64 = 0,
};

const ReleaseMetadata = struct {
    name: []const u8 = "",
    release: []const u8 = "",
    saved_seq: u32 = 0,
    saved_tick: u64 = 0,
};

const ReleaseRecord = struct {
    name_len: usize,
    name_storage: [max_release_len]u8 = [_]u8{0} ** max_release_len,
    saved_seq: u32,

    fn name(self: *const @This()) []const u8 {
        return self.name_storage[0..self.name_len];
    }
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
    try refreshAppManifest(name, tick);
    try refreshManifest(name, tick);
}

pub fn deletePackage(name: []const u8, tick: u64) Error!void {
    try validatePackageName(name);
    if (!try packageExists(name)) return error.PackageNotFound;

    var root_buf: [filesystem.max_path_len]u8 = undefined;
    try filesystem.deleteTree(packageRootPath(name, &root_buf), tick);
}

pub fn entrypointPath(name: []const u8, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    try validatePackageName(name);
    return std.fmt.bufPrint(buffer, "/packages/{s}/bin/main.oc", .{name}) catch error.InvalidPath;
}

pub fn manifestPath(name: []const u8, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    try validatePackageName(name);
    return std.fmt.bufPrint(buffer, "/packages/{s}/meta/package.txt", .{name}) catch error.InvalidPath;
}

pub fn appManifestPath(name: []const u8, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    try validatePackageName(name);
    return std.fmt.bufPrint(buffer, "/packages/{s}/meta/app.txt", .{name}) catch error.InvalidPath;
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

pub fn verifyPackageAlloc(allocator: std.mem.Allocator, name: []const u8, max_bytes: usize) Error!VerifyResult {
    try validatePackageName(name);
    if (!try packageExists(name)) return error.PackageNotFound;

    const manifest = try manifestAlloc(allocator, name, 1024);
    defer allocator.free(manifest);
    const info = try parseManifestInfo(manifest);

    var root_buf: [filesystem.max_path_len]u8 = undefined;
    var entrypoint_buf: [filesystem.max_path_len]u8 = undefined;
    var app_manifest_buf: [filesystem.max_path_len]u8 = undefined;
    var assets_buf: [filesystem.max_path_len]u8 = undefined;

    const expected_root = packageRootPath(name, &root_buf);
    if (!std.mem.eql(u8, info.root, expected_root)) {
        return .{
            .ok = false,
            .payload = try formatVerifyPathMismatch(allocator, name, "root", info.root, expected_root, max_bytes),
        };
    }

    const expected_entrypoint = try entrypointPath(name, &entrypoint_buf);
    if (!std.mem.eql(u8, info.entrypoint, expected_entrypoint)) {
        return .{
            .ok = false,
            .payload = try formatVerifyPathMismatch(allocator, name, "entrypoint", info.entrypoint, expected_entrypoint, max_bytes),
        };
    }

    const expected_app_manifest = try appManifestPath(name, &app_manifest_buf);
    if (!std.mem.eql(u8, info.app_manifest, expected_app_manifest)) {
        return .{
            .ok = false,
            .payload = try formatVerifyPathMismatch(allocator, name, "app_manifest", info.app_manifest, expected_app_manifest, max_bytes),
        };
    }

    const expected_asset_root = try assetsPath(name, &assets_buf);
    if (!std.mem.eql(u8, info.asset_root, expected_asset_root)) {
        return .{
            .ok = false,
            .payload = try formatVerifyPathMismatch(allocator, name, "asset_root", info.asset_root, expected_asset_root, max_bytes),
        };
    }

    const script_stat = try filesystem.statSummary(expected_entrypoint);
    const app_manifest_stat = try filesystem.statSummary(expected_app_manifest);
    const asset_digest = try packageAssetDigest(name);

    if (info.script_bytes != @as(u32, @intCast(script_stat.size))) {
        return .{
            .ok = false,
            .payload = try formatVerifyU32Mismatch(
                allocator,
                name,
                "script_bytes",
                info.script_bytes,
                @as(u32, @intCast(script_stat.size)),
                max_bytes,
            ),
        };
    }
    if (info.script_checksum != script_stat.checksum) {
        return .{
            .ok = false,
            .payload = try formatVerifyHex32Mismatch(allocator, name, "script_checksum", info.script_checksum, script_stat.checksum, max_bytes),
        };
    }
    if (info.app_manifest_checksum != app_manifest_stat.checksum) {
        return .{
            .ok = false,
            .payload = try formatVerifyHex32Mismatch(
                allocator,
                name,
                "app_manifest_checksum",
                info.app_manifest_checksum,
                app_manifest_stat.checksum,
                max_bytes,
            ),
        };
    }
    if (info.asset_count != asset_digest.count) {
        return .{
            .ok = false,
            .payload = try formatVerifyU32Mismatch(allocator, name, "asset_count", info.asset_count, asset_digest.count, max_bytes),
        };
    }
    if (info.asset_bytes != asset_digest.bytes) {
        return .{
            .ok = false,
            .payload = try formatVerifyU32Mismatch(allocator, name, "asset_bytes", info.asset_bytes, asset_digest.bytes, max_bytes),
        };
    }
    if (info.asset_tree_checksum != asset_digest.tree_checksum) {
        return .{
            .ok = false,
            .payload = try formatVerifyHex64Mismatch(
                allocator,
                name,
                "asset_tree_checksum",
                info.asset_tree_checksum,
                asset_digest.tree_checksum,
                max_bytes,
            ),
        };
    }

    const payload = try std.fmt.allocPrint(
        allocator,
        "name={s}\nstatus=ok\nroot={s}\nentrypoint={s}\nscript_bytes={d}\nscript_checksum={x:0>8}\napp_manifest={s}\napp_manifest_checksum={x:0>8}\nasset_root={s}\nasset_count={d}\nasset_bytes={d}\nasset_tree_checksum={x:0>16}\n",
        .{
            name,
            expected_root,
            expected_entrypoint,
            info.script_bytes,
            info.script_checksum,
            expected_app_manifest,
            info.app_manifest_checksum,
            expected_asset_root,
            info.asset_count,
            info.asset_bytes,
            info.asset_tree_checksum,
        },
    );
    errdefer allocator.free(payload);
    if (payload.len > max_bytes) return error.ResponseTooLarge;
    return .{ .ok = true, .payload = payload };
}

pub fn appManifestAlloc(allocator: std.mem.Allocator, name: []const u8, max_bytes: usize) Error![]u8 {
    var entrypoint_buf: [filesystem.max_path_len]u8 = undefined;
    const profile = try loadLaunchProfile(name, &entrypoint_buf);
    const manifest = try std.fmt.allocPrint(
        allocator,
        "name={s}\nentrypoint={s}\ndisplay_width={d}\ndisplay_height={d}\nconnector={s}\ntrust_bundle={s}\n",
        .{
            name,
            profile.entrypoint,
            profile.display_width,
            profile.display_height,
            connectorNameFromType(profile.connector_type),
            profile.trustBundle(),
        },
    );
    errdefer allocator.free(manifest);
    if (manifest.len > max_bytes) return error.ResponseTooLarge;
    return manifest;
}

pub fn configureDisplayMode(name: []const u8, width: u16, height: u16, tick: u64) Error!void {
    var entrypoint_buf: [filesystem.max_path_len]u8 = undefined;
    const profile = try loadLaunchProfile(name, &entrypoint_buf);
    try writeAppManifest(name, profile.entrypoint, width, height, profile.connector_type, profile.trustBundle(), tick);
    try refreshManifest(name, tick);
}

pub fn configureTrustBundle(name: []const u8, trust_bundle: []const u8, tick: u64) Error!void {
    var entrypoint_buf: [filesystem.max_path_len]u8 = undefined;
    const profile = try loadLaunchProfile(name, &entrypoint_buf);
    if (trust_bundle.len != 0) {
        var scratch: [512]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&scratch);
        _ = try trust_store.infoAlloc(fba.allocator(), trust_bundle, scratch.len);
    }
    try writeAppManifest(name, profile.entrypoint, profile.display_width, profile.display_height, profile.connector_type, trust_bundle, tick);
    try refreshManifest(name, tick);
}

pub fn configureConnectorType(name: []const u8, connector_type: u8, tick: u64) Error!void {
    _ = connectorNameFromType(connector_type);
    var entrypoint_buf: [filesystem.max_path_len]u8 = undefined;
    const profile = try loadLaunchProfile(name, &entrypoint_buf);
    try writeAppManifest(name, profile.entrypoint, profile.display_width, profile.display_height, connector_type, profile.trustBundle(), tick);
    try refreshManifest(name, tick);
}

pub fn loadLaunchProfile(name: []const u8, entrypoint_buffer: *[filesystem.max_path_len]u8) Error!LaunchProfile {
    if (!try packageExists(name)) return error.PackageNotFound;

    const default_entrypoint = try entrypointPath(name, entrypoint_buffer);
    var profile = LaunchProfile{
        .entrypoint = default_entrypoint,
        .display_width = default_display_width,
        .display_height = default_display_height,
        .connector_type = default_connector_type,
    };

    var app_path_buf: [filesystem.max_path_len]u8 = undefined;
    const app_path = try appManifestPath(name, &app_path_buf);

    var read_buffer: [256]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&read_buffer);
    const raw = filesystem.readFileAlloc(fba.allocator(), app_path, read_buffer.len) catch |err| switch (err) {
        error.FileNotFound => return profile,
        else => return err,
    };

    var lines = std.mem.splitScalar(u8, raw, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "entrypoint=")) {
            const value = line["entrypoint=".len..];
            if (!isValidEntrypoint(name, value)) return error.InvalidPackageMetadata;
            if (value.len > entrypoint_buffer.len) return error.InvalidPackageMetadata;
            @memcpy(entrypoint_buffer[0..value.len], value);
            profile.entrypoint = entrypoint_buffer[0..value.len];
            continue;
        }
        if (std.mem.startsWith(u8, line, "display_width=")) {
            profile.display_width = std.fmt.parseInt(u16, line["display_width=".len..], 10) catch return error.InvalidPackageMetadata;
            continue;
        }
        if (std.mem.startsWith(u8, line, "display_height=")) {
            profile.display_height = std.fmt.parseInt(u16, line["display_height=".len..], 10) catch return error.InvalidPackageMetadata;
            continue;
        }
        if (std.mem.startsWith(u8, line, "connector=")) {
            profile.connector_type = parseConnectorType(line["connector=".len..]) catch return error.InvalidPackageMetadata;
            continue;
        }
        if (std.mem.startsWith(u8, line, "trust_bundle=")) {
            const value = line["trust_bundle=".len..];
            if (value.len > trust_store.max_name_len) return error.InvalidPackageMetadata;
            @memset(&profile.trust_bundle_storage, 0);
            if (value.len > 0) {
                @memcpy(profile.trust_bundle_storage[0..value.len], value);
            }
            profile.trust_bundle_len = @intCast(value.len);
            continue;
        }
    }

    return profile;
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

pub fn releaseListAlloc(allocator: std.mem.Allocator, name: []const u8, max_bytes: usize) Error![]u8 {
    try validatePackageName(name);
    if (!try packageExists(name)) return error.PackageNotFound;
    var records: [filesystem.max_entries]ReleaseRecord = undefined;
    const record_count = try collectReleaseRecords(name, &records);
    sortReleaseRecordsOldestFirst(records[0..record_count]);

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    for (records[0..record_count]) |record| {
        const release_name = record.name();
        if (release_name.len == 0) continue;
        if (out.items.len + release_name.len + 1 > max_bytes) return error.ResponseTooLarge;
        try out.appendSlice(allocator, release_name);
        try out.append(allocator, '\n');
    }

    return out.toOwnedSlice(allocator);
}

pub fn releaseInfoAlloc(
    allocator: std.mem.Allocator,
    name: []const u8,
    release: []const u8,
    max_bytes: usize,
) Error![]u8 {
    try validatePackageName(name);
    try validateReleaseName(release);
    if (!try releaseExists(name, release)) return error.PackageReleaseNotFound;

    var metadata_path_buf: [filesystem.max_path_len]u8 = undefined;
    var manifest_path_buf: [filesystem.max_path_len]u8 = undefined;

    const metadata_path = try releaseMetadataPath(name, release, &metadata_path_buf);
    const manifest_path = try releaseManifestPath(name, release, &manifest_path_buf);

    var metadata_scratch: [512]u8 = undefined;
    var metadata_fba = std.heap.FixedBufferAllocator.init(&metadata_scratch);
    const metadata_raw = try filesystem.readFileAlloc(metadata_fba.allocator(), metadata_path, metadata_scratch.len);
    const metadata = try parseReleaseMetadata(metadata_raw);

    var manifest_scratch: [768]u8 = undefined;
    var manifest_fba = std.heap.FixedBufferAllocator.init(&manifest_scratch);
    const manifest_raw = try filesystem.readFileAlloc(manifest_fba.allocator(), manifest_path, manifest_scratch.len);
    const manifest = try parseManifestInfo(manifest_raw);

    var root_buf: [filesystem.max_path_len]u8 = undefined;
    const root = try releaseRootPath(name, release, &root_buf);
    const payload = try std.fmt.allocPrint(
        allocator,
        "name={s}\nrelease={s}\nsaved_seq={d}\nsaved_tick={d}\nroot={s}\nentrypoint={s}\nmanifest={s}\napp_manifest={s}\nscript_bytes={d}\nscript_checksum={x:0>8}\napp_manifest_checksum={x:0>8}\nasset_root={s}\nasset_count={d}\nasset_bytes={d}\nasset_tree_checksum={x:0>16}\n",
        .{
            if (metadata.name.len != 0) metadata.name else name,
            if (metadata.release.len != 0) metadata.release else release,
            metadata.saved_seq,
            metadata.saved_tick,
            root,
            manifest.entrypoint,
            manifest_path,
            manifest.app_manifest,
            manifest.script_bytes,
            manifest.script_checksum,
            manifest.app_manifest_checksum,
            manifest.asset_root,
            manifest.asset_count,
            manifest.asset_bytes,
            manifest.asset_tree_checksum,
        },
    );
    errdefer allocator.free(payload);
    if (payload.len > max_bytes) return error.ResponseTooLarge;
    return payload;
}

pub fn releaseExistsAlloc(name: []const u8, release: []const u8) Error!bool {
    try validatePackageName(name);
    try validateReleaseName(release);
    return releaseExists(name, release);
}

pub fn channelListAlloc(allocator: std.mem.Allocator, name: []const u8, max_bytes: usize) Error![]u8 {
    try validatePackageName(name);
    if (!try packageExists(name)) return error.PackageNotFound;
    var records: [filesystem.max_entries]ReleaseRecord = undefined;
    const record_count = try collectChannelRecords(name, &records);
    sortReleaseRecordsOldestFirst(records[0..record_count]);

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    for (records[0..record_count]) |record| {
        const channel_name = record.name();
        if (channel_name.len == 0) continue;
        if (out.items.len + channel_name.len + 1 > max_bytes) return error.ResponseTooLarge;
        try out.appendSlice(allocator, channel_name);
        try out.append(allocator, '\n');
    }

    return out.toOwnedSlice(allocator);
}

pub fn setPackageReleaseChannel(name: []const u8, channel: []const u8, release: []const u8, tick: u64) Error!void {
    try validatePackageName(name);
    try validateChannelName(channel);
    try validateReleaseName(release);
    if (!try releaseExists(name, release)) return error.PackageReleaseNotFound;

    var channels_root_buf: [filesystem.max_path_len]u8 = undefined;
    var channel_path_buf: [filesystem.max_path_len]u8 = undefined;
    try filesystem.createDirPath(channelsRootPath(name, &channels_root_buf));
    try filesystem.writeFile(try channelPath(name, channel, &channel_path_buf), release, tick);
}

pub fn activatePackageReleaseChannel(name: []const u8, channel: []const u8, tick: u64) Error!void {
    var scratch: [128]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&scratch);
    const release = try readChannelTargetAlloc(fba.allocator(), name, channel, max_release_len);
    try activatePackageRelease(name, release, tick);
}

pub fn channelInfoAlloc(allocator: std.mem.Allocator, name: []const u8, channel: []const u8, max_bytes: usize) Error![]u8 {
    try validatePackageName(name);
    try validateChannelName(channel);
    if (!try packageExists(name)) return error.PackageNotFound;
    const release = try readChannelTargetAlloc(allocator, name, channel, max_release_len);
    defer allocator.free(release);

    const payload = try std.fmt.allocPrint(allocator, "name={s}\nchannel={s}\nrelease={s}\n", .{ name, channel, release });
    errdefer allocator.free(payload);
    if (payload.len > max_bytes) return error.ResponseTooLarge;
    return payload;
}

pub fn snapshotPackageRelease(name: []const u8, release: []const u8, tick: u64) Error!void {
    try validatePackageName(name);
    try validateReleaseName(release);
    if (!try packageExists(name)) return error.PackageNotFound;
    if (try releaseExists(name, release)) return error.PackageReleaseAlreadyExists;

    const saved_seq = try nextReleaseSequence(name);
    try createReleaseDirectories(name, release);

    var canonical_entrypoint_buf: [filesystem.max_path_len]u8 = undefined;
    var canonical_manifest_buf: [filesystem.max_path_len]u8 = undefined;
    var canonical_app_manifest_buf: [filesystem.max_path_len]u8 = undefined;
    var canonical_assets_buf: [filesystem.max_path_len]u8 = undefined;
    var release_entrypoint_buf: [filesystem.max_path_len]u8 = undefined;
    var release_manifest_buf: [filesystem.max_path_len]u8 = undefined;
    var release_app_manifest_buf: [filesystem.max_path_len]u8 = undefined;
    var release_assets_buf: [filesystem.max_path_len]u8 = undefined;

    try copyFilePath(
        try entrypointPath(name, &canonical_entrypoint_buf),
        try releaseEntrypointPath(name, release, &release_entrypoint_buf),
        tick,
    );
    try copyFilePath(
        try manifestPath(name, &canonical_manifest_buf),
        try releaseManifestPath(name, release, &release_manifest_buf),
        tick,
    );
    try copyFilePath(
        try appManifestPath(name, &canonical_app_manifest_buf),
        try releaseAppManifestPath(name, release, &release_app_manifest_buf),
        tick,
    );
    try copyTreeUnderPrefix(
        try assetsPath(name, &canonical_assets_buf),
        try releaseAssetsPath(name, release, &release_assets_buf),
        tick,
    );
    try writeReleaseMetadata(name, release, saved_seq, tick);
}

pub fn activatePackageRelease(name: []const u8, release: []const u8, tick: u64) Error!void {
    try validatePackageName(name);
    try validateReleaseName(release);
    if (!try releaseExists(name, release)) return error.PackageReleaseNotFound;

    try deleteActivePackageLayout(name, tick);

    var root_buf: [filesystem.max_path_len]u8 = undefined;
    var bin_buf: [filesystem.max_path_len]u8 = undefined;
    var meta_buf: [filesystem.max_path_len]u8 = undefined;
    var assets_buf: [filesystem.max_path_len]u8 = undefined;
    try filesystem.createDirPath(packageRootPath(name, &root_buf));
    try filesystem.createDirPath(packageBinPath(name, &bin_buf));
    try filesystem.createDirPath(packageMetaPath(name, &meta_buf));
    try filesystem.createDirPath(packageAssetsPath(name, &assets_buf));

    var canonical_entrypoint_buf: [filesystem.max_path_len]u8 = undefined;
    var canonical_app_manifest_buf: [filesystem.max_path_len]u8 = undefined;
    var canonical_assets_buf: [filesystem.max_path_len]u8 = undefined;
    var release_entrypoint_buf: [filesystem.max_path_len]u8 = undefined;
    var release_app_manifest_buf: [filesystem.max_path_len]u8 = undefined;
    var release_assets_buf: [filesystem.max_path_len]u8 = undefined;

    try copyFilePath(
        try releaseEntrypointPath(name, release, &release_entrypoint_buf),
        try entrypointPath(name, &canonical_entrypoint_buf),
        tick,
    );
    try copyFilePath(
        try releaseAppManifestPath(name, release, &release_app_manifest_buf),
        try appManifestPath(name, &canonical_app_manifest_buf),
        tick,
    );
    try copyTreeUnderPrefix(
        try releaseAssetsPath(name, release, &release_assets_buf),
        try assetsPath(name, &canonical_assets_buf),
        tick,
    );
    try refreshManifest(name, tick);
}

pub fn deletePackageRelease(name: []const u8, release: []const u8, tick: u64) Error!void {
    try validatePackageName(name);
    try validateReleaseName(release);
    if (!try releaseExists(name, release)) return error.PackageReleaseNotFound;

    var root_buf: [filesystem.max_path_len]u8 = undefined;
    try filesystem.deleteTree(try releaseRootPath(name, release, &root_buf), tick);
}

pub fn prunePackageReleases(name: []const u8, keep: usize, tick: u64) Error!ReleasePruneResult {
    try validatePackageName(name);
    if (!try packageExists(name)) return error.PackageNotFound;

    var records: [filesystem.max_entries]ReleaseRecord = undefined;
    const record_count = try collectReleaseRecords(name, &records);
    sortReleaseRecordsNewestFirst(records[0..record_count]);

    var deleted_count: u32 = 0;
    var index = keep;
    while (index < record_count) : (index += 1) {
        try deletePackageRelease(name, records[index].name(), tick);
        deleted_count += 1;
    }

    return .{
        .kept_count = @intCast(@min(keep, record_count)),
        .deleted_count = deleted_count,
    };
}

pub fn validatePackageName(name: []const u8) Error!void {
    if (name.len == 0 or name.len > max_name_len) return error.InvalidPackageName;
    for (name) |char| {
        if (std.ascii.isAlphanumeric(char) or char == '-' or char == '_' or char == '.') continue;
        return error.InvalidPackageName;
    }
}

pub fn validateReleaseName(name: []const u8) Error!void {
    if (name.len == 0 or name.len > max_release_len) return error.InvalidReleaseName;
    for (name) |char| {
        if (std.ascii.isAlphanumeric(char) or char == '-' or char == '_' or char == '.') continue;
        return error.InvalidReleaseName;
    }
}

pub fn validateChannelName(name: []const u8) Error!void {
    if (name.len == 0 or name.len > max_channel_len) return error.InvalidChannelName;
    for (name) |char| {
        if (std.ascii.isAlphanumeric(char) or char == '-' or char == '_' or char == '.') continue;
        return error.InvalidChannelName;
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

fn releasesRootPath(name: []const u8, buffer: *[filesystem.max_path_len]u8) []const u8 {
    return std.fmt.bufPrint(buffer, "/packages/{s}/releases", .{name}) catch unreachable;
}

fn channelsRootPath(name: []const u8, buffer: *[filesystem.max_path_len]u8) []const u8 {
    return std.fmt.bufPrint(buffer, "/packages/{s}/channels", .{name}) catch unreachable;
}

fn channelPath(name: []const u8, channel: []const u8, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    try validatePackageName(name);
    try validateChannelName(channel);
    return std.fmt.bufPrint(buffer, "/packages/{s}/channels/{s}.txt", .{ name, channel }) catch error.InvalidPath;
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

fn releaseRootPath(name: []const u8, release: []const u8, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    try validatePackageName(name);
    try validateReleaseName(release);
    return std.fmt.bufPrint(buffer, "/packages/{s}/releases/{s}", .{ name, release }) catch error.InvalidPath;
}

fn releaseBinPath(name: []const u8, release: []const u8, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    try validatePackageName(name);
    try validateReleaseName(release);
    return std.fmt.bufPrint(buffer, "/packages/{s}/releases/{s}/bin", .{ name, release }) catch error.InvalidPath;
}

fn releaseMetaPath(name: []const u8, release: []const u8, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    try validatePackageName(name);
    try validateReleaseName(release);
    return std.fmt.bufPrint(buffer, "/packages/{s}/releases/{s}/meta", .{ name, release }) catch error.InvalidPath;
}

fn releaseAssetsPath(name: []const u8, release: []const u8, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    try validatePackageName(name);
    try validateReleaseName(release);
    return std.fmt.bufPrint(buffer, "/packages/{s}/releases/{s}/assets", .{ name, release }) catch error.InvalidPath;
}

fn releaseMetadataPath(name: []const u8, release: []const u8, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    try validatePackageName(name);
    try validateReleaseName(release);
    return std.fmt.bufPrint(buffer, "/packages/{s}/releases/{s}/meta/release.txt", .{ name, release }) catch error.InvalidPath;
}

fn releaseEntrypointPath(name: []const u8, release: []const u8, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    try validatePackageName(name);
    try validateReleaseName(release);
    return std.fmt.bufPrint(buffer, "/packages/{s}/releases/{s}/bin/main.oc", .{ name, release }) catch error.InvalidPath;
}

fn releaseManifestPath(name: []const u8, release: []const u8, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    try validatePackageName(name);
    try validateReleaseName(release);
    return std.fmt.bufPrint(buffer, "/packages/{s}/releases/{s}/meta/package.txt", .{ name, release }) catch error.InvalidPath;
}

fn releaseAppManifestPath(name: []const u8, release: []const u8, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    try validatePackageName(name);
    try validateReleaseName(release);
    return std.fmt.bufPrint(buffer, "/packages/{s}/releases/{s}/meta/app.txt", .{ name, release }) catch error.InvalidPath;
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

fn releaseExists(name: []const u8, release: []const u8) Error!bool {
    var entrypoint_buf: [filesystem.max_path_len]u8 = undefined;
    const entrypoint = try releaseEntrypointPath(name, release, &entrypoint_buf);
    _ = filesystem.statSummary(entrypoint) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    return true;
}

fn nextReleaseSequence(name: []const u8) Error!u32 {
    var records: [filesystem.max_entries]ReleaseRecord = undefined;
    const record_count = try collectReleaseRecords(name, &records);
    var max_seq: u32 = 0;
    for (records[0..record_count]) |record| {
        max_seq = @max(max_seq, record.saved_seq);
    }
    return max_seq + 1;
}

const AssetDigest = struct {
    count: u32 = 0,
    bytes: u32 = 0,
    tree_checksum: u64 = 0,
};

fn packageAssetDigest(name: []const u8) Error!AssetDigest {
    var assets_buf: [filesystem.max_path_len]u8 = undefined;
    const assets_root = try assetsPath(name, &assets_buf);
    var digest: AssetDigest = .{};
    var matching_indices: [filesystem.max_entries]u32 = undefined;
    var matching_count: usize = 0;

    var idx: u32 = 0;
    while (idx < filesystem.max_entries) : (idx += 1) {
        const record = filesystem.entry(idx);
        if (record.kind != abi.filesystem_kind_file) continue;
        const path = record.path[0..record.path_len];
        if (!std.mem.startsWith(u8, path, assets_root)) continue;
        if (path.len <= assets_root.len or path[assets_root.len] != '/') continue;
        matching_indices[matching_count] = idx;
        matching_count += 1;
        digest.count +%= 1;
        digest.bytes +%= record.byte_len;
    }

    std.mem.sort(u32, matching_indices[0..matching_count], {}, lessAssetRecordPath);

    var hasher = std.hash.Wyhash.init(0);
    for (matching_indices[0..matching_count]) |record_index| {
        const record = filesystem.entry(record_index);
        const path = record.path[0..record.path_len];
        hasher.update(path);

        var size_bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &size_bytes, record.byte_len, .little);
        hasher.update(&size_bytes);

        var checksum_bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &checksum_bytes, record.checksum, .little);
        hasher.update(&checksum_bytes);
    }
    digest.tree_checksum = hasher.final();
    return digest;
}

fn refreshManifest(name: []const u8, tick: u64) Error!void {
    var root_buf: [filesystem.max_path_len]u8 = undefined;
    var entrypoint_buf: [filesystem.max_path_len]u8 = undefined;
    var manifest_buf: [filesystem.max_path_len]u8 = undefined;
    var app_manifest_buf: [filesystem.max_path_len]u8 = undefined;
    var assets_buf: [filesystem.max_path_len]u8 = undefined;

    const root = packageRootPath(name, &root_buf);
    const entrypoint = try entrypointPath(name, &entrypoint_buf);
    const manifest = try manifestPath(name, &manifest_buf);
    const app_manifest = try appManifestPath(name, &app_manifest_buf);
    const assets_root = try assetsPath(name, &assets_buf);
    const script_stat = filesystem.statSummary(entrypoint) catch |err| switch (err) {
        error.FileNotFound => return error.PackageNotFound,
        else => return err,
    };
    const app_manifest_stat = filesystem.statSummary(app_manifest) catch |err| switch (err) {
        error.FileNotFound => return error.PackageNotFound,
        else => return err,
    };
    const digest = try packageAssetDigest(name);
    var launch_entrypoint_buf: [filesystem.max_path_len]u8 = undefined;
    const profile = try loadLaunchProfile(name, &launch_entrypoint_buf);

    var metadata: [512]u8 = undefined;
    const manifest_body = std.fmt.bufPrint(
        &metadata,
        "name={s}\nroot={s}\nentrypoint={s}\napp_manifest={s}\nscript_bytes={d}\nscript_checksum={x:0>8}\napp_manifest_checksum={x:0>8}\ndisplay_width={d}\ndisplay_height={d}\nconnector={s}\ntrust_bundle={s}\nasset_root={s}\nasset_count={d}\nasset_bytes={d}\nasset_tree_checksum={x:0>16}\n",
        .{
            name,
            root,
            entrypoint,
            app_manifest,
            script_stat.size,
            script_stat.checksum,
            app_manifest_stat.checksum,
            profile.display_width,
            profile.display_height,
            connectorNameFromType(profile.connector_type),
            profile.trustBundle(),
            assets_root,
            digest.count,
            digest.bytes,
            digest.tree_checksum,
        },
    ) catch return error.InvalidPath;
    try filesystem.writeFile(manifest, manifest_body, tick);
}

fn createReleaseDirectories(name: []const u8, release: []const u8) Error!void {
    var releases_root_buf: [filesystem.max_path_len]u8 = undefined;
    var release_root_buf: [filesystem.max_path_len]u8 = undefined;
    var release_bin_buf: [filesystem.max_path_len]u8 = undefined;
    var release_meta_buf: [filesystem.max_path_len]u8 = undefined;
    var release_assets_buf: [filesystem.max_path_len]u8 = undefined;

    try filesystem.createDirPath(releasesRootPath(name, &releases_root_buf));
    try filesystem.createDirPath(try releaseRootPath(name, release, &release_root_buf));
    try filesystem.createDirPath(try releaseBinPath(name, release, &release_bin_buf));
    try filesystem.createDirPath(try releaseMetaPath(name, release, &release_meta_buf));
    try filesystem.createDirPath(try releaseAssetsPath(name, release, &release_assets_buf));
}

fn writeReleaseMetadata(name: []const u8, release: []const u8, saved_seq: u32, saved_tick: u64) Error!void {
    var metadata_path_buf: [filesystem.max_path_len]u8 = undefined;
    const metadata_path = try releaseMetadataPath(name, release, &metadata_path_buf);

    var body: [256]u8 = undefined;
    const metadata = std.fmt.bufPrint(
        &body,
        "name={s}\nrelease={s}\nsaved_seq={d}\nsaved_tick={d}\n",
        .{ name, release, saved_seq, saved_tick },
    ) catch return error.InvalidPath;
    try filesystem.writeFile(metadata_path, metadata, saved_tick);
}

fn deleteActivePackageLayout(name: []const u8, tick: u64) Error!void {
    var bin_buf: [filesystem.max_path_len]u8 = undefined;
    var meta_buf: [filesystem.max_path_len]u8 = undefined;
    var assets_buf: [filesystem.max_path_len]u8 = undefined;
    const active_paths = [_][]const u8{
        packageBinPath(name, &bin_buf),
        packageMetaPath(name, &meta_buf),
        packageAssetsPath(name, &assets_buf),
    };
    for (active_paths) |active_path| {
        filesystem.deleteTree(active_path, tick) catch |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        };
    }
}

fn copyFilePath(source_path: []const u8, destination_path: []const u8, tick: u64) Error!void {
    var copy_scratch: [release_copy_max_bytes]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&copy_scratch);
    const data = try filesystem.readFileAlloc(fba.allocator(), source_path, copy_scratch.len);
    try filesystem.createDirPath(parentSlice(destination_path));
    try filesystem.writeFile(destination_path, data, tick);
}

fn copyTreeUnderPrefix(source_prefix: []const u8, destination_prefix: []const u8, tick: u64) Error!void {
    try filesystem.createDirPath(destination_prefix);
    var saw_matching_entry = false;

    var idx: u32 = 0;
    while (idx < filesystem.max_entries) : (idx += 1) {
        const record = filesystem.entry(idx);
        if (record.kind != abi.filesystem_kind_directory) continue;
        const path = record.path[0..record.path_len];
        const relative = relativeTreePath(source_prefix, path) orelse continue;
        saw_matching_entry = true;
        if (relative.len == 0) continue;

        var destination_buf: [filesystem.max_path_len]u8 = undefined;
        const destination_path = std.fmt.bufPrint(&destination_buf, "{s}/{s}", .{ destination_prefix, relative }) catch return error.InvalidPath;
        try filesystem.createDirPath(destination_path);
    }

    idx = 0;
    while (idx < filesystem.max_entries) : (idx += 1) {
        const record = filesystem.entry(idx);
        if (record.kind != abi.filesystem_kind_file) continue;
        const path = record.path[0..record.path_len];
        const relative = relativeTreePath(source_prefix, path) orelse continue;
        saw_matching_entry = true;

        var destination_buf: [filesystem.max_path_len]u8 = undefined;
        const destination_path = std.fmt.bufPrint(&destination_buf, "{s}/{s}", .{ destination_prefix, relative }) catch return error.InvalidPath;
        try copyFilePath(path, destination_path, tick);
    }

    if (!saw_matching_entry) {
        _ = filesystem.statSummary(source_prefix) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return err,
        };
    }
}

fn relativeTreePath(root: []const u8, candidate: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, candidate, root)) return null;
    if (candidate.len == root.len) return "";
    if (candidate.len <= root.len or candidate[root.len] != '/') return null;
    return candidate[root.len + 1 ..];
}

fn fileListingName(line: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, line, "file ")) return null;
    const remainder = line["file ".len..];
    const last_space = std.mem.lastIndexOfScalar(u8, remainder, ' ') orelse return null;
    if (last_space == 0) return null;
    return remainder[0..last_space];
}

fn readChannelTargetAlloc(allocator: std.mem.Allocator, name: []const u8, channel: []const u8, max_bytes: usize) Error![]u8 {
    try validatePackageName(name);
    try validateChannelName(channel);
    if (!try packageExists(name)) return error.PackageNotFound;

    var channel_path_buf: [filesystem.max_path_len]u8 = undefined;
    const raw = filesystem.readFileAlloc(allocator, try channelPath(name, channel, &channel_path_buf), max_bytes) catch |err| switch (err) {
        error.FileNotFound => return error.PackageChannelNotFound,
        else => return err,
    };
    errdefer allocator.free(raw);
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    try validateReleaseName(trimmed);
    if (!try releaseExists(name, trimmed)) return error.PackageReleaseNotFound;
    if (trimmed.len == raw.len) return raw;
    const normalized = try allocator.dupe(u8, trimmed);
    allocator.free(raw);
    return normalized;
}

fn collectReleaseRecords(name: []const u8, records: *[filesystem.max_entries]ReleaseRecord) Error!usize {
    var releases_buf: [filesystem.max_path_len]u8 = undefined;
    const releases_root = releasesRootPath(name, &releases_buf);

    var count: usize = 0;
    var idx: u32 = 0;
    while (idx < filesystem.max_entries) : (idx += 1) {
        const record = filesystem.entry(idx);
        if (record.kind != abi.filesystem_kind_directory) continue;
        const path = record.path[0..record.path_len];
        const release_name = directChildName(releases_root, path) orelse continue;
        if (release_name.len == 0) continue;
        if (findReleaseRecord(records[0..count], release_name) != null) continue;

        var saved_seq: u32 = 0;
        var metadata_path_buf: [filesystem.max_path_len]u8 = undefined;
        const metadata_path = try releaseMetadataPath(name, release_name, &metadata_path_buf);
        var metadata_scratch: [256]u8 = undefined;
        var metadata_fba = std.heap.FixedBufferAllocator.init(&metadata_scratch);
        const metadata_raw = filesystem.readFileAlloc(metadata_fba.allocator(), metadata_path, metadata_scratch.len) catch |err| switch (err) {
            error.FileNotFound => null,
            else => return err,
        };
        if (metadata_raw) |raw| {
            const metadata = try parseReleaseMetadata(raw);
            saved_seq = metadata.saved_seq;
        }

        records[count] = .{
            .name_len = release_name.len,
            .saved_seq = saved_seq,
        };
        @memcpy(records[count].name_storage[0..release_name.len], release_name);
        count += 1;
    }

    return count;
}

fn collectChannelRecords(name: []const u8, records: *[filesystem.max_entries]ReleaseRecord) Error!usize {
    var channels_root_buf: [filesystem.max_path_len]u8 = undefined;
    const channels_root = channelsRootPath(name, &channels_root_buf);

    var count: usize = 0;
    var idx: u32 = 0;
    while (idx < filesystem.max_entries) : (idx += 1) {
        const record = filesystem.entry(idx);
        if (record.kind != abi.filesystem_kind_file) continue;
        const path = record.path[0..record.path_len];
        const channel_file = directChildName(channels_root, path) orelse continue;
        if (!std.mem.endsWith(u8, channel_file, ".txt")) continue;
        const channel_name = channel_file[0 .. channel_file.len - ".txt".len];
        if (channel_name.len == 0) continue;
        if (findReleaseRecord(records[0..count], channel_name) != null) continue;

        records[count].name_len = channel_name.len;
        @memset(&records[count].name_storage, 0);
        @memcpy(records[count].name_storage[0..channel_name.len], channel_name);
        records[count].saved_seq = 0;
        count += 1;
    }

    return count;
}

fn findReleaseRecord(records: []const ReleaseRecord, release_name: []const u8) ?usize {
    for (records, 0..) |record, index| {
        if (std.mem.eql(u8, record.name(), release_name)) return index;
    }
    return null;
}

fn directChildName(parent: []const u8, candidate: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, candidate, parent)) return null;
    if (candidate.len <= parent.len or candidate[parent.len] != '/') return null;
    const rest = candidate[parent.len + 1 ..];
    if (rest.len == 0) return null;
    const end_index = std.mem.indexOfScalar(u8, rest, '/') orelse rest.len;
    if (end_index == 0) return null;
    return rest[0..end_index];
}

fn sortReleaseRecordsOldestFirst(records: []ReleaseRecord) void {
    var i: usize = 0;
    while (i < records.len) : (i += 1) {
        var best_index = i;
        var j: usize = i + 1;
        while (j < records.len) : (j += 1) {
            if (records[j].saved_seq < records[best_index].saved_seq) {
                best_index = j;
                continue;
            }
            if (records[j].saved_seq == records[best_index].saved_seq and std.mem.lessThan(u8, records[j].name(), records[best_index].name())) {
                best_index = j;
            }
        }
        if (best_index != i) std.mem.swap(ReleaseRecord, &records[i], &records[best_index]);
    }
}

fn sortReleaseRecordsNewestFirst(records: []ReleaseRecord) void {
    var i: usize = 0;
    while (i < records.len) : (i += 1) {
        var best_index = i;
        var j: usize = i + 1;
        while (j < records.len) : (j += 1) {
            if (records[j].saved_seq > records[best_index].saved_seq) {
                best_index = j;
                continue;
            }
            if (records[j].saved_seq == records[best_index].saved_seq and std.mem.lessThan(u8, records[best_index].name(), records[j].name())) {
                best_index = j;
            }
        }
        if (best_index != i) std.mem.swap(ReleaseRecord, &records[i], &records[best_index]);
    }
}

fn lessAssetRecordPath(_: void, lhs_index: u32, rhs_index: u32) bool {
    const lhs = filesystem.entry(lhs_index);
    const rhs = filesystem.entry(rhs_index);
    return std.mem.lessThan(u8, lhs.path[0..lhs.path_len], rhs.path[0..rhs.path_len]);
}

fn parseManifestInfo(raw: []const u8) Error!ManifestInfo {
    var info: ManifestInfo = .{};
    var lines = std.mem.splitScalar(u8, raw, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "root=")) {
            info.root = line["root=".len..];
            continue;
        }
        if (std.mem.startsWith(u8, line, "entrypoint=")) {
            info.entrypoint = line["entrypoint=".len..];
            continue;
        }
        if (std.mem.startsWith(u8, line, "app_manifest=")) {
            info.app_manifest = line["app_manifest=".len..];
            continue;
        }
        if (std.mem.startsWith(u8, line, "script_bytes=")) {
            info.script_bytes = std.fmt.parseInt(u32, line["script_bytes=".len..], 10) catch return error.InvalidPackageMetadata;
            continue;
        }
        if (std.mem.startsWith(u8, line, "script_checksum=")) {
            info.script_checksum = std.fmt.parseInt(u32, line["script_checksum=".len..], 16) catch return error.InvalidPackageMetadata;
            continue;
        }
        if (std.mem.startsWith(u8, line, "app_manifest_checksum=")) {
            info.app_manifest_checksum = std.fmt.parseInt(u32, line["app_manifest_checksum=".len..], 16) catch return error.InvalidPackageMetadata;
            continue;
        }
        if (std.mem.startsWith(u8, line, "asset_root=")) {
            info.asset_root = line["asset_root=".len..];
            continue;
        }
        if (std.mem.startsWith(u8, line, "asset_count=")) {
            info.asset_count = std.fmt.parseInt(u32, line["asset_count=".len..], 10) catch return error.InvalidPackageMetadata;
            continue;
        }
        if (std.mem.startsWith(u8, line, "asset_bytes=")) {
            info.asset_bytes = std.fmt.parseInt(u32, line["asset_bytes=".len..], 10) catch return error.InvalidPackageMetadata;
            continue;
        }
        if (std.mem.startsWith(u8, line, "asset_tree_checksum=")) {
            info.asset_tree_checksum = std.fmt.parseInt(u64, line["asset_tree_checksum=".len..], 16) catch return error.InvalidPackageMetadata;
            continue;
        }
    }

    if (info.root.len == 0 or info.entrypoint.len == 0 or info.app_manifest.len == 0 or info.asset_root.len == 0) {
        return error.InvalidPackageMetadata;
    }
    return info;
}

fn parseReleaseMetadata(raw: []const u8) Error!ReleaseMetadata {
    var metadata: ReleaseMetadata = .{};
    var lines = std.mem.splitScalar(u8, raw, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "name=")) {
            metadata.name = line["name=".len..];
            continue;
        }
        if (std.mem.startsWith(u8, line, "release=")) {
            metadata.release = line["release=".len..];
            continue;
        }
        if (std.mem.startsWith(u8, line, "saved_seq=")) {
            metadata.saved_seq = std.fmt.parseInt(u32, line["saved_seq=".len..], 10) catch return error.InvalidPackageMetadata;
            continue;
        }
        if (std.mem.startsWith(u8, line, "saved_tick=")) {
            metadata.saved_tick = std.fmt.parseInt(u64, line["saved_tick=".len..], 10) catch return error.InvalidPackageMetadata;
            continue;
        }
    }
    return metadata;
}

fn formatVerifyPathMismatch(
    allocator: std.mem.Allocator,
    name: []const u8,
    field: []const u8,
    expected: []const u8,
    actual: []const u8,
    max_bytes: usize,
) Error![]u8 {
    const payload = try std.fmt.allocPrint(
        allocator,
        "name={s}\nstatus=mismatch\nfield={s}\nexpected={s}\nactual={s}\n",
        .{ name, field, expected, actual },
    );
    errdefer allocator.free(payload);
    if (payload.len > max_bytes) return error.ResponseTooLarge;
    return payload;
}

fn formatVerifyU32Mismatch(
    allocator: std.mem.Allocator,
    name: []const u8,
    field: []const u8,
    expected: u32,
    actual: u32,
    max_bytes: usize,
) Error![]u8 {
    const payload = try std.fmt.allocPrint(
        allocator,
        "name={s}\nstatus=mismatch\nfield={s}\nexpected={d}\nactual={d}\n",
        .{ name, field, expected, actual },
    );
    errdefer allocator.free(payload);
    if (payload.len > max_bytes) return error.ResponseTooLarge;
    return payload;
}

fn formatVerifyHex32Mismatch(
    allocator: std.mem.Allocator,
    name: []const u8,
    field: []const u8,
    expected: u32,
    actual: u32,
    max_bytes: usize,
) Error![]u8 {
    const payload = try std.fmt.allocPrint(
        allocator,
        "name={s}\nstatus=mismatch\nfield={s}\nexpected={x:0>8}\nactual={x:0>8}\n",
        .{ name, field, expected, actual },
    );
    errdefer allocator.free(payload);
    if (payload.len > max_bytes) return error.ResponseTooLarge;
    return payload;
}

fn formatVerifyHex64Mismatch(
    allocator: std.mem.Allocator,
    name: []const u8,
    field: []const u8,
    expected: u64,
    actual: u64,
    max_bytes: usize,
) Error![]u8 {
    const payload = try std.fmt.allocPrint(
        allocator,
        "name={s}\nstatus=mismatch\nfield={s}\nexpected={x:0>16}\nactual={x:0>16}\n",
        .{ name, field, expected, actual },
    );
    errdefer allocator.free(payload);
    if (payload.len > max_bytes) return error.ResponseTooLarge;
    return payload;
}

fn refreshAppManifest(name: []const u8, tick: u64) Error!void {
    var entrypoint_buf: [filesystem.max_path_len]u8 = undefined;
    const entrypoint = try entrypointPath(name, &entrypoint_buf);
    try writeAppManifest(name, entrypoint, default_display_width, default_display_height, default_connector_type, "", tick);
}

fn writeAppManifest(name: []const u8, entrypoint: []const u8, width: u16, height: u16, connector_type: u8, trust_bundle: []const u8, tick: u64) Error!void {
    var app_manifest_buf: [filesystem.max_path_len]u8 = undefined;
    const app_manifest = try appManifestPath(name, &app_manifest_buf);
    var metadata: [256]u8 = undefined;
    const body = std.fmt.bufPrint(
        &metadata,
        "name={s}\nentrypoint={s}\ndisplay_width={d}\ndisplay_height={d}\nconnector={s}\ntrust_bundle={s}\n",
        .{ name, entrypoint, width, height, connectorNameFromType(connector_type), trust_bundle },
    ) catch return error.InvalidPath;
    try filesystem.writeFile(app_manifest, body, tick);
}

pub fn connectorNameFromType(connector_type: u8) []const u8 {
    return switch (connector_type) {
        abi.display_connector_none => "none",
        abi.display_connector_virtual => "virtual",
        abi.display_connector_displayport => "displayport",
        abi.display_connector_hdmi => "hdmi",
        abi.display_connector_embedded_displayport => "embedded-displayport",
        else => return "unknown",
    };
}

pub fn parseConnectorType(name: []const u8) Error!u8 {
    if (std.ascii.eqlIgnoreCase(name, "none")) return abi.display_connector_none;
    if (std.ascii.eqlIgnoreCase(name, "virtual")) return abi.display_connector_virtual;
    if (std.ascii.eqlIgnoreCase(name, "displayport") or std.ascii.eqlIgnoreCase(name, "dp")) return abi.display_connector_displayport;
    if (std.ascii.eqlIgnoreCase(name, "hdmi")) return abi.display_connector_hdmi;
    if (std.ascii.eqlIgnoreCase(name, "embedded-displayport") or std.ascii.eqlIgnoreCase(name, "edp")) return abi.display_connector_embedded_displayport;
    return error.InvalidDisplayConnector;
}

fn isValidEntrypoint(name: []const u8, entrypoint: []const u8) bool {
    var prefix_buf: [filesystem.max_path_len]u8 = undefined;
    const prefix = std.fmt.bufPrint(&prefix_buf, "/packages/{s}/", .{name}) catch return false;
    return std.mem.startsWith(u8, entrypoint, prefix) and entrypoint.len < filesystem.max_path_len;
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
    var app_manifest_buf: [filesystem.max_path_len]u8 = undefined;
    const entrypoint = try entrypointPath("demo", &entrypoint_buf);
    const manifest = try manifestPath("demo", &manifest_buf);
    const app_manifest = try appManifestPath("demo", &app_manifest_buf);

    const script = try filesystem.readFileAlloc(std.testing.allocator, entrypoint, 64);
    defer std.testing.allocator.free(script);
    try std.testing.expectEqualStrings("echo package-ok", script);

    const metadata = try filesystem.readFileAlloc(std.testing.allocator, manifest, 512);
    defer std.testing.allocator.free(metadata);
    try std.testing.expect(std.mem.indexOf(u8, metadata, "name=demo") != null);
    try std.testing.expect(std.mem.indexOf(u8, metadata, "root=/packages/demo") != null);
    try std.testing.expect(std.mem.indexOf(u8, metadata, entrypoint) != null);
    try std.testing.expect(std.mem.indexOf(u8, metadata, app_manifest) != null);
    try std.testing.expect(std.mem.indexOf(u8, metadata, "script_bytes=15") != null);
    try std.testing.expect(std.mem.indexOf(u8, metadata, "script_checksum=") != null);
    try std.testing.expect(std.mem.indexOf(u8, metadata, "app_manifest_checksum=") != null);
    try std.testing.expect(std.mem.indexOf(u8, metadata, "display_width=640") != null);
    try std.testing.expect(std.mem.indexOf(u8, metadata, "display_height=400") != null);
    try std.testing.expect(std.mem.indexOf(u8, metadata, "connector=none") != null);
    try std.testing.expect(std.mem.indexOf(u8, metadata, "trust_bundle=") != null);
    try std.testing.expect(std.mem.indexOf(u8, metadata, "asset_root=/packages/demo/assets") != null);
    try std.testing.expect(std.mem.indexOf(u8, metadata, "asset_count=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, metadata, "asset_bytes=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, metadata, "asset_tree_checksum=") != null);

    const app = try appManifestAlloc(std.testing.allocator, "demo", 256);
    defer std.testing.allocator.free(app);
    try std.testing.expect(std.mem.indexOf(u8, app, "entrypoint=/packages/demo/bin/main.oc") != null);
    try std.testing.expect(std.mem.indexOf(u8, app, "display_width=640") != null);
    try std.testing.expect(std.mem.indexOf(u8, app, "display_height=400") != null);
    try std.testing.expect(std.mem.indexOf(u8, app, "connector=none") != null);
    try std.testing.expect(std.mem.indexOf(u8, app, "trust_bundle=") != null);

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

    const manifest = try manifestAlloc(std.testing.allocator, "info-demo", 512);
    defer std.testing.allocator.free(manifest);

    try std.testing.expect(std.mem.indexOf(u8, manifest, "name=info-demo") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "root=/packages/info-demo") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "/packages/info-demo/bin/main.oc") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "app_manifest=/packages/info-demo/meta/app.txt") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "script_bytes=14") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "script_checksum=") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "app_manifest_checksum=") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "display_width=640") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "display_height=400") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "connector=none") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "trust_bundle=") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "asset_root=/packages/info-demo/assets") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "asset_count=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "asset_bytes=14") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "asset_tree_checksum=") != null);

    const assets = try listPackageAssetsAlloc(std.testing.allocator, "info-demo", 64);
    defer std.testing.allocator.free(assets);
    try std.testing.expectEqualStrings("dir config\n", assets);

    const asset = try readPackageAssetAlloc(std.testing.allocator, "info-demo", "config/app.json", 64);
    defer std.testing.allocator.free(asset);
    try std.testing.expectEqualStrings("{\"mode\":\"tcp\"}", asset);
}

test "package store persists app manifest display preferences and launch profile" {
    storage_backend.resetForTest();
    filesystem.resetForTest();

    try installScriptPackage("app-demo", "echo app-demo", 9);
    try trust_store.installBundle("app-root", "root-cert", 9);
    try configureDisplayMode("app-demo", 1280, 720, 10);
    try configureConnectorType("app-demo", abi.display_connector_virtual, 11);
    try configureTrustBundle("app-demo", "app-root", 12);

    const app_manifest = try appManifestAlloc(std.testing.allocator, "app-demo", 512);
    defer std.testing.allocator.free(app_manifest);
    try std.testing.expect(std.mem.indexOf(u8, app_manifest, "entrypoint=/packages/app-demo/bin/main.oc") != null);
    try std.testing.expect(std.mem.indexOf(u8, app_manifest, "display_width=1280") != null);
    try std.testing.expect(std.mem.indexOf(u8, app_manifest, "display_height=720") != null);
    try std.testing.expect(std.mem.indexOf(u8, app_manifest, "connector=virtual") != null);
    try std.testing.expect(std.mem.indexOf(u8, app_manifest, "trust_bundle=app-root") != null);

    var entrypoint_buf: [filesystem.max_path_len]u8 = undefined;
    const profile = try loadLaunchProfile("app-demo", &entrypoint_buf);
    try std.testing.expectEqualStrings("/packages/app-demo/bin/main.oc", profile.entrypoint);
    try std.testing.expectEqual(@as(u16, 1280), profile.display_width);
    try std.testing.expectEqual(@as(u16, 720), profile.display_height);
    try std.testing.expectEqual(@as(u8, abi.display_connector_virtual), profile.connector_type);
    try std.testing.expectEqualStrings("app-root", profile.trustBundle());

    const manifest = try manifestAlloc(std.testing.allocator, "app-demo", 512);
    defer std.testing.allocator.free(manifest);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "display_width=1280") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "display_height=720") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "connector=virtual") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "trust_bundle=app-root") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "script_checksum=") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "app_manifest_checksum=") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "asset_tree_checksum=") != null);
}

test "package store verifies persisted package manifest and asset tree" {
    storage_backend.resetForTest();
    filesystem.resetForTest();

    try installScriptPackage("verify-demo", "echo verify-demo", 20);
    try installPackageAsset("verify-demo", "config/app.json", "{\"mode\":\"verify\"}", 21);
    try configureDisplayMode("verify-demo", 1280, 720, 22);

    var result = try verifyPackageAlloc(std.testing.allocator, "verify-demo", 512);
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.ok);
    try std.testing.expect(std.mem.indexOf(u8, result.payload, "status=ok") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.payload, "script_checksum=") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.payload, "app_manifest_checksum=") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.payload, "asset_tree_checksum=") != null);
}

test "package store verification detects tampered package script" {
    storage_backend.resetForTest();
    filesystem.resetForTest();

    try installScriptPackage("tamper-demo", "echo original", 30);

    var entrypoint_buf: [filesystem.max_path_len]u8 = undefined;
    const entrypoint = try entrypointPath("tamper-demo", &entrypoint_buf);
    try filesystem.writeFile(entrypoint, "echo altered!", 31);

    var result = try verifyPackageAlloc(std.testing.allocator, "tamper-demo", 512);
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!result.ok);
    try std.testing.expect(std.mem.indexOf(u8, result.payload, "status=mismatch") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.payload, "field=script_checksum") != null);
}

test "package store snapshots and reactivates persisted package releases" {
    storage_backend.resetForTest();
    filesystem.resetForTest();

    try installScriptPackage("demo", "echo release-one", 1);
    try installPackageAsset("demo", "config/app.json", "{\"mode\":\"one\"}", 2);
    try snapshotPackageRelease("demo", "r1", 3);

    const release_listing = try releaseListAlloc(std.testing.allocator, "demo", 64);
    defer std.testing.allocator.free(release_listing);
    try std.testing.expectEqualStrings("r1\n", release_listing);

    try installScriptPackage("demo", "echo release-two", 4);
    try installPackageAsset("demo", "config/app.json", "{\"mode\":\"two\"}", 5);

    var entrypoint_buf: [filesystem.max_path_len]u8 = undefined;
    const canonical_entrypoint = try entrypointPath("demo", &entrypoint_buf);
    const mutated_script = try filesystem.readFileAlloc(std.testing.allocator, canonical_entrypoint, 64);
    defer std.testing.allocator.free(mutated_script);
    try std.testing.expectEqualStrings("echo release-two", mutated_script);

    try activatePackageRelease("demo", "r1", 6);

    const restored_script = try filesystem.readFileAlloc(std.testing.allocator, canonical_entrypoint, 64);
    defer std.testing.allocator.free(restored_script);
    try std.testing.expectEqualStrings("echo release-one", restored_script);

    const restored_asset = try readPackageAssetAlloc(std.testing.allocator, "demo", "config/app.json", 64);
    defer std.testing.allocator.free(restored_asset);
    try std.testing.expectEqualStrings("{\"mode\":\"one\"}", restored_asset);

    const manifest = try manifestAlloc(std.testing.allocator, "demo", 512);
    defer std.testing.allocator.free(manifest);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "script_checksum=") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "asset_tree_checksum=") != null);
}

test "package store persists package releases on ata-backed storage" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    ata_pio_disk.testEnableMockDevice(8192);
    ata_pio_disk.testInstallMockMbrPartition(2048, 4096, 0x83);
    defer ata_pio_disk.testDisableMockDevice();

    try installScriptPackage("persisted", "echo release-one", 1);
    try installPackageAsset("persisted", "config/app.json", "{\"mode\":\"release-one\"}", 2);
    try snapshotPackageRelease("persisted", "golden", 3);
    try setPackageReleaseChannel("persisted", "stable", "golden", 4);

    try installScriptPackage("persisted", "echo release-two", 5);
    try installPackageAsset("persisted", "config/app.json", "{\"mode\":\"release-two\"}", 6);

    filesystem.resetForTest();
    try activatePackageReleaseChannel("persisted", "stable", 7);

    var entrypoint_buf: [filesystem.max_path_len]u8 = undefined;
    const canonical_entrypoint = try entrypointPath("persisted", &entrypoint_buf);
    const restored_script = try filesystem.readFileAlloc(std.testing.allocator, canonical_entrypoint, 64);
    defer std.testing.allocator.free(restored_script);
    try std.testing.expectEqualStrings("echo release-one", restored_script);

    const restored_asset = try readPackageAssetAlloc(std.testing.allocator, "persisted", "config/app.json", 64);
    defer std.testing.allocator.free(restored_asset);
    try std.testing.expectEqualStrings("{\"mode\":\"release-one\"}", restored_asset);

    const release_listing = try releaseListAlloc(std.testing.allocator, "persisted", 64);
    defer std.testing.allocator.free(release_listing);
    try std.testing.expectEqualStrings("golden\n", release_listing);

    const channel_info = try channelInfoAlloc(std.testing.allocator, "persisted", "stable", 128);
    defer std.testing.allocator.free(channel_info);
    try std.testing.expect(std.mem.indexOf(u8, channel_info, "release=golden") != null);
}

test "package store reports, deletes, and prunes persisted package releases" {
    storage_backend.resetForTest();
    filesystem.resetForTest();

    try installScriptPackage("demo", "echo release-one", 1);
    try installPackageAsset("demo", "config/app.json", "{\"mode\":\"one\"}", 2);
    try snapshotPackageRelease("demo", "r1", 3);

    try installScriptPackage("demo", "echo release-two", 4);
    try installPackageAsset("demo", "config/app.json", "{\"mode\":\"two\"}", 5);
    try snapshotPackageRelease("demo", "r2", 6);

    try installScriptPackage("demo", "echo release-three", 7);
    try installPackageAsset("demo", "config/app.json", "{\"mode\":\"three\"}", 8);
    try snapshotPackageRelease("demo", "r3", 9);

    const info = try releaseInfoAlloc(std.testing.allocator, "demo", "r2", 512);
    defer std.testing.allocator.free(info);
    try std.testing.expect(std.mem.indexOf(u8, info, "name=demo") != null);
    try std.testing.expect(std.mem.indexOf(u8, info, "release=r2") != null);
    try std.testing.expect(std.mem.indexOf(u8, info, "saved_seq=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, info, "saved_tick=6") != null);
    try std.testing.expect(std.mem.indexOf(u8, info, "script_checksum=") != null);
    try std.testing.expect(std.mem.indexOf(u8, info, "asset_tree_checksum=") != null);

    try deletePackageRelease("demo", "r2", 10);

    const listing_after_delete = try releaseListAlloc(std.testing.allocator, "demo", 64);
    defer std.testing.allocator.free(listing_after_delete);
    try std.testing.expectEqualStrings("r1\nr3\n", listing_after_delete);

    const prune = try prunePackageReleases("demo", 1, 11);
    try std.testing.expectEqual(@as(u32, 1), prune.kept_count);
    try std.testing.expectEqual(@as(u32, 1), prune.deleted_count);

    const listing_after_prune = try releaseListAlloc(std.testing.allocator, "demo", 64);
    defer std.testing.allocator.free(listing_after_prune);
    try std.testing.expectEqualStrings("r3\n", listing_after_prune);

    try setPackageReleaseChannel("demo", "stable", "r3", 12);

    const channel_listing = try channelListAlloc(std.testing.allocator, "demo", 64);
    defer std.testing.allocator.free(channel_listing);
    try std.testing.expectEqualStrings("stable\n", channel_listing);

    const channel_info = try channelInfoAlloc(std.testing.allocator, "demo", "stable", 128);
    defer std.testing.allocator.free(channel_info);
    try std.testing.expect(std.mem.indexOf(u8, channel_info, "release=r3") != null);

    try installScriptPackage("demo", "echo release-channel-mutated", 13);
    try activatePackageReleaseChannel("demo", "stable", 14);

    var entrypoint_buf: [filesystem.max_path_len]u8 = undefined;
    const canonical_entrypoint = try entrypointPath("demo", &entrypoint_buf);
    const restored_script = try filesystem.readFileAlloc(std.testing.allocator, canonical_entrypoint, 64);
    defer std.testing.allocator.free(restored_script);
    try std.testing.expectEqualStrings("echo release-three", restored_script);

    try std.testing.expectError(error.PackageReleaseNotFound, activatePackageRelease("demo", "r1", 15));
}
