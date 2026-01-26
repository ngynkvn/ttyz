const std = @import("std");

/// Parser result - either success with value and remaining input, or failure
pub fn Result(comptime T: type) type {
    return union(enum) {
        ok: struct {
            value: T,
            rest: []const u8,
        },
        err: struct {
            expected: []const u8,
            found: []const u8,
        },

        pub fn map(self: @This(), comptime U: type, f: fn (T) U) Result(U) {
            return switch (self) {
                .ok => |ok| .{ .ok = .{ .value = f(ok.value), .rest = ok.rest } },
                .err => |e| .{ .err = e },
            };
        }

        pub fn isOk(self: @This()) bool {
            return self == .ok;
        }

        pub fn isErr(self: @This()) bool {
            return self == .err;
        }
    };
}

/// A parser is a function that takes input and returns a result
pub fn Parser(comptime T: type) type {
    return *const fn ([]const u8) Result(T);
}

// ============================================================================
// Basic Parsers
// ============================================================================

/// Parse a single character matching a predicate
pub fn satisfy(comptime pred: fn (u8) bool, comptime expected: []const u8) Parser(u8) {
    const S = struct {
        fn parse(input: []const u8) Result(u8) {
            if (input.len == 0) {
                return .{ .err = .{ .expected = expected, .found = "end of input" } };
            }
            if (pred(input[0])) {
                return .{ .ok = .{ .value = input[0], .rest = input[1..] } };
            }
            return .{ .err = .{ .expected = expected, .found = input[0..1] } };
        }
    };
    return S.parse;
}

/// Parse a specific character
pub fn char(comptime c: u8) Parser(u8) {
    const S = struct {
        fn pred(ch: u8) bool {
            return ch == c;
        }
    };
    return satisfy(S.pred, &[_]u8{c});
}

/// Parse an exact string literal
pub fn literal(comptime str: []const u8) Parser([]const u8) {
    const S = struct {
        fn parse(input: []const u8) Result([]const u8) {
            if (input.len < str.len) {
                return .{ .err = .{ .expected = str, .found = "end of input" } };
            }
            if (std.mem.eql(u8, input[0..str.len], str)) {
                return .{ .ok = .{ .value = str, .rest = input[str.len..] } };
            }
            return .{ .err = .{ .expected = str, .found = input[0..@min(str.len, input.len)] } };
        }
    };
    return S.parse;
}

// ============================================================================
// Character Class Parsers
// ============================================================================

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn isHexDigit(c: u8) bool {
    return isDigit(c) or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
}

fn isAlpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
}

fn isAlphaNum(c: u8) bool {
    return isAlpha(c) or isDigit(c);
}

fn isWhitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r';
}

pub const digit = satisfy(isDigit, "digit");
pub const hexDigit = satisfy(isHexDigit, "hex digit");
pub const alpha = satisfy(isAlpha, "letter");
pub const alphaNum = satisfy(isAlphaNum, "alphanumeric");
pub const whitespace = satisfy(isWhitespace, "whitespace");

// ============================================================================
// Combinators
// ============================================================================

/// Try first parser, if it fails try second
pub fn alt(comptime T: type, comptime p1: Parser(T), comptime p2: Parser(T)) Parser(T) {
    const S = struct {
        fn parse(input: []const u8) Result(T) {
            const r1 = p1(input);
            if (r1.isOk()) return r1;
            return p2(input);
        }
    };
    return S.parse;
}

/// Parse p, or return default value if it fails
pub fn optional(comptime T: type, comptime p: Parser(T), comptime default: T) Parser(T) {
    const S = struct {
        fn parse(input: []const u8) Result(T) {
            const r = p(input);
            if (r.isOk()) return r;
            return .{ .ok = .{ .value = default, .rest = input } };
        }
    };
    return S.parse;
}

/// Sequence two parsers, returning both results as a tuple
pub fn seq(comptime T: type, comptime U: type, comptime p1: Parser(T), comptime p2: Parser(U)) Parser(struct { T, U }) {
    const S = struct {
        fn parse(input: []const u8) Result(struct { T, U }) {
            const r1 = p1(input);
            switch (r1) {
                .ok => |ok1| {
                    const r2 = p2(ok1.rest);
                    switch (r2) {
                        .ok => |ok2| return .{ .ok = .{ .value = .{ ok1.value, ok2.value }, .rest = ok2.rest } },
                        .err => |e| return .{ .err = e },
                    }
                },
                .err => |e| return .{ .err = e },
            }
        }
    };
    return S.parse;
}

/// Sequence two parsers, keeping only the left result
pub fn left(comptime T: type, comptime U: type, comptime p1: Parser(T), comptime p2: Parser(U)) Parser(T) {
    const S = struct {
        fn parse(input: []const u8) Result(T) {
            const r1 = p1(input);
            switch (r1) {
                .ok => |ok1| {
                    const r2 = p2(ok1.rest);
                    switch (r2) {
                        .ok => |ok2| return .{ .ok = .{ .value = ok1.value, .rest = ok2.rest } },
                        .err => |e| return .{ .err = e },
                    }
                },
                .err => |e| return .{ .err = e },
            }
        }
    };
    return S.parse;
}

/// Sequence two parsers, keeping only the right result
pub fn right(comptime T: type, comptime U: type, comptime p1: Parser(T), comptime p2: Parser(U)) Parser(U) {
    const S = struct {
        fn parse(input: []const u8) Result(U) {
            const r1 = p1(input);
            switch (r1) {
                .ok => |ok1| {
                    return p2(ok1.rest);
                },
                .err => |e| return .{ .err = e },
            }
        }
    };
    return S.parse;
}

/// Parse exactly N repetitions
pub fn count(comptime N: usize, comptime p: Parser(u8)) Parser([N]u8) {
    const S = struct {
        fn parse(input: []const u8) Result([N]u8) {
            var result: [N]u8 = undefined;
            var rest = input;
            for (0..N) |i| {
                const r = p(rest);
                switch (r) {
                    .ok => |ok| {
                        result[i] = ok.value;
                        rest = ok.rest;
                    },
                    .err => |e| return .{ .err = e },
                }
            }
            return .{ .ok = .{ .value = result, .rest = rest } };
        }
    };
    return S.parse;
}

/// Map the result of a parser through a function
pub fn map(comptime T: type, comptime U: type, comptime p: Parser(T), comptime f: fn (T) U) Parser(U) {
    const S = struct {
        fn parse(input: []const u8) Result(U) {
            return p(input).map(U, f);
        }
    };
    return S.parse;
}

// ============================================================================
// Hex Color Parser
// ============================================================================

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn eql(self: Color, other: Color) bool {
        return self.r == other.r and self.g == other.g and self.b == other.b;
    }
};

fn hexPairToU8(pair: [2]u8) u8 {
    return (hexCharToValue(pair[0]) << 4) | hexCharToValue(pair[1]);
}

fn hexCharToValue(c: u8) u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => 0,
    };
}

/// Parse two hex digits and convert to u8
const hexByte = map([2]u8, u8, count(2, hexDigit), hexPairToU8);

fn tupleToColor(t: struct { u8, struct { u8, u8 } }) Color {
    return .{ .r = t[0], .g = t[1][0], .b = t[1][1] };
}

/// Parse RGB hex bytes
const hexRgb = map(
    struct { u8, struct { u8, u8 } },
    Color,
    seq(u8, struct { u8, u8 }, hexByte, seq(u8, u8, hexByte, hexByte)),
    tupleToColor,
);

/// Parse hex color with # prefix (e.g., "#FF00AA")
pub const hexColorWithHash = right(u8, Color, char('#'), hexRgb);

/// Parse hex color with or without # prefix
pub const hexColor = alt(Color, hexColorWithHash, hexRgb);

// ============================================================================
// Tests
// ============================================================================

test "satisfy - matches predicate" {
    const result = digit("123");
    try std.testing.expect(result.isOk());
    try std.testing.expectEqual('1', result.ok.value);
    try std.testing.expectEqualStrings("23", result.ok.rest);
}

test "satisfy - fails on non-match" {
    const result = digit("abc");
    try std.testing.expect(result.isErr());
    try std.testing.expectEqualStrings("digit", result.err.expected);
}

test "char - matches specific character" {
    const hash = char('#');
    const result = hash("#abc");
    try std.testing.expect(result.isOk());
    try std.testing.expectEqual('#', result.ok.value);
    try std.testing.expectEqualStrings("abc", result.ok.rest);
}

test "literal - matches string" {
    const rgb = literal("rgb");
    const result = rgb("rgb(255)");
    try std.testing.expect(result.isOk());
    try std.testing.expectEqualStrings("rgb", result.ok.value);
    try std.testing.expectEqualStrings("(255)", result.ok.rest);
}

test "hexDigit - matches hex characters" {
    try std.testing.expect(hexDigit("0").isOk());
    try std.testing.expect(hexDigit("9").isOk());
    try std.testing.expect(hexDigit("a").isOk());
    try std.testing.expect(hexDigit("F").isOk());
    try std.testing.expect(hexDigit("g").isErr());
}

test "count - parses exact repetitions" {
    const twoHex = count(2, hexDigit);
    const result = twoHex("FFabc");
    try std.testing.expect(result.isOk());
    try std.testing.expectEqualStrings("FF", &result.ok.value);
    try std.testing.expectEqualStrings("abc", result.ok.rest);
}

test "hexByte - converts hex pair to u8" {
    const result = hexByte("FF");
    try std.testing.expect(result.isOk());
    try std.testing.expectEqual(255, result.ok.value);

    const result2 = hexByte("00");
    try std.testing.expect(result2.isOk());
    try std.testing.expectEqual(0, result2.ok.value);

    const result3 = hexByte("7f");
    try std.testing.expect(result3.isOk());
    try std.testing.expectEqual(127, result3.ok.value);
}

test "hexColor - parses #RRGGBB format" {
    const result = hexColor("#FF00AA");
    try std.testing.expect(result.isOk());
    try std.testing.expect(result.ok.value.eql(.{ .r = 255, .g = 0, .b = 170 }));
    try std.testing.expectEqualStrings("", result.ok.rest);
}

test "hexColor - parses RRGGBB without hash" {
    const result = hexColor("FF00AA");
    try std.testing.expect(result.isOk());
    try std.testing.expect(result.ok.value.eql(.{ .r = 255, .g = 0, .b = 170 }));
}

test "hexColor - parses lowercase" {
    const result = hexColor("#ff00aa");
    try std.testing.expect(result.isOk());
    try std.testing.expect(result.ok.value.eql(.{ .r = 255, .g = 0, .b = 170 }));
}

test "hexColor - parses mixed case" {
    const result = hexColor("#Ff00Aa");
    try std.testing.expect(result.isOk());
    try std.testing.expect(result.ok.value.eql(.{ .r = 255, .g = 0, .b = 170 }));
}

test "hexColor - parses black" {
    const result = hexColor("#000000");
    try std.testing.expect(result.isOk());
    try std.testing.expect(result.ok.value.eql(.{ .r = 0, .g = 0, .b = 0 }));
}

test "hexColor - parses white" {
    const result = hexColor("#FFFFFF");
    try std.testing.expect(result.isOk());
    try std.testing.expect(result.ok.value.eql(.{ .r = 255, .g = 255, .b = 255 }));
}

test "hexColor - leaves trailing input" {
    const result = hexColor("#FF0000 extra");
    try std.testing.expect(result.isOk());
    try std.testing.expect(result.ok.value.eql(.{ .r = 255, .g = 0, .b = 0 }));
    try std.testing.expectEqualStrings(" extra", result.ok.rest);
}

test "hexColor - fails on invalid input" {
    const result = hexColor("#GG0000");
    try std.testing.expect(result.isErr());
}

test "hexColor - fails on too short" {
    const result = hexColor("#FF00");
    try std.testing.expect(result.isErr());
}

test "alt - tries second parser on failure" {
    const hashOrAt = alt(u8, char('#'), char('@'));
    try std.testing.expect(hashOrAt("#").isOk());
    try std.testing.expect(hashOrAt("@").isOk());
    try std.testing.expect(hashOrAt("x").isErr());
}

test "optional - returns default on failure" {
    const maybeHash = optional(u8, char('#'), 0);
    const r1 = maybeHash("#abc");
    try std.testing.expect(r1.isOk());
    try std.testing.expectEqual('#', r1.ok.value);

    const r2 = maybeHash("abc");
    try std.testing.expect(r2.isOk());
    try std.testing.expectEqual(0, r2.ok.value);
    try std.testing.expectEqualStrings("abc", r2.ok.rest);
}

test "seq - combines two parsers" {
    const hashThenDigit = seq(u8, u8, char('#'), digit);
    const result = hashThenDigit("#5");
    try std.testing.expect(result.isOk());
    try std.testing.expectEqual('#', result.ok.value[0]);
    try std.testing.expectEqual('5', result.ok.value[1]);
}
