//! Event handling example
//!
//! Demonstrates keyboard and mouse event handling with the threaded I/O loop.

const std = @import("std");
const ttyz = @import("ttyz");
const ansi = ttyz.ansi;

pub fn main(init: std.process.Init) !void {
    var screen = try ttyz.Screen.init();
    defer _ = screen.deinit() catch {};

    // Start the background I/O thread for event polling
    try screen.start();

    var last_key: ?ttyz.Event.Key = null;
    var mouse_pos: struct { row: usize = 0, col: usize = 0 } = .{};
    var click_count: usize = 0;

    while (screen.running) {
        // Poll all pending events
        while (screen.pollEvent()) |event| {
            switch (event) {
                .key => |key| {
                    last_key = key;
                    switch (key) {
                        .q, .Q, .esc => screen.running = false,
                        else => {},
                    }
                },
                .mouse => |mouse| {
                    mouse_pos.row = mouse.row;
                    mouse_pos.col = mouse.col;
                    if (mouse.button_state == .pressed) {
                        click_count += 1;
                    }
                },
                .interrupt => screen.running = false,
                else => {},
            }
        }

        // Render current state
        try screen.clearScreen();
        try screen.home();

        try screen.print(ansi.bold ++ "Event Handling Demo" ++ ansi.reset ++ "\r\n\r\n", .{});

        // Show last key
        try screen.print("Last key: ", .{});
        if (last_key) |key| {
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
        try screen.print("Mouse: " ++ ansi.fg.green ++ "row={}, col={}" ++ ansi.reset ++ "\r\n", .{ mouse_pos.row, mouse_pos.col });
        try screen.print("Clicks: " ++ ansi.fg.yellow ++ "{}" ++ ansi.reset ++ "\r\n\r\n", .{click_count});

        try screen.print(ansi.faint ++ "Press 'q' or ESC to quit" ++ ansi.reset ++ "\r\n", .{});
        try screen.flush();

        init.io.sleep(std.Io.Duration.fromMilliseconds(16), .awake) catch {};
    }
}
