//! Text utilities for terminal output formatting.
//!
//! Provides common text operations like padding, centering, truncation,
//! and display width calculation for terminal output.
//!
//! ## Example
//! ```zig
//! var buf: [32]u8 = undefined;
//! const padded = text.padRight("Hi", 10, &buf);  // "Hi        "
//! const width = text.displayWidth("Hello");      // 5
//! ```

const std = @import("std");

/// Text utilities for terminal output.
pub const Text = @This();

/// Truncate text to fit within width, adding ellipsis if needed
pub fn truncate(allocator: std.mem.Allocator, text: []const u8, max_width: usize) ![]const u8 {
    if (text.len <= max_width) return text;
    if (max_width <= 3) return text[0..max_width];

    const result = try allocator.alloc(u8, max_width);
    @memcpy(result[0 .. max_width - 3], text[0 .. max_width - 3]);
    @memcpy(result[max_width - 3 ..], "...");
    return result;
}

/// Pad text on the right with spaces to reach width
pub fn padRight(text: []const u8, width: usize, buf: []u8) []const u8 {
    if (text.len >= width) return text[0..@min(text.len, buf.len)];
    const copy_len = @min(text.len, buf.len);
    @memcpy(buf[0..copy_len], text[0..copy_len]);
    const pad_len = @min(width - copy_len, buf.len - copy_len);
    @memset(buf[copy_len..][0..pad_len], ' ');
    return buf[0 .. copy_len + pad_len];
}

/// Pad text on the left with spaces to reach width
pub fn padLeft(text: []const u8, width: usize, buf: []u8) []const u8 {
    if (text.len >= width) return text[0..@min(text.len, buf.len)];
    const padding = width - text.len;
    const pad_len = @min(padding, buf.len);
    @memset(buf[0..pad_len], ' ');
    const copy_len = @min(text.len, buf.len - pad_len);
    @memcpy(buf[pad_len..][0..copy_len], text[0..copy_len]);
    return buf[0 .. pad_len + copy_len];
}

/// Calculate display width of a string (accounting for unicode)
/// For now, assumes ASCII (1 byte = 1 column)
pub fn displayWidth(text: []const u8) usize {
    var width: usize = 0;
    var i: usize = 0;
    while (i < text.len) {
        const byte = text[i];
        if (byte < 0x80) {
            // ASCII
            width += 1;
            i += 1;
        } else if (byte < 0xC0) {
            // Continuation byte, skip
            i += 1;
        } else if (byte < 0xE0) {
            // 2-byte sequence
            width += 1;
            i += 2;
        } else if (byte < 0xF0) {
            // 3-byte sequence (many CJK characters are 2 columns wide)
            width += 2;
            i += 3;
        } else {
            // 4-byte sequence
            width += 2;
            i += 4;
        }
    }
    return width;
}

/// Repeat a character n times into a buffer
pub fn repeat(char: u8, count: usize, buf: []u8) []const u8 {
    const len = @min(count, buf.len);
    @memset(buf[0..len], char);
    return buf[0..len];
}

/// Write a horizontal rule
pub fn writeHorizontalRule(writer: std.Io.Writer, width: usize, char: u8) !void {
    var i: usize = 0;
    while (i < width) : (i += 1) {
        try writer.writeByte(char);
    }
}

test "displayWidth" {
    try std.testing.expectEqual(@as(usize, 5), displayWidth("hello"));
    try std.testing.expectEqual(@as(usize, 0), displayWidth(""));
}

test "repeat" {
    var buf: [10]u8 = undefined;
    const result = repeat('-', 5, &buf);
    try std.testing.expectEqualStrings("-----", result);
}
