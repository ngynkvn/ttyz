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

var orig_termios: ?posix.termios = null;
var tty_fd: ?posix.fd_t = null;

/// The main interface for terminal I/O operations.
///
/// Screen manages raw mode initialization, event handling, and output buffering.
/// It provides thread-safe methods for writing to the terminal and polling for
/// input events.
pub const Screen = struct {
    /// Error type for Screen write operations.
    pub const WriteError = error{WriteFailed};
    pub const ReadError = error{ReadFailed};

    /// Options for `printArgs`.
    pub const WriteArgs = struct {
        /// Optional sleep duration in nanoseconds before writing.
        sleep: usize = 0,
    };

    /// Configuration options for Screen initialization.
    pub const Options = struct {
        /// Buffer for the output writer.
        writer: []u8,
        /// Buffer for text input accumulation.
        textinput: []u8,
        /// Buffer for the event queue.
        events: []Event,
        /// Path to the TTY device.
        tty_path: []const u8 = "/dev/tty",
        /// Whether to handle SIGINT (Ctrl+C) as an event instead of terminating.
        handle_sigint: bool = true,
        /// Whether to use alternate screen buffer.
        alt_screen: bool = true,
        /// Whether to hide the cursor.
        hide_cursor: bool = true,
        /// Whether to enable mouse tracking.
        mouse_tracking: bool = true,

        // Default buffer sizes
        pub const default_writer_size = 4096;
        pub const default_textinput_size = 32;
        pub const default_events_size = 32;

        /// Default options using static buffers.
        pub const default: Options = .{
            .writer = &default_writer_buf,
            .textinput = &default_textinput_buf,
            .events = &default_events_buf,
        };

        var default_writer_buf: [default_writer_size]u8 = undefined;
        var default_textinput_buf: [default_textinput_size]u8 = undefined;
        var default_events_buf: [default_events_size]Event = undefined;
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
    /// Queue for pending input events.
    event_queue: BoundedQueue(Event),
    /// Set to false to stop the main loop.
    running: bool,
    /// Text input accumulator.
    textinput: std.ArrayList(u8),
    /// ANSI escape sequence parser for input.
    input_parser: parser.Parser,
    /// Stored options for cleanup.
    options: Options,

    /// Enter "raw mode", returning a struct that wraps around the provided tty file
    pub fn init(io: std.Io, options: Options) !Screen {
        const f = try std.Io.Dir.openFileAbsolute(io, options.tty_path, .{ .mode = .read_write });
        return try initFrom(io, f, options);
    }

    /// Initialize a Screen from an existing TTY file descriptor.
    pub fn initFrom(io: std.Io, f: std.Io.File, options: Options) !Screen {
        const fd = f.handle;
        tty_fd = fd;
        const orig = try posix.tcgetattr(fd);
        orig_termios = orig;

        var raw = orig;
        // zig fmt: off
        raw.lflag.ECHO   = false;
        raw.lflag.ICANON = false;
        raw.lflag.IEXTEN = false;
        raw.lflag.ISIG   = !options.handle_sigint;
        raw.iflag.IXON   = false;
        raw.iflag.ICRNL  = false;
        raw.iflag.BRKINT = false;
        raw.iflag.INPCK  = false;
        raw.iflag.ISTRIP = false;
        raw.oflag.OPOST  = false;
        raw.cflag.CSIZE  = .CS8;

        raw.cc[@intFromEnum(system.V.MIN)]  = 0;
        raw.cc[@intFromEnum(system.V.TIME)] = 1;
        // zig fmt: on

        const setrc = system.tcsetattr(fd, .FLUSH, &raw);
        if (posix.errno(setrc) != .SUCCESS) return error.CouldNotSetTermiosFlags;

        var self = Screen{
            .file = f,
            .fd = fd,
            .running = true,
            .width = 0,
            .height = 0,
            .lock = .{},
            .writer = f.writerStreaming(io, options.writer),
            .event_queue = BoundedQueue(Event).init(options.events),
            .textinput = std.ArrayList(u8).initBuffer(options.textinput),
            .input_parser = parser.Parser.init(),
            .options = options,
        };

        const ws = try self.querySize();
        self.width = ws.col;
        self.height = ws.row;
        std.log.debug("windowsize is {}x{}; xpixel={d}, ypixel={d}", .{ self.width, self.height, ws.xpixel, ws.ypixel });

        try self.writeStartSequences();
        return self;
    }

    /// Write startup escape sequences based on options.
    fn writeStartSequences(self: *Screen) !void {
        if (self.options.alt_screen) _ = try self.writeRawDirect(E.ENTER_ALT_SCREEN);
        if (self.options.hide_cursor) _ = try self.writeRawDirect(E.CURSOR_INVISIBLE);
        if (self.options.mouse_tracking) _ = try self.writeRawDirect(E.ENABLE_MOUSE_TRACKING);
    }

    /// Write cleanup escape sequences based on options.
    fn writeExitSequences(self: *Screen) !void {
        if (self.options.mouse_tracking) _ = try self.writeRawDirect(E.DISABLE_MOUSE_TRACKING);
        if (self.options.hide_cursor) _ = try self.writeRawDirect(E.CURSOR_VISIBLE);
        if (self.options.alt_screen) _ = try self.writeRawDirect(E.EXIT_ALT_SCREEN);
    }

    /// Write bytes directly to terminal (bypasses buffer).
    fn writeRawDirect(self: *Screen, bytes: []const u8) !usize {
        const n = try self.writer.interface.write(bytes);
        try self.writer.flush();
        return n;
    }

    /// Clean up and restore terminal to its original state.
    pub fn deinit(self: *Screen) !posix.E {
        self.running = false;
        try self.writeExitSequences();
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
                if (byte == 3) return .interrupt;
                if (byte == '\r' or byte == '\n') return .{ .key = .carriage_return };
                if (byte == '\t') return .{ .key = .tab };
                if (byte == 0x1B) return .{ .key = .esc };
                return null;
            },
            .print => {
                return .{ .key = @enumFromInt(byte) };
            },
            .csi_dispatch => {
                return self.parseCsiEvent();
            },
            .osc_end => {
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

        switch (final) {
            'A' => return .{ .key = .arrow_up },
            'B' => return .{ .key = .arrow_down },
            'C' => return .{ .key = .arrow_right },
            'D' => return .{ .key = .arrow_left },
            'H' => return .{ .key = .home },
            'F' => return .{ .key = .end },
            'Z' => return .{ .key = .backtab },
            'R' => {
                if (params.len >= 2) {
                    return .{ .cursor_pos = .{
                        .row = params[0],
                        .col = params[1],
                    } };
                }
                return null;
            },
            '~' => {
                if (params.len >= 1) {
                    if (Event.Key.fromCsiNum(@intCast(params[0]), '~')) |key| {
                        return .{ .key = key };
                    }
                }
                return null;
            },
            'M', 'm' => {
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
    pub fn pollEvent(self: *Screen) ?Event {
        return self.event_queue.popFront();
    }

    /// Push an event to the queue.
    pub fn pushEvent(self: *Screen, event: Event) void {
        self.event_queue.pushBackBounded(event) catch {};
    }

    /// Read input from TTY and queue events.
    /// Non-blocking due to termios VMIN=0, VTIME=1 settings.
    pub fn readAndQueueEvents(self: *Screen) void {
        var input_buffer: [32]u8 = undefined;
        const rc = system.read(self.fd, &input_buffer, input_buffer.len);
        if (rc <= 0) return;

        const bytes_read: usize = @intCast(rc);
        for (input_buffer[0..bytes_read]) |byte| {
            const action = self.input_parser.advance(byte);
            if (self.actionToEvent(action, byte)) |ev| {
                self.pushEvent(ev);
            }
        }
    }

    /// Move cursor to the specified row and column.
    pub fn goto(self: *Screen, r: u16, c: u16) !void {
        try self.print(E.GOTO, .{ r, c });
    }

    /// Send a cursor position query to the terminal.
    pub fn queryPos(self: *Screen) !void {
        self.lock.lock();
        defer self.lock.unlock();
        _ = try self.writeRawDirect(E.REPORT_CURSOR_POS);
    }

    /// Query the current terminal size.
    pub fn querySize(self: *Screen) !posix.winsize {
        self.lock.lock();
        defer self.lock.unlock();
        return try queryHandleSize(self.fd);
    }

    /// Read raw input bytes into the provided buffer.
    pub fn read(self: *Screen, buffer: []u8) ReadError!usize {
        const rc = system.read(self.fd, buffer.ptr, buffer.len);
        if (rc < 0) return error.ReadFailed;
        return @intCast(rc);
    }

    /// Print formatted output to the terminal.
    pub fn print(self: *Screen, comptime fmt: []const u8, args: anytype) !void {
        try self.printArgs(fmt, args, .{});
    }

    /// Write raw bytes to the terminal.
    pub fn write(self: *Screen, buf: []const u8) !usize {
        self.lock.lock();
        defer self.lock.unlock();
        return try self.writer.interface.write(buf);
    }

    /// Write all bytes to the terminal.
    pub fn writeAll(self: *Screen, buf: []const u8) !void {
        self.lock.lock();
        defer self.lock.unlock();
        try self.writer.interface.writeAll(buf);
    }

    /// Print formatted output with additional options.
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

    /// Clear screen and move cursor to home position.
    pub fn reset(self: *Screen) !void {
        try self.writeAll(E.CLEAR_SCREEN ++ E.HOME);
    }

    /// Hide the cursor.
    pub fn hideCursor(self: *Screen) !void {
        try self.writeAll(E.CURSOR_INVISIBLE);
    }

    /// Show the cursor.
    pub fn showCursor(self: *Screen) !void {
        try self.writeAll(E.CURSOR_VISIBLE);
    }
};

/// Query the terminal size for a given file descriptor.
pub fn queryHandleSize(fd: posix.fd_t) !posix.winsize {
    var ws: posix.winsize = .{ .row = 0, .col = 0, .xpixel = 0, .ypixel = 0 };
    const result = system.ioctl(fd, posix.T.IOCGWINSZ, @intFromPtr(&ws));
    if (posix.errno(result) != .SUCCESS) return error.IoctlReturnedNonZero;
    return ws;
}

/// Custom panic handler that restores terminal state before panicking.
pub const panic = std.debug.FullPanic(panicTty);

pub fn panicTty(msg: []const u8, ra: ?usize) noreturn {
    if (tty_fd) |fd| {
        const exit_seq = E.EXIT_ALT_SCREEN ++ E.CURSOR_VISIBLE ++ E.DISABLE_MOUSE_TRACKING;
        _ = system.write(fd, exit_seq.ptr, exit_seq.len);
        if (orig_termios) |orig| _ = system.tcsetattr(fd, .FLUSH, &orig);
    }
    std.log.err("panic: {s}", .{msg});
    std.debug.defaultPanic(msg, ra);
}
