//! Kitty Graphics Protocol Demo
//!
//! Demonstrates the Kitty graphics protocol for displaying images in
//! compatible terminals (Kitty, WezTerm, Ghostty, etc.).
//!
//! This example generates and displays:
//! - A color gradient
//! - Colored boxes
//! - Image with transparency

const std = @import("std");
const ttyz = @import("ttyz");
const kitty = ttyz.kitty;
const draw = ttyz.draw;
const E = ttyz.E;

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    var screen = try ttyz.Screen.init();
    defer _ = screen.deinit() catch {};

    try screen.clearScreen();
    try screen.home();

    try screen.print(E.BOLD ++ "Kitty Graphics Protocol Demo" ++ E.RESET_STYLE ++ "\r\n\r\n", .{});
    try screen.print("This demo shows images using the Kitty graphics protocol.\r\n", .{});
    try screen.print("Works in: Kitty, WezTerm, Ghostty, and compatible terminals.\r\n\r\n", .{});

    // Create a gradient image
    const gradient_width: usize = 200;
    const gradient_height: usize = 50;
    var gradient = try draw.Canvas.initAlloc(allocator, gradient_width, gradient_height);
    defer gradient.deinit(allocator);

    // Fill with a rainbow gradient
    for (0..gradient_height) |y| {
        for (0..gradient_width) |x| {
            const idx = y * gradient_width * 4 + x * 4;
            // HSV to RGB conversion for rainbow effect
            const hue: f32 = @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(gradient_width));
            const r, const g, const b = hsvToRgb(hue, 1.0, 1.0);
            gradient.canvas[idx] = r;
            gradient.canvas[idx + 1] = g;
            gradient.canvas[idx + 2] = b;
            gradient.canvas[idx + 3] = 255; // Alpha
        }
    }

    try screen.print("1. Rainbow gradient ({d}x{d} pixels):\r\n", .{ gradient_width, gradient_height });
    try screen.flush();

    // Get a writer for kitty output
    // Buffer needs to hold base64-encoded RGBA data (~4/3 of raw size) plus protocol overhead
    var buf: [65536]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try gradient.writeKitty(&writer);

    // Write the kitty command to screen
    _ = try screen.write(writer.buffered());
    try screen.flush();

    try screen.print("\r\n\r\n", .{});

    // Create a checkerboard pattern with transparency
    const checker_size: usize = 100;
    var checker = try draw.Canvas.initAlloc(allocator, checker_size, checker_size);
    defer checker.deinit(allocator);

    const cell_size: usize = 10;
    for (0..checker_size) |y| {
        for (0..checker_size) |x| {
            const idx = y * checker_size * 4 + x * 4;
            const cx = x / cell_size;
            const cy = y / cell_size;
            const is_dark = (cx + cy) % 2 == 0;

            if (is_dark) {
                checker.canvas[idx] = 50; // R
                checker.canvas[idx + 1] = 50; // G
                checker.canvas[idx + 2] = 80; // B
                checker.canvas[idx + 3] = 255; // A
            } else {
                checker.canvas[idx] = 200; // R
                checker.canvas[idx + 1] = 200; // G
                checker.canvas[idx + 2] = 220; // B
                checker.canvas[idx + 3] = 128; // A - semi-transparent
            }
        }
    }

    try screen.print("2. Checkerboard with transparency ({d}x{d} pixels):\r\n", .{ checker_size, checker_size });
    try screen.flush();

    writer = std.Io.Writer.fixed(&buf);
    try checker.writeKitty(&writer);
    _ = try screen.write(writer.buffered());
    try screen.flush();

    try screen.print("\r\n\r\n", .{});

    // Create colored boxes
    const box_width: usize = 150;
    const box_height: usize = 40;
    var boxes = try draw.Canvas.initAlloc(allocator, box_width, box_height);
    defer boxes.deinit(allocator);

    // Clear to black
    @memset(boxes.canvas, 0);

    // Draw red, green, blue boxes
    try boxes.drawBox(5, 5, 40, 30, 0xFF0000FF); // Red
    try boxes.drawBox(55, 5, 40, 30, 0xFF00FF00); // Green
    try boxes.drawBox(105, 5, 40, 30, 0xFFFF0000); // Blue

    try screen.print("3. Colored boxes (RGB):\r\n", .{});
    try screen.flush();

    writer = std.Io.Writer.fixed(&buf);
    try boxes.writeKitty(&writer);
    _ = try screen.write(writer.buffered());
    try screen.flush();

    try screen.print("\r\n\r\n", .{});
    try screen.print(E.DIM ++ "Press any key to clear images and exit..." ++ E.RESET_STYLE, .{});
    try screen.flush();

    // Wait for keypress
    try screen.start();
    while (screen.running) {
        if (screen.pollEvent()) |event| {
            switch (event) {
                .key => break,
                .interrupt => break,
                else => {},
            }
        }
        init.io.sleep(std.Io.Duration.fromMilliseconds(10), .awake) catch {};
    }

    // Clear all images before exiting
    writer = std.Io.Writer.fixed(&buf);
    try kitty.deleteAll(&writer);
    _ = try screen.write(writer.buffered());
    try screen.flush();
}

/// Convert HSV to RGB (h in 0-1, s in 0-1, v in 0-1)
fn hsvToRgb(h: f32, s: f32, v: f32) struct { u8, u8, u8 } {
    const c = v * s;
    const x = c * (1.0 - @abs(@mod(h * 6.0, 2.0) - 1.0));
    const m = v - c;

    var r: f32 = 0;
    var g: f32 = 0;
    var b: f32 = 0;

    const h6 = h * 6.0;
    if (h6 < 1) {
        r = c;
        g = x;
    } else if (h6 < 2) {
        r = x;
        g = c;
    } else if (h6 < 3) {
        g = c;
        b = x;
    } else if (h6 < 4) {
        g = x;
        b = c;
    } else if (h6 < 5) {
        r = x;
        b = c;
    } else {
        r = c;
        b = x;
    }

    return .{
        @intFromFloat((r + m) * 255),
        @intFromFloat((g + m) * 255),
        @intFromFloat((b + m) * 255),
    };
}
