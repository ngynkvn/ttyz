//! Color representation for terminal cells.

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

    // Bright variants
    pub const bright_black = Color{ .indexed = 8 };
    pub const bright_red = Color{ .indexed = 9 };
    pub const bright_green = Color{ .indexed = 10 };
    pub const bright_yellow = Color{ .indexed = 11 };
    pub const bright_blue = Color{ .indexed = 12 };
    pub const bright_magenta = Color{ .indexed = 13 };
    pub const bright_cyan = Color{ .indexed = 14 };
    pub const bright_white = Color{ .indexed = 15 };

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

    /// Create an RGB color.
    pub fn fromRgb(r: u8, g: u8, b: u8) Color {
        return .{ .rgb = .{ .r = r, .g = g, .b = b } };
    }
};

const std = @import("std");

test "Color.eql" {
    try std.testing.expect(Color.red.eql(Color{ .indexed = 1 }));
    try std.testing.expect(!Color.red.eql(Color.blue));

    const rgb1 = Color{ .rgb = .{ .r = 255, .g = 0, .b = 0 } };
    const rgb2 = Color{ .rgb = .{ .r = 255, .g = 0, .b = 0 } };
    try std.testing.expect(rgb1.eql(rgb2));
}

test "Color.fromRgb" {
    const c = Color.fromRgb(128, 64, 32);
    try std.testing.expectEqual(@as(u8, 128), c.rgb.r);
    try std.testing.expectEqual(@as(u8, 64), c.rgb.g);
    try std.testing.expectEqual(@as(u8, 32), c.rgb.b);
}
