//! Screen - Main terminal I/O interface
//!
//! Manages raw mode initialization, event handling, and output buffering.

const std = @import("std");
const posix = std.posix;
const system = posix.system;

const E = @import("esc.zig");
const parser = @import("parser.zig");
const BoundedQueue = @import("bounded_queue.zig").BoundedQueue;
const Event = @import("event.zig").Event;

/// Library configuration constants.
pub const CONFIG = .{
    .HANDLE_SIGINT = true,
    .START_SEQUENCE = E.ENTER_ALT_SCREEN ++ E.CURSOR_INVISIBLE ++ E.ENABLE_MOUSE_TRACKING,
    .EXIT_SEQUENCE = E.EXIT_ALT_SCREEN ++ E.CURSOR_VISIBLE ++ E.DISABLE_MOUSE_TRACKING,
    .TTY_PATH = "/dev/tty",
};

var orig_termios: ?posix.termios = null;
var tty_fd: ?posix.fd_t = null;

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
    /// Error type for Screen write operations.
    pub const WriteError = error{WriteFailed};
    pub const ReadError = error{ReadFailed};

    /// Options for `printArgs`.
    pub const WriteArgs = struct {
        /// Optional sleep duration in nanoseconds before writing.
        sleep: usize = 0,
    };

    pub const Signals = struct {
        pub var WINCH: bool = false;
        pub var INTERRUPT: bool = false;
        pub fn handleSignals(sig: std.posix.SIG) callconv(.c) void {
            if (sig == std.posix.SIG.WINCH) {
                @atomicStore(bool, &Signals.WINCH, true, .seq_cst);
            } else {
                std.log.err("received unexpected signal: {}", .{sig});
            }
        }
    };

    file: std.Io.File,
    /// The underlying TTY file descriptor.
    fd: posix.fd_t,
    /// Terminal width in columns.
    width: u16,
    /// Terminal height in rows.
    height: u16,
    /// Mutex for thread-safe output operations.
    lock: std.Thread.Mutex,
    /// Buffered writer for terminal output.
    writer: std.Io.File.Writer,
    /// Buffer for the writer.
    writer_buffer: [4096]u8,
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
    /// ANSI escape sequence parser for input.
    input_parser: parser.Parser,

    /// Enter "raw mode", returning a struct that wraps around the provided tty file
    /// Entering raw mode will automatically send the sequence for entering an
    /// alternate screen (smcup) and hiding the cursor.
    /// Use `defer Screen.deinit()` to reset on exit.
    /// Deferral will set the sequence for exiting alt screen (rmcup)
    ///
    /// Explanation here: https://viewsourcecode.org/snaptoken/kilo/02.enteringScreen.html
    /// https://zig.news/lhp/want-to-create-a-tui-application-the-basics-of-uncooked-terminal-io-17gm
    pub fn init(io: std.Io) !Screen {
        const f = try std.Io.Dir.openFileAbsolute(io, CONFIG.TTY_PATH, .{ .mode = .read_write });
        return try initFrom(io, f);
    }

    /// Initialize a Screen from an existing TTY file descriptor.
    /// This allows using a custom TTY instead of the default `/dev/tty`.
    pub fn initFrom(io: std.Io, f: std.Io.File) !Screen {
        const fd = f.handle;
        tty_fd = fd;
        const orig = try posix.tcgetattr(fd);
        orig_termios = orig;

        var raw = orig;
        // Some explanation of the flags can be found in the links above.
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

        const setrc = system.tcsetattr(fd, .FLUSH, &raw);
        if (posix.errno(setrc) != .SUCCESS) return error.CouldNotSetTermiosFlags;

        var self: Screen = undefined;
        self = .{
            .file = f,
            .fd = fd,
            .running = true,
            .width = 0,
            .height = 0,
            .lock = .{},
            .writer = f.writerStreaming(io, &self.writer_buffer),
            .writer_buffer = undefined,
            // input
            .io_thread = null,
            .event_queue = BoundedQueue(Event, 32).init(),
            .toggle = false,
            .textinput_buffer = std.mem.zeroes([32]u8),
            .textinput = std.ArrayList(u8).initBuffer(&self.textinput_buffer),
            .input_parser = parser.Parser.init(),
        };

        const ws = try self.querySize();
        self.width = ws.col;
        self.height = ws.row;
        std.log.debug("windowsize is {}x{}; xpixel={d}, ypixel={d}", .{ self.width, self.height, ws.xpixel, ws.ypixel });

        _ = try self.writeRawDirect(CONFIG.START_SEQUENCE);
        return self;
    }

    /// Write bytes directly to terminal (bypasses buffer).
    fn writeRawDirect(self: *Screen, bytes: []const u8) !usize {
        const n = try self.writer.interface.write(bytes);
        try self.writer.flush();
        return n;
    }

    /// Write bytes to the buffered writer.
    fn writeRaw(self: *Screen, bytes: []const u8) !usize {
        _ = self;
        _ = bytes;
        @compileError("unused");
    }

    /// Flush the buffered writer to terminal.
    fn flushBuffer(self: *Screen) !void {
        _ = self;
        @compileError("unused");
    }

    /// Clean up and restore terminal to its original state.
    /// Stops the I/O thread, restores terminal settings, and closes the TTY.
    /// Returns the errno from restoring terminal settings.
    pub fn deinit(self: *Screen) !posix.E {
        self.running = false;
        if (self.io_thread) |thread| thread.join();
        _ = try self.writeRawDirect(CONFIG.EXIT_SEQUENCE);
        const rc = if (orig_termios) |orig|
            system.tcsetattr(self.fd, .FLUSH, &orig)
        else
            0;
        _ = system.close(self.fd);
        return posix.errno(rc);
    }

    /// Convert parser action to an Event, if applicable.
    pub fn actionToEvent(self: *Screen, action: parser.Action, byte: u8) ?Event {
        switch (action) {
            .execute => {
                // Handle C0 control characters
                if (byte == 3) return .interrupt; // Ctrl+C
                if (byte == '\r' or byte == '\n') return .{ .key = .carriage_return };
                if (byte == '\t') return .{ .key = .tab };
                if (byte == 0x1B) return .{ .key = .esc }; // ESC alone
                return null;
            },
            .print => {
                // Printable character
                return .{ .key = @enumFromInt(byte) };
            },
            .csi_dispatch => {
                return self.parseCsiEvent();
            },
            .osc_end => {
                // Check for focus events (OSC 1004)
                const osc_data = self.input_parser.getOscData();
                if (osc_data.len > 0) {
                    if (osc_data[0] == 'I') return .{ .focus = true };
                    if (osc_data[0] == 'O') return .{ .focus = false };
                }
                return null;
            },
            else => return null,
        }
    }

    /// Parse a CSI sequence into an Event.
    fn parseCsiEvent(self: *Screen) ?Event {
        const p = &self.input_parser;
        const final = p.final_char;
        const params = p.getParams();

        // Arrow keys and simple navigation
        switch (final) {
            'A' => return .{ .key = .arrow_up },
            'B' => return .{ .key = .arrow_down },
            'C' => return .{ .key = .arrow_right },
            'D' => return .{ .key = .arrow_left },
            'H' => return .{ .key = .home },
            'F' => return .{ .key = .end },
            'Z' => return .{ .key = .backtab },
            'R' => {
                // Cursor position response
                if (params.len >= 2) {
                    return .{ .cursor_pos = .{
                        .row = params[0],
                        .col = params[1],
                    } };
                }
                return null;
            },
            '~' => {
                // Function keys and special keys
                if (params.len >= 1) {
                    if (Event.Key.fromCsiNum(@intCast(params[0]), '~')) |key| {
                        return .{ .key = key };
                    }
                }
                return null;
            },
            'M', 'm' => {
                // SGR extended mouse coordinates (private marker '<')
                // Format: CSI < Cb ; Cx ; Cy M (press) or m (release)
                if (p.private_marker == '<' and params.len >= 3) {
                    var mouse = Event.Mouse.fromButtonCode(params[0], final);
                    mouse.col = params[1];
                    mouse.row = params[2];
                    return .{ .mouse = mouse };
                }
                return null;
            },
            'I' => return .{ .focus = true },
            'O' => return .{ .focus = false },
            else => return null,
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
        _ = try self.writeRawDirect(E.REPORT_CURSOR_POS);
    }

    /// Query the current terminal size.
    /// Returns a `winsize` struct with `row`, `col`, `xpixel`, and `ypixel` fields.
    pub fn querySize(self: *Screen) !posix.winsize {
        self.lock.lock();
        defer self.lock.unlock();
        return try queryHandleSize(self.fd);
    }

    /// Read raw input bytes into the provided buffer.
    /// Returns the number of bytes read.
    pub fn read(self: *Screen, buffer: []u8) ReadError!usize {
        const rc = system.read(self.fd, buffer.ptr, buffer.len);
        if (rc < 0) return error.ReadFailed;
        return @intCast(rc);
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

    /// Print formatted output with additional options.
    /// Thread-safe.
    pub fn printArgs(self: *Screen, comptime fmt: []const u8, args: anytype, wargs: WriteArgs) !void {
        self.lock.lock();
        defer self.lock.unlock();
        if (wargs.sleep != 0) {
            const ts = std.c.timespec{
                .sec = @intCast(wargs.sleep / std.time.ns_per_s),
                .nsec = @intCast(wargs.sleep % std.time.ns_per_s),
            };
            _ = std.c.nanosleep(&ts, null);
        }
        try self.writer.interface.print(fmt, args);
    }

    /// Flush the output buffer to the terminal.
    /// Call this after a series of writes to ensure output is displayed.
    pub fn flush(self: *Screen) !void {
        self.lock.lock();
        defer self.lock.unlock();
        try self.writer.flush();
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

/// Query the terminal size for a given file descriptor.
/// Returns a `winsize` struct with terminal dimensions.
pub fn queryHandleSize(fd: posix.fd_t) !posix.winsize {
    var ws: posix.winsize = .{ .row = 0, .col = 0, .xpixel = 0, .ypixel = 0 };
    const result = system.ioctl(fd, posix.T.IOCGWINSZ, @intFromPtr(&ws));
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
    if (tty_fd) |fd| {
        _ = system.write(fd, CONFIG.EXIT_SEQUENCE.ptr, CONFIG.EXIT_SEQUENCE.len);
        if (orig_termios) |orig| _ = system.tcsetattr(fd, .FLUSH, &orig);
    }
    std.log.err("panic: {s}", .{msg});
    std.debug.defaultPanic(msg, ra);
}
