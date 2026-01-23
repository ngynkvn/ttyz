//! Minimal ttyz example - Hello World
//!
//! Demonstrates basic Frame rendering with Layout.

const std = @import("std");
const ttyz = @import("ttyz");
const Frame = ttyz.Frame;
const Layout = ttyz.frame.Layout;
const Color = ttyz.frame.Color;

const HelloApp = struct {
    pub fn handleEvent(_: *HelloApp, event: ttyz.Event) bool {
        return switch (event) {
            .key => false, // Any key exits
            .interrupt => false,
            else => true,
        };
    }

    pub fn render(_: *HelloApp, f: *Frame) !void {
        const header, const content, const footer = f.areas(3, Layout(3).vertical(.{
            .{ .length = 1 },
            .{ .fill = 1 },
            .{ .length = 1 },
        }));

        // Header
        f.setString(0, header.y, "ttyz - Terminal UI Library", .{ .bold = true }, Color.cyan, .default);

        // Center content
        const msg = "Hello, ttyz!";
        const cx = content.x + (content.width -| @as(u16, @intCast(msg.len))) / 2;
        const cy = content.y + content.height / 2;
        f.setString(cx, cy, msg, .{ .bold = true }, Color.green, .default);

        // Footer
        f.setString(0, footer.y, "Press any key to exit", .{ .dim = true }, .default, .default);
    }
};

pub fn main(init: std.process.Init) !void {
    var app = HelloApp{};
    try ttyz.Runner(HelloApp).run(&app, init);
}
