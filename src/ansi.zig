//! ANSI escape sequence library based on ECMA-48.
//! Provides functions for terminal manipulation, text styling, and color support.

const std = @import("std");

pub const parser = @import("parser.zig");

// =============================================================================
// C0 Control Characters
// =============================================================================

pub const C0 = struct {
    pub const NUL: u8 = 0x00; // Null
    pub const SOH: u8 = 0x01; // Start of Heading
    pub const STX: u8 = 0x02; // Start of Text
    pub const ETX: u8 = 0x03; // End of Text
    pub const EOT: u8 = 0x04; // End of Transmission
    pub const ENQ: u8 = 0x05; // Enquiry
    pub const ACK: u8 = 0x06; // Acknowledge
    pub const BEL: u8 = 0x07; // Bell
    pub const BS: u8 = 0x08; // Backspace
    pub const HT: u8 = 0x09; // Horizontal Tab
    pub const LF: u8 = 0x0A; // Line Feed
    pub const VT: u8 = 0x0B; // Vertical Tab
    pub const FF: u8 = 0x0C; // Form Feed
    pub const CR: u8 = 0x0D; // Carriage Return
    pub const SO: u8 = 0x0E; // Shift Out
    pub const SI: u8 = 0x0F; // Shift In
    pub const DLE: u8 = 0x10; // Data Link Escape
    pub const DC1: u8 = 0x11; // Device Control 1 (XON)
    pub const DC2: u8 = 0x12; // Device Control 2
    pub const DC3: u8 = 0x13; // Device Control 3 (XOFF)
    pub const DC4: u8 = 0x14; // Device Control 4
    pub const NAK: u8 = 0x15; // Negative Acknowledge
    pub const SYN: u8 = 0x16; // Synchronous Idle
    pub const ETB: u8 = 0x17; // End of Transmission Block
    pub const CAN: u8 = 0x18; // Cancel
    pub const EM: u8 = 0x19; // End of Medium
    pub const SUB: u8 = 0x1A; // Substitute
    pub const ESC: u8 = 0x1B; // Escape
    pub const FS: u8 = 0x1C; // File Separator
    pub const GS: u8 = 0x1D; // Group Separator
    pub const RS: u8 = 0x1E; // Record Separator
    pub const US: u8 = 0x1F; // Unit Separator
    pub const SP: u8 = 0x20; // Space
    pub const DEL: u8 = 0x7F; // Delete
};

// =============================================================================
// C1 Control Characters (8-bit)
// =============================================================================

pub const C1 = struct {
    pub const PAD: u8 = 0x80; // Padding Character
    pub const HOP: u8 = 0x81; // High Octet Preset
    pub const BPH: u8 = 0x82; // Break Permitted Here
    pub const NBH: u8 = 0x83; // No Break Here
    pub const IND: u8 = 0x84; // Index
    pub const NEL: u8 = 0x85; // Next Line
    pub const SSA: u8 = 0x86; // Start of Selected Area
    pub const ESA: u8 = 0x87; // End of Selected Area
    pub const HTS: u8 = 0x88; // Horizontal Tab Set
    pub const HTJ: u8 = 0x89; // Horizontal Tab with Justification
    pub const VTS: u8 = 0x8A; // Vertical Tab Set
    pub const PLD: u8 = 0x8B; // Partial Line Down
    pub const PLU: u8 = 0x8C; // Partial Line Up
    pub const RI: u8 = 0x8D; // Reverse Index
    pub const SS2: u8 = 0x8E; // Single Shift 2
    pub const SS3: u8 = 0x8F; // Single Shift 3
    pub const DCS: u8 = 0x90; // Device Control String
    pub const PU1: u8 = 0x91; // Private Use 1
    pub const PU2: u8 = 0x92; // Private Use 2
    pub const STS: u8 = 0x93; // Set Transmit State
    pub const CCH: u8 = 0x94; // Cancel Character
    pub const MW: u8 = 0x95; // Message Waiting
    pub const SPA: u8 = 0x96; // Start of Protected Area
    pub const EPA: u8 = 0x97; // End of Protected Area
    pub const SOS: u8 = 0x98; // Start of String
    pub const SGCI: u8 = 0x99; // Single Graphic Character Introducer
    pub const SCI: u8 = 0x9A; // Single Character Introducer
    pub const CSI: u8 = 0x9B; // Control Sequence Introducer
    pub const ST: u8 = 0x9C; // String Terminator
    pub const OSC: u8 = 0x9D; // Operating System Command
    pub const PM: u8 = 0x9E; // Privacy Message
    pub const APC: u8 = 0x9F; // Application Program Command
};

// =============================================================================
// Escape Sequence Prefixes
// =============================================================================

/// ESC [
pub const CSI = "\x1b[";
/// ESC ]
pub const OSC = "\x1b]";
/// ESC P
pub const DCS = "\x1bP";
/// ESC \
pub const ST = "\x1b\\";
/// BEL (used as string terminator in some terminals)
pub const BEL = "\x07";

// =============================================================================
// SGR (Select Graphic Rendition) Attributes
// =============================================================================

pub const Attr = enum(u8) {
    reset = 0,
    bold = 1,
    faint = 2,
    italic = 3,
    underline = 4,
    slow_blink = 5,
    rapid_blink = 6,
    reverse = 7,
    conceal = 8,
    crossed_out = 9,
    default_font = 10,
    alt_font_1 = 11,
    alt_font_2 = 12,
    alt_font_3 = 13,
    alt_font_4 = 14,
    alt_font_5 = 15,
    alt_font_6 = 16,
    alt_font_7 = 17,
    alt_font_8 = 18,
    alt_font_9 = 19,
    fraktur = 20,
    double_underline = 21,
    normal_intensity = 22,
    no_italic = 23,
    no_underline = 24,
    no_blink = 25,
    proportional_spacing = 26,
    no_reverse = 27,
    no_conceal = 28,
    no_crossed_out = 29,
    fg_black = 30,
    fg_red = 31,
    fg_green = 32,
    fg_yellow = 33,
    fg_blue = 34,
    fg_magenta = 35,
    fg_cyan = 36,
    fg_white = 37,
    fg_extended = 38,
    fg_default = 39,
    bg_black = 40,
    bg_red = 41,
    bg_green = 42,
    bg_yellow = 43,
    bg_blue = 44,
    bg_magenta = 45,
    bg_cyan = 46,
    bg_white = 47,
    bg_extended = 48,
    bg_default = 49,
    no_proportional_spacing = 50,
    framed = 51,
    encircled = 52,
    overlined = 53,
    no_framed_encircled = 54,
    no_overlined = 55,
    underline_color = 58,
    default_underline_color = 59,
    ideogram_underline = 60,
    ideogram_double_underline = 61,
    ideogram_overline = 62,
    ideogram_double_overline = 63,
    ideogram_stress = 64,
    no_ideogram = 65,
    superscript = 73,
    subscript = 74,
    no_superscript_subscript = 75,
    fg_bright_black = 90,
    fg_bright_red = 91,
    fg_bright_green = 92,
    fg_bright_yellow = 93,
    fg_bright_blue = 94,
    fg_bright_magenta = 95,
    fg_bright_cyan = 96,
    fg_bright_white = 97,
    bg_bright_black = 100,
    bg_bright_red = 101,
    bg_bright_green = 102,
    bg_bright_yellow = 103,
    bg_bright_blue = 104,
    bg_bright_magenta = 105,
    bg_bright_cyan = 106,
    bg_bright_white = 107,
};

// =============================================================================
// Colors
// =============================================================================

/// Basic 16-color palette (0-15)
pub const BasicColor = enum(u8) {
    black = 0,
    red = 1,
    green = 2,
    yellow = 3,
    blue = 4,
    magenta = 5,
    cyan = 6,
    white = 7,
    bright_black = 8,
    bright_red = 9,
    bright_green = 10,
    bright_yellow = 11,
    bright_blue = 12,
    bright_magenta = 13,
    bright_cyan = 14,
    bright_white = 15,
};

/// 256-color palette index (0-255)
pub const IndexedColor = u8;

/// RGB true color
pub const RGBColor = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn init(r: u8, g: u8, b: u8) RGBColor {
        return .{ .r = r, .g = g, .b = b };
    }

    /// Parse hex color string like "#FF5733" or "FF5733"
    pub fn fromHex(hex: []const u8) ?RGBColor {
        const s = if (hex.len > 0 and hex[0] == '#') hex[1..] else hex;
        if (s.len != 6) return null;

        const r = std.fmt.parseInt(u8, s[0..2], 16) catch return null;
        const g = std.fmt.parseInt(u8, s[2..4], 16) catch return null;
        const b = std.fmt.parseInt(u8, s[4..6], 16) catch return null;

        return .{ .r = r, .g = g, .b = b };
    }
};

/// Color type union
pub const Color = union(enum) {
    default,
    basic: BasicColor,
    indexed: IndexedColor,
    rgb: RGBColor,
};

// =============================================================================
// Underline Styles
// =============================================================================

pub const UnderlineStyle = enum(u8) {
    none = 0,
    single = 1,
    double = 2,
    curly = 3,
    dotted = 4,
    dashed = 5,
};

// =============================================================================
// Style Builder
// =============================================================================

pub const Style = struct {
    bold: bool = false,
    faint: bool = false,
    italic: bool = false,
    underline: UnderlineStyle = .none,
    slow_blink: bool = false,
    rapid_blink: bool = false,
    reverse: bool = false,
    conceal: bool = false,
    strikethrough: bool = false,
    overline: bool = false,
    fg: Color = .default,
    bg: Color = .default,
    underline_color: Color = .default,

    /// Write the SGR sequence to start this style
    pub fn writeStart(self: Style, writer: *std.Io.Writer) !void {
        try writer.writeAll(CSI);

        var first = true;

        if (self.bold) {
            try writer.writeAll("1");
            first = false;
        }
        if (self.faint) {
            if (!first) try writer.writeAll(";");
            try writer.writeAll("2");
            first = false;
        }
        if (self.italic) {
            if (!first) try writer.writeAll(";");
            try writer.writeAll("3");
            first = false;
        }
        if (self.underline != .none) {
            if (!first) try writer.writeAll(";");
            try writer.writeAll("4");
            if (self.underline != .single) {
                try writer.print(":{d}", .{@intFromEnum(self.underline)});
            }
            first = false;
        }
        if (self.slow_blink) {
            if (!first) try writer.writeAll(";");
            try writer.writeAll("5");
            first = false;
        }
        if (self.rapid_blink) {
            if (!first) try writer.writeAll(";");
            try writer.writeAll("6");
            first = false;
        }
        if (self.reverse) {
            if (!first) try writer.writeAll(";");
            try writer.writeAll("7");
            first = false;
        }
        if (self.conceal) {
            if (!first) try writer.writeAll(";");
            try writer.writeAll("8");
            first = false;
        }
        if (self.strikethrough) {
            if (!first) try writer.writeAll(";");
            try writer.writeAll("9");
            first = false;
        }
        if (self.overline) {
            if (!first) try writer.writeAll(";");
            try writer.writeAll("53");
            first = false;
        }

        // Foreground color
        switch (self.fg) {
            .default => {},
            .basic => |c| {
                if (!first) try writer.writeAll(";");
                const code: u8 = if (@intFromEnum(c) < 8) 30 + @intFromEnum(c) else 90 + @intFromEnum(c) - 8;
                try writer.print("{d}", .{code});
                first = false;
            },
            .indexed => |i| {
                if (!first) try writer.writeAll(";");
                try writer.print("38;5;{d}", .{i});
                first = false;
            },
            .rgb => |rgb| {
                if (!first) try writer.writeAll(";");
                try writer.print("38;2;{d};{d};{d}", .{ rgb.r, rgb.g, rgb.b });
                first = false;
            },
        }

        // Background color
        switch (self.bg) {
            .default => {},
            .basic => |c| {
                if (!first) try writer.writeAll(";");
                const code: u8 = if (@intFromEnum(c) < 8) 40 + @intFromEnum(c) else 100 + @intFromEnum(c) - 8;
                try writer.print("{d}", .{code});
                first = false;
            },
            .indexed => |i| {
                if (!first) try writer.writeAll(";");
                try writer.print("48;5;{d}", .{i});
                first = false;
            },
            .rgb => |rgb| {
                if (!first) try writer.writeAll(";");
                try writer.print("48;2;{d};{d};{d}", .{ rgb.r, rgb.g, rgb.b });
                first = false;
            },
        }

        // Underline color
        switch (self.underline_color) {
            .default => {},
            .basic => |c| {
                if (!first) try writer.writeAll(";");
                try writer.print("58;5;{d}", .{@intFromEnum(c)});
                first = false;
            },
            .indexed => |i| {
                if (!first) try writer.writeAll(";");
                try writer.print("58;5;{d}", .{i});
                first = false;
            },
            .rgb => |rgb| {
                if (!first) try writer.writeAll(";");
                try writer.print("58;2;{d};{d};{d}", .{ rgb.r, rgb.g, rgb.b });
                first = false;
            },
        }

        if (first) {
            try writer.writeAll("0"); // Reset if no attributes
        }

        try writer.writeAll("m");
    }

    /// Write the SGR reset sequence
    pub fn writeEnd(_: Style, writer: *std.Io.Writer) !void {
        try writer.writeAll(CSI ++ "0m");
    }

    /// Write styled text
    pub fn write(self: Style, writer: *std.Io.Writer, text: []const u8) !void {
        try self.writeStart(writer);
        try writer.writeAll(text);
        try self.writeEnd(writer);
    }

    /// Format into a buffer and return the sequence to start this style
    pub fn sequence(self: Style, buf: []u8) []const u8 {
        var writer = std.Io.Writer.fixed(buf);
        self.writeStart(&writer) catch return "";
        return writer.buffered();
    }
};

// =============================================================================
// SGR Functions
// =============================================================================

/// Reset all attributes
pub const reset = CSI ++ "0m";

/// Bold/bright
pub const bold = CSI ++ "1m";

/// Faint/dim
pub const faint = CSI ++ "2m";

/// Italic
pub const italic = CSI ++ "3m";

/// Underline
pub const underline = CSI ++ "4m";

/// Slow blink
pub const slow_blink = CSI ++ "5m";

/// Rapid blink
pub const rapid_blink = CSI ++ "6m";

/// Reverse video
pub const reverse = CSI ++ "7m";

/// Conceal/hidden
pub const conceal = CSI ++ "8m";

/// Crossed out / strikethrough
pub const crossed_out = CSI ++ "9m";

/// Normal intensity (not bold, not faint)
pub const normal_intensity = CSI ++ "22m";

/// Not italic
pub const no_italic = CSI ++ "23m";

/// Not underlined
pub const no_underline = CSI ++ "24m";

/// Not blinking
pub const no_blink = CSI ++ "25m";

/// Not reversed
pub const no_reverse = CSI ++ "27m";

/// Reveal (not concealed)
pub const no_conceal = CSI ++ "28m";

/// Not crossed out
pub const no_crossed_out = CSI ++ "29m";

/// Overlined
pub const overline = CSI ++ "53m";

/// Not overlined
pub const no_overline = CSI ++ "55m";

// =============================================================================
// Cursor Movement (CUP, CUU, CUD, CUF, CUB, etc.)
// =============================================================================

pub const cursor = struct {
    /// Move cursor up n lines
    pub fn up(writer: *std.Io.Writer, n: u16) !void {
        try writer.print(CSI ++ "{d}A", .{n});
    }

    /// Move cursor down n lines
    pub fn down(writer: *std.Io.Writer, n: u16) !void {
        try writer.print(CSI ++ "{d}B", .{n});
    }

    /// Move cursor forward (right) n columns
    pub fn forward(writer: *std.Io.Writer, n: u16) !void {
        try writer.print(CSI ++ "{d}C", .{n});
    }

    /// Move cursor backward (left) n columns
    pub fn backward(writer: *std.Io.Writer, n: u16) !void {
        try writer.print(CSI ++ "{d}D", .{n});
    }

    /// Move cursor to beginning of line n lines down
    pub fn nextLine(writer: *std.Io.Writer, n: u16) !void {
        try writer.print(CSI ++ "{d}E", .{n});
    }

    /// Move cursor to beginning of line n lines up
    pub fn prevLine(writer: *std.Io.Writer, n: u16) !void {
        try writer.print(CSI ++ "{d}F", .{n});
    }

    /// Move cursor to column n (1-based)
    pub fn toColumn(writer: *std.Io.Writer, col: u16) !void {
        try writer.print(CSI ++ "{d}G", .{col});
    }

    /// Move cursor to row, column (1-based)
    pub fn toPos(writer: *std.Io.Writer, row: u16, col: u16) !void {
        try writer.print(CSI ++ "{d};{d}H", .{ row, col });
    }

    /// Move cursor to row (1-based)
    pub fn toRow(writer: *std.Io.Writer, row: u16) !void {
        try writer.print(CSI ++ "{d}d", .{row});
    }

    /// Save cursor position
    pub fn save(writer: *std.Io.Writer) !void {
        try writer.writeAll(CSI ++ "s");
    }

    /// Restore cursor position
    pub fn restore(writer: *std.Io.Writer) !void {
        try writer.writeAll(CSI ++ "u");
    }

    /// Hide cursor
    pub fn hide(writer: *std.Io.Writer) !void {
        try writer.writeAll(CSI ++ "?25l");
    }

    /// Show cursor
    pub fn show(writer: *std.Io.Writer) !void {
        try writer.writeAll(CSI ++ "?25h");
    }

    /// Move cursor to home position (1,1)
    pub fn home(writer: *std.Io.Writer) !void {
        try writer.writeAll(CSI ++ "H");
    }

    /// Request cursor position (response: ESC [ row ; col R)
    pub fn requestPos(writer: *std.Io.Writer) !void {
        try writer.writeAll(CSI ++ "6n");
    }

    /// Comptime: cursor up
    pub fn upSeq(comptime n: u16) *const [seqLen("{d}A", n)]u8 {
        return comptime blk: {
            var buf: [32]u8 = undefined;
            const len = std.fmt.formatIntBuf(&buf, n, 10, .lower, .{});
            break :blk CSI ++ buf[0..len] ++ "A";
        };
    }

    /// Comptime: cursor down
    pub fn downSeq(comptime n: u16) *const [seqLen("{d}B", n)]u8 {
        return comptime blk: {
            var buf: [32]u8 = undefined;
            const len = std.fmt.formatIntBuf(&buf, n, 10, .lower, .{});
            break :blk CSI ++ buf[0..len] ++ "B";
        };
    }

    fn seqLen(comptime fmt: []const u8, comptime n: u16) usize {
        _ = fmt;
        var buf: [32]u8 = undefined;
        const len = std.fmt.formatIntBuf(&buf, n, 10, .lower, .{});
        return CSI.len + len + 1;
    }
};

// Static cursor sequences
pub const cursor_up = CSI ++ "A";
pub const cursor_down = CSI ++ "B";
pub const cursor_forward = CSI ++ "C";
pub const cursor_backward = CSI ++ "D";
pub const cursor_home = CSI ++ "H";
pub const cursor_save = CSI ++ "s";
pub const cursor_restore = CSI ++ "u";
pub const cursor_hide = CSI ++ "?25l";
pub const cursor_show = CSI ++ "?25h";

// =============================================================================
// Erase Functions
// =============================================================================

pub const erase = struct {
    /// Erase from cursor to end of screen
    pub fn toEndOfScreen(writer: *std.Io.Writer) !void {
        try writer.writeAll(CSI ++ "0J");
    }

    /// Erase from cursor to beginning of screen
    pub fn toStartOfScreen(writer: *std.Io.Writer) !void {
        try writer.writeAll(CSI ++ "1J");
    }

    /// Erase entire screen
    pub fn screen(writer: *std.Io.Writer) !void {
        try writer.writeAll(CSI ++ "2J");
    }

    /// Erase entire screen and scrollback buffer
    pub fn screenAndScrollback(writer: *std.Io.Writer) !void {
        try writer.writeAll(CSI ++ "3J");
    }

    /// Erase from cursor to end of line
    pub fn toEndOfLine(writer: *std.Io.Writer) !void {
        try writer.writeAll(CSI ++ "0K");
    }

    /// Erase from cursor to beginning of line
    pub fn toStartOfLine(writer: *std.Io.Writer) !void {
        try writer.writeAll(CSI ++ "1K");
    }

    /// Erase entire line
    pub fn line(writer: *std.Io.Writer) !void {
        try writer.writeAll(CSI ++ "2K");
    }

    /// Erase n characters from cursor position
    pub fn chars(writer: *std.Io.Writer, n: u16) !void {
        try writer.print(CSI ++ "{d}X", .{n});
    }
};

// Static erase sequences
pub const erase_to_end_of_screen = CSI ++ "0J";
pub const erase_to_start_of_screen = CSI ++ "1J";
pub const erase_screen = CSI ++ "2J";
pub const erase_screen_and_scrollback = CSI ++ "3J";
pub const erase_to_end_of_line = CSI ++ "0K";
pub const erase_to_start_of_line = CSI ++ "1K";
pub const erase_line = CSI ++ "2K";

// =============================================================================
// Scroll Functions
// =============================================================================

pub const scroll = struct {
    /// Scroll up n lines
    pub fn up(writer: *std.Io.Writer, n: u16) !void {
        try writer.print(CSI ++ "{d}S", .{n});
    }

    /// Scroll down n lines
    pub fn down(writer: *std.Io.Writer, n: u16) !void {
        try writer.print(CSI ++ "{d}T", .{n});
    }
};

// =============================================================================
// Line Functions
// =============================================================================

pub const line = struct {
    /// Insert n blank lines at cursor position
    pub fn insert(writer: *std.Io.Writer, n: u16) !void {
        try writer.print(CSI ++ "{d}L", .{n});
    }

    /// Delete n lines at cursor position
    pub fn delete(writer: *std.Io.Writer, n: u16) !void {
        try writer.print(CSI ++ "{d}M", .{n});
    }
};

// =============================================================================
// Character Functions
// =============================================================================

pub const char = struct {
    /// Insert n blank characters at cursor position
    pub fn insert(writer: *std.Io.Writer, n: u16) !void {
        try writer.print(CSI ++ "{d}@", .{n});
    }

    /// Delete n characters at cursor position
    pub fn delete(writer: *std.Io.Writer, n: u16) !void {
        try writer.print(CSI ++ "{d}P", .{n});
    }
};

// =============================================================================
// Screen Modes
// =============================================================================

pub const screen_mode = struct {
    /// Enable alternative screen buffer
    pub fn enableAltBuffer(writer: *std.Io.Writer) !void {
        try writer.writeAll(CSI ++ "?1049h");
    }

    /// Disable alternative screen buffer
    pub fn disableAltBuffer(writer: *std.Io.Writer) !void {
        try writer.writeAll(CSI ++ "?1049l");
    }

    /// Enable line wrapping
    pub fn enableLineWrap(writer: *std.Io.Writer) !void {
        try writer.writeAll(CSI ++ "?7h");
    }

    /// Disable line wrapping
    pub fn disableLineWrap(writer: *std.Io.Writer) !void {
        try writer.writeAll(CSI ++ "?7l");
    }

    /// Enable bracketed paste mode
    pub fn enableBracketedPaste(writer: *std.Io.Writer) !void {
        try writer.writeAll(CSI ++ "?2004h");
    }

    /// Disable bracketed paste mode
    pub fn disableBracketedPaste(writer: *std.Io.Writer) !void {
        try writer.writeAll(CSI ++ "?2004l");
    }
};

pub const alt_buffer_enable = CSI ++ "?1049h";
pub const alt_buffer_disable = CSI ++ "?1049l";
pub const line_wrap_enable = CSI ++ "?7h";
pub const line_wrap_disable = CSI ++ "?7l";
pub const bracketed_paste_enable = CSI ++ "?2004h";
pub const bracketed_paste_disable = CSI ++ "?2004l";

// =============================================================================
// Mouse Modes
// =============================================================================

pub const mouse = struct {
    /// Enable mouse tracking (normal mode - X10 compatible)
    pub fn enableNormal(writer: *std.Io.Writer) !void {
        try writer.writeAll(CSI ++ "?1000h");
    }

    /// Disable mouse tracking
    pub fn disableNormal(writer: *std.Io.Writer) !void {
        try writer.writeAll(CSI ++ "?1000l");
    }

    /// Enable mouse button tracking
    pub fn enableButton(writer: *std.Io.Writer) !void {
        try writer.writeAll(CSI ++ "?1002h");
    }

    /// Disable mouse button tracking
    pub fn disableButton(writer: *std.Io.Writer) !void {
        try writer.writeAll(CSI ++ "?1002l");
    }

    /// Enable mouse any-event tracking
    pub fn enableAny(writer: *std.Io.Writer) !void {
        try writer.writeAll(CSI ++ "?1003h");
    }

    /// Disable mouse any-event tracking
    pub fn disableAny(writer: *std.Io.Writer) !void {
        try writer.writeAll(CSI ++ "?1003l");
    }

    /// Enable SGR extended mouse mode
    pub fn enableSGR(writer: *std.Io.Writer) !void {
        try writer.writeAll(CSI ++ "?1006h");
    }

    /// Disable SGR extended mouse mode
    pub fn disableSGR(writer: *std.Io.Writer) !void {
        try writer.writeAll(CSI ++ "?1006l");
    }
};

// =============================================================================
// OSC (Operating System Command) Sequences
// =============================================================================

pub const osc = struct {
    /// Set window title
    pub fn setTitle(writer: *std.Io.Writer, title: []const u8) !void {
        try writer.writeAll(OSC ++ "0;");
        try writer.writeAll(title);
        try writer.writeAll(BEL);
    }

    /// Set icon name
    pub fn setIconName(writer: *std.Io.Writer, name: []const u8) !void {
        try writer.writeAll(OSC ++ "1;");
        try writer.writeAll(name);
        try writer.writeAll(BEL);
    }

    /// Set clipboard (OSC 52)
    pub fn setClipboard(writer: *std.Io.Writer, data: []const u8) !void {
        try writer.writeAll(OSC ++ "52;c;");
        try writer.writeAll(data); // Should be base64 encoded
        try writer.writeAll(BEL);
    }

    /// Request clipboard (OSC 52)
    pub fn requestClipboard(writer: *std.Io.Writer) !void {
        try writer.writeAll(OSC ++ "52;c;?" ++ BEL);
    }

    /// Hyperlink (OSC 8)
    pub fn hyperlinkStart(writer: *std.Io.Writer, url: []const u8) !void {
        try writer.writeAll(OSC ++ "8;;");
        try writer.writeAll(url);
        try writer.writeAll(BEL);
    }

    /// End hyperlink
    pub fn hyperlinkEnd(writer: *std.Io.Writer) !void {
        try writer.writeAll(OSC ++ "8;;" ++ BEL);
    }

    /// Notify (OSC 9 - iTerm2)
    pub fn notify(writer: *std.Io.Writer, message: []const u8) !void {
        try writer.writeAll(OSC ++ "9;");
        try writer.writeAll(message);
        try writer.writeAll(BEL);
    }
};

// =============================================================================
// String Utilities
// =============================================================================

/// Calculate the display width of a string, ignoring ANSI escape sequences
pub fn stringWidth(s: []const u8) usize {
    var width: usize = 0;
    var i: usize = 0;

    while (i < s.len) {
        if (s[i] == C0.ESC) {
            // Skip escape sequence
            i += 1;
            if (i < s.len and s[i] == '[') {
                // CSI sequence
                i += 1;
                while (i < s.len and s[i] >= 0x20 and s[i] <= 0x3F) : (i += 1) {}
                if (i < s.len and s[i] >= 0x40 and s[i] <= 0x7E) i += 1;
            } else if (i < s.len and s[i] == ']') {
                // OSC sequence - skip until BEL or ST
                i += 1;
                while (i < s.len and s[i] != C0.BEL and !(i + 1 < s.len and s[i] == C0.ESC and s[i + 1] == '\\')) : (i += 1) {}
                if (i < s.len and s[i] == C0.BEL) i += 1;
                if (i + 1 < s.len and s[i] == C0.ESC and s[i + 1] == '\\') i += 2;
            }
        } else if (s[i] < 0x20 or s[i] == 0x7F) {
            // Control character - no width
            i += 1;
        } else if (s[i] & 0x80 == 0) {
            // ASCII printable
            width += 1;
            i += 1;
        } else {
            // UTF-8 - count as 1 for now (proper implementation would check for wide chars)
            const len = std.unicode.utf8ByteSequenceLength(s[i]) catch 1;
            width += 1; // Simplified - doesn't account for wide characters
            i += len;
        }
    }

    return width;
}

/// Strip ANSI escape sequences from a string
pub fn strip(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == C0.ESC) {
            // Skip escape sequence
            i += 1;
            if (i < s.len and s[i] == '[') {
                // CSI sequence
                i += 1;
                while (i < s.len and s[i] >= 0x20 and s[i] <= 0x3F) : (i += 1) {}
                if (i < s.len and s[i] >= 0x40 and s[i] <= 0x7E) i += 1;
            } else if (i < s.len and s[i] == ']') {
                // OSC sequence
                i += 1;
                while (i < s.len and s[i] != C0.BEL and !(i + 1 < s.len and s[i] == C0.ESC and s[i + 1] == '\\')) : (i += 1) {}
                if (i < s.len and s[i] == C0.BEL) i += 1;
                if (i + 1 < s.len and s[i] == C0.ESC and s[i + 1] == '\\') i += 2;
            }
        } else {
            try result.append(allocator, s[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice(allocator);
}

// =============================================================================
// Foreground Color Convenience Functions
// =============================================================================

pub const fg = struct {
    pub const black = CSI ++ "30m";
    pub const red = CSI ++ "31m";
    pub const green = CSI ++ "32m";
    pub const yellow = CSI ++ "33m";
    pub const blue = CSI ++ "34m";
    pub const magenta = CSI ++ "35m";
    pub const cyan = CSI ++ "36m";
    pub const white = CSI ++ "37m";
    pub const default = CSI ++ "39m";

    pub const bright_black = CSI ++ "90m";
    pub const bright_red = CSI ++ "91m";
    pub const bright_green = CSI ++ "92m";
    pub const bright_yellow = CSI ++ "93m";
    pub const bright_blue = CSI ++ "94m";
    pub const bright_magenta = CSI ++ "95m";
    pub const bright_cyan = CSI ++ "96m";
    pub const bright_white = CSI ++ "97m";

    /// Set foreground to 256-color palette index
    pub fn indexed(writer: *std.Io.Writer, index: u8) !void {
        try writer.print(CSI ++ "38;5;{d}m", .{index});
    }

    /// Set foreground to RGB color
    pub fn rgb(writer: *std.Io.Writer, r: u8, g: u8, b: u8) !void {
        try writer.print(CSI ++ "38;2;{d};{d};{d}m", .{ r, g, b });
    }
};

// =============================================================================
// Background Color Convenience Functions
// =============================================================================

pub const bg = struct {
    pub const black = CSI ++ "40m";
    pub const red = CSI ++ "41m";
    pub const green = CSI ++ "42m";
    pub const yellow = CSI ++ "43m";
    pub const blue = CSI ++ "44m";
    pub const magenta = CSI ++ "45m";
    pub const cyan = CSI ++ "46m";
    pub const white = CSI ++ "47m";
    pub const default = CSI ++ "49m";

    pub const bright_black = CSI ++ "100m";
    pub const bright_red = CSI ++ "101m";
    pub const bright_green = CSI ++ "102m";
    pub const bright_yellow = CSI ++ "103m";
    pub const bright_blue = CSI ++ "104m";
    pub const bright_magenta = CSI ++ "105m";
    pub const bright_cyan = CSI ++ "106m";
    pub const bright_white = CSI ++ "107m";

    /// Set background to 256-color palette index
    pub fn indexed(writer: *std.Io.Writer, index: u8) !void {
        try writer.print(CSI ++ "48;5;{d}m", .{index});
    }

    /// Set background to RGB color
    pub fn rgb(writer: *std.Io.Writer, r: u8, g: u8, b: u8) !void {
        try writer.print(CSI ++ "48;2;{d};{d};{d}m", .{ r, g, b });
    }
};

// Re-export parser module
// =============================================================================
// Tests
// =============================================================================

test "RGBColor.fromHex" {
    const c1 = RGBColor.fromHex("#FF5733").?;
    try std.testing.expectEqual(@as(u8, 0xFF), c1.r);
    try std.testing.expectEqual(@as(u8, 0x57), c1.g);
    try std.testing.expectEqual(@as(u8, 0x33), c1.b);

    const c2 = RGBColor.fromHex("00FF00").?;
    try std.testing.expectEqual(@as(u8, 0x00), c2.r);
    try std.testing.expectEqual(@as(u8, 0xFF), c2.g);
    try std.testing.expectEqual(@as(u8, 0x00), c2.b);

    try std.testing.expectEqual(@as(?RGBColor, null), RGBColor.fromHex("invalid"));
    try std.testing.expectEqual(@as(?RGBColor, null), RGBColor.fromHex("#FFF"));
}

test "Style.sequence" {
    var buf: [64]u8 = undefined;

    const bold_style = Style{ .bold = true };
    const seq = bold_style.sequence(&buf);
    try std.testing.expectEqualStrings("\x1b[1m", seq);
}

test "Style.write" {
    var buf: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    const style = Style{ .bold = true, .fg = .{ .basic = .red } };
    try style.write(&writer, "Hello");

    try std.testing.expectEqualStrings("\x1b[1;31mHello\x1b[0m", writer.buffered());
}

test "stringWidth" {
    try std.testing.expectEqual(@as(usize, 5), stringWidth("Hello"));
    try std.testing.expectEqual(@as(usize, 5), stringWidth("\x1b[31mHello\x1b[0m"));
    try std.testing.expectEqual(@as(usize, 11), stringWidth("Hello World"));
    try std.testing.expectEqual(@as(usize, 11), stringWidth("\x1b[1;34mHello\x1b[0m World"));
}

test "strip" {
    const allocator = std.testing.allocator;

    const s1 = try strip(allocator, "\x1b[31mHello\x1b[0m");
    defer allocator.free(s1);
    try std.testing.expectEqualStrings("Hello", s1);

    const s2 = try strip(allocator, "\x1b[1;34mBold Blue\x1b[0m Text");
    defer allocator.free(s2);
    try std.testing.expectEqualStrings("Bold Blue Text", s2);
}

test "cursor sequences" {
    var buf: [32]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try cursor.up(&writer, 5);
    try std.testing.expectEqualStrings("\x1b[5A", writer.buffered());

    writer.end = 0;
    try cursor.toPos(&writer, 10, 20);
    try std.testing.expectEqualStrings("\x1b[10;20H", writer.buffered());
}

test "erase sequences" {
    var buf: [32]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try erase.screen(&writer);
    try std.testing.expectEqualStrings("\x1b[2J", writer.buffered());

    writer.end = 0;
    try erase.line(&writer);
    try std.testing.expectEqualStrings("\x1b[2K", writer.buffered());
}
