const std = @import("std");

pub const block_len: usize = 128;
pub const max_name_len: usize = 13;

pub const Timing = struct {
    pixel_clock_khz: u32,
    h_active: u16,
    h_blank: u16,
    v_active: u16,
    v_blank: u16,
    refresh_hz: u16,
};

pub const ParsedEdid = struct {
    manufacturer_id: u16,
    manufacturer_name: [3]u8,
    product_code: u16,
    serial_number: u32,
    manufacture_week: u8,
    manufacture_year: u16,
    version: u8,
    revision: u8,
    input_digital: bool,
    physical_width_mm: u16,
    physical_height_mm: u16,
    extension_count: u8,
    preferred_timing: ?Timing,
    display_name_len: u8,
    display_name: [max_name_len]u8,
};

pub const ParseError = error{
    InvalidLength,
    InvalidHeader,
    InvalidChecksum,
};

const edid_header = [_]u8{ 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00 };

fn decodeManufacturer(word: u16) [3]u8 {
    return .{
        @as(u8, @intCast(((word >> 10) & 0x1F) + 0x40)),
        @as(u8, @intCast(((word >> 5) & 0x1F) + 0x40)),
        @as(u8, @intCast((word & 0x1F) + 0x40)),
    };
}

fn parseDetailedTiming(block: []const u8) ?Timing {
    if (block.len < 18) return null;
    const pixel_clock_units = std.mem.readInt(u16, block[0..2], .little);
    if (pixel_clock_units == 0) return null;

    const h_active: u16 = @as(u16, block[2]) | (@as(u16, (block[4] >> 4) & 0xF) << 8);
    const h_blank: u16 = @as(u16, block[3]) | (@as(u16, block[4] & 0xF) << 8);
    const v_active: u16 = @as(u16, block[5]) | (@as(u16, (block[7] >> 4) & 0xF) << 8);
    const v_blank: u16 = @as(u16, block[6]) | (@as(u16, block[7] & 0xF) << 8);
    const h_total = @as(u32, h_active) + @as(u32, h_blank);
    const v_total = @as(u32, v_active) + @as(u32, v_blank);
    const pixel_clock_khz = @as(u32, pixel_clock_units) * 10;
    const refresh_hz = if (h_total == 0 or v_total == 0)
        0
    else
        @as(u16, @intCast(@divFloor(pixel_clock_khz * 1000, h_total * v_total)));

    return .{
        .pixel_clock_khz = pixel_clock_khz,
        .h_active = h_active,
        .h_blank = h_blank,
        .v_active = v_active,
        .v_blank = v_blank,
        .refresh_hz = refresh_hz,
    };
}

fn parseDisplayName(block: []const u8) ?struct { len: u8, value: [max_name_len]u8 } {
    if (block.len < 18) return null;
    if (block[0] != 0 or block[1] != 0 or block[2] != 0 or block[3] != 0xFC) return null;

    var result: [max_name_len]u8 = [_]u8{0} ** max_name_len;
    var len: usize = 0;
    var idx: usize = 5;
    while (idx < 18 and len < result.len) : (idx += 1) {
        const byte = block[idx];
        if (byte == 0 or byte == 0x0A) break;
        result[len] = byte;
        len += 1;
    }

    while (len > 0 and result[len - 1] == ' ') {
        len -= 1;
    }

    return .{
        .len = @intCast(len),
        .value = result,
    };
}

pub fn parse(raw: []const u8) ParseError!ParsedEdid {
    if (raw.len < block_len) return error.InvalidLength;
    if (!std.mem.eql(u8, raw[0..edid_header.len], &edid_header)) return error.InvalidHeader;

    var checksum: u8 = 0;
    for (raw[0..block_len]) |byte| checksum +%= byte;
    if (checksum != 0) return error.InvalidChecksum;

    const manufacturer_id = std.mem.readInt(u16, raw[8..10], .big);
    var parsed = ParsedEdid{
        .manufacturer_id = manufacturer_id,
        .manufacturer_name = decodeManufacturer(manufacturer_id),
        .product_code = std.mem.readInt(u16, raw[10..12], .little),
        .serial_number = std.mem.readInt(u32, raw[12..16], .little),
        .manufacture_week = raw[16],
        .manufacture_year = @as(u16, 1990) + @as(u16, raw[17]),
        .version = raw[18],
        .revision = raw[19],
        .input_digital = (raw[20] & 0x80) != 0,
        .physical_width_mm = @as(u16, raw[21]) * 10,
        .physical_height_mm = @as(u16, raw[22]) * 10,
        .extension_count = raw[126],
        .preferred_timing = null,
        .display_name_len = 0,
        .display_name = [_]u8{0} ** max_name_len,
    };

    var descriptor_offset: usize = 54;
    while (descriptor_offset + 18 <= block_len) : (descriptor_offset += 18) {
        const descriptor = raw[descriptor_offset .. descriptor_offset + 18];
        if (parsed.preferred_timing == null) {
            parsed.preferred_timing = parseDetailedTiming(descriptor);
        }
        if (parsed.display_name_len == 0) {
            if (parseDisplayName(descriptor)) |name| {
                parsed.display_name_len = name.len;
                parsed.display_name = name.value;
            }
        }
    }

    return parsed;
}

fn encodeManufacturer(a: u8, b: u8, c: u8) u16 {
    return (@as(u16, a - 0x40) << 10) | (@as(u16, b - 0x40) << 5) | @as(u16, c - 0x40);
}

fn writeDetailedTiming(block: []u8, pixel_clock_units: u16, h_active: u16, h_blank: u16, v_active: u16, v_blank: u16) void {
    std.mem.writeInt(u16, block[0..2], pixel_clock_units, .little);
    block[2] = @truncate(h_active);
    block[3] = @truncate(h_blank);
    block[4] = @as(u8, @intCast(((h_active >> 8) & 0xF) << 4)) | @as(u8, @intCast((h_blank >> 8) & 0xF));
    block[5] = @truncate(v_active);
    block[6] = @truncate(v_blank);
    block[7] = @as(u8, @intCast(((v_active >> 8) & 0xF) << 4)) | @as(u8, @intCast((v_blank >> 8) & 0xF));
    block[8] = 0;
    block[9] = 0;
    block[10] = 0;
    block[11] = 0;
    block[12] = 0;
    block[13] = 0;
    block[14] = 0;
    block[15] = 0;
    block[16] = 0;
    block[17] = 0;
}

fn setDisplayName(block: []u8, name: []const u8) void {
    @memset(block, 0);
    block[3] = 0xFC;
    var idx: usize = 0;
    while (idx < name.len and idx < max_name_len) : (idx += 1) {
        block[5 + idx] = name[idx];
    }
    if (5 + idx < block.len) block[5 + idx] = 0x0A;
}

fn finalizeChecksum(edid_bytes: []u8) void {
    var checksum: u8 = 0;
    for (edid_bytes[0 .. block_len - 1]) |byte| checksum +%= byte;
    edid_bytes[block_len - 1] = 0 -% checksum;
}

fn sampleEdid() [block_len]u8 {
    var bytes: [block_len]u8 = [_]u8{0} ** block_len;
    std.mem.copyForwards(u8, bytes[0..edid_header.len], &edid_header);
    std.mem.writeInt(u16, bytes[8..10], encodeManufacturer('Q', 'E', 'M'), .big);
    std.mem.writeInt(u16, bytes[10..12], 0x1234, .little);
    std.mem.writeInt(u32, bytes[12..16], 0xCAFEBABE, .little);
    bytes[16] = 1;
    bytes[17] = 36; // 2026
    bytes[18] = 1;
    bytes[19] = 4;
    bytes[20] = 0x80;
    bytes[21] = 60;
    bytes[22] = 34;
    writeDetailedTiming(bytes[54..72], 7425, 1280, 370, 720, 30);
    setDisplayName(bytes[72..90], "QEMU-EDID");
    finalizeChecksum(&bytes);
    return bytes;
}

test "edid parser decodes preferred timing and display name" {
    const parsed = try parse(&sampleEdid());
    try std.testing.expectEqual(encodeManufacturer('Q', 'E', 'M'), parsed.manufacturer_id);
    try std.testing.expectEqualSlices(u8, "QEM", parsed.manufacturer_name[0..]);
    try std.testing.expectEqual(@as(u16, 0x1234), parsed.product_code);
    try std.testing.expectEqual(@as(u32, 0xCAFEBABE), parsed.serial_number);
    try std.testing.expectEqual(@as(u16, 600), parsed.physical_width_mm);
    try std.testing.expectEqual(@as(u16, 340), parsed.physical_height_mm);
    try std.testing.expect(parsed.input_digital);
    const preferred = parsed.preferred_timing orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u16, 1280), preferred.h_active);
    try std.testing.expectEqual(@as(u16, 720), preferred.v_active);
    try std.testing.expectEqual(@as(u32, 74250), preferred.pixel_clock_khz);
    try std.testing.expect(preferred.refresh_hz >= 60);
    try std.testing.expectEqualStrings("QEMU-EDID", parsed.display_name[0..parsed.display_name_len]);
}

test "edid parser rejects invalid checksum" {
    var bytes = sampleEdid();
    bytes[20] +%= 1;
    try std.testing.expectError(error.InvalidChecksum, parse(&bytes));
}

test "edid parser rejects invalid header" {
    var bytes = sampleEdid();
    bytes[0] = 0x12;
    finalizeChecksum(&bytes);
    try std.testing.expectError(error.InvalidHeader, parse(&bytes));
}
