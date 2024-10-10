const std = @import("std");

const posix = std.posix;
const system = posix.system;

pub const CONFIG = .{
    .SLOWDOWN = std.time.ns_per_ms * 0,
    // Disable tty's SIGINT handling,
    .HANDLE_SIGINT = true,
    .START_SEQUENCE = E.ENTER_ALT_SCREEN ++ E.CURSOR_INVISIBLE,
    .EXIT_SEQUENCE = E.EXIT_ALT_SCREEN ++ E.CURSOR_VISIBLE,
    .TTY_HANDLE = "/dev/tty",
    .TRACING = true,
};

/// vt100 / xterm escape sequences
/// References used:
///  - https://vt100.net/docs/vt100-ug/chapter3.html
///  - `man terminfo`, `man tput`, `man infocmp`
// zig fmt: off
pub const E = struct {
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
    /// setab .{color}
    pub const SET_ANSI_BG        = ESC ++ "4{d}m";
    /// set true color (rgb)
    pub const SET_TRUCOLOR       = ESC ++ "38;2;{};{};{}m";
    pub const RESET_COLORS       = ESC ++ "m";
};
// zig fmt: on

pub var nbytes: usize = 0;
pub var gotos: usize = 0;
pub const RawMode = struct {
    orig_termios: posix.termios,
    tty: std.fs.File,
    width: u16,
    height: u16,
    buffer: std.ArrayList(u8),
    pub const Error = std.posix.WriteError;
    pub const CursorPos = struct { row: usize, col: usize };

    /// Enter "raw mode", returning a struct that wraps around the provided tty file
    /// Entering raw mode will automatically send the sequence for entering an
    /// alternate screen (smcup) and hiding the cursor.
    /// Use `defer RawMode.deinit()` to reset on exit.
    /// Deferral will set the sequence for exiting alt screen (rmcup)
    ///
    /// Explanation here: https://viewsourcecode.org/snaptoken/kilo/02.enteringRawMode.html
    /// https://zig.news/lhp/want-to-create-a-tui-application-the-basics-of-uncooked-terminal-io-17gm
    pub fn init(allocator: std.mem.Allocator, tty: std.fs.File) !RawMode {
        const orig_termios = try posix.tcgetattr(tty.handle);
        var raw = orig_termios;
        // Some explanation of the flags can be found in the links above.
        // TODO: check out the other flags later
        // zig fmt: off
        raw.lflag.ECHO   = false;                 // Disable echo input
        raw.lflag.ICANON = false;                 // Read byte by byte
        raw.lflag.IEXTEN = false;                 // Disable <C-v>
        raw.lflag.ISIG   = !CONFIG.HANDLE_SIGINT; // Disable <C-c> and <C-z>
        raw.iflag.IXON   = false;                 // Disable <C-s> and <C-q>
        raw.iflag.ICRNL  = false;                 // Disable <C-m>
        raw.iflag.BRKINT = false;                 // Break condition sends SIGINT
        raw.iflag.INPCK  = false;                 // Enable parity checking
        raw.iflag.ISTRIP = false;                 // Strip 8th bit of input byte
        raw.oflag.OPOST  = false;                 // Disable translating "\n" to "\r\n"
        raw.cflag.CSIZE  = .CS8;

        raw.cc[@intFromEnum(system.V.MIN)]  = 0;  // min bytes required for read
        raw.cc[@intFromEnum(system.V.TIME)] = 0;  // min time to wait for response, 100ms per unit
        // zig fmt: on

        const rc = system.tcsetattr(tty.handle, .FLUSH, &raw);
        if (posix.errno(rc) != .SUCCESS) return error.CouldNotSetTermiosFlags;

        // IOCGWINSZ (io control get window size (?)) is a request signal for window size
        var ws: posix.winsize = .{ .row = 0, .col = 0, .xpixel = 0, .ypixel = 0 };
        // Get the window size via ioctl(2) call to tty
        const result = system.ioctl(tty.handle, posix.T.IOCGWINSZ, @intFromPtr(&ws));
        if (posix.errno(result) != .SUCCESS) return error.IoctlReturnedNonZero;

        const width = ws.col;
        const height = ws.row;
        std.log.debug("windowsize is {}x{}", .{ width, height });
        _ = try tty.write(CONFIG.START_SEQUENCE);
        const buffer = std.ArrayList(u8).init(allocator);
        const term = .{
            .orig_termios = orig_termios,
            .tty = tty,
            .width = width,
            .height = height,
            .buffer = buffer,
        };
        return term;
    }
    pub fn deinit(self: *RawMode) !posix.E {
        _ = try self.tty.write(CONFIG.EXIT_SEQUENCE);
        defer self.buffer.deinit();
        const rc = system.tcsetattr(self.tty.handle, .FLUSH, &self.orig_termios);
        return posix.errno(rc);
    }

    /// Move cursor to (x, y) (column, row)
    /// (0, 0) is defined as the bottom left corner of the terminal.
    pub fn goto(self: *RawMode, x: u16, y: u16) !void {
        try self.print(E.GOTO, .{ self.height - y, x });
        if (CONFIG.TRACING) gotos += E.GOTO.len;
    }
    /// goto origin based on top left (row, col)
    pub fn gotorc(self: *RawMode, r: u16, c: u16) !void {
        try self.print(E.GOTO, .{ r, c });
        if (CONFIG.TRACING) gotos += E.GOTO.len;
    }

    /// translates the given `(x, y)` coordinates to internal coordinate system
    pub fn translate_xy(self: *RawMode, x: u16, y: u16) struct { u16, u16 } {
        return .{ self.height - y, x };
    }
    pub fn query(self: *RawMode) !CursorPos {
        _ = try self.tty.write(E.REPORT_CURSOR_POS);
        // TODO: make this more durable
        var buf: [32]u8 = undefined;
        const n = try self.tty.read(&buf);
        if (!std.mem.startsWith(u8, &buf, E.ESC)) return error.UnknownResponse;
        const semi = std.mem.indexOf(u8, &buf, ";") orelse return error.ParseError;
        const row = try std.fmt.parseUnsigned(usize, buf[2..semi], 10);
        const col = try std.fmt.parseUnsigned(usize, buf[semi + 1 .. n - 1], 10);
        return .{ .row = row, .col = col };
    }
    /// read input
    pub fn read(self: *RawMode, buffer: []u8) !usize {
        return self.tty.read(buffer);
    }

    /// print to screen via fmt string
    pub fn print(self: *RawMode, comptime fmt: []const u8, args: anytype) !void {
        try self.printa(fmt, args, .{});
    }
    /// raw write
    pub fn write(self: *RawMode, buf: []const u8) !usize {
        if (CONFIG.SLOWDOWN != 0) std.Thread.sleep(CONFIG.SLOWDOWN);
        return try self.buffer.writer().write(buf);
    }

    pub const WriteArgs = struct { cursor: enum { KEEP, RESTORE_POS } = .KEEP, sleep: usize = 0 };
    pub fn printa(self: *RawMode, comptime fmt: []const u8, args: anytype, wargs: WriteArgs) !void {
        // TODO: check if this will exclude this code from being added at comptime
        if (CONFIG.SLOWDOWN != 0) std.Thread.sleep(CONFIG.SLOWDOWN);
        if (wargs.sleep != 0) std.Thread.sleep(wargs.sleep);
        _ = if (wargs.cursor == .RESTORE_POS) try self.buffer.appendSlice(E.CURSOR_SAVE_POS);
        if (wargs.cursor == .RESTORE_POS and CONFIG.TRACING) nbytes += E.CURSOR_SAVE_POS.len;
        try self.buffer.writer().print(fmt, args);
        if (CONFIG.TRACING) nbytes += fmt.len;
        _ = if (wargs.cursor == .RESTORE_POS) try self.buffer.appendSlice(E.CURSOR_RESTORE_POS);
        if (wargs.cursor == .RESTORE_POS and CONFIG.TRACING) nbytes += E.CURSOR_SAVE_POS.len;
    }

    pub fn flush(self: *RawMode) !void {
        try self.tty.writeAll(self.buffer.items);
        self.buffer.clearRetainingCapacity();
    }
};
