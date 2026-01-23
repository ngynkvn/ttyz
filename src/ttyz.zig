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
//!     try ttyz.Runner(MyApp).run(&app, init);
//! }
//! ```

const std = @import("std");

// Core modules
pub const screen = @import("screen.zig");
pub const event = @import("event.zig");
pub const runner = @import("runner.zig");

// Re-export main types
pub const Screen = screen.Screen;
pub const Event = event.Event;
pub const Runner = runner.Runner;
pub const CONFIG = screen.CONFIG;
pub const panic = screen.panic;
pub const panicTty = screen.panicTty;
pub const queryHandleSize = screen.queryHandleSize;

/// Kitty graphics protocol for terminal image display.
pub const kitty = @import("kitty.zig");

/// Pixel-level RGBA canvas (alias for kitty.Canvas).
pub const draw = struct {
    pub const Canvas = kitty.Canvas;
};

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

/// Frame-based drawing with cell buffers.
pub const frame = @import("frame.zig");
pub const Frame = frame.Frame;
pub const Buffer = frame.Buffer;
pub const Cell = frame.Cell;
pub const Rect = frame.Rect;

/// DEC ANSI escape sequence parser.
pub const parser = @import("parser.zig");

/// Comprehensive ANSI escape sequence library.
pub const ansi = @import("ansi.zig");

test {
    std.testing.refAllDecls(@This());
}
