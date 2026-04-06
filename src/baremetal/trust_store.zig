// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const filesystem = @import("filesystem.zig");
const storage_backend = @import("storage_backend.zig");
const ata_pio_disk = @import("ata_pio_disk.zig");

pub const max_name_len: usize = 32;

const root_dir = "/runtime/trust";
const bundles_dir = "/runtime/trust/bundles";
const active_bundle_path = "/runtime/trust/active.txt";

pub const Error = filesystem.Error || std.mem.Allocator.Error || error{
    InvalidTrustName,
    TrustBundleNotFound,
    ActiveBundleNotSet,
    ResponseTooLarge,
};

pub fn installBundle(name: []const u8, cert_der: []const u8, tick: u64) Error!void {
    try validateTrustName(name);
    try ensureLayout();

    var path_buffer: [filesystem.max_path_len]u8 = undefined;
    const path = try bundlePath(name, &path_buffer);
    try filesystem.writeFile(path, cert_der, tick);
}

pub fn deleteBundle(name: []const u8, tick: u64) Error!void {
    try validateTrustName(name);
    try ensureLayout();

    var path_buffer: [filesystem.max_path_len]u8 = undefined;
    const path = try bundlePath(name, &path_buffer);
    filesystem.deleteFile(path, tick) catch |err| switch (err) {
        error.FileNotFound => return error.TrustBundleNotFound,
        else => return err,
    };

    if (try isActiveBundle(name)) {
        clearActiveBundle(tick) catch |err| switch (err) {
            error.ActiveBundleNotSet => {},
            else => return err,
        };
    }
}

pub fn bundlePath(name: []const u8, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    try validateTrustName(name);
    return std.fmt.bufPrint(buffer, "{s}/{s}.der", .{ bundles_dir, name }) catch error.InvalidPath;
}

pub fn bundleExists(name: []const u8) Error!bool {
    var path_buffer: [filesystem.max_path_len]u8 = undefined;
    const path = try bundlePath(name, &path_buffer);
    _ = filesystem.statSummary(path) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    return true;
}

pub fn listBundlesAlloc(allocator: std.mem.Allocator, max_bytes: usize) Error![]u8 {
    try filesystem.init();

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var idx: u32 = 0;
    while (idx < filesystem.max_entries) : (idx += 1) {
        const record = filesystem.entry(idx);
        if (record.kind == 0) continue;
        const path = record.path[0..record.path_len];
        const name = bundleNameFromPath(path) orelse continue;

        const line = try std.fmt.allocPrint(allocator, "{s}\n", .{name});
        defer allocator.free(line);
        if (out.items.len + line.len > max_bytes) return error.ResponseTooLarge;
        try out.appendSlice(allocator, line);
    }

    return out.toOwnedSlice(allocator);
}

pub fn infoAlloc(allocator: std.mem.Allocator, name: []const u8, max_bytes: usize) Error![]u8 {
    var path_buffer: [filesystem.max_path_len]u8 = undefined;
    const path = try bundlePath(name, &path_buffer);
    const stat = filesystem.statSummary(path) catch |err| switch (err) {
        error.FileNotFound => return error.TrustBundleNotFound,
        else => return err,
    };
    const selected = try isActiveBundle(name);

    const response = try std.fmt.allocPrint(
        allocator,
        "name={s}\npath={s}\nbytes={d}\nselected={d}\n",
        .{ name, path, stat.size, @intFromBool(selected) },
    );
    errdefer allocator.free(response);
    if (response.len > max_bytes) return error.ResponseTooLarge;
    return response;
}

pub fn selectBundle(name: []const u8, tick: u64) Error!void {
    try validateTrustName(name);
    try ensureLayout();

    var path_buffer: [filesystem.max_path_len]u8 = undefined;
    const path = try bundlePath(name, &path_buffer);
    _ = filesystem.statSummary(path) catch |err| switch (err) {
        error.FileNotFound => return error.TrustBundleNotFound,
        else => return err,
    };

    try filesystem.writeFile(active_bundle_path, name, tick);
}

pub fn clearActiveBundle(tick: u64) Error!void {
    try ensureLayout();
    filesystem.deleteFile(active_bundle_path, tick) catch |err| switch (err) {
        error.FileNotFound => return error.ActiveBundleNotSet,
        else => return err,
    };
}

pub fn activeBundleNameAlloc(allocator: std.mem.Allocator, max_bytes: usize) Error![]u8 {
    const name = filesystem.readFileAlloc(allocator, active_bundle_path, max_bytes) catch |err| switch (err) {
        error.FileNotFound => return error.ActiveBundleNotSet,
        else => return err,
    };
    errdefer allocator.free(name);
    try validateTrustName(name);
    return name;
}

pub fn activeBundlePathAlloc(allocator: std.mem.Allocator, max_bytes: usize) Error![]u8 {
    const active_name = try activeBundleNameAlloc(allocator, max_name_len);
    defer allocator.free(active_name);

    var path_buffer: [filesystem.max_path_len]u8 = undefined;
    const path = try bundlePath(active_name, &path_buffer);
    if (path.len > max_bytes) return error.ResponseTooLarge;
    return allocator.dupe(u8, path);
}

pub fn activeBundleInfoAlloc(allocator: std.mem.Allocator, max_bytes: usize) Error![]u8 {
    const active_name = try activeBundleNameAlloc(allocator, max_name_len);
    defer allocator.free(active_name);
    return infoAlloc(allocator, active_name, max_bytes);
}

fn ensureLayout() Error!void {
    try filesystem.init();
    try filesystem.createDirPath(root_dir);
    try filesystem.createDirPath(bundles_dir);
}

fn validateTrustName(name: []const u8) Error!void {
    if (name.len == 0 or name.len > max_name_len) return error.InvalidTrustName;
    for (name) |char| {
        if (std.ascii.isAlphanumeric(char) or char == '-' or char == '_' or char == '.') continue;
        return error.InvalidTrustName;
    }
}

fn bundleNameFromPath(path: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, path, bundles_dir ++ "/")) return null;
    if (!std.mem.endsWith(u8, path, ".der")) return null;

    const name = path[(bundles_dir ++ "/").len .. path.len - ".der".len];
    if (name.len == 0 or std.mem.indexOfScalar(u8, name, '/') != null) return null;
    return name;
}

fn isActiveBundle(name: []const u8) Error!bool {
    var scratch: [max_name_len]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&scratch);
    const active_name = activeBundleNameAlloc(fba.allocator(), max_name_len) catch |err| switch (err) {
        error.ActiveBundleNotSet => return false,
        else => return err,
    };
    return std.mem.eql(u8, active_name, name);
}

test "trust store installs lists and selects persisted bundles on the ram disk" {
    storage_backend.resetForTest();
    filesystem.resetForTest();

    try installBundle("fs55-root", "root-cert", 7);
    try selectBundle("fs55-root", 9);

    var bundle_path_buffer: [filesystem.max_path_len]u8 = undefined;
    const bundle_path = try bundlePath("fs55-root", &bundle_path_buffer);
    const cert = try filesystem.readFileAlloc(std.testing.allocator, bundle_path, 64);
    defer std.testing.allocator.free(cert);
    try std.testing.expectEqualStrings("root-cert", cert);

    const listing = try listBundlesAlloc(std.testing.allocator, 64);
    defer std.testing.allocator.free(listing);
    try std.testing.expectEqualStrings("fs55-root\n", listing);

    const info = try infoAlloc(std.testing.allocator, "fs55-root", 256);
    defer std.testing.allocator.free(info);
    try std.testing.expect(std.mem.indexOf(u8, info, "name=fs55-root") != null);
    try std.testing.expect(std.mem.indexOf(u8, info, "selected=1") != null);

    const active_name = try activeBundleNameAlloc(std.testing.allocator, max_name_len);
    defer std.testing.allocator.free(active_name);
    try std.testing.expectEqualStrings("fs55-root", active_name);

    const active_path = try activeBundlePathAlloc(std.testing.allocator, 128);
    defer std.testing.allocator.free(active_path);
    try std.testing.expectEqualStrings(bundle_path, active_path);
}

test "trust store selection and data persist on ata-backed storage" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    ata_pio_disk.testEnableMockDevice(8192);
    ata_pio_disk.testInstallMockMbrPartition(2048, 4096, 0x83);
    defer ata_pio_disk.testDisableMockDevice();

    try installBundle("persisted-root", "persisted-cert", 11);
    try selectBundle("persisted-root", 12);
    try std.testing.expectEqual(@as(u32, 2048), ata_pio_disk.logicalBaseLba());

    filesystem.resetForTest();

    var bundle_path_buffer: [filesystem.max_path_len]u8 = undefined;
    const bundle_path = try bundlePath("persisted-root", &bundle_path_buffer);
    const cert = try filesystem.readFileAlloc(std.testing.allocator, bundle_path, 64);
    defer std.testing.allocator.free(cert);
    try std.testing.expectEqualStrings("persisted-cert", cert);

    const active_path = try activeBundlePathAlloc(std.testing.allocator, 128);
    defer std.testing.allocator.free(active_path);
    try std.testing.expectEqualStrings(bundle_path, active_path);

    const info = try infoAlloc(std.testing.allocator, "persisted-root", 256);
    defer std.testing.allocator.free(info);
    try std.testing.expect(std.mem.indexOf(u8, info, "selected=1") != null);
}

test "trust store rejects selecting unknown bundles" {
    storage_backend.resetForTest();
    filesystem.resetForTest();

    try std.testing.expectError(error.TrustBundleNotFound, selectBundle("missing", 1));
}

test "trust store rotates across multiple bundles and deletes inactive bundles" {
    storage_backend.resetForTest();
    filesystem.resetForTest();

    try installBundle("root-a", "cert-a", 1);
    try installBundle("root-b", "cert-b", 2);
    try selectBundle("root-a", 3);
    try selectBundle("root-b", 4);

    const active_info = try activeBundleInfoAlloc(std.testing.allocator, 256);
    defer std.testing.allocator.free(active_info);
    try std.testing.expect(std.mem.indexOf(u8, active_info, "name=root-b") != null);
    try std.testing.expect(std.mem.indexOf(u8, active_info, "selected=1") != null);

    try deleteBundle("root-a", 5);
    const listing = try listBundlesAlloc(std.testing.allocator, 64);
    defer std.testing.allocator.free(listing);
    try std.testing.expectEqualStrings("root-b\n", listing);
    try std.testing.expectError(error.TrustBundleNotFound, infoAlloc(std.testing.allocator, "root-a", 128));

    const active_name = try activeBundleNameAlloc(std.testing.allocator, max_name_len);
    defer std.testing.allocator.free(active_name);
    try std.testing.expectEqualStrings("root-b", active_name);
}

test "trust store clears the active selection when deleting the active bundle" {
    storage_backend.resetForTest();
    filesystem.resetForTest();

    try installBundle("root-a", "cert-a", 1);
    try selectBundle("root-a", 2);
    try deleteBundle("root-a", 3);

    try std.testing.expectError(error.ActiveBundleNotSet, activeBundleNameAlloc(std.testing.allocator, max_name_len));
    try std.testing.expectError(error.ActiveBundleNotSet, activeBundleInfoAlloc(std.testing.allocator, 256));
    try std.testing.expectError(error.TrustBundleNotFound, infoAlloc(std.testing.allocator, "root-a", 128));
}
