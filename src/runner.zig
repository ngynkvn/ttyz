//! Runner - Generic event/render loop
//!
//! Simplifies the common pattern of polling events, handling them, and rendering.
//! All events (keyboard, mouse, resize, etc.) are unified into a single event channel.

const std = @import("std");
const posix = std.posix;
const system = posix.system;

const frame = @import("frame.zig");
const Screen = @import("screen.zig").Screen;
const Event = @import("event.zig").Event;
const queryHandleSize = @import("screen.zig").queryHandleSize;

/// Generic event/render loop runner.
///
/// The app type `T` must implement:
/// - `handleEvent(*T, Event) bool` - Handle an event. Return false to stop the loop.
/// - `render(*T, *Frame) !void` - Render the current frame.
///
/// Optionally, `T` may implement:
/// - `init(*T, *Screen) !void` - Called before the loop starts.
/// - `deinit(*T) void` - Called after the loop ends.
/// - `cleanup(*T, *Screen) !void` - Called just before screen cleanup.
pub fn Runner(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Configuration options for the runner.
        pub const Options = struct {
            /// Target frames per second (controls sleep duration between frames).
            fps: u32 = 30,
        };

        /// Shared state for signal handlers
        var signal_screen: ?*Screen = null;

        /// Signal handler that queues resize events
        fn handleSignals(sig: std.posix.SIG) callconv(.c) void {
            if (sig == std.posix.SIG.WINCH) {
                if (signal_screen) |screen| {
                    // Query new size and push resize event
                    if (queryHandleSize(screen.fd)) |ws| {
                        screen.pushEvent(.{ .resize = .{ .width = ws.col, .height = ws.row } });
                    } else |_| {}
                }
            }
        }

        /// Run the event/render loop with the given app.
        pub fn run(app: *T, proc: std.process.Init, buffers: Screen.Buffers) !void {
            return runWithOptions(app, proc, buffers, .{});
        }

        /// Run with custom options.
        pub fn runWithOptions(app: *T, proc: std.process.Init, buffers: Screen.Buffers, options: Options) !void {
            const io = proc.io;
            var screen = try Screen.init(io, buffers);
            defer _ = screen.deinit() catch {};

            // Store screen pointer for signal handler
            signal_screen = &screen;
            defer signal_screen = null;

            // Set up WINCH signal handler that queues resize events
            const sa = std.posix.Sigaction{
                .flags = std.posix.SA.RESTART,
                .mask = std.posix.sigemptyset(),
                .handler = .{ .handler = handleSignals },
            };
            std.posix.sigaction(std.posix.SIG.WINCH, &sa, null);

            // Initialize frame buffer
            var buffer = try frame.Buffer.init(proc.gpa, screen.width, screen.height);
            defer buffer.deinit();

            // Call app.init if it exists
            if (@hasDecl(T, "init")) {
                try app.init(&screen);
            }

            defer {
                // Call app.cleanup if it exists
                if (@hasDecl(T, "cleanup")) {
                    app.cleanup(&screen) catch {};
                }
                // Call app.deinit if it exists
                if (@hasDecl(T, "deinit")) {
                    app.deinit();
                }
            }

            const frame_duration = std.Io.Duration.fromMilliseconds(1000 / options.fps);

            while (screen.running) {
                // Read input and queue events (non-blocking due to termios VTIME=1)
                readInput(&screen);

                // Poll and handle all pending events from unified queue
                var resize: ?struct { width: u16, height: u16 } = null;
                while (screen.pollEvent()) |event| {
                    // Handle resize by updating buffer
                    switch (event) {
                        .resize => |r| {
                            screen.width = r.width;
                            screen.height = r.height;
                            if (buffer.width != r.width or buffer.height != r.height) {
                                resize = .{ .width = r.width, .height = r.height };
                            }
                        },
                        else => {},
                    }

                    // Let app handle the event
                    if (!app.handleEvent(event)) {
                        screen.running = false;
                        break;
                    }
                }

                if (!screen.running) break;
                if (resize) |r| buffer.resize(r.width, r.height) catch {};

                // Clear and render frame
                var f = frame.Frame.init(&buffer);
                f.clear();
                try app.render(&f);
                try f.render(&screen);
                try screen.flush();

                // Frame timing
                io.sleep(frame_duration, .awake) catch {};
            }
        }

        // Read input from the TTY and queue events (non-blocking due to termios VTIME=1)
        fn readInput(screen: *Screen) void {
            var input_buffer: [32]u8 = undefined;

            const rc = system.read(screen.fd, &input_buffer, input_buffer.len);
            if (rc <= 0) return;

            const bytes_read: usize = @intCast(rc);

            // Process each byte through the parser and queue events
            for (input_buffer[0..bytes_read]) |byte| {
                const action = screen.input_parser.advance(byte);
                if (screen.actionToEvent(action, byte)) |ev| {
                    screen.pushEvent(ev);
                }
            }
        }
    };
}
