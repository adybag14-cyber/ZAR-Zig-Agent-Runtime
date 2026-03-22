// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const baremetal_qemu_smoke = b.option(bool, "baremetal-qemu-smoke", "Enable QEMU auto-exit boot smoke path in bare-metal image") orelse false;
    const baremetal_console_probe_banner = b.option(bool, "baremetal-console-probe-banner", "Enable the bare-metal console probe banner in the freestanding image") orelse false;
    const baremetal_framebuffer_probe_banner = b.option(bool, "baremetal-framebuffer-probe-banner", "Enable the bare-metal linear framebuffer probe banner in the freestanding image") orelse false;
    const baremetal_ata_storage_probe = b.option(bool, "baremetal-ata-storage-probe", "Enable the ATA-backed storage validation path in the freestanding image") orelse false;
    const baremetal_ata_gpt_installer_probe = b.option(bool, "baremetal-ata-gpt-installer-probe", "Enable the GPT-backed ATA installer validation path in the freestanding image") orelse false;
    const baremetal_virtio_gpu_display_probe = b.option(bool, "baremetal-virtio-gpu-display-probe", "Enable the virtio-gpu EDID/display capability validation path in the freestanding image") orelse false;
    const baremetal_virtio_block_probe = b.option(bool, "baremetal-virtio-block-probe", "Enable the virtio-block storage validation path in the freestanding image") orelse false;
    const baremetal_virtio_block_installer_probe = b.option(bool, "baremetal-virtio-block-installer-probe", "Enable the virtio-block installer validation path in the freestanding image") orelse false;
    const baremetal_e1000_probe = b.option(bool, "baremetal-e1000-probe", "Enable the E1000 Ethernet validation path in the freestanding image") orelse false;
    const baremetal_e1000_arp_probe = b.option(bool, "baremetal-e1000-arp-probe", "Enable the E1000 ARP validation path in the freestanding image") orelse false;
    const baremetal_e1000_ipv4_probe = b.option(bool, "baremetal-e1000-ipv4-probe", "Enable the E1000 IPv4 validation path in the freestanding image") orelse false;
    const baremetal_e1000_udp_probe = b.option(bool, "baremetal-e1000-udp-probe", "Enable the E1000 UDP validation path in the freestanding image") orelse false;
    const baremetal_e1000_tcp_probe = b.option(bool, "baremetal-e1000-tcp-probe", "Enable the E1000 TCP validation path in the freestanding image") orelse false;
    const baremetal_e1000_dhcp_probe = b.option(bool, "baremetal-e1000-dhcp-probe", "Enable the E1000 DHCP validation path in the freestanding image") orelse false;
    const baremetal_e1000_dns_probe = b.option(bool, "baremetal-e1000-dns-probe", "Enable the E1000 DNS validation path in the freestanding image") orelse false;
    const baremetal_e1000_http_post_probe = b.option(bool, "baremetal-e1000-http-post-probe", "Enable the E1000 HTTP POST validation path in the freestanding image") orelse false;
    const baremetal_e1000_https_post_probe = b.option(bool, "baremetal-e1000-https-post-probe", "Enable the E1000 HTTPS POST validation path in the freestanding image") orelse false;
    const baremetal_e1000_tool_service_probe = b.option(bool, "baremetal-e1000-tool-service-probe", "Enable the E1000 tool-service validation path in the freestanding image") orelse false;
    const baremetal_virtio_net_probe = b.option(bool, "baremetal-virtio-net-probe", "Enable the virtio-net raw-frame validation path in the freestanding image") orelse false;
    const baremetal_virtio_net_arp_probe = b.option(bool, "baremetal-virtio-net-arp-probe", "Enable the virtio-net ARP validation path in the freestanding image") orelse false;
    const baremetal_virtio_net_ipv4_probe = b.option(bool, "baremetal-virtio-net-ipv4-probe", "Enable the virtio-net IPv4 validation path in the freestanding image") orelse false;
    const baremetal_virtio_net_udp_probe = b.option(bool, "baremetal-virtio-net-udp-probe", "Enable the virtio-net UDP validation path in the freestanding image") orelse false;
    const baremetal_virtio_net_tcp_probe = b.option(bool, "baremetal-virtio-net-tcp-probe", "Enable the virtio-net TCP validation path in the freestanding image") orelse false;
    const baremetal_virtio_net_dhcp_probe = b.option(bool, "baremetal-virtio-net-dhcp-probe", "Enable the virtio-net DHCP validation path in the freestanding image") orelse false;
    const baremetal_virtio_net_dns_probe = b.option(bool, "baremetal-virtio-net-dns-probe", "Enable the virtio-net DNS validation path in the freestanding image") orelse false;
    const baremetal_virtio_net_http_post_probe = b.option(bool, "baremetal-virtio-net-http-post-probe", "Enable the virtio-net HTTP POST validation path in the freestanding image") orelse false;
    const baremetal_virtio_net_https_post_probe = b.option(bool, "baremetal-virtio-net-https-post-probe", "Enable the virtio-net HTTPS POST validation path in the freestanding image") orelse false;
    const baremetal_virtio_net_tool_service_probe = b.option(bool, "baremetal-virtio-net-tool-service-probe", "Enable the virtio-net tool-service validation path in the freestanding image") orelse false;
    const baremetal_rtl8139_probe = b.option(bool, "baremetal-rtl8139-probe", "Enable the RTL8139 Ethernet validation path in the freestanding image") orelse false;
    const baremetal_rtl8139_arp_probe = b.option(bool, "baremetal-rtl8139-arp-probe", "Enable the RTL8139 ARP validation path in the freestanding image") orelse false;
    const baremetal_rtl8139_ipv4_probe = b.option(bool, "baremetal-rtl8139-ipv4-probe", "Enable the RTL8139 IPv4 validation path in the freestanding image") orelse false;
    const baremetal_rtl8139_udp_probe = b.option(bool, "baremetal-rtl8139-udp-probe", "Enable the RTL8139 UDP validation path in the freestanding image") orelse false;
    const baremetal_rtl8139_tcp_probe = b.option(bool, "baremetal-rtl8139-tcp-probe", "Enable the RTL8139 TCP validation path in the freestanding image") orelse false;
    const baremetal_rtl8139_dhcp_probe = b.option(bool, "baremetal-rtl8139-dhcp-probe", "Enable the RTL8139 DHCP validation path in the freestanding image") orelse false;
    const baremetal_rtl8139_dns_probe = b.option(bool, "baremetal-rtl8139-dns-probe", "Enable the RTL8139 DNS validation path in the freestanding image") orelse false;
    const baremetal_rtl8139_gateway_probe = b.option(bool, "baremetal-rtl8139-gateway-probe", "Enable the RTL8139 gateway-routing validation path in the freestanding image") orelse false;
    const baremetal_rtl8139_http_post_probe = b.option(bool, "baremetal-rtl8139-http-post-probe", "Enable the RTL8139 HTTP POST validation path in the freestanding image") orelse false;
    const baremetal_rtl8139_https_post_probe = b.option(bool, "baremetal-rtl8139-https-post-probe", "Enable the RTL8139 HTTPS POST validation path in the freestanding image") orelse false;
    const baremetal_rtl8139_runtime_service_probe = b.option(bool, "baremetal-rtl8139-runtime-service-probe", "Enable the RTL8139 runtime-service validation path in the freestanding image") orelse false;
    const baremetal_tool_exec_probe = b.option(bool, "baremetal-tool-exec-probe", "Enable the bare-metal tool execution validation path in the freestanding image") orelse false;
    const baremetal_tool_runtime_probe = b.option(bool, "baremetal-tool-runtime-probe", "Enable the bare-metal tool runtime validation path in the freestanding image") orelse false;
    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    if (target.result.os.tag == .windows) {
        // Zig master on Windows currently fails to emit a PDB reliably for this project.
        // Strip debug symbols here so install doesn't attempt to copy a missing .pdb.
        root_module.strip = true;
    }
    if (target.result.os.tag == .linux and target.result.abi.isAndroid() and target.result.cpu.arch == .arm) {
        // armv7 Android currently links with unresolved TLS symbol (__tls_get_addr)
        // under Zig master for this codebase. Single-threaded build avoids TLS runtime linkage.
        root_module.single_threaded = true;
    }
    const benchmark_module = b.createModule(.{
        .root_source_file = b.path("src/benchmark_main.zig"),
        .target = target,
        .optimize = optimize,
    });
    if (target.result.os.tag == .windows) {
        benchmark_module.strip = true;
    }
    if (target.result.os.tag == .linux and target.result.abi.isAndroid() and target.result.cpu.arch == .arm) {
        // Keep the benchmark binary on the same single-threaded Android ARM policy as
        // the main runtime binary so ReleaseFast cross-target builds do not pull in
        // TLS runtime linkage that currently fails under the pinned Zig lane.
        benchmark_module.single_threaded = true;
    }

    const exe = b.addExecutable(.{
        .name = "openclaw-zig",
        .root_module = root_module,
    });
    const benchmark_exe = b.addExecutable(.{
        .name = "openclaw-zig-bench",
        .root_module = benchmark_module,
    });

    b.installArtifact(exe);
    b.installArtifact(benchmark_exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the OpenClaw Zig bootstrap binary");
    run_step.dependOn(&run_cmd.step);

    const run_bench_cmd = b.addRunArtifact(benchmark_exe);
    run_bench_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_bench_cmd.addArgs(args);
    }
    const bench_step = b.step("bench", "Run the hosted benchmark suite");
    bench_step.dependOn(&run_bench_cmd.step);

    const bench_smoke_cmd = b.addRunArtifact(benchmark_exe);
    bench_smoke_cmd.step.dependOn(b.getInstallStep());
    bench_smoke_cmd.addArgs(&.{ "--duration-ms", "25", "--warmup-ms", "5", "--filter", "protocol.dns_roundtrip" });
    const bench_smoke_step = b.step("bench-smoke", "Run a narrow hosted benchmark smoke case");
    bench_smoke_step.dependOn(&bench_smoke_cmd.step);

    const test_step = b.step("test", "Run unit tests");
    const baremetal_test_module = b.createModule(.{
        .root_source_file = b.path("src/baremetal_main.zig"),
        .target = target,
        .optimize = optimize,
    });
    // The older Windows system-command workaround for `zig test` is no longer safe:
    // newer master builds can report `All 0 tests passed` through that path even when
    // the codebase contains hundreds of tests. Keep the normal build-runner test flow
    // here so the validation surface remains real on Windows.
    const tests = b.addTest(.{
        .root_module = root_module,
    });
    const run_tests = if (target.result.os.tag == .windows) blk: {
        const run = b.addSystemCommand(&.{ "cmd.exe", "/c" });
        run.setName("run hosted tests");
        run.addFileArg(tests.getEmittedBin());
        break :blk run;
    } else b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);
    const baremetal_tests = b.addTest(.{
        .root_module = baremetal_test_module,
    });
    const run_baremetal_tests = if (target.result.os.tag == .windows) blk: {
        const run = b.addSystemCommand(&.{ "cmd.exe", "/c" });
        run.setName("run baremetal-host tests");
        run.addFileArg(baremetal_tests.getEmittedBin());
        break :blk run;
    } else b.addRunArtifact(baremetal_tests);
    test_step.dependOn(&run_baremetal_tests.step);
    const benchmark_tests = b.addTest(.{
        .root_module = benchmark_module,
    });
    const run_benchmark_tests = if (target.result.os.tag == .windows) blk: {
        const run = b.addSystemCommand(&.{ "cmd.exe", "/c" });
        run.setName("run benchmark tests");
        run.addFileArg(benchmark_tests.getEmittedBin());
        break :blk run;
    } else b.addRunArtifact(benchmark_tests);
    test_step.dependOn(&run_benchmark_tests.step);

    const baremetal_target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .abi = .none,
    });
    const baremetal_module = b.createModule(.{
        .root_source_file = b.path("src/baremetal_main.zig"),
        .target = baremetal_target,
        .optimize = optimize,
    });
    const baremetal_options = b.addOptions();
    baremetal_options.addOption(bool, "qemu_smoke", baremetal_qemu_smoke);
    baremetal_options.addOption(bool, "console_probe_banner", baremetal_console_probe_banner);
    baremetal_options.addOption(bool, "framebuffer_probe_banner", baremetal_framebuffer_probe_banner);
    baremetal_options.addOption(bool, "ata_storage_probe", baremetal_ata_storage_probe);
    baremetal_options.addOption(bool, "ata_gpt_installer_probe", baremetal_ata_gpt_installer_probe);
    baremetal_options.addOption(bool, "virtio_gpu_display_probe", baremetal_virtio_gpu_display_probe);
    baremetal_options.addOption(bool, "virtio_block_probe", baremetal_virtio_block_probe);
    baremetal_options.addOption(bool, "virtio_block_installer_probe", baremetal_virtio_block_installer_probe);
    baremetal_options.addOption(bool, "e1000_probe", baremetal_e1000_probe);
    baremetal_options.addOption(bool, "e1000_arp_probe", baremetal_e1000_arp_probe);
    baremetal_options.addOption(bool, "e1000_ipv4_probe", baremetal_e1000_ipv4_probe);
    baremetal_options.addOption(bool, "e1000_udp_probe", baremetal_e1000_udp_probe);
    baremetal_options.addOption(bool, "e1000_tcp_probe", baremetal_e1000_tcp_probe);
    baremetal_options.addOption(bool, "e1000_dhcp_probe", baremetal_e1000_dhcp_probe);
    baremetal_options.addOption(bool, "e1000_dns_probe", baremetal_e1000_dns_probe);
    baremetal_options.addOption(bool, "e1000_http_post_probe", baremetal_e1000_http_post_probe);
    baremetal_options.addOption(bool, "e1000_https_post_probe", baremetal_e1000_https_post_probe);
    baremetal_options.addOption(bool, "e1000_tool_service_probe", baremetal_e1000_tool_service_probe);
    baremetal_options.addOption(bool, "virtio_net_probe", baremetal_virtio_net_probe);
    baremetal_options.addOption(bool, "virtio_net_arp_probe", baremetal_virtio_net_arp_probe);
    baremetal_options.addOption(bool, "virtio_net_ipv4_probe", baremetal_virtio_net_ipv4_probe);
    baremetal_options.addOption(bool, "virtio_net_udp_probe", baremetal_virtio_net_udp_probe);
    baremetal_options.addOption(bool, "virtio_net_tcp_probe", baremetal_virtio_net_tcp_probe);
    baremetal_options.addOption(bool, "virtio_net_dhcp_probe", baremetal_virtio_net_dhcp_probe);
    baremetal_options.addOption(bool, "virtio_net_dns_probe", baremetal_virtio_net_dns_probe);
    baremetal_options.addOption(bool, "virtio_net_http_post_probe", baremetal_virtio_net_http_post_probe);
    baremetal_options.addOption(bool, "virtio_net_https_post_probe", baremetal_virtio_net_https_post_probe);
    baremetal_options.addOption(bool, "virtio_net_tool_service_probe", baremetal_virtio_net_tool_service_probe);
    baremetal_options.addOption(bool, "rtl8139_probe", baremetal_rtl8139_probe);
    baremetal_options.addOption(bool, "rtl8139_arp_probe", baremetal_rtl8139_arp_probe);
    baremetal_options.addOption(bool, "rtl8139_ipv4_probe", baremetal_rtl8139_ipv4_probe);
    baremetal_options.addOption(bool, "rtl8139_udp_probe", baremetal_rtl8139_udp_probe);
    baremetal_options.addOption(bool, "rtl8139_tcp_probe", baremetal_rtl8139_tcp_probe);
    baremetal_options.addOption(bool, "rtl8139_dhcp_probe", baremetal_rtl8139_dhcp_probe);
    baremetal_options.addOption(bool, "rtl8139_dns_probe", baremetal_rtl8139_dns_probe);
    baremetal_options.addOption(bool, "rtl8139_gateway_probe", baremetal_rtl8139_gateway_probe);
    baremetal_options.addOption(bool, "rtl8139_http_post_probe", baremetal_rtl8139_http_post_probe);
    baremetal_options.addOption(bool, "rtl8139_https_post_probe", baremetal_rtl8139_https_post_probe);
    baremetal_options.addOption(bool, "rtl8139_runtime_service_probe", baremetal_rtl8139_runtime_service_probe);
    baremetal_options.addOption(bool, "tool_exec_probe", baremetal_tool_exec_probe);
    baremetal_options.addOption(bool, "tool_runtime_probe", baremetal_tool_runtime_probe);
    baremetal_module.addOptions("build_options", baremetal_options);
    baremetal_module.single_threaded = true;
    baremetal_module.strip = false;

    const baremetal_exe = b.addExecutable(.{
        .name = "openclaw-zig-baremetal",
        .root_module = baremetal_module,
    });
    // Keep the Multiboot2 header section alive in optimized freestanding builds.
    // Zig master currently garbage-collects the custom `.multiboot` section here
    // unless section GC is disabled at the final bare-metal artifact boundary.
    baremetal_exe.link_gc_sections = false;
    const install_baremetal = b.addInstallArtifact(baremetal_exe, .{
        .dest_sub_path = "openclaw-zig-baremetal.elf",
    });
    const baremetal_step = b.step("baremetal", "Build freestanding bare-metal runtime image");
    baremetal_step.dependOn(&install_baremetal.step);
}
