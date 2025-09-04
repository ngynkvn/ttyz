const std = @import("std");

const posix = std.posix;
const system = posix.system;

pub const kitty = @import("kitty.zig");
pub const draw = @import("draw.zig");
pub const termdraw = @import("termdraw.zig");
pub const layout = @import("layout.zig");
pub const colorz = @import("colorz.zig");
pub const E = @import("esc.zig");

pub const CONFIG = .{
    // Disable tty's SIGINT handling,
    .HANDLE_SIGINT = true,
    .START_SEQUENCE = E.ENTER_ALT_SCREEN ++ E.CURSOR_INVISIBLE ++ E.ENABLE_MOUSE_TRACKING,
    .EXIT_SEQUENCE = E.EXIT_ALT_SCREEN ++ E.CURSOR_VISIBLE ++ E.DISABLE_MOUSE_TRACKING,
    .TTY_HANDLE = "/dev/tty",
};

const cc = std.ascii.control_code;
// zig fmt: on

var orig_termios: ?posix.termios = null;
var tty_handle: ?std.fs.File.Handle = null;
pub const Screen = struct {
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
        _ = termdraw;
        const tty = try std.fs.openFileAbsolute(CONFIG.TTY_HANDLE, .{ .mode = .read_write });
        return try initFrom(tty);
    }

    pub fn initFrom(tty: std.fs.File) !Screen {
        tty_handle = tty.handle;
        const orig = try posix.tcgetattr(tty.handle);
        orig_termios = orig;

        var raw = orig;
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

        var self: Screen = undefined;
        self = .{
            .tty = tty,
            .running = true,
            .width = 0,
            .height = 0,
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
        const ws = try self.querySize();
        self.width = ws.col;
        self.height = ws.row;
        std.log.debug("windowsize is {}x{}; xpixel={d}, ypixel={d}", .{ self.width, self.height, ws.xpixel, ws.ypixel });

        _ = try tty.write(CONFIG.START_SEQUENCE);
        return self;
    }

    pub fn deinit(self: *Screen) !posix.E {
        self.running = false;
        if (self.io_thread) |thread| thread.join();
        _ = try self.tty.write(CONFIG.EXIT_SEQUENCE);
        const rc = if (orig_termios) |orig|
            system.tcsetattr(self.tty.handle, .FLUSH, &orig)
        else
            0;
        self.tty.close();
        return posix.errno(rc);
    }

    const Signals = struct {
        var WINCH: bool = false;
        var INTERRUPT: bool = false;
        pub const Signal = enum(c_int) {
            WINCH = std.posix.SIG.WINCH,
            INTERRUPT = std.posix.SIG.INT,
            _,
        };
        fn handleSignals(sig: c_int) callconv(.c) void {
            switch (@as(Signal, @enumFromInt(sig))) {
                .WINCH => {
                    std.log.info("window resized", .{});
                    @atomicStore(bool, &Signals.WINCH, true, .monotonic);
                },
                else => {
                    std.log.err("received unexpected signal: {d}", .{sig});
                },
            }
        }
    };

    pub fn start(self: *Screen) !void {
        const sa = std.posix.Sigaction{
            .flags = std.posix.SA.RESTART,
            .mask = std.posix.sigemptyset(),
            .handler = .{ .handler = Signals.handleSignals },
        };
        std.posix.sigaction(std.posix.SIG.WINCH, &sa, null);
        self.io_thread = std.Thread.spawn(.{}, Screen.ioLoop, .{self}) catch |e| {
            std.log.err("error spawning main loop: {s}", .{@errorName(e)});
            return e;
        };
    }

    pub fn ioLoop(self: *Screen) !void {
        while (self.running) {
            if (Signals.WINCH) {
                const ws = try self.querySize();
                self.width = ws.col;
                self.height = ws.row;
                @atomicStore(bool, &Signals.WINCH, false, .monotonic);
            }
            const n = self.read(&self.input_buffer) catch continue;
            self.last_read = self.input_buffer[0..n];
            const ev = Parser.collectEvents(self.input_buffer[0..n]);
            if (ev) |e| self.event_queue.appendBounded(e) catch {};
        }
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

    pub fn queryPos(self: *Screen) !void {
        self.lock.lock();
        defer self.lock.unlock();
        _ = try self.tty.write(E.REPORT_CURSOR_POS);
    }

    pub fn querySize(self: *Screen) !posix.winsize {
        self.lock.lock();
        defer self.lock.unlock();
        return try queryHandleSize(self.tty.handle);
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

    pub fn clearScreen(self: *Screen) !void {
        try self.writeAll(E.CLEAR_SCREEN);
    }

    pub fn home(self: *Screen) !void {
        try self.writeAll(E.HOME);
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
    interrupt: void,
};

pub const panic = std.debug.FullPanic(panicTty);

pub fn panicTty(msg: []const u8, ra: ?usize) noreturn {
    if (tty_handle) |handle| {
        const tty = std.fs.File{ .handle = handle };
        tty.writeAll(CONFIG.EXIT_SEQUENCE) catch {};
        if (orig_termios) |orig| _ = system.tcsetattr(tty.handle, .FLUSH, &orig);
    }
    std.debug.defaultPanic(msg, ra);
}

pub fn queryHandleSize(handle: std.fs.File.Handle) !posix.winsize {
    var ws: posix.winsize = .{ .row = 0, .col = 0, .xpixel = 0, .ypixel = 0 };
    const result = system.ioctl(handle, posix.T.IOCGWINSZ, @intFromPtr(&ws));
    if (posix.errno(result) != .SUCCESS) return error.IoctlReturnedNonZero;
    return ws;
}

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

    const ParseState = enum { start, esc, csi, csi_num };
    pub fn collectEvents(buf: []u8) ?Event {
        var p = Parser.init(buf);
        var event: ?Event = null;
        state: switch (ParseState.start) {
            .start => {
                switch (p.next()) {
                    'a'...'z', 'A'...'Z', '0'...'9' => |c| event = .{ .key = @enumFromInt(c) },
                    3 => event = .interrupt,
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
                    '<' => event = parseSgrMouse(p.buf[p.i..]),
                    else => break :state,
                }
            },
            .csi_num => {
                const s = p.i - 1;
                const last_byte = p.buf[p.buf.len - 1];
                switch (last_byte) {
                    'R' => event = parseCursorPos(p.buf[s .. p.buf.len - 1]),
                    else => std.debug.panic("unexpected last byte: {c}; {s}", .{ last_byte, p.buf[s..] }),
                }
            },
        }
        return event;
    }

    pub fn parseCursorPos(buf: []u8) ?Event {
        const sep = std.mem.indexOf(u8, buf, ";") orelse return null;
        const row = std.fmt.parseInt(u16, buf[0..sep], 10) catch return null;
        const col = std.fmt.parseInt(u16, buf[sep + 1 ..], 10) catch return null;
        return .{ .cursor_pos = .{ .row = row, .col = col } };
    }
    pub fn parseSgrMouse(buf: []u8) ?Event {
        std.log.info("parseSgrMouse: {s}", .{buf});
        return null;
        // const sep = std.mem.indexOf(u8, buf, ";") orelse return null;
        // const row = std.fmt.parseInt(u16, buf[0..sep], 10) catch return null;
        // const col = std.fmt.parseInt(u16, buf[sep + 1 ..], 10) catch return null;
        // return .{ .cursor_pos = .{ .row = row, .col = col } };
    }
};

pub fn _cast(T: type, value: anytype) T {
    return std.math.lossyCast(T, value);
}

test {
    std.testing.refAllDecls(@This());
}
