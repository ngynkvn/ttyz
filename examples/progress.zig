//! Progress bar and spinner example
//!
//! Demonstrates animated terminal output with progress indicators.

const std = @import("std");
const ttyz = @import("ttyz");
const E = ttyz.E;
const text = ttyz.text;

/// Draw a simple progress bar
fn drawProgressBar(screen: *ttyz.Screen, progress: f32, width: u16) !void {
    const filled = @as(u16, @intFromFloat(progress * @as(f32, @floatFromInt(width))));
    const empty = width - filled;

    try screen.print("[", .{});
    try screen.print(E.FG_GREEN, .{});

    var i: u16 = 0;
    while (i < filled) : (i += 1) {
        try screen.print("=", .{});
    }
    if (filled < width) {
        try screen.print(">", .{});
        i = 1;
    } else {
        i = 0;
    }
    try screen.print(E.RESET_STYLE, .{});
    while (i < empty) : (i += 1) {
        try screen.print(" ", .{});
    }

    try screen.print("] {d:>5.1}%", .{progress * 100});
}

/// Spinner characters
const spinners = [_][]const u8{ "|", "/", "-", "\\" };
const dots = [_][]const u8{ ".  ", ".. ", "...", " ..", "  .", "   " };
const braille = [_][]const u8{ "\u{28F7}", "\u{28EF}", "\u{28DF}", "\u{287F}", "\u{28BF}", "\u{28FB}", "\u{28FD}", "\u{28FE}" };

pub fn main(init: std.process.Init) !void {
    var screen = try ttyz.Screen.init();
    defer _ = screen.deinit() catch {};

    const total_steps: usize = 100;
    var step: usize = 0;
    var frame: usize = 0;

    while (step <= total_steps) {
        try screen.clearScreen();
        try screen.home();

        try screen.print(E.BOLD ++ "Progress Demo" ++ E.RESET_STYLE ++ "\n\n", .{});

        // Main progress bar
        const progress = @as(f32, @floatFromInt(step)) / @as(f32, @floatFromInt(total_steps));
        try screen.print("  ", .{});
        try drawProgressBar(&screen, progress, 40);
        try screen.print("\n\n", .{});

        // Different spinner styles
        try screen.print("  Spinners:\n", .{});
        try screen.print("    Basic:   " ++ E.FG_CYAN ++ "{s}" ++ E.RESET_STYLE ++ "  Working...\n", .{spinners[frame % spinners.len]});
        try screen.print("    Dots:    " ++ E.FG_YELLOW ++ "{s}" ++ E.RESET_STYLE ++ "  Loading\n", .{dots[(frame / 2) % dots.len]});
        try screen.print("    Braille: " ++ E.FG_MAGENTA ++ "{s}" ++ E.RESET_STYLE ++ "  Processing\n\n", .{braille[frame % braille.len]});

        // Multiple concurrent progress bars
        try screen.print("  Multiple tasks:\n", .{});
        const task_progress = [_]f32{
            @min(1.0, progress * 1.5),
            @min(1.0, progress * 1.2),
            progress,
            @min(1.0, @max(0, progress * 2.0 - 0.5)),
        };
        const task_names = [_][]const u8{ "Download ", "Extract  ", "Build    ", "Install  " };

        for (task_names, task_progress) |name, p| {
            try screen.print("    {s} ", .{name});
            if (p >= 1.0) {
                try screen.print(E.FG_GREEN ++ "[done]" ++ E.RESET_STYLE ++ "\n", .{});
            } else if (p > 0) {
                try drawProgressBar(&screen, p, 20);
                try screen.print("\n", .{});
            } else {
                try screen.print(E.DIM ++ "[waiting]" ++ E.RESET_STYLE ++ "\n", .{});
            }
        }

        try screen.print("\n" ++ E.DIM ++ "  Step {}/{}" ++ E.RESET_STYLE, .{ step, total_steps });
        try screen.flush();

        init.io.sleep(std.Io.Duration.fromMilliseconds(33), .awake) catch {};
        step += 1;
        frame += 1;
    }

    // Completion message
    try screen.print("\n\n" ++ E.FG_GREEN ++ E.BOLD ++ "  Complete!" ++ E.RESET_STYLE ++ "\n", .{});
    try screen.flush();
    init.io.sleep(std.Io.Duration.fromSeconds(1), .awake) catch {};
}
