# ttyz

A Zig library for building terminal user interfaces (TUI). Provides low-level terminal control including raw mode handling, escape sequences, input event processing, an immediate-mode layout system, and support for the Kitty graphics protocol.

## Features

- **Raw mode terminal I/O** with automatic state restoration on exit/panic
- **Event system** for keyboard, mouse, and focus events
- **Threaded I/O loop** for non-blocking input handling
- **Immediate-mode layout engine** inspired by [Clay](https://github.com/nicbarker/clay)
- **Kitty graphics protocol** support for terminal image display
- **Box drawing** with Unicode characters
- **Comptime color parsing** for inline ANSI colors in format strings
- **Text utilities** for padding, centering, and Unicode codepoint counting

## Requirements

- Zig 0.15.2 or later
- Unix-like system with `/dev/tty` support (Linux, macOS, BSD)

## Installation

Add ttyz as a dependency in your `build.zig.zon`:

```zig
.dependencies = .{
    .ttyz = .{
        .url = "https://github.com/ngynkvn/ttyz/archive/<commit>.tar.gz",
        .hash = "...",
    },
},
```

Then in your `build.zig`:

```zig
const ttyz = b.dependency("ttyz", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("ttyz", ttyz.module("ttyz"));
```

## Quick Start

The recommended way to use ttyz is with the `Runner` pattern, which handles the main loop, event processing, and Frame rendering:

```zig
const std = @import("std");
const ttyz = @import("ttyz");

const MyApp = struct {
    message: []const u8 = "Hello, ttyz!",

    // Return false to exit, true to continue
    pub fn handleEvent(self: *MyApp, event: ttyz.Event) bool {
        _ = self;
        return switch (event) {
            .key => |k| k != .q and k != .Q,
            .interrupt => false,
            else => true,
        };
    }

    // Render using the Frame API
    pub fn render(self: *MyApp, f: *ttyz.Frame) !void {
        // Center the message
        const cx = (f.buffer.width -| @as(u16, @intCast(self.message.len))) / 2;
        const cy = f.buffer.height / 2;
        f.setString(cx, cy, self.message, .{ .bold = true }, .default, .default);

        // Footer
        f.setString(0, f.buffer.height - 1, "Press Q to quit", .{ .dim = true }, .default, .default);
    }
};

pub fn main(init: std.process.Init) !void {
    var app = MyApp{};
    try ttyz.Runner(MyApp).run(&app, init, ttyz.Screen.Options.default);
}
```

### Low-Level API

For more control, you can use the Screen API directly:

```zig
const std = @import("std");
const ttyz = @import("ttyz");
const ansi = ttyz.ansi;

pub fn main(init: std.process.Init) !void {
    var screen = try ttyz.Screen.init(init.io, ttyz.Screen.Options.default);
    defer _ = screen.deinit() catch {};

    while (screen.running) {
        screen.readAndQueueEvents();

        while (screen.pollEvent()) |event| {
            switch (event) {
                .key => |key| if (key == .q) { screen.running = false; },
                .mouse => |mouse| {
                    try screen.print("Mouse at {},{}\n", .{mouse.row, mouse.col});
                },
                else => {},
            }
        }

        try screen.home();
        try screen.print(ansi.bold ++ "ttyz" ++ ansi.reset ++ " - {}x{}\n", .{screen.width, screen.height});
        try screen.flush();

        init.io.sleep(std.Io.Duration.fromMilliseconds(16), .awake) catch {};
    }
}
```

## Modules

### Core (`ttyz.Screen`)

The main interface for terminal I/O:

```zig
var screen = try ttyz.Screen.init(io, ttyz.Screen.Options.default);
defer _ = screen.deinit() catch {};

screen.readAndQueueEvents();       // Poll for input events
try screen.goto(row, col);         // Move cursor
try screen.print("{}", .{val});    // Formatted output
_ = try screen.write("text");      // Raw output
try screen.clearScreen();          // Clear screen
try screen.flush();                // Flush output buffer
```

### ANSI Escape Sequences (`ttyz.ansi`)

Comprehensive ANSI escape sequence constants and functions:

```zig
const ansi = ttyz.ansi;

// Cursor control
ansi.cursor_home    // Move to (1,1)
ansi.cursor_hide    // Hide cursor
ansi.cursor_show    // Show cursor
ansi.goto_fmt       // Format string for goto: "\x1b[{d};{d}H"

// Screen control
ansi.erase_screen       // Clear entire screen
ansi.alt_buffer_enable  // Enter alternate screen
ansi.alt_buffer_disable // Exit alternate screen

// Styles (compile-time string concatenation)
ansi.bold, ansi.faint, ansi.italic, ansi.underline
ansi.reverse, ansi.crossed_out, ansi.reset

// Colors
ansi.fg.red, ansi.fg.green, ansi.fg.blue, ...
ansi.bg.red, ansi.bg.green, ansi.bg.blue, ...
ansi.fg_256_fmt     // Format for 256-color: "\x1b[38;5;{d}m"
ansi.fg_rgb_fmt     // Format for true color: "\x1b[38;2;{};{};{}m"

// Mouse tracking
ansi.mouse_tracking_enable, ansi.mouse_tracking_disable
```

Usage example:
```zig
try screen.print(ansi.bold ++ ansi.fg.green ++ "Success!" ++ ansi.reset, .{});
try screen.print(ansi.fg_256_fmt, .{196});  // Color 196
try screen.print(ansi.fg_rgb_fmt, .{255, 128, 0});  // Orange
```

### Frame and Buffer (`ttyz.Frame`, `ttyz.Buffer`)

Frame-based rendering with a cell buffer. This is the recommended approach for most TUI applications:

```zig
const Frame = ttyz.Frame;
const Buffer = ttyz.Buffer;
const Color = ttyz.frame.Color;
const Layout = ttyz.frame.Layout;

// In your render function:
pub fn render(self: *MyApp, f: *Frame) !void {
    // Draw text with style and color
    f.setString(x, y, "Hello", .{ .bold = true }, Color.green, .default);

    // Draw a box
    f.drawRect(ttyz.Rect{ .x = 0, .y = 0, .width = 20, .height = 5 }, .single);

    // Fill a region
    f.fillRect(area, .{ .char = ' ', .bg = Color.blue });

    // Use Layout for automatic sizing
    const header, const content, const footer = f.areas(3, Layout(3).vertical(.{
        .{ .length = 1 },  // Fixed 1 row
        .{ .fill = 1 },    // Fill remaining space
        .{ .length = 1 },  // Fixed 1 row
    }));

    // Draw in each area
    f.setString(header.x, header.y, "Header", .{}, .default, .default);
}
```

### Layout System (`ttyz.frame.Layout`)

Declarative layout for dividing screen space:

```zig
const Layout = ttyz.frame.Layout;

// Vertical layout: header, content, footer
const areas = Layout(3).vertical(.{
    .{ .length = 2 },  // 2 rows
    .{ .fill = 1 },    // Fill remaining
    .{ .length = 1 },  // 1 row
}).areas(frame.rect());  // Returns [3]Rect

// Horizontal layout with spacing
const cols = Layout(3).horizontal(.{
    .{ .fill = 1 },
    .{ .fill = 2 },  // 2x the width of others
    .{ .fill = 1 },
}).withSpacing(1).areas(content);
```

### Color Formatting (`ttyz.colorz`)

Comptime format string parser for inline ANSI colors:

```zig
var clr = ttyz.colorz.wrap(&writer);
try clr.print("@[.green]Success@[.reset]: @[.bold]{s}@[.reset]", .{message});

// Available codes:
// Colors: @[.red], @[.green], @[.blue], @[.yellow], @[.cyan], @[.magenta], etc.
// Styles: @[.bold], @[.dim], @[.reset]
// Cursor: @[!H] (home), @[G1;2] (goto row 1, col 2)
```

### Box Drawing (`ttyz.termdraw`)

Draw boxes and lines with Unicode characters:

```zig
try ttyz.termdraw.box(&writer, .{
    .x = 10, .y = 5,
    .width = 20, .height = 10,
    .color = .{255, 128, 0, 255},  // RGBA
});

try ttyz.termdraw.hline(&writer, .{ .x = 0, .y = 10, .width = 40 });
try ttyz.termdraw.vline(&writer, .{ .x = 20, .y = 0, .height = 20 });
```

### Kitty Graphics (`ttyz.kitty`)

Display images in terminals supporting the Kitty graphics protocol:

```zig
var image = ttyz.kitty.Image.with(.{
    .a = 'T',  // action: transmit
    .t = 'f',  // transmission: file
    .f = 100,  // format: PNG
}, "/path/to/image.png");
try image.write(&writer);
```

### Canvas Drawing (`ttyz.draw`)

Pixel-level RGBA drawing with Kitty output:

```zig
var canvas = try ttyz.draw.Canvas.initAlloc(allocator, 200, 200);
defer canvas.deinit(allocator);

try canvas.drawBox(10, 10, 50, 50, 0xFF0000FF);  // Red box
try canvas.writeKitty(&writer);
```

### Text Utilities (`ttyz.text`)

Common text operations:

```zig
// Codepoint count (UTF-8)
const width = ttyz.text.codepointCount("Hello");

// Padding
var buf: [32]u8 = undefined;
const padded = ttyz.text.padRight("Hi", 10, &buf);  // "Hi        "

// Truncation with ellipsis
const truncated = try ttyz.text.truncate(allocator, "Long text", 7);  // "Long..."
```

### Testing (`ttyz.TestCapture`)

Test your TUI code without a real terminal:

```zig
const std = @import("std");
const ttyz = @import("ttyz");

test "Frame renders text correctly" {
    const capture = try ttyz.TestCapture.init(std.testing.allocator, 80, 24);
    defer capture.deinit();

    var buffer = try ttyz.Buffer.init(std.testing.allocator, 80, 24);
    defer buffer.deinit();

    var frame = ttyz.Frame.init(&buffer);
    frame.setString(0, 0, "Hello", .{}, .default, .default);
    try frame.render(capture.screen());
    try capture.screen().flush();

    // Verify output
    try std.testing.expect(capture.contains("Hello"));
    try std.testing.expectEqual(@as(usize, 1), capture.count("Hello"));
}
```

## Events

The event system supports:

- **Keyboard**: Letters, numbers, function keys (F1-F12), navigation keys (Home, End, PageUp, PageDown, Insert, Delete), arrow keys
- **Mouse**: Left/middle/right buttons, press/release/motion, scroll wheel
- **Focus**: Terminal focus in/out events (when enabled)
- **Cursor position**: Response to cursor position queries

```zig
while (screen.pollEvent()) |event| {
    switch (event) {
        .key => |key| switch (key) {
            .f1 => showHelp(),
            .arrow_up => moveUp(),
            .home => goToStart(),
            else => {},
        },
        .mouse => |m| handleMouse(m.button, m.row, m.col),
        .focus => |focused| if (!focused) pause(),
        .interrupt => break,
        else => {},
    }
}
```

## Building

```bash
zig build          # Build the library and examples
zig build run      # Run the example application
zig build demo     # Run the interactive demo
zig build test     # Run tests
zig build check    # Run tests and verification
zig build docs     # Generate documentation (output in zig-out/docs/)
```

### Debug Mode

Run with `--debug` to enable logging to stderr:

```bash
zig build run -- --debug 2>/tmp/ttyz.log
```

### Demo Application

The demo showcases all major features in an interactive TUI:

```bash
zig build demo
```

Features demonstrated:
- Tab navigation between sections
- Color palettes (16, 256, and true color)
- Event tracking (keyboard, mouse)
- Box drawing with Unicode characters
- Text utilities and colorz formatting

## License

MIT
