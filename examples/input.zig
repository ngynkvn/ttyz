//! Event handling example
//!
//! Demonstrates keyboard and mouse event handling with ttyz.Runner.

const std = @import("std");
const ttyz = @import("ttyz");
const ansi = ttyz.ansi;

const InputDemo = struct {
    last_key: ?ttyz.Event.Key = null,
    mouse_pos: struct { row: usize = 0, col: usize = 0 } = .{},
    click_count: usize = 0,

    pub fn handleEvent(self: *InputDemo, event: ttyz.Event) bool {
        switch (event) {
            .key => |key| {
                self.last_key = key;
                switch (key) {
                    .q, .Q, .esc => return false,
                    else => {},
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

    pub fn render(self: *InputDemo, screen: *ttyz.Screen) !void {
        try screen.print(ansi.bold ++ "Event Handling Demo" ++ ansi.reset ++ "\r\n\r\n", .{});

        // Show last key
        try screen.print("Last key: ", .{});
        if (self.last_key) |key| {
            const key_val = @intFromEnum(key);
            if (key_val >= 32 and key_val < 127) {
                try screen.print(ansi.fg.cyan ++ "'{c}'" ++ ansi.reset ++ " ({})\r\n", .{ @as(u8, @intCast(key_val)), key_val });
            } else {
                try screen.print(ansi.fg.cyan ++ "{s}" ++ ansi.reset ++ " ({})\r\n", .{ @tagName(key), key_val });
            }
        } else {
            try screen.print(ansi.faint ++ "(none)" ++ ansi.reset ++ "\r\n", .{});
        }

        // Show mouse position
        try screen.print("Mouse: " ++ ansi.fg.green ++ "row={}, col={}" ++ ansi.reset ++ "\r\n", .{ self.mouse_pos.row, self.mouse_pos.col });
        try screen.print("Clicks: " ++ ansi.fg.yellow ++ "{}" ++ ansi.reset ++ "\r\n\r\n", .{self.click_count});

        try screen.print(ansi.faint ++ "Press 'q' or ESC to quit" ++ ansi.reset ++ "\r\n", .{});
    }
};

pub fn main(init: std.process.Init) !void {
    var app = InputDemo{};
    try ttyz.Runner(InputDemo).runWithOptions(&app, init, .{ .fps = 60 });
}
