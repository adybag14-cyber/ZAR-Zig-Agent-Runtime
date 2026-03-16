const std = @import("std");
const abi = @import("abi.zig");
const filesystem = @import("filesystem.zig");
const storage_backend = @import("storage_backend.zig");
const ata_pio_disk = @import("ata_pio_disk.zig");

pub const max_name_len: usize = 32;

const trust_root_path = "/runtime/trust";
const bundle_root_path = "/runtime/trust/bundles";
const active_bundle_path = "/runtime/trust/active.txt";

pub const Error = filesystem.Error || std.mem.Allocator.Error || error{
    InvalidTrustName,
    TrustNotFound,
    NoActiveBundle,
    ResponseTooLarge,
};

const BundleRecord = struct {
    name: [max_name_len]u8 = undefined,
    name_len: usize,
    byte_len: u32,
};

pub fn installBundle(name: []const u8, cert_der: []const u8, tick: u64) Error!void {
    try validateTrustName(name);

    var path_buf: [filesystem.max_path_len]u8 = undefined;
    try filesystem.createDirPath(bundle_root_path);
    try filesystem.writeFile(try bundlePath(name, &path_buf), cert_der, tick);
}

pub fn selectBundle(name: []const u8, tick: u64) Error!void {
    try validateTrustName(name);

    var path_buf: [filesystem.max_path_len]u8 = undefined;
    const selected_path = try bundlePath(name, &path_buf);
    const stat = filesystem.statSummary(selected_path) catch |err| switch (err) {
        error.FileNotFound => return error.TrustNotFound,
        else => return err,
    };
    if (stat.kind != .file) return error.TrustNotFound;

    try filesystem.createDirPath(trust_root_path);
    try filesystem.writeFile(active_bundle_path, name, tick);
}

pub fn bundlePath(name: []const u8, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    try validateTrustName(name);
    return std.fmt.bufPrint(buffer, "/runtime/trust/bundles/{s}.der", .{name}) catch error.InvalidPath;
}

pub fn selectedBundleNameAlloc(allocator: std.mem.Allocator, max_bytes: usize) Error![]u8 {
    const name = filesystem.readFileAlloc(allocator, active_bundle_path, @min(max_bytes, max_name_len)) catch |err| switch (err) {
        error.FileNotFound => return error.NoActiveBundle,
        else => return err,
    };
    errdefer allocator.free(name);
    if (name.len == 0) return error.NoActiveBundle;
    try validateTrustName(name);
    return name;
}

pub fn selectedBundleInfoAlloc(allocator: std.mem.Allocator, max_bytes: usize) Error![]u8 {
    const name = try selectedBundleNameAlloc(allocator, max_name_len);
    defer allocator.free(name);
    return infoAlloc(allocator, name, max_bytes);
}

pub fn infoAlloc(allocator: std.mem.Allocator, name: []const u8, max_bytes: usize) Error![]u8 {
    try validateTrustName(name);

    var path_buf: [filesystem.max_path_len]u8 = undefined;
    const selected_path = try bundlePath(name, &path_buf);
    const stat = filesystem.statSummary(selected_path) catch |err| switch (err) {
        error.FileNotFound => return error.TrustNotFound,
        else => return err,
    };

    const active_name = selectedBundleNameAlloc(allocator, max_name_len) catch |err| switch (err) {
        error.NoActiveBundle => null,
        else => return err,
    };
    defer if (active_name) |name_buf| allocator.free(name_buf);

    const selected_flag: u8 = if (active_name) |current_name|
        @intFromBool(std.mem.eql(u8, current_name, name))
    else
        0;
    const active_display = if (active_name) |current_name| current_name else "<none>";

    const info = try std.fmt.allocPrint(
        allocator,
        "name={s}\npath={s}\nbytes={d}\nselected={d}\nactive={s}\n",
        .{ name, selected_path, stat.size, selected_flag, active_display },
    );
    errdefer allocator.free(info);
    if (info.len > max_bytes) return error.ResponseTooLarge;
    return info;
}

pub fn listBundlesAlloc(allocator: std.mem.Allocator, max_bytes: usize) Error![]u8 {
    try filesystem.init();

    const active_name = selectedBundleNameAlloc(allocator, max_name_len) catch |err| switch (err) {
        error.NoActiveBundle => null,
        else => return err,
    };
    defer if (active_name) |name_buf| allocator.free(name_buf);

    var bundles: [filesystem.max_entries]BundleRecord = undefined;
    var bundle_count: usize = 0;

    var idx: u32 = 0;
    while (idx < filesystem.max_entries) : (idx += 1) {
        const record = filesystem.entry(idx);
        if (record.kind == 0 or record.kind != abi.filesystem_kind_file) continue;

        const path = record.path[0..record.path_len];
        const bundle_name = bundleNameFromPath(path) orelse continue;

        bundles[bundle_count] = .{
            .name_len = bundle_name.len,
            .byte_len = record.byte_len,
        };
        @memcpy(bundles[bundle_count].name[0..bundle_name.len], bundle_name);
        bundle_count += 1;
    }

    sortBundleRecords(bundles[0..bundle_count]);

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    for (bundles[0..bundle_count]) |bundle| {
        const bundle_name = bundle.name[0..bundle.name_len];
        const selected_flag: u8 = if (active_name) |current_name|
            @intFromBool(std.mem.eql(u8, current_name, bundle_name))
        else
            0;
        const line = try std.fmt.allocPrint(
            allocator,
            "bundle {s} bytes={d} selected={d}\n",
            .{ bundle_name, bundle.byte_len, selected_flag },
        );
        defer allocator.free(line);
        if (out.items.len + line.len > max_bytes) return error.ResponseTooLarge;
        try out.appendSlice(allocator, line);
    }

    return out.toOwnedSlice(allocator);
}

fn validateTrustName(name: []const u8) Error!void {
    if (name.len == 0 or name.len > max_name_len) return error.InvalidTrustName;
    for (name) |char| {
        if (std.ascii.isAlphanumeric(char) or char == '-' or char == '_' or char == '.') continue;
        return error.InvalidTrustName;
    }
}

fn bundleNameFromPath(path: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, path, "/runtime/trust/bundles/")) return null;
    if (!std.mem.endsWith(u8, path, ".der")) return null;

    const name = path["/runtime/trust/bundles/".len .. path.len - ".der".len];
    if (name.len == 0 or name.len > max_name_len) return null;
    if (std.mem.indexOfScalar(u8, name, '/') != null) return null;
    return name;
}

fn sortBundleRecords(records: []BundleRecord) void {
    var i: usize = 1;
    while (i < records.len) : (i += 1) {
        var j = i;
        while (j > 0 and lessThan(records[j], records[j - 1])) : (j -= 1) {
            const tmp = records[j - 1];
            records[j - 1] = records[j];
            records[j] = tmp;
        }
    }
}

fn lessThan(a: BundleRecord, b: BundleRecord) bool {
    return std.mem.order(u8, a.name[0..a.name_len], b.name[0..b.name_len]) == .lt;
}

test "trust store installs lists selects and reports bundle info on the ram disk" {
    storage_backend.resetForTest();
    filesystem.resetForTest();

    try installBundle("beta-root", "BBBB", 7);
    try installBundle("alpha-root", "ALPHA", 8);

    const listing_before = try listBundlesAlloc(std.testing.allocator, 256);
    defer std.testing.allocator.free(listing_before);
    try std.testing.expectEqualStrings(
        "bundle alpha-root bytes=5 selected=0\nbundle beta-root bytes=4 selected=0\n",
        listing_before,
    );

    try selectBundle("beta-root", 9);

    const selected_name = try selectedBundleNameAlloc(std.testing.allocator, 64);
    defer std.testing.allocator.free(selected_name);
    try std.testing.expectEqualStrings("beta-root", selected_name);

    const listing_after = try listBundlesAlloc(std.testing.allocator, 256);
    defer std.testing.allocator.free(listing_after);
    try std.testing.expectEqualStrings(
        "bundle alpha-root bytes=5 selected=0\nbundle beta-root bytes=4 selected=1\n",
        listing_after,
    );

    const info = try selectedBundleInfoAlloc(std.testing.allocator, 256);
    defer std.testing.allocator.free(info);
    try std.testing.expect(std.mem.indexOf(u8, info, "name=beta-root\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, info, "path=/runtime/trust/bundles/beta-root.der\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, info, "bytes=4\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, info, "selected=1\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, info, "active=beta-root\n") != null);
}

test "trust store persists selected bundles on ata-backed storage" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    ata_pio_disk.testEnableMockDevice(8192);
    ata_pio_disk.testInstallMockMbrPartition(2048, 4096, 0x83);
    defer ata_pio_disk.testDisableMockDevice();

    try installBundle("fs55-root", "EDGE-ROOT", 11);
    try selectBundle("fs55-root", 12);

    filesystem.resetForTest();

    const listing = try listBundlesAlloc(std.testing.allocator, 256);
    defer std.testing.allocator.free(listing);
    try std.testing.expectEqualStrings("bundle fs55-root bytes=9 selected=1\n", listing);

    const info = try selectedBundleInfoAlloc(std.testing.allocator, 256);
    defer std.testing.allocator.free(info);
    try std.testing.expect(std.mem.indexOf(u8, info, "name=fs55-root\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, info, "path=/runtime/trust/bundles/fs55-root.der\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, info, "bytes=9\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, info, "selected=1\n") != null);
}

test "trust store rejects invalid selections" {
    storage_backend.resetForTest();
    filesystem.resetForTest();

    try std.testing.expectError(error.TrustNotFound, selectBundle("missing-root", 1));
    try std.testing.expectError(error.NoActiveBundle, selectedBundleInfoAlloc(std.testing.allocator, 128));
}
