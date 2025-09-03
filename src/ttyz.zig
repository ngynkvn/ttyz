const std = @import("std");

const posix = std.posix;
const system = posix.system;

pub const CONFIG = .{
    // Disable tty's SIGINT handling,
    .HANDLE_SIGINT = true,
    .START_SEQUENCE = E.ENTER_ALT_SCREEN ++ E.CURSOR_INVISIBLE,
    .EXIT_SEQUENCE = E.EXIT_ALT_SCREEN ++ E.CURSOR_VISIBLE,
    .TTY_HANDLE = "/dev/tty",
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
const cc = std.ascii.control_code;
// zig fmt: on

pub const Screen = struct {
    orig_termios: posix.termios,
    tty: std.fs.File,
    width: u16,
    height: u16,
    buffer: [4096]u8,
    input_buffer: [32]u8,
    last_read: []u8,
    lock: std.Thread.Mutex,
    writer: std.fs.File.Writer,
    event_buffer: [32]Event,
    event_queue: std.ArrayList(Event),
    io_thread: ?std.Thread,
    running: bool,
    pub const Error = std.posix.WriteError;

    /// Enter "raw mode", returning a struct that wraps around the provided tty file
    /// Entering raw mode will automatically send the sequence for entering an
    /// alternate screen (smcup) and hiding the cursor.
    /// Use `defer Screen.deinit()` to reset on exit.
    /// Deferral will set the sequence for exiting alt screen (rmcup)
    ///
    /// Explanation here: https://viewsourcecode.org/snaptoken/kilo/02.enteringScreen.html
    /// https://zig.news/lhp/want-to-create-a-tui-application-the-basics-of-uncooked-terminal-io-17gm
    pub fn init() !Screen {
        const tty = try std.fs.openFileAbsolute(CONFIG.TTY_HANDLE, .{ .mode = .read_write });
        return try initFrom(tty);
    }

    pub fn initFrom(tty: std.fs.File) !Screen {
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
        raw.cc[@intFromEnum(system.V.TIME)] = 1;  // min time to wait for response, 100ms per unit
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
        std.log.debug("windowsize is {}x{}; xpixel={d}, ypixel={d}", .{ width, height, ws.xpixel, ws.ypixel });
        _ = try tty.write(CONFIG.START_SEQUENCE);
        var self: Screen = undefined;
        self = .{
            .orig_termios = orig_termios,
            .tty = tty,
            .running = true,
            .width = width,
            .height = height,
            .last_read = &.{},
            // writer
            .lock = .{},
            .buffer = std.mem.zeroes([4096]u8),
            .writer = tty.writer(&self.buffer),
            // input
            .input_buffer = std.mem.zeroes([32]u8),
            .io_thread = null,
            .event_buffer = undefined,
            .event_queue = std.ArrayList(Event).initBuffer(&self.event_buffer),
        };
        return self;
    }

    pub fn deinit(self: *Screen) !posix.E {
        self.running = false;
        if (self.io_thread) |thread| thread.join();
        _ = try self.tty.write(CONFIG.EXIT_SEQUENCE);
        const rc = system.tcsetattr(self.tty.handle, .FLUSH, &self.orig_termios);
        self.tty.close();
        return posix.errno(rc);
    }

    pub fn start(self: *Screen) !void {
        self.io_thread = std.Thread.spawn(.{}, Screen.ioLoop, .{self}) catch |e| {
            std.log.err("error spawning main loop: {s}", .{@errorName(e)});
            return e;
        };
    }

    pub fn ioLoop(self: *Screen) !void {
        while (self.running) {
            const n = self.read(&self.input_buffer) catch continue;
            self.last_read = self.input_buffer[0..n];
            self.collectEvents(self.input_buffer[0..n]);
        }
    }

    const ParseState = enum { start, esc, csi, csi_num, end };
    const Parser = struct {
        buf: []u8,
        i: usize,
        fn init(buf: []u8) Parser {
            return .{ .buf = buf, .i = 0 };
        }
        fn isEnd(self: *Parser) bool {
            return self.i >= self.buf.len;
        }
        fn next(self: *Parser) u8 {
            if (self.isEnd()) return 0;
            self.advance();
            return self.buf[self.i - 1];
        }
        fn remaining(self: *Parser) usize {
            if (self.isEnd()) return 0;
            return self.buf.len - self.i;
        }
        fn advance(self: *Parser) void {
            self.i += 1;
        }
        fn peek(self: *Parser) u8 {
            return self.buf[self.i];
        }
        fn expect(self: *Parser, c: u8) ?void {
            if (self.isEnd() or self.peek() != c) return null;
            self.advance();
        }
    };

    pub fn collectEvents(self: *Screen, buf: []u8) void {
        var p = Parser.init(buf);
        var event: ?Event = null;
        state: switch (ParseState.start) {
            .start => {
                switch (p.next()) {
                    'a'...'z', 'A'...'Z', '0'...'9' => |c| event = .{ .key = @enumFromInt(c) },
                    cc.esc => continue :state .esc,
                    else => break :state,
                }
            },
            .esc => {
                switch (p.next()) {
                    '[' => continue :state .csi,
                    else => break :state,
                }
            },
            .csi => {
                switch (p.next()) {
                    'A', 'B', 'C', 'D' => |c| event = .{ .key = .arrow(c) },
                    '0'...'9' => continue :state .csi_num,
                    else => break :state,
                }
            },
            .csi_num => {
                const s = p.i - 1;
                const last_byte = p.buf[p.buf.len - 1];
                switch (last_byte) {
                    'R' => event = parseCursorPos(p.buf[s .. p.buf.len - 1]),
                    else => break :state,
                }
            },
            .end => break :state,
        }
        if (event) |e| self.event_queue.appendBounded(e) catch {};
    }

    fn parseCursorPos(buf: []u8) ?Event {
        const sep = std.mem.indexOf(u8, buf, ";") orelse return null;
        const row = std.fmt.parseInt(u16, buf[0..sep], 10) catch return null;
        const col = std.fmt.parseInt(u16, buf[sep + 1 ..], 10) catch return null;
        return .{ .cursor_pos = .{ .row = row, .col = col } };
    }

    pub fn pollEvent(self: *Screen) ?Event {
        if (self.event_queue.items.len == 0) return null;
        return self.event_queue.orderedRemove(0);
    }

    /// Move cursor to (x, y) (column, row)
    /// (0, 0) is defined as the bottom left corner of the terminal.
    pub fn goto(self: *Screen, r: u16, c: u16) !void {
        try self.print(E.GOTO, .{ r, c });
    }

    pub fn query(self: *Screen) !void {
        self.lock.lock();
        defer self.lock.unlock();
        _ = try self.tty.write(E.REPORT_CURSOR_POS);
    }

    /// read input
    pub fn read(self: *Screen, buffer: []u8) !usize {
        return self.tty.read(buffer);
    }

    /// print to screen via fmt string
    pub fn print(self: *Screen, comptime fmt: []const u8, args: anytype) !void {
        try self.printArgs(fmt, args, .{});
    }

    /// raw write
    pub fn write(self: *Screen, buf: []const u8) !usize {
        self.lock.lock();
        defer self.lock.unlock();
        return try self.writer.interface.write(buf);
    }

    pub fn writeAll(self: *Screen, buf: []const u8) !void {
        self.lock.lock();
        defer self.lock.unlock();
        try self.writer.interface.writeAll(buf);
    }

    pub const WriteArgs = struct { sleep: usize = 0 };
    pub fn printArgs(self: *Screen, comptime fmt: []const u8, args: anytype, wargs: WriteArgs) !void {
        self.lock.lock();
        defer self.lock.unlock();
        // TODO: check if this will exclude this code from being added at comptime
        if (wargs.sleep != 0) std.Thread.sleep(wargs.sleep);
        try self.writer.interface.print(fmt, args);
    }

    pub fn flush(self: *Screen) !void {
        self.lock.lock();
        defer self.lock.unlock();
        return self.writer.interface.flush();
    }
};

pub const Event = union(enum) {
    // ASCII letters
    pub const Key = enum(u8) {
        esc = 27,
        arrow_up,
        arrow_down,
        arrow_right,
        arrow_left,
        // zig fmt: off
        @"0" = 48, @"1" = 49, @"2" = 50, @"3" = 51, @"4" = 52, @"5" = 53, @"6" = 54, @"7" = 55, @"8" = 56, @"9" = 57,

        A = 65, B = 66, C = 67, D = 68, E = 69, F = 70, G = 71, H = 72, 
        I = 73, J = 74, K = 75, L = 76, M = 77, N = 78, O = 79, P = 80, 
        Q = 81, R = 82, S = 83, T = 84, U = 85, V = 86, W = 87, X = 88, Y = 89, Z = 90,

        a = 97, b = 98, c = 99, d = 100, e = 101, f = 102, g = 103, h = 104, 
        i = 105, j = 106, k = 107, l = 108, m = 109, n = 110, o = 111, p = 112, 
        q = 113, r = 114, s = 115, t = 116, u = 117, v = 118, w = 119, x = 120, y = 121, z = 122,

        _,
        // zig fmt: on
        fn arrow(c: u8) Key {
            return switch (c) {
                'A' => .arrow_up,
                'B' => .arrow_down,
                'C' => .arrow_right,
                'D' => .arrow_left,
                else => unreachable,
            };
        }
    };
    pub const CursorPos = struct { row: usize, col: usize };
    key: Key,
    cursor_pos: CursorPos,
};
