// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const abi = @import("abi.zig");

pub const block_len: usize = 128;
pub const max_name_len: usize = 13;
pub const max_timings: usize = 16;
const cea_extension_tag: u8 = 0x02;
const displayid_extension_tag: u8 = 0x70;
const cea_tag_audio: u8 = 1;
const cea_tag_vendor: u8 = 3;
const hdmi_vendor_oui = [_]u8{ 0x03, 0x0C, 0x00 };

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
    digital_interface_type: u8,
    physical_width_mm: u16,
    physical_height_mm: u16,
    extension_count: u8,
    capability_flags: u16,
    preferred_timing: ?Timing,
    timing_count: u8,
    timings: [max_timings]Timing,
    display_name_len: u8,
    display_name: [max_name_len]u8,
};

pub const ParseError = error{
    InvalidLength,
    InvalidHeader,
    InvalidChecksum,
};

const edid_header = [_]u8{ 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00 };

const EstablishedTiming = struct {
    byte_index: usize,
    bit_mask: u8,
    width: u16,
    height: u16,
    refresh_hz: u16,
};

const established_timings = [_]EstablishedTiming{
    .{ .byte_index = 35, .bit_mask = 0x80, .width = 720, .height = 400, .refresh_hz = 70 },
    .{ .byte_index = 35, .bit_mask = 0x40, .width = 720, .height = 400, .refresh_hz = 88 },
    .{ .byte_index = 35, .bit_mask = 0x20, .width = 640, .height = 480, .refresh_hz = 60 },
    .{ .byte_index = 35, .bit_mask = 0x10, .width = 640, .height = 480, .refresh_hz = 67 },
    .{ .byte_index = 35, .bit_mask = 0x08, .width = 640, .height = 480, .refresh_hz = 72 },
    .{ .byte_index = 35, .bit_mask = 0x04, .width = 640, .height = 480, .refresh_hz = 75 },
    .{ .byte_index = 35, .bit_mask = 0x02, .width = 800, .height = 600, .refresh_hz = 56 },
    .{ .byte_index = 35, .bit_mask = 0x01, .width = 800, .height = 600, .refresh_hz = 60 },
    .{ .byte_index = 36, .bit_mask = 0x80, .width = 800, .height = 600, .refresh_hz = 72 },
    .{ .byte_index = 36, .bit_mask = 0x40, .width = 800, .height = 600, .refresh_hz = 75 },
    .{ .byte_index = 36, .bit_mask = 0x20, .width = 832, .height = 624, .refresh_hz = 75 },
    .{ .byte_index = 36, .bit_mask = 0x10, .width = 1024, .height = 768, .refresh_hz = 87 },
    .{ .byte_index = 36, .bit_mask = 0x08, .width = 1024, .height = 768, .refresh_hz = 60 },
    .{ .byte_index = 36, .bit_mask = 0x04, .width = 1024, .height = 768, .refresh_hz = 70 },
    .{ .byte_index = 36, .bit_mask = 0x02, .width = 1024, .height = 768, .refresh_hz = 75 },
    .{ .byte_index = 36, .bit_mask = 0x01, .width = 1280, .height = 1024, .refresh_hz = 75 },
    .{ .byte_index = 37, .bit_mask = 0x80, .width = 1152, .height = 870, .refresh_hz = 75 },
};

fn decodeManufacturer(word: u16) [3]u8 {
    return .{
        @as(u8, @intCast(((word >> 10) & 0x1F) + 0x40)),
        @as(u8, @intCast(((word >> 5) & 0x1F) + 0x40)),
        @as(u8, @intCast((word & 0x1F) + 0x40)),
    };
}

fn decodeDigitalInterfaceType(raw: u8) u8 {
    if ((raw & 0x80) == 0) return abi.display_interface_none;
    return switch ((raw >> 4) & 0x07) {
        0 => abi.display_interface_undefined,
        1 => abi.display_interface_dvi,
        2 => abi.display_interface_hdmi_a,
        3 => abi.display_interface_hdmi_b,
        4 => abi.display_interface_mddi,
        5 => abi.display_interface_displayport,
        else => abi.display_interface_undefined,
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

fn appendTiming(parsed: *ParsedEdid, timing: Timing) void {
    if (timing.h_active == 0 or timing.v_active == 0) return;

    var index: usize = 0;
    while (index < parsed.timing_count and index < parsed.timings.len) : (index += 1) {
        const existing = parsed.timings[index];
        if (existing.h_active == timing.h_active and existing.v_active == timing.v_active and existing.refresh_hz == timing.refresh_hz) {
            return;
        }
    }
    if (parsed.timing_count >= parsed.timings.len) return;
    parsed.timings[parsed.timing_count] = timing;
    parsed.timing_count += 1;
}

fn appendDetailedTiming(parsed: *ParsedEdid, block: []const u8) void {
    const timing = parseDetailedTiming(block) orelse return;
    if (parsed.preferred_timing == null) {
        parsed.preferred_timing = timing;
        parsed.capability_flags |= abi.display_capability_preferred_timing;
    }
    appendTiming(parsed, timing);
}

fn parseEstablishedTimings(raw: []const u8, parsed: *ParsedEdid) void {
    for (established_timings) |timing| {
        if ((raw[timing.byte_index] & timing.bit_mask) == 0) continue;
        appendTiming(parsed, .{
            .pixel_clock_khz = 0,
            .h_active = timing.width,
            .h_blank = 0,
            .v_active = timing.height,
            .v_blank = 0,
            .refresh_hz = timing.refresh_hz,
        });
    }
}

fn decodeStandardTimingWidth(byte: u8) ?u16 {
    if (byte == 0x00 or byte == 0x01) return null;
    return (@as(u16, byte) + 31) * 8;
}

fn decodeStandardTimingHeight(width: u16, aspect_bits: u8, version: u8, revision: u8) u16 {
    return switch (aspect_bits) {
        0 => if (version > 1 or revision >= 3) @as(u16, @intCast(@divTrunc(@as(u32, width) * 10, 16))) else width,
        1 => @as(u16, @intCast(@divTrunc(@as(u32, width) * 3, 4))),
        2 => @as(u16, @intCast(@divTrunc(@as(u32, width) * 4, 5))),
        else => @as(u16, @intCast(@divTrunc(@as(u32, width) * 9, 16))),
    };
}

fn parseStandardTimings(raw: []const u8, parsed: *ParsedEdid) void {
    var offset: usize = 38;
    while (offset + 1 < 54) : (offset += 2) {
        const width = decodeStandardTimingWidth(raw[offset]) orelse continue;
        if (raw[offset] == 0x01 and raw[offset + 1] == 0x01) continue;
        const aspect_bits = (raw[offset + 1] >> 6) & 0x03;
        const refresh_hz: u16 = @as(u16, raw[offset + 1] & 0x3F) + 60;
        appendTiming(parsed, .{
            .pixel_clock_khz = 0,
            .h_active = width,
            .h_blank = 0,
            .v_active = decodeStandardTimingHeight(width, aspect_bits, parsed.version, parsed.revision),
            .v_blank = 0,
            .refresh_hz = refresh_hz,
        });
    }
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

fn parseCeaExtension(block: []const u8, parsed: *ParsedEdid) void {
    if (block.len < block_len) return;
    parsed.capability_flags |= abi.display_capability_cea_extension;
    if ((block[3] & 0x80) != 0) parsed.capability_flags |= abi.display_capability_underscan;
    if ((block[3] & 0x40) != 0) parsed.capability_flags |= abi.display_capability_basic_audio;
    if ((block[3] & 0x20) != 0) parsed.capability_flags |= abi.display_capability_ycbcr444;
    if ((block[3] & 0x10) != 0) parsed.capability_flags |= abi.display_capability_ycbcr422;

    const dtd_offset = if (block[2] >= 4 and block[2] <= 127) @as(usize, block[2]) else block_len - 1;
    var offset: usize = 4;
    while (offset < dtd_offset and offset < block_len - 1) {
        const header = block[offset];
        const tag = (header >> 5) & 0x07;
        const length = @as(usize, header & 0x1F);
        offset += 1;
        if (offset + length > dtd_offset or offset + length > block_len - 1) break;
        const payload = block[offset .. offset + length];
        if (tag == cea_tag_audio and payload.len > 0) {
            parsed.capability_flags |= abi.display_capability_basic_audio;
        } else if (tag == cea_tag_vendor and payload.len >= hdmi_vendor_oui.len and std.mem.eql(u8, payload[0..hdmi_vendor_oui.len], &hdmi_vendor_oui)) {
            parsed.capability_flags |= abi.display_capability_hdmi_vendor_data;
        }
        offset += length;
    }

    offset = dtd_offset;
    while (offset + 18 <= block_len) : (offset += 18) {
        appendDetailedTiming(parsed, block[offset .. offset + 18]);
    }
}

fn parseExtensionBlocks(raw: []const u8, parsed: *ParsedEdid) ParseError!void {
    const declared_extensions: usize = parsed.extension_count;
    if (declared_extensions == 0) return;
    const required_len = block_len * (declared_extensions + 1);
    if (raw.len < required_len) return error.InvalidLength;

    var extension_index: usize = 0;
    while (extension_index < declared_extensions) : (extension_index += 1) {
        const block_start = block_len * (extension_index + 1);
        const block = raw[block_start .. block_start + block_len];

        var checksum: u8 = 0;
        for (block) |byte| checksum +%= byte;
        if (checksum != 0) return error.InvalidChecksum;

        switch (block[0]) {
            cea_extension_tag => parseCeaExtension(block, parsed),
            displayid_extension_tag => parsed.capability_flags |= abi.display_capability_displayid_extension,
            else => {},
        }
    }
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
        .digital_interface_type = decodeDigitalInterfaceType(raw[20]),
        .physical_width_mm = @as(u16, raw[21]) * 10,
        .physical_height_mm = @as(u16, raw[22]) * 10,
        .extension_count = raw[126],
        .capability_flags = 0,
        .preferred_timing = null,
        .timing_count = 0,
        .timings = [_]Timing{std.mem.zeroes(Timing)} ** max_timings,
        .display_name_len = 0,
        .display_name = [_]u8{0} ** max_name_len,
    };

    if (parsed.input_digital) parsed.capability_flags |= abi.display_capability_digital_input;

    var descriptor_offset: usize = 54;
    while (descriptor_offset + 18 <= block_len) : (descriptor_offset += 18) {
        const descriptor = raw[descriptor_offset .. descriptor_offset + 18];
        appendDetailedTiming(&parsed, descriptor);
        if (parsed.display_name_len == 0) {
            if (parseDisplayName(descriptor)) |name| {
                parsed.display_name_len = name.len;
                parsed.display_name = name.value;
            }
        }
    }

    parseEstablishedTimings(raw, &parsed);
    parseStandardTimings(raw, &parsed);

    try parseExtensionBlocks(raw, &parsed);

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

fn encodeStandardTiming(width: u16, refresh_hz: u16, aspect_bits: u8) [2]u8 {
    return .{
        @as(u8, @intCast(@divExact(width, 8) - 31)),
        @as(u8, @intCast((aspect_bits << 6) | ((refresh_hz - 60) & 0x3F))),
    };
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
    const standard_1280x800 = encodeStandardTiming(1280, 60, 0);
    bytes[38] = standard_1280x800[0];
    bytes[39] = standard_1280x800[1];
    const standard_1024x768 = encodeStandardTiming(1024, 60, 1);
    bytes[40] = standard_1024x768[0];
    bytes[41] = standard_1024x768[1];
    bytes[35] = 0x01; // 800x600@60 established timing
    writeDetailedTiming(bytes[54..72], 7425, 1280, 370, 720, 30);
    setDisplayName(bytes[72..90], "QEMU-EDID");
    finalizeChecksum(&bytes);
    return bytes;
}

fn sampleEdidWithInterface(interface_bits: u8) [block_len]u8 {
    var bytes = sampleEdid();
    bytes[20] = 0x80 | ((interface_bits & 0x07) << 4);
    finalizeChecksum(&bytes);
    return bytes;
}

fn sampleEdidWithCeaExtension() [block_len * 2]u8 {
    var bytes: [block_len * 2]u8 = [_]u8{0} ** (block_len * 2);
    const base = sampleEdid();
    std.mem.copyForwards(u8, bytes[0..block_len], &base);
    bytes[126] = 1;
    finalizeChecksum(bytes[0..block_len]);

    const extension = bytes[block_len .. block_len * 2];
    extension[0] = cea_extension_tag;
    extension[1] = 0x03;
    extension[2] = 8;
    extension[3] = 0xF0;
    extension[4] = 0x63;
    extension[5] = hdmi_vendor_oui[0];
    extension[6] = hdmi_vendor_oui[1];
    extension[7] = hdmi_vendor_oui[2];
    finalizeChecksum(extension);
    return bytes;
}

fn sampleEdidWithDisplayIdExtension() [block_len * 2]u8 {
    var bytes: [block_len * 2]u8 = [_]u8{0} ** (block_len * 2);
    const base = sampleEdid();
    std.mem.copyForwards(u8, bytes[0..block_len], &base);
    bytes[126] = 1;
    finalizeChecksum(bytes[0..block_len]);

    const extension = bytes[block_len .. block_len * 2];
    extension[0] = displayid_extension_tag;
    extension[1] = 0x20;
    extension[2] = 0x00;
    extension[3] = 0x00;
    finalizeChecksum(extension);
    return bytes;
}

fn expectTimingPresent(parsed: ParsedEdid, width: u16, height: u16) !void {
    var index: usize = 0;
    while (index < parsed.timing_count and index < parsed.timings.len) : (index += 1) {
        const timing = parsed.timings[index];
        if (timing.h_active == width and timing.v_active == height) return;
    }
    return error.TestUnexpectedResult;
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
    try std.testing.expectEqual(@as(u8, abi.display_interface_undefined), parsed.digital_interface_type);
    const preferred = parsed.preferred_timing orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u16, 1280), preferred.h_active);
    try std.testing.expectEqual(@as(u16, 720), preferred.v_active);
    try std.testing.expectEqual(@as(u32, 74250), preferred.pixel_clock_khz);
    try std.testing.expect(preferred.refresh_hz >= 60);
    try std.testing.expectEqual(@as(u16, abi.display_capability_digital_input | abi.display_capability_preferred_timing), parsed.capability_flags);
    try std.testing.expectEqualStrings("QEMU-EDID", parsed.display_name[0..parsed.display_name_len]);
    try std.testing.expectEqual(@as(u8, 4), parsed.timing_count);
    try expectTimingPresent(parsed, 1280, 720);
    try expectTimingPresent(parsed, 1280, 800);
    try expectTimingPresent(parsed, 1024, 768);
    try expectTimingPresent(parsed, 800, 600);
}

test "edid parser decodes digital interface type" {
    const hdmi_a = try parse(&sampleEdidWithInterface(2));
    try std.testing.expectEqual(@as(u8, abi.display_interface_hdmi_a), hdmi_a.digital_interface_type);

    const displayport = try parse(&sampleEdidWithInterface(5));
    try std.testing.expectEqual(@as(u8, abi.display_interface_displayport), displayport.digital_interface_type);
}

test "edid parser decodes cea capability flags" {
    const parsed = try parse(&sampleEdidWithCeaExtension());
    try std.testing.expectEqual(@as(u8, 1), parsed.extension_count);
    try std.testing.expect((parsed.capability_flags & abi.display_capability_cea_extension) != 0);
    try std.testing.expect((parsed.capability_flags & abi.display_capability_basic_audio) != 0);
    try std.testing.expect((parsed.capability_flags & abi.display_capability_hdmi_vendor_data) != 0);
    try std.testing.expect((parsed.capability_flags & abi.display_capability_underscan) != 0);
    try std.testing.expect((parsed.capability_flags & abi.display_capability_ycbcr444) != 0);
    try std.testing.expect((parsed.capability_flags & abi.display_capability_ycbcr422) != 0);
}

test "edid parser decodes displayid capability flags" {
    const parsed = try parse(&sampleEdidWithDisplayIdExtension());
    try std.testing.expectEqual(@as(u8, 1), parsed.extension_count);
    try std.testing.expect((parsed.capability_flags & abi.display_capability_displayid_extension) != 0);
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
