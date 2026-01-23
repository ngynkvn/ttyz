const std = @import("std");
const ttyz = @import("ttyz");
const builtin = std.builtin;
const termdraw = ttyz.termdraw;
const E = ttyz.E;
const layout = ttyz.layout;

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

    var ctx = layout.Context.init(allocator);
    defer ctx.deinit();

    // Panel dimensions (modifiable via input)
    var left_width: u16 = 20;
    var left_height: u16 = 8;
    var right_width: u16 = 25;
    var right_height: u16 = 8;
    var active_panel: enum { left, right } = .left;

    while (s.running) {
        ctx.begin();

        // Main horizontal container
        {
            ctx.open(.{
                .direction = .horizontal,
                .padding = layout.Padding.all(1),
                .gap = 2,
            });
            defer ctx.close();

            // Left panel
            {
                ctx.open(.{
                    .width = .{ .fixed = left_width },
                    .height = .{ .fixed = left_height },
                    .border = true,
                    .color = if (active_panel == .left) .{ 50, 50, 80, 255 } else null,
                });
                defer ctx.close();
                ctx.text("Left Panel");
            }

            // Right panel
            {
                ctx.open(.{
                    .width = .{ .fixed = right_width },
                    .height = .{ .fixed = right_height },
                    .border = true,
                    .color = if (active_panel == .right) .{ 50, 80, 50, 255 } else null,
                });
                defer ctx.close();
                ctx.text("Right Panel");
            }
        }

        const commands = try ctx.end(s.width, s.height);
        defer allocator.free(commands);

        try s.clearScreen();
        try s.home();

        // Title and instructions
        try s.print(E.BOLD ++ "ttyz Layout Demo" ++ E.RESET_STYLE ++ "\r\n\r\n", .{});
        try s.print("Active: " ++ E.FG_GREEN ++ "{s}" ++ E.RESET_STYLE ++ "\r\n", .{if (active_panel == .left) "Left" else "Right"});
        try s.print("Size input: " ++ E.FG_CYAN ++ "{s}" ++ E.RESET_STYLE ++ "\r\n\r\n", .{s.textinput.items});
        try s.print(E.DIM ++ "Type WxH (e.g. 10x5) + Enter to resize active panel\r\n", .{});
        try s.print("Tab to switch panel, q to quit" ++ E.RESET_STYLE ++ "\r\n\r\n", .{});

        // Render all layout commands
        for (commands) |cmd| {
            try cmd.render(&s);
        }

        while (s.pollEvent()) |event| {
            std.log.info("event: {}", .{event});
            switch (event) {
                .key => |key| {
                    switch (key) {
                        .q, .Q => s.running = false,
                        .tab => {
                            active_panel = if (active_panel == .left) .right else .left;
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
                            switch (active_panel) {
                                .left => {
                                    left_width = new_w;
                                    left_height = new_h;
                                },
                                .right => {
                                    right_width = new_w;
                                    right_height = new_h;
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
                .cursor_pos => {},
                .mouse => {},
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
