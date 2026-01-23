//! Minimal ttyz example - Hello World
//!
//! Demonstrates the basic Screen initialization and output.

const std = @import("std");
const ttyz = @import("ttyz");

pub fn main(init: std.process.Init) !void {
    // Initialize raw mode terminal
    var screen = try ttyz.Screen.init(init.io);
    defer _ = screen.deinit() catch {};

    // Clear screen and move to top-left
    try screen.clearScreen();
    try screen.home();

    // Print colored output
    const ansi = ttyz.ansi;
    try screen.print(ansi.fg.green ++ "Hello, " ++ ansi.fg.cyan ++ "ttyz" ++ ansi.fg.green ++ "!" ++ ansi.reset ++ "\r\n\r\n", .{});
    try screen.print("Screen size: {}x{}\r\n", .{ screen.width, screen.height });
    try screen.print("\r\nPress any key to exit...", .{});
    try screen.flush();

    // Wait for a keypress
    _ = try screen.read(&.{});
}
