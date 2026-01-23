const E = @import("ttyz.zig").E;
const std = @import("std");

pub const TermDraw = struct {
    width: usize,
    height: usize,

    pub fn init(width: usize, height: usize) !TermDraw {
        return .{ .width = width, .height = height };
    }

    const BoxOptions = struct { x: u8, y: u8, width: u8, height: u8 };
    pub fn box(w: *std.io.Writer, o: BoxOptions) !void {
        try w.print(E.GOTO, .{ o.y, o.x });
        try w.writeAll(C[0..3]);
        _ = try w.writeSplat(&.{H}, o.width - 2);
        try w.writeAll(C[6..9]);
        for (0..o.height - 1) |i| {
            try w.print(E.GOTO, .{ o.y + i + 1, o.x });
            try w.writeAll(V);
            try w.print(E.GOTO, .{ o.y + i + 1, o.x + o.width - 1 });
            try w.writeAll(V);
        }
        try w.print(E.GOTO, .{ o.y + o.height, o.x });
        try w.writeAll(C[9..12]);
        _ = try w.writeSplat(&.{H}, o.width - 2);
        try w.writeAll(C[15..18]);
    }
};
const C = "╔╦╗╚╩╝";
const L = "╠╬╣║═";
const H = L[12..15];
const V = L[9..12];
