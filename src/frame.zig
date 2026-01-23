//! Frame - Cell-based buffer for terminal rendering.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Buffer = @import("frame/buffer.zig").Buffer;
pub const layout = @import("frame/layout.zig");
pub const Layout = layout.Layout;
pub const Direction = layout.Direction;
pub const Constraint = layout.Constraint;
pub const Rect = @import("frame/rect.zig").Rect;
const types = @import("frame/types.zig");
pub const Style = types.Style;
pub const Color = types.Color;
pub const Cell = types.Cell;
pub const BorderStyle = types.BorderStyle;
pub const BorderChars = types.BorderChars;
const ttyz = @import("ttyz.zig");
const Screen = ttyz.Screen;
const ansi = ttyz.ansi;
const E = ansi.E;

// Re-export types
// Layout types
/// Drawing context wrapping a Buffer.
pub const Frame = struct {
    buffer: *Buffer,

    pub fn init(buffer: *Buffer) Frame {
        return .{ .buffer = buffer };
    }

    pub fn area(self: Frame) Rect {
        return self.buffer.area();
    }

    /// Split the frame's area using a layout with N constraints.
    /// Returns N rectangles based on the layout direction and constraints.
    ///
    /// Example:
    /// ```
    /// const areas = frame.areas(Layout(3).vertical(.{
    ///     .{ .length = 3 },      // header
    ///     .{ .fill = 1 },        // content
    ///     .{ .length = 1 },      // footer
    /// }));
    /// ```
    pub fn areas(self: Frame, comptime N: usize, l: Layout(N)) [N]Rect {
        return l.areas(self.area());
    }

    pub fn setCell(self: *Frame, x: u16, y: u16, cell: Cell) void {
        self.buffer.set(x, y, cell);
    }

    pub fn setString(self: *Frame, x: u16, y: u16, text: []const u8, style: Style, fg: Color, bg: Color) void {
        var col = x;
        var iter = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
        while (iter.nextCodepoint()) |codepoint| {
            if (col >= self.buffer.width) break;
            self.buffer.set(col, y, .{ .char = codepoint, .fg = fg, .bg = bg, .style = style });
            col += 1;
        }
    }

    pub fn fillRect(self: *Frame, rect: Rect, cell: Cell) void {
        const clipped = self.buffer.area().intersect(rect) orelse return;
        var y = clipped.y;
        while (y < clipped.bottom()) : (y += 1) {
            var px = clipped.x;
            while (px < clipped.right()) : (px += 1) {
                self.buffer.set(px, y, cell);
            }
        }
    }

    pub fn drawRect(self: *Frame, rect: Rect, border_style: BorderStyle) void {
        self.drawRectStyled(rect, border_style, .{}, .default, .default);
    }

    pub fn drawRectStyled(self: *Frame, rect: Rect, border_style: BorderStyle, style: Style, fg: Color, bg: Color) void {
        if (rect.width < 2 or rect.height < 2) return;
        const chars = border_style.chars();
        const x1, const y1 = .{ rect.x, rect.y };
        const x2, const y2 = .{ rect.x + rect.width - 1, rect.y + rect.height - 1 };

        self.buffer.set(x1, y1, .{ .char = chars.top_left, .fg = fg, .bg = bg, .style = style });
        self.buffer.set(x2, y1, .{ .char = chars.top_right, .fg = fg, .bg = bg, .style = style });
        self.buffer.set(x1, y2, .{ .char = chars.bottom_left, .fg = fg, .bg = bg, .style = style });
        self.buffer.set(x2, y2, .{ .char = chars.bottom_right, .fg = fg, .bg = bg, .style = style });

        var x = x1 + 1;
        while (x < x2) : (x += 1) {
            self.buffer.set(x, y1, .{ .char = chars.horizontal, .fg = fg, .bg = bg, .style = style });
            self.buffer.set(x, y2, .{ .char = chars.horizontal, .fg = fg, .bg = bg, .style = style });
        }
        var y = y1 + 1;
        while (y < y2) : (y += 1) {
            self.buffer.set(x1, y, .{ .char = chars.vertical, .fg = fg, .bg = bg, .style = style });
            self.buffer.set(x2, y, .{ .char = chars.vertical, .fg = fg, .bg = bg, .style = style });
        }
    }

    /// Draw a horizontal line.
    pub fn hline(self: *Frame, x: u16, y: u16, width: u16, char: u21, style: Style, fg: Color, bg: Color) void {
        var col = x;
        while (col < x +| width and col < self.buffer.width) : (col += 1) {
            self.buffer.set(col, y, .{ .char = char, .fg = fg, .bg = bg, .style = style });
        }
    }

    /// Draw a vertical line.
    pub fn vline(self: *Frame, x: u16, y: u16, height: u16, char: u21, style: Style, fg: Color, bg: Color) void {
        var row = y;
        while (row < y +| height and row < self.buffer.height) : (row += 1) {
            self.buffer.set(x, row, .{ .char = char, .fg = fg, .bg = bg, .style = style });
        }
    }

    /// Set a string with default colors.
    pub fn setText(self: *Frame, x: u16, y: u16, text: []const u8) void {
        self.setString(x, y, text, .{}, .default, .default);
    }

    pub fn clear(self: *Frame) void {
        self.buffer.clear();
    }

    pub fn render(self: Frame, screen: *Screen) !void {
        var current_style: Style = .{};
        var current_fg: Color = .default;
        var current_bg: Color = .default;
        try screen.writeAll(E.RESET_STYLE);

        var utf8_buf: [4]u8 = undefined;
        var y: u16 = 0;
        while (y < self.buffer.height) : (y += 1) {
            try screen.print(E.GOTO, .{ y + 1, @as(u16, 1) });
            var x: u16 = 0;
            while (x < self.buffer.width) : (x += 1) {
                const cell = self.buffer.get(x, y);
                if (!cell.style.eql(current_style) or !cell.fg.eql(current_fg) or !cell.bg.eql(current_bg)) {
                    try screen.writeAll(E.RESET_STYLE);
                    current_style = .{};
                    current_fg = .default;
                    current_bg = .default;

                    if (cell.style.bold) try screen.writeAll(E.BOLD);
                    if (cell.style.dim) try screen.writeAll(E.DIM);
                    if (cell.style.italic) try screen.writeAll(E.ITALIC);
                    if (cell.style.underline) try screen.writeAll(E.UNDERLINE);
                    if (cell.style.blink) try screen.writeAll(E.BLINK);
                    if (cell.style.reverse) try screen.writeAll(E.REVERSE);
                    if (cell.style.strikethrough) try screen.writeAll(E.STRIKETHROUGH);

                    switch (cell.fg) {
                        .default => {},
                        .indexed => |i| try screen.print(E.SET_FG_256, .{i}),
                        .rgb => |c| try screen.print(E.SET_TRUCOLOR, .{ c.r, c.g, c.b }),
                    }
                    switch (cell.bg) {
                        .default => {},
                        .indexed => |i| try screen.print(E.SET_BG_256, .{i}),
                        .rgb => |c| try screen.print(E.SET_TRUCOLOR_BG, .{ c.r, c.g, c.b }),
                    }
                    current_style = cell.style;
                    current_fg = cell.fg;
                    current_bg = cell.bg;
                }
                const len = std.unicode.utf8Encode(cell.char, &utf8_buf) catch 1;
                _ = try screen.write(utf8_buf[0..len]);
            }
        }
        try screen.writeAll(E.RESET_STYLE);
    }
};

test {
    std.testing.refAllDecls(@This());
    _ = @import("frame/types.zig");
    _ = @import("frame/rect.zig");
    _ = @import("frame/buffer.zig");
    _ = @import("frame/layout.zig");
}
