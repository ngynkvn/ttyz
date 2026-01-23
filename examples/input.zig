//! Event handling example
//!
//! Demonstrates keyboard and mouse event handling using Frame and Layout.

const std = @import("std");
const ttyz = @import("ttyz");
const frame = ttyz.frame;
const Frame = ttyz.Frame;
const Layout = frame.Layout;
const Color = frame.Color;

const InputDemo = struct {
    last_key: ?ttyz.Event.Key = null,
    mouse_pos: struct { row: usize = 0, col: usize = 0 } = .{},
    click_count: usize = 0,
    key_history: [8]u8 = .{' '} ** 8,
    key_idx: usize = 0,

    pub fn handleEvent(self: *InputDemo, event: ttyz.Event) bool {
        switch (event) {
            .key => |key| {
                self.last_key = key;
                const key_val = @intFromEnum(key);
                if (key_val < 128) {
                    self.key_history[self.key_idx] = @intCast(key_val);
                    self.key_idx = (self.key_idx + 1) % self.key_history.len;
                }
                return switch (key) {
                    .q, .Q, .esc => false,
                    else => true,
                };
            },
            .mouse => |mouse| {
                self.mouse_pos.row = mouse.row;
                self.mouse_pos.col = mouse.col;
                if (mouse.button_state == .pressed) {
                    self.click_count += 1;
                }
                return true;
            },
            .interrupt => return false,
            else => return true,
        }
    }

    pub fn render(self: *InputDemo, f: *Frame) !void {
        // Main layout
        const title_area, const content, const footer = f.areas(3, Layout(3).vertical(.{
            .{ .length = 2 },
            .{ .fill = 1 },
            .{ .length = 1 },
        }));

        // Title
        f.setString(2, title_area.y, "Event Handling Demo", .{ .bold = true }, Color.cyan, .default);

        // Content split into left (info) and right (button area)
        const info, const btn_area = Layout(2).horizontal(.{
            .{ .fill = 1 },
            .{ .fill = 1 },
        }).areas(content);
        var buf: [64]u8 = undefined;

        f.setString(info.x + 2, info.y + 1, "Last Key:", .{}, .default, .default);
        if (self.last_key) |key| {
            const key_val = @intFromEnum(key);
            if (key_val >= 32 and key_val < 127) {
                const key_str = std.fmt.bufPrint(&buf, "'{c}' ({})", .{ @as(u8, @intCast(key_val)), key_val }) catch "?";
                f.setString(info.x + 12, info.y + 1, key_str, .{}, Color.cyan, .default);
            } else {
                const key_str = std.fmt.bufPrint(&buf, "{s} ({})", .{ @tagName(key), key_val }) catch "?";
                f.setString(info.x + 12, info.y + 1, key_str, .{}, Color.cyan, .default);
            }
        } else {
            f.setString(info.x + 12, info.y + 1, "(none)", .{ .dim = true }, .default, .default);
        }

        const mouse_str = std.fmt.bufPrint(&buf, "row={}, col={}", .{ self.mouse_pos.row, self.mouse_pos.col }) catch "?";
        f.setString(info.x + 2, info.y + 3, "Mouse:", .{}, .default, .default);
        f.setString(info.x + 12, info.y + 3, mouse_str, .{}, Color.green, .default);

        const click_str = std.fmt.bufPrint(&buf, "{}", .{self.click_count}) catch "?";
        f.setString(info.x + 2, info.y + 4, "Clicks:", .{}, .default, .default);
        f.setString(info.x + 12, info.y + 4, click_str, .{}, Color.yellow, .default);

        f.setString(info.x + 2, info.y + 6, "History:", .{}, .default, .default);
        var x = info.x + 12;
        for (self.key_history) |k| {
            if (std.ascii.isPrint(k)) {
                f.buffer.set(x, info.y + 6, .{ .char = '[', .fg = Color.cyan });
                f.buffer.set(x + 1, info.y + 6, .{ .char = k, .fg = Color.cyan });
                f.buffer.set(x + 2, info.y + 6, .{ .char = ']', .fg = Color.cyan });
            } else {
                f.setString(x, info.y + 6, "[?]", .{}, Color.cyan, .default);
            }
            x += 4;
        }

        // Right: Interactive button
        const btn_x = btn_area.x + 4;
        const btn_y = btn_area.y + 3;
        f.drawRect(frame.Rect{ .x = btn_x, .y = btn_y, .width = 14, .height = 3 }, .rounded);
        f.setString(btn_x + 2, btn_y + 1, "Click Me!", .{ .bold = true }, Color.blue, .default);

        // Hover detection
        if (self.mouse_pos.row >= btn_y and self.mouse_pos.row < btn_y + 3 and
            self.mouse_pos.col >= btn_x and self.mouse_pos.col < btn_x + 14)
        {
            f.setString(btn_x + 15, btn_y + 1, "<- Hovering!", .{}, Color.green, .default);
        }

        // Footer
        f.setString(2, footer.y, "Press Q or ESC to quit", .{ .dim = true }, .default, .default);
    }
};

pub fn main(init: std.process.Init) !void {
    var app = InputDemo{};
    try ttyz.Runner(InputDemo).runWithOptions(&app, init, .{ .fps = 60 });
}
