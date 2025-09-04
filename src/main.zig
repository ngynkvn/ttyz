const std = @import("std");
const ttyz = @import("ttyz");
const termdraw = ttyz.termdraw;
const E = ttyz.E;
const layout = ttyz.layout;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();
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

    var canvas = try ttyz.draw.Canvas.initAlloc(allocator, 200, 200);
    defer canvas.deinit(allocator);
    try canvas.drawBox(0, 0, 150, 150, 0xFFFFFFFF);
    try canvas.writeKitty(&w.interface);

    var s = try ttyz.Screen.init();
    defer _ = s.deinit() catch |e| {
        std.log.err("Error deinitializing raw mode: {s}", .{@errorName(e)});
    };
    try s.start();
    var last_event: ?ttyz.Event = null;
    var L = layout.Context.init(allocator, &s);
    defer L.deinit();

    while (s.running) {
        _ = L.begin();

        L.OpenElement(.{
            .id = 1,
            .layoutDirection = .left_to_right,
            .sizing = .As(.fit, .fit),
            .padding = .All(1),
        });
        {
            L.OpenElement(.{
                .id = 2,
                .sizing = .As(.Fixed(20), .Fixed(5)),
                .backgroundColor = .{ 43, 255, 51, 255 },
            });
            // L.Text("Hello, world2");
            L.CloseElement();

            L.OpenElement(.{
                .id = 3,
                .sizing = .As(.Fixed(20), .Fixed(10)),
                .backgroundColor = .{ 43, 255, 51, 255 },
            });
            // L.Text("Hello, world3");
            L.CloseElement();
        }
        L.CloseElement();

        try s.clearScreen();
        try s.home();
        const renderCommands = try L.end();
        defer allocator.free(renderCommands);

        for (1.., renderCommands) |i, command| {
            _ = i;
            const ui = command.node.ui;
            switch (command.node.tag) {
                .text => {
                    try s.print(E.GOTO ++ "{s}\n", .{ ui.y, ui.x, command.data });
                },
                .box => {
                    try termdraw.TermDraw.box(
                        &s.writer.interface,
                        .{ .x = ui.x, .y = ui.y, .width = ui.width, .height = ui.height },
                    );
                    try s.writer.interface.writeAll("\x1b[0m");
                },
            }
        }

        // try termdraw.TermDraw.box(&s.writer.interface, .{ .x = 5, .y = 10, .width = 10, .height = 10 });
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
