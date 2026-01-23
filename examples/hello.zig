//! Minimal ttyz example - Hello World
//!
//! Demonstrates basic Frame rendering with Layout.

const std = @import("std");
const ttyz = @import("ttyz");
const frame = ttyz.frame;
const Frame = ttyz.Frame;
const Buffer = ttyz.Buffer;
const Layout = frame.Layout;
const Color = frame.Color;

const HelloApp = struct {
    buffer: Buffer,
    allocator: std.mem.Allocator,

    pub fn init(self: *HelloApp, screen: *ttyz.Screen) !void {
        self.buffer = try Buffer.init(self.allocator, screen.width, screen.height);
    }

    pub fn deinit(self: *HelloApp) void {
        self.buffer.deinit();
    }

    pub fn handleEvent(_: *HelloApp, event: ttyz.Event) bool {
        return switch (event) {
            .key => false, // Any key exits
            .interrupt => false,
            else => true,
        };
    }

    pub fn render(self: *HelloApp, screen: *ttyz.Screen) !void {
        if (self.buffer.width != screen.width or self.buffer.height != screen.height) {
            try self.buffer.resize(screen.width, screen.height);
        }

        var f = Frame.init(&self.buffer);
        f.clear();

        // Split into header, content, footer
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
        var buf: [64]u8 = undefined;
        const footer_text = std.fmt.bufPrint(&buf, "Screen: {}x{} | Press any key to exit", .{ screen.width, screen.height }) catch "Press any key";
        f.setString(0, footer.y, footer_text, .{ .dim = true }, .default, .default);

        try f.render(screen);
    }
};

pub fn main(init: std.process.Init) !void {
    var app = HelloApp{ .buffer = undefined, .allocator = init.gpa };
    try ttyz.Runner(HelloApp).run(&app, init);
}
