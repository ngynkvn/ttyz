const std = @import("std");
const ttyz = @import("ttyz");
const builtin = std.builtin;
const termdraw = ttyz.termdraw;
const E = ttyz.E;
const layout = ttyz.layout;

const Element = layout.Element;

const Root = struct {
    pub var props = layout.NodeProps{ .id = 1, .layout_direction = .left_right, .sizing = .As(.fit, .fit), .padding = .From(0, 0, 0, 0) };
    pub fn render(ctx: *layout.Context) void {
        ctx.OpenElement(Section.props);
        Section.render(ctx);
        ctx.CloseElement();
        ctx.OpenElement(Section2.props);
        Section2.render(ctx);
        ctx.CloseElement();
    }
    const Section = struct {
        pub var props = layout.NodeProps{ .id = 2, .sizing = .As(.Fixed(12), .Fixed(6)), .color = .{ 43, 255, 51, 255 } };
        pub fn render(ctx: *layout.Context) void {
            _ = ctx;
            // ctx.Text("Section1");
        }
    };
    const Section2 = struct {
        pub var props = layout.NodeProps{ .id = 3, .sizing = .As(.Fixed(6), .Fixed(8)), .color = .{ 43, 255, 51, 255 } };
        pub fn render(ctx: *layout.Context) void {
            _ = ctx;
            // ctx.Text("Section2");
        }
    };
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    // Check for debug flag in args or environment
    var enable_debug = false;
    const args = init.minimal.args.toSlice(allocator) catch &.{};
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--debug")) {
            enable_debug = true;
            break;
        }
    }
    if (init.environ_map.get("TTYZ_DEBUG") != null) {
        enable_debug = true;
    }
    if (enable_debug) {
        enableLogging();
    }

    var s = try ttyz.Screen.init();
    defer _ = s.deinit() catch |e| {
        std.log.err("Error deinitializing raw mode: {s}", .{@errorName(e)});
    };
    try s.start();

    var last_event: ?ttyz.Event = null;
    _ = &last_event;
    var L = layout.Context.init(allocator, &s);
    defer L.deinit();

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
                    // TODO: termdraw.box needs writer interface update
                    try s.print(E.GOTO ++ "\x1b[32m{s}\x1b[0m", .{ ui.y, ui.x, s.textinput.items });
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
                        .tab => {
                            s.toggle = !s.toggle;
                        },
                        .@"0", .@"1", .@"2", .@"3", .@"4", .@"5", .@"6", .@"7", .@"8", .@"9", .x => |c| {
                            s.textinput.appendBounded(@intFromEnum(c)) catch {
                                std.log.err("failed to append to textinput_buffer", .{});
                            };
                        },
                        .enter, .carriage_return => {
                            const i = std.mem.indexOfScalar(u8, s.textinput.items, 'x') orelse {
                                std.log.err("failed to find x in textinput", .{});
                                continue;
                            };
                            const inp_w = s.textinput.items[0..i];
                            const inp_h = s.textinput.items[i + 1 ..];
                            const new_w = std.fmt.parseInt(u16, inp_w, 10) catch {
                                std.log.err("failed to parse width", .{});
                                continue;
                            };
                            const new_h = std.fmt.parseInt(u16, inp_h, 10) catch {
                                std.log.err("failed to parse height", .{});
                                continue;
                            };
                            switch (s.toggle) {
                                true => {
                                    Root.Section.props.sizing = .As(.Fixed(new_w), .Fixed(new_h));
                                },
                                false => {
                                    Root.Section2.props.sizing = .As(.Fixed(new_w), .Fixed(new_h));
                                },
                            }

                            s.textinput.shrinkRetainingCapacity(0);
                        },
                        .esc => {
                            s.textinput.shrinkRetainingCapacity(0);
                        },
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
                .focus => |focused| {
                    std.log.info("focus changed: {}", .{focused});
                },
                .interrupt => s.running = false,
            }
        }
        try s.flush();
        init.io.sleep(std.Io.Duration.fromMilliseconds(10), .awake) catch {};
    }
}

pub const std_options: std.Options = .{
    .log_level = .debug,
    .logFn = logHandlerFn,
};

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
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    if (!debug) return;
    const level_txt = comptime asText(level);
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    var buffer: [1024]u8 = undefined;
    const msg = std.fmt.bufPrint(&buffer, level_txt ++ prefix2 ++ format ++ "\n", args) catch return;
    _ = std.posix.system.write(std.posix.STDERR_FILENO, msg.ptr, msg.len);
}

fn enableLogging() void {
    debug = true;
}

fn disableLogging() void {
    debug = false;
}
