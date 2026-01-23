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

const std = @import("std");

/// Comprehensive ANSI escape sequence library.
pub const ansi = @import("ansi.zig");
/// Comptime color format string parser for inline ANSI colors.
pub const colorz = @import("colorz.zig");
/// VT100/xterm escape sequence constants.
pub const E = @import("esc.zig");
pub const event = @import("event.zig");
pub const Event = event.Event;
/// Frame-based drawing with cell buffers.
pub const frame = @import("frame.zig");
pub const Frame = frame.Frame;
pub const Buffer = frame.Buffer;
pub const Cell = frame.Cell;
pub const Rect = frame.Rect;
/// Kitty graphics protocol for terminal image display.
pub const kitty = @import("kitty.zig");
/// Immediate-mode UI layout engine.
pub const layout = @import("layout.zig");
/// DEC ANSI escape sequence parser.
pub const parser = @import("parser.zig");
pub const runner = @import("runner.zig");
pub const Runner = runner.Runner;
pub const screen = @import("screen.zig");
pub const Screen = screen.Screen;
pub const Backend = screen.Backend;
pub const TtyBackend = screen.TtyBackend;
pub const TestBackend = screen.TestBackend;
pub const panic = screen.panic;
pub const panicTty = screen.panicTty;
pub const queryHandleSize = screen.queryHandleSize;
/// Test utilities for capturing terminal output.
pub const test_capture = @import("test_capture.zig");
pub const TestCapture = test_capture.TestCapture;
/// Box drawing with Unicode characters.
pub const termdraw = @import("termdraw.zig");
/// Text utilities for padding, centering, and display width.
pub const text = @import("text.zig");

// Core modules
// Re-export main types
/// Pixel-level RGBA canvas (alias for kitty.Canvas).
pub const draw = struct {
    pub const Canvas = kitty.Canvas;
};

test {
    std.testing.refAllDecls(@This());
}
