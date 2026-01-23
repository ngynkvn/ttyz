//! Progress bar and spinner example
//!
//! Demonstrates animated terminal output with progress indicators using ttyz.Runner.

const std = @import("std");
const ttyz = @import("ttyz");
const ansi = ttyz.ansi;

const ProgressDemo = struct {
    step: usize = 0,
    frame: usize = 0,
    total_steps: usize = 100,
    complete: bool = false,

    /// Spinner characters
    const spinners = [_][]const u8{ "|", "/", "-", "\\" };
    const dots = [_][]const u8{ ".  ", ".. ", "...", " ..", "  .", "   " };
    const braille = [_][]const u8{ "\u{28F7}", "\u{28EF}", "\u{28DF}", "\u{287F}", "\u{28BF}", "\u{28FB}", "\u{28FD}", "\u{28FE}" };

    pub fn handleEvent(self: *ProgressDemo, event: ttyz.Event) bool {
        switch (event) {
            .key => |key| {
                switch (key) {
                    .q, .Q, .esc => return false,
                    else => {},
                }
            },
            .interrupt => return false,
            else => {},
        }
        // Stop when complete
        return !self.complete;
    }

    pub fn render(self: *ProgressDemo, screen: *ttyz.Screen) !void {
        if (self.step > self.total_steps) {
            // Show completion message and mark complete
            try screen.print("\r\n\r\n" ++ ansi.fg.green ++ ansi.bold ++ "  Complete!" ++ ansi.reset ++ "\r\n", .{});
            self.complete = true;
            return;
        }

        try screen.clearScreen();
        try screen.home();
        try screen.print(ansi.bold ++ "Progress Demo" ++ ansi.reset ++ "\r\n\r\n", .{});

        // Main progress bar
        const progress = @as(f32, @floatFromInt(self.step)) / @as(f32, @floatFromInt(self.total_steps));
        try screen.print("  ", .{});
        try self.drawProgressBar(screen, progress, 40);
        try screen.print("\r\n\r\n", .{});

        // Different spinner styles
        try screen.print("  Spinners:\r\n", .{});
        try screen.print("    Basic:   " ++ ansi.fg.cyan ++ "{s}" ++ ansi.reset ++ "  Working...\r\n", .{spinners[self.frame % spinners.len]});
        try screen.print("    Dots:    " ++ ansi.fg.yellow ++ "{s}" ++ ansi.reset ++ "  Loading\r\n", .{dots[(self.frame / 2) % dots.len]});
        try screen.print("    Braille: " ++ ansi.fg.magenta ++ "{s}" ++ ansi.reset ++ "  Processing\r\n\r\n", .{braille[self.frame % braille.len]});

        // Multiple concurrent progress bars
        try screen.print("  Multiple tasks:\r\n", .{});
        const task_progress = [_]f32{
            @min(1.0, progress * 1.5),
            @min(1.0, progress * 1.2),
            progress,
            @min(1.0, @max(0, progress * 2.0 - 0.5)),
        };
        const task_names = [_][]const u8{ "Download ", "Extract  ", "Build    ", "Install  " };

        for (task_names, task_progress) |name, p| {
            try screen.print("    {s} ", .{name});
            if (p >= 1.0) {
                try screen.print(ansi.fg.green ++ "[done]" ++ ansi.reset ++ "\r\n", .{});
            } else if (p > 0) {
                try self.drawProgressBar(screen, p, 20);
                try screen.print("\r\n", .{});
            } else {
                try screen.print(ansi.faint ++ "[waiting]" ++ ansi.reset ++ "\r\n", .{});
            }
        }

        try screen.print("\r\n" ++ ansi.faint ++ "  Step {}/{}" ++ ansi.reset, .{ self.step, self.total_steps });

        self.step += 1;
        self.frame += 1;
    }

    /// Draw a simple progress bar
    fn drawProgressBar(self: *ProgressDemo, screen: *ttyz.Screen, progress: f32, width: u16) !void {
        _ = self;
        const filled = @as(u16, @intFromFloat(progress * @as(f32, @floatFromInt(width))));
        const empty = width - filled;

        try screen.print("[", .{});
        try screen.print(ansi.fg.green, .{});

        var i: u16 = 0;
        while (i < filled) : (i += 1) {
            try screen.print("=", .{});
        }
        if (filled < width) {
            try screen.print(">", .{});
            i = 1;
        } else {
            i = 0;
        }
        try screen.print(ansi.reset, .{});
        while (i < empty) : (i += 1) {
            try screen.print(" ", .{});
        }

        try screen.print("] {d:>5.1}%", .{progress * 100});
    }
};

pub fn main(init: std.process.Init) !void {
    var app = ProgressDemo{};
    try ttyz.Runner(ProgressDemo).run(&app, init);
}
