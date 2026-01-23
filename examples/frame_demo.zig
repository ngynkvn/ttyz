//! Frame Demo - Demonstrates the Frame abstraction for cell-based rendering.
//!
//! This example shows:
//! - Creating a Buffer and Frame
//! - Drawing rectangles with different border styles
//! - Drawing styled text
//! - Rendering to the terminal

const std = @import("std");
const ttyz = @import("ttyz");

const Frame = ttyz.Frame;
const Buffer = ttyz.Buffer;
const Cell = ttyz.Cell;
const Rect = ttyz.Rect;
const frame = ttyz.frame;

const Style = frame.Style;
const Color = frame.Color;
const BorderStyle = frame.BorderStyle;

const App = struct {
    buffer: Buffer,
    frame_count: usize = 0,
    selected_border: usize = 0,
    allocator: std.mem.Allocator,

    const border_styles = [_]BorderStyle{ .single, .double, .rounded, .thick };
    const border_names = [_][]const u8{ "Single", "Double", "Rounded", "Thick" };

    pub fn init(self: *App, screen: *ttyz.Screen) !void {
        self.buffer = try Buffer.init(self.allocator, screen.width, screen.height);
    }

    pub fn deinit(self: *App) void {
        self.buffer.deinit();
    }

    pub fn handleEvent(self: *App, event: ttyz.Event) bool {
        switch (event) {
            .key => |k| switch (k) {
                .q => return false,
                .arrow_left => {
                    if (self.selected_border > 0) self.selected_border -= 1;
                },
                .arrow_right => {
                    if (self.selected_border < border_styles.len - 1) self.selected_border += 1;
                },
                else => {},
            },
            .interrupt => return false,
            else => {},
        }
        return true;
    }

    pub fn render(self: *App, screen: *ttyz.Screen) !void {
        // Resize buffer if needed
        if (self.buffer.width != screen.width or self.buffer.height != screen.height) {
            try self.buffer.resize(screen.width, screen.height);
        }

        var f = Frame.init(&self.buffer);
        f.clear();

        // Draw main border
        const main_rect = Rect{ .x = 0, .y = 0, .width = screen.width, .height = screen.height };
        f.drawRectStyled(main_rect, .double, .{}, Color.cyan, .default);

        // Title
        const title = " Frame Demo ";
        const title_x = (screen.width - @as(u16, @intCast(title.len))) / 2;
        f.setString(title_x, 0, title, .{ .bold = true }, Color.yellow, .default);

        // Instructions
        f.setString(2, 2, "Use arrow keys to change border style, Q to quit", .{}, .default, .default);

        // Draw a showcase of border styles
        var x: u16 = 2;
        for (border_styles, 0..) |style, i| {
            const rect = Rect{ .x = x, .y = 4, .width = 16, .height = 7 };
            const is_selected = i == self.selected_border;
            const fg: Color = if (is_selected) Color.green else .default;
            const text_style: Style = if (is_selected) .{ .bold = true } else .{};

            f.drawRectStyled(rect, style, text_style, fg, .default);

            // Label
            const name = border_names[i];
            const label_x = x + (16 - @as(u16, @intCast(name.len))) / 2;
            f.setString(label_x, 5, name, text_style, fg, .default);

            if (is_selected) {
                f.setString(x + 3, 7, "(selected)", .{ .dim = true }, .default, .default);
            }

            x += 18;
        }

        // Style demo box
        const style_box = Rect{ .x = 2, .y = 12, .width = 40, .height = 10 };
        f.drawRect(style_box, border_styles[self.selected_border]);
        f.setString(4, 12, " Text Styles ", .{}, Color.magenta, .default);

        // Demonstrate various text styles
        f.setString(4, 14, "Normal text", .{}, .default, .default);
        f.setString(4, 15, "Bold text", .{ .bold = true }, .default, .default);
        f.setString(4, 16, "Italic text", .{ .italic = true }, .default, .default);
        f.setString(4, 17, "Underlined text", .{ .underline = true }, .default, .default);
        f.setString(4, 18, "Dim text", .{ .dim = true }, .default, .default);
        f.setString(4, 19, "Reversed text", .{ .reverse = true }, .default, .default);

        // Color demo
        f.setString(25, 14, "Red", .{ .bold = true }, Color.red, .default);
        f.setString(25, 15, "Green", .{ .bold = true }, Color.green, .default);
        f.setString(25, 16, "Blue", .{ .bold = true }, Color.blue, .default);
        f.setString(25, 17, "Yellow", .{ .bold = true }, Color.yellow, .default);
        f.setString(25, 18, "Cyan", .{ .bold = true }, Color.cyan, .default);
        f.setString(25, 19, "Magenta", .{ .bold = true }, Color.magenta, .default);

        // RGB color demo
        const rgb_box = Rect{ .x = 44, .y = 12, .width = 30, .height = 10 };
        f.drawRect(rgb_box, .rounded);
        f.setString(46, 12, " RGB Colors ", .{}, .default, .default);

        // Draw a gradient-like display
        var row: u16 = 14;
        while (row < 20) : (row += 1) {
            var col: u16 = 46;
            while (col < 72) : (col += 1) {
                const r: u8 = @intCast((col - 46) * 10);
                const g: u8 = @intCast((row - 14) * 40);
                const b: u8 = 128;
                f.buffer.set(col, row, .{
                    .char = ' ',
                    .bg = Color{ .rgb = .{ .r = r, .g = g, .b = b } },
                });
            }
        }

        // Frame counter
        var buf: [32]u8 = undefined;
        const counter_text = std.fmt.bufPrint(&buf, "Frame: {}", .{self.frame_count}) catch "Frame: ???";
        f.setString(screen.width - @as(u16, @intCast(counter_text.len)) - 2, screen.height - 1, counter_text, .{ .dim = true }, .default, .default);

        self.frame_count += 1;

        // Render the frame to screen
        try f.render(screen);
    }
};

pub fn main(init: std.process.Init) !void {
    var app = App{
        .buffer = undefined,
        .allocator = init.gpa,
    };
    try ttyz.Runner(App).run(&app, init);
}
