const std = @import("std");
const ttyz = @import("ttyz");
const builtin = std.builtin;
const termdraw = ttyz.termdraw;
const E = ttyz.E;
const layout = ttyz.layout;
const Element = layout.Element;

var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
var arena = std.heap.ArenaAllocator.init(gpa.allocator());
const allocator = arena.allocator();

const Root = struct {
    pub const props = layout.NodeProps{ .id = 1, .layout_direction = .left_right, .sizing = .As(.fit, .fit), .padding = .From(1, 3, 1, 3) };
    pub fn render(ctx: *layout.Context) void {
        Element.from(Section).render(ctx);
        Element.from(Section2).render(ctx);
    }
    const Section = struct {
        pub const props = layout.NodeProps{ .id = 2, .sizing = .As(.Fixed(20), .Fixed(3)), .background_color = .{ 43, 255, 51, 255 } };
        pub fn render(ctx: *layout.Context) void {
            ctx.Text("Section1");
        }
    };
    const Section2 = struct {
        pub const props = layout.NodeProps{ .id = 3, .sizing = .As(.Fixed(10), .Fixed(6)), .background_color = .{ 43, 255, 51, 255 } };
        pub fn render(ctx: *layout.Context) void {
            ctx.Text("Section2");
        }
    };
};

pub fn main() !void {
    defer _ = gpa.deinit();
    defer arena.deinit();

    // TODO: comptime generate a parser for args
    const args = try parseArgs();

    const cwd = try std.process.getCwdAlloc(allocator);
    defer allocator.free(cwd);

    if (args.debug) {
        try enableLogging();
    }

    const tty = try std.fs.openFileAbsolute("/dev/tty", .{ .mode = .read_write });
    var w = tty.writer(&.{});

    const path = try std.fs.path.join(allocator, &.{ cwd, "testdata/mushroom.png" });
    defer allocator.free(path);
    var image = ttyz.kitty.Image.with(.{ .a = 'T', .t = 'f', .f = 100 }, path);
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
    var clr = ttyz.colorz.wrap(&s.writer.interface);

    while (s.running) {
        const renderCommands = try L.render(Root);
        defer allocator.free(renderCommands);

        try s.clearScreen();
        try s.home();
        for (renderCommands) |command| {
            const ui = command.node.ui;
            switch (command.node.tag) {
                .text => {
                    try s.print(E.GOTO ++ "{s}\n", .{ ui.y, ui.x, command.node.text.? });
                },
                .box => {
                    try termdraw.box(
                        &s.writer.interface,
                        .{ .x = ui.x, .y = ui.y, .width = ui.width, .height = ui.height, .background_color = command.node.style.background_color },
                    );
                    try clr.print(E.GOTO ++ "@[.green]({},{})({},{})@[.reset]", .{ ui.y, ui.x, ui.y, ui.x, ui.width, ui.height });
                },
            }
        }

        while (s.pollEvent()) |event| {
            std.log.info("event: {}", .{event});
            switch (event) {
                .key => |key| {
                    last_event = event;
                    switch (key) {
                        .q, .Q => s.running = false,
                        else => {},
                    }
                },
                .cursor_pos => |cursor_pos| {
                    _ = cursor_pos;
                    // try s.print("{}\n", .{cursor_pos});
                },
                .mouse => |mouse| {
                    _ = mouse;
                    // try s.print("{}\n", .{mouse});
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

pub const std_options: std.Options = .{
    .log_level = .debug,
    .logFn = logHandlerFn,
};

/// Arguments
/// debug: bool,
/// log_path: []const u8,
const Args = struct {
    debug: bool,
    log_path: []const u8,
    pub const default = Args{ .debug = false, .log_path = "/tmp/ttyz.log" };
};

fn parseArgs() !Args {
    var args = std.process.args();
    _ = args.skip();
    var parsed_args: Args = .default;
    if (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--debug") or std.mem.eql(u8, arg, "-d")) {
            parsed_args.debug = true;
            parsed_args.log_path = args.next() orelse Args.default.log_path;
        }
    }
    return parsed_args;
}

/// Panic handler
/// Closes the log file and calls the library panic handler
pub const panic = std.debug.FullPanic(panicCloseLogHandle);
pub fn panicCloseLogHandle(msg: []const u8, ra: ?usize) noreturn {
    ttyz.panicTty(msg, ra);
    disableLogging();
}

/// Converts a log level to a text string
fn asText(comptime self: std.log.Level) []const u8 {
    return switch (self) {
        .err => "\x1b[31mERR\x1b[0m",
        .warn => "\x1b[33mWARN\x1b[0m",
        .info => "\x1b[32mINFO\x1b[0m",
        .debug => "\x1b[36mDEBUG\x1b[0m",
    };
}

var debug = false;

/// copy of std.log.defaultLog
fn logHandlerFn(
    comptime level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    if (!debug) return;
    const level_txt = comptime asText(level);
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    var buffer: [64]u8 = undefined;
    const stderr = std.debug.lockStderrWriter(&buffer);
    defer std.debug.unlockStderrWriter();
    nosuspend stderr.print(level_txt ++ prefix2 ++ format ++ "\n", args) catch return;
}

fn enableLogging() !void {
    debug = true;
}

fn disableLogging() void {
    debug = false;
}
