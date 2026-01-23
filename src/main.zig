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

    const tty = try std.fs.openFileAbsolute("/dev/tty", .{ .mode = .read_write });
    var w = tty.writer(&.{});

    const cwd = try std.process.getCwdAlloc(allocator);
    defer allocator.free(cwd);

    const path = try std.fs.path.join(allocator, &.{ cwd, "testdata/mushroom.png" });
    defer allocator.free(path);
    var image = ttyz.kitty.Image.default;
    image.params.a = 'T';
    image.params.t = 'f';
    image.params.f = 100;
    image.filePath(path);
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

    var c = ttyz.colorz.wrap(&s.writer.interface);
    while (s.running) {
        _ = L.begin();

        L.OpenElement(.{
            .id = 1,
            .layoutDirection = .left_to_right,
            .sizing = .As(.fit, .fit),
            .padding = .From(0, 1, 0, 1),
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

        for (renderCommands) |command| {
            const ui = command.node.ui;
            switch (command.node.tag) {
                .text => {
                    try s.print(E.GOTO ++ "{s}\n", .{ ui.y, ui.x, command.data });
                },
                .box => {
                    try termdraw.box(
                        &s.writer.interface,
                        .{ .x = ui.x, .y = ui.y, .width = ui.width, .height = ui.height },
                    );
                    try c.print(E.GOTO ++ "({},{})({},{})", .{ ui.y, ui.x, ui.y, ui.x, ui.width, ui.height });
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

pub const std_options: std.Options = .{
    .log_level = .debug,
    .logFn = logHandlerFn,
};

var logHandle: ?std.fs.File = null;
fn initLogHandle() !void {}

fn deinitLogHandle() !void {
    _ = logHandle.?.close();
}
/// copy of std.log.defaultLog
fn logHandlerFn(
    comptime level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_txt = comptime asText(level);
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    var buffer: [64]u8 = undefined;
    const stderr = std.debug.lockStderrWriter(&buffer);
    defer std.debug.unlockStderrWriter();
    nosuspend stderr.print(level_txt ++ prefix2 ++ format ++ "\n", args) catch return;
}

fn asText(comptime self: std.log.Level) []const u8 {
    return switch (self) {
        .err => "\x1b[31mERR\x1b[0m",
        .warn => "\x1b[33mWARN\x1b[0m",
        .info => "\x1b[32mINFO\x1b[0m",
        .debug => "\x1b[36mDEBUG\x1b[0m",
    };
}
