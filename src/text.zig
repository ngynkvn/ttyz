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

/// Calculate display width of a string (accounting for unicode).
///
/// Uses a simple heuristic based on UTF-8 byte length:
/// - 1-byte (ASCII): 1 column
/// - 2-byte (Latin Extended, Greek, Cyrillic, etc.): 1 column
/// - 3-byte (CJK, emoji, symbols): 2 columns
/// - 4-byte (emoji, rare characters): 2 columns
///
/// Known limitations:
/// - Box drawing characters (U+2500-U+257F) are 3-byte but should be 1 column
/// - Half-width katakana (U+FF65-U+FF9F) are 3-byte but should be 1 column
/// - Zero-width characters (U+200B, U+200D, etc.) should be 0 columns
/// - Combining characters (U+0300-U+036F) should be 0 columns
/// - Control characters (\n, \t, etc.) are counted as 1 but render varies
///
/// For accurate width calculation, consider using a proper Unicode width library.
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
    // std.testing.expectEqual(width, newDisplayWidth(text)) catch |e| {
    //     @panic(@errorName(e));
    // };
    return width;
}
pub fn newDisplayWidth(text: []const u8) usize {
    var i: usize = 0;
    var width: usize = 0;
    while (i < text.len) {
        const len = std.unicode.utf8ByteSequenceLength(text[i]) catch 1;
        width += len;
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

/// Test case for displayWidth function.
const DisplayWidthTestCase = struct {
    input: []const u8,
    expected: usize,
    description: []const u8,
};

/// All displayWidth test cases in a single array.
/// Note: Some cases document current (incorrect) behavior for known limitations.
const display_width_test_cases = [_]DisplayWidthTestCase{
    // Basic ASCII
    .{ .input = "hello", .expected = 5, .description = "basic ASCII word" },
    .{ .input = "", .expected = 0, .description = "empty string" },
    .{ .input = " ", .expected = 1, .description = "single space" },
    .{ .input = "0123456789", .expected = 10, .description = "digits" },

    // 2-byte UTF-8 (Latin Extended, Greek, Cyrillic) - 1 column wide
    .{ .input = "é", .expected = 1, .description = "Latin e with acute (U+00E9)" },
    .{ .input = "café", .expected = 4, .description = "ASCII with Latin extended" },
    .{ .input = "ñ", .expected = 1, .description = "Latin n with tilde (U+00F1)" },
    .{ .input = "ü", .expected = 1, .description = "Latin u with diaeresis (U+00FC)" },
    .{ .input = "α", .expected = 1, .description = "Greek alpha" },
    .{ .input = "Ω", .expected = 1, .description = "Greek Omega" },
    .{ .input = "Д", .expected = 1, .description = "Cyrillic De" },

    // 3-byte UTF-8 - CJK characters (2 columns wide)
    .{ .input = "中", .expected = 2, .description = "Chinese character" },
    .{ .input = "中文", .expected = 4, .description = "Two Chinese characters" },
    .{ .input = "你好吗", .expected = 6, .description = "Three Chinese characters" },
    .{ .input = "あ", .expected = 2, .description = "Japanese hiragana" },
    .{ .input = "こん", .expected = 4, .description = "Two hiragana" },
    .{ .input = "ア", .expected = 2, .description = "Japanese katakana" },
    .{ .input = "カタカナ", .expected = 8, .description = "Four katakana (4*2)" },
    .{ .input = "한", .expected = 2, .description = "Korean hangul" },
    .{ .input = "한글", .expected = 4, .description = "Two hangul" },

    // Mixed ASCII and CJK
    .{ .input = "Hello中", .expected = 7, .description = "ASCII + Chinese (5+2)" },
    .{ .input = "Hello中文", .expected = 9, .description = "ASCII + two Chinese (5+4)" },
    .{ .input = "AB中CD", .expected = 6, .description = "Mixed: A(1)+B(1)+中(2)+C(1)+D(1)" },
    .{ .input = "Test中文Test", .expected = 12, .description = "ASCII-CJK-ASCII (4+4+4)" },

    // Emoji (3-byte and 4-byte)
    .{ .input = "❤", .expected = 2, .description = "Heavy heart U+2764 (3-byte)" },
    .{ .input = "★", .expected = 2, .description = "Star U+2605 (3-byte)" },
    .{ .input = "☺", .expected = 2, .description = "Smiling face U+263A (3-byte)" },
    .{ .input = "😀", .expected = 2, .description = "Grinning face (4-byte)" },
    .{ .input = "🎉", .expected = 2, .description = "Party popper (4-byte)" },
    .{ .input = "😀😀", .expected = 4, .description = "Two 4-byte emoji" },

    // Box drawing - KNOWN LIMITATION: should be 1 wide but returns 2
    .{ .input = "─", .expected = 2, .description = "Box horizontal (SHOULD be 1)" },
    .{ .input = "│", .expected = 2, .description = "Box vertical (SHOULD be 1)" },
    .{ .input = "┌", .expected = 2, .description = "Box corner (SHOULD be 1)" },
    .{ .input = "┌──┐", .expected = 8, .description = "Box top (SHOULD be 4)" },

    // Zero-width characters - KNOWN LIMITATION: should be 0 but returns 2
    .{ .input = "\u{200B}", .expected = 2, .description = "Zero-width space (SHOULD be 0)" },
    .{ .input = "\u{200D}", .expected = 2, .description = "Zero-width joiner (SHOULD be 0)" },

    // Combining characters - 2-byte, returns 1 (should be 0 when after base)
    .{ .input = "\u{0301}", .expected = 1, .description = "Combining acute accent alone" },

    // Edge cases - single chars of each byte-length
    .{ .input = "a", .expected = 1, .description = "1-byte ASCII" },
    .{ .input = "é", .expected = 1, .description = "2-byte Latin" },
    .{ .input = "中", .expected = 2, .description = "3-byte CJK" },
    .{ .input = "😀", .expected = 2, .description = "4-byte emoji" },

    // Control characters (treated as 1 column)
    .{ .input = "\n", .expected = 1, .description = "newline" },
    .{ .input = "\t", .expected = 1, .description = "tab" },
    .{ .input = "\r", .expected = 1, .description = "carriage return" },

    // Full-width forms (3-byte, correctly 2 columns)
    .{ .input = "Ａ", .expected = 2, .description = "Fullwidth A" },
    .{ .input = "１", .expected = 2, .description = "Fullwidth 1" },
    .{ .input = "ＡＢ", .expected = 4, .description = "Two fullwidth chars" },

    // Half-width katakana - KNOWN LIMITATION: should be 1 but returns 2
    .{ .input = "ｱ", .expected = 2, .description = "Halfwidth katakana A (SHOULD be 1)" },
    .{ .input = "ｲ", .expected = 2, .description = "Halfwidth katakana I (SHOULD be 1)" },
};

test "displayWidth" {
    for (display_width_test_cases) |tc| {
        std.testing.expectEqual(tc.expected, displayWidth(tc.input)) catch |err| {
            std.debug.print("FAIL: {s} - input: \"{s}\"\n", .{ tc.description, tc.input });
            return err;
        };
    }
}

test "repeat" {
    var buf: [10]u8 = undefined;
    const result = repeat('-', 5, &buf);
    try std.testing.expectEqualStrings("-----", result);
}

const std = @import("std");
