const std = @import("std");
const base64 = std.base64;
const kitty = @import("kitty.zig");

pub const Canvas = struct {
    width: usize,
    height: usize,
    canvas: []u8,

    pub fn writeKitty(canvas: *Canvas, writer: *std.Io.Writer) !void {
        var image = kitty.Image.default;
        image.params.a = 'T';
        image.params.f = 32;
        image.params.t = 'd';
        image.params.s = canvas.width;
        image.params.v = canvas.height;
        image.setPayload(canvas.canvas);
        try image.write(writer);
    }

    pub fn initAlloc(allocator: std.mem.Allocator, width: usize, height: usize) !Canvas {
        const canvas = try allocator.alloc(u8, width * height * 4);
        return .{ .width = width, .height = height, .canvas = canvas };
    }

    pub fn init(width: usize, height: usize, canvas: []u8) !Canvas {
        return .{ .width = width, .height = height, .canvas = canvas };
    }
    pub fn deinit(canvas: *Canvas, allocator: std.mem.Allocator) void {
        allocator.free(canvas.canvas);
    }

    pub fn drawBox(canvas: *Canvas, x: usize, y: usize, width: usize, height: usize, color: u32) !void {
        const a, const g, const b, const r = std.mem.toBytes(color);
        for (0..width) |i| {
            for (0..height) |j| {
                const idx = (y + j) * (canvas.width * 4) + (x + i) * 4;
                canvas.canvas[idx] = b;
                canvas.canvas[idx + 1] = g;
                canvas.canvas[idx + 2] = r;
                canvas.canvas[idx + 3] = a;
            }
        }
    }

    pub fn write(canvas: *Canvas, writer: *std.Io.Writer) !void {
        try base64.standard.Encoder.encodeWriter(writer, canvas.canvas);
    }
};
