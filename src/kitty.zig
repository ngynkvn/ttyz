//! Kitty graphics protocol for terminal image display.
//!
//! ## Quick Start
//! ```zig
//! // Display RGBA pixels
//! try kitty.displayRgba(writer, pixels, width, height);
//!
//! // Display a PNG file
//! try kitty.displayFile(io, writer, "image.png");
//! ```
//!
//! ## Reference
//! https://sw.kovidgoyal.net/kitty/graphics-protocol/

const std = @import("std");

// =============================================================================
// Types
// =============================================================================

/// Pixel formats for image data.
pub const Format = enum(usize) {
    rgb = 24,
    rgba = 32,
    png = 100,
};

/// Transmission modes.
pub const Transmission = enum(u8) {
    direct = 'd',
    file = 'f',
    temp_file = 't',
    shared_memory = 's',
};

// =============================================================================
// High-Level API
// =============================================================================

/// Display RGBA pixel data.
pub fn displayRgba(writer: *std.Io.Writer, pixels: []const u8, width: usize, height: usize) !void {
    try transmit(writer, pixels, .{
        .format = .rgba,
        .width = width,
        .height = height,
    });
}

/// Display RGB pixel data.
pub fn displayRgb(writer: *std.Io.Writer, pixels: []const u8, width: usize, height: usize) !void {
    try transmit(writer, pixels, .{
        .format = .rgb,
        .width = width,
        .height = height,
    });
}

/// Display a PNG file (reads and transmits contents).
pub fn displayFile(io: std.Io, writer: *std.Io.Writer, path: []const u8) !void {
    const file = if (std.fs.path.isAbsolute(path))
        try std.Io.Dir.openFileAbsolute(io, path, .{})
    else
        try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    try transmitFile(io, writer, file, .{ .format = .png });
}

/// Display a PNG file using allocator.
pub fn displayFileAlloc(allocator: std.mem.Allocator, writer: *std.Io.Writer, path: []const u8) !void {
    const data = try std.fs.cwd().readFileAlloc(allocator, path, 10 * 1024 * 1024);
    defer allocator.free(data);
    try transmit(writer, data, .{ .format = .png });
}

/// Display a PNG file by path (terminal reads file directly).
pub fn displayFilePath(writer: *std.Io.Writer, path: []const u8) !void {
    try transmitPath(writer, path, .{ .format = .png });
}

/// Delete all images.
pub fn deleteAll(writer: *std.Io.Writer) !void {
    try writeCommand(writer, .{ .a = 'd', .d = 'a' });
}

/// Delete image by ID.
pub fn deleteById(writer: *std.Io.Writer, id: usize) !void {
    try writeCommand(writer, .{ .a = 'd', .d = 'i', .i = id });
}

/// Clear images at cursor.
pub fn clearAtCursor(writer: *std.Io.Writer) !void {
    try writeCommand(writer, .{ .a = 'd', .d = 'c' });
}

// =============================================================================
// Transmission
// =============================================================================

pub const TransmitOptions = struct {
    format: Format = .rgba,
    width: ?usize = null,
    height: ?usize = null,
    id: ?usize = null,
};

const MAX_CHUNK: usize = 3072;

/// Transmit image data with chunking.
pub fn transmit(writer: *std.Io.Writer, data: []const u8, opts: TransmitOptions) !void {
    if (data.len <= MAX_CHUNK) {
        try writeCommandWithPayload(writer, data, .{
            .a = 'T',
            .f = @intFromEnum(opts.format),
            .s = opts.width,
            .v = opts.height,
            .i = opts.id,
            .m = 0,
        });
    } else {
        var offset: usize = 0;
        var first = true;
        while (offset < data.len) {
            const end = @min(offset + MAX_CHUNK, data.len);
            const is_last = end >= data.len;

            if (first) {
                try writeCommandWithPayload(writer, data[offset..end], .{
                    .a = 'T',
                    .f = @intFromEnum(opts.format),
                    .s = opts.width,
                    .v = opts.height,
                    .i = opts.id,
                    .m = if (is_last) 0 else 1,
                });
                first = false;
            } else {
                try writeContinuation(writer, data[offset..end], is_last);
            }
            offset = end;
        }
    }
}

/// Transmit file path (terminal reads file).
pub fn transmitPath(writer: *std.Io.Writer, path: []const u8, opts: TransmitOptions) !void {
    try writeCommandWithPayload(writer, path, .{
        .a = 'T',
        .f = @intFromEnum(opts.format),
        .t = 'f',
        .i = opts.id,
        .m = 0,
    });
}

/// Transmit file contents with streaming.
pub fn transmitFile(io: std.Io, writer: *std.Io.Writer, file: std.Io.File, opts: TransmitOptions) !void {
    var buf_a: [MAX_CHUNK]u8 = undefined;
    var buf_b: [MAX_CHUNK]u8 = undefined;
    var current: []u8 = &buf_a;
    var next: []u8 = &buf_b;

    var current_len = try file.readStreaming(io, &.{current});
    if (current_len == 0) {
        try writeCommandWithPayload(writer, &.{}, .{
            .a = 'T',
            .f = @intFromEnum(opts.format),
            .i = opts.id,
            .m = 0,
        });
        return;
    }

    var first = true;
    while (current_len > 0) {
        const next_len = try file.readStreaming(io, &.{next});
        const is_last = next_len == 0;

        if (first) {
            try writeCommandWithPayload(writer, current[0..current_len], .{
                .a = 'T',
                .f = @intFromEnum(opts.format),
                .i = opts.id,
                .m = if (is_last) 0 else 1,
            });
            first = false;
        } else {
            try writeContinuation(writer, current[0..current_len], is_last);
        }

        const tmp = current;
        current = next;
        next = tmp;
        current_len = next_len;
    }
}

// =============================================================================
// Low-level Protocol
// =============================================================================

/// Protocol parameters.
pub const Params = struct {
    a: ?u8 = null, // action
    f: ?usize = null, // format
    t: ?u8 = null, // transmission
    s: ?usize = null, // width
    v: ?usize = null, // height
    i: ?usize = null, // image id
    p: ?usize = null, // placement id
    m: ?usize = null, // more data
    d: ?u8 = null, // delete
    q: ?u8 = null, // quiet
    x: ?usize = null, // x offset
    y: ?usize = null, // y offset
    w: ?usize = null, // display width
    h: ?usize = null, // display height
    c: ?usize = null, // columns
    r: ?usize = null, // rows
    z: ?isize = null, // z-index
};

const ESC = std.ascii.control_code.esc;

fn writeCommand(writer: *std.Io.Writer, params: Params) !void {
    try writer.writeAll(&.{ ESC, '_', 'G' });
    try writeParams(writer, params);
    try writer.writeAll(&.{ ESC, '\\' });
}

fn writeCommandWithPayload(writer: *std.Io.Writer, payload: []const u8, params: Params) !void {
    try writer.writeAll(&.{ ESC, '_', 'G' });
    try writeParams(writer, params);
    try writer.writeByte(';');
    try std.base64.standard.Encoder.encodeWriter(writer, payload);
    try writer.writeAll(&.{ ESC, '\\' });
}

fn writeContinuation(writer: *std.Io.Writer, chunk: []const u8, is_last: bool) !void {
    try writer.writeAll(&.{ ESC, '_', 'G' });
    try writer.writeAll(if (is_last) "m=0;" else "m=1;");
    try std.base64.standard.Encoder.encodeWriter(writer, chunk);
    try writer.writeAll(&.{ ESC, '\\' });
}

fn writeParams(writer: *std.Io.Writer, params: Params) !void {
    var first = true;
    var buf: [20]u8 = undefined;

    inline for (std.meta.fields(Params)) |field| {
        if (@field(params, field.name)) |v| {
            if (!first) try writer.writeByte(',');
            first = false;
            try writer.writeAll(field.name);
            try writer.writeByte('=');
            switch (@TypeOf(v)) {
                u8 => try writer.writeByte(v),
                usize => try writer.writeAll(std.fmt.bufPrint(&buf, "{d}", .{v}) catch unreachable),
                isize => try writer.writeAll(std.fmt.bufPrint(&buf, "{d}", .{v}) catch unreachable),
                else => @compileError("unsupported type"),
            }
        }
    }
}

// =============================================================================
// Canvas
// =============================================================================

/// RGBA pixel buffer.
pub const Canvas = struct {
    width: usize,
    height: usize,
    pixels: []u8,

    pub fn initAlloc(allocator: std.mem.Allocator, width: usize, height: usize) !Canvas {
        return .{
            .width = width,
            .height = height,
            .pixels = try allocator.alloc(u8, width * height * 4),
        };
    }

    pub fn deinit(self: *Canvas, allocator: std.mem.Allocator) void {
        allocator.free(self.pixels);
    }

    pub fn display(self: *Canvas, writer: *std.Io.Writer) !void {
        try displayRgba(writer, self.pixels, self.width, self.height);
    }

    pub fn setPixel(self: *Canvas, x: usize, y: usize, r: u8, g: u8, b: u8, a: u8) void {
        const idx = (y * self.width + x) * 4;
        if (idx + 3 < self.pixels.len) {
            self.pixels[idx] = r;
            self.pixels[idx + 1] = g;
            self.pixels[idx + 2] = b;
            self.pixels[idx + 3] = a;
        }
    }

    pub fn drawBox(self: *Canvas, x: usize, y: usize, w: usize, h: usize, color: u32) void {
        const r, const g, const b, const a = std.mem.toBytes(color);
        for (0..h) |dy| {
            for (0..w) |dx| {
                self.setPixel(x + dx, y + dy, r, g, b, a);
            }
        }
    }

    pub fn clear(self: *Canvas) void {
        @memset(self.pixels, 0);
    }
};

// =============================================================================
// Tests
// =============================================================================

test "transmit small data" {
    var buf: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try transmit(&writer, "test", .{ .format = .png });

    const out = writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, out, "a=T") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "f=100") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "m=0") != null);
}

test "transmit chunked data" {
    var large: [MAX_CHUNK + 100]u8 = undefined;
    @memset(&large, 0xAB);

    var buf: [16384]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try transmit(&writer, &large, .{ .format = .rgba });

    const out = writer.buffered();
    var chunks: usize = 0;
    for (0..out.len - 1) |i| {
        if (out[i] == ESC and out[i + 1] == '_') chunks += 1;
    }
    try std.testing.expect(chunks >= 2);
}

test "writeParams" {
    var buf: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try writeParams(&writer, .{ .a = 'T', .f = 32, .s = 10, .v = 20 });

    const out = writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, out, "a=T") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "f=32") != null);
}

test "Canvas setPixel" {
    var pixels: [16]u8 = undefined;
    var canvas = Canvas{ .width = 2, .height = 2, .pixels = &pixels };

    canvas.setPixel(0, 0, 255, 0, 0, 255);
    try std.testing.expectEqual(@as(u8, 255), pixels[0]); // R
    try std.testing.expectEqual(@as(u8, 0), pixels[1]); // G
    try std.testing.expectEqual(@as(u8, 0), pixels[2]); // B
    try std.testing.expectEqual(@as(u8, 255), pixels[3]); // A
}
