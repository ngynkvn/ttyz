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
const frame = ttyz.frame;
const Frame = ttyz.Frame;
const Buffer = ttyz.Buffer;
const Layout = frame.Layout;
const Color = frame.Color;

const KittyDemo = struct {
    buffer: Buffer,
    allocator: std.mem.Allocator,
    gradient: ?draw.Canvas = null,
    checker: ?draw.Canvas = null,
    boxes: ?draw.Canvas = null,
    rendered: bool = false,

    pub fn init(self: *KittyDemo, screen: *ttyz.Screen) !void {
        self.buffer = try Buffer.init(self.allocator, screen.width, screen.height);

        // Create gradient image
        const gradient_width: usize = 200;
        const gradient_height: usize = 50;
        self.gradient = try draw.Canvas.initAlloc(self.allocator, gradient_width, gradient_height);
        for (0..gradient_height) |y| {
            for (0..gradient_width) |x| {
                const hue: f32 = @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(gradient_width));
                const r, const g, const b = hsvToRgb(hue, 1.0, 1.0);
                self.gradient.?.setPixel(x, y, r, g, b, 255);
            }
        }

        // Create checkerboard
        const checker_size: usize = 100;
        self.checker = try draw.Canvas.initAlloc(self.allocator, checker_size, checker_size);
        const cell_size: usize = 10;
        for (0..checker_size) |y| {
            for (0..checker_size) |x| {
                const cx = x / cell_size;
                const cy = y / cell_size;
                const is_dark = (cx + cy) % 2 == 0;
                if (is_dark) {
                    self.checker.?.setPixel(x, y, 50, 50, 80, 255);
                } else {
                    self.checker.?.setPixel(x, y, 200, 200, 220, 128);
                }
            }
        }

        // Create colored boxes
        const box_width: usize = 150;
        const box_height: usize = 40;
        self.boxes = try draw.Canvas.initAlloc(self.allocator, box_width, box_height);
        self.boxes.?.clear();
        self.boxes.?.drawBox(5, 5, 40, 30, 0xFF0000FF); // Red
        self.boxes.?.drawBox(55, 5, 40, 30, 0xFF00FF00); // Green
        self.boxes.?.drawBox(105, 5, 40, 30, 0xFFFF0000); // Blue
    }

    pub fn deinit(self: *KittyDemo) void {
        if (self.gradient) |*g| g.deinit(self.allocator);
        if (self.checker) |*c| c.deinit(self.allocator);
        if (self.boxes) |*b| b.deinit(self.allocator);
        self.buffer.deinit();
    }

    pub fn handleEvent(_: *KittyDemo, event: ttyz.Event) bool {
        return switch (event) {
            .key => false,
            .interrupt => false,
            else => true,
        };
    }

    pub fn render(self: *KittyDemo, screen: *ttyz.Screen) !void {
        if (self.rendered) return;
        self.rendered = true;

        if (self.buffer.width != screen.width or self.buffer.height != screen.height) {
            try self.buffer.resize(screen.width, screen.height);
        }

        var f = Frame.init(&self.buffer);
        f.clear();

        // Layout
        const header, _ = f.areas(2, Layout(2).vertical(.{
            .{ .length = 3 },
            .{ .fill = 1 },
        }));

        // Title
        f.setString(2, header.y, "Kitty Graphics Protocol Demo", .{ .bold = true }, Color.cyan, .default);
        f.setString(2, header.y + 1, "Works in: Kitty, WezTerm, Ghostty, etc.", .{ .dim = true }, .default, .default);

        try f.render(screen);
        try screen.flush();

        // Now render images directly to screen (not through Frame)
        var buf: [65536]u8 = undefined;
        var writer = std.Io.Writer.fixed(&buf);

        // 1. Gradient
        try screen.print("\r\n1. Rainbow gradient (200x50 pixels):\r\n", .{});
        try screen.flush();
        if (self.gradient) |*g| {
            writer = std.Io.Writer.fixed(&buf);
            try g.display(&writer);
            _ = try screen.write(writer.buffered());
            try screen.flush();
        }

        // 2. Checkerboard
        try screen.print("\r\n\r\n2. Checkerboard with transparency (100x100 pixels):\r\n", .{});
        try screen.flush();
        if (self.checker) |*c| {
            writer = std.Io.Writer.fixed(&buf);
            try c.display(&writer);
            _ = try screen.write(writer.buffered());
            try screen.flush();
        }

        // 3. Colored boxes
        try screen.print("\r\n\r\n3. Colored boxes (RGB):\r\n", .{});
        try screen.flush();
        if (self.boxes) |*b| {
            writer = std.Io.Writer.fixed(&buf);
            try b.display(&writer);
            _ = try screen.write(writer.buffered());
            try screen.flush();
        }

        // 4. PNG file
        try screen.print("\r\n\r\n4. PNG file from disk (testdata/mushroom.png):\r\n", .{});
        try screen.flush();
        writer = std.Io.Writer.fixed(&buf);
        try kitty.displayFile(&writer, "testdata/mushroom.png");
        _ = try screen.write(writer.buffered());
        try screen.flush();

        try screen.print("\r\n\r\nPress any key to clear images and exit...", .{});
        try screen.flush();
    }

    pub fn cleanup(self: *KittyDemo, screen: *ttyz.Screen) !void {
        _ = self;
        // Clear all images before exiting
        var buf: [256]u8 = undefined;
        var writer = std.Io.Writer.fixed(&buf);
        try kitty.deleteAll(&writer);
        _ = try screen.write(writer.buffered());
        try screen.flush();
    }
};

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

pub fn main(init: std.process.Init) !void {
    var app = KittyDemo{ .buffer = undefined, .allocator = init.arena.allocator() };
    try ttyz.Runner(KittyDemo).run(&app, init);
}
