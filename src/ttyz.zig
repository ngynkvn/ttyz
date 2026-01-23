//! ttyz - Terminal User Interface Library for Zig
//!
//! A library for building terminal user interfaces with support for:
//! - Raw mode terminal I/O with automatic state restoration
//! - Keyboard, mouse, and focus event handling
//! - VT100/xterm escape sequences
//! - Immediate-mode layout engine
//! - Kitty graphics protocol
//! - Box drawing and text utilities
//!
//! ## Quick Start
//! ```zig
//! var screen = try ttyz.Screen.init();
//! defer _ = screen.deinit() catch {};
//! try screen.start();
//!
//! while (screen.running) {
//!     while (screen.pollEvent()) |event| {
//!         // handle events
//!     }
//!     try screen.clearScreen();
//!     try screen.print("Hello, world!\n", .{});
//!     try screen.flush();
//! }
//! ```

const std = @import("std");
const assert = std.debug.assert;

const posix = std.posix;
const system = posix.system;

/// Kitty graphics protocol for terminal image display.
pub const kitty = @import("kitty.zig");

/// Pixel-level RGBA canvas drawing with Kitty output.
pub const draw = @import("draw.zig");

/// Box drawing with Unicode characters.
pub const termdraw = @import("termdraw.zig");

/// Immediate-mode UI layout engine.
pub const layout = @import("layout.zig");

/// Comptime color format string parser for inline ANSI colors.
pub const colorz = @import("colorz.zig");

/// Text utilities for padding, centering, and display width.
pub const text = @import("text.zig");

/// VT100/xterm escape sequence constants.
pub const E = @import("esc.zig");

/// Generic bounded ring buffer queue.
pub const BoundedQueue = @import("bounded_queue.zig").BoundedQueue;

/// Library configuration constants.
/// These control the default behavior when initializing a Screen.
///
/// Fields:
/// - `HANDLE_SIGINT`: If true, the library handles SIGINT (Ctrl+C) internally.
/// - `START_SEQUENCE`: Escape sequence sent when entering raw mode.
/// - `EXIT_SEQUENCE`: Escape sequence sent when exiting raw mode.
/// - `TTY_HANDLE`: Path to the TTY device.
pub const CONFIG = .{
    .HANDLE_SIGINT = true,
    .START_SEQUENCE = E.ENTER_ALT_SCREEN ++ E.CURSOR_INVISIBLE ++ E.ENABLE_MOUSE_TRACKING,
    .EXIT_SEQUENCE = E.EXIT_ALT_SCREEN ++ E.CURSOR_VISIBLE ++ E.DISABLE_MOUSE_TRACKING,
    .TTY_HANDLE = "/dev/tty",
};

const cc = std.ascii.control_code;
const ascii = std.ascii;
// zig fmt: on

var orig_termios: ?posix.termios = null;
var tty_handle: ?std.fs.File.Handle = null;

/// The main interface for terminal I/O operations.
///
/// Screen manages raw mode initialization, event handling, and output buffering.
/// It provides thread-safe methods for writing to the terminal and polling for
/// input events.
///
/// ## Example
/// ```zig
/// var screen = try Screen.init();
/// defer _ = screen.deinit() catch {};
///
/// try screen.start();  // Start the I/O thread
///
/// while (screen.running) {
///     while (screen.pollEvent()) |event| {
///         switch (event) {
///             .key => |k| if (k == .q) screen.running = false,
///             else => {},
///         }
///     }
///     try screen.clearScreen();
///     try screen.home();
///     try screen.print("Size: {}x{}\n", .{screen.width, screen.height});
///     try screen.flush();
/// }
/// ```
pub const Screen = struct {
    /// The underlying TTY file handle.
    tty: std.fs.File,
    /// Terminal width in columns.
    width: u16,
    /// Terminal height in rows.
    height: u16,
    /// Internal output buffer.
    buffer: [4096]u8,
    /// Last read data (internal use).
    last_read: []u8,
    /// Mutex for thread-safe output operations.
    lock: std.Thread.Mutex,
    /// Buffered writer for terminal output.
    writer: std.fs.File.Writer,
    /// Queue for pending input events.
    event_queue: BoundedQueue(Event, 32),
    /// Background I/O thread handle.
    io_thread: ?std.Thread,
    /// Set to false to stop the main loop and I/O thread.
    running: bool,
    /// Application state toggle (for demo purposes).
    toggle: bool,
    /// Buffer for text input.
    textinput_buffer: [32]u8,
    /// Text input accumulator.
    textinput: std.ArrayList(u8),

    /// Error type for Screen write operations.
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

    /// Initialize a Screen from an existing TTY file handle.
    /// This allows using a custom TTY instead of the default `/dev/tty`.
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
            .io_thread = null,
            .event_queue = BoundedQueue(Event, 32).init(),
            .toggle = false,
            .textinput_buffer = std.mem.zeroes([32]u8),
            .textinput = std.ArrayList(u8).initBuffer(&self.textinput_buffer),
        };
        const ws = try self.querySize();
        self.width = ws.col;
        self.height = ws.row;
        std.log.debug("windowsize is {}x{}; xpixel={d}, ypixel={d}", .{ self.width, self.height, ws.xpixel, ws.ypixel });

        _ = try tty.write(CONFIG.START_SEQUENCE);
        return self;
    }

    /// Clean up and restore terminal to its original state.
    /// Stops the I/O thread, restores terminal settings, and closes the TTY.
    /// Returns the errno from restoring terminal settings.
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
                    @atomicStore(bool, &Signals.WINCH, true, .seq_cst);
                },
                else => {
                    std.log.err("received unexpected signal: {d}", .{sig});
                },
            }
        }
    };

    /// Start the background I/O thread for event handling.
    /// This spawns a thread that reads input events and handles window resize signals.
    /// Call this after `init()` to enable event polling via `pollEvent()`.
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

    /// Internal I/O loop run by the background thread.
    /// Reads input, parses events, and handles window resize signals.
    fn ioLoop(self: *Screen) !void {
        var input_buffer = std.mem.zeroes([32]u8);
        var reader = self.tty.readerStreaming(&input_buffer);
        while (self.running) {
            if (Signals.WINCH) {
                const ws = try self.querySize();
                std.log.info("window resized: {[row]}x{[col]}; {[xpixel]}x{[ypixel]}", ws);
                self.width = ws.col;
                self.height = ws.row;
                @atomicStore(bool, &Signals.WINCH, false, .seq_cst);
            }
            const ev = Parser.collectEvents(&reader.interface) catch |e| {
                switch (e) {
                    error.UnknownEvent => {},
                    else => {},
                }
                continue;
            };
            self.event_queue.pushBackBounded(ev) catch {};
        }
    }

    /// Poll for the next input event.
    /// Returns `null` if no events are available.
    /// Events are queued by the background I/O thread started with `start()`.
    pub fn pollEvent(self: *Screen) ?Event {
        return self.event_queue.popFront();
    }

    /// Move cursor to the specified row and column.
    /// Coordinates are 1-based: (1, 1) is the top-left corner.
    pub fn goto(self: *Screen, r: u16, c: u16) !void {
        try self.print(E.GOTO, .{ r, c });
    }

    /// Send a cursor position query to the terminal.
    /// The response will be delivered as a `cursor_pos` event.
    pub fn queryPos(self: *Screen) !void {
        self.lock.lock();
        defer self.lock.unlock();
        _ = try self.tty.write(E.REPORT_CURSOR_POS);
    }

    /// Query the current terminal size.
    /// Returns a `winsize` struct with `row`, `col`, `xpixel`, and `ypixel` fields.
    pub fn querySize(self: *Screen) !posix.winsize {
        self.lock.lock();
        defer self.lock.unlock();
        return try queryHandleSize(self.tty.handle);
    }

    /// Read raw input bytes into the provided buffer.
    /// Returns the number of bytes read.
    pub fn read(self: *Screen, buffer: []u8) !usize {
        return self.tty.read(buffer);
    }

    /// Print formatted output to the terminal.
    /// Uses the same format syntax as `std.fmt`.
    pub fn print(self: *Screen, comptime fmt: []const u8, args: anytype) !void {
        try self.printArgs(fmt, args, .{});
    }

    /// Write raw bytes to the terminal.
    /// Returns the number of bytes written. Thread-safe.
    pub fn write(self: *Screen, buf: []const u8) !usize {
        self.lock.lock();
        defer self.lock.unlock();
        return try self.writer.interface.write(buf);
    }

    /// Write all bytes to the terminal.
    /// Thread-safe.
    pub fn writeAll(self: *Screen, buf: []const u8) !void {
        self.lock.lock();
        defer self.lock.unlock();
        try self.writer.interface.writeAll(buf);
    }

    /// Options for `printArgs`.
    pub const WriteArgs = struct {
        /// Optional sleep duration in nanoseconds before writing.
        sleep: usize = 0,
    };

    /// Print formatted output with additional options.
    /// Thread-safe.
    pub fn printArgs(self: *Screen, comptime fmt: []const u8, args: anytype, wargs: WriteArgs) !void {
        self.lock.lock();
        defer self.lock.unlock();
        if (wargs.sleep != 0) std.Thread.sleep(wargs.sleep);
        try self.writer.interface.print(fmt, args);
    }

    /// Flush the output buffer to the terminal.
    /// Call this after a series of writes to ensure output is displayed.
    pub fn flush(self: *Screen) !void {
        self.lock.lock();
        defer self.lock.unlock();
        return self.writer.interface.flush();
    }

    /// Clear the entire screen.
    pub fn clearScreen(self: *Screen) !void {
        try self.writeAll(E.CLEAR_SCREEN);
    }

    /// Move the cursor to the home position (top-left corner).
    pub fn home(self: *Screen) !void {
        try self.writeAll(E.HOME);
    }
};

/// Input event from the terminal.
/// Events are polled using `Screen.pollEvent()`.
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
        pub fn arrow(c: u8) Key {
            return switch (c) {
                'A' => .arrow_up,
                'B' => .arrow_down,
                'C' => .arrow_right,
                'D' => .arrow_left,
                else => unreachable,
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
    pub const MouseButton = enum { left, middle, right, scroll_up, scroll_down, unknown };

    /// State of a mouse button.
    pub const MouseButtonState = enum { pressed, released, motion, unknown };

    /// Cursor position in the terminal.
    pub const CursorPos = struct { row: usize, col: usize };

    /// Mouse event data.
    pub const Mouse = struct {
        button: MouseButton,
        row: usize,
        col: usize,
        button_state: MouseButtonState,
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
};

const Parser = struct {
    const ParseState = enum { start, esc, csi, csi_num };
    pub fn collectEvents(r: *std.Io.Reader) !Event {
        try r.fillMore();
        defer r.tossBuffered();
        state: switch (ParseState.start) {
            .start => {
                const c = try r.takeByte();
                if (ascii.isPrint(c) or ascii.isWhitespace(c)) {
                    return .{ .key = @enumFromInt(c) };
                }
                return switch (try r.takeByte()) {
                    3 => .interrupt,
                    cc.esc => continue :state .esc,
                    else => break :state,
                };
            },
            .esc => {
                const c = r.takeByte() catch |e| if (e == error.EndOfStream) cc.esc else break :state;
                return switch (c) {
                    '[' => continue :state .csi,
                    else => break :state,
                };
            },
            .csi => {
                return switch (try r.peekByte()) {
                    'A', 'B', 'C', 'D' => .{ .key = .arrow(try r.takeByte()) },
                    '0'...'9' => continue :state .csi_num,
                    '<' => parseSgrMouse(r) catch error.UnknownEvent,
                    else => break :state,
                };
            },
            .csi_num => {
                const cursor_pos = try r.peekDelimiterExclusive('R');
                return parseCursorPos(cursor_pos) orelse error.UnknownEvent;
            },
        }
        return error.UnknownEvent;
    }

    pub fn parseCursorPos(buf: []u8) ?Event {
        const sep = std.mem.indexOf(u8, buf, ";") orelse return null;
        const row = std.fmt.parseInt(u16, buf[0..sep], 10) catch return null;
        const col = std.fmt.parseInt(u16, buf[sep + 1 ..], 10) catch return null;
        return .{ .cursor_pos = .{ .row = row, .col = col } };
    }

    pub fn parseSgrMouse(r: *std.Io.Reader) !Event {
        assert(try r.takeByte() == '<');
        const Pbutton = try r.takeDelimiter(';') orelse return error.UnknownEvent;
        const button: Event.MouseButton = switch (Pbutton[0]) {
            '0' => .left,
            '1' => .middle,
            '2' => .right,
            else => .unknown,
        };

        const Pcol = try r.takeDelimiter(';') orelse return error.UnknownEvent;
        const col = std.fmt.parseInt(u16, Pcol, 10) catch return error.UnknownEvent;

        const Prow_state = try r.peekGreedy(1);
        const row = std.fmt.parseInt(u16, Prow_state[0 .. Prow_state.len - 1], 10) catch return error.UnknownEvent;

        const Pbutton_state = Prow_state[Prow_state.len - 1];
        const button_state: Event.MouseButtonState = switch (Pbutton_state) {
            'M' => .pressed,
            'm' => .released,
            else => .unknown,
        };

        return .{ .mouse = .{ .button = button, .row = row, .col = col, .button_state = button_state } };
    }
};

/// Query the terminal size for a given file handle.
/// Returns a `winsize` struct with terminal dimensions.
pub fn queryHandleSize(handle: std.fs.File.Handle) !posix.winsize {
    var ws: posix.winsize = .{ .row = 0, .col = 0, .xpixel = 0, .ypixel = 0 };
    const result = system.ioctl(handle, posix.T.IOCGWINSZ, @intFromPtr(&ws));
    if (posix.errno(result) != .SUCCESS) return error.IoctlReturnedNonZero;
    return ws;
}

/// Custom panic handler that restores terminal state before panicking.
/// Assign to `pub const panic = ttyz.panic;` in your root source file
/// to ensure the terminal is restored even on panics.
pub const panic = std.debug.FullPanic(panicTty);

/// Internal panic handler implementation.
/// Restores terminal state before calling the default panic handler.
pub fn panicTty(msg: []const u8, ra: ?usize) noreturn {
    if (tty_handle) |handle| {
        const tty = std.fs.File{ .handle = handle };
        tty.writeAll(CONFIG.EXIT_SEQUENCE) catch {};
        if (orig_termios) |orig| _ = system.tcsetattr(tty.handle, .FLUSH, &orig);
    }
    std.log.err("panic: {s}", .{msg});
    std.debug.defaultPanic(msg, ra);
}

test {
    std.testing.refAllDecls(@This());
}
