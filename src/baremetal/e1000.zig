// SPDX-License-Identifier: GPL-2.0-only
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
    MissingMmioBar,
    MissingIoBar,
    ResetTimeout,
    AutoReadTimeout,
    EepromReadFailed,
    EepromChecksumMismatch,
    MacReadFailed,
    RingProgramFailed,
};

const pci_vendor_id: u16 = 0x8086;
const pci_device_id_82540em: u16 = 0x100E;
const tx_descriptor_count: usize = 64;
const rx_descriptor_count: usize = 64;
const tx_buffer_capacity: usize = 2048;
const rx_buffer_capacity: usize = 2048;
const rx_snapshot_capacity: usize = 2048;
const min_frame_len: usize = 60;
const tx_poll_limit: usize = 100_000;
const reset_poll_limit: usize = 100_000;
const eeprom_poll_limit: usize = 100_000;
const reset_settle_loops: usize = 2_000_000;
const eeprom_word_count: u8 = 64;
const eeprom_checksum_expected: u16 = 0xBABA;

const reg_ctrl: u32 = 0x00000;
const reg_status: u32 = 0x00008;
const reg_eecd: u32 = 0x00010;
const reg_eerd: u32 = 0x00014;
const reg_mdic: u32 = 0x00020;
const reg_icr: u32 = 0x000C0;
const reg_imc: u32 = 0x000D8;
const reg_rctl: u32 = 0x00100;
const reg_tctl: u32 = 0x00400;
const reg_tipg: u32 = 0x00410;
const reg_rdbal: u32 = 0x02800;
const reg_rdbah: u32 = 0x02804;
const reg_rdlen: u32 = 0x02808;
const reg_rdh: u32 = 0x02810;
const reg_rdt: u32 = 0x02818;
const reg_tdbal: u32 = 0x03800;
const reg_tdbah: u32 = 0x03804;
const reg_tdlen: u32 = 0x03808;
const reg_tdh: u32 = 0x03810;
const reg_tdt: u32 = 0x03818;
const reg_ral0: u32 = 0x05400;
const reg_rah0: u32 = 0x05404;

const ctrl_slu: u32 = 0x0000_0040;
const ctrl_rst: u32 = 0x0400_0000;
const status_lu: u32 = 0x0000_0002;
const eerd_start: u32 = 0x0000_0001;
const eerd_done: u32 = 0x0000_0010;
const eerd_addr_shift: u5 = 8;
const eerd_data_shift: u5 = 16;
const rah_av: u32 = 0x8000_0000;

const rctl_en: u32 = 0x0000_0002;
const rctl_rdmts_half: u32 = 0x0000_0000;
const rctl_bam: u32 = 0x0000_8000;
const rctl_sz_2048: u32 = 0x0000_0000;
const rctl_secrc: u32 = 0x0400_0000;

const tctl_en: u32 = 0x0000_0002;
const tctl_psp: u32 = 0x0000_0008;
const tctl_rtlc: u32 = 0x0100_0000;
const collision_threshold: u32 = 15;
const collision_distance: u32 = 63;
const ct_shift: u5 = 4;
const cold_shift: u5 = 12;
const tipg_ipgt: u32 = 8;
const tipg_ipgr1: u32 = 8;
const tipg_ipgr2: u32 = 6;
const tipg_ipgr1_shift: u5 = 10;
const tipg_ipgr2_shift: u5 = 20;

const txd_cmd_eop: u8 = 0x01;
const txd_cmd_ifcs: u8 = 0x02;
const txd_cmd_rs: u8 = 0x08;
const txd_stat_dd: u8 = 0x01;
const rxd_stat_dd: u8 = 0x01;
const rxd_stat_eop: u8 = 0x02;

const mdic_reg_shift: u5 = 16;
const mdic_phy_shift: u5 = 21;
const mdic_op_write: u32 = 0x0400_0000;
const mdic_op_read: u32 = 0x0800_0000;
const mdic_ready: u32 = 0x1000_0000;
const mdic_error: u32 = 0x4000_0000;
const mdic_phy_address: u32 = 1;
const phy_reg_bmcr: u8 = 0;
const bmcr_loopback: u16 = 0x4000;

const default_mock_mac = [6]u8{ 0x52, 0x54, 0x00, 0xA1, 0x00, 0xE1 };

const TxDesc = extern struct {
    buffer_addr: u64,
    length: u16,
    cso: u8,
    cmd: u8,
    status: u8,
    css: u8,
    special: u16,
};

const RxDesc = extern struct {
    buffer_addr: u64,
    length: u16,
    checksum: u16,
    status: u8,
    errors: u8,
    special: u16,
};

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
var tx_desc_ring: [tx_descriptor_count]TxDesc align(128) = undefined;
var rx_desc_ring: [rx_descriptor_count]RxDesc align(128) = undefined;
var tx_buffers: [tx_descriptor_count][tx_buffer_capacity]u8 align(16) = undefined;
var rx_buffers: [rx_descriptor_count][rx_buffer_capacity]u8 align(16) = undefined;
var tx_snapshot: [tx_buffer_capacity]u8 = [_]u8{0} ** tx_buffer_capacity;
var rx_snapshot: [rx_snapshot_capacity]u8 = [_]u8{0} ** rx_snapshot_capacity;
var active_mmio_base: usize = 0;
var active_io_base: u16 = 0;
var tx_next_to_clean: usize = 0;

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
    resetBuffers();
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
    probe_pending_rx_status = rxd_stat_dd | rxd_stat_eop;
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
    resetBuffers();
    if (mockAvailable()) {
        initMock();
        return;
    }
    if (!hardwareBacked()) return error.UnsupportedPlatform;

    const nic = pci.discoverE1000() orelse return error.DeviceNotFound;
    if (nic.mmio_base == 0) return error.MissingMmioBar;
    if (nic.io_base == 0) return error.MissingIoBar;
    pci.enableE1000MemoryAndBusMaster(nic.location);

    active_mmio_base = @as(usize, @intCast(nic.mmio_base));
    active_io_base = nic.io_base;

    state.backend = abi.ethernet_backend_e1000;
    state.pci_bus = nic.location.bus;
    state.pci_device = nic.location.device;
    state.pci_function = nic.location.function;
    state.irq_line = nic.irq_line;
    state.io_base = nic.io_base;
    state.hardware_backed = 1;

    try resetHardware();
    try validateAndReadMac(&state.mac);
    try programRings();
    state.initialized = 1;
}

pub fn enableMacLoopbackForProbe() Error!void {
    if (state.initialized == 0 and !init()) return error.NotAvailable;
    if (mockAvailable()) {
        state.loopback_enabled = 1;
        return;
    }
    if (!hardwareBacked() or active_mmio_base == 0) return error.NotInitialized;
    const bmcr = readPhyRegister(phy_reg_bmcr) catch return error.HardwareFault;
    writePhyRegister(phy_reg_bmcr, bmcr | bmcr_loopback) catch return error.HardwareFault;
    const loopback_bmcr = readPhyRegister(phy_reg_bmcr) catch return error.HardwareFault;
    if ((loopback_bmcr & bmcr_loopback) == 0) return error.HardwareFault;
    state.loopback_enabled = 1;
    state.link_up = 1;
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
    std.mem.copyForwards(u8, tx_snapshot[0..send_len], tx_buf[0..send_len]);
    state.last_tx_len = @as(u32, @intCast(send_len));
    state.last_tx_status = 0;

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
        state.last_tx_status = txd_stat_dd;
        state.tx_index = @as(u8, @intCast((tx_slot + 1) % tx_descriptor_count));
        return;
    }

    const next_slot: usize = (tx_slot + 1) % tx_descriptor_count;
    if (!waitForTxSpace(next_slot)) {
        state.tx_errors +%= 1;
        return error.Timeout;
    }

    const tx_desc = txDescPtr(tx_slot);
    tx_desc.buffer_addr = ptr64(&tx_buffers[tx_slot]) orelse return error.HardwareFault;
    tx_desc.length = @as(u16, @intCast(send_len));
    tx_desc.cso = 0;
    tx_desc.cmd = txd_cmd_eop | txd_cmd_ifcs | txd_cmd_rs;
    tx_desc.status = 0;
    tx_desc.css = 0;
    tx_desc.special = 0;

    compilerFence();
    writeMmio32(reg_tdt, @as(u32, @intCast(next_slot)));
    flushMmio();

    state.tx_packets +%= 1;
    state.last_tx_status = tx_desc.status;
    state.tx_index = @as(u8, @intCast(next_slot));
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

    const rx_slot: usize = @as(usize, @intCast(state.rx_consumer_offset % rx_descriptor_count));
    const desc = rxDescPtr(rx_slot);
    const status = desc.status;
    if ((status & rxd_stat_dd) == 0) return 0;
    if ((status & rxd_stat_eop) == 0) {
        state.rx_errors +%= 1;
        return error.HardwareFault;
    }

    const frame_len: usize = @min(@as(usize, desc.length), rx_snapshot_capacity);
    std.mem.copyForwards(u8, rx_snapshot[0..frame_len], rx_buffers[rx_slot][0..frame_len]);
    state.last_rx_len = @as(u32, @intCast(frame_len));
    state.last_rx_status = status;
    state.rx_packets +%= 1;

    desc.length = 0;
    desc.checksum = 0;
    desc.status = 0;
    desc.errors = 0;
    desc.special = 0;
    desc.buffer_addr = ptr64(&rx_buffers[rx_slot]) orelse return error.HardwareFault;

    compilerFence();
    writeMmio32(reg_rdt, @as(u32, @intCast(rx_slot)));
    flushMmio();
    state.rx_consumer_offset = @as(u32, @intCast((rx_slot + 1) % rx_descriptor_count));
    return state.last_rx_len;
}

pub fn rxByte(index: u32) u8 {
    if (index >= state.last_rx_len or index >= rx_snapshot_capacity) return 0;
    return rx_snapshot[index];
}

pub fn txByte(index: u32) u8 {
    if (index >= state.last_tx_len or index >= tx_buffer_capacity) return 0;
    return tx_snapshot[index];
}

pub fn debugStatus() u32 {
    if (state.initialized == 0 or mockAvailable() or active_mmio_base == 0) return 0;
    return readMmio32(reg_status);
}

pub fn debugLoopbackEnabled() bool {
    if (state.initialized == 0) return false;
    if (mockAvailable()) return state.loopback_enabled != 0;
    const bmcr = readPhyRegister(phy_reg_bmcr) catch return false;
    return (bmcr & bmcr_loopback) != 0;
}

pub fn debugTxHead() u32 {
    if (state.initialized == 0 or mockAvailable() or active_mmio_base == 0) return 0;
    return readMmio32(reg_tdh);
}

pub fn debugTxTail() u32 {
    if (state.initialized == 0 or mockAvailable() or active_mmio_base == 0) return 0;
    return readMmio32(reg_tdt);
}

pub fn debugRxHead() u32 {
    if (state.initialized == 0 or mockAvailable() or active_mmio_base == 0) return 0;
    return readMmio32(reg_rdh);
}

pub fn debugRxTail() u32 {
    if (state.initialized == 0 or mockAvailable() or active_mmio_base == 0) return 0;
    return readMmio32(reg_rdt);
}

fn resetState() void {
    state = defaultState();
    active_mmio_base = 0;
    active_io_base = 0;
    tx_next_to_clean = 0;
}

fn resetBuffers() void {
    @memset(&tx_snapshot, 0);
    @memset(&rx_snapshot, 0);
    @memset(&tx_buffers, [_]u8{0} ** tx_buffer_capacity);
    @memset(&rx_buffers, [_]u8{0} ** rx_buffer_capacity);
    @memset(&tx_desc_ring, std.mem.zeroes(TxDesc));
    @memset(&rx_desc_ring, std.mem.zeroes(RxDesc));
}

fn initMock() void {
    state.backend = abi.ethernet_backend_e1000;
    state.initialized = 1;
    state.hardware_backed = 0;
    state.tx_enabled = 1;
    state.rx_enabled = 1;
    state.loopback_enabled = 1;
    state.link_up = 1;
    state.io_base = 0xE100;
    state.irq_line = 11;
    state.mac = default_mock_mac;
    tx_next_to_clean = 0;
}

fn mockAvailable() bool {
    return builtin.is_test and mock_enabled;
}

fn hardwareBacked() bool {
    return builtin.os.tag == .freestanding and builtin.cpu.arch == .x86_64;
}

fn validateAndReadMac(out: *[6]u8) InitError!void {
    var sum: u32 = 0;
    var word_index: u8 = 0;
    while (word_index < eeprom_word_count) : (word_index += 1) {
        const word = try readEepromWord(word_index);
        sum +%= word;
    }
    if (@as(u16, @truncate(sum)) != eeprom_checksum_expected) return error.EepromChecksumMismatch;

    word_index = 0;
    while (word_index < 3) : (word_index += 1) {
        const word = try readEepromWord(word_index);
        out[word_index * 2] = @as(u8, @truncate(word));
        out[(word_index * 2) + 1] = @as(u8, @truncate(word >> 8));
    }
    if (macIsZero(out.*)) return error.MacReadFailed;
    mirrorMacToRar(out.*);
}

fn readEepromWord(word_index: u8) InitError!u16 {
    writeMmio32(reg_eerd, eerd_start | (@as(u32, word_index) << eerd_addr_shift));
    var attempts: usize = 0;
    while (attempts < eeprom_poll_limit) : (attempts += 1) {
        const value = readMmio32(reg_eerd);
        if ((value & eerd_done) != 0) {
            return @as(u16, @truncate(value >> eerd_data_shift));
        }
        std.atomic.spinLoopHint();
    }
    return error.EepromReadFailed;
}

fn mirrorMacToRar(mac: [6]u8) void {
    const low = @as(u32, mac[0]) |
        (@as(u32, mac[1]) << 8) |
        (@as(u32, mac[2]) << 16) |
        (@as(u32, mac[3]) << 24);
    const high = @as(u32, mac[4]) |
        (@as(u32, mac[5]) << 8) |
        rah_av;
    writeMmio32(reg_ral0, low);
    writeMmio32(reg_rah0, high);
}

fn resetHardware() InitError!void {
    writeMmio32(reg_imc, 0xFFFF_FFFF);
    writeMmio32(reg_rctl, 0);
    writeMmio32(reg_tctl, tctl_psp);
    flushMmio();

    const ctrl = readMmio32(reg_ctrl);
    writeIoReg32(reg_ctrl, ctrl | ctrl_rst);
    flushMmio();

    var attempts: usize = 0;
    while (attempts < reset_poll_limit) : (attempts += 1) {
        if ((readMmio32(reg_ctrl) & ctrl_rst) == 0) break;
        std.atomic.spinLoopHint();
    } else {
        return error.ResetTimeout;
    }

    settleAfterReset();

    writeMmio32(reg_imc, 0xFFFF_FFFF);
    _ = readMmio32(reg_icr);

    var ctrl_post = readMmio32(reg_ctrl);
    ctrl_post |= ctrl_slu;
    writeMmio32(reg_ctrl, ctrl_post);
}

fn programRings() InitError!void {
    const tx_ring_addr = ptr64(&tx_desc_ring) orelse return error.RingProgramFailed;
    const rx_ring_addr = ptr64(&rx_desc_ring) orelse return error.RingProgramFailed;

    var index: usize = 0;
    while (index < tx_descriptor_count) : (index += 1) {
        tx_desc_ring[index] = .{
            .buffer_addr = ptr64(&tx_buffers[index]) orelse return error.RingProgramFailed,
            .length = 0,
            .cso = 0,
            .cmd = 0,
            .status = txd_stat_dd,
            .css = 0,
            .special = 0,
        };
    }

    index = 0;
    while (index < rx_descriptor_count) : (index += 1) {
        rx_desc_ring[index] = .{
            .buffer_addr = ptr64(&rx_buffers[index]) orelse return error.RingProgramFailed,
            .length = 0,
            .checksum = 0,
            .status = 0,
            .errors = 0,
            .special = 0,
        };
    }

    writeReg64(reg_tdbal, tx_ring_addr);
    writeMmio32(reg_tdlen, @as(u32, @intCast(tx_descriptor_count * @sizeOf(TxDesc))));
    writeMmio32(reg_tdh, 0);
    writeMmio32(reg_tdt, 0);

    writeMmio32(reg_tipg, tipg_ipgt | (tipg_ipgr1 << tipg_ipgr1_shift) | (tipg_ipgr2 << tipg_ipgr2_shift));
    writeMmio32(reg_tctl, tctl_en | tctl_psp | tctl_rtlc | (collision_threshold << ct_shift) | (collision_distance << cold_shift));

    writeReg64(reg_rdbal, rx_ring_addr);
    writeMmio32(reg_rdlen, @as(u32, @intCast(rx_descriptor_count * @sizeOf(RxDesc))));
    writeMmio32(reg_rdh, 0);
    writeMmio32(reg_rdt, @as(u32, @intCast(rx_descriptor_count - 1)));
    writeMmio32(reg_rctl, rctl_en | rctl_bam | rctl_rdmts_half | rctl_sz_2048 | rctl_secrc);

    state.tx_enabled = 1;
    state.rx_enabled = 1;
    state.link_up = if ((readMmio32(reg_status) & status_lu) != 0) 1 else 0;
    state.tx_index = 0;
    state.rx_consumer_offset = 0;
    tx_next_to_clean = 0;
}

fn reclaimTxCompletions() void {
    while (tx_next_to_clean != @as(usize, state.tx_index)) {
        const desc = txDescPtr(tx_next_to_clean);
        if ((desc.status & txd_stat_dd) == 0) break;
        tx_next_to_clean = (tx_next_to_clean + 1) % tx_descriptor_count;
    }
}

fn waitForTxSpace(next_slot: usize) bool {
    var attempts: usize = 0;
    while (attempts < tx_poll_limit) : (attempts += 1) {
        reclaimTxCompletions();
        if (next_slot != tx_next_to_clean) return true;
        std.atomic.spinLoopHint();
    }
    debugWriteTxState("e1000 waitForTxSpace timeout", next_slot);
    return false;
}

fn txDescPtr(slot: usize) *volatile TxDesc {
    return @as(*volatile TxDesc, @ptrCast(&tx_desc_ring[slot]));
}

fn rxDescPtr(slot: usize) *volatile RxDesc {
    return @as(*volatile RxDesc, @ptrCast(&rx_desc_ring[slot]));
}

fn readPhyRegister(register_index: u8) Error!u16 {
    writeMmio32(reg_mdic, mdic_op_read | (@as(u32, register_index) << mdic_reg_shift) | (mdic_phy_address << mdic_phy_shift));
    var attempts: usize = 0;
    while (attempts < eeprom_poll_limit) : (attempts += 1) {
        const value = readMmio32(reg_mdic);
        if ((value & mdic_ready) != 0) {
            if ((value & mdic_error) != 0) return error.HardwareFault;
            return @as(u16, @truncate(value));
        }
        std.atomic.spinLoopHint();
    }
    return error.Timeout;
}

fn writePhyRegister(register_index: u8, value: u16) Error!void {
    writeMmio32(
        reg_mdic,
        mdic_op_write |
            (@as(u32, register_index) << mdic_reg_shift) |
            (mdic_phy_address << mdic_phy_shift) |
            @as(u32, value),
    );
    var attempts: usize = 0;
    while (attempts < eeprom_poll_limit) : (attempts += 1) {
        const mdic = readMmio32(reg_mdic);
        if ((mdic & mdic_ready) != 0) {
            if ((mdic & mdic_error) != 0) return error.HardwareFault;
            return;
        }
        std.atomic.spinLoopHint();
    }
    return error.Timeout;
}

fn settleAfterReset() void {
    var attempts: usize = 0;
    while (attempts < reset_settle_loops) : (attempts += 1) {
        _ = readMmio32(reg_eecd);
        std.atomic.spinLoopHint();
    }
}

fn queueMockReceive(frame: []const u8) void {
    const rx_len: usize = @min(frame.len, rx_snapshot_capacity);
    std.mem.copyForwards(u8, rx_snapshot[0..rx_len], frame[0..rx_len]);
    mock_pending_rx_len = @as(u32, @intCast(rx_len));
    mock_pending_rx_status = rxd_stat_dd | rxd_stat_eop;
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

fn macIsZero(mac: [6]u8) bool {
    for (mac) |byte| {
        if (byte != 0) return false;
    }
    return true;
}

fn writeReg64(base_offset: u32, value: u64) void {
    writeMmio32(base_offset, @as(u32, @truncate(value)));
    writeMmio32(base_offset + 4, @as(u32, @truncate(value >> 32)));
}

fn flushMmio() void {
    _ = readMmio32(reg_status);
}

fn compilerFence() void {
    asm volatile ("sfence" ::: .{ .memory = true });
}

fn debugWriteTxState(label: []const u8, next_slot: usize) void {
    if (!hardwareBacked()) return;
    debugWriteString(label);
    debugWriteString(" idx=");
    debugWriteHexU32(state.tx_index);
    debugWriteString(" clean=");
    debugWriteHexU32(@as(u32, @intCast(tx_next_to_clean)));
    debugWriteString(" next=");
    debugWriteHexU32(@as(u32, @intCast(next_slot)));
    debugWriteString(" tdh=");
    debugWriteHexU32(readMmio32(reg_tdh));
    debugWriteString(" tdt=");
    debugWriteHexU32(readMmio32(reg_tdt));
    debugWriteString(" d0=");
    debugWriteHexByte(txDescPtr(0).status);
    debugWriteString(" d1=");
    debugWriteHexByte(txDescPtr(1).status);
    debugWriteString("\r\n");
}

fn debugWriteString(text: []const u8) void {
    for (text) |byte| debugWriteByte(byte);
}

fn debugWriteHexNibble(nibble: u8) void {
    const value = nibble & 0x0F;
    debugWriteByte(if (value < 10) '0' + value else 'A' + (value - 10));
}

fn debugWriteHexByte(value: u8) void {
    debugWriteHexNibble(value >> 4);
    debugWriteHexNibble(value);
}

fn debugWriteHexU32(value: u32) void {
    var shift: u5 = 28;
    while (true) {
        debugWriteHexNibble(@as(u8, @truncate(value >> shift)));
        if (shift == 0) break;
        shift -%= 4;
    }
}

fn debugWriteByte(byte: u8) void {
    asm volatile ("outb %[al], %[dx]"
        :
        : [dx] "{dx}" (@as(u16, 0xE9)),
          [al] "{al}" (byte),
        : .{ .memory = true });
}

fn mmioPtr(comptime T: type, offset: u32) *volatile T {
    return @as(*volatile T, @ptrFromInt(active_mmio_base + offset));
}

fn readMmio32(offset: u32) u32 {
    return mmioPtr(u32, offset).*;
}

fn writeMmio32(offset: u32, value: u32) void {
    mmioPtr(u32, offset).* = value;
}

fn writeIoReg32(register_offset: u32, value: u32) void {
    writePort32(active_io_base, register_offset);
    writePort32(active_io_base + 4, value);
}

fn ptr64(ptr: anytype) ?u64 {
    const value = @intFromPtr(ptr);
    return @as(u64, value);
}

fn writePort32(port: u16, value: u32) void {
    if (!hardwareBacked()) return;
    asm volatile ("outl %[eax], %[dx]"
        :
        : [dx] "{dx}" (port),
          [eax] "{eax}" (value),
        : .{ .memory = true });
}

test "e1000 mock init and loopback send path exports stable state" {
    testEnableMockDevice();
    defer testDisableMockDevice();

    try std.testing.expect(init());
    const eth = statePtr();
    try std.testing.expectEqual(@as(u32, abi.ethernet_magic), eth.magic);
    try std.testing.expectEqual(@as(u8, abi.ethernet_backend_e1000), eth.backend);
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

test "e1000 mock send hook sees transmitted frame" {
    testEnableMockDevice();
    defer testDisableMockDevice();

    const Hook = struct {
        var seen: bool = false;
        fn onSend(frame: []const u8) void {
            std.debug.assert(frame.len >= 14);
            std.debug.assert(frame[12] == 0x88);
            std.debug.assert(frame[13] == 0xB5);
            seen = true;
        }
    };

    Hook.seen = false;
    testInstallMockSendHook(Hook.onSend);
    defer testInstallMockSendHook(null);

    try std.testing.expect(init());
    _ = try sendPattern(96, 0x41);
    try std.testing.expect(Hook.seen);
}
