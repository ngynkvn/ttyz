//! Screen - Main terminal I/O interface
//!
//! Manages raw mode initialization, event handling, and output buffering.
//! Supports both real TTY and test backends for output capture.

const std = @import("std");
const assert = std.debug.assert;
const posix = std.posix;
const system = posix.system;

const ansi = @import("ansi.zig");
const backend_mod = @import("backend.zig");
pub const Backend = backend_mod.Backend;
pub const TtyBackend = backend_mod.TtyBackend;
pub const TestBackend = backend_mod.TestBackend;
const Event = @import("event.zig").Event;
const parser = @import("parser.zig");

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

    /// Backend for I/O operations (TTY or test).
    backend: Backend,
    /// Terminal width in columns.
    width: u16,
    /// Terminal height in rows.
    height: u16,
    /// Mutex for thread-safe output operations.
    lock: std.Thread.Mutex,
    /// Queue for pending input events.
    event_queue: std.Deque(Event),
    /// Set to false to stop the main loop.
    running: bool,
    /// Text input accumulator.
    textinput: std.ArrayList(u8),
    /// ANSI escape sequence parser for input.
    input_parser: parser.Parser,
    /// Stored options for cleanup.
    options: Options,

    // Legacy field for backward compatibility - returns fd from TTY backend or -1
    pub fn getFd(self: *Screen) posix.fd_t {
        return switch (self.backend) {
            .tty => |t| t.fd,
            .testing => -1,
        };
    }

    /// Enter "raw mode", returning a struct that wraps around the provided tty file
    pub fn init(io: std.Io, options: Options) !Screen {
        const tty_backend = try TtyBackend.init(io, options.tty_path, options.writer, options.handle_sigint);
        return try initWithBackend(.{ .tty = tty_backend }, options);
    }

    /// Initialize a Screen from an existing TTY file descriptor.
    pub fn initFrom(io: std.Io, f: std.Io.File, options: Options) !Screen {
        const tty_backend = try TtyBackend.initFromFile(io, f, options.writer, options.handle_sigint);
        return try initWithBackend(.{ .tty = tty_backend }, options);
    }

    /// Initialize a Screen with a test backend for output capture.
    pub fn initTest(test_backend: *TestBackend, options: Options) !Screen {
        return try initWithBackend(.{ .testing = test_backend }, options);
    }

    /// Initialize a Screen with a specific backend.
    pub fn initWithBackend(backend: Backend, options: Options) !Screen {
        // Set global state for panic handler (TTY only)
        switch (backend) {
            .tty => |t| {
                tty_fd = t.fd;
                orig_termios = t.orig_termios;
            },
            .testing => {},
        }

        var self = Screen{
            .backend = backend,
            .running = true,
            .width = 0,
            .height = 0,
            .lock = .{},
            .event_queue = std.Deque(Event).initBuffer(options.events),
            .textinput = std.ArrayList(u8).initBuffer(options.textinput),
            .input_parser = parser.Parser.init(),
            .options = options,
        };

        const size = self.backend.getSize();
        self.width = size.width;
        self.height = size.height;
        std.log.debug("screen size is {}x{}", .{ self.width, self.height });

        try self.writeStartSequences();
        return self;
    }

    /// Write startup escape sequences based on options.
    fn writeStartSequences(self: *Screen) !void {
        if (self.options.hide_cursor) _ = try self.writeRawFrom(ansi.cursor.hide);
        if (self.options.alt_screen) _ = try self.writeRawFrom(ansi.screen_mode.enableAltBuffer);
        if (self.options.mouse_tracking) _ = try self.writeRawDirect(ansi.mouse_tracking_enable);
    }

    /// Write cleanup escape sequences based on options.
    fn writeExitSequences(self: *Screen) !void {
        if (self.options.hide_cursor) try self.writeRawFrom(ansi.cursor.show);
        if (self.options.alt_screen) try self.writeRawFrom(ansi.screen_mode.disableAltBuffer);
        if (self.options.mouse_tracking) _ = try self.writeRawDirect(ansi.mouse_tracking_disable);
    }

    fn writeRawFrom(self: *Screen, f: *const fn (*std.Io.Writer) anyerror!void) !void {
        try f(self.backend.writer());
        try self.flush();
    }

    /// Write bytes directly to terminal (bypasses buffer).
    fn writeRawDirect(self: *Screen, bytes: []const u8) !usize {
        const n = try self.backend.write(bytes);
        try self.backend.flush();
        return n;
    }

    /// Clean up and restore terminal to its original state.
    pub fn deinit(self: *Screen) !posix.E {
        self.running = false;
        try self.writeExitSequences();
        self.backend.deinit();
        return .SUCCESS;
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
                    // Invariant: cursor position params should be non-negative
                    // (they're u16 so always >= 0, but verify slice access is safe)
                    assert(params.len >= 2);
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
                    // Invariant: mouse events require exactly 3 params
                    assert(params.len >= 3);
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
    /// If the queue is full, the event is dropped silently. This prevents
    /// blocking on slow event consumers. Increase `Options.events` buffer
    /// size if events are being dropped.
    pub fn pushEvent(self: *Screen, event: Event) void {
        self.event_queue.pushBackBounded(event) catch {
            std.log.debug("event queue full, dropping event", .{});
        };
    }

    /// Read input from TTY and queue events.
    /// Non-blocking due to termios VMIN=0, VTIME=1 settings.
    pub fn readAndQueueEvents(self: *Screen) void {
        var input_buffer: [32]u8 = undefined;
        const bytes_read = self.backend.read(&input_buffer) catch return;
        if (bytes_read == 0) return;

        for (input_buffer[0..bytes_read]) |byte| {
            const action = self.input_parser.advance(byte) orelse continue;
            const ev = self.actionToEvent(action, byte) orelse continue;
            self.pushEvent(ev);
        }
    }

    /// Move cursor to the specified row and column.
    pub fn goto(self: *Screen, r: u16, c: u16) !void {
        try self.print(ansi.goto_fmt, .{ r, c });
    }

    /// Send a cursor position query to the terminal.
    pub fn queryPos(self: *Screen) !void {
        self.lock.lock();
        defer self.lock.unlock();
        _ = try self.writeRawDirect(ansi.cursor_position_report);
    }

    /// Query the current terminal size.
    pub fn querySize(self: *Screen) backend_mod.Size {
        self.lock.lock();
        defer self.lock.unlock();
        return self.backend.getSize();
    }

    /// Read raw input bytes into the provided buffer.
    pub fn read(self: *Screen, buffer: []u8) !usize {
        return try self.backend.read(buffer);
    }

    /// Print formatted output to the terminal.
    pub fn print(self: *Screen, comptime fmt: []const u8, args: anytype) !void {
        try self.printArgs(fmt, args, .{});
    }

    /// Write raw bytes to the terminal.
    pub fn write(self: *Screen, buf: []const u8) !usize {
        self.lock.lock();
        defer self.lock.unlock();
        return try self.backend.write(buf);
    }

    /// Write all bytes to the terminal.
    pub fn writeAll(self: *Screen, buf: []const u8) !void {
        self.lock.lock();
        defer self.lock.unlock();
        // Write all by calling write in a loop
        var written: usize = 0;
        while (written < buf.len) {
            written += try self.backend.write(buf[written..]);
        }
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
        // Format into a stack buffer then write through backend
        var buf: [256]u8 = undefined;
        const formatted = std.fmt.bufPrint(&buf, fmt, args) catch &buf;
        var written: usize = 0;
        while (written < formatted.len) {
            written += self.backend.write(formatted[written..]) catch break;
        }
    }

    /// Flush the output buffer to the terminal.
    pub fn flush(self: *Screen) !void {
        self.lock.lock();
        defer self.lock.unlock();
        try self.backend.flush();
    }

    /// Clear the entire screen.
    pub fn clearScreen(self: *Screen) !void {
        try self.writeAll(ansi.erase_screen);
    }

    /// Move the cursor to the home position (top-left corner).
    pub fn home(self: *Screen) !void {
        try self.writeAll(ansi.cursor_home);
    }

    /// Clear screen and move cursor to home position.
    pub fn reset(self: *Screen) !void {
        try self.writeAll(ansi.erase_screen ++ ansi.cursor_home);
    }

    /// Hide the cursor.
    pub fn hideCursor(self: *Screen) !void {
        try self.writeAll(ansi.cursor_hide);
    }

    /// Show the cursor.
    pub fn showCursor(self: *Screen) !void {
        try self.writeAll(ansi.cursor_show);
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
        const exit_seq = ansi.alt_buffer_disable ++ ansi.cursor_show ++ ansi.mouse_tracking_disable;
        _ = system.write(fd, exit_seq.ptr, exit_seq.len);
        if (orig_termios) |orig| _ = system.tcsetattr(fd, .FLUSH, &orig);
    }
    std.log.err("panic: {s}", .{msg});
    std.debug.defaultPanic(msg, ra);
}

// =============================================================================
// Tests
// =============================================================================

test "Screen.initTest creates screen with test backend" {
    var backend = TestBackend.init(std.testing.allocator, 80, 24);
    defer backend.deinit();

    var events_buf: [8]Event = undefined;
    var textinput_buf: [16]u8 = undefined;
    var writer_buf: [64]u8 = undefined;

    var screen = try Screen.initTest(&backend, .{
        .events = &events_buf,
        .textinput = &textinput_buf,
        .writer = &writer_buf,
        .alt_screen = false,
        .hide_cursor = false,
        .mouse_tracking = false,
    });
    defer _ = screen.deinit() catch {};

    try std.testing.expectEqual(@as(u16, 80), screen.width);
    try std.testing.expectEqual(@as(u16, 24), screen.height);
    try std.testing.expect(screen.running);
}

test "Screen.pushEvent and pollEvent" {
    var backend = TestBackend.init(std.testing.allocator, 80, 24);
    defer backend.deinit();

    var events_buf: [8]Event = undefined;
    var textinput_buf: [16]u8 = undefined;
    var writer_buf: [64]u8 = undefined;

    var screen = try Screen.initTest(&backend, .{
        .events = &events_buf,
        .textinput = &textinput_buf,
        .writer = &writer_buf,
        .alt_screen = false,
        .hide_cursor = false,
        .mouse_tracking = false,
    });
    defer _ = screen.deinit() catch {};

    // Queue should be empty initially
    try std.testing.expectEqual(@as(?Event, null), screen.pollEvent());

    // Push some events
    screen.pushEvent(.{ .key = .a });
    screen.pushEvent(.{ .key = .b });
    screen.pushEvent(.interrupt);

    // Poll them back in order
    const e1 = screen.pollEvent().?;
    try std.testing.expectEqual(Event.Key.a, e1.key);

    const e2 = screen.pollEvent().?;
    try std.testing.expectEqual(Event.Key.b, e2.key);

    const e3 = screen.pollEvent().?;
    try std.testing.expect(e3 == .interrupt);

    // Queue empty again
    try std.testing.expectEqual(@as(?Event, null), screen.pollEvent());
}

test "Screen.actionToEvent - execute actions" {
    var backend = TestBackend.init(std.testing.allocator, 80, 24);
    defer backend.deinit();

    var events_buf: [8]Event = undefined;
    var textinput_buf: [16]u8 = undefined;
    var writer_buf: [64]u8 = undefined;

    var screen = try Screen.initTest(&backend, .{
        .events = &events_buf,
        .textinput = &textinput_buf,
        .writer = &writer_buf,
        .alt_screen = false,
        .hide_cursor = false,
        .mouse_tracking = false,
    });
    defer _ = screen.deinit() catch {};

    // Ctrl+C (byte 3) -> interrupt
    const interrupt = screen.actionToEvent(.execute, 3);
    try std.testing.expect(interrupt.? == .interrupt);

    // Carriage return -> carriage_return key
    const cr = screen.actionToEvent(.execute, '\r');
    try std.testing.expectEqual(Event.Key.carriage_return, cr.?.key);

    // Newline -> carriage_return key
    const nl = screen.actionToEvent(.execute, '\n');
    try std.testing.expectEqual(Event.Key.carriage_return, nl.?.key);

    // Tab -> tab key
    const tab = screen.actionToEvent(.execute, '\t');
    try std.testing.expectEqual(Event.Key.tab, tab.?.key);

    // Escape -> esc key
    const esc = screen.actionToEvent(.execute, 0x1B);
    try std.testing.expectEqual(Event.Key.esc, esc.?.key);

    // Other execute bytes return null
    try std.testing.expectEqual(@as(?Event, null), screen.actionToEvent(.execute, 0));
}

test "Screen.actionToEvent - print action" {
    var backend = TestBackend.init(std.testing.allocator, 80, 24);
    defer backend.deinit();

    var events_buf: [8]Event = undefined;
    var textinput_buf: [16]u8 = undefined;
    var writer_buf: [64]u8 = undefined;

    var screen = try Screen.initTest(&backend, .{
        .events = &events_buf,
        .textinput = &textinput_buf,
        .writer = &writer_buf,
        .alt_screen = false,
        .hide_cursor = false,
        .mouse_tracking = false,
    });
    defer _ = screen.deinit() catch {};

    // Print action converts byte to key
    const key_a = screen.actionToEvent(.print, 'a');
    try std.testing.expectEqual(Event.Key.a, key_a.?.key);

    const key_z = screen.actionToEvent(.print, 'z');
    try std.testing.expectEqual(Event.Key.z, key_z.?.key);

    const key_A = screen.actionToEvent(.print, 'A');
    try std.testing.expectEqual(Event.Key.A, key_A.?.key);

    const key_5 = screen.actionToEvent(.print, '5');
    try std.testing.expectEqual(Event.Key.@"5", key_5.?.key);
}

test "Screen.write and writeAll" {
    var backend = TestBackend.init(std.testing.allocator, 80, 24);
    defer backend.deinit();

    var events_buf: [8]Event = undefined;
    var textinput_buf: [16]u8 = undefined;
    var writer_buf: [64]u8 = undefined;

    var screen = try Screen.initTest(&backend, .{
        .events = &events_buf,
        .textinput = &textinput_buf,
        .writer = &writer_buf,
        .alt_screen = false,
        .hide_cursor = false,
        .mouse_tracking = false,
    });
    defer _ = screen.deinit() catch {};

    _ = try screen.write("Hello");
    try screen.writeAll(", World!");
    try screen.flush();

    const output = backend.getOutput();
    try std.testing.expect(std.mem.indexOf(u8, output, "Hello") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "World") != null);
}

test "Screen.clearScreen outputs erase sequence" {
    var backend = TestBackend.init(std.testing.allocator, 80, 24);
    defer backend.deinit();

    var events_buf: [8]Event = undefined;
    var textinput_buf: [16]u8 = undefined;
    var writer_buf: [64]u8 = undefined;

    var screen = try Screen.initTest(&backend, .{
        .events = &events_buf,
        .textinput = &textinput_buf,
        .writer = &writer_buf,
        .alt_screen = false,
        .hide_cursor = false,
        .mouse_tracking = false,
    });
    defer _ = screen.deinit() catch {};

    try screen.clearScreen();
    try screen.flush();

    const output = backend.getOutput();
    // Should contain erase screen sequence
    try std.testing.expect(std.mem.indexOf(u8, output, ansi.erase_screen) != null);
}

test "Screen.home outputs cursor home sequence" {
    var backend = TestBackend.init(std.testing.allocator, 80, 24);
    defer backend.deinit();

    var events_buf: [8]Event = undefined;
    var textinput_buf: [16]u8 = undefined;
    var writer_buf: [64]u8 = undefined;

    var screen = try Screen.initTest(&backend, .{
        .events = &events_buf,
        .textinput = &textinput_buf,
        .writer = &writer_buf,
        .alt_screen = false,
        .hide_cursor = false,
        .mouse_tracking = false,
    });
    defer _ = screen.deinit() catch {};

    try screen.home();
    try screen.flush();

    const output = backend.getOutput();
    try std.testing.expect(std.mem.indexOf(u8, output, ansi.cursor_home) != null);
}

test "Screen.querySize returns backend size" {
    var backend = TestBackend.init(std.testing.allocator, 120, 40);
    defer backend.deinit();

    var events_buf: [8]Event = undefined;
    var textinput_buf: [16]u8 = undefined;
    var writer_buf: [64]u8 = undefined;

    var screen = try Screen.initTest(&backend, .{
        .events = &events_buf,
        .textinput = &textinput_buf,
        .writer = &writer_buf,
        .alt_screen = false,
        .hide_cursor = false,
        .mouse_tracking = false,
    });
    defer _ = screen.deinit() catch {};

    const size = screen.querySize();
    try std.testing.expectEqual(@as(u16, 120), size.width);
    try std.testing.expectEqual(@as(u16, 40), size.height);
}

test "Screen.deinit sets running to false" {
    var backend = TestBackend.init(std.testing.allocator, 80, 24);
    defer backend.deinit();

    var events_buf: [8]Event = undefined;
    var textinput_buf: [16]u8 = undefined;
    var writer_buf: [64]u8 = undefined;

    var screen = try Screen.initTest(&backend, .{
        .events = &events_buf,
        .textinput = &textinput_buf,
        .writer = &writer_buf,
        .alt_screen = false,
        .hide_cursor = false,
        .mouse_tracking = false,
    });

    try std.testing.expect(screen.running);
    _ = try screen.deinit();
    try std.testing.expect(!screen.running);
}

fn parseEventFromSeq(screen: *Screen, seq: []const u8) ?Event {
    var event: ?Event = null;
    for (seq) |byte| {
        if (screen.input_parser.advance(byte)) |action| {
            if (screen.actionToEvent(action, byte)) |ev| {
                event = ev;
            }
        }
    }
    return event;
}

test "Screen.actionToEvent - CSI key sequences" {
    var backend = TestBackend.init(std.testing.allocator, 80, 24);
    defer backend.deinit();

    var events_buf: [8]Event = undefined;
    var textinput_buf: [16]u8 = undefined;
    var writer_buf: [64]u8 = undefined;

    var screen = try Screen.initTest(&backend, .{
        .events = &events_buf,
        .textinput = &textinput_buf,
        .writer = &writer_buf,
        .alt_screen = false,
        .hide_cursor = false,
        .mouse_tracking = false,
    });
    defer _ = screen.deinit() catch {};

    const up = parseEventFromSeq(&screen, "\x1b[A").?;
    switch (up) {
        .key => |k| try std.testing.expectEqual(Event.Key.arrow_up, k),
        else => try std.testing.expect(false),
    }

    screen.input_parser.reset();
    const home = parseEventFromSeq(&screen, "\x1b[1~").?;
    switch (home) {
        .key => |k| try std.testing.expectEqual(Event.Key.home, k),
        else => try std.testing.expect(false),
    }

    screen.input_parser.reset();
    const f5 = parseEventFromSeq(&screen, "\x1b[15~").?;
    switch (f5) {
        .key => |k| try std.testing.expectEqual(Event.Key.f5, k),
        else => try std.testing.expect(false),
    }

    screen.input_parser.reset();
    const backtab = parseEventFromSeq(&screen, "\x1b[Z").?;
    switch (backtab) {
        .key => |k| try std.testing.expectEqual(Event.Key.backtab, k),
        else => try std.testing.expect(false),
    }
}

test "Screen.actionToEvent - CSI cursor and mouse sequences" {
    var backend = TestBackend.init(std.testing.allocator, 80, 24);
    defer backend.deinit();

    var events_buf: [8]Event = undefined;
    var textinput_buf: [16]u8 = undefined;
    var writer_buf: [64]u8 = undefined;

    var screen = try Screen.initTest(&backend, .{
        .events = &events_buf,
        .textinput = &textinput_buf,
        .writer = &writer_buf,
        .alt_screen = false,
        .hide_cursor = false,
        .mouse_tracking = false,
    });
    defer _ = screen.deinit() catch {};

    const pos = parseEventFromSeq(&screen, "\x1b[10;20R").?;
    switch (pos) {
        .cursor_pos => |p| {
            try std.testing.expectEqual(@as(usize, 10), p.row);
            try std.testing.expectEqual(@as(usize, 20), p.col);
        },
        else => try std.testing.expect(false),
    }

    screen.input_parser.reset();
    const mouse = parseEventFromSeq(&screen, "\x1b[<0;10;20M").?;
    switch (mouse) {
        .mouse => |m| {
            try std.testing.expectEqual(Event.MouseButton.left, m.button);
            try std.testing.expectEqual(Event.MouseButtonState.pressed, m.button_state);
            try std.testing.expectEqual(@as(usize, 10), m.col);
            try std.testing.expectEqual(@as(usize, 20), m.row);
        },
        else => try std.testing.expect(false),
    }
}

test "Screen.actionToEvent - OSC focus sequences" {
    var backend = TestBackend.init(std.testing.allocator, 80, 24);
    defer backend.deinit();

    var events_buf: [8]Event = undefined;
    var textinput_buf: [16]u8 = undefined;
    var writer_buf: [64]u8 = undefined;

    var screen = try Screen.initTest(&backend, .{
        .events = &events_buf,
        .textinput = &textinput_buf,
        .writer = &writer_buf,
        .alt_screen = false,
        .hide_cursor = false,
        .mouse_tracking = false,
    });
    defer _ = screen.deinit() catch {};

    const focused = parseEventFromSeq(&screen, "\x1b]I\x07").?;
    switch (focused) {
        .focus => |state| try std.testing.expect(state),
        else => try std.testing.expect(false),
    }

    screen.input_parser.reset();
    const unfocused = parseEventFromSeq(&screen, "\x1b]O\x07").?;
    switch (unfocused) {
        .focus => |state| try std.testing.expect(!state),
        else => try std.testing.expect(false),
    }
}
