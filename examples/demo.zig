//! Comprehensive ttyz demo
//!
//! Demonstrates all features using Frame and Layout.

const std = @import("std");
const ttyz = @import("ttyz");
const fr = ttyz.frame;
const Frame = ttyz.Frame;
const Layout = fr.Layout;
const Color = fr.Color;
const Rect = fr.Rect;

const Demo = struct {
    current_tab: Tab = .overview,
    mouse_pos: struct { row: usize = 0, col: usize = 0 } = .{},
    click_count: usize = 0,
    key_history: [8]u8 = .{' '} ** 8,
    key_idx: usize = 0,
    color_offset: u8 = 0,
    anim_frame: usize = 0,

    const Tab = enum { overview, colors, events, boxes, text_demo };
    const tabs = [_]Tab{ .overview, .colors, .events, .boxes, .text_demo };

    fn tabName(t: Tab) []const u8 {
        return switch (t) {
            .overview => "Overview",
            .colors => "Colors",
            .events => "Events",
            .boxes => "Boxes",
            .text_demo => "Text",
        };
    }

    pub fn handleEvent(self: *Demo, event: ttyz.Event) bool {
        switch (event) {
            .key => |key| {
                switch (key) {
                    .q, .Q, .esc => return false,
                    .tab => {
                        const idx = @intFromEnum(self.current_tab);
                        self.current_tab = tabs[(idx + 1) % tabs.len];
                    },
                    else => {
                        const key_val = @intFromEnum(key);
                        if (key_val < 128) {
                            self.key_history[self.key_idx] = @intCast(key_val);
                            self.key_idx = (self.key_idx + 1) % self.key_history.len;
                        }
                    },
                }
            },
            .mouse => |mouse| {
                self.mouse_pos.row = mouse.row;
                self.mouse_pos.col = mouse.col;
                if (mouse.button_state == .pressed) {
                    self.click_count += 1;
                }
            },
            .interrupt => return false,
            else => {},
        }
        return true;
    }

    pub fn render(self: *Demo, f: *Frame) !void {
        // Main layout: header, tabs, content, footer
        const header, const tab_bar, const content, const footer = f.areas(4, Layout(4).vertical(.{
            .{ .length = 1 }, // header
            .{ .length = 2 }, // tabs
            .{ .fill = 1 }, // content
            .{ .length = 1 }, // footer
        }));

        // Header
        f.fillRect(header, .{ .char = ' ', .bg = Color.blue });
        const title = " ttyz Demo ";
        const title_x = header.x + (header.width -| @as(u16, @intCast(title.len))) / 2;
        f.setString(title_x, header.y, title, .{ .bold = true }, Color.white, Color.blue);

        // Tab bar
        self.drawTabBar(f, tab_bar);

        // Content
        switch (self.current_tab) {
            .overview => self.drawOverview(f, content),
            .colors => self.drawColors(f, content),
            .events => self.drawEvents(f, content),
            .boxes => self.drawBoxes(f, content),
            .text_demo => self.drawText(f, content),
        }

        // Footer
        f.fillRect(footer, .{ .char = ' ', .bg = Color{ .indexed = 236 } });
        var buf: [64]u8 = undefined;
        const footer_text = std.fmt.bufPrint(&buf, " Tab: Switch | Q: Quit | {}x{} | Frame: {}", .{ f.buffer.width, f.buffer.height, self.anim_frame }) catch "";
        f.setString(footer.x + 1, footer.y, footer_text, .{}, .default, Color{ .indexed = 236 });

        self.anim_frame +%= 1;
        if (self.anim_frame % 4 == 0) self.color_offset +%= 1;
    }

    fn drawTabBar(self: *Demo, f: *Frame, area: Rect) void {
        var x = area.x + 2;
        for (tabs) |t| {
            const name = tabName(t);
            const is_active = t == self.current_tab;
            if (is_active) {
                f.setString(x, area.y, name, .{ .bold = true }, Color.black, Color.white);
            } else {
                f.setString(x, area.y, name, .{ .dim = true }, .default, .default);
            }
            x += @as(u16, @intCast(name.len)) + 2;
        }
    }

    fn drawOverview(self: *Demo, f: *Frame, area: Rect) void {
        const spinners = [_][]const u8{ "|", "/", "-", "\\" };
        const spinner = spinners[(self.anim_frame / 8) % spinners.len];

        f.setString(area.x + 3, area.y + 1, spinner, .{}, Color.cyan, .default);
        f.setString(area.x + 5, area.y + 1, "Welcome to ttyz!", .{ .bold = true }, .default, .default);

        const features = [_][]const u8{
            "A Zig library for terminal user interfaces",
            "",
            "Features:",
            "  * Raw mode terminal I/O with auto-restore",
            "  * Keyboard, mouse, and focus events",
            "  * Box drawing with Unicode characters",
            "  * 16, 256, and true color support",
            "  * Frame-based rendering with Layout",
            "  * Kitty graphics protocol support",
            "",
            "Navigation:",
            "  Tab        - Switch tabs",
            "  Q / Esc    - Quit",
        };

        for (features, 0..) |line, i| {
            f.setString(area.x + 5, area.y + 3 + @as(u16, @intCast(i)), line, .{}, .default, .default);
        }
    }

    fn drawColors(self: *Demo, f: *Frame, area: Rect) void {
        // 16 colors
        f.setString(area.x + 3, area.y + 1, "16 Basic Colors:", .{ .bold = true }, .default, .default);
        var x = area.x + 3;
        for (0..8) |i| {
            const c: u8 = @intCast(i);
            f.buffer.set(x, area.y + 2, .{ .char = ' ', .bg = Color{ .indexed = c } });
            f.buffer.set(x + 1, area.y + 2, .{ .char = ' ', .bg = Color{ .indexed = c } });
            x += 2;
        }
        x = area.x + 3;
        for (8..16) |i| {
            const c: u8 = @intCast(i);
            f.buffer.set(x, area.y + 3, .{ .char = ' ', .bg = Color{ .indexed = c } });
            f.buffer.set(x + 1, area.y + 3, .{ .char = ' ', .bg = Color{ .indexed = c } });
            x += 2;
        }

        // 256 colors
        f.setString(area.x + 3, area.y + 5, "256 Color Palette:", .{ .bold = true }, .default, .default);
        x = area.x + 3;
        for (0..36) |i| {
            const c: u8 = @intCast(16 + ((i + self.color_offset) % 216));
            f.buffer.set(x, area.y + 6, .{ .char = ' ', .bg = Color{ .indexed = c } });
            x += 1;
        }
        x = area.x + 3;
        for (232..256) |i| {
            f.buffer.set(x, area.y + 7, .{ .char = ' ', .bg = Color{ .indexed = @intCast(i) } });
            x += 1;
        }

        // True color
        f.setString(area.x + 3, area.y + 9, "True Color:", .{ .bold = true }, .default, .default);
        x = area.x + 3;
        for (0..36) |i| {
            const hue = @as(f32, @floatFromInt(i)) / 36.0;
            const rgb = hsvToRgb(hue, 1.0, 1.0);
            f.buffer.set(x, area.y + 10, .{ .char = ' ', .bg = Color{ .rgb = .{ .r = rgb[0], .g = rgb[1], .b = rgb[2] } } });
            x += 1;
        }

        // Styles
        f.setString(area.x + 3, area.y + 12, "Styles:", .{ .bold = true }, .default, .default);
        x = area.x + 3;
        f.setString(x, area.y + 13, "Bold", .{ .bold = true }, .default, .default);
        x += 6;
        f.setString(x, area.y + 13, "Dim", .{ .dim = true }, .default, .default);
        x += 5;
        f.setString(x, area.y + 13, "Italic", .{ .italic = true }, .default, .default);
        x += 8;
        f.setString(x, area.y + 13, "Underline", .{ .underline = true }, .default, .default);
        x += 11;
        f.setString(x, area.y + 13, "Reverse", .{ .reverse = true }, .default, .default);
    }

    fn drawEvents(self: *Demo, f: *Frame, area: Rect) void {
        f.setString(area.x + 3, area.y + 1, "Event Tracking:", .{ .bold = true }, .default, .default);

        var buf: [64]u8 = undefined;
        const mouse_str = std.fmt.bufPrint(&buf, "({}, {})", .{ self.mouse_pos.row, self.mouse_pos.col }) catch "?";
        f.setString(area.x + 5, area.y + 3, "Mouse Position:", .{}, .default, .default);
        f.setString(area.x + 22, area.y + 3, mouse_str, .{}, Color.green, .default);

        const click_str = std.fmt.bufPrint(&buf, "{}", .{self.click_count}) catch "?";
        f.setString(area.x + 5, area.y + 4, "Click Count:", .{}, .default, .default);
        f.setString(area.x + 22, area.y + 4, click_str, .{}, Color.yellow, .default);

        f.setString(area.x + 5, area.y + 5, "Recent Keys:", .{}, .default, .default);
        var x = area.x + 22;
        for (self.key_history) |k| {
            if (std.ascii.isPrint(k)) {
                f.buffer.set(x, area.y + 5, .{ .char = '[', .fg = Color.cyan });
                f.buffer.set(x + 1, area.y + 5, .{ .char = k, .fg = Color.cyan });
                f.buffer.set(x + 2, area.y + 5, .{ .char = ']', .fg = Color.cyan });
            }
            x += 4;
        }

        // Button
        const btn_x = area.x + 10;
        const btn_y = area.y + 8;
        f.fillRect(Rect{ .x = btn_x, .y = btn_y, .width = 12, .height = 1 }, .{ .char = ' ', .bg = Color.blue });
        f.setString(btn_x + 1, btn_y, "Click Me!", .{ .bold = true }, Color.white, Color.blue);

        if (self.mouse_pos.row == btn_y and self.mouse_pos.col >= btn_x and self.mouse_pos.col < btn_x + 12) {
            f.setString(btn_x + 13, btn_y, "<- Hovering!", .{}, Color.green, .default);
        }
    }

    fn drawBoxes(self: *Demo, f: *Frame, area: Rect) void {
        _ = self;
        // Draw boxes using layout
        const cols = Layout(3).horizontal(.{
            .{ .fill = 1 },
            .{ .fill = 1 },
            .{ .fill = 1 },
        }).withSpacing(2).areas(area.inner(2));

        f.drawRectStyled(Rect{ .x = cols[0].x, .y = cols[0].y, .width = @min(cols[0].width, 18), .height = 7 }, .single, .{}, Color.red, .default);
        f.setString(cols[0].x + 2, cols[0].y + 3, "Single", .{}, Color.red, .default);

        f.drawRectStyled(Rect{ .x = cols[1].x, .y = cols[1].y, .width = @min(cols[1].width, 18), .height = 7 }, .double, .{}, Color.green, .default);
        f.setString(cols[1].x + 2, cols[1].y + 3, "Double", .{}, Color.green, .default);

        f.drawRectStyled(Rect{ .x = cols[2].x, .y = cols[2].y, .width = @min(cols[2].width, 18), .height = 7 }, .rounded, .{}, Color.blue, .default);
        f.setString(cols[2].x + 2, cols[2].y + 3, "Rounded", .{}, Color.blue, .default);

        // Nested box
        const nested_y = cols[0].y + 8;
        f.drawRectStyled(Rect{ .x = area.x + 3, .y = nested_y, .width = 30, .height = 5 }, .thick, .{}, Color.yellow, .default);
        f.drawRectStyled(Rect{ .x = area.x + 5, .y = nested_y + 1, .width = 26, .height = 3 }, .single, .{}, Color.magenta, .default);
        f.setString(area.x + 8, nested_y + 2, "Nested boxes!", .{}, .default, .default);
    }

    fn drawText(self: *Demo, f: *Frame, area: Rect) void {
        _ = self;
        f.setString(area.x + 3, area.y + 1, "Text Rendering:", .{ .bold = true }, .default, .default);

        // Unicode
        f.setString(area.x + 5, area.y + 3, "Unicode:", .{}, .default, .default);
        f.setString(area.x + 15, area.y + 3, "\u{2764} \u{2605} \u{2603} \u{2602} \u{263A}", .{}, Color.red, .default);

        // Box drawing
        f.setString(area.x + 5, area.y + 5, "Box chars:", .{}, .default, .default);
        f.setString(area.x + 15, area.y + 5, "\u{250C}\u{2500}\u{2510} \u{2554}\u{2550}\u{2557} \u{256D}\u{2500}\u{256E}", .{}, Color.cyan, .default);

        // Blocks
        f.setString(area.x + 5, area.y + 7, "Blocks:", .{}, .default, .default);
        f.setString(area.x + 15, area.y + 7, "\u{2588}\u{2589}\u{258A}\u{258B}\u{258C}\u{258D}\u{258E}\u{258F}", .{}, Color.green, .default);

        // Braille
        f.setString(area.x + 5, area.y + 9, "Braille:", .{}, .default, .default);
        f.setString(area.x + 15, area.y + 9, "\u{2801}\u{2803}\u{2807}\u{280F}\u{281F}\u{283F}\u{287F}\u{28FF}", .{}, Color.yellow, .default);
    }
};

fn hsvToRgb(h: f32, s: f32, v: f32) [3]u8 {
    const i_val = @as(u32, @intFromFloat(h * 6));
    const f = h * 6 - @as(f32, @floatFromInt(i_val));
    const p = v * (1 - s);
    const q = v * (1 - f * s);
    const t = v * (1 - (1 - f) * s);

    const rgb: [3]f32 = switch (i_val % 6) {
        0 => .{ v, t, p },
        1 => .{ q, v, p },
        2 => .{ p, v, t },
        3 => .{ p, q, v },
        4 => .{ t, p, v },
        else => .{ v, p, q },
    };

    return .{
        @intFromFloat(rgb[0] * 255),
        @intFromFloat(rgb[1] * 255),
        @intFromFloat(rgb[2] * 255),
    };
}

pub fn main(init: std.process.Init) !void {
    // Allocate buffers for Screen
    var writer_buf: [4096]u8 = undefined;
    var textinput_buf: [32]u8 = undefined;
    var event_buf: [32]ttyz.Event = undefined;

    var app = Demo{};
    try ttyz.Runner(Demo).run(&app, init, .{
        .writer = &writer_buf,
        .textinput = &textinput_buf,
        .events = &event_buf,
    });
}
