pub const std = @import("std");

pub const Action = @import("../parser.zig").Action;
pub const State = @import("../parser.zig").State;

/// A transition entry containing an action and next state
pub const Transition = struct {
    action: ?Action,
    state: ?State,
    _unassigned: ?void = null,
    pub const none = Transition{ .action = null, .state = null, ._unassigned = {} };
    pub fn act(self: Transition, a: Action) Transition {
        return .{ .action = a, .state = self.state };
    }
    pub fn to(self: Transition, s: State) Transition {
        return .{ .action = self.action, .state = s };
    }
};

/// Transition table type: indexed by [state][byte]
pub const TransitionTable = [State.fields.len][256]Transition;

/// Build the complete transition table at comptime
pub const table: TransitionTable = buildTable();
// comptime {
//     for (0.., table) |r, row| {
//         const state = @as(State, @enumFromInt(r));
//         for (0.., row) |c, cell| {
//             if (cell._unassigned) |_| {
//                 @compileLog(state, c, cell);
//             }
//         }
//     }
// }

fn buildTable() TransitionTable {
    @setEvalBranchQuota(100000);
    var t: TransitionTable = undefined;
    const Constructor = struct {
        fn act(a: Action) Transition {
            return Transition.none.act(a);
        }
        fn to(s: State) Transition {
            return Transition.none.to(s);
        }
    };
    const act = Constructor.act;
    const to = Constructor.to;

    // Initialize all to none/same-state
    for (&t) |*s| s.* = @splat(Transition.none);

    // === ANYWHERE transitions (apply to all states) ===
    for (0..std.meta.fields(State).len) |s| {
        // 0x18       => [:execute, transition_to(:GROUND)],
        t[s][0x18] = act(.execute).to(.ground);
        // 0x1a       => [:execute, transition_to(:GROUND)],
        t[s][0x1A] = act(.execute).to(.ground);
        // 0x80..0x8f => [:execute, transition_to(:GROUND)],
        for (0x80..0x90) |b| t[s][b] = act(.execute).to(.ground);
        // 0x91..0x97 => [:execute, transition_to(:GROUND)],
        for (0x91..0x98) |b| t[s][b] = act(.execute).to(.ground);
        // 0x99       => [:execute, transition_to(:GROUND)],
        t[s][0x99] = act(.execute).to(.ground);
        // 0x9a       => [:execute, transition_to(:GROUND)],
        t[s][0x9A] = act(.execute).to(.ground);
        // 0x9c       => transition_to(:GROUND),
        t[s][0x9C] = to(.ground);
        // 0x1b       => transition_to(:ESCAPE),
        t[s][0x1B] = act(.clear).to(.escape);
        // 0x98       => transition_to(:SOS_PM_APC_STRING),
        t[s][0x98] = to(.sos_pm_apc_string);
        // 0x9e       => transition_to(:SOS_PM_APC_STRING),
        t[s][0x9E] = to(.sos_pm_apc_string);
        // 0x9f       => transition_to(:SOS_PM_APC_STRING),
        t[s][0x9F] = to(.sos_pm_apc_string);
        // 0x90       => transition_to(:DCS_ENTRY),
        t[s][0x90] = act(.clear).to(.dcs_entry);
        // 0x9d       => transition_to(:OSC_STRING),
        t[s][0x9D] = act(.osc_start).to(.osc_string);
        // 0x9b       => transition_to(:CSI_ENTRY),
        t[s][0x9B] = act(.clear).to(.csi_entry);
    }

    // === GROUND state ===
    {
        const ground = &t[@intFromEnum(State.ground)];
        for (0x00..0x18) |b| ground[b] = act(.execute);
        ground[0x19] = act(.execute);
        for (0x1C..0x20) |b| ground[b] = act(.execute);
        for (0x20..0x80) |b| ground[b] = act(.print);
    }

    // === ESCAPE state ===
    {
        const escape = &t[@intFromEnum(State.escape)];
        // C0 controls -> execute
        for (0x00..0x18) |b| escape[b] = act(.execute).to(.escape);
        escape[0x19] = act(.execute).to(.escape);
        for (0x1C..0x20) |b| escape[b] = act(.execute).to(.escape);
        // Intermediate (0x20-0x2F) -> collect, escape_intermediate
        for (0x20..0x30) |b| escape[b] = act(.collect).to(.escape_intermediate);
        // 0x30-0x4F -> esc_dispatch (except special cases)
        for (0x30..0x50) |b| escape[b] = act(.esc_dispatch).to(.ground);
        // 'P' (0x50) -> DCS
        escape[0x50] = act(.clear).to(.dcs_entry);
        // 0x51-0x57 -> esc_dispatch
        for (0x51..0x58) |b| escape[b] = act(.esc_dispatch).to(.ground);
        // 'X' (0x58) -> SOS
        escape[0x58] = to(.sos_pm_apc_string);
        // 'Y', 'Z' -> esc_dispatch
        escape[0x59] = act(.esc_dispatch).to(.ground);
        escape[0x5A] = act(.esc_dispatch).to(.ground);
        // '[' (0x5B) -> CSI
        escape[0x5B] = act(.clear).to(.csi_entry);
        // '\' (0x5C) -> esc_dispatch (ST)
        escape[0x5C] = act(.esc_dispatch).to(.ground);
        // ']' (0x5D) -> OSC
        escape[0x5D] = act(.osc_start).to(.osc_string);
        // '^' (0x5E) -> PM
        escape[0x5E] = to(.sos_pm_apc_string);
        // '_' (0x5F) -> APC
        escape[0x5F] = to(.sos_pm_apc_string);
        // 0x60-0x7E -> esc_dispatch
        for (0x60..0x7F) |b| escape[b] = act(.esc_dispatch).to(.ground);
        // DEL (0x7F) -> ignore
        escape[0x7F] = act(.ignore).to(.escape);
    }

    // === ESCAPE_INTERMEDIATE state ===
    {
        const escape_intermediate = &t[@intFromEnum(State.escape_intermediate)];
        // C0 controls -> execute
        for (0x00..0x18) |b| escape_intermediate[b] = act(.execute).to(.escape_intermediate);
        escape_intermediate[0x19] = act(.execute).to(.escape_intermediate);
        for (0x1C..0x20) |b| escape_intermediate[b] = act(.execute).to(.escape_intermediate);
        // Intermediate (0x20-0x2F) -> collect
        for (0x20..0x30) |b| escape_intermediate[b] = act(.collect).to(.escape_intermediate);
        // 0x30-0x7E -> esc_dispatch
        for (0x30..0x7F) |b| escape_intermediate[b] = act(.esc_dispatch).to(.ground);
        // DEL -> ignore
        escape_intermediate[0x7F] = act(.ignore).to(.escape_intermediate);
    }

    // === CSI_ENTRY state ===
    {
        const csi_entry = &t[@intFromEnum(State.csi_entry)];
        // C0 controls -> execute
        for (0x00..0x18) |b| csi_entry[b] = act(.execute).to(.csi_entry);
        csi_entry[0x19] = act(.execute).to(.csi_entry);
        for (0x1C..0x20) |b| csi_entry[b] = act(.execute).to(.csi_entry);
        // Intermediate (0x20-0x2F) -> collect, csi_intermediate
        for (0x20..0x30) |b| csi_entry[b] = act(.collect).to(.csi_intermediate);
        // Digits (0x30-0x39) -> param, csi_param
        for (0x30..0x3A) |b| csi_entry[b] = act(.param).to(.csi_param);
        // ':' (0x3A) -> csi_ignore
        csi_entry[0x3A] = to(.csi_ignore);
        // ';' (0x3B) -> param, csi_param
        csi_entry[0x3B] = act(.param).to(.csi_param);
        // '<', '=', '>', '?' (0x3C-0x3F) -> collect (private marker), csi_param
        for (0x3C..0x40) |b| csi_entry[b] = act(.collect).to(.csi_param);
        // Final bytes (0x40-0x7E) -> csi_dispatch
        for (0x40..0x7F) |b| csi_entry[b] = act(.csi_dispatch).to(.ground);
        // DEL -> ignore
        csi_entry[0x7F] = act(.ignore).to(.csi_entry);
    }

    // === CSI_PARAM state ===
    {
        const csi_param = &t[@intFromEnum(State.csi_param)];
        // C0 controls -> execute
        for (0x00..0x18) |b| csi_param[b] = act(.execute).to(.csi_param);
        csi_param[0x19] = act(.execute).to(.csi_param);
        for (0x1C..0x20) |b| csi_param[b] = act(.execute).to(.csi_param);
        // Intermediate (0x20-0x2F) -> collect, csi_intermediate
        for (0x20..0x30) |b| csi_param[b] = act(.collect).to(.csi_intermediate);
        // Digits (0x30-0x39) -> param
        for (0x30..0x3A) |b| csi_param[b] = act(.param).to(.csi_param);
        // ':' and 0x3C-0x3F -> csi_ignore (invalid in param)
        csi_param[0x3A] = to(.csi_ignore);
        // ';' -> param
        csi_param[0x3B] = act(.param).to(.csi_param);
        for (0x3C..0x40) |b| csi_param[b] = to(.csi_ignore);
        // Final bytes (0x40-0x7E) -> csi_dispatch
        for (0x40..0x7F) |b| csi_param[b] = act(.csi_dispatch).to(.ground);
        // DEL -> ignore
        csi_param[0x7F] = act(.ignore).to(.csi_param);
    }
    // === CSI_INTERMEDIATE state ===
    {
        const csi_intermediate = &t[@intFromEnum(State.csi_intermediate)];
        // C0 controls -> execute
        for (0x00..0x18) |b| csi_intermediate[b] = act(.execute).to(.csi_intermediate);
        csi_intermediate[0x19] = act(.execute).to(.csi_intermediate);
        for (0x1C..0x20) |b| csi_intermediate[b] = act(.execute).to(.csi_intermediate);
        // Intermediate (0x20-0x2F) -> collect
        for (0x20..0x30) |b| csi_intermediate[b] = act(.collect).to(.csi_intermediate);
        // 0x30-0x3F -> csi_ignore (invalid)
        for (0x30..0x40) |b| csi_intermediate[b] = to(.csi_ignore);
        // Final bytes (0x40-0x7E) -> csi_dispatch
        for (0x40..0x7F) |b| csi_intermediate[b] = act(.csi_dispatch).to(.ground);
        // DEL -> ignore
        csi_intermediate[0x7F] = act(.ignore).to(.csi_intermediate);
    }
    // === CSI_IGNORE state ===
    {
        const csi_ignore = &t[@intFromEnum(State.csi_ignore)];
        // C0 controls -> execute
        for (0x00..0x18) |b| csi_ignore[b] = act(.execute).to(.csi_ignore);
        csi_ignore[0x19] = act(.execute).to(.csi_ignore);
        for (0x1C..0x20) |b| csi_ignore[b] = act(.execute).to(.csi_ignore);
        // 0x20-0x3F -> ignore
        for (0x20..0x40) |b| csi_ignore[b] = act(.ignore).to(.csi_ignore);
        // Final bytes (0x40-0x7E) -> ground
        for (0x40..0x7F) |b| csi_ignore[b] = to(.ground);
        // DEL -> ignore
        csi_ignore[0x7F] = act(.ignore).to(.csi_ignore);
    }

    // === DCS_ENTRY state ===
    {
        const dcs_entry = &t[@intFromEnum(State.dcs_entry)];
        // 0x00-0x1F -> ignore
        for (0x00..0x20) |b| dcs_entry[b] = act(.ignore).to(.dcs_entry);
        // ESC should still be able to interrupt (restore anywhere rule)
        dcs_entry[0x1B] = act(.clear).to(.escape);
        // Intermediate (0x20-0x2F) -> collect, dcs_intermediate
        for (0x20..0x30) |b| dcs_entry[b] = act(.collect).to(.dcs_intermediate);
        // Digits (0x30-0x39) -> param, dcs_param
        for (0x30..0x3A) |b| dcs_entry[b] = act(.param).to(.dcs_param);
        // ':' -> dcs_ignore
        dcs_entry[0x3A] = to(.dcs_ignore);
        // ';' -> param, dcs_param
        dcs_entry[0x3B] = act(.param).to(.dcs_param);
        // '<', '=', '>', '?' -> collect (private marker), dcs_param
        for (0x3C..0x40) |b| dcs_entry[b] = act(.collect).to(.dcs_param);
        // Final bytes (0x40-0x7E) -> hook, dcs_passthrough
        for (0x40..0x7F) |b| dcs_entry[b] = act(.hook).to(.dcs_passthrough);
        // DEL -> ignore
        dcs_entry[0x7F] = act(.ignore).to(.dcs_entry);
    }

    // === DCS_PARAM state ===
    {
        const dcs_param = &t[@intFromEnum(State.dcs_param)];
        // 0x00-0x1F -> ignore
        for (0x00..0x20) |b| dcs_param[b] = act(.ignore).to(.dcs_param);
        // ESC should still be able to interrupt (restore anywhere rule)
        dcs_param[0x1B] = act(.clear).to(.escape);
        // Intermediate (0x20-0x2F) -> collect, dcs_intermediate
        for (0x20..0x30) |b| dcs_param[b] = act(.collect).to(.dcs_intermediate);
        // Digits (0x30-0x39) -> param
        for (0x30..0x3A) |b| dcs_param[b] = act(.param).to(.dcs_param);
        // ':' and 0x3C-0x3F -> dcs_ignore
        dcs_param[0x3A] = to(.dcs_ignore);
        // ';' -> param
        dcs_param[0x3B] = act(.param).to(.dcs_param);
        for (0x3C..0x40) |b| dcs_param[b] = to(.dcs_ignore);
        // Final bytes (0x40-0x7E) -> hook, dcs_passthrough
        for (0x40..0x7F) |b| dcs_param[b] = act(.hook).to(.dcs_passthrough);
        // DEL -> ignore
        dcs_param[0x7F] = act(.ignore).to(.dcs_param);
    }

    // === DCS_INTERMEDIATE state ===
    {
        const dcs_intermediate = &t[@intFromEnum(State.dcs_intermediate)];
        // 0x00-0x1F -> ignore
        for (0x00..0x20) |b| dcs_intermediate[b] = act(.ignore).to(.dcs_intermediate);
        // ESC should still be able to interrupt (restore anywhere rule)
        dcs_intermediate[0x1B] = act(.clear).to(.escape);
        // Intermediate (0x20-0x2F) -> collect
        for (0x20..0x30) |b| dcs_intermediate[b] = act(.collect).to(.dcs_intermediate);
        // 0x30-0x3F -> dcs_ignore
        for (0x30..0x40) |b| dcs_intermediate[b] = to(.dcs_ignore);
        // Final bytes (0x40-0x7E) -> hook, dcs_passthrough
        for (0x40..0x7F) |b| dcs_intermediate[b] = act(.hook).to(.dcs_passthrough);
        // DEL -> ignore
        dcs_intermediate[0x7F] = act(.ignore).to(.dcs_intermediate);
    }

    // === DCS_PASSTHROUGH state ===
    {
        const dcs_passthrough = &t[@intFromEnum(State.dcs_passthrough)];
        // 0x00-0x17, 0x19, 0x1C-0x1F, 0x20-0x7E -> put
        for (0x00..0x18) |b| dcs_passthrough[b] = act(.put).to(.dcs_passthrough);
        dcs_passthrough[0x19] = act(.put).to(.dcs_passthrough);
        for (0x1C..0x20) |b| dcs_passthrough[b] = act(.put).to(.dcs_passthrough);
        for (0x20..0x7F) |b| dcs_passthrough[b] = act(.put).to(.dcs_passthrough);
        // DEL -> ignore
        dcs_passthrough[0x7F] = act(.ignore).to(.dcs_passthrough);
    }
    // === DCS_IGNORE state ===
    {
        const dcs_ignore = &t[@intFromEnum(State.dcs_ignore)];
        // 0x00-0x7F -> ignore (wait for ST)
        for (0x00..0x80) |b| dcs_ignore[b] = act(.ignore).to(.dcs_ignore);
        // ESC should still be able to interrupt this state (restore anywhere rule)
        dcs_ignore[0x1B] = act(.clear).to(.escape);
    }

    // === OSC_STRING state ===
    {
        const osc_string = &t[@intFromEnum(State.osc_string)];
        // BEL (0x07) -> osc_end
        osc_string[0x07] = act(.osc_end).to(.ground);
        // 0x08-0x0D -> osc_put (some terminals allow these)
        for (0x08..0x0E) |b| osc_string[b] = act(.osc_put).to(.osc_string);
        // 0x20-0x7F -> osc_put
        for (0x20..0x80) |b| osc_string[b] = act(.osc_put).to(.osc_string);
    }
    // === SOS_PM_APC_STRING state ===
    // Everything ignored until ST (handled by anywhere rules)
    {
        const sos_pm_apc = &t[@intFromEnum(State.sos_pm_apc_string)];
        for (0x00..0x80) |b| sos_pm_apc[b] = act(.ignore).to(.sos_pm_apc_string);
        // ESC should still be able to interrupt this state (restore anywhere rule)
        sos_pm_apc[0x1B] = act(.clear).to(.escape);
    }

    return t;
}
