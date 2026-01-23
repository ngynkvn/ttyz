//! Input events from the terminal.
//!
//! Events are polled using `Screen.pollEvent()`.

/// Input event from the terminal.
pub const Event = union(enum) {
    /// Keyboard key codes.
    /// Includes ASCII characters, function keys, and navigation keys.
    pub const Key = enum(u8) {
        // zig fmt: off
        backspace = 8, tab = 9,
        enter = 10, esc = 27,
        carriage_return = 13,
        space = 32,

        // Arrow keys (values chosen to not conflict with ASCII)
        arrow_up = 128, arrow_down = 129,
        arrow_right = 130, arrow_left = 131,

        // Navigation keys
        home = 132, end = 133,
        page_up = 134, page_down = 135,
        insert = 136, delete = 137,
        backtab = 138,

        // Function keys
        f1 = 140, f2 = 141, f3 = 142, f4 = 143,
        f5 = 144, f6 = 145, f7 = 146, f8 = 147,
        f9 = 148, f10 = 149, f11 = 150, f12 = 151,

        @"0" = 48, @"1" = 49, @"2" = 50,
        @"3" = 51, @"4" = 52, @"5" = 53,
        @"6" = 54, @"7" = 55, @"8" = 56,
        @"9" = 57,

        A = 65, B = 66, C = 67, D = 68, E = 69, F = 70, G = 71, H = 72,
        I = 73, J = 74, K = 75, L = 76, M = 77, N = 78, O = 79, P = 80,
        Q = 81, R = 82, S = 83, T = 84, U = 85, V = 86, W = 87, X = 88, Y = 89, Z = 90,

        a = 97, b = 98, c = 99, d = 100, e = 101, f = 102, g = 103, h = 104,
        i = 105, j = 106, k = 107, l = 108, m = 109, n = 110, o = 111, p = 112,
        q = 113, r = 114, s = 115, t = 116, u = 117, v = 118, w = 119, x = 120, y = 121, z = 122,
        // zig fmt: on
        _,
        /// Convert arrow key escape sequence suffix to Key.
        /// Returns null for invalid input (only 'A', 'B', 'C', 'D' are valid).
        pub fn arrow(c: u8) ?Key {
            return switch (c) {
                'A' => .arrow_up,
                'B' => .arrow_down,
                'C' => .arrow_right,
                'D' => .arrow_left,
                else => null,
            };
        }

        /// Parse CSI sequence number to navigation/function key
        pub fn fromCsiNum(num: u8, suffix: u8) ?Key {
            // CSI sequences: ESC [ <num> ~
            if (suffix == '~') {
                return switch (num) {
                    1 => .home,
                    2 => .insert,
                    3 => .delete,
                    4 => .end,
                    5 => .page_up,
                    6 => .page_down,
                    11 => .f1,
                    12 => .f2,
                    13 => .f3,
                    14 => .f4,
                    15 => .f5,
                    17 => .f6,
                    18 => .f7,
                    19 => .f8,
                    20 => .f9,
                    21 => .f10,
                    23 => .f11,
                    24 => .f12,
                    else => null,
                };
            }
            return null;
        }
    };

    /// Mouse button identifiers.
    pub const MouseButton = enum { left, middle, right, scroll_up, scroll_down, none, unknown };

    /// State of a mouse button.
    pub const MouseButtonState = enum { pressed, released, motion };

    /// Cursor position in the terminal.
    pub const CursorPos = struct { row: usize, col: usize };

    /// Mouse event data (SGR extended coordinates).
    /// See: https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h3-Extended-coordinates
    pub const Mouse = struct {
        button: MouseButton,
        row: usize,
        col: usize,
        button_state: MouseButtonState,
        /// Shift key was held during the event.
        shift: bool = false,
        /// Meta/Alt key was held during the event.
        meta: bool = false,
        /// Ctrl key was held during the event.
        ctrl: bool = false,

        /// Parse SGR mouse button code into button and modifiers.
        /// Button code format:
        /// - bits 0-1: button (0=left, 1=middle, 2=right)
        /// - bit 2: shift
        /// - bit 3: meta
        /// - bit 4: ctrl
        /// - bit 5: motion
        /// - bits 6-7: scroll wheel (64=up, 65=down)
        pub fn fromButtonCode(code: usize, final: u8) Mouse {
            const is_motion = (code & 32) != 0;
            const is_scroll = (code & 64) != 0;

            const button: MouseButton = if (is_scroll)
                if ((code & 1) != 0) .scroll_down else .scroll_up
            else switch (code & 3) {
                0 => .left,
                1 => .middle,
                2 => .right,
                3 => .none, // release in X10 mode, shouldn't happen in SGR
                else => .unknown,
            };

            const button_state: MouseButtonState = if (is_motion)
                .motion
            else if (final == 'm')
                .released
            else
                .pressed;

            return .{
                .button = button,
                .row = 0,
                .col = 0,
                .button_state = button_state,
                .shift = (code & 4) != 0,
                .meta = (code & 8) != 0,
                .ctrl = (code & 16) != 0,
            };
        }
    };

    /// A key was pressed.
    key: Key,
    /// Response to a cursor position query.
    cursor_pos: CursorPos,
    /// Mouse button or movement event.
    mouse: Mouse,
    /// Terminal focus changed (true = gained focus, false = lost focus).
    focus: bool,
    /// Ctrl+C was pressed.
    interrupt: void,
    /// Terminal window was resized.
    resize: struct { width: u16, height: u16 },
};

const std = @import("std");
const testing = std.testing;

test "Key.arrow - valid arrow keys" {
    try testing.expectEqual(Event.Key.arrow_up, Event.Key.arrow('A').?);
    try testing.expectEqual(Event.Key.arrow_down, Event.Key.arrow('B').?);
    try testing.expectEqual(Event.Key.arrow_right, Event.Key.arrow('C').?);
    try testing.expectEqual(Event.Key.arrow_left, Event.Key.arrow('D').?);
}

test "Key.arrow - invalid input returns null" {
    try testing.expectEqual(@as(?Event.Key, null), Event.Key.arrow('X'));
    try testing.expectEqual(@as(?Event.Key, null), Event.Key.arrow('a'));
    try testing.expectEqual(@as(?Event.Key, null), Event.Key.arrow(0));
}

test "Key.fromCsiNum - navigation keys" {
    try testing.expectEqual(Event.Key.home, Event.Key.fromCsiNum(1, '~').?);
    try testing.expectEqual(Event.Key.insert, Event.Key.fromCsiNum(2, '~').?);
    try testing.expectEqual(Event.Key.delete, Event.Key.fromCsiNum(3, '~').?);
    try testing.expectEqual(Event.Key.end, Event.Key.fromCsiNum(4, '~').?);
    try testing.expectEqual(Event.Key.page_up, Event.Key.fromCsiNum(5, '~').?);
    try testing.expectEqual(Event.Key.page_down, Event.Key.fromCsiNum(6, '~').?);
}

test "Key.fromCsiNum - function keys" {
    try testing.expectEqual(Event.Key.f1, Event.Key.fromCsiNum(11, '~').?);
    try testing.expectEqual(Event.Key.f2, Event.Key.fromCsiNum(12, '~').?);
    try testing.expectEqual(Event.Key.f5, Event.Key.fromCsiNum(15, '~').?);
    try testing.expectEqual(Event.Key.f12, Event.Key.fromCsiNum(24, '~').?);
}

test "Key.fromCsiNum - invalid input returns null" {
    // Wrong suffix
    try testing.expectEqual(@as(?Event.Key, null), Event.Key.fromCsiNum(1, 'A'));
    // Unknown number
    try testing.expectEqual(@as(?Event.Key, null), Event.Key.fromCsiNum(99, '~'));
    try testing.expectEqual(@as(?Event.Key, null), Event.Key.fromCsiNum(0, '~'));
}

test "Mouse.fromButtonCode - basic buttons" {
    // Left button press (code 0, final 'M' = press)
    const left = Event.Mouse.fromButtonCode(0, 'M');
    try testing.expectEqual(Event.MouseButton.left, left.button);
    try testing.expectEqual(Event.MouseButtonState.pressed, left.button_state);

    // Middle button press
    const middle = Event.Mouse.fromButtonCode(1, 'M');
    try testing.expectEqual(Event.MouseButton.middle, middle.button);

    // Right button press
    const right = Event.Mouse.fromButtonCode(2, 'M');
    try testing.expectEqual(Event.MouseButton.right, right.button);
}

test "Mouse.fromButtonCode - button release" {
    // Left button release (code 0, final 'm' = release)
    const released = Event.Mouse.fromButtonCode(0, 'm');
    try testing.expectEqual(Event.MouseButton.left, released.button);
    try testing.expectEqual(Event.MouseButtonState.released, released.button_state);
}

test "Mouse.fromButtonCode - motion" {
    // Motion flag is bit 5 (32)
    const motion = Event.Mouse.fromButtonCode(32, 'M');
    try testing.expectEqual(Event.MouseButtonState.motion, motion.button_state);
}

test "Mouse.fromButtonCode - scroll wheel" {
    // Scroll up is bit 6 (64)
    const scroll_up = Event.Mouse.fromButtonCode(64, 'M');
    try testing.expectEqual(Event.MouseButton.scroll_up, scroll_up.button);

    // Scroll down is bit 6 + bit 0 (65)
    const scroll_down = Event.Mouse.fromButtonCode(65, 'M');
    try testing.expectEqual(Event.MouseButton.scroll_down, scroll_down.button);
}

test "Mouse.fromButtonCode - modifiers" {
    // Shift is bit 2 (4)
    const with_shift = Event.Mouse.fromButtonCode(4, 'M');
    try testing.expect(with_shift.shift);
    try testing.expect(!with_shift.meta);
    try testing.expect(!with_shift.ctrl);

    // Meta/Alt is bit 3 (8)
    const with_meta = Event.Mouse.fromButtonCode(8, 'M');
    try testing.expect(!with_meta.shift);
    try testing.expect(with_meta.meta);

    // Ctrl is bit 4 (16)
    const with_ctrl = Event.Mouse.fromButtonCode(16, 'M');
    try testing.expect(with_ctrl.ctrl);

    // All modifiers: shift + meta + ctrl = 4 + 8 + 16 = 28
    const all_mods = Event.Mouse.fromButtonCode(28, 'M');
    try testing.expect(all_mods.shift);
    try testing.expect(all_mods.meta);
    try testing.expect(all_mods.ctrl);
}
