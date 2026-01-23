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
const Allocator = std.mem.Allocator;
const ttyz = @import("ttyz.zig");
const Screen = ttyz.Screen;
const E = ttyz.E;

/// Text styling attributes.
/// Packed to minimize memory usage in Cell structures.
pub const Style = packed struct {
    bold: bool = false,
    dim: bool = false,
    italic: bool = false,
    underline: bool = false,
    blink: bool = false,
    reverse: bool = false,
    strikethrough: bool = false,
    _padding: u1 = 0,

    /// Check if this style has any attributes set.
    pub fn hasAttributes(self: Style) bool {
        return self.bold or self.dim or self.italic or self.underline or
            self.blink or self.reverse or self.strikethrough;
    }

    /// Check if two styles are equal.
    pub fn eql(self: Style, other: Style) bool {
        return @as(u8, @bitCast(self)) == @as(u8, @bitCast(other));
    }
};

/// Color representation for terminal cells.
pub const Color = union(enum) {
    /// Terminal default color.
    default,
    /// 256-color palette index (0-255).
    indexed: u8,
    /// True color RGB.
    rgb: struct { r: u8, g: u8, b: u8 },

    /// Common colors for convenience.
    pub const black = Color{ .indexed = 0 };
    pub const red = Color{ .indexed = 1 };
    pub const green = Color{ .indexed = 2 };
    pub const yellow = Color{ .indexed = 3 };
    pub const blue = Color{ .indexed = 4 };
    pub const magenta = Color{ .indexed = 5 };
    pub const cyan = Color{ .indexed = 6 };
    pub const white = Color{ .indexed = 7 };

    /// Check if two colors are equal.
    pub fn eql(self: Color, other: Color) bool {
        return switch (self) {
            .default => other == .default,
            .indexed => |i| switch (other) {
                .indexed => |j| i == j,
                else => false,
            },
            .rgb => |c| switch (other) {
                .rgb => |d| c.r == d.r and c.g == d.g and c.b == d.b,
                else => false,
            },
        };
    }
};

/// A single terminal cell containing a character and its styling.
pub const Cell = struct {
    /// Unicode codepoint (21-bit for full Unicode range).
    char: u21 = ' ',
    /// Foreground color.
    fg: Color = .default,
    /// Background color.
    bg: Color = .default,
    /// Text style attributes.
    style: Style = .{},

    /// Check if two cells are equal.
    pub fn eql(self: Cell, other: Cell) bool {
        return self.char == other.char and
            self.fg.eql(other.fg) and
            self.bg.eql(other.bg) and
            self.style.eql(other.style);
    }
};

/// A rectangle area in the terminal.
pub const Rect = struct {
    x: u16,
    y: u16,
    width: u16,
    height: u16,

    /// Create a rect at origin with given dimensions.
    pub fn sized(width: u16, height: u16) Rect {
        return .{ .x = 0, .y = 0, .width = width, .height = height };
    }

    /// Check if a point is within this rectangle.
    pub fn contains(self: Rect, x: u16, y: u16) bool {
        return x >= self.x and x < self.x + self.width and
            y >= self.y and y < self.y + self.height;
    }

    /// Get the intersection of two rectangles.
    /// Returns null if they don't overlap.
    pub fn intersect(self: Rect, other: Rect) ?Rect {
        const x1 = @max(self.x, other.x);
        const y1 = @max(self.y, other.y);
        const x2 = @min(self.x + self.width, other.x + other.width);
        const y2 = @min(self.y + self.height, other.y + other.height);

        if (x1 >= x2 or y1 >= y2) return null;

        return .{
            .x = x1,
            .y = y1,
            .width = x2 - x1,
            .height = y2 - y1,
        };
    }

    /// Shrink the rectangle by a margin on all sides.
    pub fn inner(self: Rect, margin: u16) Rect {
        const double_margin = margin * 2;
        if (self.width <= double_margin or self.height <= double_margin) {
            return .{ .x = self.x, .y = self.y, .width = 0, .height = 0 };
        }
        return .{
            .x = self.x + margin,
            .y = self.y + margin,
            .width = self.width - double_margin,
            .height = self.height - double_margin,
        };
    }

    /// Get the right edge x coordinate (exclusive).
    pub fn right(self: Rect) u16 {
        return self.x + self.width;
    }

    /// Get the bottom edge y coordinate (exclusive).
    pub fn bottom(self: Rect) u16 {
        return self.y + self.height;
    }
};

/// A 2D grid of cells representing the terminal buffer.
pub const Buffer = struct {
    cells: []Cell,
    width: u16,
    height: u16,
    allocator: Allocator,

    /// Initialize a new buffer with the given dimensions.
    pub fn init(allocator: Allocator, width: u16, height: u16) !Buffer {
        const size = @as(usize, width) * @as(usize, height);
        const cells = try allocator.alloc(Cell, size);
        @memset(cells, Cell{});
        return .{
            .cells = cells,
            .width = width,
            .height = height,
            .allocator = allocator,
        };
    }

    /// Free the buffer's memory.
    pub fn deinit(self: *Buffer) void {
        self.allocator.free(self.cells);
    }

    /// Resize the buffer to new dimensions.
    /// Existing content is discarded.
    pub fn resize(self: *Buffer, width: u16, height: u16) !void {
        const size = @as(usize, width) * @as(usize, height);
        self.allocator.free(self.cells);
        self.cells = try self.allocator.alloc(Cell, size);
        @memset(self.cells, Cell{});
        self.width = width;
        self.height = height;
    }

    /// Clear the buffer to default cells.
    pub fn clear(self: *Buffer) void {
        @memset(self.cells, Cell{});
    }

    /// Get the index for a given position.
    fn index(self: *const Buffer, x: u16, y: u16) ?usize {
        if (x >= self.width or y >= self.height) return null;
        return @as(usize, y) * @as(usize, self.width) + @as(usize, x);
    }

    /// Get the cell at the given position.
    pub fn get(self: *const Buffer, x: u16, y: u16) Cell {
        const idx = self.index(x, y) orelse return Cell{};
        return self.cells[idx];
    }

    /// Set the cell at the given position.
    pub fn set(self: *Buffer, x: u16, y: u16, cell: Cell) void {
        const idx = self.index(x, y) orelse return;
        self.cells[idx] = cell;
    }

    /// Set just the character at the given position.
    pub fn setChar(self: *Buffer, x: u16, y: u16, char: u21) void {
        const idx = self.index(x, y) orelse return;
        self.cells[idx].char = char;
    }

    /// Get the entire buffer area as a Rect.
    pub fn area(self: *const Buffer) Rect {
        return .{ .x = 0, .y = 0, .width = self.width, .height = self.height };
    }
};

/// Border styles for drawing rectangles.
pub const BorderStyle = enum {
    single,
    double,
    rounded,
    thick,
    none,

    /// Get the box-drawing characters for this border style.
    pub fn chars(self: BorderStyle) BorderChars {
        return switch (self) {
            .single => .{
                .top_left = '┌',
                .top_right = '┐',
                .bottom_left = '└',
                .bottom_right = '┘',
                .horizontal = '─',
                .vertical = '│',
            },
            .double => .{
                .top_left = '╔',
                .top_right = '╗',
                .bottom_left = '╚',
                .bottom_right = '╝',
                .horizontal = '═',
                .vertical = '║',
            },
            .rounded => .{
                .top_left = '╭',
                .top_right = '╮',
                .bottom_left = '╰',
                .bottom_right = '╯',
                .horizontal = '─',
                .vertical = '│',
            },
            .thick => .{
                .top_left = '┏',
                .top_right = '┓',
                .bottom_left = '┗',
                .bottom_right = '┛',
                .horizontal = '━',
                .vertical = '┃',
            },
            .none => .{
                .top_left = ' ',
                .top_right = ' ',
                .bottom_left = ' ',
                .bottom_right = ' ',
                .horizontal = ' ',
                .vertical = ' ',
            },
        };
    }
};

/// Characters used for drawing borders.
pub const BorderChars = struct {
    top_left: u21,
    top_right: u21,
    bottom_left: u21,
    bottom_right: u21,
    horizontal: u21,
    vertical: u21,
};

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

test "Rect.contains" {
    const rect = Rect{ .x = 10, .y = 20, .width = 30, .height = 40 };
    try std.testing.expect(rect.contains(10, 20));
    try std.testing.expect(rect.contains(39, 59));
    try std.testing.expect(!rect.contains(9, 20));
    try std.testing.expect(!rect.contains(40, 20));
}

test "Rect.intersect" {
    const r1 = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    const r2 = Rect{ .x = 5, .y = 5, .width = 10, .height = 10 };
    const intersection = r1.intersect(r2).?;
    try std.testing.expectEqual(@as(u16, 5), intersection.x);
    try std.testing.expectEqual(@as(u16, 5), intersection.y);
    try std.testing.expectEqual(@as(u16, 5), intersection.width);
    try std.testing.expectEqual(@as(u16, 5), intersection.height);
}

test "Rect.inner" {
    const rect = Rect{ .x = 10, .y = 20, .width = 30, .height = 40 };
    const inner = rect.inner(5);
    try std.testing.expectEqual(@as(u16, 15), inner.x);
    try std.testing.expectEqual(@as(u16, 25), inner.y);
    try std.testing.expectEqual(@as(u16, 20), inner.width);
    try std.testing.expectEqual(@as(u16, 30), inner.height);
}

test "Buffer basic operations" {
    var buffer = try Buffer.init(std.testing.allocator, 10, 5);
    defer buffer.deinit();

    buffer.set(3, 2, .{ .char = 'X' });
    const cell = buffer.get(3, 2);
    try std.testing.expectEqual(@as(u21, 'X'), cell.char);
}

test "Style.eql" {
    const s1 = Style{ .bold = true, .italic = true };
    const s2 = Style{ .bold = true, .italic = true };
    const s3 = Style{ .bold = true };
    try std.testing.expect(s1.eql(s2));
    try std.testing.expect(!s1.eql(s3));
}

test "Color.eql" {
    try std.testing.expect(Color.red.eql(Color{ .indexed = 1 }));
    try std.testing.expect(!Color.red.eql(Color.blue));

    const rgb1 = Color{ .rgb = .{ .r = 255, .g = 0, .b = 0 } };
    const rgb2 = Color{ .rgb = .{ .r = 255, .g = 0, .b = 0 } };
    try std.testing.expect(rgb1.eql(rgb2));
}
