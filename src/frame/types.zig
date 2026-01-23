//! Core types for the frame buffer system.


/// Text styling attributes (packed into 1 byte).
pub const Style = packed struct {
    bold: bool = false,
    dim: bool = false,
    italic: bool = false,
    underline: bool = false,
    blink: bool = false,
    reverse: bool = false,
    strikethrough: bool = false,
    _padding: u1 = 0,

    pub fn hasAttributes(self: Style) bool {
        return self.bold or self.dim or self.italic or self.underline or
            self.blink or self.reverse or self.strikethrough;
    }

    pub fn eql(self: Style, other: Style) bool {
        return @as(u8, @bitCast(self)) == @as(u8, @bitCast(other));
    }
};

/// Color representation for terminal cells.
pub const Color = union(enum) {
    default,
    indexed: u8,
    rgb: struct { r: u8, g: u8, b: u8 },

    // Standard colors
    pub const black = Color{ .indexed = 0 };
    pub const red = Color{ .indexed = 1 };
    pub const green = Color{ .indexed = 2 };
    pub const yellow = Color{ .indexed = 3 };
    pub const blue = Color{ .indexed = 4 };
    pub const magenta = Color{ .indexed = 5 };
    pub const cyan = Color{ .indexed = 6 };
    pub const white = Color{ .indexed = 7 };
    pub const bright_black = Color{ .indexed = 8 };
    pub const bright_red = Color{ .indexed = 9 };
    pub const bright_green = Color{ .indexed = 10 };
    pub const bright_yellow = Color{ .indexed = 11 };
    pub const bright_blue = Color{ .indexed = 12 };
    pub const bright_magenta = Color{ .indexed = 13 };
    pub const bright_cyan = Color{ .indexed = 14 };
    pub const bright_white = Color{ .indexed = 15 };

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

    pub fn fromRgb(r: u8, g: u8, b: u8) Color {
        return .{ .rgb = .{ .r = r, .g = g, .b = b } };
    }
};

/// A single terminal cell.
pub const Cell = struct {
    char: u21 = ' ',
    fg: Color = .default,
    bg: Color = .default,
    style: Style = .{},

    pub fn eql(self: Cell, other: Cell) bool {
        return self.char == other.char and
            self.fg.eql(other.fg) and
            self.bg.eql(other.bg) and
            self.style.eql(other.style);
    }

    pub fn fromChar(c: u21) Cell {
        return .{ .char = c };
    }

    pub fn styled(c: u21, style: Style, fg: Color, bg: Color) Cell {
        return .{ .char = c, .style = style, .fg = fg, .bg = bg };
    }
};

/// Border styles for drawing rectangles.
pub const BorderStyle = enum {
    single,
    double,
    rounded,
    thick,
    none,

    pub fn chars(self: BorderStyle) BorderChars {
        return switch (self) {
            .single => .{ .top_left = '┌', .top_right = '┐', .bottom_left = '└', .bottom_right = '┘', .horizontal = '─', .vertical = '│' },
            .double => .{ .top_left = '╔', .top_right = '╗', .bottom_left = '╚', .bottom_right = '╝', .horizontal = '═', .vertical = '║' },
            .rounded => .{ .top_left = '╭', .top_right = '╮', .bottom_left = '╰', .bottom_right = '╯', .horizontal = '─', .vertical = '│' },
            .thick => .{ .top_left = '┏', .top_right = '┓', .bottom_left = '┗', .bottom_right = '┛', .horizontal = '━', .vertical = '┃' },
            .none => .{ .top_left = ' ', .top_right = ' ', .bottom_left = ' ', .bottom_right = ' ', .horizontal = ' ', .vertical = ' ' },
        };
    }
};

pub const BorderChars = struct {
    top_left: u21,
    top_right: u21,
    bottom_left: u21,
    bottom_right: u21,
    horizontal: u21,
    vertical: u21,
};

// Tests
test "Style" {
    const s1 = Style{ .bold = true, .italic = true };
    const s2 = Style{ .bold = true, .italic = true };
    try std.testing.expect(s1.eql(s2));
    try std.testing.expect(!(Style{}).hasAttributes());
    try std.testing.expect((Style{ .bold = true }).hasAttributes());
}

test "Color" {
    try std.testing.expect(Color.red.eql(Color{ .indexed = 1 }));
    try std.testing.expect(!Color.red.eql(Color.blue));
    const rgb1 = Color.fromRgb(255, 0, 0);
    const rgb2 = Color{ .rgb = .{ .r = 255, .g = 0, .b = 0 } };
    try std.testing.expect(rgb1.eql(rgb2));
}

test "Cell" {
    const c1 = Cell{ .char = 'A', .fg = Color.red };
    const c2 = Cell{ .char = 'A', .fg = Color.red };
    try std.testing.expect(c1.eql(c2));
}

const std = @import("std");
