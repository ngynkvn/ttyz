//! Frame - Cell-based buffer for terminal rendering.

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

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

// Re-export types
// Layout types
/// Drawing context wrapping a Buffer.
///
/// Frame provides immediate-mode drawing methods for terminal UIs.
/// It wraps a Buffer and provides methods for setting cells, drawing
/// text, rectangles, and lines with colors and styles.
///
/// ## Example
/// ```zig
/// var frame = Frame.init(&buffer);
/// frame.clear();
/// frame.setString(0, 0, "Hello", .{ .bold = true }, .green, .default);
/// frame.drawRect(Rect{ .x = 0, .y = 0, .width = 20, .height = 10 }, .single);
/// try frame.render(&screen);
/// ```
pub const Frame = struct {
    /// The underlying buffer that stores cell data.
    buffer: *Buffer,

    /// Create a Frame from a Buffer.
    pub fn init(buffer: *Buffer) Frame {
        return .{ .buffer = buffer };
    }

    /// Get the rectangular area of the frame.
    /// Returns a Rect covering the entire buffer dimensions.
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

    /// Set a single cell at the given coordinates.
    /// Out-of-bounds coordinates are silently ignored.
    pub fn setCell(self: *Frame, x: u16, y: u16, cell: Cell) void {
        self.buffer.set(x, y, cell);
    }

    /// Draw a string at the given position with style and colors.
    /// The string is drawn left-to-right, one codepoint per cell.
    /// Text that extends beyond the buffer width is clipped.
    pub fn setString(self: *Frame, x: u16, y: u16, text: []const u8, style: Style, fg: Color, bg: Color) void {
        var col = x;
        var iter = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
        while (iter.nextCodepoint()) |codepoint| {
            if (col >= self.buffer.width) break;
            self.buffer.set(col, y, .{ .char = codepoint, .fg = fg, .bg = bg, .style = style });
            col += 1;
        }
    }

    /// Fill a rectangular region with a single cell.
    /// The rectangle is clipped to the buffer bounds.
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

    /// Draw a rectangle border with the specified border style.
    /// Uses default style and colors. For styled borders, use `drawRectStyled`.
    pub fn drawRect(self: *Frame, rect: Rect, border_style: BorderStyle) void {
        self.drawRectStyled(rect, border_style, .{}, .default, .default);
    }

    /// Draw a styled rectangle border with custom style and colors.
    /// The rectangle must have width >= 2 and height >= 2.
    /// Border styles include `.single`, `.double`, `.rounded`, `.heavy`, `.none`.
    pub fn drawRectStyled(self: *Frame, rect: Rect, border_style: BorderStyle, style: Style, fg: Color, bg: Color) void {
        if (rect.width < 2 or rect.height < 2) return;
        const chars = border_style.chars();
        const x1, const y1 = .{ rect.x, rect.y };
        // Invariant: width >= 2 and height >= 2, so subtraction is safe
        assert(rect.width >= 2 and rect.height >= 2);
        const x2, const y2 = .{ rect.x +| (rect.width - 1), rect.y +| (rect.height - 1) };

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

    /// Clear all cells in the buffer to default (space character, default colors).
    pub fn clear(self: *Frame) void {
        self.buffer.clear();
    }

    /// Render the frame to a Screen.
    /// Outputs ANSI escape sequences for cursor positioning, colors, and styles,
    /// followed by the cell characters. Call `screen.flush()` after to display.
    pub fn render(self: Frame, screen: *Screen) !void {
        var current_style: Style = .{};
        var current_fg: Color = .default;
        var current_bg: Color = .default;
        try screen.writeAll(ansi.reset);

        var utf8_buf: [4]u8 = undefined;
        var y: u16 = 0;
        while (y < self.buffer.height) : (y += 1) {
            try screen.print(ansi.goto_fmt, .{ y + 1, @as(u16, 1) });
            var x: u16 = 0;
            while (x < self.buffer.width) : (x += 1) {
                const cell = self.buffer.get(x, y);
                if (!cell.style.eql(current_style) or !cell.fg.eql(current_fg) or !cell.bg.eql(current_bg)) {
                    try screen.writeAll(ansi.reset);
                    current_style = .{};
                    current_fg = .default;
                    current_bg = .default;

                    if (cell.style.bold) try screen.writeAll(ansi.bold);
                    if (cell.style.dim) try screen.writeAll(ansi.faint);
                    if (cell.style.italic) try screen.writeAll(ansi.italic);
                    if (cell.style.underline) try screen.writeAll(ansi.underline);
                    if (cell.style.blink) try screen.writeAll(ansi.slow_blink);
                    if (cell.style.reverse) try screen.writeAll(ansi.reverse);
                    if (cell.style.strikethrough) try screen.writeAll(ansi.crossed_out);

                    switch (cell.fg) {
                        .default => {},
                        .indexed => |i| try screen.print(ansi.fg_256_fmt, .{i}),
                        .rgb => |c| try screen.print(ansi.fg_rgb_fmt, .{ c.r, c.g, c.b }),
                    }
                    switch (cell.bg) {
                        .default => {},
                        .indexed => |i| try screen.print(ansi.bg_256_fmt, .{i}),
                        .rgb => |c| try screen.print(ansi.bg_rgb_fmt, .{ c.r, c.g, c.b }),
                    }
                    current_style = cell.style;
                    current_fg = cell.fg;
                    current_bg = cell.bg;
                }
                const len = std.unicode.utf8Encode(cell.char, &utf8_buf) catch 1;
                _ = try screen.write(utf8_buf[0..len]);
            }
        }
        try screen.writeAll(ansi.reset);
    }
};

test {
    _ = @import("frame/types.zig");
    _ = @import("frame/rect.zig");
    _ = @import("frame/buffer.zig");
    _ = @import("frame/layout.zig");
    std.testing.refAllDecls(@This());
}
