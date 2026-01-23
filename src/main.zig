const std = @import("std");
const ttyz = @import("ttyz");
const builtin = std.builtin;
const termdraw = ttyz.termdraw;
const ansi = ttyz.ansi;
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

    var s = try ttyz.Screen.init(init.io);
    defer _ = s.deinit() catch |e| {
        std.log.err("Error deinitializing raw mode: {s}", .{@errorName(e)});
    };

    // Panel dimensions (modifiable via input)
    var left_width: u16 = 20;
    var left_height: u16 = 8;
    var right_width: u16 = 25;
    var right_height: u16 = 8;
    var active_panel: enum { left, right } = .left;

    // Cursor/mouse position tracking
    var mouse_row: usize = 0;
    var mouse_col: usize = 0;
    var mouse_button: ttyz.Event.MouseButton = .none;
    var mouse_state: ttyz.Event.MouseButtonState = .released;
    var mouse_mods: struct { shift: bool = false, meta: bool = false, ctrl: bool = false } = .{};
    var cursor_row: usize = 0;
    var cursor_col: usize = 0;

    while (s.running) {
        // Main horizontal container (top padding leaves room for instructions)

        try s.clearScreen();
        try s.home();

        // Title and instructions
        try s.print(ansi.bold ++ "ttyz Layout Demo" ++ ansi.reset ++ "\r\n\r\n", .{});
        try s.print("Active: " ++ ansi.fg.green ++ "{s}" ++ ansi.reset ++ "  ", .{if (active_panel == .left) "Left" else "Right"});
        try s.print("Cursor: " ++ ansi.fg.magenta ++ "({d}, {d})" ++ ansi.reset ++ "\r\n", .{ cursor_col, cursor_row });

        // Mouse info with SGR details
        try s.print("Mouse: " ++ ansi.fg.yellow ++ "({d}, {d})" ++ ansi.reset, .{ mouse_col, mouse_row });
        try s.print("  btn=" ++ ansi.fg.cyan ++ "{s}" ++ ansi.reset, .{@tagName(mouse_button)});
        try s.print(" {s}", .{@tagName(mouse_state)});
        if (mouse_mods.shift or mouse_mods.meta or mouse_mods.ctrl) {
            try s.print(" [", .{});
            if (mouse_mods.ctrl) try s.print("C", .{});
            if (mouse_mods.meta) try s.print("M", .{});
            if (mouse_mods.shift) try s.print("S", .{});
            try s.print("]", .{});
        }
        try s.print("\r\n", .{});

        try s.print("Size input: " ++ ansi.fg.cyan ++ "{s}" ++ ansi.reset ++ "\r\n\r\n", .{s.textinput.items});
        try s.print(ansi.faint ++ "Type WxH (e.g. 10x5) + Enter to resize active panel\r\n", .{});
        try s.print("Tab to switch panel, q to quit" ++ ansi.reset ++ "\r\n\r\n", .{});

        // Read input (non-blocking due to termios settings)
        readInput(&s);

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
                .cursor_pos => |pos| {
                    cursor_row = pos.row;
                    cursor_col = pos.col;
                },
                .mouse => |m| {
                    mouse_row = m.row;
                    mouse_col = m.col;
                    mouse_button = m.button;
                    mouse_state = m.button_state;
                    mouse_mods = .{ .shift = m.shift, .meta = m.meta, .ctrl = m.ctrl };
                },
                .focus => |focused| {
                    std.log.info("focus changed: {}", .{focused});
                },
                .resize => |r| {
                    s.width = r.width;
                    s.height = r.height;
                    std.log.info("resize: {}x{}", .{ r.width, r.height });
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

/// Read input from the TTY (non-blocking due to termios VMIN=0, VTIME=1)
fn readInput(screen: *ttyz.Screen) void {
    var input_buffer: [32]u8 = undefined;

    const rc = std.posix.system.read(screen.fd, &input_buffer, input_buffer.len);
    if (rc <= 0) return;

    const bytes_read: usize = @intCast(rc);

    // Process each byte through the parser
    for (input_buffer[0..bytes_read]) |byte| {
        const action = screen.input_parser.advance(byte);
        if (screen.actionToEvent(action, byte)) |ev| {
            screen.event_queue.pushBackBounded(ev) catch {};
        }
    }
}
