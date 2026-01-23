//! Runner - Generic event/render loop
//!
//! Simplifies the common pattern of polling events, handling them, and rendering.

const std = @import("std");
const posix = std.posix;
const system = posix.system;

const frame = @import("frame.zig");
const Screen = @import("screen.zig").Screen;
const Event = @import("event.zig").Event;

/// Generic event/render loop runner using async std.Io.
///
/// Simplifies the common pattern of polling events, handling them, and rendering.
/// Uses std.Io for non-blocking I/O instead of spawning threads.
///
/// The app type `T` must implement:
/// - `handleEvent(*T, Event) bool` - Handle an event. Return false to stop the loop.
/// - `render(*T, *Frame) !void` - Render the current frame.
///
/// Optionally, `T` may implement:
/// - `init(*T, *Screen) !void` - Called before the loop starts.
/// - `deinit(*T) void` - Called after the loop ends.
/// - `cleanup(*T, *Screen) !void` - Called just before screen cleanup (for terminal-direct output).
///
/// ## Example
/// ```zig
/// const MyApp = struct {
///     count: usize = 0,
///
///     pub fn handleEvent(self: *MyApp, event: ttyz.Event) bool {
///         switch (event) {
///             .key => |k| if (k == .q) return false,
///             .interrupt => return false,
///             else => {},
///         }
///         return true;
///     }
///
///     pub fn render(self: *MyApp, f: *ttyz.Frame) !void {
///         f.setString(0, 0, "Hello!", .{}, .default, .default);
///     }
/// };
///
/// pub fn main(proc: std.process.Init) !void {
///     var app = MyApp{};
///     try ttyz.Runner(MyApp).run(&app, proc);
/// }
/// ```
pub fn Runner(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Configuration options for the runner.
        pub const Options = struct {
            /// Target frames per second (controls sleep duration between frames).
            fps: u32 = 30,
        };

        /// Run the event/render loop with the given app.
        /// App must implement:
        ///   - `fn handleEvent(self: *T, event: Event) bool` - return false to exit
        ///   - `fn render(self: *T, f: *Frame) !void` - draw to the frame
        /// App may optionally implement:
        ///   - `fn init(self: *T, screen: *Screen) !void` - called once at start
        ///   - `fn deinit(self: *T) void` - called on exit
        ///   - `fn cleanup(self: *T, screen: *Screen) !void` - called before screen cleanup
        pub fn run(app: *T, proc: std.process.Init) !void {
            return runWithOptions(app, proc, .{});
        }

        /// Run with custom options.
        pub fn runWithOptions(app: *T, proc: std.process.Init, options: Options) !void {
            const io = proc.io;
            var screen = try Screen.init(io);
            defer _ = screen.deinit() catch {};

            // Set up WINCH signal handler
            const sa = std.posix.Sigaction{
                .flags = std.posix.SA.RESTART,
                .mask = std.posix.sigemptyset(),
                .handler = .{ .handler = Screen.Signals.handleSignals },
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
                // Call app.cleanup if it exists (for terminal-direct output cleanup)
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
                // Check for window resize signal
                if (Screen.Signals.WINCH) {
                    if (screen.querySize()) |ws| {
                        screen.width = ws.col;
                        screen.height = ws.row;
                    } else |_| {}
                    @atomicStore(bool, &Screen.Signals.WINCH, false, .seq_cst);
                }

                // Read input (non-blocking due to termios settings)
                readInput(&screen);

                // Poll and handle all pending events
                while (screen.pollEvent()) |event| {
                    if (!app.handleEvent(event)) {
                        screen.running = false;
                        break;
                    }
                }

                if (!screen.running) break;

                // Resize buffer if needed
                if (buffer.width != screen.width or buffer.height != screen.height) {
                    try buffer.resize(screen.width, screen.height);
                }

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

        /// Read input from the TTY (non-blocking due to termios VMIN=0, VTIME=1)
        fn readInput(screen: *Screen) void {
            var input_buffer: [32]u8 = undefined;

            const rc = system.read(screen.fd, &input_buffer, input_buffer.len);
            if (rc <= 0) return;

            const bytes_read: usize = @intCast(rc);

            // Process each byte through the parser
            for (input_buffer[0..bytes_read]) |byte| {
                const action = screen.input_parser.advance(byte);
                if (screen.actionToEvent(action, byte)) |ev| {
                    screen.event_queue.pushBackBounded(ev) catch {};
                }
            }
        }
    };
}
