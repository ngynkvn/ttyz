const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ttyz_mod = b.addModule("ttyz", .{
        .root_source_file = b.path("src/ttyz.zig"),
        .target = target,
    });

    // Example executables
    const exes = [_]struct { name: []const u8, desc: []const u8, path: []const u8 }{
        .{ .name = "main", .desc = "Run the main application", .path = "src" },
        .{ .name = "demo", .desc = "Run the interactive demo", .path = "examples" },
        .{ .name = "hello", .desc = "Run the hello world example", .path = "examples" },
        .{ .name = "input", .desc = "Run the input handling example", .path = "examples" },
        .{ .name = "progress", .desc = "Run the progress bar example", .path = "examples" },
        .{ .name = "colors", .desc = "Run the color showcase example", .path = "examples" },
    };

    const test_step = b.step("test", "Run tests");
    for (exes) |e| {
        const exe = b.addExecutable(.{
            .name = e.name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(b.fmt("{s}/{s}.zig", .{ e.path, e.name })),
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
        const step = b.step(e.name, e.desc);
        step.dependOn(&run_cmd.step);
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
        const tests = b.addTest(.{
            .root_module = exe.root_module,
        });
        const run_tests = b.addRunArtifact(tests);
        test_step.dependOn(&run_tests.step);
    }

    // Tests
    const mod_tests = b.addTest(.{
        .root_module = ttyz_mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    test_step.dependOn(&run_mod_tests.step);

    const check_step = b.step("check", "Check the app");
    check_step.dependOn(test_step);

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
