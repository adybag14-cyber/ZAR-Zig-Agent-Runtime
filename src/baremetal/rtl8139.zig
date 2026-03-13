const std = @import("std");
const builtin = @import("builtin");
const pci = @import("pci.zig");

pub const Error = error{
    NotPresent,
    NotReady,
    BusyTimeout,
    TxTooLarge,
    RxFrameTooLarge,
};

pub const state_magic: u32 = 0x4F43454E; // "OCEN"
pub const backend_none: u8 = 0;
pub const backend_rtl8139: u8 = 1;

pub const State = extern struct {
    magic: u32,
    api_version: u16,
    backend: u8,
    present: u8,
    initialized: u8,
    hardware_backed: u8,
    link_up: u8,
    reserved0: u8,
    pci_bus: u8,
    pci_device: u8,
    pci_function: u8,
    irq_line: u8,
    io_base: u16,
    reserved1: u16,
    mac: [6]u8,
    reserved2: [2]u8,
    tx_packets: u32,
    tx_errors: u32,
    rx_packets: u32,
    rx_errors: u32,
    last_tx_len: u32,
    last_rx_len: u32,
    last_isr: u16,
    reserved3: u16,
};

pub const tx_buffer_size: usize = 1536;
pub const tx_slot_count: usize = 4;
pub const rx_ring_size: usize = 8192;
pub const rx_buffer_size: usize = rx_ring_size + 16 + 1500;
pub const snapshot_size: usize = 256;

const vendor_realtek: u16 = 0x10EC;
const device_rtl8139: u16 = 0x8139;
const poll_limit: usize = 100_000;

const reg_idr0: u16 = 0x00;
const reg_tsd0: u16 = 0x10;
const reg_tsad0: u16 = 0x20;
const reg_rbstart: u16 = 0x30;
const reg_cr: u16 = 0x37;
const reg_capr: u16 = 0x38;
const reg_cbr: u16 = 0x3A;
const reg_imr: u16 = 0x3C;
const reg_isr: u16 = 0x3E;
const reg_tcr: u16 = 0x40;
const reg_rcr: u16 = 0x44;
const reg_config1: u16 = 0x52;

const cr_rst: u8 = 0x10;
const cr_re: u8 = 0x08;
const cr_te: u8 = 0x04;

const isr_rx_ok: u16 = 0x0001;
const isr_rx_err: u16 = 0x0002;
const isr_tx_ok: u16 = 0x0004;
const isr_tx_err: u16 = 0x0008;

const rcr_wrap: u32 = 1 << 7;
const rcr_accept_all: u32 = 0x0F;
const tcr_default: u32 = 0x0300_0700;

var state: State = undefined;
var tx_slot: u8 = 0;
var tx_buffers: [tx_slot_count][tx_buffer_size]u8 align(16) = [_][tx_buffer_size]u8{[_]u8{0} ** tx_buffer_size} ** tx_slot_count;
var rx_buffer: [rx_buffer_size]u8 align(256) = [_]u8{0} ** rx_buffer_size;
var last_tx_snapshot: [snapshot_size]u8 = [_]u8{0} ** snapshot_size;
var last_rx_snapshot: [snapshot_size]u8 = [_]u8{0} ** snapshot_size;
var rx_offset: u32 = 0;

var mock_rx_frame: [snapshot_size]u8 = [_]u8{0} ** snapshot_size;
var mock_rx_len: u32 = 0;

pub fn resetForTest() void {
    state = .{
        .magic = state_magic,
        .api_version = 2,
        .backend = backend_none,
        .present = 0,
        .initialized = 0,
        .hardware_backed = 0,
        .link_up = 0,
        .reserved0 = 0,
        .pci_bus = 0,
        .pci_device = 0,
        .pci_function = 0,
        .irq_line = 0,
        .io_base = 0,
        .reserved1 = 0,
        .mac = .{ 0, 0, 0, 0, 0, 0 },
        .reserved2 = .{ 0, 0 },
        .tx_packets = 0,
        .tx_errors = 0,
        .rx_packets = 0,
        .rx_errors = 0,
        .last_tx_len = 0,
        .last_rx_len = 0,
        .last_isr = 0,
        .reserved3 = 0,
    };
    tx_slot = 0;
    rx_offset = 0;
    @memset(&tx_buffers, [_]u8{0} ** tx_buffer_size);
    @memset(&rx_buffer, 0);
    @memset(&last_tx_snapshot, 0);
    @memset(&last_rx_snapshot, 0);
    @memset(&mock_rx_frame, 0);
    mock_rx_len = 0;
}

pub fn init() void {
    if (state.initialized != 0) return;
    resetForTest();

    if (!hardwareBacked()) {
        if (builtin.is_test) {
            initMock();
        }
        return;
    }

    initHardware() catch {};
}

pub fn statePtr() *const State {
    return &state;
}

pub fn poll() void {
    if (state.initialized == 0) return;

    if (!hardwareBacked()) {
        if (builtin.is_test and mock_rx_len != 0) {
            const copy_len = @min(snapshot_size, @as(usize, @intCast(mock_rx_len)));
            std.mem.copyForwards(u8, last_rx_snapshot[0..copy_len], mock_rx_frame[0..copy_len]);
            if (copy_len < snapshot_size) {
                @memset(last_rx_snapshot[copy_len..], 0);
            }
            state.rx_packets +%= 1;
            state.last_rx_len = mock_rx_len;
            state.last_isr = isr_rx_ok;
            mock_rx_len = 0;
        }
        return;
    }

    const isr = read16(state.io_base + reg_isr);
    if (isr == 0 or isr == 0xFFFF) return;
    state.last_isr = isr;
    write16(state.io_base + reg_isr, isr);

    if ((isr & isr_rx_err) != 0) state.rx_errors +%= 1;
    if ((isr & isr_tx_err) != 0) state.tx_errors +%= 1;
    if ((isr & isr_rx_ok) != 0) {
        drainReceiveRing();
    }
}

pub fn sendPattern(byte_len: u32, seed: u8) Error!void {
    if (state.initialized == 0 or state.present == 0) return error.NotReady;
    if (byte_len == 0 or byte_len > tx_buffer_size) return error.TxTooLarge;

    const len: usize = @intCast(byte_len);
    const slot_index: usize = tx_slot;
    for (tx_buffers[slot_index][0..len], 0..) |*byte, index| {
        byte.* = seed +% @as(u8, @truncate(index));
    }
    const tx_copy_len = @min(snapshot_size, len);
    std.mem.copyForwards(u8, last_tx_snapshot[0..tx_copy_len], tx_buffers[slot_index][0..tx_copy_len]);
    if (tx_copy_len < snapshot_size) {
        @memset(last_tx_snapshot[tx_copy_len..], 0);
    }
    state.last_tx_len = byte_len;

    if (!hardwareBacked()) {
        state.tx_packets +%= 1;
        state.last_isr = isr_tx_ok;
        tx_slot = @intCast((slot_index + 1) % tx_slot_count);
        return;
    }

    const tsad_reg = reg_tsad0 + (@as(u16, @intCast(slot_index)) * 4);
    const tsd_reg = reg_tsd0 + (@as(u16, @intCast(slot_index)) * 4);
    write32(state.io_base + tsad_reg, @as(u32, @truncate(@intFromPtr(&tx_buffers[slot_index]))));
    write32(state.io_base + tsd_reg, byte_len);

    var attempt: usize = 0;
    while (attempt < poll_limit) : (attempt += 1) {
        const isr = read16(state.io_base + reg_isr);
        if ((isr & isr_tx_ok) != 0) {
            state.last_isr = isr;
            write16(state.io_base + reg_isr, isr);
            state.tx_packets +%= 1;
            tx_slot = @intCast((slot_index + 1) % tx_slot_count);
            return;
        }
        if ((isr & isr_tx_err) != 0) {
            state.last_isr = isr;
            write16(state.io_base + reg_isr, isr);
            state.tx_errors +%= 1;
            tx_slot = @intCast((slot_index + 1) % tx_slot_count);
            return error.BusyTimeout;
        }
        std.atomic.spinLoopHint();
    }

    state.tx_errors +%= 1;
    return error.BusyTimeout;
}

pub fn lastTxByte(index: u32) u8 {
    if (index >= snapshot_size) return 0;
    return last_tx_snapshot[index];
}

pub fn lastRxByte(index: u32) u8 {
    if (index >= snapshot_size) return 0;
    return last_rx_snapshot[index];
}

pub fn testInjectRxFrame(frame: []const u8) void {
    if (!builtin.is_test) return;
    const copy_len = @min(snapshot_size, frame.len);
    std.mem.copyForwards(u8, mock_rx_frame[0..copy_len], frame[0..copy_len]);
    if (copy_len < snapshot_size) {
        @memset(mock_rx_frame[copy_len..], 0);
    }
    mock_rx_len = @as(u32, @intCast(copy_len));
}

fn initMock() void {
    state.backend = backend_rtl8139;
    state.present = 1;
    state.initialized = 1;
    state.hardware_backed = 0;
    state.link_up = 1;
    state.pci_bus = 0;
    state.pci_device = 3;
    state.pci_function = 0;
    state.irq_line = 11;
    state.io_base = 0xC000;
    state.mac = .{ 0x52, 0x54, 0x00, 0x12, 0x34, 0x56 };
}

fn initHardware() Error!void {
    const dev = pci.discoverRealtekRtl8139() orelse return error.NotPresent;
    if (dev.vendor_id != vendor_realtek or dev.device_id != device_rtl8139) return error.NotPresent;

    state.backend = backend_rtl8139;
    state.present = 1;
    state.hardware_backed = 1;
    state.pci_bus = dev.location.bus;
    state.pci_device = dev.location.device;
    state.pci_function = dev.location.function;
    state.irq_line = dev.irq_line;
    state.io_base = dev.io_base;

    write8(state.io_base + reg_config1, 0x00);
    write8(state.io_base + reg_cr, cr_rst);
    try waitResetClear();

    write32(state.io_base + reg_rbstart, @as(u32, @truncate(@intFromPtr(&rx_buffer))));
    write16(state.io_base + reg_capr, 0);
    write16(state.io_base + reg_imr, 0);
    write16(state.io_base + reg_isr, 0xFFFF);
    write32(state.io_base + reg_tcr, tcr_default);
    write32(state.io_base + reg_rcr, rcr_accept_all | rcr_wrap);
    write8(state.io_base + reg_cr, cr_re | cr_te);

    var index: usize = 0;
    while (index < state.mac.len) : (index += 1) {
        state.mac[index] = read8(state.io_base + reg_idr0 + @as(u16, @intCast(index)));
    }
    state.initialized = 1;
    state.link_up = 1;
}

fn waitResetClear() Error!void {
    var attempt: usize = 0;
    while (attempt < poll_limit) : (attempt += 1) {
        if ((read8(state.io_base + reg_cr) & cr_rst) == 0) return;
        std.atomic.spinLoopHint();
    }
    return error.BusyTimeout;
}

fn drainReceiveRing() void {
    var safety: usize = 0;
    while (safety < 16) : (safety += 1) {
        const cbr = read16(state.io_base + reg_cbr);
        if (@as(u16, @truncate(rx_offset)) == cbr) break;

        const frame_status = readRing16(rx_offset);
        const frame_len = readRing16(rx_offset + 2);
        if (frame_len == 0 or frame_len > rx_buffer_size) {
            state.rx_errors +%= 1;
            break;
        }
        if ((frame_status & 0x0001) == 0) {
            state.rx_errors +%= 1;
            break;
        }

        const payload_len = @min(snapshot_size, @as(usize, frame_len));
        copyFromRing((rx_offset + 4) % rx_ring_size, last_rx_snapshot[0..payload_len]);
        if (payload_len < snapshot_size) {
            @memset(last_rx_snapshot[payload_len..], 0);
        }
        state.rx_packets +%= 1;
        state.last_rx_len = frame_len;

        var next = rx_offset + 4 + @as(u32, frame_len);
        next = (next + 3) & ~@as(u32, 3);
        next %= rx_ring_size;
        rx_offset = next;
        const capr_value: u16 = if (next >= 16)
            @truncate(next - 16)
        else
            @truncate((rx_ring_size + next) - 16);
        write16(state.io_base + reg_capr, capr_value);
    }
}

fn readRing16(offset: u32) u16 {
    const lo = ringByte(offset);
    const hi = ringByte(offset + 1);
    return @as(u16, lo) | (@as(u16, hi) << 8);
}

fn ringByte(offset: u32) u8 {
    const idx: usize = @intCast(offset % rx_ring_size);
    return rx_buffer[idx];
}

fn copyFromRing(offset: u32, out: []u8) void {
    var idx: usize = 0;
    while (idx < out.len) : (idx += 1) {
        out[idx] = ringByte(offset + @as(u32, @intCast(idx)));
    }
}

fn hardwareBacked() bool {
    return builtin.os.tag == .freestanding and builtin.cpu.arch == .x86_64;
}

fn read8(port: u16) u8 {
    return asm volatile ("inb %[dx], %[al]"
        : [al] "={al}" (-> u8),
        : [dx] "{dx}" (port),
        : "memory");
}

fn read16(port: u16) u16 {
    return asm volatile ("inw %[dx], %[ax]"
        : [ax] "={ax}" (-> u16),
        : [dx] "{dx}" (port),
        : "memory");
}

fn write8(port: u16, value: u8) void {
    asm volatile ("outb %[al], %[dx]"
        :
        : [dx] "{dx}" (port),
          [al] "{al}" (value),
        : "memory");
}

fn write16(port: u16, value: u16) void {
    asm volatile ("outw %[ax], %[dx]"
        :
        : [dx] "{dx}" (port),
          [ax] "{ax}" (value),
        : "memory");
}

fn write32(port: u16, value: u32) void {
    asm volatile ("outl %[eax], %[dx]"
        :
        : [dx] "{dx}" (port),
          [eax] "{eax}" (value),
        : "memory");
}

test "rtl8139 mock init exposes deterministic state" {
    resetForTest();
    init();
    const nic = statePtr();
    try std.testing.expectEqual(@as(u32, state_magic), nic.magic);
    try std.testing.expectEqual(@as(u8, backend_rtl8139), nic.backend);
    try std.testing.expectEqual(@as(u8, 1), nic.present);
    try std.testing.expectEqual(@as(u8, 1), nic.initialized);
    try std.testing.expectEqual(@as(u8, 0), nic.hardware_backed);
    try std.testing.expectEqualSlices(u8, &.{ 0x52, 0x54, 0x00, 0x12, 0x34, 0x56 }, &nic.mac);
}

test "rtl8139 mock send pattern updates tx snapshot and counters" {
    resetForTest();
    init();
    try sendPattern(8, 0x41);
    const nic = statePtr();
    try std.testing.expectEqual(@as(u32, 1), nic.tx_packets);
    try std.testing.expectEqual(@as(u32, 8), nic.last_tx_len);
    try std.testing.expectEqual(@as(u8, 0x41), lastTxByte(0));
    try std.testing.expectEqual(@as(u8, 0x42), lastTxByte(1));
    try std.testing.expectEqual(@as(u16, isr_tx_ok), nic.last_isr);
}

test "rtl8139 mock poll consumes injected rx frame" {
    resetForTest();
    init();
    testInjectRxFrame(&.{ 0xDE, 0xAD, 0xBE, 0xEF });
    poll();
    const nic = statePtr();
    try std.testing.expectEqual(@as(u32, 1), nic.rx_packets);
    try std.testing.expectEqual(@as(u32, 4), nic.last_rx_len);
    try std.testing.expectEqual(@as(u8, 0xDE), lastRxByte(0));
    try std.testing.expectEqual(@as(u8, 0xAD), lastRxByte(1));
    try std.testing.expectEqual(@as(u16, isr_rx_ok), nic.last_isr);
}
