//! Terminal drawing utilities using Unicode box-drawing characters.
//!
//! Provides functions for drawing boxes, lines, and other shapes using
//! heavy Unicode box-drawing characters (━, ┃, ┏, ┓, etc.).
//!
//! ## Example
//! ```zig
//! try termdraw.box(&writer, .{
//!     .x = 10, .y = 5,
//!     .width = 20, .height = 10,
//!     .color = .{255, 128, 0, 255},
//! });
//! try termdraw.hline(&writer, .{ .x = 0, .y = 20, .width = 40 });
//! ```

const assert = std.debug.assert;

const C = BoxChars.Heavy;
const horiz = C.get(.horiz);
const vert = C.get(.vert);
const dl = C.get(.dl);
const dr = C.get(.dr);
const ur = C.get(.ur);
const ul = C.get(.ul);

/// Options for drawing a box.
const BoxOptions = struct {
    /// X position (column) of the top-left corner.
    x: u16,
    /// Y position (row) of the top-left corner.
    y: u16,
    /// Width of the box in columns.
    width: u16,
    /// Height of the box in rows.
    height: u16,
    /// Optional RGBA color for the box border.
    color: ?[4]u8 = null,
};

/// Draw a box with Unicode box-drawing characters.
/// The box is drawn at the specified position with the given dimensions.
/// Works with any writer that has print and writeAll methods.
/// For bounds-checked drawing, use TermDraw.box.
/// Invariant: width and height must be >= 2 for a proper box.
pub fn box(w: anytype, o: BoxOptions) !void {
    try boxRaw(w, o);
}

fn boxRaw(w: anytype, o: BoxOptions) !void {
    // A box needs at least 2x2 for corners
    assert(o.width >= 2 and o.height >= 2);
    const x = o.x;
    const y = o.y;
    const width = o.width;
    const height = o.height;
    var buf: [256]u8 = undefined;
    if (o.color) |color| {
        const s = std.fmt.bufPrint(&buf, ansi.fg_rgb_fmt, .{ color[0], color[1], color[2] }) catch return;
        _ = try w.write(s);
    }
    const goto_s = std.fmt.bufPrint(&buf, ansi.goto_fmt, .{ y, x }) catch return;
    _ = try w.write(goto_s);
    _ = try w.write(dr);
    var i: u16 = 0;
    while (i < width -| 2) : (i += 1) {
        _ = try w.write(horiz);
    }
    _ = try w.write(dl);
    for (1..height -| 1) |row| {
        const line_s = std.fmt.bufPrint(&buf, ansi.goto_fmt ++ vert ++ ansi.goto_fmt ++ vert, .{ y + row, x, y + row, x + width -| 1 }) catch return;
        _ = try w.write(line_s);
    }
    const bottom_s = std.fmt.bufPrint(&buf, ansi.goto_fmt ++ ur, .{ y + height -| 1, x }) catch return;
    _ = try w.write(bottom_s);
    i = 0;
    while (i < width -| 2) : (i += 1) {
        _ = try w.write(horiz);
    }
    _ = try w.write(ul ++ ansi.reset);
}

/// Options for drawing a horizontal line.
const HLineOptions = struct {
    /// X position (column) of the line start.
    x: u16,
    /// Y position (row) of the line.
    y: u16,
    /// Width of the line in columns.
    width: u16,
};

/// Draw a horizontal line using the heavy horizontal box character (━).
/// For bounds-checked drawing, use TermDraw.hline.
pub fn hline(w: anytype, o: HLineOptions) !void {
    try hlineRaw(w, o);
}

fn hlineRaw(w: anytype, o: HLineOptions) !void {
    var buf: [32]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, ansi.goto_fmt, .{ o.y, o.x }) catch return;
    _ = try w.write(s);
    var i: u16 = 0;
    while (i < o.width) : (i += 1) {
        _ = try w.write(horiz);
    }
}

/// Options for drawing a vertical line.
const VLineOptions = struct {
    /// X position (column) of the line.
    x: u16,
    /// Y position (row) of the line start.
    y: u16,
    /// Height of the line in rows.
    height: u16,
};

/// Draw a vertical line using the heavy vertical box character (┃).
/// For bounds-checked drawing, use TermDraw.vline.
pub fn vline(w: anytype, o: VLineOptions) !void {
    try vlineRaw(w, o);
}

fn vlineRaw(w: anytype, o: VLineOptions) !void {
    var buf: [32]u8 = undefined;
    for (0..o.height) |i| {
        const s = std.fmt.bufPrint(&buf, ansi.goto_fmt ++ vert, .{ o.y + @as(u16, @intCast(i)), o.x }) catch return;
        _ = try w.write(s);
    }
}

fn posWithin(pos: u16, max: usize) bool {
    if (pos == 0) return false;
    return @as(usize, pos) <= max;
}

fn clampSpan(max: usize, pos: u16, len: u16) ?u16 {
    if (len == 0) return null;
    if (!posWithin(pos, max)) return null;
    const start = @as(usize, pos);
    const remaining = max - start + 1;
    const clamped = @min(@as(usize, len), remaining);
    if (clamped == 0) return null;
    return @as(u16, @intCast(clamped));
}

fn clampBox(self: *const TermDraw, o: BoxOptions) ?BoxOptions {
    if (o.width < 2 or o.height < 2) return null;
    const width = clampSpan(self.width, o.x, o.width) orelse return null;
    const height = clampSpan(self.height, o.y, o.height) orelse return null;
    if (width < 2 or height < 2) return null;
    return .{ .x = o.x, .y = o.y, .width = width, .height = height, .color = o.color };
}

fn clampHLine(self: *const TermDraw, o: HLineOptions) ?HLineOptions {
    if (!posWithin(o.y, self.height)) return null;
    const width = clampSpan(self.width, o.x, o.width) orelse return null;
    return .{ .x = o.x, .y = o.y, .width = width };
}

fn clampVLine(self: *const TermDraw, o: VLineOptions) ?VLineOptions {
    if (!posWithin(o.x, self.width)) return null;
    const height = clampSpan(self.height, o.y, o.height) orelse return null;
    return .{ .x = o.x, .y = o.y, .height = height };
}

/// Terminal drawing context for bounds-clamped drawing.
pub const TermDraw = struct {
    /// Terminal width in columns.
    width: usize,
    /// Terminal height in rows.
    height: usize,

    pub const InitError = error{InvalidDimensions};

    /// Initialize a TermDraw context with the given dimensions.
    /// Returns error.InvalidDimensions if width or height is zero.
    pub fn init(width: usize, height: usize) InitError!TermDraw {
        if (width == 0 or height == 0) return error.InvalidDimensions;
        return .{ .width = width, .height = height };
    }

    /// Draw a box clipped to the context bounds.
    pub fn box(self: *const TermDraw, w: anytype, o: BoxOptions) !void {
        const clipped = clampBox(self, o) orelse return;
        try boxRaw(w, clipped);
    }

    /// Draw a horizontal line clipped to the context bounds.
    pub fn hline(self: *const TermDraw, w: anytype, o: HLineOptions) !void {
        const clipped = clampHLine(self, o) orelse return;
        try hlineRaw(w, clipped);
    }

    /// Draw a vertical line clipped to the context bounds.
    pub fn vline(self: *const TermDraw, w: anytype, o: VLineOptions) !void {
        const clipped = clampVLine(self, o) orelse return;
        try vlineRaw(w, clipped);
    }
};

/// Initialize a TermDraw context with the given dimensions.
pub fn init(width: usize, height: usize) !TermDraw {
    return TermDraw.init(width, height);
}

pub const Chars = [_][]const u8{
    '─', '━', '│', '┃', '┄', '┅', '┆', '┇', '┈', '┉', '┊', '┋', '┌', '┍', '┎', '┏',
    '┐', '┑', '┒', '┓', '└', '┕', '┖', '┗', '┘', '┙', '┚', '┛', '├', '┝', '┞', '┟',
    '┠', '┡', '┢', '┣', '┤', '┥', '┦', '┧', '┨', '┩', '┪', '┫', '┬', '┭', '┮', '┯',
    '┰', '┱', '┲', '┳', '┴', '┵', '┶', '┷', '┸', '┹', '┺', '┻', '┼', '┽', '┾', '┿',
    '╀', '╁', '╂', '╃', '╄', '╅', '╆', '╇', '╈', '╉', '╊', '╋', '╌', '╍', '╎', '╏',
    '═', '║', '╒', '╓', '╔', '╕', '╖', '╗', '╘', '╙', '╚', '╛', '╜', '╝', '╞', '╟',
    '╠', '╡', '╢', '╣', '╤', '╥', '╦', '╧', '╨', '╩', '╪', '╫', '╬', '╭', '╮', '╯',
    '╰', '╱', '╲', '╳', '╴', '╵', '╶', '╷', '╸', '╹', '╺', '╻', '╼', '╽', '╾', '╿',
};

const BoxChars = struct {
    const Heavy = std.enums.EnumArray(Names, []const u8).init(.{
        // zig fmt: off
        .ddh = "╍", .ddv = "╏",
        .down = "╻", .dh = "┳",
        .dl = "┓", .dr = "┏",
        .horiz = "━", .left = "╸",
        .qdh = "┉", .qdb = "┋",
        .right = "╺", .tdh = "┅",
        .tdv = "┇", .up = "╹",
        .uh = "┻", .ul = "┛",
        .ur = "┗", .vert = "┃",
        .vh = "╋", .vl = "┫",
        .vr = "┣",
        // zig fmt: on
    });

    const Names = enum {
        /// double_dash_horizontal,
        ddh,
        /// double_dash_vertical,
        ddv,
        /// down,
        down,
        /// down_and_horizontal,
        dh,
        /// down_and_left,
        dl,
        /// down_and_right,
        dr,
        /// horizontal,
        horiz,
        /// left,
        left,
        /// quadruple_dash_horizontal,
        qdh,
        /// quadruple_dash_vertical,
        qdb,
        /// right,
        right,
        /// triple_dash_horizontal,
        tdh,
        /// triple_dash_vertical,
        tdv,
        /// up,
        up,
        /// up_and_horizontal,
        uh,
        /// up_and_left,
        ul,
        /// up_and_right,
        ur,
        /// vertical,
        vert,
        /// vertical_and_horizontal,
        vh,
        /// vertical_and_left,
        vl,
        /// vertical_and_right,
        vr,
    };
};

const std = @import("std");
const ansi = @import("ansi.zig");
const testing = std.testing;

test "TermDraw.init creates context with dimensions" {
    const td = try TermDraw.init(80, 24);
    try testing.expectEqual(@as(usize, 80), td.width);
    try testing.expectEqual(@as(usize, 24), td.height);
}

test "TermDraw.init rejects zero dimensions" {
    try testing.expectError(error.InvalidDimensions, TermDraw.init(0, 24));
}

test "TermDraw.hline clamps to bounds" {
    const td = try TermDraw.init(5, 5);
    var buf: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try td.hline(&writer, .{ .x = 4, .y = 1, .width = 10 });

    const output = writer.buffered();
    var count: usize = 0;
    var i: usize = 0;
    while (i < output.len) {
        if (std.mem.startsWith(u8, output[i..], "━")) {
            count += 1;
            i += 3;
        } else {
            i += 1;
        }
    }
    try testing.expectEqual(@as(usize, 2), count);
}

test "box draws correct corner characters" {
    var buf: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try box(&writer, .{ .x = 1, .y = 1, .width = 4, .height = 3 });

    const output = writer.buffered();
    // Should contain box corner characters
    try testing.expect(std.mem.indexOf(u8, output, "┏") != null); // dr (down-right)
    try testing.expect(std.mem.indexOf(u8, output, "┓") != null); // dl (down-left)
    try testing.expect(std.mem.indexOf(u8, output, "┗") != null); // ur (up-right)
    try testing.expect(std.mem.indexOf(u8, output, "┛") != null); // ul (up-left)
}

test "box includes horizontal lines" {
    var buf: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try box(&writer, .{ .x = 1, .y = 1, .width = 5, .height = 3 });

    const output = writer.buffered();
    // Should contain horizontal line character
    try testing.expect(std.mem.indexOf(u8, output, "━") != null);
}

test "box with color includes ANSI color codes" {
    var buf: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try box(&writer, .{ .x = 1, .y = 1, .width = 4, .height = 3, .color = .{ 255, 128, 0, 255 } });

    const output = writer.buffered();
    // Should contain RGB color escape sequence
    try testing.expect(std.mem.indexOf(u8, output, "\x1b[38;2;") != null);
    // Should end with reset
    try testing.expect(std.mem.indexOf(u8, output, "\x1b[0m") != null);
}

test "hline draws horizontal line" {
    var buf: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try hline(&writer, .{ .x = 1, .y = 1, .width = 5 });

    const output = writer.buffered();
    // Should contain horizontal line characters
    try testing.expect(std.mem.indexOf(u8, output, "━") != null);
    // Count occurrences of horizontal line (each is 3 bytes in UTF-8)
    var count: usize = 0;
    var i: usize = 0;
    while (i < output.len) {
        if (std.mem.startsWith(u8, output[i..], "━")) {
            count += 1;
            i += 3;
        } else {
            i += 1;
        }
    }
    try testing.expectEqual(@as(usize, 5), count);
}

test "vline draws vertical line" {
    var buf: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try vline(&writer, .{ .x = 1, .y = 1, .height = 3 });

    const output = writer.buffered();
    // Should contain vertical line characters
    try testing.expect(std.mem.indexOf(u8, output, "┃") != null);
    // Count occurrences of vertical line
    var count: usize = 0;
    var i: usize = 0;
    while (i < output.len) {
        if (std.mem.startsWith(u8, output[i..], "┃")) {
            count += 1;
            i += 3;
        } else {
            i += 1;
        }
    }
    try testing.expectEqual(@as(usize, 3), count);
}

test "BoxChars.Heavy returns correct characters" {
    try testing.expectEqualStrings("━", BoxChars.Heavy.get(.horiz));
    try testing.expectEqualStrings("┃", BoxChars.Heavy.get(.vert));
    try testing.expectEqualStrings("┏", BoxChars.Heavy.get(.dr));
    try testing.expectEqualStrings("┓", BoxChars.Heavy.get(.dl));
    try testing.expectEqualStrings("┗", BoxChars.Heavy.get(.ur));
    try testing.expectEqualStrings("┛", BoxChars.Heavy.get(.ul));
}
