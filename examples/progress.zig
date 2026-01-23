//! Progress bar and spinner example
//!
//! Demonstrates animated terminal output with progress indicators using Frame and Layout.

const std = @import("std");
const ttyz = @import("ttyz");
const frame = ttyz.frame;
const Frame = ttyz.Frame;
const Layout = frame.Layout;
const Color = frame.Color;

const ProgressDemo = struct {
    step: usize = 0,
    anim_frame: usize = 0,
    total_steps: usize = 100,
    complete: bool = false,

    const spinners = [_][]const u8{ "|", "/", "-", "\\" };
    const dots = [_][]const u8{ ".  ", ".. ", "...", " ..", "  .", "   " };
    const braille = [_][]const u8{ "\u{28F7}", "\u{28EF}", "\u{28DF}", "\u{287F}", "\u{28BF}", "\u{28FB}", "\u{28FD}", "\u{28FE}" };

    pub fn handleEvent(self: *ProgressDemo, event: ttyz.Event) bool {
        return switch (event) {
            .key => |k| switch (k) {
                .q, .Q, .esc => false,
                else => !self.complete,
            },
            .interrupt => false,
            else => !self.complete,
        };
    }

    pub fn render(self: *ProgressDemo, f: *Frame) !void {
        // Main layout
        const title_area, const content, const footer_area = f.areas(3, Layout(3).vertical(.{
            .{ .length = 2 },
            .{ .fill = 1 },
            .{ .length = 1 },
        }));

        // Title
        f.setString(2, title_area.y, "Progress Demo", .{ .bold = true }, Color.cyan, .default);

        const progress = @as(f32, @floatFromInt(self.step)) / @as(f32, @floatFromInt(self.total_steps));

        if (self.step > self.total_steps) {
            // Completion message
            const msg = "Complete!";
            const cx = content.x + (content.width -| @as(u16, @intCast(msg.len))) / 2;
            const cy = content.y + content.height / 2;
            f.setString(cx, cy, msg, .{ .bold = true }, Color.green, .default);
            self.complete = true;
        } else {
            // Content sections
            const prog_area, const spin_area, const task_area = Layout(3).vertical(.{
                .{ .length = 3 }, // Main progress
                .{ .length = 5 }, // Spinners
                .{ .fill = 1 }, // Tasks
            }).areas(content);

            // Main progress bar
            self.drawProgressBar(f, prog_area.x + 2, prog_area.y + 1, 40, progress);

            // Spinners section
            f.setString(spin_area.x + 2, spin_area.y, "Spinners:", .{}, .default, .default);
            f.setString(spin_area.x + 4, spin_area.y + 1, spinners[self.anim_frame % spinners.len], .{}, Color.cyan, .default);
            f.setString(spin_area.x + 7, spin_area.y + 1, "Working...", .{}, .default, .default);
            f.setString(spin_area.x + 4, spin_area.y + 2, dots[(self.anim_frame / 2) % dots.len], .{}, Color.yellow, .default);
            f.setString(spin_area.x + 9, spin_area.y + 2, "Loading", .{}, .default, .default);
            f.setString(spin_area.x + 4, spin_area.y + 3, braille[self.anim_frame % braille.len], .{}, Color.magenta, .default);
            f.setString(spin_area.x + 7, spin_area.y + 3, "Processing", .{}, .default, .default);

            // Multiple tasks
            f.setString(task_area.x + 2, task_area.y, "Tasks:", .{}, .default, .default);
            const task_progress = [_]f32{
                @min(1.0, progress * 1.5),
                @min(1.0, progress * 1.2),
                progress,
                @min(1.0, @max(0, progress * 2.0 - 0.5)),
            };
            const task_names = [_][]const u8{ "Download", "Extract ", "Build   ", "Install " };

            for (task_names, task_progress, 0..) |name, p, i| {
                const y = task_area.y + 1 + @as(u16, @intCast(i));
                f.setString(task_area.x + 4, y, name, .{}, .default, .default);
                if (p >= 1.0) {
                    f.setString(task_area.x + 13, y, "[done]", .{}, Color.green, .default);
                } else if (p > 0) {
                    self.drawProgressBar(f, task_area.x + 13, y, 20, p);
                } else {
                    f.setString(task_area.x + 13, y, "[waiting]", .{ .dim = true }, .default, .default);
                }
            }

            self.step += 1;
            self.anim_frame += 1;
        }

        // Footer
        var buf: [32]u8 = undefined;
        const footer_text = std.fmt.bufPrint(&buf, "Step {}/{}", .{ @min(self.step, self.total_steps), self.total_steps }) catch "...";
        f.setString(2, footer_area.y, footer_text, .{ .dim = true }, .default, .default);
    }

    fn drawProgressBar(self: *ProgressDemo, f: *Frame, x: u16, y: u16, width: u16, progress: f32) void {
        _ = self;
        const filled = @as(u16, @intFromFloat(progress * @as(f32, @floatFromInt(width))));

        f.buffer.set(x, y, .{ .char = '[' });
        var i: u16 = 0;
        while (i < filled and i < width) : (i += 1) {
            f.buffer.set(x + 1 + i, y, .{ .char = '=', .fg = Color.green });
        }
        if (filled < width) {
            f.buffer.set(x + 1 + filled, y, .{ .char = '>', .fg = Color.green });
            i = filled + 1;
        }
        while (i < width) : (i += 1) {
            f.buffer.set(x + 1 + i, y, .{ .char = ' ' });
        }
        f.buffer.set(x + 1 + width, y, .{ .char = ']' });

        // Percentage
        var buf: [8]u8 = undefined;
        const pct = std.fmt.bufPrint(&buf, "{d:>5.1}%", .{progress * 100}) catch "???%";
        f.setString(x + width + 3, y, pct, .{}, .default, .default);
    }
};

pub fn main(init: std.process.Init) !void {
    var app = ProgressDemo{};
    try ttyz.Runner(ProgressDemo).run(&app, init);
}
