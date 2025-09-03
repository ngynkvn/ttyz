const std = @import("std");
const ttyz = @import("ttyz");
const termdraw = ttyz.termdraw;
const E = ttyz.E;

pub fn main() !void {
    // const tty = std.fs.File.stdout();
    const tty = try std.fs.openFileAbsolute("/dev/tty", .{ .mode = .read_write });
    // const ws = try ttyz.queryHandleSize(tty.handle);
    var w = tty.writer(&.{});

    var image = ttyz.kitty.Image.default;
    image.params.a = 'T';
    image.params.t = 'f';
    image.params.f = 100;
    image.filePath("testdata/mushroom.png");
    var w = tty.writer(&.{});
    image.filePath("/Users/ngynkvn/dev/zig/ttyz/testdata/mushroom.png");
    var w = tty.writer(&.{});
    try image.write(&w.interface);

    var canvas = try ttyz.draw.Canvas.initAlloc(std.heap.page_allocator, 200, 200);
    try canvas.drawBox(0, 0, 150, 150, 0xFFFFFFFF);
    try canvas.writeKitty(&w.interface);

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
                "Hello, world!\n\r" ++
                "Size: {}x{}\n\r" ++
                "{?}\n\r",
            .{ s.width, s.height, last_event },
        );
        try s.queryPos();
        try termdraw.TermDraw.box(&s.writer.interface, .{ .x = 5, .y = 10, .width = 10, .height = 10 });
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
