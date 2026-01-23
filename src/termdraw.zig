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

const E = @import("ttyz.zig").E;
const std = @import("std");

/// Terminal drawing context for managing drawing state.
pub const TermDraw = @This();

width: usize,
height: usize,
const C = BoxChars.Heavy;
const horiz = C.get(.horiz);
const vert = C.get(.vert);
const dl = C.get(.dl);
const dr = C.get(.dr);
const ur = C.get(.ur);
const ul = C.get(.ul);

/// Initialize a TermDraw context with the given dimensions.
pub fn init(width: usize, height: usize) !TermDraw {
    return .{ .width = width, .height = height };
}

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
pub fn box(w: *std.Io.Writer, o: BoxOptions) !void {
    const x = o.x;
    const y = o.y;
    const width = o.width;
    const height = o.height;
    if (o.color) |color| try w.print(E.SET_TRUCOLOR, .{ color[0], color[1], color[2] });
    try w.print(E.GOTO, .{ y, x });
    try w.writeAll(dr);
    _ = try w.writeSplat(&.{horiz}, width -| 2);
    try w.writeAll(dl);
    for (1..height -| 1) |i| {
        try w.print(E.GOTO ++ vert ++ E.GOTO ++ vert, .{ y + i, x, y + i, x + width -| 1 });
    }
    try w.print(E.GOTO ++ ur, .{ y + height -| 1, x });
    _ = try w.writeSplat(&.{horiz}, width -| 2);
    try w.writeAll(ul ++ E.RESET_COLORS);
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
pub fn hline(w: *std.Io.Writer, o: HLineOptions) !void {
    try w.print(E.GOTO, .{ o.y, o.x });
    _ = try w.writeSplat(&.{horiz}, o.width);
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
pub fn vline(w: *std.Io.Writer, o: VLineOptions) !void {
    for (0..o.height) |i| {
        try w.print(E.GOTO ++ vert, .{ o.y + @as(u16, @intCast(i)), o.x });
    }
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
