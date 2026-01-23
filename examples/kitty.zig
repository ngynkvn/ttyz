//! Kitty Graphics Protocol Demo
//!
//! Demonstrates the Kitty graphics protocol for displaying images in
//! compatible terminals (Kitty, WezTerm, Ghostty, etc.).
//!
//! This example generates and displays:
//! - A color gradient
//! - Colored boxes
//! - Image with transparency
//! - PNG file from disk (mushroom.png)

const std = @import("std");
const ttyz = @import("ttyz");
const kitty = ttyz.kitty;
const draw = ttyz.draw;
const ansi = ttyz.ansi;

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    var screen = try ttyz.Screen.init(init.io);
    defer _ = screen.deinit() catch {};

    try screen.clearScreen();
    try screen.home();

    try screen.print(ansi.bold ++ "Kitty Graphics Protocol Demo" ++ ansi.reset ++ "\r\n\r\n", .{});
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
            const hue: f32 = @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(gradient_width));
            const r, const g, const b = hsvToRgb(hue, 1.0, 1.0);
            gradient.setPixel(x, y, r, g, b, 255);
        }
    }

    try screen.print("1. Rainbow gradient ({d}x{d} pixels):\r\n", .{ gradient_width, gradient_height });
    try screen.flush();

    // Get a writer for kitty output
    // Buffer needs to hold base64-encoded RGBA data (~4/3 of raw size) plus protocol overhead
    var buf: [65536]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try gradient.display(&writer);

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
            const cx = x / cell_size;
            const cy = y / cell_size;
            const is_dark = (cx + cy) % 2 == 0;
            if (is_dark) {
                checker.setPixel(x, y, 50, 50, 80, 255);
            } else {
                checker.setPixel(x, y, 200, 200, 220, 128);
            }
        }
    }

    try screen.print("2. Checkerboard with transparency ({d}x{d} pixels):\r\n", .{ checker_size, checker_size });
    try screen.flush();

    writer = std.Io.Writer.fixed(&buf);
    try checker.display(&writer);
    _ = try screen.write(writer.buffered());
    try screen.flush();

    try screen.print("\r\n\r\n", .{});

    // Create colored boxes
    const box_width: usize = 150;
    const box_height: usize = 40;
    var boxes = try draw.Canvas.initAlloc(allocator, box_width, box_height);
    defer boxes.deinit(allocator);

    boxes.clear();

    // Draw red, green, blue boxes
    boxes.drawBox(5, 5, 40, 30, 0xFF0000FF); // Red
    boxes.drawBox(55, 5, 40, 30, 0xFF00FF00); // Green
    boxes.drawBox(105, 5, 40, 30, 0xFFFF0000); // Blue

    try screen.print("3. Colored boxes (RGB):\r\n", .{});
    try screen.flush();

    writer = std.Io.Writer.fixed(&buf);
    try boxes.display(&writer);
    _ = try screen.write(writer.buffered());
    try screen.flush();

    try screen.print("\r\n\r\n", .{});

    // Display PNG file from disk
    try screen.print("4. PNG file from disk (testdata/mushroom.png):\r\n", .{});
    try screen.flush();

    writer = std.Io.Writer.fixed(&buf);
    try kitty.displayFile(&writer, "testdata/mushroom.png");
    _ = try screen.write(writer.buffered());
    try screen.flush();

    try screen.print("\r\n\r\n", .{});
    try screen.print(ansi.faint ++ "Press any key to clear images and exit..." ++ ansi.reset, .{});
    try screen.flush();

    // Wait for keypress (read input directly, non-blocking due to termios)
    while (screen.running) {
        // Read input
        var input_buffer: [32]u8 = undefined;
        const rc = std.posix.system.read(screen.fd, &input_buffer, input_buffer.len);
        if (rc > 0) {
            const bytes_read: usize = @intCast(rc);
            for (input_buffer[0..bytes_read]) |byte| {
                const action = screen.input_parser.advance(byte);
                if (screen.actionToEvent(action, byte)) |event| {
                    switch (event) {
                        .key => {
                            screen.running = false;
                            break;
                        },
                        .interrupt => {
                            screen.running = false;
                            break;
                        },
                        else => {},
                    }
                }
            }
        }
        if (!screen.running) break;
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
