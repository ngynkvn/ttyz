//! Pixel-level RGBA canvas for drawing with Kitty graphics protocol output.
//!
//! Provides a canvas abstraction for pixel-based drawing that can be
//! rendered to terminals supporting the Kitty graphics protocol.
//!
//! ## Example
//! ```zig
//! var canvas = try draw.Canvas.initAlloc(allocator, 200, 200);
//! defer canvas.deinit(allocator);
//!
//! try canvas.drawBox(10, 10, 50, 50, 0xFF0000FF);  // Red box
//! try canvas.writeKitty(&writer);
//! ```

const std = @import("std");
const base64 = std.base64;
const kitty = @import("kitty.zig");

/// A pixel canvas with RGBA storage for drawing operations.
pub const Canvas = struct {
    /// Canvas width in pixels.
    width: usize,
    /// Canvas height in pixels.
    height: usize,
    /// Raw RGBA pixel data (4 bytes per pixel).
    canvas: []u8,

    /// Write the canvas to the terminal using the Kitty graphics protocol.
    /// The image is transmitted directly and displayed at the current cursor position.
    pub fn writeKitty(canvas: *Canvas, writer: anytype) !void {
        try kitty.displayRgba(writer, canvas.canvas, canvas.width, canvas.height);
    }

    /// Allocate a new canvas with the given dimensions.
    /// The caller owns the returned canvas and must call `deinit` to free it.
    pub fn initAlloc(allocator: std.mem.Allocator, width: usize, height: usize) !Canvas {
        const canvas = try allocator.alloc(u8, width * height * 4);
        return .{ .width = width, .height = height, .canvas = canvas };
    }

    /// Initialize a canvas using existing pixel buffer.
    /// The buffer must be at least width * height * 4 bytes.
    pub fn init(width: usize, height: usize, canvas: []u8) !Canvas {
        return .{ .width = width, .height = height, .canvas = canvas };
    }

    /// Free the canvas pixel buffer.
    pub fn deinit(canvas: *Canvas, allocator: std.mem.Allocator) void {
        allocator.free(canvas.canvas);
    }

    /// Draw a filled rectangle on the canvas.
    /// Color is specified as a 32-bit ARGB value.
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

    /// Write the raw canvas data as base64 to the writer.
    /// This is a low-level function; prefer `writeKitty` for terminal output.
    pub fn write(canvas: *Canvas, writer: anytype) !void {
        try base64.standard.Encoder.encodeWriter(writer, canvas.canvas);
    }
};
