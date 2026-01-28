//! Comprehensive correctness tests for ttyz library
//!
//! This file contains extensive tests to verify correctness of all modules,
//! including edge cases, boundary conditions, and integration scenarios.

const std = @import("std");
const testing = std.testing;

const ttyz = @import("../ttyz.zig");
const ansi = ttyz.ansi;
const parser = ttyz.parser;
const event = ttyz.event;
const frame = ttyz.frame;

// =============================================================================
// Parser Tests - Edge Cases and Boundary Conditions
// =============================================================================

test "Parser - handles maximum parameters" {
    var p = parser.Parser.init();

    // Build a CSI sequence with max params (16)
    _ = p.advance(0x1B);
    _ = p.advance('[');
    for (0..parser.MAX_PARAMS) |i| {
        // Add parameter value
        _ = p.advance('1');
        // Add separator (except for last)
        if (i < parser.MAX_PARAMS - 1) {
            _ = p.advance(';');
        }
    }
    _ = p.advance('m');

    const params = p.getParams();
    try testing.expectEqual(@as(usize, parser.MAX_PARAMS), params.len);
}

test "Parser - overflow params are ignored" {
    var p = parser.Parser.init();

    // Build a CSI sequence with more than max params
    _ = p.advance(0x1B);
    _ = p.advance('[');
    for (0..parser.MAX_PARAMS + 5) |_| {
        _ = p.advance('1');
        _ = p.advance(';');
    }
    _ = p.advance('m');

    const params = p.getParams();
    // Should cap at MAX_PARAMS
    try testing.expect(params.len <= parser.MAX_PARAMS);
}

test "Parser - parameter value saturation" {
    var p = parser.Parser.init();

    // Parse a very large number that would overflow u16
    for ("\x1b[999999999999999m") |byte| {
        _ = p.advance(byte);
    }

    // Should not panic, value should be saturated
    try testing.expectEqual(parser.State.ground, p.state);
}

test "Parser - empty CSI sequence" {
    var p = parser.Parser.init();

    // Parse "\x1b[m" - no parameters
    for ("\x1b[m") |byte| {
        _ = p.advance(byte);
    }

    try testing.expectEqual(parser.State.ground, p.state);
    try testing.expectEqual(@as(u8, 'm'), p.final_char);
    // Should have no params
    try testing.expectEqual(@as(usize, 0), p.getParams().len);
}

test "Parser - consecutive escape sequences" {
    var p = parser.Parser.init();

    // Parse multiple sequences without explicit reset
    for ("\x1b[1m\x1b[31m\x1b[0m") |byte| {
        _ = p.advance(byte);
    }

    try testing.expectEqual(parser.State.ground, p.state);
    try testing.expectEqual(@as(u8, 'm'), p.final_char);
}

test "Parser - nested/interrupted sequences" {
    var p = parser.Parser.init();

    // Start a CSI, then start another escape
    _ = p.advance(0x1B);
    _ = p.advance('[');
    _ = p.advance('1');
    // Interrupt with new escape
    _ = p.advance(0x1B);

    try testing.expectEqual(parser.State.escape, p.state);
}

test "Parser - all C0 control codes execute" {
    var p = parser.Parser.init();

    const c0_codes = [_]u8{ 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D };
    for (c0_codes) |code| {
        p.reset();
        const action = p.advance(code);
        try testing.expectEqual(@as(?parser.Action, parser.Action.execute), action);
        try testing.expectEqual(parser.State.ground, p.state);
    }
}

test "Parser - 8-bit C1 sequences" {
    var p = parser.Parser.init();

    // 0x9B is 8-bit CSI
    _ = p.advance(0x9B);
    try testing.expectEqual(parser.State.csi_entry, p.state);

    p.reset();

    // 0x90 is 8-bit DCS
    _ = p.advance(0x90);
    try testing.expectEqual(parser.State.dcs_entry, p.state);

    p.reset();

    // 0x9D is 8-bit OSC
    _ = p.advance(0x9D);
    try testing.expectEqual(parser.State.osc_string, p.state);
}

test "Parser - OSC max length handling" {
    var p = parser.Parser.init();

    // Start OSC
    _ = p.advance(0x1B);
    _ = p.advance(']');

    // Fill with data up to and beyond max
    for (0..parser.MAX_OSC_LEN + 10) |_| {
        _ = p.advance('a');
    }

    // OSC data should be capped at MAX_OSC_LEN
    try testing.expect(p.getOscData().len <= parser.MAX_OSC_LEN);
}

test "Parser - intermediate characters" {
    var p = parser.Parser.init();

    // CSI with intermediates: \x1b[?25l (DECTCEM)
    for ("\x1b[?25l") |byte| {
        _ = p.advance(byte);
    }

    try testing.expectEqual(@as(u8, '?'), p.private_marker);
    try testing.expectEqual(@as(u8, 'l'), p.final_char);
}

test "Parser - getParam with defaults" {
    var p = parser.Parser.init();

    // Parse "\x1b[H" - cursor home with default params
    for ("\x1b[H") |byte| {
        _ = p.advance(byte);
    }

    // Both params default to 1
    try testing.expectEqual(@as(u16, 1), p.getParam(0, 1));
    try testing.expectEqual(@as(u16, 1), p.getParam(1, 1));
    try testing.expectEqual(@as(u16, 99), p.getParam(5, 99)); // out of bounds
}

// =============================================================================
// Event Tests - Edge Cases
// =============================================================================

test "Event.Key - all arrow keys" {
    try testing.expectEqual(event.Event.Key.arrow_up, event.Event.Key.arrow('A').?);
    try testing.expectEqual(event.Event.Key.arrow_down, event.Event.Key.arrow('B').?);
    try testing.expectEqual(event.Event.Key.arrow_right, event.Event.Key.arrow('C').?);
    try testing.expectEqual(event.Event.Key.arrow_left, event.Event.Key.arrow('D').?);

    // Invalid codes
    try testing.expectEqual(@as(?event.Event.Key, null), event.Event.Key.arrow('E'));
    try testing.expectEqual(@as(?event.Event.Key, null), event.Event.Key.arrow('Z'));
    try testing.expectEqual(@as(?event.Event.Key, null), event.Event.Key.arrow(0));
    try testing.expectEqual(@as(?event.Event.Key, null), event.Event.Key.arrow(255));
}

test "Event.Key - all function keys" {
    const fkeys = [_]struct { num: u8, key: event.Event.Key }{
        .{ .num = 11, .key = .f1 },
        .{ .num = 12, .key = .f2 },
        .{ .num = 13, .key = .f3 },
        .{ .num = 14, .key = .f4 },
        .{ .num = 15, .key = .f5 },
        .{ .num = 17, .key = .f6 },
        .{ .num = 18, .key = .f7 },
        .{ .num = 19, .key = .f8 },
        .{ .num = 20, .key = .f9 },
        .{ .num = 21, .key = .f10 },
        .{ .num = 23, .key = .f11 },
        .{ .num = 24, .key = .f12 },
    };

    for (fkeys) |fk| {
        const key = event.Event.Key.fromCsiNum(fk.num, '~');
        try testing.expectEqual(fk.key, key.?);
    }
}

test "Event.Key - navigation keys" {
    const nav_keys = [_]struct { num: u8, key: event.Event.Key }{
        .{ .num = 1, .key = .home },
        .{ .num = 2, .key = .insert },
        .{ .num = 3, .key = .delete },
        .{ .num = 4, .key = .end },
        .{ .num = 5, .key = .page_up },
        .{ .num = 6, .key = .page_down },
    };

    for (nav_keys) |nk| {
        const key = event.Event.Key.fromCsiNum(nk.num, '~');
        try testing.expectEqual(nk.key, key.?);
    }
}

test "Event.Mouse - all modifier combinations" {
    // Test all 8 combinations of shift/meta/ctrl
    for (0..8) |combo| {
        const shift_mask: usize = if (combo & 1 != 0) 4 else 0;
        const meta_mask: usize = if (combo & 2 != 0) 8 else 0;
        const ctrl_mask: usize = if (combo & 4 != 0) 16 else 0;
        const code = shift_mask | meta_mask | ctrl_mask;

        const mouse = event.Event.Mouse.fromButtonCode(code, 'M');

        try testing.expectEqual(combo & 1 != 0, mouse.shift);
        try testing.expectEqual(combo & 2 != 0, mouse.meta);
        try testing.expectEqual(combo & 4 != 0, mouse.ctrl);
    }
}

test "Event.Mouse - button states" {
    // Press
    const press = event.Event.Mouse.fromButtonCode(0, 'M');
    try testing.expectEqual(event.Event.MouseButtonState.pressed, press.button_state);

    // Release
    const release = event.Event.Mouse.fromButtonCode(0, 'm');
    try testing.expectEqual(event.Event.MouseButtonState.released, release.button_state);

    // Motion (bit 5 = 32)
    const motion = event.Event.Mouse.fromButtonCode(32, 'M');
    try testing.expectEqual(event.Event.MouseButtonState.motion, motion.button_state);
}

// =============================================================================
// Layout Tests - Edge Cases
// =============================================================================

test "Layout - single constraint" {
    const layout = frame.Layout(1).vertical(.{.{ .fill = 1 }});
    const result = layout.areas(frame.Rect.sized(80, 24));

    try testing.expectEqual(@as(u16, 0), result[0].x);
    try testing.expectEqual(@as(u16, 0), result[0].y);
    try testing.expectEqual(@as(u16, 80), result[0].width);
    try testing.expectEqual(@as(u16, 24), result[0].height);
}

test "Layout - all length constraints" {
    const layout = frame.Layout(3).vertical(.{
        .{ .length = 10 },
        .{ .length = 10 },
        .{ .length = 10 },
    });
    const result = layout.areas(frame.Rect.sized(80, 30));

    try testing.expectEqual(@as(u16, 10), result[0].height);
    try testing.expectEqual(@as(u16, 10), result[1].height);
    try testing.expectEqual(@as(u16, 10), result[2].height);
}

test "Layout - weighted fills" {
    const layout = frame.Layout(3).horizontal(.{
        .{ .fill = 1 },
        .{ .fill = 2 },
        .{ .fill = 1 },
    });
    const result = layout.areas(frame.Rect.sized(100, 24));

    // 1:2:1 ratio of 100 = 25:50:25
    try testing.expectEqual(@as(u16, 25), result[0].width);
    try testing.expectEqual(@as(u16, 50), result[1].width);
    try testing.expectEqual(@as(u16, 25), result[2].width);
}

test "Layout - percentage constraints" {
    const layout = frame.Layout(4).vertical(.{
        .{ .percentage = 10 },
        .{ .percentage = 20 },
        .{ .percentage = 30 },
        .{ .percentage = 40 },
    });
    const result = layout.areas(frame.Rect.sized(80, 100));

    try testing.expectEqual(@as(u16, 10), result[0].height);
    try testing.expectEqual(@as(u16, 20), result[1].height);
    try testing.expectEqual(@as(u16, 30), result[2].height);
    try testing.expectEqual(@as(u16, 40), result[3].height);
}

test "Layout - mixed constraints" {
    const layout = frame.Layout(3).vertical(.{
        .{ .length = 3 },
        .{ .fill = 1 },
        .{ .length = 1 },
    });
    const result = layout.areas(frame.Rect.sized(80, 24));

    try testing.expectEqual(@as(u16, 3), result[0].height);
    try testing.expectEqual(@as(u16, 20), result[1].height); // 24 - 3 - 1 = 20
    try testing.expectEqual(@as(u16, 1), result[2].height);
}

test "Layout - spacing between areas" {
    const layout = frame.Layout(3).horizontal(.{
        .{ .fill = 1 },
        .{ .fill = 1 },
        .{ .fill = 1 },
    }).withSpacing(2);
    const result = layout.areas(frame.Rect.sized(100, 24));

    // 100 - (2*2 spacing) = 96 / 3 = 32 each
    try testing.expectEqual(@as(u16, 32), result[0].width);
    try testing.expectEqual(@as(u16, 34), result[1].x); // 32 + 2 spacing
    try testing.expectEqual(@as(u16, 32), result[1].width);
    try testing.expectEqual(@as(u16, 68), result[2].x); // 34 + 32 + 2
}

test "Layout - zero-size area" {
    const layout = frame.Layout(1).vertical(.{.{ .fill = 1 }});
    const result = layout.areas(frame.Rect.sized(0, 0));

    try testing.expectEqual(@as(u16, 0), result[0].width);
    try testing.expectEqual(@as(u16, 0), result[0].height);
}

test "Layout - ratio constraints" {
    const layout = frame.Layout(2).horizontal(.{
        .{ .ratio = .{ .num = 1, .den = 3 } },
        .{ .ratio = .{ .num = 2, .den = 3 } },
    });
    const result = layout.areas(frame.Rect.sized(90, 24));

    try testing.expectEqual(@as(u16, 30), result[0].width);
    try testing.expectEqual(@as(u16, 60), result[1].width);
}

// =============================================================================
// Rect Tests - Edge Cases
// =============================================================================

test "Rect - contains boundary conditions" {
    const rect = frame.Rect{ .x = 10, .y = 20, .width = 30, .height = 40 };

    // Top-left corner (inclusive)
    try testing.expect(rect.contains(10, 20));
    // Just inside bottom-right (exclusive)
    try testing.expect(rect.contains(39, 59));
    // Just outside bounds
    try testing.expect(!rect.contains(40, 59));
    try testing.expect(!rect.contains(39, 60));
    try testing.expect(!rect.contains(9, 20));
    try testing.expect(!rect.contains(10, 19));
}

test "Rect - intersect non-overlapping" {
    const r1 = frame.Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    const r2 = frame.Rect{ .x = 20, .y = 20, .width = 10, .height = 10 };

    try testing.expectEqual(@as(?frame.Rect, null), r1.intersect(r2));
}

test "Rect - intersect touching edges" {
    const r1 = frame.Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    const r2 = frame.Rect{ .x = 10, .y = 0, .width = 10, .height = 10 };

    // Edges touch but don't overlap
    try testing.expectEqual(@as(?frame.Rect, null), r1.intersect(r2));
}

test "Rect - intersect one inside other" {
    const outer = frame.Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };
    const inner = frame.Rect{ .x = 10, .y = 10, .width = 20, .height = 20 };

    const result = outer.intersect(inner).?;
    try testing.expectEqual(@as(u16, 10), result.x);
    try testing.expectEqual(@as(u16, 10), result.y);
    try testing.expectEqual(@as(u16, 20), result.width);
    try testing.expectEqual(@as(u16, 20), result.height);
}

test "Rect - inner with large margin" {
    const rect = frame.Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };

    // Margin larger than half dimensions results in zero-size rect
    const result = rect.inner(10);
    try testing.expectEqual(@as(u16, 0), result.width);
    try testing.expectEqual(@as(u16, 0), result.height);
}

test "Rect - right and bottom with overflow protection" {
    const rect = frame.Rect{
        .x = std.math.maxInt(u16) - 5,
        .y = std.math.maxInt(u16) - 5,
        .width = 100,
        .height = 100,
    };

    // Should saturate at max value
    try testing.expectEqual(std.math.maxInt(u16), rect.right());
    try testing.expectEqual(std.math.maxInt(u16), rect.bottom());
}

test "Rect - area calculation" {
    const rect = frame.Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    try testing.expectEqual(@as(u32, 5000), rect.area());
}

test "Rect - isEmpty" {
    try testing.expect(frame.Rect.sized(0, 10).isEmpty());
    try testing.expect(frame.Rect.sized(10, 0).isEmpty());
    try testing.expect(frame.Rect.sized(0, 0).isEmpty());
    try testing.expect(!frame.Rect.sized(1, 1).isEmpty());
}

// =============================================================================
// Buffer Tests - Edge Cases
// =============================================================================

test "Buffer - set and get all positions" {
    var buffer = try frame.Buffer.init(testing.allocator, 10, 10);
    defer buffer.deinit();

    // Set every cell
    for (0..10) |y| {
        for (0..10) |x| {
            const char: u21 = @intCast('A' + @as(u21, @intCast(x + y * 10)) % 26);
            buffer.set(@intCast(x), @intCast(y), .{ .char = char });
        }
    }

    // Verify every cell
    for (0..10) |y| {
        for (0..10) |x| {
            const expected: u21 = @intCast('A' + @as(u21, @intCast(x + y * 10)) % 26);
            const cell = buffer.get(@intCast(x), @intCast(y));
            try testing.expectEqual(expected, cell.char);
        }
    }
}

test "Buffer - out of bounds returns default" {
    var buffer = try frame.Buffer.init(testing.allocator, 10, 10);
    defer buffer.deinit();

    const default = buffer.get(100, 100);
    try testing.expectEqual(@as(u21, ' '), default.char);
    try testing.expect(default.fg.eql(frame.Color.default));
    try testing.expect(default.bg.eql(frame.Color.default));
}

test "Buffer - out of bounds set is no-op" {
    var buffer = try frame.Buffer.init(testing.allocator, 10, 10);
    defer buffer.deinit();

    // Should not crash
    buffer.set(100, 100, .{ .char = 'X' });
    buffer.set(std.math.maxInt(u16), std.math.maxInt(u16), .{ .char = 'Y' });
}

test "Buffer - clear resets all cells" {
    var buffer = try frame.Buffer.init(testing.allocator, 10, 10);
    defer buffer.deinit();

    // Set some cells
    buffer.set(5, 5, .{ .char = 'X', .fg = frame.Color.red });

    // Clear
    buffer.clear();

    // Verify cleared
    const cell = buffer.get(5, 5);
    try testing.expectEqual(@as(u21, ' '), cell.char);
    try testing.expect(cell.fg.eql(frame.Color.default));
}

test "Buffer - resize clears content" {
    var buffer = try frame.Buffer.init(testing.allocator, 10, 10);
    defer buffer.deinit();

    buffer.set(5, 5, .{ .char = 'X' });
    try buffer.resize(20, 20);

    // Old position should be cleared
    const cell = buffer.get(5, 5);
    try testing.expectEqual(@as(u21, ' '), cell.char);
}

test "Buffer - area returns correct rect" {
    var buffer = try frame.Buffer.init(testing.allocator, 80, 24);
    defer buffer.deinit();

    const area = buffer.area();
    try testing.expectEqual(@as(u16, 0), area.x);
    try testing.expectEqual(@as(u16, 0), area.y);
    try testing.expectEqual(@as(u16, 80), area.width);
    try testing.expectEqual(@as(u16, 24), area.height);
}

// =============================================================================
// Frame Tests - Drawing Operations
// =============================================================================

test "Frame - setString clips to width" {
    var buffer = try frame.Buffer.init(testing.allocator, 10, 10);
    defer buffer.deinit();

    var f = frame.Frame.init(&buffer);
    f.setString(5, 0, "Hello World", .{}, .default, .default);

    // Only first 5 chars should fit (10 - 5 = 5)
    try testing.expectEqual(@as(u21, 'H'), buffer.get(5, 0).char);
    try testing.expectEqual(@as(u21, 'e'), buffer.get(6, 0).char);
    try testing.expectEqual(@as(u21, 'l'), buffer.get(7, 0).char);
    try testing.expectEqual(@as(u21, 'l'), buffer.get(8, 0).char);
    try testing.expectEqual(@as(u21, 'o'), buffer.get(9, 0).char);
}

test "Frame - fillRect clips to bounds" {
    var buffer = try frame.Buffer.init(testing.allocator, 10, 10);
    defer buffer.deinit();

    var f = frame.Frame.init(&buffer);
    // Fill rect that extends beyond buffer
    f.fillRect(frame.Rect{ .x = 5, .y = 5, .width = 100, .height = 100 }, .{ .char = 'X' });

    // Should only fill within bounds
    try testing.expectEqual(@as(u21, 'X'), buffer.get(9, 9).char);
    // Outside original rect should still be default
    try testing.expectEqual(@as(u21, ' '), buffer.get(0, 0).char);
}

test "Frame - drawRect with minimum size" {
    var buffer = try frame.Buffer.init(testing.allocator, 10, 10);
    defer buffer.deinit();

    var f = frame.Frame.init(&buffer);
    // Minimum size rect (2x2)
    f.drawRect(frame.Rect{ .x = 0, .y = 0, .width = 2, .height = 2 }, .single);

    // All 4 corners should be set
    try testing.expectEqual(@as(u21, '┌'), buffer.get(0, 0).char);
    try testing.expectEqual(@as(u21, '┐'), buffer.get(1, 0).char);
    try testing.expectEqual(@as(u21, '└'), buffer.get(0, 1).char);
    try testing.expectEqual(@as(u21, '┘'), buffer.get(1, 1).char);
}

test "Frame - drawRect too small is no-op" {
    var buffer = try frame.Buffer.init(testing.allocator, 10, 10);
    defer buffer.deinit();

    var f = frame.Frame.init(&buffer);
    // Try to draw 1x1 rect (too small)
    f.drawRect(frame.Rect{ .x = 0, .y = 0, .width = 1, .height = 1 }, .single);

    // Should not have drawn anything
    try testing.expectEqual(@as(u21, ' '), buffer.get(0, 0).char);
}

test "Frame - hline and vline" {
    var buffer = try frame.Buffer.init(testing.allocator, 20, 20);
    defer buffer.deinit();

    var f = frame.Frame.init(&buffer);
    f.hline(0, 5, 10, '-', .{}, .default, .default);
    f.vline(5, 0, 10, '|', .{}, .default, .default);

    // Check horizontal line
    for (0..10) |x| {
        const cell = buffer.get(@intCast(x), 5);
        if (x == 5) {
            // Intersection point - last write wins (vline)
            try testing.expectEqual(@as(u21, '|'), cell.char);
        } else {
            try testing.expectEqual(@as(u21, '-'), cell.char);
        }
    }

    // Check vertical line
    for (0..10) |y| {
        const cell = buffer.get(5, @intCast(y));
        try testing.expectEqual(@as(u21, '|'), cell.char);
    }
}

test "Frame - border styles" {
    var buffer = try frame.Buffer.init(testing.allocator, 20, 10);
    defer buffer.deinit();

    var f = frame.Frame.init(&buffer);

    const styles = [_]frame.BorderStyle{ .single, .double, .rounded, .thick };
    const expected_corners = [_][4]u21{
        .{ '┌', '┐', '└', '┘' }, // single
        .{ '╔', '╗', '╚', '╝' }, // double
        .{ '╭', '╮', '╰', '╯' }, // rounded
        .{ '┏', '┓', '┗', '┛' }, // thick
    };

    for (styles, 0..) |style, i| {
        buffer.clear();
        f.drawRect(frame.Rect{ .x = 0, .y = 0, .width = 5, .height = 3 }, style);

        try testing.expectEqual(expected_corners[i][0], buffer.get(0, 0).char);
        try testing.expectEqual(expected_corners[i][1], buffer.get(4, 0).char);
        try testing.expectEqual(expected_corners[i][2], buffer.get(0, 2).char);
        try testing.expectEqual(expected_corners[i][3], buffer.get(4, 2).char);
    }
}

// =============================================================================
// Color and Style Tests
// =============================================================================

test "Color equality" {
    // Default colors
    const default1: frame.Color = .default;
    const default2: frame.Color = .default;
    try testing.expect(default1.eql(default2));

    // Indexed colors
    try testing.expect(frame.Color.red.eql(.{ .indexed = 1 }));
    try testing.expect(!frame.Color.red.eql(frame.Color.blue));

    // RGB colors
    const rgb1 = frame.Color.fromRgb(255, 128, 64);
    const rgb2 = frame.Color.fromRgb(255, 128, 64);
    const rgb3 = frame.Color.fromRgb(255, 128, 65);

    try testing.expect(rgb1.eql(rgb2));
    try testing.expect(!rgb1.eql(rgb3));

    // Different types
    try testing.expect(!frame.Color.red.eql(.default));
    try testing.expect(!rgb1.eql(frame.Color.red));
}

test "Style equality and attributes" {
    const s1 = frame.Style{ .bold = true, .italic = true };
    const s2 = frame.Style{ .bold = true, .italic = true };
    const s3 = frame.Style{ .bold = true };

    try testing.expect(s1.eql(s2));
    try testing.expect(!s1.eql(s3));

    // hasAttributes
    try testing.expect(s1.hasAttributes());
    try testing.expect(!(frame.Style{}).hasAttributes());
}

test "Cell equality" {
    const c1 = frame.Cell{ .char = 'A', .fg = frame.Color.red, .style = .{ .bold = true } };
    const c2 = frame.Cell{ .char = 'A', .fg = frame.Color.red, .style = .{ .bold = true } };
    const c3 = frame.Cell{ .char = 'B', .fg = frame.Color.red, .style = .{ .bold = true } };
    const c4 = frame.Cell{ .char = 'A', .fg = frame.Color.blue, .style = .{ .bold = true } };

    try testing.expect(c1.eql(c2));
    try testing.expect(!c1.eql(c3));
    try testing.expect(!c1.eql(c4));
}

// =============================================================================
// ANSI Module Tests
// =============================================================================

test "ANSI - RGBColor.fromHex" {
    // With hash
    const c1 = ansi.RGBColor.fromHex("#FF5733").?;
    try testing.expectEqual(@as(u8, 0xFF), c1.r);
    try testing.expectEqual(@as(u8, 0x57), c1.g);
    try testing.expectEqual(@as(u8, 0x33), c1.b);

    // Without hash
    const c2 = ansi.RGBColor.fromHex("00FF00").?;
    try testing.expectEqual(@as(u8, 0x00), c2.r);
    try testing.expectEqual(@as(u8, 0xFF), c2.g);
    try testing.expectEqual(@as(u8, 0x00), c2.b);

    // Invalid inputs
    try testing.expectEqual(@as(?ansi.RGBColor, null), ansi.RGBColor.fromHex(""));
    try testing.expectEqual(@as(?ansi.RGBColor, null), ansi.RGBColor.fromHex("#FFF"));
    try testing.expectEqual(@as(?ansi.RGBColor, null), ansi.RGBColor.fromHex("GGGGGG"));
    try testing.expectEqual(@as(?ansi.RGBColor, null), ansi.RGBColor.fromHex("#FFFFFFFF"));
}

test "ANSI - stringWidth ignores escape sequences" {
    // Plain text
    try testing.expectEqual(@as(usize, 5), ansi.stringWidth("Hello"));

    // With color codes
    try testing.expectEqual(@as(usize, 5), ansi.stringWidth("\x1b[31mHello\x1b[0m"));
    try testing.expectEqual(@as(usize, 5), ansi.stringWidth("\x1b[1;34mHello\x1b[0m"));

    // Multiple sequences
    try testing.expectEqual(@as(usize, 10), ansi.stringWidth("\x1b[31mHello\x1b[0m\x1b[32mWorld\x1b[0m"));

    // Control characters have no width
    try testing.expectEqual(@as(usize, 5), ansi.stringWidth("Hello\n"));
}

test "ANSI - strip removes escape sequences" {
    const allocator = testing.allocator;

    const s1 = try ansi.strip(allocator, "\x1b[31mHello\x1b[0m");
    defer allocator.free(s1);
    try testing.expectEqualStrings("Hello", s1);

    const s2 = try ansi.strip(allocator, "No escapes");
    defer allocator.free(s2);
    try testing.expectEqualStrings("No escapes", s2);

    const s3 = try ansi.strip(allocator, "\x1b[1;2;3;4mComplex\x1b[0m");
    defer allocator.free(s3);
    try testing.expectEqualStrings("Complex", s3);
}

test "ANSI - String builder comptime" {
    // Basic styles
    try testing.expectEqualStrings("\x1b[1mBold\x1b[0m", comptime ansi.str("Bold").bold().done());
    try testing.expectEqualStrings("\x1b[3mItalic\x1b[0m", comptime ansi.str("Italic").italic().done());
    try testing.expectEqualStrings("\x1b[4mUnder\x1b[0m", comptime ansi.str("Under").underline().done());

    // Colors
    try testing.expectEqualStrings("\x1b[31mRed\x1b[0m", comptime ansi.str("Red").fg(.red).done());
    try testing.expectEqualStrings("\x1b[42mBg\x1b[0m", comptime ansi.str("Bg").bg(.green).done());

    // Combinations
    const combined = comptime ansi.str("Test").bold().fg(.cyan).bg(.black).done();
    try testing.expect(std.mem.indexOf(u8, combined, "\x1b[1m") != null);
    try testing.expect(std.mem.indexOf(u8, combined, "\x1b[36m") != null);
    try testing.expect(std.mem.indexOf(u8, combined, "\x1b[40m") != null);

    // Raw (no reset)
    try testing.expectEqualStrings("\x1b[31mtext", comptime ansi.str("text").fg(.red).raw());
}

test "ANSI - cursor movement functions" {
    var buf: [32]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try ansi.cursor.up(&writer, 5);
    try testing.expectEqualStrings("\x1b[5A", writer.buffered());

    writer.end = 0;
    try ansi.cursor.down(&writer, 3);
    try testing.expectEqualStrings("\x1b[3B", writer.buffered());

    writer.end = 0;
    try ansi.cursor.forward(&writer, 10);
    try testing.expectEqualStrings("\x1b[10C", writer.buffered());

    writer.end = 0;
    try ansi.cursor.backward(&writer, 2);
    try testing.expectEqualStrings("\x1b[2D", writer.buffered());

    writer.end = 0;
    try ansi.cursor.toPos(&writer, 10, 20);
    try testing.expectEqualStrings("\x1b[10;20H", writer.buffered());
}

// =============================================================================
// TestBackend Tests
// =============================================================================

test "TestBackend - basic write and read" {
    const allocator = testing.allocator;
    var backend = ttyz.TestBackend.init(allocator, 80, 24);
    defer backend.deinit();

    _ = try backend.write("Hello");
    _ = try backend.write(", World!");

    try testing.expectEqualStrings("Hello, World!", backend.getOutput());
}

test "TestBackend - clear output" {
    const allocator = testing.allocator;
    var backend = ttyz.TestBackend.init(allocator, 80, 24);
    defer backend.deinit();

    _ = try backend.write("Hello");
    backend.clearOutput();

    try testing.expectEqualStrings("", backend.getOutput());
}

test "TestBackend - dimensions" {
    const allocator = testing.allocator;

    var b1 = ttyz.TestBackend.init(allocator, 80, 24);
    defer b1.deinit();
    var size = b1.getSize();
    try testing.expectEqual(@as(u16, 80), size.width);
    try testing.expectEqual(@as(u16, 24), size.height);

    var b2 = ttyz.TestBackend.init(allocator, 120, 40);
    defer b2.deinit();
    size = b2.getSize();
    try testing.expectEqual(@as(u16, 120), size.width);
    try testing.expectEqual(@as(u16, 40), size.height);
}

// =============================================================================
// Integration Tests
// =============================================================================

test "Integration - Frame rendering captures output" {
    const allocator = testing.allocator;

    var capture = try ttyz.TestCapture.init(allocator, 80, 24);
    defer capture.deinit();

    var buffer = try frame.Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    var f = frame.Frame.init(&buffer);
    f.clear();
    f.setString(0, 0, "Test Output", .{}, .default, .default);
    f.drawRect(frame.Rect{ .x = 0, .y = 1, .width = 20, .height = 5 }, .single);

    try f.render(capture.screen());
    try capture.screen().flush();

    try testing.expect(capture.contains("Test Output"));
    try testing.expect(capture.contains("┌")); // Box corner
}

test "Integration - Layout with Frame" {
    const allocator = testing.allocator;

    var buffer = try frame.Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    var f = frame.Frame.init(&buffer);

    // Use layout to split into header/content/footer
    const header, const content, const footer = f.areas(3, frame.Layout(3).vertical(.{
        .{ .length = 3 },
        .{ .fill = 1 },
        .{ .length = 1 },
    }));

    // Verify layout dimensions
    try testing.expectEqual(@as(u16, 3), header.height);
    try testing.expectEqual(@as(u16, 20), content.height); // 24 - 3 - 1
    try testing.expectEqual(@as(u16, 1), footer.height);
    try testing.expectEqual(@as(u16, 80), header.width);
}

test "Integration - Event queue operations" {
    const allocator = testing.allocator;

    var backend = ttyz.TestBackend.init(allocator, 80, 24);
    defer backend.deinit();

    var events_buf: [8]event.Event = undefined;
    var textinput_buf: [16]u8 = undefined;
    var writer_buf: [64]u8 = undefined;

    var screen = try ttyz.Screen.initTest(&backend, .{
        .events = &events_buf,
        .textinput = &textinput_buf,
        .writer = &writer_buf,
        .alt_screen = false,
        .hide_cursor = false,
        .mouse_tracking = false,
    });
    defer _ = screen.deinit() catch {};

    // Queue multiple events
    screen.pushEvent(.{ .key = .a });
    screen.pushEvent(.{ .key = .b });
    screen.pushEvent(.{ .key = .c });
    screen.pushEvent(.interrupt);

    // Poll them in order
    try testing.expectEqual(event.Event.Key.a, screen.pollEvent().?.key);
    try testing.expectEqual(event.Event.Key.b, screen.pollEvent().?.key);
    try testing.expectEqual(event.Event.Key.c, screen.pollEvent().?.key);
    try testing.expect(screen.pollEvent().? == .interrupt);
    try testing.expectEqual(@as(?event.Event, null), screen.pollEvent());
}

test "Integration - complex layout nesting" {
    const allocator = testing.allocator;

    var buffer = try frame.Buffer.init(allocator, 100, 50);
    defer buffer.deinit();

    // Split vertically first
    const v_layout = frame.Layout(2).vertical(.{
        .{ .length = 5 },
        .{ .fill = 1 },
    });
    const top, const bottom = v_layout.areas(buffer.area());

    try testing.expectEqual(@as(u16, 5), top.height);
    try testing.expectEqual(@as(u16, 45), bottom.height);

    // Split bottom horizontally
    const h_layout = frame.Layout(3).horizontal(.{
        .{ .length = 20 },
        .{ .fill = 1 },
        .{ .length = 20 },
    });
    const left, const middle, const right = h_layout.areas(bottom);

    try testing.expectEqual(@as(u16, 20), left.width);
    try testing.expectEqual(@as(u16, 60), middle.width);
    try testing.expectEqual(@as(u16, 20), right.width);
}
