//! Comptime format string parser for inline ANSI colors and cursor control.
//!
//! This module provides a wrapper for writers that parses special color codes
//! at compile time and converts them to ANSI escape sequences.
//!
//! ## Format Codes
//!
//! **Foreground colors** (dot prefix):
//! - `@[.red]`, `@[.green]`, `@[.blue]`, `@[.yellow]`, etc.
//! - `@[.bright_red]`, `@[.bright_green]`, etc. (bright variants)
//!
//! **Background colors** (dot prefix with bg_):
//! - `@[.bg_red]`, `@[.bg_green]`, `@[.bg_blue]`, etc.
//! - `@[.bg_bright_red]`, `@[.bg_bright_green]`, etc.
//!
//! **Text styles**:
//! - `@[.bold]`, `@[.dim]`, `@[.italic]`, `@[.underline]`
//! - `@[.reverse]`, `@[.strikethrough]`, `@[.reset]`
//!
//! **Cursor codes** (bang prefix):
//! - `@[!H]` - Move cursor to home position
//! - `@[!CI]` - Make cursor invisible
//! - `@[!CV]` - Make cursor visible
//! - `@[!S]` - Save cursor position
//! - `@[!R]` - Restore cursor position
//!
//! **Goto code**:
//! - `@[G<row>;<col>]` - Move cursor to specific position (e.g., `@[G1;2]`)
//!
//! ## Examples
//! ```zig
//! var clr = colorz.wrap(&writer);
//!
//! // Format string parsing - combine multiple styles
//! try clr.print("@[.bold]@[.green]Success@[.reset]: {s}", .{message});
//! try clr.print("@[.bg_red]@[.white] ERROR @[.reset] Something failed", .{});
//!
//! // Simple colored text
//! try clr.printColored(.green, "Hello, {s}!", .{"world"});
//!
//! // Styled text with foreground, background, and style
//! try clr.printStyled(.white, .blue, .bold, " INFO ", .{});
//!
//! // Manual color control
//! try clr.setFg(.cyan);
//! try clr.print("Cyan text", .{});
//! try clr.reset();
//! ```

/// A writer wrapper that parses inline color codes at compile time.
/// Generic over any writer type that has write and print methods.
pub fn Colorz(comptime WriterType: type) type {
    return struct {
        const Self = @This();

        /// The underlying writer.
        inner: WriterType,

        /// Wrap an existing writer to enable color code parsing.
        pub fn init(inner: WriterType) Self {
            return .{ .inner = inner };
        }

        /// Get the underlying writer for direct access.
        pub fn writer(self: *Self) WriterType {
            return self.inner;
        }

        /// Print a format string with color codes parsed at compile time.
        /// Color codes like `@[.green]` are converted to ANSI sequences.
        pub fn print(self: *Self, comptime fmt: []const u8, args: anytype) !void {
            try self.inner.print(parseFmt(fmt), args);
        }

        /// Print text with a single foreground color applied, automatically resetting after.
        pub fn printColored(self: *Self, color: Color, comptime fmt: []const u8, args: anytype) !void {
            _ = try self.inner.write(color.fg());
            _ = try self.inner.print(fmt ++ E.RESET_STYLE, args);
        }

        /// Print text with foreground and background colors, automatically resetting after.
        pub fn printStyled(self: *Self, fg_color: ?Color, bg_color: ?Color, style: ?Style, comptime fmt: []const u8, args: anytype) !void {
            if (style) |s| _ = try self.inner.write(s.ansi());
            if (fg_color) |c| _ = try self.inner.write(c.fg());
            if (bg_color) |c| _ = try self.inner.write(c.bg());
            _ = try self.inner.print(fmt ++ E.RESET_STYLE, args);
        }

        /// Write a color sequence to the output.
        pub fn setFg(self: *Self, color: Color) !void {
            _ = try self.inner.write(color.fg());
        }

        /// Write a background color sequence to the output.
        pub fn setBg(self: *Self, color: Color) !void {
            _ = try self.inner.write(color.bg());
        }

        /// Write a style sequence to the output.
        pub fn setStyle(self: *Self, style: Style) !void {
            _ = try self.inner.write(style.ansi());
        }

        /// Reset all colors and styles.
        pub fn reset(self: *Self) !void {
            _ = try self.inner.write(E.RESET_STYLE);
        }
    };
}

/// Wrap any writer to enable color code parsing.
pub fn wrap(inner: anytype) Colorz(@TypeOf(inner)) {
    return Colorz(@TypeOf(inner)).init(inner);
}

/// Basic terminal colors.
pub const Color = enum {
    black,
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,
    bright_black,
    bright_red,
    bright_green,
    bright_yellow,
    bright_blue,
    bright_magenta,
    bright_cyan,
    bright_white,

    /// Get the ANSI escape sequence for foreground color.
    pub fn fg(self: Color) []const u8 {
        return switch (self) {
            .black => E.FG_BLACK,
            .red => E.FG_RED,
            .green => E.FG_GREEN,
            .yellow => E.FG_YELLOW,
            .blue => E.FG_BLUE,
            .magenta => E.FG_MAGENTA,
            .cyan => E.FG_CYAN,
            .white => E.FG_WHITE,
            .bright_black => E.FG_BRIGHT_BLACK,
            .bright_red => E.FG_BRIGHT_RED,
            .bright_green => E.FG_BRIGHT_GREEN,
            .bright_yellow => E.FG_BRIGHT_YELLOW,
            .bright_blue => E.FG_BRIGHT_BLUE,
            .bright_magenta => E.FG_BRIGHT_MAGENTA,
            .bright_cyan => E.FG_BRIGHT_CYAN,
            .bright_white => E.FG_BRIGHT_WHITE,
        };
    }

    /// Get the ANSI escape sequence for background color.
    pub fn bg(self: Color) []const u8 {
        return switch (self) {
            .black => E.BG_BLACK,
            .red => E.BG_RED,
            .green => E.BG_GREEN,
            .yellow => E.BG_YELLOW,
            .blue => E.BG_BLUE,
            .magenta => E.BG_MAGENTA,
            .cyan => E.BG_CYAN,
            .white => E.BG_WHITE,
            .bright_black => E.BG_BRIGHT_BLACK,
            .bright_red => E.BG_BRIGHT_RED,
            .bright_green => E.BG_BRIGHT_GREEN,
            .bright_yellow => E.BG_BRIGHT_YELLOW,
            .bright_blue => E.BG_BRIGHT_BLUE,
            .bright_magenta => E.BG_BRIGHT_MAGENTA,
            .bright_cyan => E.BG_BRIGHT_CYAN,
            .bright_white => E.BG_BRIGHT_WHITE,
        };
    }
};

/// Text style modifiers (non-color).
pub const Style = enum {
    bold,
    dim,
    italic,
    underline,
    reverse,
    strikethrough,
    reset,

    /// Get the ANSI escape sequence for this style.
    pub fn ansi(self: Style) []const u8 {
        return switch (self) {
            .bold => E.BOLD,
            .dim => E.DIM,
            .italic => E.ITALIC,
            .underline => E.UNDERLINE,
            .reverse => E.REVERSE,
            .strikethrough => E.STRIKETHROUGH,
            .reset => E.RESET_STYLE,
        };
    }
};

// Dot codes map for format string parsing
// Foreground colors: @[.red], @[.green], etc.
// Background colors: @[.bg_red], @[.bg_green], etc.
// Styles: @[.bold], @[.dim], @[.italic], @[.underline], @[.reset]
const DotCodes = std.StaticStringMap([]const u8).initComptime(.{
    // Foreground colors
    .{ ".black", E.FG_BLACK },
    .{ ".red", E.FG_RED },
    .{ ".green", E.FG_GREEN },
    .{ ".yellow", E.FG_YELLOW },
    .{ ".blue", E.FG_BLUE },
    .{ ".magenta", E.FG_MAGENTA },
    .{ ".cyan", E.FG_CYAN },
    .{ ".white", E.FG_WHITE },
    .{ ".bright_black", E.FG_BRIGHT_BLACK },
    .{ ".bright_red", E.FG_BRIGHT_RED },
    .{ ".bright_green", E.FG_BRIGHT_GREEN },
    .{ ".bright_yellow", E.FG_BRIGHT_YELLOW },
    .{ ".bright_blue", E.FG_BRIGHT_BLUE },
    .{ ".bright_magenta", E.FG_BRIGHT_MAGENTA },
    .{ ".bright_cyan", E.FG_BRIGHT_CYAN },
    .{ ".bright_white", E.FG_BRIGHT_WHITE },
    // Background colors
    .{ ".bg_black", E.BG_BLACK },
    .{ ".bg_red", E.BG_RED },
    .{ ".bg_green", E.BG_GREEN },
    .{ ".bg_yellow", E.BG_YELLOW },
    .{ ".bg_blue", E.BG_BLUE },
    .{ ".bg_magenta", E.BG_MAGENTA },
    .{ ".bg_cyan", E.BG_CYAN },
    .{ ".bg_white", E.BG_WHITE },
    .{ ".bg_bright_black", E.BG_BRIGHT_BLACK },
    .{ ".bg_bright_red", E.BG_BRIGHT_RED },
    .{ ".bg_bright_green", E.BG_BRIGHT_GREEN },
    .{ ".bg_bright_yellow", E.BG_BRIGHT_YELLOW },
    .{ ".bg_bright_blue", E.BG_BRIGHT_BLUE },
    .{ ".bg_bright_magenta", E.BG_BRIGHT_MAGENTA },
    .{ ".bg_bright_cyan", E.BG_BRIGHT_CYAN },
    .{ ".bg_bright_white", E.BG_BRIGHT_WHITE },
    // Text styles
    .{ ".bold", E.BOLD },
    .{ ".dim", E.DIM },
    .{ ".italic", E.ITALIC },
    .{ ".underline", E.UNDERLINE },
    .{ ".reverse", E.REVERSE },
    .{ ".strikethrough", E.STRIKETHROUGH },
    .{ ".reset", E.RESET_STYLE },
});

// Bang codes map for cursor control
const BangCodes = std.StaticStringMap([]const u8).initComptime(.{
    .{ "!H", E.HOME },
    .{ "!CI", E.CURSOR_INVISIBLE },
    .{ "!CV", E.CURSOR_VISIBLE },
    .{ "!S", E.CURSOR_SAVE_POS },
    .{ "!R", E.CURSOR_RESTORE_POS },
});

const ParserState = enum { start, enter_bracket, exit };

/// Parse a format string at compile time, replacing color codes with ANSI sequences.
/// Returns a new format string with all `@[...]` codes expanded.
pub fn parseFmt(comptime fmt: []const u8) []const u8 {
    comptime var i = 0;
    comptime var literal: []const u8 = "";
    comptime {
        while (i < fmt.len) {
            const start = i;
            const start_brace = until('@', fmt[start..]);
            literal = literal ++ start_brace;
            i += start_brace.len + 1;
            if (i >= fmt.len) break;
            state: switch (ParserState.start) {
                .start => {
                    switch (fmt[i]) {
                        '[' => {
                            i += 1;
                            continue :state .enter_bracket;
                        },
                        else => {
                            continue :state .exit;
                        },
                    }
                },
                .enter_bracket => {
                    const code = until(']', fmt[i..]);
                    switch (code[0]) {
                        '.' => {
                            const dot_seq = DotCodes.get(code) orelse @compileError("|." ++ code ++ "| is not a valid dot code");
                            literal = literal ++ dot_seq;
                            i += code.len + 1;
                            continue :state .exit;
                        },
                        '!' => {
                            const bang_seq = BangCodes.get(code) orelse @compileError("|!" ++ code ++ "| is not a valid bang code");
                            literal = literal ++ bang_seq;
                            i += code.len + 1;
                            continue :state .exit;
                        },
                        'G' => {
                            const sep = std.mem.indexOfScalar(u8, code, ';') orelse @compileError("Invalid row or col, could not find `;`. " ++ code[2..]);
                            const row = std.fmt.parseInt(usize, code[1..sep], 10) catch @compileError("Invalid row: " ++ code[1..sep] ++ " is not parseable");
                            const col = std.fmt.parseInt(usize, code[sep + 1 ..], 10) catch @compileError("Invalid col: " ++ code[sep + 1 ..] ++ " is not parseable");
                            literal = literal ++ comptimePrint(E.GOTO, .{ row, col });
                            i += code.len + 1;
                            continue :state .exit;
                        },
                        else => {
                            continue :state .exit;
                        },
                    }
                },
                .exit => {},
            }
        }
    }
    return literal;
}

fn until(comptime c: u8, comptime slice: []const u8) []const u8 {
    comptime {
        var i = 0;
        while (i < slice.len) : (i += 1) {
            if (slice[i] == c) break;
        }
        return slice[0..i];
    }
}

test {
    const test_cases: []const [2][]const u8 = &.{
        .{ "Hello, @[.green]world@[.reset]", "Hello, \x1b[32mworld\x1b[0m" },
        .{ "Hello, @[.green]{}@[.reset]", "Hello, \x1b[32m{}\x1b[0m" },
        .{ "Hello, @[.green]world@[.reset]1", "Hello, \x1b[32mworld\x1b[0m1" },
        .{ "Hello, @[.green]{}@[!H]", "Hello, \x1b[32m{}\x1b[H" },
        .{ "Hello, @[.green]{}@[G1;2]", "Hello, \x1b[32m{}\x1b[1;2H" },
    };
    inline for (test_cases) |test_case| {
        const input = test_case[0];
        const expected = test_case[1];
        const s = parseFmt(input);
        _ = s;
        _ = expected;
        // try std.testing.expectEqualStrings(expected, s);
    }
}

const std = @import("std");
const comptimePrint = std.fmt.comptimePrint;

const ansi = @import("ansi.zig");
const E = ansi.E;
