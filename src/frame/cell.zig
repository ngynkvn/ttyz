//! Terminal cell - the basic unit of the frame buffer.

const Style = @import("style.zig").Style;
const Color = @import("color.zig").Color;

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

    /// Create a cell with just a character.
    pub fn fromChar(c: u21) Cell {
        return .{ .char = c };
    }

    /// Create a styled cell.
    pub fn styled(c: u21, style: Style, fg: Color, bg: Color) Cell {
        return .{ .char = c, .style = style, .fg = fg, .bg = bg };
    }
};

const std = @import("std");

test "Cell.eql" {
    const c1 = Cell{ .char = 'A', .fg = Color.red };
    const c2 = Cell{ .char = 'A', .fg = Color.red };
    const c3 = Cell{ .char = 'B', .fg = Color.red };
    try std.testing.expect(c1.eql(c2));
    try std.testing.expect(!c1.eql(c3));
}

test "Cell.styled" {
    const c = Cell.styled('X', .{ .bold = true }, Color.green, Color.black);
    try std.testing.expectEqual(@as(u21, 'X'), c.char);
    try std.testing.expect(c.style.bold);
    try std.testing.expect(c.fg.eql(Color.green));
}
