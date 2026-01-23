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

test "displayWidth basic ASCII" {
    try std.testing.expectEqual(@as(usize, 5), displayWidth("hello"));
    try std.testing.expectEqual(@as(usize, 0), displayWidth(""));
    try std.testing.expectEqual(@as(usize, 1), displayWidth(" "));
    try std.testing.expectEqual(@as(usize, 10), displayWidth("0123456789"));
}

test "displayWidth Latin extended characters" {
    // 2-byte UTF-8 sequences (Latin Extended, Greek, Cyrillic, etc.)
    // These should be 1 column wide

    // é (U+00E9) - Latin small e with acute - 2 bytes
    try std.testing.expectEqual(@as(usize, 1), displayWidth("é"));
    try std.testing.expectEqual(@as(usize, 4), displayWidth("café"));

    // ñ (U+00F1) - Latin small n with tilde
    try std.testing.expectEqual(@as(usize, 1), displayWidth("ñ"));

    // ü (U+00FC) - Latin small u with diaeresis
    try std.testing.expectEqual(@as(usize, 1), displayWidth("ü"));

    // Greek letters
    try std.testing.expectEqual(@as(usize, 1), displayWidth("α")); // alpha
    try std.testing.expectEqual(@as(usize, 1), displayWidth("Ω")); // Omega

    // Cyrillic
    try std.testing.expectEqual(@as(usize, 1), displayWidth("Д")); // De
}

test "displayWidth CJK characters" {
    // 3-byte UTF-8 sequences - CJK characters are typically 2 columns wide

    // Chinese characters
    try std.testing.expectEqual(@as(usize, 2), displayWidth("中"));
    try std.testing.expectEqual(@as(usize, 4), displayWidth("中文"));
    try std.testing.expectEqual(@as(usize, 6), displayWidth("你好吗"));

    // Japanese hiragana
    try std.testing.expectEqual(@as(usize, 2), displayWidth("あ"));
    try std.testing.expectEqual(@as(usize, 4), displayWidth("こん"));

    // Japanese katakana
    try std.testing.expectEqual(@as(usize, 2), displayWidth("ア"));
    try std.testing.expectEqual(@as(usize, 8), displayWidth("カタカナ")); // 4 chars * 2 wide each

    // Korean hangul
    try std.testing.expectEqual(@as(usize, 2), displayWidth("한"));
    try std.testing.expectEqual(@as(usize, 4), displayWidth("한글"));
}

test "displayWidth mixed ASCII and CJK" {
    // Mixed content: ASCII is 1 wide, CJK is 2 wide
    try std.testing.expectEqual(@as(usize, 7), displayWidth("Hello中")); // 5 + 2
    try std.testing.expectEqual(@as(usize, 9), displayWidth("Hello中文")); // 5 + 4

    // "AB中CD" = A(1) + B(1) + 中(2) + C(1) + D(1) = 6
    try std.testing.expectEqual(@as(usize, 6), displayWidth("AB中CD"));

    // More complex mixed strings
    // T(1) + e(1) + s(1) + t(1) + 中(2) + 文(2) + T(1) + e(1) + s(1) + t(1) = 12
    try std.testing.expectEqual(@as(usize, 12), displayWidth("Test中文Test"));
}

test "displayWidth emoji" {
    // Basic emoji (often 3-byte or 4-byte UTF-8)
    // Most emoji are rendered as 2 columns wide in terminals

    // Simple emoji (3-byte)
    try std.testing.expectEqual(@as(usize, 2), displayWidth("❤")); // Heavy heart (U+2764)
    try std.testing.expectEqual(@as(usize, 2), displayWidth("★")); // Star (U+2605)
    try std.testing.expectEqual(@as(usize, 2), displayWidth("☺")); // Smiling face (U+263A)

    // 4-byte emoji
    try std.testing.expectEqual(@as(usize, 2), displayWidth("😀")); // Grinning face
    try std.testing.expectEqual(@as(usize, 2), displayWidth("🎉")); // Party popper
    try std.testing.expectEqual(@as(usize, 4), displayWidth("😀😀")); // Two emoji
}

test "displayWidth box drawing characters" {
    // Box drawing characters are 3-byte UTF-8 but should be 1 column wide
    // Note: Current implementation treats all 3-byte as 2-wide, which is incorrect for these

    // These SHOULD be 1 wide, but current impl says 2
    // This test documents current (incorrect) behavior
    try std.testing.expectEqual(@as(usize, 2), displayWidth("─")); // Box horizontal
    try std.testing.expectEqual(@as(usize, 2), displayWidth("│")); // Box vertical
    try std.testing.expectEqual(@as(usize, 2), displayWidth("┌")); // Box corner
    try std.testing.expectEqual(@as(usize, 8), displayWidth("┌──┐")); // Box top - 4 chars * 2
}

test "displayWidth special Unicode" {
    // Zero-width characters (SHOULD be 0 width)
    // Current implementation doesn't handle these specially

    // Zero-width space (U+200B) - 3 bytes
    // Should be 0 but current impl returns 2
    try std.testing.expectEqual(@as(usize, 2), displayWidth("\u{200B}"));

    // Zero-width joiner (U+200D) - 3 bytes
    try std.testing.expectEqual(@as(usize, 2), displayWidth("\u{200D}"));

    // Combining characters (should be 0 width)
    // Combining acute accent (U+0301) - 2 bytes after base char
    try std.testing.expectEqual(@as(usize, 1), displayWidth("\u{0301}")); // Just the combining char
}

test "displayWidth edge cases" {
    // Empty string
    try std.testing.expectEqual(@as(usize, 0), displayWidth(""));

    // Single characters of each byte-length
    try std.testing.expectEqual(@as(usize, 1), displayWidth("a")); // 1-byte
    try std.testing.expectEqual(@as(usize, 1), displayWidth("é")); // 2-byte
    try std.testing.expectEqual(@as(usize, 2), displayWidth("中")); // 3-byte
    try std.testing.expectEqual(@as(usize, 2), displayWidth("😀")); // 4-byte

    // Newlines and control characters (should probably be 0, but treated as 1)
    try std.testing.expectEqual(@as(usize, 1), displayWidth("\n"));
    try std.testing.expectEqual(@as(usize, 1), displayWidth("\t"));
    try std.testing.expectEqual(@as(usize, 1), displayWidth("\r"));
}

test "displayWidth full-width forms" {
    // Full-width ASCII variants (U+FF01 to U+FF5E)
    // These are 3-byte UTF-8 and SHOULD be 2 columns wide

    try std.testing.expectEqual(@as(usize, 2), displayWidth("Ａ")); // Fullwidth A
    try std.testing.expectEqual(@as(usize, 2), displayWidth("１")); // Fullwidth 1
    try std.testing.expectEqual(@as(usize, 4), displayWidth("ＡＢ")); // Two fullwidth chars
}

test "displayWidth halfwidth katakana" {
    // Half-width katakana (U+FF65 to U+FF9F)
    // These are 3-byte UTF-8 but should be 1 column wide
    // Current implementation incorrectly returns 2

    try std.testing.expectEqual(@as(usize, 2), displayWidth("ｱ")); // Halfwidth A - SHOULD be 1
    try std.testing.expectEqual(@as(usize, 2), displayWidth("ｲ")); // Halfwidth I - SHOULD be 1
}

test "repeat" {
    var buf: [10]u8 = undefined;
    const result = repeat('-', 5, &buf);
    try std.testing.expectEqualStrings("-----", result);
}

const std = @import("std");
