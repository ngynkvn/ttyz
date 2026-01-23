//! Comptime format string parser for inline ANSI colors and cursor control.
//!
//! This module provides a wrapper for writers that parses special color codes
//! at compile time and converts them to ANSI escape sequences.
//!
//! ## Format Codes
//!
//! **Color codes** (dot prefix):
//! - `@[.red]`, `@[.green]`, `@[.blue]`, `@[.yellow]`, etc.
//! - `@[.bright_red]`, `@[.bright_green]`, etc. (bright variants)
//! - `@[.bold]`, `@[.dim]`, `@[.reset]`
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
//! ## Example
//! ```zig
//! var clr = colorz.wrap(&writer);
//! try clr.print("@[.green]Success@[.reset]: {s}", .{message});
//! ```

const std = @import("std");
const esc = @import("esc.zig");
const assert = std.debug.assert;
const Parser = std.fmt.Parser;
const comptimePrint = std.fmt.comptimePrint;

/// A writer wrapper that parses inline color codes at compile time.
pub const Colorz = @This();

/// The underlying writer.
inner: *std.Io.Writer,

/// Wrap an existing writer to enable color code parsing.
pub fn wrap(impl: *std.Io.Writer) Colorz {
    return .{ .inner = impl };
}

/// Get the underlying writer for direct access.
pub fn writer(self: *Colorz) std.Io.Writer {
    return self.inner;
}

/// Print a format string with color codes parsed at compile time.
/// Color codes like `@[.green]` are converted to ANSI sequences.
pub fn print(self: *Colorz, comptime fmt: []const u8, args: anytype) !void {
    try self.inner.print(parseFmt(fmt), args);
}

// dot codes are used to set the color of the text
const DotCodes = std.StaticStringMap([]const u8).initComptime(.{
    .{ ".black", "\x1b[30m" },        .{ ".red", "\x1b[31m" },
    .{ ".green", "\x1b[32m" },        .{ ".yellow", "\x1b[33m" },
    .{ ".blue", "\x1b[34m" },         .{ ".magenta", "\x1b[35m" },
    .{ ".cyan", "\x1b[36m" },         .{ ".white", "\x1b[37m" },
    .{ ".bright_black", "\x1b[90m" }, .{ ".bright_red", "\x1b[91m" },
    .{ ".bright_green", "\x1b[92m" }, .{ ".bright_yellow", "\x1b[93m" },
    .{ ".bright_blue", "\x1b[94m" },  .{ ".bright_magenta", "\x1b[95m" },
    .{ ".bright_cyan", "\x1b[96m" },  .{ ".bright_white", "\x1b[97m" },
    .{ ".bold", "\x1b[1m" },          .{ ".dim", "\x1b[2m" },
    .{ ".reset", "\x1b[0m" },
});

// bang codes are used to set the cursor position
const BangCodes = std.StaticStringMap([]const u8).initComptime(.{
    .{ "!H", "\x1b[H" },
    .{ "!CI", esc.E.CURSOR_INVISIBLE },
    .{ "!CV", esc.E.CURSOR_VISIBLE },
    .{ "!S", esc.E.CURSOR_SAVE_POS },
    .{ "!R", esc.E.CURSOR_RESTORE_POS },
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
                            literal = literal ++ comptimePrint(esc.E.GOTO, .{ row, col });
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
