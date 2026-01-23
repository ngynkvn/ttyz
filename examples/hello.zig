//! Minimal ttyz example - Hello World
//!
//! Demonstrates the basic Screen initialization and output.

const std = @import("std");
const ttyz = @import("ttyz");

pub fn main(_: std.process.Init) !void {
    // Initialize raw mode terminal
    var screen = try ttyz.Screen.init();
    defer _ = screen.deinit() catch {};

    // Clear screen and move to top-left
    try screen.clearScreen();
    try screen.home();

    // Print colored output
    try screen.print(ttyz.E.FG_GREEN ++ "Hello, " ++ ttyz.E.FG_CYAN ++ "ttyz" ++ ttyz.E.FG_GREEN ++ "!" ++ ttyz.E.RESET_STYLE ++ "\n\n", .{});
    try screen.print("Screen size: {}x{}\n", .{ screen.width, screen.height });
    try screen.print("\nPress any key to exit...", .{});
    try screen.flush();

    // Wait for a keypress
    _ = try screen.read(&.{});
}
