//! Border styles and characters for drawing rectangles.

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

const std = @import("std");

test "BorderStyle.chars" {
    const single = BorderStyle.single.chars();
    try std.testing.expectEqual(@as(u21, '┌'), single.top_left);
    try std.testing.expectEqual(@as(u21, '─'), single.horizontal);

    const double = BorderStyle.double.chars();
    try std.testing.expectEqual(@as(u21, '╔'), double.top_left);
    try std.testing.expectEqual(@as(u21, '═'), double.horizontal);
}
