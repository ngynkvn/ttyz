//! Backend abstraction for terminal I/O
//!
//! Provides different backends for Screen to use:
//! - TtyBackend: Real terminal I/O via file descriptor
//! - TestBackend: Captures output to buffer for testing

/// Size returned by backend getSize.
pub const Size = struct { width: u16, height: u16 };

/// Backend for terminal I/O operations.
pub const Backend = union(enum) {
    tty: TtyBackend,
    testing: *TestBackend,

    pub fn writer(self: *Backend) *std.Io.Writer {
        return switch (self.*) {
            .tty => |*t| &t.writer.interface,
            .testing => undefined,
        };
    }

    pub fn write(self: *Backend, data: []const u8) !usize {
        return switch (self.*) {
            .tty => |*t| t.write(data),
            .testing => |t| t.write(data),
        };
    }

    pub fn read(self: *Backend, buf: []u8) !usize {
        return switch (self.*) {
            .tty => |*t| t.read(buf),
            .testing => |t| t.read(buf),
        };
    }

    pub fn flush(self: *Backend) !void {
        return switch (self.*) {
            .tty => |*t| t.flush(),
            .testing => |t| t.flush(),
        };
    }

    pub fn getSize(self: *Backend) Size {
        return switch (self.*) {
            .tty => |*t| t.getSize(),
            .testing => |t| t.getSize(),
        };
    }

    pub fn deinit(self: *Backend) void {
        switch (self.*) {
            .tty => |*t| t.deinit(),
            .testing => {}, // TestBackend manages its own lifetime
        }
    }
};

/// Real terminal backend using TTY file descriptor.
pub const TtyBackend = struct {
    file: std.Io.File,
    fd: posix.fd_t,
    writer: std.Io.File.Writer,
    orig_termios: ?posix.termios,

    pub fn init(io: std.Io, tty_path: []const u8, writer_buf: []u8, handle_sigint: bool) !TtyBackend {
        const f = try std.Io.Dir.openFileAbsolute(io, tty_path, .{ .mode = .read_write });
        return try initFromFile(io, f, writer_buf, handle_sigint);
    }

    pub fn initFromFile(io: std.Io, f: std.Io.File, writer_buf: []u8, handle_sigint: bool) !TtyBackend {
        const fd = f.handle;

        const orig = try posix.tcgetattr(fd);

        var raw = orig;
        // zig fmt: off
        raw.lflag.ECHO   = false;
        raw.lflag.ICANON = false;
        raw.lflag.IEXTEN = false;
        raw.lflag.ISIG   = !handle_sigint;
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

        return .{
            .file = f,
            .fd = fd,
            .writer = f.writerStreaming(io, writer_buf),
            .orig_termios = orig,
        };
    }

    pub fn write(self: *TtyBackend, data: []const u8) !usize {
        return try self.writer.interface.write(data);
    }

    pub fn read(self: *TtyBackend, buf: []u8) !usize {
        const rc = system.read(self.fd, buf.ptr, buf.len);
        if (rc < 0) return error.ReadFailed;
        return @intCast(rc);
    }

    pub fn flush(self: *TtyBackend) !void {
        try self.writer.flush();
    }

    pub fn getSize(self: *TtyBackend) Size {
        var ws: posix.winsize = .{ .row = 0, .col = 0, .xpixel = 0, .ypixel = 0 };
        const result = system.ioctl(self.fd, posix.T.IOCGWINSZ, @intFromPtr(&ws));
        if (posix.errno(result) != .SUCCESS) {
            return .{ .width = 80, .height = 24 }; // fallback
        }
        return .{ .width = ws.col, .height = ws.row };
    }

    pub fn deinit(self: *TtyBackend) void {
        if (self.orig_termios) |orig| {
            _ = system.tcsetattr(self.fd, .FLUSH, &orig);
        }
        _ = system.close(self.fd);
    }
};

/// Test backend that captures output to a buffer.
pub const TestBackend = struct {
    output: std.ArrayList(u8),
    allocator: std.mem.Allocator,
    events: []const Event,
    event_idx: usize,
    width: u16,
    height: u16,

    pub fn init(allocator: std.mem.Allocator, width: u16, height: u16) TestBackend {
        return .{
            .output = .{},
            .allocator = allocator,
            .events = &.{},
            .event_idx = 0,
            .width = width,
            .height = height,
        };
    }

    pub fn deinit(self: *TestBackend) void {
        self.output.deinit(self.allocator);
    }

    pub fn write(self: *TestBackend, data: []const u8) !usize {
        try self.output.appendSlice(self.allocator, data);
        return data.len;
    }

    pub fn read(self: *TestBackend, buf: []u8) !usize {
        _ = self;
        _ = buf;
        // Return 0 to indicate no input available
        return 0;
    }

    pub fn flush(self: *TestBackend) !void {
        // No-op for test backend
        _ = self;
    }

    pub fn getSize(self: *TestBackend) Size {
        return .{ .width = self.width, .height = self.height };
    }

    /// Get all captured output.
    pub fn getOutput(self: *TestBackend) []const u8 {
        return self.output.items;
    }

    /// Clear captured output.
    pub fn clearOutput(self: *TestBackend) void {
        self.output.clearRetainingCapacity();
    }

    /// Set events to be returned by pollEvent.
    pub fn setEvents(self: *TestBackend, events: []const Event) void {
        self.events = events;
        self.event_idx = 0;
    }

    /// Get next event (used by Screen).
    pub fn nextEvent(self: *TestBackend) ?Event {
        if (self.event_idx < self.events.len) {
            const event = self.events[self.event_idx];
            self.event_idx += 1;
            return event;
        }
        return null;
    }
};

test "TestBackend captures output" {
    const allocator = std.testing.allocator;
    var backend = TestBackend.init(allocator, 80, 24);
    defer backend.deinit();

    _ = try backend.write("Hello");
    _ = try backend.write(", World!");

    try std.testing.expectEqualStrings("Hello, World!", backend.getOutput());
}

test "TestBackend returns configured size" {
    const allocator = std.testing.allocator;
    var backend = TestBackend.init(allocator, 120, 40);
    defer backend.deinit();

    const size = backend.getSize();
    try std.testing.expectEqual(@as(u16, 120), size.width);
    try std.testing.expectEqual(@as(u16, 40), size.height);
}

const std = @import("std");
const posix = std.posix;
const system = posix.system;

const Event = @import("event.zig").Event;
