const std = @import("std");
const builtin = @import("builtin");
const abi = @import("abi.zig");
const pci = @import("pci.zig");

pub const Error = error{
    NotAvailable,
    NotInitialized,
    FrameTooLarge,
    Timeout,
    HardwareFault,
};

pub const InitError = error{
    UnsupportedPlatform,
    DeviceNotFound,
    ResetTimeout,
    BufferProgramFailed,
    MacReadFailed,
    DataPathEnableFailed,
};

const pci_vendor_id: u16 = 0x10EC;
const pci_device_id: u16 = 0x8139;
const tx_descriptor_count: usize = 4;
const tx_buffer_capacity: usize = 2048;
const rx_ring_bytes: usize = 8192;
const rx_ring_allocation_bytes: usize = rx_ring_bytes + 16 + 1500;
const rx_snapshot_capacity: usize = 2048;
const min_frame_len: usize = 60;
const tx_poll_limit: usize = 100_000;

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

const cr_re: u8 = 0x08;
const cr_te: u8 = 0x04;
const cr_rst: u8 = 0x10;

const isr_rok: u16 = 0x0001;
const isr_rer: u16 = 0x0002;
const isr_tok: u16 = 0x0004;
const isr_ter: u16 = 0x0008;
const isr_rxovw: u16 = 0x0010;
const isr_all_known: u16 = 0xFFFF;

const tsd_tok: u32 = 0x0000_8000;
const tsd_tabt: u32 = 0x4000_0000;
const tsd_owc: u32 = 0x2000_0000;
const tsd_tun: u32 = 0x4000_0000;
const tsd_carrier_lost: u32 = 0x8000_0000;

const tcr_mxdma_unlimited: u32 = 7 << 8;
const tcr_loopback_internal: u32 = 3 << 17;
const tcr_ifg96: u32 = 3 << 24;

const rcr_aap: u32 = 1 << 0;
const rcr_apm: u32 = 1 << 1;
const rcr_ab: u32 = 1 << 3;
const rcr_wrap: u32 = 1 << 7;
const rcr_mxdma_unlimited: u32 = 7 << 8;
const rcr_rblen_8k: u32 = 0 << 11;

const default_mock_mac = [6]u8{ 0x52, 0x54, 0x00, 0x12, 0x34, 0x56 };

fn defaultState() abi.BaremetalEthernetState {
    return .{
        .magic = abi.ethernet_magic,
        .api_version = abi.api_version,
        .backend = abi.ethernet_backend_none,
        .initialized = 0,
        .hardware_backed = 0,
        .tx_enabled = 0,
        .rx_enabled = 0,
        .loopback_enabled = 0,
        .link_up = 0,
        .pci_bus = 0,
        .pci_device = 0,
        .pci_function = 0,
        .irq_line = 0,
        .reserved0 = .{ 0, 0, 0 },
        .io_base = 0,
        .tx_packets = 0,
        .rx_packets = 0,
        .tx_errors = 0,
        .rx_errors = 0,
        .rx_overflows = 0,
        .last_tx_len = 0,
        .last_rx_len = 0,
        .last_tx_status = 0,
        .last_rx_status = 0,
        .tx_index = 0,
        .reserved1 = .{ 0, 0, 0 },
        .mac = .{ 0, 0, 0, 0, 0, 0 },
        .reserved2 = .{ 0, 0 },
        .rx_consumer_offset = 0,
    };
}

var state: abi.BaremetalEthernetState = defaultState();
var tx_buffers: [tx_descriptor_count][tx_buffer_capacity]u8 align(16) = [_][tx_buffer_capacity]u8{[_]u8{0} ** tx_buffer_capacity} ** tx_descriptor_count;
var rx_ring: [rx_ring_allocation_bytes]u8 align(16) = [_]u8{0} ** rx_ring_allocation_bytes;
var rx_snapshot: [rx_snapshot_capacity]u8 = [_]u8{0} ** rx_snapshot_capacity;
var mock_enabled: bool = false;
var mock_pending_rx_len: u32 = 0;
var mock_pending_rx_status: u32 = 0;
const SendHook = *const fn (frame: []const u8) void;
var mock_send_hook: ?SendHook = null;
var probe_send_hook: ?SendHook = null;
var probe_pending_rx_len: u32 = 0;
var probe_pending_rx_status: u32 = 0;

pub fn resetForTest() void {
    resetState();
    @memset(&tx_buffers, [_]u8{0} ** tx_buffer_capacity);
    @memset(&rx_ring, 0);
    @memset(&rx_snapshot, 0);
    mock_enabled = false;
    mock_pending_rx_len = 0;
    mock_pending_rx_status = 0;
    mock_send_hook = null;
    probe_send_hook = null;
    probe_pending_rx_len = 0;
    probe_pending_rx_status = 0;
}

pub fn testEnableMockDevice() void {
    if (!builtin.is_test) return;
    resetForTest();
    mock_enabled = true;
}

pub fn testDisableMockDevice() void {
    if (!builtin.is_test) return;
    resetForTest();
}

pub fn testInstallMockSendHook(hook: ?SendHook) void {
    if (!builtin.is_test) return;
    mock_send_hook = hook;
}

pub fn installProbeSendHook(hook: ?SendHook) void {
    probe_send_hook = hook;
}

pub fn injectProbeReceive(frame: []const u8) void {
    const rx_len: usize = @min(frame.len, rx_snapshot_capacity);
    std.mem.copyForwards(u8, rx_snapshot[0..rx_len], frame[0..rx_len]);
    probe_pending_rx_len = @as(u32, @intCast(rx_len));
    probe_pending_rx_status = isr_rok;
}

pub fn statePtr() *const abi.BaremetalEthernetState {
    return &state;
}

pub fn init() bool {
    initDetailed() catch return false;
    return true;
}

pub fn initDetailed() InitError!void {
    if (state.magic != abi.ethernet_magic or state.api_version != abi.api_version) {
        resetState();
    }
    if (state.initialized != 0) return;

    resetState();
    if (mockAvailable()) {
        initMock();
        return;
    }
    if (!hardwareBacked()) return error.UnsupportedPlatform;

    const nic = pci.discoverRtl8139() orelse return error.DeviceNotFound;
    pci.enableRtl8139IoAndBusMaster(nic.location);

    state.backend = abi.ethernet_backend_rtl8139;
    state.pci_bus = nic.location.bus;
    state.pci_device = nic.location.device;
    state.pci_function = nic.location.function;
    state.irq_line = nic.irq_line;
    state.io_base = nic.io_base;
    state.hardware_backed = 1;
    state.loopback_enabled = 1;

    powerUp(nic.io_base);
    if (!softReset(nic.io_base)) {
        resetState();
        return error.ResetTimeout;
    }
    if (!programBuffers(nic.io_base)) {
        resetState();
        return error.BufferProgramFailed;
    }

    readMac(nic.io_base, &state.mac);
    if (macIsZero(state.mac)) {
        resetState();
        return error.MacReadFailed;
    }

    if (!ensureDataPath(nic.io_base)) {
        resetState();
        return error.DataPathEnableFailed;
    }

    // Re-acknowledge any latched status after the engine transitions to RE|TE.
    write16(nic.io_base + reg_isr, isr_all_known);
    // Reassert the intended loopback-friendly config after enable so the
    // runtime path is not relying on pre-enable register state.
    write32(nic.io_base + reg_tcr, tcr_mxdma_unlimited | tcr_ifg96 | tcr_loopback_internal);
    write32(nic.io_base + reg_rcr, rcr_aap | rcr_apm | rcr_ab | rcr_wrap | rcr_mxdma_unlimited | rcr_rblen_8k);

    state.initialized = 1;
    return;
}

pub fn macByte(index: u32) u8 {
    if (index >= state.mac.len) return 0;
    return state.mac[index];
}

pub fn sendPattern(byte_len: u32, seed: u8) Error!u32 {
    if (state.initialized == 0 and !init()) return error.NotAvailable;
    const requested_len: usize = @intCast(byte_len);
    const send_len = @min(tx_buffer_capacity, @max(min_frame_len, requested_len));
    var frame = [_]u8{0} ** tx_buffer_capacity;
    buildPatternFrame(frame[0..send_len], seed, state.mac);
    try sendFrame(frame[0..send_len]);
    return @as(u32, @intCast(send_len));
}

pub fn sendFrame(frame: []const u8) Error!void {
    if (state.initialized == 0 and !init()) return error.NotAvailable;
    if (frame.len > tx_buffer_capacity) return error.FrameTooLarge;

    const tx_slot: usize = state.tx_index;
    const send_len: usize = @max(min_frame_len, frame.len);
    const tx_buf = tx_buffers[tx_slot][0..send_len];
    @memset(tx_buf, 0);
    std.mem.copyForwards(u8, tx_buf[0..frame.len], frame);

    if (probe_send_hook) |hook| {
        hook(tx_buf[0..send_len]);
    }

    if (mockAvailable()) {
        if (mock_send_hook) |hook| {
            hook(tx_buf[0..send_len]);
        } else {
            queueMockReceive(tx_buf[0..send_len]);
        }
        state.tx_packets +%= 1;
        state.last_tx_len = @as(u32, @intCast(send_len));
        state.last_tx_status = tsd_tok;
        state.tx_index = @as(u8, @intCast((tx_slot + 1) % tx_descriptor_count));
        return;
    }

    const io_base: u16 = @intCast(state.io_base & 0xFFFF);
    if (!ensureDataPath(io_base)) {
        state.tx_errors +%= 1;
        return error.HardwareFault;
    }
    write32(io_base + reg_tsd0 + (@as(u16, @intCast(tx_slot)) * 4), @as(u32, @intCast(send_len)));
    const status_word = pollTxStatus(io_base, tx_slot) catch |err| {
        state.tx_errors +%= 1;
        return err;
    };

    state.tx_packets +%= 1;
    state.last_tx_len = @as(u32, @intCast(send_len));
    state.last_tx_status = status_word;
    state.tx_index = @as(u8, @intCast((tx_slot + 1) % tx_descriptor_count));
}

pub fn pollReceive() Error!u32 {
    if (state.initialized == 0 and !init()) return error.NotAvailable;

    if (probe_pending_rx_len != 0) {
        state.last_rx_len = probe_pending_rx_len;
        state.last_rx_status = probe_pending_rx_status;
        state.rx_packets +%= 1;
        probe_pending_rx_len = 0;
        probe_pending_rx_status = 0;
        return state.last_rx_len;
    }

    if (mockAvailable()) {
        if (mock_pending_rx_len == 0) return 0;
        state.last_rx_len = mock_pending_rx_len;
        state.last_rx_status = mock_pending_rx_status;
        state.rx_packets +%= 1;
        mock_pending_rx_len = 0;
        mock_pending_rx_status = 0;
        return state.last_rx_len;
    }

    const io_base: u16 = @intCast(state.io_base & 0xFFFF);
    if (!ensureDataPath(io_base)) {
        state.rx_errors +%= 1;
        return error.HardwareFault;
    }
    const producer = read16(io_base + reg_cbr);
    if (producer == @as(u16, @intCast(state.rx_consumer_offset))) {
        return 0;
    }

    const packet_offset: usize = @intCast(state.rx_consumer_offset);
    const header = readU32Le(rx_ring[packet_offset .. packet_offset + 4]);
    const packet_status: u16 = @as(u16, @truncate(header));
    const total_len: usize = @as(usize, @intCast(header >> 16));
    if ((packet_status & isr_rok) == 0 or total_len < 4) {
        state.rx_errors +%= 1;
        write16(io_base + reg_isr, isr_rer | isr_rxovw | isr_rok);
        return error.HardwareFault;
    }

    const payload_len: usize = @min(total_len - 4, rx_snapshot_capacity);
    std.mem.copyForwards(u8, rx_snapshot[0..payload_len], rx_ring[packet_offset + 4 .. packet_offset + 4 + payload_len]);
    state.last_rx_len = @as(u32, @intCast(payload_len));
    state.last_rx_status = packet_status;
    state.rx_packets +%= 1;

    var next_offset: usize = packet_offset + total_len + 4;
    next_offset = (next_offset + 3) & ~@as(usize, 3);
    next_offset %= rx_ring_bytes;
    state.rx_consumer_offset = @as(u32, @intCast(next_offset));
    const capr_value: u16 = @as(u16, @intCast((next_offset + rx_ring_bytes - 16) % rx_ring_bytes));
    write16(io_base + reg_capr, capr_value);
    write16(io_base + reg_isr, isr_rok | isr_rer | isr_rxovw | isr_tok | isr_ter);
    return state.last_rx_len;
}

pub fn rxByte(index: u32) u8 {
    if (index >= state.last_rx_len or index >= rx_snapshot_capacity) return 0;
    return rx_snapshot[index];
}

pub fn debugProducerOffset() u16 {
    if (state.initialized == 0) return 0;
    if (mockAvailable()) return @as(u16, @intCast(state.rx_consumer_offset & 0xFFFF));
    const io_base: u16 = @intCast(state.io_base & 0xFFFF);
    return read16(io_base + reg_cbr);
}

pub fn debugInterruptStatus() u16 {
    if (state.initialized == 0) return 0;
    if (mockAvailable()) return isr_rok;
    const io_base: u16 = @intCast(state.io_base & 0xFFFF);
    return read16(io_base + reg_isr);
}

pub fn debugCommandRegister() u8 {
    if (state.initialized == 0) return 0;
    if (mockAvailable()) return cr_re | cr_te;
    const io_base: u16 = @intCast(state.io_base & 0xFFFF);
    return read8(io_base + reg_cr);
}

pub fn debugLastTxStatus() u32 {
    if (state.initialized == 0) return 0;
    if (mockAvailable()) return state.last_tx_status;
    const io_base: u16 = @intCast(state.io_base & 0xFFFF);
    const slot = if (state.tx_index == 0) tx_descriptor_count - 1 else @as(usize, state.tx_index) - 1;
    return read32(io_base + reg_tsd0 + (@as(u16, @intCast(slot)) * 4));
}

fn resetState() void {
    state = defaultState();
}

fn initMock() void {
    state.backend = abi.ethernet_backend_rtl8139;
    state.initialized = 1;
    state.hardware_backed = 0;
    state.tx_enabled = 1;
    state.rx_enabled = 1;
    state.loopback_enabled = 1;
    state.link_up = 1;
    state.io_base = 0xC100;
    state.irq_line = 11;
    state.mac = default_mock_mac;
}

fn mockAvailable() bool {
    return builtin.is_test and mock_enabled;
}

fn hardwareBacked() bool {
    return builtin.os.tag == .freestanding and builtin.cpu.arch == .x86_64;
}

fn macIsZero(mac: [6]u8) bool {
    for (mac) |byte| {
        if (byte != 0) return false;
    }
    return true;
}

fn powerUp(io_base: u16) void {
    write8(io_base + reg_config1, 0x00);
}

fn softReset(io_base: u16) bool {
    write8(io_base + reg_cr, cr_rst);
    var attempts: usize = 0;
    while (attempts < tx_poll_limit) : (attempts += 1) {
        if ((read8(io_base + reg_cr) & cr_rst) == 0) return true;
        std.atomic.spinLoopHint();
    }
    return false;
}

fn programBuffers(io_base: u16) bool {
    const rx_addr = ptr32(&rx_ring) orelse return false;
    write32(io_base + reg_rbstart, rx_addr);

    var index: usize = 0;
    while (index < tx_descriptor_count) : (index += 1) {
        const tx_addr = ptr32(&tx_buffers[index]) orelse return false;
        write32(io_base + reg_tsad0 + (@as(u16, @intCast(index)) * 4), tx_addr);
        write32(io_base + reg_tsd0 + (@as(u16, @intCast(index)) * 4), 0);
    }

    state.rx_consumer_offset = 0;
    write16(io_base + reg_capr, 0xFFF0);
    write16(io_base + reg_imr, 0);
    write16(io_base + reg_isr, isr_all_known);
    write32(io_base + reg_tcr, tcr_mxdma_unlimited | tcr_ifg96 | tcr_loopback_internal);
    write32(io_base + reg_rcr, rcr_aap | rcr_apm | rcr_ab | rcr_wrap | rcr_mxdma_unlimited | rcr_rblen_8k);
    return true;
}

fn readMac(io_base: u16, out: *[6]u8) void {
    var index: usize = 0;
    while (index < out.len) : (index += 1) {
        out[index] = read8(io_base + reg_idr0 + @as(u16, @intCast(index)));
    }
}

fn ensureDataPath(io_base: u16) bool {
    if (state.tx_enabled != 0 and state.rx_enabled != 0) return true;
    write8(io_base + reg_cr, cr_re | cr_te);
    const status = read8(io_base + reg_cr);
    if ((status & (cr_re | cr_te)) != (cr_re | cr_te)) return false;
    state.tx_enabled = 1;
    state.rx_enabled = 1;
    state.link_up = 1;
    return true;
}

fn pollTxStatus(io_base: u16, tx_slot: usize) Error!u32 {
    const tsd_offset = io_base + reg_tsd0 + (@as(u16, @intCast(tx_slot)) * 4);
    var attempts: usize = 0;
    while (attempts < tx_poll_limit) : (attempts += 1) {
        const status_word = read32(tsd_offset);
        if ((status_word & tsd_tok) != 0) return status_word;
        if ((status_word & (tsd_tabt | tsd_owc | tsd_carrier_lost | tsd_tun)) != 0) return error.HardwareFault;
        std.atomic.spinLoopHint();
    }
    return error.Timeout;
}

fn queueMockReceive(frame: []const u8) void {
    const rx_len: usize = @min(frame.len, rx_snapshot_capacity);
    std.mem.copyForwards(u8, rx_snapshot[0..rx_len], frame[0..rx_len]);
    mock_pending_rx_len = @as(u32, @intCast(rx_len));
    mock_pending_rx_status = isr_rok;
}

fn buildPatternFrame(frame: []u8, seed: u8, mac: [6]u8) void {
    const dest = frame[0..6];
    const src = frame[6..12];
    std.mem.copyForwards(u8, dest, mac[0..]);
    std.mem.copyForwards(u8, src, mac[0..]);
    frame[12] = 0x88;
    frame[13] = 0xB5;
    var index: usize = 14;
    while (index < frame.len) : (index += 1) {
        frame[index] = seed +% @as(u8, @truncate(index - 14));
    }
}

fn ptr32(ptr: anytype) ?u32 {
    const value = @intFromPtr(ptr);
    if (value > std.math.maxInt(u32)) return null;
    return @as(u32, @intCast(value));
}

fn readU32Le(bytes: []const u8) u32 {
    return @as(u32, bytes[0]) |
        (@as(u32, bytes[1]) << 8) |
        (@as(u32, bytes[2]) << 16) |
        (@as(u32, bytes[3]) << 24);
}

fn read8(port: u16) u8 {
    if (!hardwareBacked()) return 0;
    return asm volatile ("inb %[dx], %[al]"
        : [al] "={al}" (-> u8),
        : [dx] "{dx}" (port),
        : "memory");
}

fn write8(port: u16, value: u8) void {
    if (!hardwareBacked()) return;
    asm volatile ("outb %[al], %[dx]"
        :
        : [dx] "{dx}" (port),
          [al] "{al}" (value),
        : "memory");
}

fn read16(port: u16) u16 {
    if (!hardwareBacked()) return 0;
    return asm volatile ("inw %[dx], %[ax]"
        : [ax] "={ax}" (-> u16),
        : [dx] "{dx}" (port),
        : "memory");
}

fn write16(port: u16, value: u16) void {
    if (!hardwareBacked()) return;
    asm volatile ("outw %[ax], %[dx]"
        :
        : [dx] "{dx}" (port),
          [ax] "{ax}" (value),
        : "memory");
}

fn read32(port: u16) u32 {
    if (!hardwareBacked()) return 0;
    return asm volatile ("inl %[dx], %[eax]"
        : [eax] "={eax}" (-> u32),
        : [dx] "{dx}" (port),
        : "memory");
}

fn write32(port: u16, value: u32) void {
    if (!hardwareBacked()) return;
    asm volatile ("outl %[eax], %[dx]"
        :
        : [dx] "{dx}" (port),
          [eax] "{eax}" (value),
        : "memory");
}

test "rtl8139 mock init and loopback send path exports stable state" {
    testEnableMockDevice();
    defer testDisableMockDevice();

    try std.testing.expect(init());
    const eth = statePtr();
    try std.testing.expectEqual(@as(u32, abi.ethernet_magic), eth.magic);
    try std.testing.expectEqual(@as(u8, abi.ethernet_backend_rtl8139), eth.backend);
    try std.testing.expectEqual(@as(u8, 1), eth.initialized);
    try std.testing.expectEqual(@as(u8, 1), eth.loopback_enabled);
    try std.testing.expectEqual(@as(u8, 0x52), macByte(0));

    const sent_len = try sendPattern(96, 0x41);
    try std.testing.expectEqual(@as(u32, 96), sent_len);
    const recv_len = try pollReceive();
    try std.testing.expectEqual(sent_len, recv_len);
    try std.testing.expectEqual(@as(u8, 0x52), rxByte(0));
    try std.testing.expectEqual(@as(u8, 0x88), rxByte(12));
    try std.testing.expectEqual(@as(u8, 0xB5), rxByte(13));
    try std.testing.expectEqual(@as(u8, 0x41), rxByte(14));
    try std.testing.expectEqual(@as(u32, 1), eth.tx_packets);
    try std.testing.expectEqual(@as(u32, 1), eth.rx_packets);
}
