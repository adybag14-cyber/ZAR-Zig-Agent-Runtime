// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const abi = @import("abi.zig");
const ata_pio_disk = @import("ata_pio_disk.zig");
const ram_disk = @import("ram_disk.zig");
const virtio_block = @import("virtio_block.zig");

pub const block_size: usize = ram_disk.block_size;
pub const block_count: usize = ram_disk.block_count;
pub const capacity_bytes: usize = block_size * block_count;

pub const Error = ram_disk.Error || ata_pio_disk.Error || virtio_block.Error || error{
    NoDevice,
};

const Backend = enum {
    ram_disk,
    ata_pio,
    virtio_block,
};

var active_backend: Backend = .ram_disk;
var initialized = false;

fn primeBackends() void {
    ata_pio_disk.init();
    virtio_block.init();
    ram_disk.init();
}

fn backendAvailable(backend: Backend) bool {
    return switch (backend) {
        .ram_disk => true,
        .ata_pio => ata_pio_disk.statePtr().mounted != 0,
        .virtio_block => virtio_block.statePtr().mounted != 0,
    };
}

fn defaultBackend() Backend {
    if (backendAvailable(.ata_pio)) return .ata_pio;
    if (backendAvailable(.virtio_block)) return .virtio_block;
    return .ram_disk;
}

pub fn resetForTest() void {
    ram_disk.resetForTest();
    ata_pio_disk.resetForTest();
    virtio_block.resetForTest();
    active_backend = .ram_disk;
    initialized = false;
}

pub fn init() void {
    primeBackends();
    if (!initialized) {
        active_backend = defaultBackend();
        initialized = true;
        return;
    }
    if (!backendAvailable(active_backend)) {
        active_backend = defaultBackend();
    }
}

pub fn statePtr() *const abi.BaremetalStorageState {
    return switch (active_backend) {
        .ram_disk => ram_disk.statePtr(),
        .ata_pio => ata_pio_disk.statePtr(),
        .virtio_block => virtio_block.statePtr(),
    };
}

pub fn activeBackend() u8 {
    return statePtr().backend;
}

pub fn backendCount() u8 {
    return 3;
}

pub fn isBackendAvailable(backend: u8) bool {
    primeBackends();
    return switch (backend) {
        abi.storage_backend_ram_disk => true,
        abi.storage_backend_ata_pio => backendAvailable(.ata_pio),
        abi.storage_backend_virtio_block => backendAvailable(.virtio_block),
        else => false,
    };
}

pub fn selectBackendById(backend: u8) Error!void {
    primeBackends();
    switch (backend) {
        abi.storage_backend_ram_disk => active_backend = .ram_disk,
        abi.storage_backend_ata_pio => {
            if (!backendAvailable(.ata_pio)) return error.NoDevice;
            active_backend = .ata_pio;
        },
        abi.storage_backend_virtio_block => {
            if (!backendAvailable(.virtio_block)) return error.NoDevice;
            active_backend = .virtio_block;
        },
        else => return error.OutOfRange,
    }
    initialized = true;
}

pub fn logicalBaseLba() u32 {
    return switch (active_backend) {
        .ram_disk => 0,
        .ata_pio => ata_pio_disk.logicalBaseLba(),
        .virtio_block => 0,
    };
}

pub fn selectedPartitionIndex() ?u8 {
    return switch (active_backend) {
        .ram_disk => null,
        .ata_pio => ata_pio_disk.selectedPartitionIndex(),
        .virtio_block => null,
    };
}

pub fn partitionCount() u8 {
    return switch (active_backend) {
        .ram_disk => 0,
        .ata_pio => ata_pio_disk.partitionCount(),
        .virtio_block => 0,
    };
}

pub fn partitionInfo(index: u8) ?ata_pio_disk.PartitionInfo {
    return switch (active_backend) {
        .ram_disk => null,
        .ata_pio => ata_pio_disk.partitionInfo(index),
        .virtio_block => null,
    };
}

pub fn selectPartition(index: u8) Error!void {
    switch (active_backend) {
        .ram_disk => return error.OutOfRange,
        .ata_pio => try ata_pio_disk.selectPartition(index),
        .virtio_block => return error.OutOfRange,
    }
}

pub fn readBlocks(lba: u32, out: []u8) Error!void {
    switch (active_backend) {
        .ram_disk => try ram_disk.readBlocks(lba, out),
        .ata_pio => try ata_pio_disk.readBlocks(lba, out),
        .virtio_block => try virtio_block.readBlocks(lba, out),
    }
}

pub fn writeBlocks(lba: u32, input: []const u8) Error!void {
    switch (active_backend) {
        .ram_disk => try ram_disk.writeBlocks(lba, input),
        .ata_pio => try ata_pio_disk.writeBlocks(lba, input),
        .virtio_block => try virtio_block.writeBlocks(lba, input),
    }
}

pub fn flush() Error!void {
    switch (active_backend) {
        .ram_disk => try ram_disk.flush(),
        .ata_pio => try ata_pio_disk.flush(),
        .virtio_block => try virtio_block.flush(),
    }
}

pub fn readByte(lba: u32, offset: u32) u8 {
    return switch (active_backend) {
        .ram_disk => ram_disk.readByte(lba, offset),
        .ata_pio => ata_pio_disk.readByte(lba, offset),
        .virtio_block => virtio_block.readByte(lba, offset),
    };
}

test "storage backend facade exposes ram-disk baseline semantics" {
    resetForTest();
    init();

    const storage = statePtr();
    try std.testing.expectEqual(@as(u8, abi.storage_backend_ram_disk), activeBackend());
    try std.testing.expectEqual(@as(u8, abi.storage_backend_ram_disk), storage.backend);
    try std.testing.expectEqual(@as(u32, block_size), storage.block_size);
    try std.testing.expectEqual(@as(u32, block_count), storage.block_count);

    var payload = [_]u8{0} ** block_size;
    for (&payload, 0..) |*byte, idx| {
        byte.* = @as(u8, @truncate(idx));
    }
    try writeBlocks(3, payload[0..]);
    try std.testing.expectEqual(@as(u8, 1), storage.dirty);
    try std.testing.expectEqual(@as(u8, 0), readByte(3, 0));
    try std.testing.expectEqual(@as(u8, 1), readByte(3, 1));

    var out = [_]u8{0} ** block_size;
    try readBlocks(3, out[0..]);
    try std.testing.expectEqualSlices(u8, payload[0..], out[0..]);
    try flush();
    try std.testing.expectEqual(@as(u8, 0), storage.dirty);
}

test "storage backend facade prefers ata pio backend when a device is available" {
    resetForTest();
    ata_pio_disk.testEnableMockDevice(8192);
    ata_pio_disk.testInstallMockMbrPartition(2048, 4096, 0x83);
    defer ata_pio_disk.testDisableMockDevice();

    init();

    const storage = statePtr();
    try std.testing.expectEqual(@as(u8, abi.storage_backend_ata_pio), activeBackend());
    try std.testing.expectEqual(@as(u8, abi.storage_backend_ata_pio), storage.backend);
    try std.testing.expectEqual(@as(u8, 1), storage.mounted);
    try std.testing.expectEqual(@as(u32, 4096), storage.block_count);
    try std.testing.expectEqual(@as(u32, 2048), ata_pio_disk.logicalBaseLba());

    var payload = [_]u8{0} ** block_size;
    for (&payload, 0..) |*byte, idx| {
        byte.* = @as(u8, @truncate(0x20 + idx));
    }
    try writeBlocks(9, payload[0..]);
    try std.testing.expectEqual(@as(u8, 0x20), readByte(9, 0));
    try std.testing.expectEqual(@as(u8, 0x21), readByte(9, 1));
    try std.testing.expectEqual(@as(u8, 0), ata_pio_disk.testReadMockByteRaw(9, 0));
    try std.testing.expectEqual(@as(u8, 0x20), ata_pio_disk.testReadMockByteRaw(2048 + 9, 0));
    try std.testing.expectEqual(@as(u8, 0x21), ata_pio_disk.testReadMockByteRaw(2048 + 9, 1));
}

test "storage backend facade prefers virtio block backend when a device is available" {
    resetForTest();
    virtio_block.testEnableMockDevice(128);
    defer virtio_block.testDisableMockDevice();

    init();

    const storage = statePtr();
    try std.testing.expectEqual(@as(u8, abi.storage_backend_virtio_block), activeBackend());
    try std.testing.expectEqual(@as(u8, abi.storage_backend_virtio_block), storage.backend);
    try std.testing.expectEqual(@as(u8, 1), storage.mounted);
    try std.testing.expectEqual(@as(u32, 128), storage.block_count);
    try std.testing.expectEqual(@as(u32, 512), storage.block_size);
    try std.testing.expectEqual(@as(u8, 0), partitionCount());
    try std.testing.expectEqual(@as(?u8, null), selectedPartitionIndex());

    var payload = [_]u8{0} ** block_size;
    for (&payload, 0..) |*byte, idx| {
        byte.* = @as(u8, @truncate(0x70 + idx));
    }
    try writeBlocks(7, payload[0..]);
    try std.testing.expectEqual(@as(u8, 0x70), readByte(7, 0));
    try std.testing.expectEqual(@as(u8, 0x71), readByte(7, 1));
    try std.testing.expectEqual(@as(u8, 0x70), virtio_block.testReadMockByteRaw(7, 0));
    try flush();
    try std.testing.expectEqual(@as(u8, 0), storage.dirty);
}

test "storage backend facade prefers ata pio over virtio block when both are available" {
    resetForTest();
    ata_pio_disk.testEnableMockDevice(8192);
    ata_pio_disk.testInstallMockMbrPartition(2048, 4096, 0x83);
    virtio_block.testEnableMockDevice(128);
    defer ata_pio_disk.testDisableMockDevice();
    defer virtio_block.testDisableMockDevice();

    init();

    const storage = statePtr();
    try std.testing.expectEqual(@as(u8, abi.storage_backend_ata_pio), activeBackend());
    try std.testing.expectEqual(@as(u8, abi.storage_backend_ata_pio), storage.backend);
}

test "storage backend facade exports and selects ata partitions" {
    resetForTest();
    ata_pio_disk.testEnableMockDevice(16384);
    ata_pio_disk.testInstallMockMbrPartition(2048, 4096, 0x83);
    ata_pio_disk.testInstallMockMbrPartitionAt(1, 8192, 2048, 0x83);
    defer ata_pio_disk.testDisableMockDevice();

    init();

    try std.testing.expectEqual(@as(u8, abi.storage_backend_ata_pio), activeBackend());
    try std.testing.expectEqual(@as(u8, 2), partitionCount());
    try std.testing.expectEqual(@as(u32, 2048), logicalBaseLba());
    try std.testing.expectEqual(@as(?u8, 0), selectedPartitionIndex());
    try std.testing.expectEqual(@as(u32, 8192), partitionInfo(1).?.start_lba);
    try selectPartition(1);
    try std.testing.expectEqual(@as(u32, 8192), logicalBaseLba());
    try std.testing.expectEqual(@as(?u8, 1), selectedPartitionIndex());

    var payload = [_]u8{0} ** block_size;
    payload[0] = 0x44;
    payload[1] = 0x45;
    try writeBlocks(5, payload[0..]);
    try std.testing.expectEqual(@as(u8, 0x44), ata_pio_disk.testReadMockByteRaw(8192 + 5, 0));
    try std.testing.expectEqual(@as(u8, 0), ata_pio_disk.testReadMockByteRaw(2048 + 5, 0));
}

test "storage backend facade supports explicit backend selection" {
    resetForTest();
    ata_pio_disk.testEnableMockDevice(8192);
    ata_pio_disk.testInstallMockMbrPartition(2048, 4096, 0x83);
    virtio_block.testEnableMockDevice(128);
    defer ata_pio_disk.testDisableMockDevice();
    defer virtio_block.testDisableMockDevice();

    init();
    try std.testing.expectEqual(@as(u8, abi.storage_backend_ata_pio), activeBackend());
    try std.testing.expectEqual(@as(u8, 3), backendCount());
    try std.testing.expect(isBackendAvailable(abi.storage_backend_ram_disk));
    try std.testing.expect(isBackendAvailable(abi.storage_backend_ata_pio));
    try std.testing.expect(isBackendAvailable(abi.storage_backend_virtio_block));

    try selectBackendById(abi.storage_backend_virtio_block);
    try std.testing.expectEqual(@as(u8, abi.storage_backend_virtio_block), activeBackend());
    try std.testing.expectEqual(@as(u8, abi.storage_backend_virtio_block), statePtr().backend);

    try selectBackendById(abi.storage_backend_ram_disk);
    try std.testing.expectEqual(@as(u8, abi.storage_backend_ram_disk), activeBackend());
    try std.testing.expectEqual(@as(u8, abi.storage_backend_ram_disk), statePtr().backend);

    try std.testing.expectError(error.OutOfRange, selectBackendById(99));
}
