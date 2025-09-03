const std = @import("std");
const ttyz = @import("ttyz");
const E = ttyz.E;

pub fn main() !void {
    var s = try ttyz.Screen.init();
    defer _ = s.deinit() catch |e| {
        std.log.err("Error deinitializing raw mode: {s}", .{@errorName(e)});
    };
    try s.start();
    var last_event: ?ttyz.Event = null;
    while (s.running) {
        try s.writeAll(E.CLEAR_SCREEN);
        try s.writeAll(E.HOME);
        try s.writeAll("Hello, world!\n");
        try s.print("{?}\n", .{last_event});
        try s.query();
        while (s.pollEvent()) |event| {
            switch (event) {
                .key => |key| {
                    last_event = event;
                    switch (key) {
                        .q, .Q => s.running = false,
                        else => {},
                    }
                },
                .cursor_pos => |cursor_pos| {
                    try s.print("{}\n", .{cursor_pos});
                },
            }
        }
        try s.flush();
        std.Thread.sleep(std.time.ns_per_s / 16);
    }
}
