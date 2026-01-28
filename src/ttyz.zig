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
//! const MyApp = struct {
//!     pub fn handleEvent(self: *MyApp, event: ttyz.Event) bool {
//!         return switch (event) {
//!             .key => |k| k != .q,
//!             .interrupt => false,
//!             else => true,
//!         };
//!     }
//!
//!     pub fn render(self: *MyApp, f: *ttyz.Frame) !void {
//!         f.setString(0, 0, "Hello, ttyz!", .{}, .default, .default);
//!     }
//! };
//!
//! pub fn main(init: std.process.Init) !void {
//!     var app = MyApp{};
//!     try ttyz.Runner(MyApp).run(&app, init, ttyz.Screen.Options.default);
//! }
//! ```

// Re-exported types for convenience
pub const Event = event.Event;
pub const Frame = frame.Frame;
pub const Buffer = frame.Buffer;
pub const Cell = frame.Cell;
pub const Rect = frame.Rect;
pub const Runner = runner.Runner;
pub const Screen = screen.Screen;
pub const Backend = screen.Backend;
pub const TtyBackend = screen.TtyBackend;
pub const TestBackend = screen.TestBackend;
pub const TestCapture = test_capture.TestCapture;

/// Panic handler that restores terminal state before panicking.
pub const panic = screen.panic;
/// Low-level panic handler function (use `panic` for the public API).
pub const panicTty = screen.panicTty;
/// Query terminal size for a given file descriptor.
pub const queryHandleSize = screen.queryHandleSize;

/// Pixel-level RGBA canvas for Kitty graphics protocol.
pub const draw = struct {
    pub const Canvas = kitty.Canvas;
};

test {
    std.testing.refAllDecls(@This());
}

const std = @import("std");
pub const ansi = @import("ansi.zig");
pub const colorz = @import("colorz.zig");
pub const event = @import("event.zig");
pub const frame = @import("frame.zig");
pub const kitty = @import("kitty.zig");
pub const parser = @import("parser.zig");
pub const runner = @import("runner.zig");
pub const screen = @import("screen.zig");
pub const termdraw = @import("termdraw.zig");
pub const test_capture = @import("test_capture.zig");
pub const text = @import("text.zig");
