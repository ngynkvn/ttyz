# ttyz Guide

This guide provides step-by-step tutorials for building terminal user interfaces with ttyz.

## Table of Contents

1. [Getting Started](#getting-started)
2. [The Runner Pattern](#the-runner-pattern)
3. [Working with Frames](#working-with-frames)
4. [Layouts](#layouts)
5. [Colors and Styles](#colors-and-styles)
6. [Event Handling](#event-handling)
7. [Box Drawing](#box-drawing)
8. [Testing Your TUI](#testing-your-tui)
9. [Advanced Topics](#advanced-topics)

---

## Getting Started

### Prerequisites

- Zig 0.15.2 or later
- Unix-like system (Linux, macOS, BSD)

### Adding ttyz to Your Project

1. Add to `build.zig.zon`:
```zig
.dependencies = .{
    .ttyz = .{
        .url = "https://github.com/ngynkvn/ttyz/archive/<commit>.tar.gz",
        .hash = "...",
    },
},
```

2. In `build.zig`:
```zig
const ttyz = b.dependency("ttyz", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("ttyz", ttyz.module("ttyz"));
```

---

## The Runner Pattern

The `Runner` is the recommended way to build ttyz applications. It handles:
- Screen initialization and cleanup
- The main event loop
- Frame buffer management
- Automatic screen refresh

### Minimal Example

```zig
const std = @import("std");
const ttyz = @import("ttyz");

const App = struct {
    // Called for each event. Return false to exit.
    pub fn handleEvent(_: *App, event: ttyz.Event) bool {
        return switch (event) {
            .key => |k| k != .q,  // Q to quit
            .interrupt => false,  // Ctrl+C
            else => true,
        };
    }

    // Called each frame to render the UI
    pub fn render(_: *App, f: *ttyz.Frame) !void {
        f.setString(0, 0, "Hello, World!", .{}, .default, .default);
    }
};

pub fn main(init: std.process.Init) !void {
    var app = App{};
    try ttyz.Runner(App).run(&app, init, ttyz.Screen.Options.default);
}
```

### Screen Options

Customize screen behavior:

```zig
const options = ttyz.Screen.Options{
    .alt_screen = true,      // Use alternate screen buffer (default: true)
    .hide_cursor = true,     // Hide cursor (default: true)
    .mouse_tracking = true,  // Enable mouse events (default: true)
    .handle_sigint = true,   // Treat Ctrl+C as event, not signal (default: true)
};
try ttyz.Runner(App).run(&app, init, options);
```

---

## Working with Frames

A `Frame` wraps a `Buffer` and provides drawing methods. The Runner creates and manages the Frame for you.

### Drawing Text

```zig
pub fn render(self: *App, f: *ttyz.Frame) !void {
    const Color = ttyz.frame.Color;

    // Basic text
    f.setString(0, 0, "Plain text", .{}, .default, .default);

    // Styled text
    f.setString(0, 1, "Bold text", .{ .bold = true }, .default, .default);
    f.setString(0, 2, "Italic", .{ .italic = true }, .default, .default);
    f.setString(0, 3, "Underlined", .{ .underline = true }, .default, .default);

    // Colored text
    f.setString(0, 4, "Red text", .{}, Color.red, .default);
    f.setString(0, 5, "On blue", .{}, .default, Color.blue);

    // Combined
    f.setString(0, 6, "Bold green on blue", .{ .bold = true }, Color.green, Color.blue);
}
```

### Color Types

```zig
const Color = ttyz.frame.Color;

// Named colors (16-color palette)
Color.black, Color.red, Color.green, Color.yellow
Color.blue, Color.magenta, Color.cyan, Color.white

// Indexed (256-color palette)
Color{ .indexed = 196 }  // Bright red
Color{ .indexed = 240 }  // Gray

// True color (RGB)
Color{ .rgb = .{ .r = 255, .g = 128, .b = 0 } }  // Orange
```

### Drawing Shapes

```zig
const Rect = ttyz.Rect;

// Draw a box outline
f.drawRect(Rect{ .x = 5, .y = 5, .width = 20, .height = 10 }, .single);

// Box styles: .single, .double, .rounded, .thick

// Styled box with colors
f.drawRectStyled(
    Rect{ .x = 30, .y = 5, .width = 20, .height = 10 },
    .double,
    .{ .bold = true },
    Color.cyan,
    .default
);

// Fill a rectangle
f.fillRect(Rect{ .x = 0, .y = 0, .width = 10, .height = 3 }, .{
    .char = ' ',
    .bg = Color.blue,
});
```

---

## Layouts

Layouts help divide screen space without manual coordinate calculations.

### Vertical Layout

```zig
const Layout = ttyz.frame.Layout;

pub fn render(self: *App, f: *ttyz.Frame) !void {
    // Split into header (2 rows), content (fills), footer (1 row)
    const header, const content, const footer = f.areas(3, Layout(3).vertical(.{
        .{ .length = 2 },  // Fixed 2 rows
        .{ .fill = 1 },    // Fill remaining space
        .{ .length = 1 },  // Fixed 1 row
    }));

    // Draw in each area
    f.fillRect(header, .{ .char = ' ', .bg = Color.blue });
    f.setString(header.x + 1, header.y, "Header", .{ .bold = true }, Color.white, Color.blue);

    f.setString(content.x + 1, content.y + 1, "Content area", .{}, .default, .default);

    f.setString(footer.x, footer.y, "Press Q to quit", .{ .dim = true }, .default, .default);
}
```

### Horizontal Layout

```zig
// Split into 3 columns
const left, const middle, const right = Layout(3).horizontal(.{
    .{ .length = 20 },  // Fixed 20 columns
    .{ .fill = 1 },     // Fill remaining
    .{ .length = 20 },  // Fixed 20 columns
}).areas(content);
```

### Layout with Spacing

```zig
const cols = Layout(3).horizontal(.{
    .{ .fill = 1 },
    .{ .fill = 1 },
    .{ .fill = 1 },
}).withSpacing(2).areas(area);  // 2-column gap between each
```

### Nested Layouts

```zig
// Main vertical layout
const header, const body, const footer = f.areas(3, Layout(3).vertical(.{
    .{ .length = 1 },
    .{ .fill = 1 },
    .{ .length = 1 },
}));

// Split body horizontally
const sidebar, const main = Layout(2).horizontal(.{
    .{ .length = 25 },
    .{ .fill = 1 },
}).areas(body);

// Now draw in each area...
```

---

## Colors and Styles

### Using ansi Module Directly

For low-level control or Screen API usage:

```zig
const ansi = ttyz.ansi;

// Inline in format strings (compile-time concatenation)
try screen.print(ansi.bold ++ "Bold text" ++ ansi.reset, .{});
try screen.print(ansi.fg.red ++ "Red" ++ ansi.reset, .{});

// 256 colors
try screen.print(ansi.fg_256_fmt ++ "Color 196" ++ ansi.reset, .{196});

// True color
try screen.print(ansi.fg_rgb_fmt ++ "Orange" ++ ansi.reset, .{255, 128, 0});
```

### Using colorz for Format Strings

```zig
const colorz = ttyz.colorz;

var writer = ...; // Any writer
var clr = colorz.wrap(&writer);

// Color codes in format strings
try clr.print("@[.green]Success:@[.reset] {s}", .{message});
try clr.print("@[.bold]@[.red]Error@[.reset]", .{});

// Available codes:
// Colors: @[.red], @[.green], @[.blue], @[.yellow], @[.cyan], @[.magenta], etc.
// Background: @[.bg_red], @[.bg_blue], etc.
// Styles: @[.bold], @[.dim], @[.italic], @[.underline], @[.reset]
// Cursor: @[!H] (home), @[G1;2] (goto row 1, col 2)
```

---

## Event Handling

### Keyboard Events

```zig
pub fn handleEvent(self: *App, event: ttyz.Event) bool {
    switch (event) {
        .key => |key| switch (key) {
            // Letters (lowercase and uppercase)
            .a, .A => self.doAction(),
            .q, .Q => return false,  // Quit

            // Special keys
            .enter, .carriage_return => self.confirm(),
            .esc => self.cancel(),
            .tab => self.nextField(),
            .backtab => self.prevField(),  // Shift+Tab

            // Navigation
            .arrow_up => self.moveUp(),
            .arrow_down => self.moveDown(),
            .arrow_left => self.moveLeft(),
            .arrow_right => self.moveRight(),
            .home => self.goToStart(),
            .end => self.goToEnd(),
            .page_up => self.pageUp(),
            .page_down => self.pageDown(),

            // Function keys
            .f1 => self.showHelp(),
            .f5 => self.refresh(),

            // Editing
            .delete => self.deleteChar(),
            .insert => self.toggleInsert(),

            else => {},
        },
        else => {},
    }
    return true;
}
```

### Mouse Events

```zig
.mouse => |m| {
    // Position
    const row = m.row;
    const col = m.col;

    // Button
    switch (m.button) {
        .left => if (m.button_state == .pressed) self.click(row, col),
        .right => self.rightClick(row, col),
        .middle => {},
        .scroll_up => self.scrollUp(),
        .scroll_down => self.scrollDown(),
        .none => {},  // Motion only
    }

    // Modifiers
    if (m.ctrl) { /* Ctrl held */ }
    if (m.shift) { /* Shift held */ }
    if (m.meta) { /* Alt/Meta held */ }
},
```

### Focus Events

```zig
.focus => |has_focus| {
    if (has_focus) {
        self.resume();
    } else {
        self.pause();
    }
},
```

### Other Events

```zig
.resize => |size| {
    // Terminal was resized
    self.width = size.width;
    self.height = size.height;
},

.cursor_pos => |pos| {
    // Response to cursor position query
    self.cursor_row = pos.row;
    self.cursor_col = pos.col;
},

.interrupt => {
    // Ctrl+C (when handle_sigint is true)
    return false;
},
```

---

## Box Drawing

### Using termdraw

For direct terminal drawing with Unicode box characters:

```zig
const termdraw = ttyz.termdraw;

// Draw a box (uses heavy box characters: ┏━┓ etc.)
try termdraw.box(&screen, .{
    .x = 5,
    .y = 5,
    .width = 30,
    .height = 10,
    .color = .{ 255, 128, 0, 255 },  // RGBA orange
});

// Horizontal line
try termdraw.hline(&screen, .{
    .x = 0,
    .y = 20,
    .width = 40,
});

// Vertical line
try termdraw.vline(&screen, .{
    .x = 40,
    .y = 0,
    .height = 20,
});
```

### Using Frame.drawRect

For frame-based box drawing:

```zig
// Single line: ┌─┐ │ └─┘
f.drawRect(rect, .single);

// Double line: ╔═╗ ║ ╚═╝
f.drawRect(rect, .double);

// Rounded: ╭─╮ │ ╰─╯
f.drawRect(rect, .rounded);

// Thick/heavy: ┏━┓ ┃ ┗━┛
f.drawRect(rect, .thick);
```

---

## Testing Your TUI

ttyz provides `TestCapture` for testing rendering without a real terminal.

### Basic Test

```zig
const std = @import("std");
const ttyz = @import("ttyz");

test "renders greeting" {
    // Create test capture context
    const capture = try ttyz.TestCapture.init(std.testing.allocator, 80, 24);
    defer capture.deinit();

    // Create buffer and frame
    var buffer = try ttyz.Buffer.init(std.testing.allocator, 80, 24);
    defer buffer.deinit();

    var frame = ttyz.Frame.init(&buffer);

    // Render something
    frame.setString(0, 0, "Welcome!", .{}, .default, .default);
    try frame.render(capture.screen());
    try capture.screen().flush();

    // Assert
    try std.testing.expect(capture.contains("Welcome!"));
}
```

### TestCapture Methods

```zig
// Check if output contains a string
try std.testing.expect(capture.contains("text"));

// Count occurrences
try std.testing.expectEqual(@as(usize, 3), capture.count("foo"));

// Get raw output
const output = capture.getOutput();

// Check output length
try std.testing.expect(!capture.isEmpty());

// Clear for next test
capture.clear();

// Access screen dimensions
try std.testing.expectEqual(@as(u16, 80), capture.screen().width);
```

### Testing with Events

```zig
test "handles key events" {
    const capture = try ttyz.TestCapture.init(std.testing.allocator, 80, 24);
    defer capture.deinit();

    // Inject events
    capture.setEvents(&.{
        .{ .key = .a },
        .{ .key = .b },
        .{ .key = .enter },
    });

    // Process events
    var app = MyApp{};
    while (capture.screen().pollEvent()) |event| {
        if (!app.handleEvent(event)) break;
    }

    // Verify state
    try std.testing.expectEqualStrings("ab", app.input);
}
```

---

## Advanced Topics

### Direct Screen Access

For cases where the Runner pattern doesn't fit:

```zig
pub fn main(init: std.process.Init) !void {
    var screen = try ttyz.Screen.init(init.io, ttyz.Screen.Options.default);
    defer _ = screen.deinit() catch {};

    while (screen.running) {
        // Read input
        screen.readAndQueueEvents();

        // Process events
        while (screen.pollEvent()) |event| {
            // Handle event...
        }

        // Draw directly
        try screen.home();
        try screen.clearScreen();
        try screen.print("Direct output: {}\n", .{value});
        try screen.flush();

        // Rate limit
        init.io.sleep(std.Io.Duration.fromMilliseconds(16), .awake) catch {};
    }
}
```

### Kitty Graphics Protocol

Display images in supported terminals:

```zig
const kitty = ttyz.kitty;

// Load and display an image file
var image = kitty.Image.with(.{
    .a = 'T',   // Action: transmit
    .t = 'f',   // Transmission: file
    .f = 100,   // Format: PNG
}, "/path/to/image.png");
try image.write(&writer);

// Draw to a canvas and display
var canvas = try ttyz.draw.Canvas.initAlloc(allocator, 200, 200);
defer canvas.deinit(allocator);

try canvas.drawBox(10, 10, 50, 50, 0xFF0000FF);
try canvas.writeKitty(&writer);
```

### Custom Panic Handler

ttyz provides a panic handler that restores terminal state:

```zig
// In your main file, before main():
pub const panic = ttyz.panic;

// Or for custom behavior:
pub const panic = std.debug.FullPanic(myPanicFn);

fn myPanicFn(msg: []const u8, ra: ?usize) noreturn {
    // Your cleanup...
    ttyz.panicTty(msg, ra);  // Restores terminal
}
```

---

## Examples

The `examples/` directory contains working examples:

- `hello.zig` - Minimal hello world with Layout
- `colors.zig` - Color palette showcase
- `input.zig` - Keyboard and mouse input handling
- `demo.zig` - Comprehensive feature demo with tabs
- `frame_demo.zig` - Frame and Layout examples
- `progress.zig` - Progress bar animation

Run examples with:
```bash
zig build hello      # or colors, input, demo, etc.
```
