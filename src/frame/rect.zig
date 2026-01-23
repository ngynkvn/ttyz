//! Rectangle geometry for terminal coordinates.


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

    /// Create a rect at a position with given dimensions.
    pub fn new(x: u16, y: u16, width: u16, height: u16) Rect {
        return .{ .x = x, .y = y, .width = width, .height = height };
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

    /// Get the area (width * height).
    pub fn area(self: Rect) u32 {
        return @as(u32, self.width) * @as(u32, self.height);
    }

    /// Check if the rectangle is empty (zero area).
    pub fn isEmpty(self: Rect) bool {
        return self.width == 0 or self.height == 0;
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
    const inr = rect.inner(5);
    try std.testing.expectEqual(@as(u16, 15), inr.x);
    try std.testing.expectEqual(@as(u16, 25), inr.y);
    try std.testing.expectEqual(@as(u16, 20), inr.width);
    try std.testing.expectEqual(@as(u16, 30), inr.height);
}

test "Rect.isEmpty" {
    try std.testing.expect(Rect.sized(0, 10).isEmpty());
    try std.testing.expect(Rect.sized(10, 0).isEmpty());
    try std.testing.expect(!Rect.sized(10, 10).isEmpty());
}

const std = @import("std");
