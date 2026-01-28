//! Test capture utilities for terminal output verification.
//!
//! Provides a simple interface for testing terminal rendering without a real TTY.
//!
//! ## Example
//! ```zig
//!
//! test "Frame renders text" {
//!     var capture = try ttyz.TestCapture.init(std.testing.allocator, 80, 24);
//!     defer capture.deinit();
//!
//!     var buffer = try ttyz.Buffer.init(std.testing.allocator, 80, 24);
//!     defer buffer.deinit();
//!
//!     var frame = ttyz.Frame.init(&buffer);
//!     frame.setString(0, 0, "Hello", .{}, .default, .default);
//!     try frame.render(capture.screen());
//!     try capture.screen().flush();
//!
//!     try std.testing.expect(capture.contains("Hello"));
//! }
//! ```

/// Test capture context that bundles a TestBackend with a Screen.
///
/// Simplifies testing by managing all the necessary buffers and state.
/// Allocated on the heap to ensure stable pointers for the backend.
pub const TestCapture = struct {
    const Self = @This();

    backend: TestBackend,
    screen_state: Screen,
    allocator: std.mem.Allocator,

    // Internal buffers for Screen.Options
    events_buf: [32]Event,
    textinput_buf: [32]u8,
    writer_buf: [256]u8, // Unused by TestBackend but required by Options

    /// Initialize a test capture context.
    ///
    /// Creates a TestBackend and Screen configured for testing.
    /// The screen will capture all output to an internal buffer.
    /// Returns a pointer because the struct must have stable addresses.
    pub fn init(allocator: std.mem.Allocator, width: u16, height: u16) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = .{
            .backend = TestBackend.init(allocator, width, height),
            .screen_state = undefined,
            .allocator = allocator,
            .events_buf = undefined,
            .textinput_buf = undefined,
            .writer_buf = undefined,
        };

        // Initialize screen with test backend
        self.screen_state = try Screen.initTest(&self.backend, .{
            .events = &self.events_buf,
            .textinput = &self.textinput_buf,
            .writer = &self.writer_buf,
            .alt_screen = false,
            .hide_cursor = false,
            .mouse_tracking = false,
        });

        return self;
    }

    /// Get the screen for rendering.
    pub fn screen(self: *Self) *Screen {
        return &self.screen_state;
    }

    /// Clean up resources.
    pub fn deinit(self: *Self) void {
        _ = self.screen_state.deinit() catch {};
        self.backend.deinit();
        self.allocator.destroy(self);
    }

    /// Get all captured output as a string.
    pub fn getOutput(self: *TestCapture) []const u8 {
        return self.backend.getOutput();
    }

    /// Check if the captured output contains a substring.
    pub fn contains(self: *TestCapture, needle: []const u8) bool {
        return std.mem.indexOf(u8, self.getOutput(), needle) != null;
    }

    /// Check if the captured output contains a substring, case-insensitive.
    pub fn containsIgnoreCase(self: *TestCapture, needle: []const u8) bool {
        const output = self.getOutput();
        // Simple case-insensitive search
        if (needle.len > output.len) return false;
        var i: usize = 0;
        while (i <= output.len - needle.len) : (i += 1) {
            var match = true;
            for (needle, 0..) |c, j| {
                const oc = output[i + j];
                if (std.ascii.toLower(c) != std.ascii.toLower(oc)) {
                    match = false;
                    break;
                }
            }
            if (match) return true;
        }
        return false;
    }

    /// Clear captured output buffer.
    pub fn clear(self: *TestCapture) void {
        self.backend.clearOutput();
    }

    /// Get the number of bytes captured.
    pub fn len(self: *TestCapture) usize {
        return self.getOutput().len;
    }

    /// Check if any output was captured.
    pub fn isEmpty(self: *TestCapture) bool {
        return self.len() == 0;
    }

    /// Count occurrences of a substring in the output.
    pub fn count(self: *TestCapture, needle: []const u8) usize {
        const output = self.getOutput();
        if (needle.len == 0 or needle.len > output.len) return 0;

        var n: usize = 0;
        var i: usize = 0;
        while (i <= output.len - needle.len) {
            if (std.mem.eql(u8, output[i..][0..needle.len], needle)) {
                n += 1;
                i += needle.len;
            } else {
                i += 1;
            }
        }
        return n;
    }
};

test "TestCapture basic usage" {
    const capture = try TestCapture.init(std.testing.allocator, 80, 24);
    defer capture.deinit();

    try capture.screen().writeAll("Hello, World!");
    try capture.screen().flush();

    try std.testing.expect(capture.contains("Hello"));
    try std.testing.expect(capture.contains("World"));
    try std.testing.expect(!capture.contains("Goodbye"));
}

test "TestCapture with Frame" {
    const Buffer = frame_mod.Buffer;
    const Frame = frame_mod.Frame;

    const capture = try TestCapture.init(std.testing.allocator, 80, 24);
    defer capture.deinit();

    var buffer = try Buffer.init(std.testing.allocator, 80, 24);
    defer buffer.deinit();

    var frame = Frame.init(&buffer);
    frame.setString(0, 0, "Test", .{}, .default, .default);
    try frame.render(capture.screen());
    try capture.screen().flush();

    try std.testing.expect(capture.contains("Test"));
}

test "TestCapture count occurrences" {
    const capture = try TestCapture.init(std.testing.allocator, 80, 24);
    defer capture.deinit();

    try capture.screen().writeAll("foo bar foo baz foo");
    try capture.screen().flush();

    try std.testing.expectEqual(@as(usize, 3), capture.count("foo"));
    try std.testing.expectEqual(@as(usize, 1), capture.count("bar"));
    try std.testing.expectEqual(@as(usize, 0), capture.count("qux"));
}

test "TestCapture screen dimensions" {
    const capture = try TestCapture.init(std.testing.allocator, 120, 40);
    defer capture.deinit();

    try std.testing.expectEqual(@as(u16, 120), capture.screen().width);
    try std.testing.expectEqual(@as(u16, 40), capture.screen().height);
}

const std = @import("std");

const ttyz = @import("ttyz");

const Event = @import("event.zig").Event;
const frame_mod = @import("frame.zig");
const Screen = @import("screen.zig").Screen;
const TestBackend = @import("backend.zig").TestBackend;
