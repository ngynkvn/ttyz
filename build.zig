const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const clap = b.dependency("flags", .{
        .target = target,
        .optimize = optimize,
    });

    const ttyz_mod = b.addModule("ttyz", .{
        .root_source_file = b.path("src/ttyz.zig"),
        .target = target,
    });

    const ttyz_exe = b.addExecutable(.{
        .name = "ttyz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ttyz", .module = ttyz_mod },
            },
        }),
    });

    b.installArtifact(ttyz_exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(ttyz_exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = ttyz_mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = ttyz_exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    const check_step = b.step("check", "Check the app");
    check_step.dependOn(test_step);
    check_step.dependOn(&run_cmd.step);
}
