const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
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

    const exe = b.addExecutable(.{
        .name = "openclaw-zig",
        .root_module = root_module,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the OpenClaw Zig bootstrap binary");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run unit tests");
    if (target.result.os.tag == .windows) {
        // Work around a Zig master Windows build-runner regression around `--listen`.
        const test_cmd = b.addSystemCommand(&.{
            b.graph.zig_exe,
            "test",
            "src/main.zig",
        });
        test_step.dependOn(&test_cmd.step);
    } else {
        const tests = b.addTest(.{
            .root_module = root_module,
        });
        const run_tests = b.addRunArtifact(tests);
        test_step.dependOn(&run_tests.step);
    }
}
