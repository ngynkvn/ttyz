//! Color showcase example
//!
//! Demonstrates 16, 256, and true color support using Frame and Layout.

const std = @import("std");
const ttyz = @import("ttyz");
const frame = ttyz.frame;
const Frame = ttyz.Frame;
const Buffer = ttyz.Buffer;
const Layout = frame.Layout;
const Color = frame.Color;
const Style = frame.Style;

const ColorDemo = struct {
    buffer: Buffer,
    allocator: std.mem.Allocator,
    hue_offset: u8 = 0,
    frame_count: usize = 0,

    pub fn init(self: *ColorDemo, screen: *ttyz.Screen) !void {
        self.buffer = try Buffer.init(self.allocator, screen.width, screen.height);
    }

    pub fn deinit(self: *ColorDemo) void {
        self.buffer.deinit();
    }

    pub fn handleEvent(_: *ColorDemo, event: ttyz.Event) bool {
        return switch (event) {
            .key => |k| switch (k) {
                .q, .Q, .esc => false,
                else => true,
            },
            .interrupt => false,
            else => true,
        };
    }

    pub fn render(self: *ColorDemo, screen: *ttyz.Screen) !void {
        if (self.buffer.width != screen.width or self.buffer.height != screen.height) {
            try self.buffer.resize(screen.width, screen.height);
        }

        var f = Frame.init(&self.buffer);
        f.clear();

        // Main layout: title, content, footer
        const title_area, const content, const footer = f.areas(3, Layout(3).vertical(.{
            .{ .length = 2 },
            .{ .fill = 1 },
            .{ .length = 1 },
        }));

        // Title
        f.setString(2, title_area.y, "Color Showcase", .{ .bold = true }, Color.cyan, .default);

        // Content sections
        const colors16, const colors256, const truecolor, const styles = Layout(4).vertical(.{
            .{ .length = 4 }, // 16 colors
            .{ .length = 5 }, // 256 colors
            .{ .length = 4 }, // True color
            .{ .fill = 1 }, // Styles
        }).areas(content);

        // 16 basic colors
        self.draw16Colors(&f, colors16);

        // 256 color palette
        self.draw256Colors(&f, colors256);

        // True color gradient
        self.drawTrueColor(&f, truecolor);

        // Text styles
        self.drawStyles(&f, styles);

        // Footer
        f.setString(2, footer.y, "Press Q to quit", .{ .dim = true }, .default, .default);

        self.frame_count += 1;
        if (self.frame_count % 4 == 0) self.hue_offset +%= 1;

        try f.render(screen);
    }

    fn draw16Colors(self: *ColorDemo, f: *Frame, area: frame.Rect) void {
        _ = self;
        f.setString(area.x + 2, area.y, "16 Basic Colors:", .{ .bold = true }, .default, .default);

        // Foreground colors
        const fg_colors = [_]Color{ Color.black, Color.red, Color.green, Color.yellow, Color.blue, Color.magenta, Color.cyan, Color.white };
        var x = area.x + 2;
        for (fg_colors) |c| {
            f.setString(x, area.y + 1, "ABC", .{}, c, .default);
            x += 4;
        }

        // Background colors
        x = area.x + 2;
        for (0..8) |i| {
            f.buffer.set(x, area.y + 2, .{ .char = ' ', .bg = Color{ .indexed = @intCast(i) } });
            f.buffer.set(x + 1, area.y + 2, .{ .char = ' ', .bg = Color{ .indexed = @intCast(i) } });
            f.buffer.set(x + 2, area.y + 2, .{ .char = ' ', .bg = Color{ .indexed = @intCast(i) } });
            x += 4;
        }
    }

    fn draw256Colors(self: *ColorDemo, f: *Frame, area: frame.Rect) void {
        f.setString(area.x + 2, area.y, "256 Color Palette:", .{ .bold = true }, .default, .default);

        // Standard 16
        var x = area.x + 2;
        for (0..16) |i| {
            const c: u8 = @intCast((i + self.hue_offset) % 16);
            f.buffer.set(x, area.y + 1, .{ .char = ' ', .bg = Color{ .indexed = c } });
            f.buffer.set(x + 1, area.y + 1, .{ .char = ' ', .bg = Color{ .indexed = c } });
            x += 2;
        }

        // Color cube slice
        x = area.x + 2;
        for (16..52) |i| {
            const c: u8 = @intCast(16 + ((i - 16 + self.hue_offset) % 216));
            f.buffer.set(x, area.y + 2, .{ .char = ' ', .bg = Color{ .indexed = c } });
            x += 1;
        }

        // Grayscale
        x = area.x + 2;
        for (232..256) |i| {
            f.buffer.set(x, area.y + 3, .{ .char = ' ', .bg = Color{ .indexed = @intCast(i) } });
            x += 1;
        }
    }

    fn drawTrueColor(self: *ColorDemo, f: *Frame, area: frame.Rect) void {
        _ = self;
        f.setString(area.x + 2, area.y, "True Color (24-bit):", .{ .bold = true }, .default, .default);

        // Rainbow gradient
        var x = area.x + 2;
        const width = @min(area.width - 4, 64);
        for (0..width) |i| {
            const hue = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(width));
            const rgb = hsvToRgb(hue, 1.0, 1.0);
            f.buffer.set(x, area.y + 1, .{ .char = ' ', .bg = Color{ .rgb = .{ .r = rgb[0], .g = rgb[1], .b = rgb[2] } } });
            f.buffer.set(x, area.y + 2, .{ .char = ' ', .bg = Color{ .rgb = .{ .r = rgb[0], .g = rgb[1], .b = rgb[2] } } });
            x += 1;
        }
    }

    fn drawStyles(_: *ColorDemo, f: *Frame, area: frame.Rect) void {
        f.setString(area.x + 2, area.y, "Text Styles:", .{ .bold = true }, .default, .default);

        var x = area.x + 2;
        f.setString(x, area.y + 1, "Bold", .{ .bold = true }, .default, .default);
        x += 6;
        f.setString(x, area.y + 1, "Dim", .{ .dim = true }, .default, .default);
        x += 5;
        f.setString(x, area.y + 1, "Italic", .{ .italic = true }, .default, .default);
        x += 8;
        f.setString(x, area.y + 1, "Underline", .{ .underline = true }, .default, .default);
        x += 11;
        f.setString(x, area.y + 1, "Reverse", .{ .reverse = true }, .default, .default);
        x += 9;
        f.setString(x, area.y + 1, "Strike", .{ .strikethrough = true }, .default, .default);
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
    var app = ColorDemo{ .buffer = undefined, .allocator = init.gpa };
    try ttyz.Runner(ColorDemo).run(&app, init);
}
