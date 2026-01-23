//! Frame - A Ratatui-inspired cell-based buffer for terminal rendering.
//!
//! Provides a double-buffered approach to terminal UI where you draw to a
//! Buffer, then render the entire frame to the screen at once.
//!
//! ## Example
//! ```zig
//! var buffer = try Buffer.init(allocator, screen.width, screen.height);
//! defer buffer.deinit();
//!
//! var frame = Frame.init(&buffer);
//! frame.clear();
//! frame.drawRect(Rect{ .x = 0, .y = 0, .width = 20, .height = 10 }, .single);
//! frame.setString(2, 2, "Hello!", .{ .bold = true }, .default, .default);
//!
//! try frame.render(&screen);
//! ```

const std = @import("std");
const ttyz = @import("ttyz.zig");
const Screen = ttyz.Screen;
const E = ttyz.E;

// Re-export submodules
pub const Style = @import("frame/style.zig").Style;
pub const Color = @import("frame/color.zig").Color;
pub const Cell = @import("frame/cell.zig").Cell;
pub const Rect = @import("frame/rect.zig").Rect;
pub const Buffer = @import("frame/buffer.zig").Buffer;
pub const BorderStyle = @import("frame/border.zig").BorderStyle;
pub const BorderChars = @import("frame/border.zig").BorderChars;

/// A drawing context wrapping a Buffer.
/// Provides high-level drawing primitives.
pub const Frame = struct {
    buffer: *Buffer,

    /// Initialize a Frame with a buffer.
    pub fn init(buffer: *Buffer) Frame {
        return .{ .buffer = buffer };
    }

    /// Get the drawable area.
    pub fn area(self: Frame) Rect {
        return self.buffer.area();
    }

    /// Set a cell at the given position.
    pub fn setCell(self: *Frame, x: u16, y: u16, cell: Cell) void {
        self.buffer.set(x, y, cell);
    }

    /// Draw a string at the given position with styling.
    pub fn setString(self: *Frame, x: u16, y: u16, text: []const u8, style: Style, fg: Color, bg: Color) void {
        var col = x;
        var iter = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
        while (iter.nextCodepoint()) |codepoint| {
            if (col >= self.buffer.width) break;
            self.buffer.set(col, y, .{
                .char = codepoint,
                .fg = fg,
                .bg = bg,
                .style = style,
            });
            col += 1;
        }
    }

    /// Fill a rectangle with a cell.
    pub fn fillRect(self: *Frame, rect: Rect, cell: Cell) void {
        const buf_area = self.buffer.area();
        const clipped = buf_area.intersect(rect) orelse return;

        var y = clipped.y;
        while (y < clipped.bottom()) : (y += 1) {
            var px = clipped.x;
            while (px < clipped.right()) : (px += 1) {
                self.buffer.set(px, y, cell);
            }
        }
    }

    /// Draw a rectangle border.
    pub fn drawRect(self: *Frame, rect: Rect, border_style: BorderStyle) void {
        self.drawRectStyled(rect, border_style, .{}, .default, .default);
    }

    /// Draw a rectangle border with custom styling.
    pub fn drawRectStyled(self: *Frame, rect: Rect, border_style: BorderStyle, style: Style, fg: Color, bg: Color) void {
        if (rect.width < 2 or rect.height < 2) return;

        const chars = border_style.chars();
        const x1 = rect.x;
        const y1 = rect.y;
        const x2 = rect.x + rect.width - 1;
        const y2 = rect.y + rect.height - 1;

        // Corners
        self.buffer.set(x1, y1, .{ .char = chars.top_left, .fg = fg, .bg = bg, .style = style });
        self.buffer.set(x2, y1, .{ .char = chars.top_right, .fg = fg, .bg = bg, .style = style });
        self.buffer.set(x1, y2, .{ .char = chars.bottom_left, .fg = fg, .bg = bg, .style = style });
        self.buffer.set(x2, y2, .{ .char = chars.bottom_right, .fg = fg, .bg = bg, .style = style });

        // Horizontal lines
        var x = x1 + 1;
        while (x < x2) : (x += 1) {
            self.buffer.set(x, y1, .{ .char = chars.horizontal, .fg = fg, .bg = bg, .style = style });
            self.buffer.set(x, y2, .{ .char = chars.horizontal, .fg = fg, .bg = bg, .style = style });
        }

        // Vertical lines
        var y = y1 + 1;
        while (y < y2) : (y += 1) {
            self.buffer.set(x1, y, .{ .char = chars.vertical, .fg = fg, .bg = bg, .style = style });
            self.buffer.set(x2, y, .{ .char = chars.vertical, .fg = fg, .bg = bg, .style = style });
        }
    }

    /// Clear the entire buffer.
    pub fn clear(self: *Frame) void {
        self.buffer.clear();
    }

    /// Render the buffer to a Screen.
    /// Iterates row-by-row, minimizing escape sequences by tracking state changes.
    pub fn render(self: Frame, screen: *Screen) !void {
        var current_style: Style = .{};
        var current_fg: Color = .default;
        var current_bg: Color = .default;

        // Reset styles at start
        try screen.writeAll(E.RESET_STYLE);

        var utf8_buf: [4]u8 = undefined;

        var y: u16 = 0;
        while (y < self.buffer.height) : (y += 1) {
            // Move cursor to start of row (1-based coordinates)
            try screen.print(E.GOTO, .{ y + 1, @as(u16, 1) });

            var x: u16 = 0;
            while (x < self.buffer.width) : (x += 1) {
                const cell = self.buffer.get(x, y);

                // Check if we need to change styles
                if (!cell.style.eql(current_style) or !cell.fg.eql(current_fg) or !cell.bg.eql(current_bg)) {
                    // Reset and apply new styles
                    try screen.writeAll(E.RESET_STYLE);
                    current_style = .{};
                    current_fg = .default;
                    current_bg = .default;

                    // Apply style attributes
                    if (cell.style.bold) try screen.writeAll(E.BOLD);
                    if (cell.style.dim) try screen.writeAll(E.DIM);
                    if (cell.style.italic) try screen.writeAll(E.ITALIC);
                    if (cell.style.underline) try screen.writeAll(E.UNDERLINE);
                    if (cell.style.blink) try screen.writeAll(E.BLINK);
                    if (cell.style.reverse) try screen.writeAll(E.REVERSE);
                    if (cell.style.strikethrough) try screen.writeAll(E.STRIKETHROUGH);

                    // Apply foreground color
                    switch (cell.fg) {
                        .default => {},
                        .indexed => |i| try screen.print(E.SET_FG_256, .{i}),
                        .rgb => |c| try screen.print(E.SET_TRUCOLOR, .{ c.r, c.g, c.b }),
                    }

                    // Apply background color
                    switch (cell.bg) {
                        .default => {},
                        .indexed => |i| try screen.print(E.SET_BG_256, .{i}),
                        .rgb => |c| try screen.print(E.SET_TRUCOLOR_BG, .{ c.r, c.g, c.b }),
                    }

                    current_style = cell.style;
                    current_fg = cell.fg;
                    current_bg = cell.bg;
                }

                // Write the character
                const len = std.unicode.utf8Encode(cell.char, &utf8_buf) catch 1;
                _ = try screen.write(utf8_buf[0..len]);
            }
        }

        // Reset styles at end
        try screen.writeAll(E.RESET_STYLE);
    }
};

test {
    std.testing.refAllDecls(@This());
    _ = @import("frame/style.zig");
    _ = @import("frame/color.zig");
    _ = @import("frame/cell.zig");
    _ = @import("frame/rect.zig");
    _ = @import("frame/buffer.zig");
    _ = @import("frame/border.zig");
}
