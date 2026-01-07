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
- **Text utilities** for padding, centering, and display width calculation

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

```zig
const std = @import("std");
const ttyz = @import("ttyz");
const E = ttyz.E;

pub fn main() !void {
    // Initialize raw mode (enters alternate screen, hides cursor)
    var screen = try ttyz.Screen.init();
    defer _ = screen.deinit() catch {};

    // Start the I/O thread for event handling
    try screen.start();

    while (screen.running) {
        // Process events
        while (screen.pollEvent()) |event| {
            switch (event) {
                .key => |key| {
                    if (key == .q) screen.running = false;
                },
                .mouse => |mouse| {
                    try screen.print("Mouse at {},{}\n", .{mouse.row, mouse.col});
                },
                else => {},
            }
        }

        // Draw
        try screen.home();
        try screen.print("Press 'q' to quit. Screen: {}x{}\n", .{screen.width, screen.height});
        try screen.flush();

        std.Thread.sleep(std.time.ns_per_s / 60);
    }
}
```

## Modules

### Core (`ttyz.Screen`)

The main interface for terminal I/O:

```zig
var screen = try ttyz.Screen.init();
defer _ = screen.deinit() catch {};

try screen.start();              // Start I/O thread
try screen.goto(row, col);       // Move cursor
try screen.print("{}", .{val});  // Formatted output
try screen.write("text");        // Raw output
try screen.clearScreen();        // Clear screen
try screen.flush();              // Flush output buffer
```

### Escape Sequences (`ttyz.E`)

VT100/xterm escape sequence constants:

```zig
// Cursor control
E.HOME, E.GOTO, E.CURSOR_UP, E.CURSOR_DOWN

// Screen control
E.CLEAR_SCREEN, E.ENTER_ALT_SCREEN, E.EXIT_ALT_SCREEN

// Colors and styles
E.FG_RED, E.BG_BLUE, E.BOLD, E.UNDERLINE, E.RESET_STYLE
E.SET_FG_256, E.SET_TRUCOLOR  // 256-color and RGB

// Mouse and focus
E.ENABLE_MOUSE_TRACKING, E.ENABLE_FOCUS_EVENTS
```

### Layout System (`ttyz.layout`)

Immediate-mode UI layout inspired by Clay:

```zig
const Root = struct {
    pub var props = layout.NodeProps{
        .sizing = .As(.fit, .fit),
        .layout_direction = .left_right,
        .padding = .All(1),
    };

    pub fn render(ctx: *layout.Context) void {
        ctx.OpenElement(Child.props);
        Child.render(ctx);
        ctx.CloseElement();
    }
};

var ctx = layout.Context.init(allocator, &screen);
const commands = try ctx.render(Root);
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
// Display width (handles unicode)
const width = ttyz.text.displayWidth("Hello");

// Padding
var buf: [32]u8 = undefined;
const padded = ttyz.text.padRight("Hi", 10, &buf);  // "Hi        "

// Truncation with ellipsis
const truncated = try ttyz.text.truncate(allocator, "Long text", 7);  // "Long..."
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
