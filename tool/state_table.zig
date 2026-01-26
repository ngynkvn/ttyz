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
};

const Entry = struct {
    start: u8,
    end: u8,
    transition: Transition,
};

const StateDefn = struct {
    state: State,
    on_entry: Action = .none,
    on_exit: Action = .none,
    entries: []const Entry,
};

fn t(a: Action, s: State) Transition {
    return .{ .action = a, .state = s };
}

fn act(a: Action) Transition {
    return .{ .action = a, .state = null };
}

fn goto(s: State) Transition {
    return .{ .action = .none, .state = s };
}

// Anywhere transitions (apply to all states)
const anywhere_entries = [_]Entry{
    .{ .start = 0x18, .end = 0x18, .transition = t(.execute, .ground) },
    .{ .start = 0x1a, .end = 0x1a, .transition = t(.execute, .ground) },
    .{ .start = 0x80, .end = 0x8f, .transition = t(.execute, .ground) },
    .{ .start = 0x91, .end = 0x97, .transition = t(.execute, .ground) },
    .{ .start = 0x99, .end = 0x99, .transition = t(.execute, .ground) },
    .{ .start = 0x9a, .end = 0x9a, .transition = t(.execute, .ground) },
    .{ .start = 0x9c, .end = 0x9c, .transition = goto(.ground) },
    .{ .start = 0x1b, .end = 0x1b, .transition = goto(.escape) },
    .{ .start = 0x98, .end = 0x98, .transition = goto(.sos_pm_apc_string) },
    .{ .start = 0x9e, .end = 0x9e, .transition = goto(.sos_pm_apc_string) },
    .{ .start = 0x9f, .end = 0x9f, .transition = goto(.sos_pm_apc_string) },
    .{ .start = 0x90, .end = 0x90, .transition = goto(.dcs_entry) },
    .{ .start = 0x9d, .end = 0x9d, .transition = goto(.osc_string) },
    .{ .start = 0x9b, .end = 0x9b, .transition = goto(.csi_entry) },
};

const state_definitions = [_]StateDefn{
    .{
        .state = .ground,
        .entries = &.{
            .{ .start = 0x00, .end = 0x17, .transition = act(.execute) },
            .{ .start = 0x19, .end = 0x19, .transition = act(.execute) },
            .{ .start = 0x1c, .end = 0x1f, .transition = act(.execute) },
            .{ .start = 0x20, .end = 0x7f, .transition = act(.print) },
        },
    },
    .{
        .state = .escape,
        .on_entry = .clear,
        .entries = &.{
            .{ .start = 0x00, .end = 0x17, .transition = act(.execute) },
            .{ .start = 0x19, .end = 0x19, .transition = act(.execute) },
            .{ .start = 0x1c, .end = 0x1f, .transition = act(.execute) },
            .{ .start = 0x7f, .end = 0x7f, .transition = act(.ignore) },
            .{ .start = 0x20, .end = 0x2f, .transition = t(.collect, .escape_intermediate) },
            .{ .start = 0x30, .end = 0x4f, .transition = t(.esc_dispatch, .ground) },
            .{ .start = 0x51, .end = 0x57, .transition = t(.esc_dispatch, .ground) },
            .{ .start = 0x59, .end = 0x59, .transition = t(.esc_dispatch, .ground) },
            .{ .start = 0x5a, .end = 0x5a, .transition = t(.esc_dispatch, .ground) },
            .{ .start = 0x5c, .end = 0x5c, .transition = t(.esc_dispatch, .ground) },
            .{ .start = 0x60, .end = 0x7e, .transition = t(.esc_dispatch, .ground) },
            .{ .start = 0x5b, .end = 0x5b, .transition = goto(.csi_entry) },
            .{ .start = 0x5d, .end = 0x5d, .transition = goto(.osc_string) },
            .{ .start = 0x50, .end = 0x50, .transition = goto(.dcs_entry) },
            .{ .start = 0x58, .end = 0x58, .transition = goto(.sos_pm_apc_string) },
            .{ .start = 0x5e, .end = 0x5e, .transition = goto(.sos_pm_apc_string) },
            .{ .start = 0x5f, .end = 0x5f, .transition = goto(.sos_pm_apc_string) },
        },
    },
    .{
        .state = .escape_intermediate,
        .entries = &.{
            .{ .start = 0x00, .end = 0x17, .transition = act(.execute) },
            .{ .start = 0x19, .end = 0x19, .transition = act(.execute) },
            .{ .start = 0x1c, .end = 0x1f, .transition = act(.execute) },
            .{ .start = 0x20, .end = 0x2f, .transition = act(.collect) },
            .{ .start = 0x7f, .end = 0x7f, .transition = act(.ignore) },
            .{ .start = 0x30, .end = 0x7e, .transition = t(.esc_dispatch, .ground) },
        },
    },
    .{
        .state = .csi_entry,
        .on_entry = .clear,
        .entries = &.{
            .{ .start = 0x00, .end = 0x17, .transition = act(.execute) },
            .{ .start = 0x19, .end = 0x19, .transition = act(.execute) },
            .{ .start = 0x1c, .end = 0x1f, .transition = act(.execute) },
            .{ .start = 0x7f, .end = 0x7f, .transition = act(.ignore) },
            .{ .start = 0x20, .end = 0x2f, .transition = t(.collect, .csi_intermediate) },
            .{ .start = 0x3a, .end = 0x3a, .transition = goto(.csi_ignore) },
            .{ .start = 0x30, .end = 0x39, .transition = t(.param, .csi_param) },
            .{ .start = 0x3b, .end = 0x3b, .transition = t(.param, .csi_param) },
            .{ .start = 0x3c, .end = 0x3f, .transition = t(.collect, .csi_param) },
            .{ .start = 0x40, .end = 0x7e, .transition = t(.csi_dispatch, .ground) },
        },
    },
    .{
        .state = .csi_ignore,
        .entries = &.{
            .{ .start = 0x00, .end = 0x17, .transition = act(.execute) },
            .{ .start = 0x19, .end = 0x19, .transition = act(.execute) },
            .{ .start = 0x1c, .end = 0x1f, .transition = act(.execute) },
            .{ .start = 0x20, .end = 0x3f, .transition = act(.ignore) },
            .{ .start = 0x7f, .end = 0x7f, .transition = act(.ignore) },
            .{ .start = 0x40, .end = 0x7e, .transition = goto(.ground) },
        },
    },
    .{
        .state = .csi_param,
        .entries = &.{
            .{ .start = 0x00, .end = 0x17, .transition = act(.execute) },
            .{ .start = 0x19, .end = 0x19, .transition = act(.execute) },
            .{ .start = 0x1c, .end = 0x1f, .transition = act(.execute) },
            .{ .start = 0x30, .end = 0x39, .transition = act(.param) },
            .{ .start = 0x3b, .end = 0x3b, .transition = act(.param) },
            .{ .start = 0x7f, .end = 0x7f, .transition = act(.ignore) },
            .{ .start = 0x3a, .end = 0x3a, .transition = goto(.csi_ignore) },
            .{ .start = 0x3c, .end = 0x3f, .transition = goto(.csi_ignore) },
            .{ .start = 0x20, .end = 0x2f, .transition = t(.collect, .csi_intermediate) },
            .{ .start = 0x40, .end = 0x7e, .transition = t(.csi_dispatch, .ground) },
        },
    },
    .{
        .state = .csi_intermediate,
        .entries = &.{
            .{ .start = 0x00, .end = 0x17, .transition = act(.execute) },
            .{ .start = 0x19, .end = 0x19, .transition = act(.execute) },
            .{ .start = 0x1c, .end = 0x1f, .transition = act(.execute) },
            .{ .start = 0x20, .end = 0x2f, .transition = act(.collect) },
            .{ .start = 0x7f, .end = 0x7f, .transition = act(.ignore) },
            .{ .start = 0x30, .end = 0x3f, .transition = goto(.csi_ignore) },
            .{ .start = 0x40, .end = 0x7e, .transition = t(.csi_dispatch, .ground) },
        },
    },
    .{
        .state = .dcs_entry,
        .on_entry = .clear,
        .entries = &.{
            .{ .start = 0x00, .end = 0x17, .transition = act(.ignore) },
            .{ .start = 0x19, .end = 0x19, .transition = act(.ignore) },
            .{ .start = 0x1c, .end = 0x1f, .transition = act(.ignore) },
            .{ .start = 0x7f, .end = 0x7f, .transition = act(.ignore) },
            .{ .start = 0x3a, .end = 0x3a, .transition = goto(.dcs_ignore) },
            .{ .start = 0x20, .end = 0x2f, .transition = t(.collect, .dcs_intermediate) },
            .{ .start = 0x30, .end = 0x39, .transition = t(.param, .dcs_param) },
            .{ .start = 0x3b, .end = 0x3b, .transition = t(.param, .dcs_param) },
            .{ .start = 0x3c, .end = 0x3f, .transition = t(.collect, .dcs_param) },
            .{ .start = 0x40, .end = 0x7e, .transition = goto(.dcs_passthrough) },
        },
    },
    .{
        .state = .dcs_intermediate,
        .entries = &.{
            .{ .start = 0x00, .end = 0x17, .transition = act(.ignore) },
            .{ .start = 0x19, .end = 0x19, .transition = act(.ignore) },
            .{ .start = 0x1c, .end = 0x1f, .transition = act(.ignore) },
            .{ .start = 0x20, .end = 0x2f, .transition = act(.collect) },
            .{ .start = 0x7f, .end = 0x7f, .transition = act(.ignore) },
            .{ .start = 0x30, .end = 0x3f, .transition = goto(.dcs_ignore) },
            .{ .start = 0x40, .end = 0x7e, .transition = goto(.dcs_passthrough) },
        },
    },
    .{
        .state = .dcs_ignore,
        .entries = &.{
            .{ .start = 0x00, .end = 0x17, .transition = act(.ignore) },
            .{ .start = 0x19, .end = 0x19, .transition = act(.ignore) },
            .{ .start = 0x1c, .end = 0x1f, .transition = act(.ignore) },
            .{ .start = 0x20, .end = 0x7f, .transition = act(.ignore) },
        },
    },
    .{
        .state = .dcs_param,
        .entries = &.{
            .{ .start = 0x00, .end = 0x17, .transition = act(.ignore) },
            .{ .start = 0x19, .end = 0x19, .transition = act(.ignore) },
            .{ .start = 0x1c, .end = 0x1f, .transition = act(.ignore) },
            .{ .start = 0x30, .end = 0x39, .transition = act(.param) },
            .{ .start = 0x3b, .end = 0x3b, .transition = act(.param) },
            .{ .start = 0x7f, .end = 0x7f, .transition = act(.ignore) },
            .{ .start = 0x3a, .end = 0x3a, .transition = goto(.dcs_ignore) },
            .{ .start = 0x3c, .end = 0x3f, .transition = goto(.dcs_ignore) },
            .{ .start = 0x20, .end = 0x2f, .transition = t(.collect, .dcs_intermediate) },
            .{ .start = 0x40, .end = 0x7e, .transition = goto(.dcs_passthrough) },
        },
    },
    .{
        .state = .dcs_passthrough,
        .on_entry = .hook,
        .on_exit = .unhook,
        .entries = &.{
            .{ .start = 0x00, .end = 0x17, .transition = act(.put) },
            .{ .start = 0x19, .end = 0x19, .transition = act(.put) },
            .{ .start = 0x1c, .end = 0x1f, .transition = act(.put) },
            .{ .start = 0x20, .end = 0x7e, .transition = act(.put) },
            .{ .start = 0x7f, .end = 0x7f, .transition = act(.ignore) },
        },
    },
    .{
        .state = .sos_pm_apc_string,
        .entries = &.{
            .{ .start = 0x00, .end = 0x17, .transition = act(.ignore) },
            .{ .start = 0x19, .end = 0x19, .transition = act(.ignore) },
            .{ .start = 0x1c, .end = 0x1f, .transition = act(.ignore) },
            .{ .start = 0x20, .end = 0x7f, .transition = act(.ignore) },
        },
    },
    .{
        .state = .osc_string,
        .on_entry = .osc_start,
        .on_exit = .osc_end,
        .entries = &.{
            .{ .start = 0x00, .end = 0x17, .transition = act(.ignore) },
            .{ .start = 0x19, .end = 0x19, .transition = act(.ignore) },
            .{ .start = 0x1c, .end = 0x1f, .transition = act(.ignore) },
            .{ .start = 0x20, .end = 0x7f, .transition = act(.osc_put) },
        },
    },
};

const state_count = std.meta.fields(State).len;

fn buildTable() [state_count][256]Transition {
    @setEvalBranchQuota(10000);
    var result: [state_count][256]Transition = undefined;

    // Initialize all to none
    for (0..state_count) |s| {
        for (0..256) |b| {
            result[s][b] = .{};
        }
    }

    // Apply anywhere transitions to all states
    for (0..state_count) |s| {
        for (anywhere_entries) |entry| {
            for (entry.start..entry.end + 1) |b| {
                result[s][b] = entry.transition;
            }
        }
    }

    // Apply state-specific transitions
    for (state_definitions) |def| {
        const s = @intFromEnum(def.state);
        for (def.entries) |entry| {
            for (entry.start..entry.end + 1) |b| {
                result[s][b] = entry.transition;
            }
        }
    }

    return result;
}

fn buildOnEntry() [state_count]Action {
    var result: [state_count]Action = @splat(.none);
    for (state_definitions) |def| {
        result[@intFromEnum(def.state)] = def.on_entry;
    }
    return result;
}

fn buildOnExit() [state_count]Action {
    var result: [state_count]Action = @splat(.none);
    for (state_definitions) |def| {
        result[@intFromEnum(def.state)] = def.on_exit;
    }
    return result;
}

/// State transition table: table[state][byte] -> Transition
pub const table: [state_count][256]Transition = buildTable();

/// Actions to perform when entering a state
pub const on_entry: [state_count]Action = buildOnEntry();

/// Actions to perform when exiting a state
pub const on_exit: [state_count]Action = buildOnExit();

// ============================================================================
// Tests
// ============================================================================

test "ESC transitions from ground to escape" {
    try std.testing.expectEqual(State.escape, table[@intFromEnum(State.ground)][0x1b].state);
}

test "ground state prints printable chars" {
    const ground = @intFromEnum(State.ground);
    try std.testing.expectEqual(Action.print, table[ground]['A'].action);
    try std.testing.expectEqual(Action.print, table[ground][' '].action);
    try std.testing.expectEqual(Action.print, table[ground]['~'].action);
}

test "csi_entry transitions to csi_param on digit" {
    const csi_entry = @intFromEnum(State.csi_entry);
    try std.testing.expectEqual(Action.param, table[csi_entry]['5'].action);
    try std.testing.expectEqual(State.csi_param, table[csi_entry]['5'].state);
}

test "on_entry actions" {
    try std.testing.expectEqual(Action.clear, on_entry[@intFromEnum(State.escape)]);
    try std.testing.expectEqual(Action.clear, on_entry[@intFromEnum(State.csi_entry)]);
    try std.testing.expectEqual(Action.hook, on_entry[@intFromEnum(State.dcs_passthrough)]);
    try std.testing.expectEqual(Action.osc_start, on_entry[@intFromEnum(State.osc_string)]);
}

test "on_exit actions" {
    try std.testing.expectEqual(Action.unhook, on_exit[@intFromEnum(State.dcs_passthrough)]);
    try std.testing.expectEqual(Action.osc_end, on_exit[@intFromEnum(State.osc_string)]);
}

test "CSI sequence parsing" {
    // ESC [ 1 ; 2 H should parse cursor position
    const ground = @intFromEnum(State.ground);
    const escape = @intFromEnum(State.escape);
    const csi_entry = @intFromEnum(State.csi_entry);
    const csi_param = @intFromEnum(State.csi_param);

    // ESC from ground -> escape
    try std.testing.expectEqual(State.escape, table[ground][0x1b].state);
    // '[' from escape -> csi_entry
    try std.testing.expectEqual(State.csi_entry, table[escape]['['].state);
    // '1' from csi_entry -> csi_param with param action
    try std.testing.expectEqual(Action.param, table[csi_entry]['1'].action);
    try std.testing.expectEqual(State.csi_param, table[csi_entry]['1'].state);
    // ';' in csi_param stays with param action
    try std.testing.expectEqual(Action.param, table[csi_param][';'].action);
    try std.testing.expectEqual(null, table[csi_param][';'].state);
    // 'H' dispatches and goes to ground
    try std.testing.expectEqual(Action.csi_dispatch, table[csi_param]['H'].action);
    try std.testing.expectEqual(State.ground, table[csi_param]['H'].state);
}
