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
        try s.print(
            E.CLEAR_SCREEN ++
                E.HOME ++
                "Hello, world!\n" ++
                "Size: {}x{}\n" ++
                "{?}\n",
            .{ s.width, s.height, last_event },
        );
        try s.queryPos();
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
                .interrupt => {
                    s.running = false;
                },
            }
        }
        try s.flush();
        std.Thread.sleep(std.time.ns_per_s / 16);
    }
}

pub const panic = ttyz.panic;
