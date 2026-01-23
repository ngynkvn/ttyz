//! Frame Demo - Demonstrates the Frame abstraction for cell-based rendering.
//!
//! This example shows:
//! - Using Layout to split areas
//! - Drawing rectangles with different border styles
//! - Drawing styled text
//! - Rendering to the terminal

const std = @import("std");
const ttyz = @import("ttyz");

const Frame = ttyz.Frame;
const Rect = ttyz.Rect;
const frame = ttyz.frame;
const Layout = frame.Layout;

const Style = frame.Style;
const Color = frame.Color;
const BorderStyle = frame.BorderStyle;

const App = struct {
    frame_count: usize = 0,
    selected_border: usize = 0,

    const border_styles = [_]BorderStyle{ .single, .double, .rounded, .thick };
    const border_names = [_][]const u8{ "Single", "Double", "Rounded", "Thick" };

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

    pub fn render(self: *App, f: *Frame) !void {
        // Use Layout to split into header, content, and footer
        const header, const content, const footer = f.areas(3, Layout(3).vertical(.{
            .{ .length = 3 }, // header
            .{ .fill = 1 }, // content
            .{ .length = 1 }, // footer
        }));

        // Draw header with title
        f.drawRectStyled(header, .double, .{}, Color.cyan, .default);
        const title = " Frame Demo ";
        const title_x = header.x + (header.width - @as(u16, @intCast(title.len))) / 2;
        f.setString(title_x, header.y, title, .{ .bold = true }, Color.yellow, .default);
        f.setString(header.x + 2, header.y + 1, "Use arrow keys to change border style, Q to quit", .{}, .default, .default);

        // Split content into top (border showcase) and bottom (demos)
        const showcase_area, const demo_area = Layout(2).vertical(.{
            .{ .length = 8 }, // border showcase
            .{ .fill = 1 }, // demos
        }).areas(content);

        // Draw border style showcase using horizontal layout
        const col0, const col1, const col2, const col3 = Layout(4).horizontal(.{
            .{ .fill = 1 },
            .{ .fill = 1 },
            .{ .fill = 1 },
            .{ .fill = 1 },
        }).withSpacing(2).areas(showcase_area.inner(1));
        const showcase_cols = [_]Rect{ col0, col1, col2, col3 };

        for (border_styles, 0..) |style, i| {
            const col = showcase_cols[i];
            const rect = Rect{ .x = col.x, .y = col.y, .width = @min(col.width, 16), .height = 7 };
            const is_selected = i == self.selected_border;
            const fg: Color = if (is_selected) Color.green else .default;
            const text_style: Style = if (is_selected) .{ .bold = true } else .{};

            f.drawRectStyled(rect, style, text_style, fg, .default);

            const name = border_names[i];
            const label_x = rect.x + (rect.width - @as(u16, @intCast(name.len))) / 2;
            f.setString(label_x, rect.y + 1, name, text_style, fg, .default);

            if (is_selected) {
                f.setString(rect.x + 3, rect.y + 3, "(selected)", .{ .dim = true }, .default, .default);
            }
        }

        // Split demo area into left (styles) and right (colors)
        const style_area, const color_area = Layout(2).horizontal(.{
            .{ .fill = 1 },
            .{ .fill = 1 },
        }).withSpacing(2).areas(demo_area);

        // Style demo box
        f.drawRect(style_area, border_styles[self.selected_border]);
        f.setString(style_area.x + 2, style_area.y, " Text Styles ", .{}, Color.magenta, .default);

        // Demonstrate various text styles
        const sy = style_area.y + 2;
        const sx = style_area.x + 2;
        f.setString(sx, sy, "Normal text", .{}, .default, .default);
        f.setString(sx, sy + 1, "Bold text", .{ .bold = true }, .default, .default);
        f.setString(sx, sy + 2, "Italic text", .{ .italic = true }, .default, .default);
        f.setString(sx, sy + 3, "Underlined text", .{ .underline = true }, .default, .default);
        f.setString(sx, sy + 4, "Dim text", .{ .dim = true }, .default, .default);
        f.setString(sx, sy + 5, "Reversed text", .{ .reverse = true }, .default, .default);

        // Color demo in right column
        f.drawRect(color_area, .rounded);
        f.setString(color_area.x + 2, color_area.y, " Colors ", .{}, .default, .default);

        const cy = color_area.y + 2;
        const cx = color_area.x + 2;
        f.setString(cx, cy, "Red", .{ .bold = true }, Color.red, .default);
        f.setString(cx, cy + 1, "Green", .{ .bold = true }, Color.green, .default);
        f.setString(cx, cy + 2, "Blue", .{ .bold = true }, Color.blue, .default);
        f.setString(cx, cy + 3, "Yellow", .{ .bold = true }, Color.yellow, .default);
        f.setString(cx, cy + 4, "Cyan", .{ .bold = true }, Color.cyan, .default);
        f.setString(cx, cy + 5, "Magenta", .{ .bold = true }, Color.magenta, .default);

        // RGB gradient in color area
        const grad_y = cy + 7;
        if (grad_y < color_area.bottom() - 1) {
            var col: u16 = cx;
            while (col < color_area.right() - 2) : (col += 1) {
                const r: u8 = @intCast(@min(255, (col - cx) * 10));
                const g: u8 = 128;
                const b: u8 = @intCast(255 -| (col - cx) * 10);
                f.buffer.set(col, grad_y, .{
                    .char = ' ',
                    .bg = Color{ .rgb = .{ .r = r, .g = g, .b = b } },
                });
            }
        }

        // Footer with frame counter
        var buf: [64]u8 = undefined;
        const counter_text = std.fmt.bufPrint(&buf, " Frame: {} | Screen: {}x{} ", .{ self.frame_count, f.buffer.width, f.buffer.height }) catch " Frame: ??? ";
        f.fillRect(footer, .{ .char = ' ', .bg = Color{ .indexed = 236 } });
        f.setString(footer.x + 1, footer.y, counter_text, .{}, .default, Color{ .indexed = 236 });

        self.frame_count += 1;
    }
};

pub fn main(init: std.process.Init) !void {
    var app = App{};
    try ttyz.Runner(App).run(&app, init);
}
