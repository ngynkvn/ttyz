const std = @import("std");
pub const cc = std.ascii.control_code;

pub const E = @This();
/// vt100 / xterm escape sequences
/// References used:
///  - https://vt100.net/docs/vt100-ug/chapter3.html
///  - `man terminfo`, `man tput`, `man infocmp`

// zig fmt: off
/// escape code prefix
pub const ESC = "\x1b";
pub const HOME               = ESC ++ "[H";
/// goto .{row, col}
pub const GOTO               = ESC ++ "[{d};{d}H";
pub const CLEAR_LINE         = ESC ++ "[K";
pub const CLEAR_LINE_LEFT    = ESC ++ "[1K";
pub const CLEAR_LINE_ALL     = ESC ++ "[2K";
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
// zig fmt: on

// Text styles
pub const BOLD = ESC ++ "[1m";
pub const DIM = ESC ++ "[2m";
pub const ITALIC = ESC ++ "[3m";
pub const UNDERLINE = ESC ++ "[4m";
pub const BLINK = ESC ++ "[5m";
pub const REVERSE = ESC ++ "[7m";
pub const HIDDEN = ESC ++ "[8m";
pub const STRIKETHROUGH = ESC ++ "[9m";
pub const RESET_STYLE = ESC ++ "[0m";

// Colors - foreground (30-37, 90-97 for bright)
pub const FG_BLACK = ESC ++ "[30m";
pub const FG_RED = ESC ++ "[31m";
pub const FG_GREEN = ESC ++ "[32m";
pub const FG_YELLOW = ESC ++ "[33m";
pub const FG_BLUE = ESC ++ "[34m";
pub const FG_MAGENTA = ESC ++ "[35m";
pub const FG_CYAN = ESC ++ "[36m";
pub const FG_WHITE = ESC ++ "[37m";
pub const FG_DEFAULT = ESC ++ "[39m";

// Bright foreground colors
pub const FG_BRIGHT_BLACK = ESC ++ "[90m";
pub const FG_BRIGHT_RED = ESC ++ "[91m";
pub const FG_BRIGHT_GREEN = ESC ++ "[92m";
pub const FG_BRIGHT_YELLOW = ESC ++ "[93m";
pub const FG_BRIGHT_BLUE = ESC ++ "[94m";
pub const FG_BRIGHT_MAGENTA = ESC ++ "[95m";
pub const FG_BRIGHT_CYAN = ESC ++ "[96m";
pub const FG_BRIGHT_WHITE = ESC ++ "[97m";

// Colors - background (40-47, 100-107 for bright)
pub const BG_BLACK = ESC ++ "[40m";
pub const BG_RED = ESC ++ "[41m";
pub const BG_GREEN = ESC ++ "[42m";
pub const BG_YELLOW = ESC ++ "[43m";
pub const BG_BLUE = ESC ++ "[44m";
pub const BG_MAGENTA = ESC ++ "[45m";
pub const BG_CYAN = ESC ++ "[46m";
pub const BG_WHITE = ESC ++ "[47m";
pub const BG_DEFAULT = ESC ++ "[49m";

// Bright background colors
pub const BG_BRIGHT_BLACK = ESC ++ "[100m";
pub const BG_BRIGHT_RED = ESC ++ "[101m";
pub const BG_BRIGHT_GREEN = ESC ++ "[102m";
pub const BG_BRIGHT_YELLOW = ESC ++ "[103m";
pub const BG_BRIGHT_BLUE = ESC ++ "[104m";
pub const BG_BRIGHT_MAGENTA = ESC ++ "[105m";
pub const BG_BRIGHT_CYAN = ESC ++ "[106m";
pub const BG_BRIGHT_WHITE = ESC ++ "[107m";

/// setaf .{color} - 256-color foreground (0-255)
pub const SET_ANSI_FG = ESC ++ "[3{d}m";
/// setab .{color} - 256-color background (0-255)
pub const SET_ANSI_BG = ESC ++ "[4{d}m";
/// 256-color foreground .{0-255}
pub const SET_FG_256 = ESC ++ "[38;5;{d}m";
/// 256-color background .{0-255}
pub const SET_BG_256 = ESC ++ "[48;5;{d}m";
/// set true color (rgb) foreground .{r, g, b}
pub const SET_TRUCOLOR = ESC ++ "[38;2;{};{};{}m";
/// set true color (rgb) background .{r, g, b}
pub const SET_TRUCOLOR_BG = ESC ++ "[48;2;{};{};{}m";
pub const RESET_COLORS = ESC ++ "[m";

// Mouse tracking modes
pub const ENABLE_MOUSE_TRACKING = ESC ++ "[?1000;1006h";
pub const DISABLE_MOUSE_TRACKING = ESC ++ "[?1000;1006l";
pub const ENABLE_MOUSE_MOTION = ESC ++ "[?1003h"; // Track all motion
pub const DISABLE_MOUSE_MOTION = ESC ++ "[?1003l";

// Focus events
pub const ENABLE_FOCUS_EVENTS = ESC ++ "[?1004h";
pub const DISABLE_FOCUS_EVENTS = ESC ++ "[?1004l";

// Bracketed paste mode
pub const ENABLE_BRACKETED_PASTE = ESC ++ "[?2004h";
pub const DISABLE_BRACKETED_PASTE = ESC ++ "[?2004l";
pub const PASTE_START = ESC ++ "[200~";
pub const PASTE_END = ESC ++ "[201~";

// Scrolling region
/// Set scrolling region .{top, bottom}
pub const SET_SCROLL_REGION = ESC ++ "[{d};{d}r";
pub const RESET_SCROLL_REGION = ESC ++ "[r";
pub const SCROLL_UP = ESC ++ "[S";
pub const SCROLL_DOWN = ESC ++ "[T";

// Line operations
pub const INSERT_LINE = ESC ++ "[L";
pub const DELETE_LINE = ESC ++ "[M";
pub const INSERT_LINES = ESC ++ "[{d}L";
pub const DELETE_LINES = ESC ++ "[{d}M";
