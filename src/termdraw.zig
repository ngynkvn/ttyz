const E = @import("ttyz.zig").E;
const std = @import("std");

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

pub fn init(width: usize, height: usize) !TermDraw {
    return .{ .width = width, .height = height };
}

const BoxOptions = struct { x: u16, y: u16, width: u16, height: u16, color: ?[4]u8 = null };
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

const HLineOptions = struct { x: u16, y: u16, width: u16 };
pub fn hline(w: *std.Io.Writer, o: HLineOptions) !void {
    try w.print(E.GOTO, .{ o.y, o.x });
    _ = try w.writeSplat(&.{horiz}, o.width);
}

const VLineOptions = struct { x: u16, y: u16, height: u16 };
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
