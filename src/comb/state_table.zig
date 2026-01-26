const std = @import("std");

pub const State = enum {
    ground,
    escape,
    escape_intermediate,
    csi_entry,
    csi_ignore,
    csi_param,
    csi_intermediate,
    dcs_entry,
    dcs_intermediate,
    dcs_ignore,
    dcs_param,
    dcs_passthrough,
    sos_pm_apc_string,
    osc_string,
};

pub const Action = enum {
    none,
    ignore,
    print,
    execute,
    clear,
    collect,
    param,
    esc_dispatch,
    csi_dispatch,
    hook,
    put,
    unhook,
    osc_start,
    osc_put,
    osc_end,
};

pub const Transition = struct {
    action: Action = .none,
    state: ?State = null,

    pub fn format(self: Transition, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print(".{{ .action = .{s}", .{@tagName(self.action)});
        if (self.state) |s| {
            try writer.print(", .state = .{s}", .{@tagName(s)});
        }
        try writer.writeAll(" }");
    }
};

fn t(a: Action, s: ?State) Transition {
    return .{ .action = a, .state = s };
}

fn action(a: Action) Transition {
    return .{ .action = a, .state = null };
}

fn state(s: State) Transition {
    return .{ .action = .none, .state = s };
}

const Entry = struct {
    start: u8,
    end: u8,
    transition: Transition,
};

const StateEntry = struct {
    state: State,
    on_entry: Action = .none,
    on_exit: Action = .none,
    entries: []const Entry,
};

// Anywhere transitions (apply to all states)
const anywhere_entries = [_]Entry{
    .{ .start = 0x18, .end = 0x18, .transition = t(.execute, .ground) },
    .{ .start = 0x1a, .end = 0x1a, .transition = t(.execute, .ground) },
    .{ .start = 0x80, .end = 0x8f, .transition = t(.execute, .ground) },
    .{ .start = 0x91, .end = 0x97, .transition = t(.execute, .ground) },
    .{ .start = 0x99, .end = 0x99, .transition = t(.execute, .ground) },
    .{ .start = 0x9a, .end = 0x9a, .transition = t(.execute, .ground) },
    .{ .start = 0x9c, .end = 0x9c, .transition = state(.ground) },
    .{ .start = 0x1b, .end = 0x1b, .transition = state(.escape) },
    .{ .start = 0x98, .end = 0x98, .transition = state(.sos_pm_apc_string) },
    .{ .start = 0x9e, .end = 0x9e, .transition = state(.sos_pm_apc_string) },
    .{ .start = 0x9f, .end = 0x9f, .transition = state(.sos_pm_apc_string) },
    .{ .start = 0x90, .end = 0x90, .transition = state(.dcs_entry) },
    .{ .start = 0x9d, .end = 0x9d, .transition = state(.osc_string) },
    .{ .start = 0x9b, .end = 0x9b, .transition = state(.csi_entry) },
};

const state_definitions = [_]StateEntry{
    .{
        .state = .ground,
        .entries = &[_]Entry{
            .{ .start = 0x00, .end = 0x17, .transition = action(.execute) },
            .{ .start = 0x19, .end = 0x19, .transition = action(.execute) },
            .{ .start = 0x1c, .end = 0x1f, .transition = action(.execute) },
            .{ .start = 0x20, .end = 0x7f, .transition = action(.print) },
        },
    },
    .{
        .state = .escape,
        .on_entry = .clear,
        .entries = &[_]Entry{
            .{ .start = 0x00, .end = 0x17, .transition = action(.execute) },
            .{ .start = 0x19, .end = 0x19, .transition = action(.execute) },
            .{ .start = 0x1c, .end = 0x1f, .transition = action(.execute) },
            .{ .start = 0x7f, .end = 0x7f, .transition = action(.ignore) },
            .{ .start = 0x20, .end = 0x2f, .transition = t(.collect, .escape_intermediate) },
            .{ .start = 0x30, .end = 0x4f, .transition = t(.esc_dispatch, .ground) },
            .{ .start = 0x51, .end = 0x57, .transition = t(.esc_dispatch, .ground) },
            .{ .start = 0x59, .end = 0x59, .transition = t(.esc_dispatch, .ground) },
            .{ .start = 0x5a, .end = 0x5a, .transition = t(.esc_dispatch, .ground) },
            .{ .start = 0x5c, .end = 0x5c, .transition = t(.esc_dispatch, .ground) },
            .{ .start = 0x60, .end = 0x7e, .transition = t(.esc_dispatch, .ground) },
            .{ .start = 0x5b, .end = 0x5b, .transition = state(.csi_entry) },
            .{ .start = 0x5d, .end = 0x5d, .transition = state(.osc_string) },
            .{ .start = 0x50, .end = 0x50, .transition = state(.dcs_entry) },
            .{ .start = 0x58, .end = 0x58, .transition = state(.sos_pm_apc_string) },
            .{ .start = 0x5e, .end = 0x5e, .transition = state(.sos_pm_apc_string) },
            .{ .start = 0x5f, .end = 0x5f, .transition = state(.sos_pm_apc_string) },
        },
    },
    .{
        .state = .escape_intermediate,
        .entries = &[_]Entry{
            .{ .start = 0x00, .end = 0x17, .transition = action(.execute) },
            .{ .start = 0x19, .end = 0x19, .transition = action(.execute) },
            .{ .start = 0x1c, .end = 0x1f, .transition = action(.execute) },
            .{ .start = 0x20, .end = 0x2f, .transition = action(.collect) },
            .{ .start = 0x7f, .end = 0x7f, .transition = action(.ignore) },
            .{ .start = 0x30, .end = 0x7e, .transition = t(.esc_dispatch, .ground) },
        },
    },
    .{
        .state = .csi_entry,
        .on_entry = .clear,
        .entries = &[_]Entry{
            .{ .start = 0x00, .end = 0x17, .transition = action(.execute) },
            .{ .start = 0x19, .end = 0x19, .transition = action(.execute) },
            .{ .start = 0x1c, .end = 0x1f, .transition = action(.execute) },
            .{ .start = 0x7f, .end = 0x7f, .transition = action(.ignore) },
            .{ .start = 0x20, .end = 0x2f, .transition = t(.collect, .csi_intermediate) },
            .{ .start = 0x3a, .end = 0x3a, .transition = state(.csi_ignore) },
            .{ .start = 0x30, .end = 0x39, .transition = t(.param, .csi_param) },
            .{ .start = 0x3b, .end = 0x3b, .transition = t(.param, .csi_param) },
            .{ .start = 0x3c, .end = 0x3f, .transition = t(.collect, .csi_param) },
            .{ .start = 0x40, .end = 0x7e, .transition = t(.csi_dispatch, .ground) },
        },
    },
    .{
        .state = .csi_ignore,
        .entries = &[_]Entry{
            .{ .start = 0x00, .end = 0x17, .transition = action(.execute) },
            .{ .start = 0x19, .end = 0x19, .transition = action(.execute) },
            .{ .start = 0x1c, .end = 0x1f, .transition = action(.execute) },
            .{ .start = 0x20, .end = 0x3f, .transition = action(.ignore) },
            .{ .start = 0x7f, .end = 0x7f, .transition = action(.ignore) },
            .{ .start = 0x40, .end = 0x7e, .transition = state(.ground) },
        },
    },
    .{
        .state = .csi_param,
        .entries = &[_]Entry{
            .{ .start = 0x00, .end = 0x17, .transition = action(.execute) },
            .{ .start = 0x19, .end = 0x19, .transition = action(.execute) },
            .{ .start = 0x1c, .end = 0x1f, .transition = action(.execute) },
            .{ .start = 0x30, .end = 0x39, .transition = action(.param) },
            .{ .start = 0x3b, .end = 0x3b, .transition = action(.param) },
            .{ .start = 0x7f, .end = 0x7f, .transition = action(.ignore) },
            .{ .start = 0x3a, .end = 0x3a, .transition = state(.csi_ignore) },
            .{ .start = 0x3c, .end = 0x3f, .transition = state(.csi_ignore) },
            .{ .start = 0x20, .end = 0x2f, .transition = t(.collect, .csi_intermediate) },
            .{ .start = 0x40, .end = 0x7e, .transition = t(.csi_dispatch, .ground) },
        },
    },
    .{
        .state = .csi_intermediate,
        .entries = &[_]Entry{
            .{ .start = 0x00, .end = 0x17, .transition = action(.execute) },
            .{ .start = 0x19, .end = 0x19, .transition = action(.execute) },
            .{ .start = 0x1c, .end = 0x1f, .transition = action(.execute) },
            .{ .start = 0x20, .end = 0x2f, .transition = action(.collect) },
            .{ .start = 0x7f, .end = 0x7f, .transition = action(.ignore) },
            .{ .start = 0x30, .end = 0x3f, .transition = state(.csi_ignore) },
            .{ .start = 0x40, .end = 0x7e, .transition = t(.csi_dispatch, .ground) },
        },
    },
    .{
        .state = .dcs_entry,
        .on_entry = .clear,
        .entries = &[_]Entry{
            .{ .start = 0x00, .end = 0x17, .transition = action(.ignore) },
            .{ .start = 0x19, .end = 0x19, .transition = action(.ignore) },
            .{ .start = 0x1c, .end = 0x1f, .transition = action(.ignore) },
            .{ .start = 0x7f, .end = 0x7f, .transition = action(.ignore) },
            .{ .start = 0x3a, .end = 0x3a, .transition = state(.dcs_ignore) },
            .{ .start = 0x20, .end = 0x2f, .transition = t(.collect, .dcs_intermediate) },
            .{ .start = 0x30, .end = 0x39, .transition = t(.param, .dcs_param) },
            .{ .start = 0x3b, .end = 0x3b, .transition = t(.param, .dcs_param) },
            .{ .start = 0x3c, .end = 0x3f, .transition = t(.collect, .dcs_param) },
            .{ .start = 0x40, .end = 0x7e, .transition = state(.dcs_passthrough) },
        },
    },
    .{
        .state = .dcs_intermediate,
        .entries = &[_]Entry{
            .{ .start = 0x00, .end = 0x17, .transition = action(.ignore) },
            .{ .start = 0x19, .end = 0x19, .transition = action(.ignore) },
            .{ .start = 0x1c, .end = 0x1f, .transition = action(.ignore) },
            .{ .start = 0x20, .end = 0x2f, .transition = action(.collect) },
            .{ .start = 0x7f, .end = 0x7f, .transition = action(.ignore) },
            .{ .start = 0x30, .end = 0x3f, .transition = state(.dcs_ignore) },
            .{ .start = 0x40, .end = 0x7e, .transition = state(.dcs_passthrough) },
        },
    },
    .{
        .state = .dcs_ignore,
        .entries = &[_]Entry{
            .{ .start = 0x00, .end = 0x17, .transition = action(.ignore) },
            .{ .start = 0x19, .end = 0x19, .transition = action(.ignore) },
            .{ .start = 0x1c, .end = 0x1f, .transition = action(.ignore) },
            .{ .start = 0x20, .end = 0x7f, .transition = action(.ignore) },
        },
    },
    .{
        .state = .dcs_param,
        .entries = &[_]Entry{
            .{ .start = 0x00, .end = 0x17, .transition = action(.ignore) },
            .{ .start = 0x19, .end = 0x19, .transition = action(.ignore) },
            .{ .start = 0x1c, .end = 0x1f, .transition = action(.ignore) },
            .{ .start = 0x30, .end = 0x39, .transition = action(.param) },
            .{ .start = 0x3b, .end = 0x3b, .transition = action(.param) },
            .{ .start = 0x7f, .end = 0x7f, .transition = action(.ignore) },
            .{ .start = 0x3a, .end = 0x3a, .transition = state(.dcs_ignore) },
            .{ .start = 0x3c, .end = 0x3f, .transition = state(.dcs_ignore) },
            .{ .start = 0x20, .end = 0x2f, .transition = t(.collect, .dcs_intermediate) },
            .{ .start = 0x40, .end = 0x7e, .transition = state(.dcs_passthrough) },
        },
    },
    .{
        .state = .dcs_passthrough,
        .on_entry = .hook,
        .on_exit = .unhook,
        .entries = &[_]Entry{
            .{ .start = 0x00, .end = 0x17, .transition = action(.put) },
            .{ .start = 0x19, .end = 0x19, .transition = action(.put) },
            .{ .start = 0x1c, .end = 0x1f, .transition = action(.put) },
            .{ .start = 0x20, .end = 0x7e, .transition = action(.put) },
            .{ .start = 0x7f, .end = 0x7f, .transition = action(.ignore) },
        },
    },
    .{
        .state = .sos_pm_apc_string,
        .entries = &[_]Entry{
            .{ .start = 0x00, .end = 0x17, .transition = action(.ignore) },
            .{ .start = 0x19, .end = 0x19, .transition = action(.ignore) },
            .{ .start = 0x1c, .end = 0x1f, .transition = action(.ignore) },
            .{ .start = 0x20, .end = 0x7f, .transition = action(.ignore) },
        },
    },
    .{
        .state = .osc_string,
        .on_entry = .osc_start,
        .on_exit = .osc_end,
        .entries = &[_]Entry{
            .{ .start = 0x00, .end = 0x17, .transition = action(.ignore) },
            .{ .start = 0x19, .end = 0x19, .transition = action(.ignore) },
            .{ .start = 0x1c, .end = 0x1f, .transition = action(.ignore) },
            .{ .start = 0x20, .end = 0x7f, .transition = action(.osc_put) },
        },
    },
};

/// Expanded state table: [state][byte] -> Transition
pub const StateTable = [std.meta.fields(State).len][256]Transition;

pub fn buildStateTable() StateTable {
    var table: StateTable = undefined;

    // Initialize all to none
    for (0..std.meta.fields(State).len) |s| {
        for (0..256) |b| {
            table[s][b] = .{ .action = .none, .state = null };
        }
    }

    // Apply anywhere transitions to all states
    for (0..std.meta.fields(State).len) |s| {
        for (anywhere_entries) |entry| {
            for (entry.start..entry.end + 1) |b| {
                table[s][b] = entry.transition;
            }
        }
    }

    // Apply state-specific transitions
    for (state_definitions) |def| {
        const s = @intFromEnum(def.state);
        for (def.entries) |entry| {
            for (entry.start..entry.end + 1) |b| {
                table[s][b] = entry.transition;
            }
        }
    }

    return table;
}

fn getOnEntry(s: State) Action {
    for (state_definitions) |def| {
        if (def.state == s) return def.on_entry;
    }
    return .none;
}

fn getOnExit(s: State) Action {
    for (state_definitions) |def| {
        if (def.state == s) return def.on_exit;
    }
    return .none;
}

pub fn main(init: std.process.Init) !void {
    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buf);
    const stdout = &stdout_writer.interface;
    const table = buildStateTable();

    try stdout.writeAll("const std = @import(\"std\");\n\n");

    // Print State enum
    try stdout.writeAll("pub const State = enum {\n");
    inline for (std.meta.fields(State)) |field| {
        try stdout.print("    {s},\n", .{field.name});
    }
    try stdout.writeAll("};\n\n");

    // Print Action enum
    try stdout.writeAll("pub const Action = enum {\n");
    inline for (std.meta.fields(Action)) |field| {
        try stdout.print("    {s},\n", .{field.name});
    }
    try stdout.writeAll("};\n\n");

    // Print Transition struct
    try stdout.writeAll(
        \\pub const Transition = struct {
        \\    action: Action = .none,
        \\    state: ?State = null,
        \\};
        \\
        \\
    );

    // Print on_entry table
    try stdout.writeAll("pub const on_entry = [_]Action{\n");
    inline for (std.meta.fields(State)) |field| {
        const s: State = @enumFromInt(field.value);
        try stdout.print("    .{s}, // {s}\n", .{ @tagName(getOnEntry(s)), field.name });
    }
    try stdout.writeAll("};\n\n");

    // Print on_exit table
    try stdout.writeAll("pub const on_exit = [_]Action{\n");
    inline for (std.meta.fields(State)) |field| {
        const s: State = @enumFromInt(field.value);
        try stdout.print("    .{s}, // {s}\n", .{ @tagName(getOnExit(s)), field.name });
    }
    try stdout.writeAll("};\n\n");

    // Print the state table
    try stdout.writeAll("pub const state_table = [_][256]Transition{\n");

    inline for (std.meta.fields(State)) |field| {
        const s = field.value;
        try stdout.print("    // State: {s}\n", .{field.name});
        try stdout.writeAll("    .{\n");

        var i: usize = 0;
        while (i < 256) {
            // Find runs of identical transitions
            var run_end = i + 1;
            while (run_end < 256 and
                table[s][run_end].action == table[s][i].action and
                eqlOptState(table[s][run_end].state, table[s][i].state)) : (run_end += 1)
            {}

            const trans = table[s][i];
            if (run_end - i > 4) {
                // Comment for range
                try stdout.print("        // 0x{x:0>2}..0x{x:0>2}\n", .{ i, run_end - 1 });
            }

            for (i..run_end) |_| {
                try stdout.print("        .{{ .action = .{s}", .{@tagName(trans.action)});
                if (trans.state) |next| {
                    try stdout.print(", .state = .{s}", .{@tagName(next)});
                }
                try stdout.writeAll(" },\n");
            }
            i = run_end;
        }

        try stdout.writeAll("    },\n");
    }

    try stdout.writeAll("};\n");
    try stdout.flush();
}

fn eqlOptState(a: ?State, b: ?State) bool {
    if (a == null and b == null) return true;
    if (a == null or b == null) return false;
    return a.? == b.?;
}

test "state table builds without error" {
    const table = buildStateTable();
    // Check a known transition: ESC (0x1b) from ground should go to escape
    try std.testing.expectEqual(State.escape, table[@intFromEnum(State.ground)][0x1b].state);
}

test "ground state prints printable chars" {
    const table = buildStateTable();
    const ground = @intFromEnum(State.ground);
    try std.testing.expectEqual(Action.print, table[ground]['A'].action);
    try std.testing.expectEqual(Action.print, table[ground][' '].action);
    try std.testing.expectEqual(Action.print, table[ground]['~'].action);
}

test "csi_entry transitions to csi_param on digit" {
    const table = buildStateTable();
    const csi_entry = @intFromEnum(State.csi_entry);
    try std.testing.expectEqual(Action.param, table[csi_entry]['5'].action);
    try std.testing.expectEqual(State.csi_param, table[csi_entry]['5'].state);
}
