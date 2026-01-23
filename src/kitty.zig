//! Kitty graphics protocol implementation for terminal image display.
//!
//! This module implements the Kitty terminal graphics protocol, allowing
//! images to be displayed directly in compatible terminals (Kitty, WezTerm, etc.).
//!
//! ## Protocol Reference
//! See: https://sw.kovidgoyal.net/kitty/graphics-protocol/
//!
//! ## Example
//! ```zig
//! // Display RGBA pixel data directly
//! try kitty.displayRgba(writer, pixels, width, height);
//!
//! // Display a PNG file
//! try kitty.displayFile(writer, "/path/to/image.png");
//!
//! // Low-level: create custom image command
//! var image = kitty.Image.init();
//! image.setAction(.transmit_and_display);
//! image.setFormat(.rgba);
//! image.setSize(width, height);
//! try image.transmit(writer, pixels);
//! ```

const std = @import("std");
const cc = std.ascii.control_code;

/// Maximum chunk size for transmission (4096 bytes of base64 = 3072 bytes raw)
const MAX_CHUNK_SIZE: usize = 3072;

// =============================================================================
// High-Level API
// =============================================================================

/// Display RGBA pixel data at the current cursor position.
/// This is the simplest way to show an image from raw pixel data.
pub fn displayRgba(writer: *std.Io.Writer, pixels: []const u8, width: usize, height: usize) !void {
    var image = Image.init();
    image.setAction(.transmit_and_display);
    image.setFormat(.rgba);
    image.setSize(width, height);
    try image.transmit(writer, pixels);
}

/// Display RGB pixel data (no alpha) at the current cursor position.
pub fn displayRgb(writer: *std.Io.Writer, pixels: []const u8, width: usize, height: usize) !void {
    var image = Image.init();
    image.setAction(.transmit_and_display);
    image.setFormat(.rgb);
    image.setSize(width, height);
    try image.transmit(writer, pixels);
}

/// Display a PNG file at the current cursor position.
/// The path must be accessible by the terminal (use absolute paths).
pub fn displayFile(writer: *std.Io.Writer, path: []const u8) !void {
    var image = Image.init();
    image.setAction(.transmit_and_display);
    image.setTransmission(.file);
    image.setFormat(.png);
    try image.transmitPath(writer, path);
}

/// Delete all images from the terminal.
pub fn deleteAll(writer: *std.Io.Writer) !void {
    var cmd = Image.init();
    cmd.setAction(.delete);
    cmd.params.d = 'a'; // delete all
    try cmd.writeCommand(writer);
}

/// Delete a specific image by ID.
pub fn deleteById(writer: *std.Io.Writer, image_id: usize) !void {
    var cmd = Image.init();
    cmd.setAction(.delete);
    cmd.params.d = 'i'; // delete by id
    cmd.params.i = image_id;
    try cmd.writeCommand(writer);
}

/// Clear all images at the current cursor position.
pub fn clearAtCursor(writer: *std.Io.Writer) !void {
    var cmd = Image.init();
    cmd.setAction(.delete);
    cmd.params.d = 'c'; // delete at cursor
    try cmd.writeCommand(writer);
}

// =============================================================================
// Image Builder
// =============================================================================

/// An image command for the Kitty graphics protocol.
pub const Image = struct {
    params: Params = .{},

    /// Create a new image command with default settings.
    pub fn init() Image {
        return .{};
    }

    /// Create an image with specific parameters and payload (legacy API).
    pub fn with(control_data: Params, payload: []const u8) struct { Image, []const u8 } {
        return .{ .{ .params = control_data }, payload };
    }

    // -------------------------------------------------------------------------
    // Setters for common parameters
    // -------------------------------------------------------------------------

    /// Set the action to perform.
    pub fn setAction(self: *Image, action: Action) void {
        self.params.a = @intFromEnum(action);
    }

    /// Set the pixel format.
    pub fn setFormat(self: *Image, format: Format) void {
        self.params.f = @intFromEnum(format);
    }

    /// Set the transmission type.
    pub fn setTransmission(self: *Image, t: Transmission) void {
        self.params.t = @intFromEnum(t);
    }

    /// Set the source image dimensions.
    pub fn setSize(self: *Image, width: usize, height: usize) void {
        self.params.s = width;
        self.params.v = height;
    }

    /// Set the display size (for scaling).
    pub fn setDisplaySize(self: *Image, width: usize, height: usize) void {
        self.params.w = width;
        self.params.h = height;
    }

    /// Set the display position offset.
    pub fn setOffset(self: *Image, x: usize, y: usize) void {
        self.params.x = x;
        self.params.y = y;
    }

    /// Set the number of terminal cells to use for display.
    pub fn setCells(self: *Image, cols: usize, rows: usize) void {
        self.params.c = cols;
        self.params.r = rows;
    }

    /// Set a unique ID for this image (for later reference/deletion).
    pub fn setId(self: *Image, id: usize) void {
        self.params.i = id;
    }

    /// Set the placement ID (for multiple placements of same image).
    pub fn setPlacementId(self: *Image, id: usize) void {
        self.params.p = id;
    }

    /// Set the Z-index for layering.
    pub fn setZIndex(self: *Image, z: isize) void {
        self.params.z = z;
    }

    /// Suppress terminal response messages.
    pub fn setQuiet(self: *Image, level: QuietLevel) void {
        self.params.q = @intFromEnum(level);
    }

    // -------------------------------------------------------------------------
    // Transmission methods
    // -------------------------------------------------------------------------

    /// Transmit pixel data (handles chunking for large images).
    pub fn transmit(self: *Image, writer: *std.Io.Writer, data: []const u8) !void {
        if (data.len <= MAX_CHUNK_SIZE) {
            // Single chunk transmission
            self.params.m = 0;
            try self.writeCommandWithPayload(writer, data);
        } else {
            // Chunked transmission
            var offset: usize = 0;
            var first = true;
            while (offset < data.len) {
                const end = @min(offset + MAX_CHUNK_SIZE, data.len);
                const chunk = data[offset..end];
                const is_last = end >= data.len;

                self.params.m = if (is_last) 0 else 1;

                if (first) {
                    try self.writeCommandWithPayload(writer, chunk);
                    first = false;
                    // Clear params that shouldn't repeat
                    self.params.s = null;
                    self.params.v = null;
                    self.params.f = null;
                } else {
                    try self.writeContinuation(writer, chunk, is_last);
                }

                offset = end;
            }
        }
    }

    /// Transmit a file path.
    pub fn transmitPath(self: *Image, writer: *std.Io.Writer, path: []const u8) !void {
        self.params.m = 0;
        try self.writeCommandWithPayload(writer, path);
    }

    // -------------------------------------------------------------------------
    // Low-level write methods
    // -------------------------------------------------------------------------

    /// Write a command without payload.
    pub fn writeCommand(self: *Image, writer: *std.Io.Writer) !void {
        try writer.writeAll(&[_]u8{ cc.esc, '_', 'G' });
        try self.writeParams(writer);
        try writer.writeAll(&[_]u8{ cc.esc, '\\' });
    }

    /// Write a command with base64-encoded payload.
    pub fn writeCommandWithPayload(self: *Image, writer: *std.Io.Writer, payload: []const u8) !void {
        try writer.writeAll(&[_]u8{ cc.esc, '_', 'G' });
        try self.writeParams(writer);
        try writer.writeByte(';');
        try std.base64.standard.Encoder.encodeWriter(writer, payload);
        try writer.writeAll(&[_]u8{ cc.esc, '\\' });
    }

    /// Write a continuation chunk for chunked transmission.
    fn writeContinuation(self: *Image, writer: *std.Io.Writer, chunk: []const u8, is_last: bool) !void {
        _ = self;
        try writer.writeAll(&[_]u8{ cc.esc, '_', 'G' });
        if (is_last) {
            try writer.writeAll("m=0;");
        } else {
            try writer.writeAll("m=1;");
        }
        try std.base64.standard.Encoder.encodeWriter(writer, chunk);
        try writer.writeAll(&[_]u8{ cc.esc, '\\' });
    }

    /// Write control parameters.
    fn writeParams(self: *Image, writer: *std.Io.Writer) !void {
        var first = true;
        var int_buf: [20]u8 = undefined;
        inline for (std.meta.fields(Params)) |field| {
            const value = @field(self.params, field.name);
            if (value) |v| {
                if (!first) try writer.writeByte(',');
                first = false;
                try writer.writeAll(field.name);
                try writer.writeByte('=');
                switch (@TypeOf(v)) {
                    u8 => try writer.writeByte(v),
                    usize => {
                        const slice = std.fmt.bufPrint(&int_buf, "{d}", .{v}) catch unreachable;
                        try writer.writeAll(slice);
                    },
                    isize => {
                        const slice = std.fmt.bufPrint(&int_buf, "{d}", .{v}) catch unreachable;
                        try writer.writeAll(slice);
                    },
                    else => @compileError("unsupported param type"),
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // Enums
    // -------------------------------------------------------------------------

    /// Actions that can be performed.
    pub const Action = enum(u8) {
        transmit = 't',
        transmit_and_display = 'T',
        query = 'q',
        put = 'p', // display previously transmitted
        delete = 'd',
        frame = 'f', // animation frame
        animation = 'a', // animation control
        compose = 'c', // compose frames
    };

    /// Pixel formats.
    pub const Format = enum(usize) {
        rgb = 24,
        rgba = 32,
        png = 100,
    };

    /// Transmission types.
    pub const Transmission = enum(u8) {
        direct = 'd', // direct pixel data
        file = 'f', // file path
        temp_file = 't', // temporary file
        shared_memory = 's', // shared memory
    };

    /// Quiet levels.
    pub const QuietLevel = enum(u8) {
        normal = 0,
        suppress_ok = 1,
        suppress_all = 2,
    };

    // -------------------------------------------------------------------------
    // Parameters struct
    // -------------------------------------------------------------------------

    /// Control parameters for the Kitty graphics protocol.
    /// See: https://sw.kovidgoyal.net/kitty/graphics-protocol/#control-data-reference
    pub const Params = struct {
        // zig fmt: off
        /// Action: 't' (transmit), 'T' (transmit+display), 'q' (query), etc.
        a: ?u8 = null,
        /// Quiet mode: 1 (suppress OK), 2 (suppress errors too).
        q: ?u8 = null,
        /// Format: 24 (RGB), 32 (RGBA), 100 (PNG).
        f: ?usize = null,
        /// Transmission type: 'd' (direct), 'f' (file), 't' (temp file), 's' (shared memory).
        t: ?u8 = null,
        /// Source width in pixels.
        s: ?usize = null,
        /// Source height in pixels.
        v: ?usize = null,
        /// Total data size for chunked transmission.
        S: ?usize = null,
        /// Offset into data for chunked transmission.
        O: ?usize = null,
        /// Image ID for later reference.
        i: ?usize = null,
        /// Image number for placement.
        I: ?usize = null,
        /// Placement ID.
        p: ?usize = null,
        /// Compression: 'z' for zlib.
        o: ?u8 = null,
        /// More data coming: 1 if chunked, 0 for final chunk.
        m: ?usize = null,
        /// Display x position offset.
        x: ?usize = null,
        /// Display y position offset.
        y: ?usize = null,
        /// Display width (scaled).
        w: ?usize = null,
        /// Display height (scaled).
        h: ?usize = null,
        /// Source x offset (crop).
        X: ?usize = null,
        /// Source y offset (crop).
        Y: ?usize = null,
        /// Columns to display.
        c: ?usize = null,
        /// Rows to display.
        r: ?usize = null,
        /// Cursor movement after display.
        C: ?usize = null,
        /// Unicode placeholder.
        U: ?usize = null,
        /// Z-index for layering.
        z: ?isize = null,
        /// Delete specifier.
        d: ?u8 = null,
        /// Parent image ID.
        P: ?usize = null,
        /// Suppress response.
        Q: ?usize = null,
        /// Horizontal offset within cell.
        H: ?usize = null,
        /// Vertical offset within cell.
        V: ?usize = null,
        // zig fmt: on
    };
};

// =============================================================================
// Canvas - Pixel buffer for drawing
// =============================================================================

/// A pixel canvas with RGBA storage for drawing operations.
pub const Canvas = struct {
    width: usize,
    height: usize,
    pixels: []u8,

    pub fn initAlloc(allocator: std.mem.Allocator, width: usize, height: usize) !Canvas {
        const pixels = try allocator.alloc(u8, width * height * 4);
        return .{ .width = width, .height = height, .pixels = pixels };
    }

    pub fn init(width: usize, height: usize, pixels: []u8) Canvas {
        return .{ .width = width, .height = height, .pixels = pixels };
    }

    pub fn deinit(self: *Canvas, allocator: std.mem.Allocator) void {
        allocator.free(self.pixels);
    }

    pub fn display(self: *Canvas, writer: *std.Io.Writer) !void {
        try displayRgba(writer, self.pixels, self.width, self.height);
    }

    pub fn drawBox(self: *Canvas, x: usize, y: usize, width: usize, height: usize, color: u32) void {
        const a, const g, const b, const r = std.mem.toBytes(color);
        for (0..width) |i| {
            for (0..height) |j| {
                const idx = (y + j) * (self.width * 4) + (x + i) * 4;
                if (idx + 3 < self.pixels.len) {
                    self.pixels[idx] = b;
                    self.pixels[idx + 1] = g;
                    self.pixels[idx + 2] = r;
                    self.pixels[idx + 3] = a;
                }
            }
        }
    }

    pub fn setPixel(self: *Canvas, x: usize, y: usize, r: u8, g: u8, b: u8, a: u8) void {
        const idx = y * (self.width * 4) + x * 4;
        if (idx + 3 < self.pixels.len) {
            self.pixels[idx] = r;
            self.pixels[idx + 1] = g;
            self.pixels[idx + 2] = b;
            self.pixels[idx + 3] = a;
        }
    }

    pub fn clear(self: *Canvas) void {
        @memset(self.pixels, 0);
    }
};

// =============================================================================
// Tests
// =============================================================================

test "Image.init creates default image" {
    const img = Image.init();
    try std.testing.expectEqual(@as(?u8, null), img.params.a);
    try std.testing.expectEqual(@as(?usize, null), img.params.f);
}

test "Image setters work correctly" {
    var img = Image.init();
    img.setAction(.transmit_and_display);
    img.setFormat(.rgba);
    img.setSize(100, 50);

    try std.testing.expectEqual(@as(?u8, 'T'), img.params.a);
    try std.testing.expectEqual(@as(?usize, 32), img.params.f);
    try std.testing.expectEqual(@as(?usize, 100), img.params.s);
    try std.testing.expectEqual(@as(?usize, 50), img.params.v);
}

test "writeParams outputs correct format" {
    var img = Image.init();
    img.setAction(.transmit_and_display);
    img.setFormat(.rgba);
    img.setSize(10, 20);
    img.params.m = 0;

    var buf: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try img.writeParams(&writer);

    const output = writer.buffered();
    // Should contain key=value pairs separated by commas
    try std.testing.expect(std.mem.indexOf(u8, output, "a=T") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "f=32") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "s=10") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "v=20") != null);
}

test "writeCommand produces valid escape sequence" {
    var img = Image.init();
    img.setAction(.delete);
    img.params.d = 'a';

    var buf: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try img.writeCommand(&writer);

    const output = writer.buffered();
    // Should start with ESC_G and end with ESC\
    try std.testing.expectEqual(@as(u8, 0x1B), output[0]);
    try std.testing.expectEqual(@as(u8, '_'), output[1]);
    try std.testing.expectEqual(@as(u8, 'G'), output[2]);
    try std.testing.expectEqual(@as(u8, 0x1B), output[output.len - 2]);
    try std.testing.expectEqual(@as(u8, '\\'), output[output.len - 1]);
}

test "writeCommandWithPayload includes base64 data" {
    var img = Image.init();
    img.setAction(.transmit_and_display);
    img.setFormat(.rgba);
    img.params.m = 0;

    var buf: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    const test_data = "test";
    try img.writeCommandWithPayload(&writer, test_data);

    const output = writer.buffered();
    // Should contain base64 encoded "test" = "dGVzdA=="
    try std.testing.expect(std.mem.indexOf(u8, output, "dGVzdA==") != null);
}

test "chunked transmission splits large data" {
    var img = Image.init();
    img.setAction(.transmit_and_display);
    img.setFormat(.rgba);
    img.setSize(100, 100);

    // Create data larger than MAX_CHUNK_SIZE
    var large_data: [MAX_CHUNK_SIZE + 100]u8 = undefined;
    @memset(&large_data, 0xAB);

    var buf: [16384]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try img.transmit(&writer, &large_data);

    const output = writer.buffered();
    // Should have multiple ESC sequences (chunked)
    var count: usize = 0;
    for (0..output.len - 1) |i| {
        if (output[i] == 0x1B and output[i + 1] == '_') count += 1;
    }
    try std.testing.expect(count >= 2);
}
