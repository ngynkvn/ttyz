const std = @import("std");

pub const E = @This();
pub const cc = std.ascii.control_code;

/// vt100 / xterm escape sequences
/// References used:
///  - https://vt100.net/docs/vt100-ug/chapter3.html
///  - `man terminfo`, `man tput`, `man infocmp`

// zig fmt: off
/// escape code prefix
pub const ESC = "\x1b";
pub const HOME               = ESC ++ "[H";
/// goto .{y, x}
pub const GOTO               = ESC ++ "[{d};{d}H";
pub const CLEAR_LINE         = ESC ++ "[K";
pub const CLEAR_DOWN         = ESC ++ "[0J";
pub const CLEAR_UP           = ESC ++ "[1J";
pub const CLEAR_SCREEN       = ESC ++ "[2J"; // NOTE: https://vt100.net/docs/vt100-ug/chapter3.html#ED
pub const ENTER_ALT_SCREEN   = ESC ++ "[?1049h";
pub const EXIT_ALT_SCREEN    = ESC ++ "[?1049l";
pub const REPORT_CURSOR_POS  = ESC ++ "[6n";
pub const CURSOR_INVISIBLE   = ESC ++ "[?25l";
pub const CURSOR_VISIBLE     = ESC ++ "[?12;25h";
pub const CURSOR_UP          = ESC ++ "[{}A";
pub const CURSOR_DOWN        = ESC ++ "[{}B";
pub const CURSOR_FORWARD     = ESC ++ "[{}C";
pub const CURSOR_BACKWARDS   = ESC ++ "[{}D";
pub const CURSOR_HOME_ROW    = ESC ++ "[1G";
pub const CURSOR_COL_ABS     = ESC ++ "[{}G";
pub const CURSOR_SAVE_POS    = ESC ++ "[7";
pub const CURSOR_RESTORE_POS = ESC ++ "[8";
/// setaf .{color}
pub const SET_ANSI_FG        = ESC ++ "[3{d}m";
/// setab .{color}
pub const SET_ANSI_BG        = ESC ++ "[4{d}m";
/// set true color (rgb)
pub const SET_TRUCOLOR       = ESC ++ "[38;2;{};{};{}m";
pub const RESET_COLORS       = ESC ++ "[m";
// zig fmt: on

pub const ENABLE_MOUSE_TRACKING = ESC ++ "[?1000;1006h";
pub const DISABLE_MOUSE_TRACKING = ESC ++ "[?1000;1006l";
