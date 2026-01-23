const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ttyz_mod = b.addModule("ttyz", .{
        .root_source_file = b.path("src/ttyz.zig"),
        .target = target,
    });

    // Main example executable
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

    // Example executables
    const examples = [_]struct { name: []const u8, desc: []const u8 }{
        .{ .name = "demo", .desc = "Run the interactive demo" },
        .{ .name = "hello", .desc = "Run the hello world example" },
        .{ .name = "input", .desc = "Run the input handling example" },
        .{ .name = "progress", .desc = "Run the progress bar example" },
        .{ .name = "colors", .desc = "Run the color showcase example" },
    };

    for (examples) |example| {
        const exe = b.addExecutable(.{
            .name = example.name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(b.fmt("examples/{s}.zig", .{example.name})),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "ttyz", .module = ttyz_mod },
                },
            }),
        });
        b.installArtifact(exe);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());
        const step = b.step(example.name, example.desc);
        step.dependOn(&run_cmd.step);
    }

    // Run main app
    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(ttyz_exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Tests
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
    check_step.dependOn(&ttyz_exe.step);

    // Documentation
    const docs_obj = b.addObject(.{
        .name = "ttyz",
        .root_module = ttyz_mod,
    });

    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs_obj.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Generate documentation");
    docs_step.dependOn(&install_docs.step);
}
