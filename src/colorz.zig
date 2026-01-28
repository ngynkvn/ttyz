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
pub const Colorz = struct {
    const Self = @This();

    /// The underlying writer.
    inner: std.Io.Writer,

    /// Wrap an existing writer to enable color code parsing.
    pub fn init(inner: std.Io.Writer) Self {
        return .{ .inner = inner };
    }

    /// Get the underlying writer for direct access.
    pub fn writer(self: *Self) std.Io.Writer {
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
        _ = try self.inner.print(fmt ++ ansi.reset, args);
    }

    /// Print text with foreground and background colors, automatically resetting after.
    pub fn printStyled(self: *Self, fg_color: ?Color, bg_color: ?Color, style: ?Style, comptime fmt: []const u8, args: anytype) !void {
        if (style) |s| _ = try self.inner.write(s.toAnsi());
        if (fg_color) |c| _ = try self.inner.write(c.fg());
        if (bg_color) |c| _ = try self.inner.write(c.bg());
        _ = try self.inner.print(fmt ++ ansi.reset, args);
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
        _ = try self.inner.write(style.toAnsi());
    }

    /// Reset all colors and styles.
    pub fn reset(self: *Self) !void {
        _ = try self.inner.write(ansi.reset);
    }
};

/// Wrap a writer to enable color code parsing.
pub fn wrap(inner: std.Io.Writer) Colorz {
    return Colorz.init(inner);
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
            .black => ansi.fg.black,
            .red => ansi.fg.red,
            .green => ansi.fg.green,
            .yellow => ansi.fg.yellow,
            .blue => ansi.fg.blue,
            .magenta => ansi.fg.magenta,
            .cyan => ansi.fg.cyan,
            .white => ansi.fg.white,
            .bright_black => ansi.fg.bright_black,
            .bright_red => ansi.fg.bright_red,
            .bright_green => ansi.fg.bright_green,
            .bright_yellow => ansi.fg.bright_yellow,
            .bright_blue => ansi.fg.bright_blue,
            .bright_magenta => ansi.fg.bright_magenta,
            .bright_cyan => ansi.fg.bright_cyan,
            .bright_white => ansi.fg.bright_white,
        };
    }

    /// Get the ANSI escape sequence for background color.
    pub fn bg(self: Color) []const u8 {
        return switch (self) {
            .black => ansi.bg.black,
            .red => ansi.bg.red,
            .green => ansi.bg.green,
            .yellow => ansi.bg.yellow,
            .blue => ansi.bg.blue,
            .magenta => ansi.bg.magenta,
            .cyan => ansi.bg.cyan,
            .white => ansi.bg.white,
            .bright_black => ansi.bg.bright_black,
            .bright_red => ansi.bg.bright_red,
            .bright_green => ansi.bg.bright_green,
            .bright_yellow => ansi.bg.bright_yellow,
            .bright_blue => ansi.bg.bright_blue,
            .bright_magenta => ansi.bg.bright_magenta,
            .bright_cyan => ansi.bg.bright_cyan,
            .bright_white => ansi.bg.bright_white,
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
    pub fn toAnsi(self: Style) []const u8 {
        return switch (self) {
            .bold => ansi.bold,
            .dim => ansi.faint,
            .italic => ansi.italic,
            .underline => ansi.underline,
            .reverse => ansi.reverse,
            .strikethrough => ansi.crossed_out,
            .reset => ansi.reset,
        };
    }
};

// Dot codes map for format string parsing
// Foreground colors: @[.red], @[.green], etc.
// Background colors: @[.bg_red], @[.bg_green], etc.
// Styles: @[.bold], @[.dim], @[.italic], @[.underline], @[.reset]
const DotCodes = std.StaticStringMap([]const u8).initComptime(.{
    // Foreground colors
    .{ ".black", ansi.fg.black },
    .{ ".red", ansi.fg.red },
    .{ ".green", ansi.fg.green },
    .{ ".yellow", ansi.fg.yellow },
    .{ ".blue", ansi.fg.blue },
    .{ ".magenta", ansi.fg.magenta },
    .{ ".cyan", ansi.fg.cyan },
    .{ ".white", ansi.fg.white },
    .{ ".bright_black", ansi.fg.bright_black },
    .{ ".bright_red", ansi.fg.bright_red },
    .{ ".bright_green", ansi.fg.bright_green },
    .{ ".bright_yellow", ansi.fg.bright_yellow },
    .{ ".bright_blue", ansi.fg.bright_blue },
    .{ ".bright_magenta", ansi.fg.bright_magenta },
    .{ ".bright_cyan", ansi.fg.bright_cyan },
    .{ ".bright_white", ansi.fg.bright_white },
    // Background colors
    .{ ".bg_black", ansi.bg.black },
    .{ ".bg_red", ansi.bg.red },
    .{ ".bg_green", ansi.bg.green },
    .{ ".bg_yellow", ansi.bg.yellow },
    .{ ".bg_blue", ansi.bg.blue },
    .{ ".bg_magenta", ansi.bg.magenta },
    .{ ".bg_cyan", ansi.bg.cyan },
    .{ ".bg_white", ansi.bg.white },
    .{ ".bg_bright_black", ansi.bg.bright_black },
    .{ ".bg_bright_red", ansi.bg.bright_red },
    .{ ".bg_bright_green", ansi.bg.bright_green },
    .{ ".bg_bright_yellow", ansi.bg.bright_yellow },
    .{ ".bg_bright_blue", ansi.bg.bright_blue },
    .{ ".bg_bright_magenta", ansi.bg.bright_magenta },
    .{ ".bg_bright_cyan", ansi.bg.bright_cyan },
    .{ ".bg_bright_white", ansi.bg.bright_white },
    // Text styles
    .{ ".bold", ansi.bold },
    .{ ".dim", ansi.faint },
    .{ ".italic", ansi.italic },
    .{ ".underline", ansi.underline },
    .{ ".reverse", ansi.reverse },
    .{ ".strikethrough", ansi.crossed_out },
    .{ ".reset", ansi.reset },
});

// Bang codes map for cursor control
// Note: cursor save/restore use DEC sequences for wider compatibility
const BangCodes = std.StaticStringMap([]const u8).initComptime(.{
    .{ "!H", ansi.cursor_home },
    .{ "!CI", ansi.cursor_hide },
    .{ "!CV", ansi.cursor_show },
    .{ "!S", "\x1b[7" }, // DEC save cursor (more widely supported than ANSI \x1b[s)
    .{ "!R", "\x1b[8" }, // DEC restore cursor (more widely supported than ANSI \x1b[u)
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
                            literal = literal ++ comptimePrint(ansi.goto_fmt, .{ row, col });
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
        try std.testing.expectEqualStrings(expected, s);
    }
}

const std = @import("std");
const comptimePrint = std.fmt.comptimePrint;

const ansi = @import("ansi.zig");
