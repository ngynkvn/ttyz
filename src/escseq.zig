const std = @import("std");
/// vt100 / xterm escape sequences
/// References used:
///  - https://vt100.net/docs/vt100-ug/chapter3.html
///  - `man terminfo`, `man tput`, `man infocmp`
// zig fmt: off
/// escape code prefix
pub const ESC= "\x1b[";
pub const HOME               = ESC ++ "H";
/// goto .{y, x}
pub const GOTO               = ESC ++ "{d};{d}H";
pub const CLEAR_LINE         = ESC ++ "K";
pub const CLEAR_DOWN         = ESC ++ "0J";
pub const CLEAR_UP           = ESC ++ "1J";
pub const CLEAR_SCREEN       = ESC ++ "2J"; // NOTE: https://vt100.net/docs/vt100-ug/chapter3.html#ED
pub const ENTER_ALT_SCREEN   = ESC ++ "?1049h";
pub const EXIT_ALT_SCREEN    = ESC ++ "?1049l";
pub const REPORT_CURSOR_POS  = ESC ++ "6n";
pub const CURSOR_INVISIBLE   = ESC ++ "?25l";
pub const CURSOR_VISIBLE     = ESC ++ "?12;25h";
pub const CURSOR_UP          = ESC ++ "{}A";
pub const CURSOR_DOWN        = ESC ++ "{}B";
pub const CURSOR_FORWARD     = ESC ++ "{}C";
pub const CURSOR_BACKWARDS   = ESC ++ "{}D";
pub const CURSOR_HOME_ROW    = ESC ++ "1G";
pub const CURSOR_COL_ABS     = ESC ++ "{}G";
pub const CURSOR_SAVE_POS    = ESC ++ "7";
pub const CURSOR_RESTORE_POS = ESC ++ "8";
/// setaf .{color}
pub const SET_ANSI_FG        = ESC ++ "3{d}m";
pub const SET_ANSI24_FG      = ESC ++ "38;2;{d};{d};{d}m";
/// setab .{color}
pub const SET_ANSI_BG        = ESC ++ "4{d}m";
pub const SET_ANSI24_BG      = ESC ++ "48;2;{d};{d};{d}m";
pub const RESET_COLORS       = ESC ++ "m";
// zig fmt: on

pub const Color = enum(u8) {
    black = 0,
    red,
    green,
    yellow,
    blue,
    purple,
    cyan,
    white,
};

pub const AnsiModifier = struct {
    escseq: []const u8,
    const SET_ANSI = ESC ++ "{d}m";
    pub const bold = AnsiModifier{
        .escseq = std.fmt.comptimePrint(SET_ANSI, .{1}),
    };
    pub const italic = AnsiModifier{
        .escseq = std.fmt.comptimePrint(SET_ANSI, .{3}),
    };
    pub const underline = AnsiModifier{
        .escseq = std.fmt.comptimePrint(SET_ANSI, .{4}),
    };
    pub fn fg(comptime c: Color) AnsiModifier {
        return AnsiModifier{
            .escseq = std.fmt.comptimePrint(SET_ANSI, .{30 + @intFromEnum(c)}),
        };
    }
    pub fn bg(comptime c: Color) AnsiModifier {
        return AnsiModifier{
            .escseq = std.fmt.comptimePrint(SET_ANSI, .{40 + @intFromEnum(c)}),
        };
    }
};
