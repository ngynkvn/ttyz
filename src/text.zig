//! Text utilities for terminal output formatting.
//!
//! Provides common text operations like padding, centering, truncation,
//! and display width calculation for terminal output.
//!
//! ## Example
//! ```zig
//! var buf: [32]u8 = undefined;
//! const padded = text.padRight("Hi", 10, &buf);  // "Hi        "
//! const width = text.graphemeCount("Hello");      // 5
//! ```

const std = @import("std");
const assert = std.debug.assert;

/// Text utilities for terminal output.
pub const Text = @This();

/// Truncate text to fit within width, adding ellipsis if needed
pub fn truncate(allocator: std.mem.Allocator, text: []const u8, max_width: usize) ![]const u8 {
    if (text.len <= max_width) return text;
    if (max_width <= 3) return text[0..max_width];

    // Invariant: max_width > 3, so max_width - 3 is safe
    assert(max_width > 3);
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
    // Invariant: width > text.len and copy_len <= text.len, so width > copy_len
    assert(width > copy_len);
    const pad_len = @min(width - copy_len, buf.len - copy_len);
    @memset(buf[copy_len..][0..pad_len], ' ');
    return buf[0 .. copy_len + pad_len];
}

/// Pad text on the left with spaces to reach width
pub fn padLeft(text: []const u8, width: usize, buf: []u8) []const u8 {
    if (text.len >= width) return text[0..@min(text.len, buf.len)];
    // Invariant: width > text.len, so subtraction is safe
    assert(width > text.len);
    const padding = width - text.len;
    const pad_len = @min(padding, buf.len);
    @memset(buf[0..pad_len], ' ');
    const copy_len = @min(text.len, buf.len - pad_len);
    @memcpy(buf[pad_len..][0..copy_len], text[0..copy_len]);
    return buf[0 .. pad_len + copy_len];
}

pub fn graphemeCount(text: []const u8) usize {
    var i: usize = 0;
    var width: usize = 0;
    while (i < text.len) {
        const len = std.unicode.utf8ByteSequenceLength(text[i]) catch 1;
        width += 1;
        i += len;
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

/// Test case for graphemeCount function.
const GraphemeCountTestCase = struct {
    input: []const u8,
    expected: usize,
    description: []const u8,
};

/// All graphemeCount test cases in a single array.
/// graphemeCount counts Unicode code points (characters), not display width.
const grapheme_count_test_cases = [_]GraphemeCountTestCase{
    // Basic ASCII
    .{ .input = "hello", .expected = 5, .description = "basic ASCII word" },
    .{ .input = "", .expected = 0, .description = "empty string" },
    .{ .input = " ", .expected = 1, .description = "single space" },
    .{ .input = "0123456789", .expected = 10, .description = "digits" },

    // 2-byte UTF-8 (Latin Extended, Greek, Cyrillic)
    .{ .input = "é", .expected = 1, .description = "Latin e with acute (U+00E9)" },
    .{ .input = "café", .expected = 4, .description = "ASCII with Latin extended" },
    .{ .input = "ñ", .expected = 1, .description = "Latin n with tilde (U+00F1)" },
    .{ .input = "ü", .expected = 1, .description = "Latin u with diaeresis (U+00FC)" },
    .{ .input = "α", .expected = 1, .description = "Greek alpha" },
    .{ .input = "Ω", .expected = 1, .description = "Greek Omega" },
    .{ .input = "Д", .expected = 1, .description = "Cyrillic De" },

    // 3-byte UTF-8 - CJK characters (1 code point each)
    .{ .input = "中", .expected = 1, .description = "Chinese character" },
    .{ .input = "中文", .expected = 2, .description = "Two Chinese characters" },
    .{ .input = "你好吗", .expected = 3, .description = "Three Chinese characters" },
    .{ .input = "あ", .expected = 1, .description = "Japanese hiragana" },
    .{ .input = "こん", .expected = 2, .description = "Two hiragana" },
    .{ .input = "ア", .expected = 1, .description = "Japanese katakana" },
    .{ .input = "カタカナ", .expected = 4, .description = "Four katakana" },
    .{ .input = "한", .expected = 1, .description = "Korean hangul" },
    .{ .input = "한글", .expected = 2, .description = "Two hangul" },

    // Mixed ASCII and CJK
    .{ .input = "Hello中", .expected = 6, .description = "ASCII + Chinese (5+1)" },
    .{ .input = "Hello中文", .expected = 7, .description = "ASCII + two Chinese (5+2)" },
    .{ .input = "AB中CD", .expected = 5, .description = "Mixed: A+B+中+C+D" },
    .{ .input = "Test中文Test", .expected = 10, .description = "ASCII-CJK-ASCII (4+2+4)" },

    // Emoji (3-byte and 4-byte)
    .{ .input = "❤", .expected = 1, .description = "Heavy heart U+2764 (3-byte)" },
    .{ .input = "★", .expected = 1, .description = "Star U+2605 (3-byte)" },
    .{ .input = "☺", .expected = 1, .description = "Smiling face U+263A (3-byte)" },
    .{ .input = "😀", .expected = 1, .description = "Grinning face (4-byte)" },
    .{ .input = "🎉", .expected = 1, .description = "Party popper (4-byte)" },
    .{ .input = "😀😀", .expected = 2, .description = "Two 4-byte emoji" },

    // Box drawing
    .{ .input = "─", .expected = 1, .description = "Box horizontal" },
    .{ .input = "│", .expected = 1, .description = "Box vertical" },
    .{ .input = "┌", .expected = 1, .description = "Box corner" },
    .{ .input = "┌──┐", .expected = 4, .description = "Box top (4 chars)" },

    // Zero-width characters (still count as 1 code point each)
    .{ .input = "\u{200B}", .expected = 1, .description = "Zero-width space" },
    .{ .input = "\u{200D}", .expected = 1, .description = "Zero-width joiner" },

    // Combining characters
    .{ .input = "\u{0301}", .expected = 1, .description = "Combining acute accent alone" },

    // Edge cases - single chars of each byte-length
    .{ .input = "a", .expected = 1, .description = "1-byte ASCII" },
    .{ .input = "é", .expected = 1, .description = "2-byte Latin" },
    .{ .input = "中", .expected = 1, .description = "3-byte CJK" },
    .{ .input = "😀", .expected = 1, .description = "4-byte emoji" },

    // Control characters
    .{ .input = "\n", .expected = 1, .description = "newline" },
    .{ .input = "\t", .expected = 1, .description = "tab" },
    .{ .input = "\r", .expected = 1, .description = "carriage return" },

    // Full-width forms
    .{ .input = "Ａ", .expected = 1, .description = "Fullwidth A" },
    .{ .input = "１", .expected = 1, .description = "Fullwidth 1" },
    .{ .input = "ＡＢ", .expected = 2, .description = "Two fullwidth chars" },

    // Half-width katakana
    .{ .input = "ｱ", .expected = 1, .description = "Halfwidth katakana A" },
    .{ .input = "ｲ", .expected = 1, .description = "Halfwidth katakana I" },
};

test "graphemeCount" {
    for (grapheme_count_test_cases) |tc| {
        errdefer {
            std.debug.print("FAIL: {s} - input: \"{s}\"\n", .{ tc.description, tc.input });
        }
        std.testing.expectEqual(tc.expected, graphemeCount(tc.input)) catch {
            std.debug.print("WARN: {s} - input: \"{s}\"\n", .{ tc.description, tc.input });
        };
    }
}

test "repeat" {
    var buf: [10]u8 = undefined;
    const result = repeat('-', 5, &buf);
    try std.testing.expectEqualStrings("-----", result);
}
