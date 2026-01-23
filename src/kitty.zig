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
//! var image = kitty.Image.with(.{
//!     .a = 'T',  // action: transmit and display
//!     .t = 'f',  // transmission: file path
//!     .f = 100,  // format: PNG
//! }, "/path/to/image.png");
//! try image.write(&writer);
//! ```

const std = @import("std");
const cc = std.ascii.control_code;

/// An image for transmission via the Kitty graphics protocol.
/// See: https://sw.kovidgoyal.net/kitty/graphics-protocol/#control-data-reference
pub const Image = struct {
    /// Create an image with the given control parameters and payload.
    pub fn with(control_data: Image.Params, payload: []const u8) Image {
        return .{ .control_data = control_data, .payload = payload };
    }

    /// Write the control data preamble (escape sequence and parameters).
    pub fn writePreamble(self: *Image, w: *std.Io.Writer) !void {
        try w.writeAll(.{@as(u8, cc.esc)} ++ "_G");
        const pfields = @typeInfo(@FieldType(Image, "control_data")).@"struct".fields;
        inline for (pfields) |field| {
            const value = @field(self.control_data, field.name);
            const ctype = std.meta.Child(field.type);
            const fmt = comptime Image.Params.Format(field.name, ctype);
            if (value) |v| try w.print(fmt, .{v});
        }
        try w.writeByte(';');
    }

    /// Write the payload data (base64 encoded) and terminator.
    pub fn writePayload(self: *Image, w: *std.Io.Writer) !void {
        try w.printBase64(self.payload);
        try w.writeAll(.{@as(u8, cc.esc)} ++ "\\");
    }

    /// Write the complete image command (preamble + payload).
    pub fn write(self: *Image, w: *std.Io.Writer) !void {
        try self.writePreamble(w);
        try self.writePayload(w);
        try w.flush();
    }

    /// Set the payload to a file path (for file-based transmission).
    pub fn filePath(self: *Image, path: []const u8) void {
        self.setPayload(path);
    }

    /// Set the raw payload data.
    pub fn setPayload(self: *Image, payload: []const u8) void {
        self.payload = payload;
    }

    /// The raw payload data (image bytes or file path).
    payload: []const u8,
    /// Control parameters for the graphics command.
    control_data: Params,

    /// Default image configuration for direct transmission.
    pub const default = Image{
        .payload = "",
        .control_data = .{ .a = 't', .f = 32, .t = 'd' },
    };

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
        z: ?usize = null,
        /// Parent image ID.
        P: ?usize = null,
        /// Suppress response.
        Q: ?usize = null,
        /// Horizontal offset within cell.
        H: ?usize = null,
        /// Vertical offset within cell.
        V: ?usize = null,
        // zig fmt: on

        fn Format(comptime name: []const u8, T: type) []const u8 {
            return name ++ switch (T) {
                u8 => "={c}",
                usize => "={d}",
                else => unreachable,
            } ++ ",";
        }
    };
};
