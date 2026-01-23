//! Text styling attributes for terminal cells.

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

const std = @import("std");

test "Style.eql" {
    const s1 = Style{ .bold = true, .italic = true };
    const s2 = Style{ .bold = true, .italic = true };
    const s3 = Style{ .bold = true };
    try std.testing.expect(s1.eql(s2));
    try std.testing.expect(!s1.eql(s3));
}

test "Style.hasAttributes" {
    try std.testing.expect(!(Style{}).hasAttributes());
    try std.testing.expect((Style{ .bold = true }).hasAttributes());
    try std.testing.expect((Style{ .underline = true, .italic = true }).hasAttributes());
}
