//! Layout system for splitting areas into sub-rectangles.
//!
//! Inspired by Ratatui's layout system:
//! https://docs.rs/ratatui/latest/ratatui/layout/struct.Layout.html

const assert = std.debug.assert;



/// Direction of layout splitting.
pub const Direction = enum {
    horizontal,
    vertical,
};

/// Constraint for determining area size.
pub const Constraint = union(enum) {
    /// Fixed size in cells.
    length: u16,
    /// Percentage of available space (0-100).
    percentage: u16,
    /// Minimum size in cells.
    min: u16,
    /// Maximum size in cells.
    max: u16,
    /// Fill remaining space with given weight.
    fill: u16,
    /// Ratio of available space (numerator, denominator).
    /// Invariant: denominator must be non-zero.
    ratio: struct { num: u16, den: u16 },

    /// Validate constraint invariants.
    pub fn validate(self: Constraint) void {
        switch (self) {
            .ratio => |r| assert(r.den != 0), // Division by zero would occur
            .percentage => |p| assert(p <= 100), // Percentage should be 0-100
            else => {},
        }
    }

    /// Create a length constraint.
    pub fn len(n: u16) Constraint {
        return .{ .length = n };
    }

    /// Create a percentage constraint.
    pub fn pct(p: u16) Constraint {
        return .{ .percentage = p };
    }

    /// Create a fill constraint with weight 1.
    pub fn fill1() Constraint {
        return .{ .fill = 1 };
    }
};

/// Layout for splitting rectangles into sub-areas.
pub fn Layout(comptime N: usize) type {
    return struct {
        const Self = @This();

        direction: Direction,
        constraints: [N]Constraint,
        spacing: u16 = 0,

        /// Create a vertical layout with given constraints.
        pub fn vertical(constraints: [N]Constraint) Self {
            return .{ .direction = .vertical, .constraints = constraints };
        }

        /// Create a horizontal layout with given constraints.
        pub fn horizontal(constraints: [N]Constraint) Self {
            return .{ .direction = .horizontal, .constraints = constraints };
        }

        /// Set spacing between areas.
        pub fn withSpacing(self: Self, spacing: u16) Self {
            var result = self;
            result.spacing = spacing;
            return result;
        }

        /// Split a rectangle into N areas based on constraints.
        pub fn areas(self: Self, rect: Rect) [N]Rect {
            comptime assert(N > 0); // Layout must have at least one area

            // Validate all constraints at runtime in debug builds
            for (self.constraints) |constraint| {
                constraint.validate();
            }

            const total_spacing: u16 = if (N > 1) self.spacing *| @as(u16, N - 1) else 0;
            const available: u16 = switch (self.direction) {
                .horizontal => rect.width -| total_spacing,
                .vertical => rect.height -| total_spacing,
            };

            // Calculate sizes
            var sizes: [N]u16 = undefined;
            var remaining: u32 = @intCast(available);
            var fill_total: u32 = 0;

            // First pass: fixed sizes and fill weights
            for (self.constraints, 0..) |constraint, i| {
                sizes[i] = switch (constraint) {
                    .length => |n| n,
                    .percentage => |p| @intCast(@min(available, @as(u32, available) * p / 100)),
                    .min => |n| n,
                    .max => 0, // Will be filled later
                    .fill => 0, // Will be filled later
                    .ratio => |r| @intCast(@min(available, @as(u32, available) * r.num / r.den)),
                };
                switch (constraint) {
                    .fill => |w| fill_total += w,
                    .max => fill_total += 1,
                    else => remaining -|= sizes[i],
                }
            }

            // Second pass: distribute remaining space to fill/max constraints
            if (fill_total > 0) {
                // fill_total is guaranteed > 0 here, so division is safe
                for (self.constraints, 0..) |constraint, i| {
                    switch (constraint) {
                        .fill => |w| {
                            assert(fill_total > 0); // Invariant: division by zero check
                            sizes[i] = @intCast(remaining * w / fill_total);
                        },
                        .max => |n| {
                            assert(fill_total > 0); // Invariant: division by zero check
                            const share: u16 = @intCast(remaining / fill_total);
                            sizes[i] = @min(share, n);
                        },
                        else => {},
                    }
                }
            }

            // Build result rectangles
            var result: [N]Rect = undefined;
            var pos: u16 = switch (self.direction) {
                .horizontal => rect.x,
                .vertical => rect.y,
            };

            for (0..N) |i| {
                result[i] = switch (self.direction) {
                    .horizontal => .{
                        .x = pos,
                        .y = rect.y,
                        .width = sizes[i],
                        .height = rect.height,
                    },
                    .vertical => .{
                        .x = rect.x,
                        .y = pos,
                        .width = rect.width,
                        .height = sizes[i],
                    },
                };
                pos += sizes[i] + self.spacing;
            }

            return result;
        }
    };
}

/// Create a vertical layout (shorthand).
pub fn vertical(comptime N: usize, constraints: [N]Constraint) Layout(N) {
    return Layout(N).vertical(constraints);
}

/// Create a horizontal layout (shorthand).
pub fn horizontal(comptime N: usize, constraints: [N]Constraint) Layout(N) {
    return Layout(N).horizontal(constraints);
}

// Tests
test "vertical layout with lengths" {
    const layout = vertical(3, .{
        .{ .length = 3 },
        .{ .length = 10 },
        .{ .length = 3 },
    });
    const rect = Rect.sized(80, 24);
    const a, const b, const c = layout.areas(rect);

    try std.testing.expectEqual(@as(u16, 0), a.y);
    try std.testing.expectEqual(@as(u16, 3), a.height);
    try std.testing.expectEqual(@as(u16, 3), b.y);
    try std.testing.expectEqual(@as(u16, 10), b.height);
    try std.testing.expectEqual(@as(u16, 13), c.y);
    try std.testing.expectEqual(@as(u16, 3), c.height);
}

test "horizontal layout with fill" {
    const layout = horizontal(2, .{
        .{ .length = 20 },
        .{ .fill = 1 },
    });
    const rect = Rect.sized(80, 24);
    const result = layout.areas(rect);

    try std.testing.expectEqual(@as(u16, 0), result[0].x);
    try std.testing.expectEqual(@as(u16, 20), result[0].width);
    try std.testing.expectEqual(@as(u16, 20), result[1].x);
    try std.testing.expectEqual(@as(u16, 60), result[1].width);
}

test "layout with percentage" {
    const layout = vertical(2, .{
        .{ .percentage = 25 },
        .{ .percentage = 75 },
    });
    const rect = Rect.sized(80, 100);
    const result = layout.areas(rect);

    try std.testing.expectEqual(@as(u16, 25), result[0].height);
    try std.testing.expectEqual(@as(u16, 75), result[1].height);
}

test "layout with spacing" {
    const layout = vertical(2, .{
        .{ .length = 10 },
        .{ .length = 10 },
    }).withSpacing(2);
    const rect = Rect.sized(80, 24);
    const result = layout.areas(rect);

    try std.testing.expectEqual(@as(u16, 0), result[0].y);
    try std.testing.expectEqual(@as(u16, 10), result[0].height);
    try std.testing.expectEqual(@as(u16, 12), result[1].y); // 10 + 2 spacing
    try std.testing.expectEqual(@as(u16, 10), result[1].height);
}

test "layout with ratio" {
    const layout = horizontal(3, .{
        .{ .ratio = .{ .num = 1, .den = 4 } },
        .{ .ratio = .{ .num = 1, .den = 2 } },
        .{ .ratio = .{ .num = 1, .den = 4 } },
    });
    const rect = Rect.sized(100, 24);
    const result = layout.areas(rect);

    try std.testing.expectEqual(@as(u16, 25), result[0].width);
    try std.testing.expectEqual(@as(u16, 50), result[1].width);
    try std.testing.expectEqual(@as(u16, 25), result[2].width);
}

const std = @import("std");
const Rect = @import("rect.zig").Rect;
