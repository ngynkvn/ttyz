const std = @import("std");
const ttyz = @import("ttyz");
const E = ttyz.E;

pub fn main() !void {
    const tty = try std.fs.openFileAbsolute("/dev/tty", .{ .mode = .read_write });
    var image = ttyz.kitty.Image.default;
    image.params.a = 'T';
    image.params.t = 'f';
    image.params.f = 100;
    image.filePath("testdata/mushroom.png");
    var w = tty.writer(&.{});
    try image.write(&w.interface);
    try w.interface.flush();
    {
        return;
    }
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
        try s.print(E.ESC ++ "Gf=100,t=f,a=T;{s}" ++ E.ESC ++ "\\", .{"L1VzZXJzL25neW5rdm4vZGV2L3ppZy90dHl6L3Rlc3RkYXRhL211c2hyb29tLnBuZwo="});
        try s.flush();
        std.Thread.sleep(std.time.ns_per_s / 16);
    }
}

pub const panic = ttyz.panic;
