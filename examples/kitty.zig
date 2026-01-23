//! Kitty Graphics Protocol Demo
//!
//! Demonstrates the Kitty graphics protocol for displaying images in
//! compatible terminals (Kitty, WezTerm, Ghostty, etc.).
//!
//! Note: This example manages Screen directly because Kitty graphics
//! writes escape sequences outside the Frame buffer system.

const std = @import("std");

const ttyz = @import("ttyz");
const kitty = ttyz.kitty;
const draw = ttyz.draw;
const frame = ttyz.frame;
const Frame = ttyz.Frame;
const Buffer = ttyz.Buffer;
const Layout = frame.Layout;
const Color = frame.Color;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.arena.allocator();

    var screen = try ttyz.Screen.init(io, ttyz.Screen.Options.default);
    defer _ = screen.deinit() catch {};

    // Create images
    var gradient = try createGradient(allocator);
    defer gradient.deinit(allocator);

    var checker = try createCheckerboard(allocator);
    defer checker.deinit(allocator);

    var boxes = try createBoxes(allocator);
    defer boxes.deinit(allocator);

    // Render header using Frame
    var buffer = try Buffer.init(allocator, screen.width, screen.height);
    defer buffer.deinit();

    var f = Frame.init(&buffer);
    f.clear();

    const header, _ = f.areas(2, Layout(2).vertical(.{
        .{ .length = 3 },
        .{ .fill = 1 },
    }));

    f.setString(2, header.y, "Kitty Graphics Protocol Demo", .{ .bold = true }, Color.cyan, .default);
    f.setString(2, header.y + 1, "Works in: Kitty, WezTerm, Ghostty, etc.", .{ .dim = true }, .default, .default);

    try f.render(&screen);
    try screen.flush();

    // Now render images directly to screen (not through Frame)
    var buf: [65536]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    // 1. Gradient
    try screen.print("\r\n1. Rainbow gradient (200x50 pixels):\r\n", .{});
    try screen.flush();
    writer = std.Io.Writer.fixed(&buf);
    try gradient.display(&writer);
    _ = try screen.write(writer.buffered());
    try screen.flush();

    // 2. Checkerboard
    try screen.print("\r\n\r\n2. Checkerboard with transparency (100x100 pixels):\r\n", .{});
    try screen.flush();
    writer = std.Io.Writer.fixed(&buf);
    try checker.display(&writer);
    _ = try screen.write(writer.buffered());
    try screen.flush();

    // 3. Colored boxes
    try screen.print("\r\n\r\n3. Colored boxes (RGB):\r\n", .{});
    try screen.flush();
    writer = std.Io.Writer.fixed(&buf);
    try boxes.display(&writer);
    _ = try screen.write(writer.buffered());
    try screen.flush();

    // 4. PNG file
    try screen.print("\r\n\r\n4. PNG file from disk (testdata/mushroom.png):\r\n", .{});
    try screen.flush();
    writer = std.Io.Writer.fixed(&buf);
    try kitty.displayFile(io, &writer, "./testdata/mushroom.png");
    _ = try screen.write(writer.buffered());
    try screen.flush();

    try screen.print("\r\n\r\nPress any key to clear images and exit...", .{});
    try screen.flush();

    // Wait for key press
    while (true) {
        var input_buf: [32]u8 = undefined;
        const bytes_read = screen.read(&input_buf) catch 0;
        if (bytes_read > 0) break;
    }

    // Clear all images before exiting
    writer = std.Io.Writer.fixed(&buf);
    try kitty.deleteAll(&writer);
    _ = try screen.write(writer.buffered());
    try screen.flush();
}

fn createGradient(allocator: std.mem.Allocator) !draw.Canvas {
    const width: usize = 200;
    const height: usize = 50;
    var canvas = try draw.Canvas.initAlloc(allocator, width, height);
    for (0..height) |y| {
        for (0..width) |x| {
            const hue: f32 = @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(width));
            const r, const g, const b = hsvToRgb(hue, 1.0, 1.0);
            canvas.setPixel(x, y, r, g, b, 255);
        }
    }
    return canvas;
}

fn createCheckerboard(allocator: std.mem.Allocator) !draw.Canvas {
    const size: usize = 100;
    var canvas = try draw.Canvas.initAlloc(allocator, size, size);
    const cell_size: usize = 10;
    _ = cell_size; // autofix
    for (0..size) |y| {
        const cy = y;
        for (0..size) |x| {
            const cx = x;
            const is_dark = (cx + cy) % 2 == 0;
            if (is_dark) {
                canvas.setPixel(x, y, 50, 50, 80, 255);
            } else {
                canvas.setPixel(x, y, 200, 200, 220, 128);
            }
        }
    }
    return canvas;
}

fn createBoxes(allocator: std.mem.Allocator) !draw.Canvas {
    const width: usize = 150;
    const height: usize = 40;
    var canvas = try draw.Canvas.initAlloc(allocator, width, height);
    canvas.clear();
    canvas.drawBox(5, 5, 40, 30, 0xFF0000FF); // Red
    canvas.drawBox(55, 5, 40, 30, 0xFF00FF00); // Green
    canvas.drawBox(105, 5, 40, 30, 0xFFFF0000); // Blue
    return canvas;
}

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
