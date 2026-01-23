//! DEC ANSI Parser
//! Implements the state machine from https://vt100.net/emu/dec_ansi_parser
//!
//! This parser uses a transition table for efficient byte-by-byte processing
//! of ANSI escape sequences.


/// Parser states from the DEC ANSI state machine
pub const State = enum(u4) {
    ground,
    escape,
    escape_intermediate,
    csi_entry,
    csi_param,
    csi_intermediate,
    csi_ignore,
    dcs_entry,
    dcs_param,
    dcs_intermediate,
    dcs_passthrough,
    dcs_ignore,
    osc_string,
    sos_pm_apc_string,
    pub const fields = std.meta.fields(State);
};

/// Parser actions
pub const Action = enum(u4) {
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

/// A transition entry containing an action and next state
pub const Transition = struct {
    action: Action,
    state: State,
    pub const none = Transition{ .action = .none, .state = .ground };
};

/// Transition table type: indexed by [state][byte]
pub const TransitionTable = [State.fields.len][256]Transition;

/// Build the complete transition table at comptime
pub const table: TransitionTable = buildTable();

fn buildTable() TransitionTable {
    @setEvalBranchQuota(100000);
    var t: TransitionTable = undefined;

    // Initialize all to none/same-state
    for (0..std.meta.fields(State).len) |s| {
        const state: State = @enumFromInt(s);
        for (0..256) |b| {
            t[s][b] = .{ .action = .none, .state = state };
        }
    }

    // === ANYWHERE transitions (apply to all states) ===
    for (0..std.meta.fields(State).len) |s| {
        // CAN, SUB -> execute, ground
        t[s][0x18] = .{ .action = .execute, .state = .ground };
        t[s][0x1A] = .{ .action = .execute, .state = .ground };

        // ESC -> clear, escape
        t[s][0x1B] = .{ .action = .clear, .state = .escape };

        // ST (0x9C) -> ground (with state-specific action handled separately)
        t[s][0x9C] = .{ .action = .none, .state = .ground };
    }

    // ST actions for specific states
    t[@intFromEnum(State.dcs_passthrough)][0x9C] = .{ .action = .unhook, .state = .ground };
    t[@intFromEnum(State.osc_string)][0x9C] = .{ .action = .osc_end, .state = .ground };

    // === 8-bit C1 controls (anywhere) ===
    for (0..std.meta.fields(State).len) |s| {
        // CSI (0x9B)
        t[s][0x9B] = .{ .action = .clear, .state = .csi_entry };
        // DCS (0x90)
        t[s][0x90] = .{ .action = .clear, .state = .dcs_entry };
        // OSC (0x9D)
        t[s][0x9D] = .{ .action = .osc_start, .state = .osc_string };
        // SOS (0x98), PM (0x9E), APC (0x9F)
        t[s][0x98] = .{ .action = .none, .state = .sos_pm_apc_string };
        t[s][0x9E] = .{ .action = .none, .state = .sos_pm_apc_string };
        t[s][0x9F] = .{ .action = .none, .state = .sos_pm_apc_string };

        // Other C1 codes -> execute, ground
        for ([_]u8{ 0x80, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8A, 0x8B, 0x8C, 0x8D, 0x8E, 0x8F, 0x91, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x99, 0x9A }) |c| {
            t[s][c] = .{ .action = .execute, .state = .ground };
        }
    }

    // === GROUND state ===
    const ground = @intFromEnum(State.ground);
    // C0 controls -> execute
    for (0x00..0x18) |b| t[ground][b] = .{ .action = .execute, .state = .ground };
    t[ground][0x19] = .{ .action = .execute, .state = .ground };
    for (0x1C..0x20) |b| t[ground][b] = .{ .action = .execute, .state = .ground };
    // Printable -> print
    for (0x20..0x80) |b| t[ground][b] = .{ .action = .print, .state = .ground };

    // === ESCAPE state ===
    const escape = @intFromEnum(State.escape);
    // C0 controls -> execute
    for (0x00..0x18) |b| t[escape][b] = .{ .action = .execute, .state = .escape };
    t[escape][0x19] = .{ .action = .execute, .state = .escape };
    for (0x1C..0x20) |b| t[escape][b] = .{ .action = .execute, .state = .escape };
    // Intermediate (0x20-0x2F) -> collect, escape_intermediate
    for (0x20..0x30) |b| t[escape][b] = .{ .action = .collect, .state = .escape_intermediate };
    // 0x30-0x4F -> esc_dispatch (except special cases)
    for (0x30..0x50) |b| t[escape][b] = .{ .action = .esc_dispatch, .state = .ground };
    // 'P' (0x50) -> DCS
    t[escape][0x50] = .{ .action = .clear, .state = .dcs_entry };
    // 0x51-0x57 -> esc_dispatch
    for (0x51..0x58) |b| t[escape][b] = .{ .action = .esc_dispatch, .state = .ground };
    // 'X' (0x58) -> SOS
    t[escape][0x58] = .{ .action = .none, .state = .sos_pm_apc_string };
    // 'Y', 'Z' -> esc_dispatch
    t[escape][0x59] = .{ .action = .esc_dispatch, .state = .ground };
    t[escape][0x5A] = .{ .action = .esc_dispatch, .state = .ground };
    // '[' (0x5B) -> CSI
    t[escape][0x5B] = .{ .action = .clear, .state = .csi_entry };
    // '\' (0x5C) -> esc_dispatch (ST)
    t[escape][0x5C] = .{ .action = .esc_dispatch, .state = .ground };
    // ']' (0x5D) -> OSC
    t[escape][0x5D] = .{ .action = .osc_start, .state = .osc_string };
    // '^' (0x5E) -> PM
    t[escape][0x5E] = .{ .action = .none, .state = .sos_pm_apc_string };
    // '_' (0x5F) -> APC
    t[escape][0x5F] = .{ .action = .none, .state = .sos_pm_apc_string };
    // 0x60-0x7E -> esc_dispatch
    for (0x60..0x7F) |b| t[escape][b] = .{ .action = .esc_dispatch, .state = .ground };
    // DEL (0x7F) -> ignore
    t[escape][0x7F] = .{ .action = .ignore, .state = .escape };

    // === ESCAPE_INTERMEDIATE state ===
    const escape_intermediate = @intFromEnum(State.escape_intermediate);
    // C0 controls -> execute
    for (0x00..0x18) |b| t[escape_intermediate][b] = .{ .action = .execute, .state = .escape_intermediate };
    t[escape_intermediate][0x19] = .{ .action = .execute, .state = .escape_intermediate };
    for (0x1C..0x20) |b| t[escape_intermediate][b] = .{ .action = .execute, .state = .escape_intermediate };
    // Intermediate (0x20-0x2F) -> collect
    for (0x20..0x30) |b| t[escape_intermediate][b] = .{ .action = .collect, .state = .escape_intermediate };
    // 0x30-0x7E -> esc_dispatch
    for (0x30..0x7F) |b| t[escape_intermediate][b] = .{ .action = .esc_dispatch, .state = .ground };
    // DEL -> ignore
    t[escape_intermediate][0x7F] = .{ .action = .ignore, .state = .escape_intermediate };

    // === CSI_ENTRY state ===
    const csi_entry = @intFromEnum(State.csi_entry);
    // C0 controls -> execute
    for (0x00..0x18) |b| t[csi_entry][b] = .{ .action = .execute, .state = .csi_entry };
    t[csi_entry][0x19] = .{ .action = .execute, .state = .csi_entry };
    for (0x1C..0x20) |b| t[csi_entry][b] = .{ .action = .execute, .state = .csi_entry };
    // Intermediate (0x20-0x2F) -> collect, csi_intermediate
    for (0x20..0x30) |b| t[csi_entry][b] = .{ .action = .collect, .state = .csi_intermediate };
    // Digits (0x30-0x39) -> param, csi_param
    for (0x30..0x3A) |b| t[csi_entry][b] = .{ .action = .param, .state = .csi_param };
    // ':' (0x3A) -> csi_ignore
    t[csi_entry][0x3A] = .{ .action = .none, .state = .csi_ignore };
    // ';' (0x3B) -> param, csi_param
    t[csi_entry][0x3B] = .{ .action = .param, .state = .csi_param };
    // '<', '=', '>', '?' (0x3C-0x3F) -> collect (private marker), csi_param
    for (0x3C..0x40) |b| t[csi_entry][b] = .{ .action = .collect, .state = .csi_param };
    // Final bytes (0x40-0x7E) -> csi_dispatch
    for (0x40..0x7F) |b| t[csi_entry][b] = .{ .action = .csi_dispatch, .state = .ground };
    // DEL -> ignore
    t[csi_entry][0x7F] = .{ .action = .ignore, .state = .csi_entry };

    // === CSI_PARAM state ===
    const csi_param = @intFromEnum(State.csi_param);
    // C0 controls -> execute
    for (0x00..0x18) |b| t[csi_param][b] = .{ .action = .execute, .state = .csi_param };
    t[csi_param][0x19] = .{ .action = .execute, .state = .csi_param };
    for (0x1C..0x20) |b| t[csi_param][b] = .{ .action = .execute, .state = .csi_param };
    // Intermediate (0x20-0x2F) -> collect, csi_intermediate
    for (0x20..0x30) |b| t[csi_param][b] = .{ .action = .collect, .state = .csi_intermediate };
    // Digits (0x30-0x39) -> param
    for (0x30..0x3A) |b| t[csi_param][b] = .{ .action = .param, .state = .csi_param };
    // ':' and 0x3C-0x3F -> csi_ignore (invalid in param)
    t[csi_param][0x3A] = .{ .action = .none, .state = .csi_ignore };
    // ';' -> param
    t[csi_param][0x3B] = .{ .action = .param, .state = .csi_param };
    for (0x3C..0x40) |b| t[csi_param][b] = .{ .action = .none, .state = .csi_ignore };
    // Final bytes (0x40-0x7E) -> csi_dispatch
    for (0x40..0x7F) |b| t[csi_param][b] = .{ .action = .csi_dispatch, .state = .ground };
    // DEL -> ignore
    t[csi_param][0x7F] = .{ .action = .ignore, .state = .csi_param };

    // === CSI_INTERMEDIATE state ===
    const csi_intermediate = @intFromEnum(State.csi_intermediate);
    // C0 controls -> execute
    for (0x00..0x18) |b| t[csi_intermediate][b] = .{ .action = .execute, .state = .csi_intermediate };
    t[csi_intermediate][0x19] = .{ .action = .execute, .state = .csi_intermediate };
    for (0x1C..0x20) |b| t[csi_intermediate][b] = .{ .action = .execute, .state = .csi_intermediate };
    // Intermediate (0x20-0x2F) -> collect
    for (0x20..0x30) |b| t[csi_intermediate][b] = .{ .action = .collect, .state = .csi_intermediate };
    // 0x30-0x3F -> csi_ignore (invalid)
    for (0x30..0x40) |b| t[csi_intermediate][b] = .{ .action = .none, .state = .csi_ignore };
    // Final bytes (0x40-0x7E) -> csi_dispatch
    for (0x40..0x7F) |b| t[csi_intermediate][b] = .{ .action = .csi_dispatch, .state = .ground };
    // DEL -> ignore
    t[csi_intermediate][0x7F] = .{ .action = .ignore, .state = .csi_intermediate };

    // === CSI_IGNORE state ===
    const csi_ignore = @intFromEnum(State.csi_ignore);
    // C0 controls -> execute
    for (0x00..0x18) |b| t[csi_ignore][b] = .{ .action = .execute, .state = .csi_ignore };
    t[csi_ignore][0x19] = .{ .action = .execute, .state = .csi_ignore };
    for (0x1C..0x20) |b| t[csi_ignore][b] = .{ .action = .execute, .state = .csi_ignore };
    // 0x20-0x3F -> ignore
    for (0x20..0x40) |b| t[csi_ignore][b] = .{ .action = .ignore, .state = .csi_ignore };
    // Final bytes (0x40-0x7E) -> ground
    for (0x40..0x7F) |b| t[csi_ignore][b] = .{ .action = .none, .state = .ground };
    // DEL -> ignore
    t[csi_ignore][0x7F] = .{ .action = .ignore, .state = .csi_ignore };

    // === DCS_ENTRY state ===
    const dcs_entry = @intFromEnum(State.dcs_entry);
    // 0x00-0x1F -> ignore
    for (0x00..0x20) |b| t[dcs_entry][b] = .{ .action = .ignore, .state = .dcs_entry };
    // ESC should still be able to interrupt (restore anywhere rule)
    t[dcs_entry][0x1B] = .{ .action = .clear, .state = .escape };
    // Intermediate (0x20-0x2F) -> collect, dcs_intermediate
    for (0x20..0x30) |b| t[dcs_entry][b] = .{ .action = .collect, .state = .dcs_intermediate };
    // Digits (0x30-0x39) -> param, dcs_param
    for (0x30..0x3A) |b| t[dcs_entry][b] = .{ .action = .param, .state = .dcs_param };
    // ':' -> dcs_ignore
    t[dcs_entry][0x3A] = .{ .action = .none, .state = .dcs_ignore };
    // ';' -> param, dcs_param
    t[dcs_entry][0x3B] = .{ .action = .param, .state = .dcs_param };
    // '<', '=', '>', '?' -> collect (private marker), dcs_param
    for (0x3C..0x40) |b| t[dcs_entry][b] = .{ .action = .collect, .state = .dcs_param };
    // Final bytes (0x40-0x7E) -> hook, dcs_passthrough
    for (0x40..0x7F) |b| t[dcs_entry][b] = .{ .action = .hook, .state = .dcs_passthrough };
    // DEL -> ignore
    t[dcs_entry][0x7F] = .{ .action = .ignore, .state = .dcs_entry };

    // === DCS_PARAM state ===
    const dcs_param = @intFromEnum(State.dcs_param);
    // 0x00-0x1F -> ignore
    for (0x00..0x20) |b| t[dcs_param][b] = .{ .action = .ignore, .state = .dcs_param };
    // ESC should still be able to interrupt (restore anywhere rule)
    t[dcs_param][0x1B] = .{ .action = .clear, .state = .escape };
    // Intermediate (0x20-0x2F) -> collect, dcs_intermediate
    for (0x20..0x30) |b| t[dcs_param][b] = .{ .action = .collect, .state = .dcs_intermediate };
    // Digits (0x30-0x39) -> param
    for (0x30..0x3A) |b| t[dcs_param][b] = .{ .action = .param, .state = .dcs_param };
    // ':' and 0x3C-0x3F -> dcs_ignore
    t[dcs_param][0x3A] = .{ .action = .none, .state = .dcs_ignore };
    // ';' -> param
    t[dcs_param][0x3B] = .{ .action = .param, .state = .dcs_param };
    for (0x3C..0x40) |b| t[dcs_param][b] = .{ .action = .none, .state = .dcs_ignore };
    // Final bytes (0x40-0x7E) -> hook, dcs_passthrough
    for (0x40..0x7F) |b| t[dcs_param][b] = .{ .action = .hook, .state = .dcs_passthrough };
    // DEL -> ignore
    t[dcs_param][0x7F] = .{ .action = .ignore, .state = .dcs_param };

    // === DCS_INTERMEDIATE state ===
    const dcs_intermediate = @intFromEnum(State.dcs_intermediate);
    // 0x00-0x1F -> ignore
    for (0x00..0x20) |b| t[dcs_intermediate][b] = .{ .action = .ignore, .state = .dcs_intermediate };
    // ESC should still be able to interrupt (restore anywhere rule)
    t[dcs_intermediate][0x1B] = .{ .action = .clear, .state = .escape };
    // Intermediate (0x20-0x2F) -> collect
    for (0x20..0x30) |b| t[dcs_intermediate][b] = .{ .action = .collect, .state = .dcs_intermediate };
    // 0x30-0x3F -> dcs_ignore
    for (0x30..0x40) |b| t[dcs_intermediate][b] = .{ .action = .none, .state = .dcs_ignore };
    // Final bytes (0x40-0x7E) -> hook, dcs_passthrough
    for (0x40..0x7F) |b| t[dcs_intermediate][b] = .{ .action = .hook, .state = .dcs_passthrough };
    // DEL -> ignore
    t[dcs_intermediate][0x7F] = .{ .action = .ignore, .state = .dcs_intermediate };

    // === DCS_PASSTHROUGH state ===
    const dcs_passthrough = @intFromEnum(State.dcs_passthrough);
    // 0x00-0x17, 0x19, 0x1C-0x1F, 0x20-0x7E -> put
    for (0x00..0x18) |b| t[dcs_passthrough][b] = .{ .action = .put, .state = .dcs_passthrough };
    t[dcs_passthrough][0x19] = .{ .action = .put, .state = .dcs_passthrough };
    for (0x1C..0x20) |b| t[dcs_passthrough][b] = .{ .action = .put, .state = .dcs_passthrough };
    for (0x20..0x7F) |b| t[dcs_passthrough][b] = .{ .action = .put, .state = .dcs_passthrough };
    // DEL -> ignore
    t[dcs_passthrough][0x7F] = .{ .action = .ignore, .state = .dcs_passthrough };

    // === DCS_IGNORE state ===
    const dcs_ignore = @intFromEnum(State.dcs_ignore);
    // 0x00-0x7F -> ignore (wait for ST)
    for (0x00..0x80) |b| t[dcs_ignore][b] = .{ .action = .ignore, .state = .dcs_ignore };
    // ESC should still be able to interrupt this state (restore anywhere rule)
    t[dcs_ignore][0x1B] = .{ .action = .clear, .state = .escape };

    // === OSC_STRING state ===
    const osc_string = @intFromEnum(State.osc_string);
    // BEL (0x07) -> osc_end
    t[osc_string][0x07] = .{ .action = .osc_end, .state = .ground };
    // 0x08-0x0D -> osc_put (some terminals allow these)
    for (0x08..0x0E) |b| t[osc_string][b] = .{ .action = .osc_put, .state = .osc_string };
    // 0x20-0x7F -> osc_put
    for (0x20..0x80) |b| t[osc_string][b] = .{ .action = .osc_put, .state = .osc_string };

    // === SOS_PM_APC_STRING state ===
    // Everything ignored until ST (handled by anywhere rules)
    const sos_pm_apc = @intFromEnum(State.sos_pm_apc_string);
    for (0x00..0x80) |b| t[sos_pm_apc][b] = .{ .action = .ignore, .state = .sos_pm_apc_string };
    // ESC should still be able to interrupt this state (restore anywhere rule)
    t[sos_pm_apc][0x1B] = .{ .action = .clear, .state = .escape };

    return t;
}

/// Maximum number of parameters in a CSI sequence
pub const MAX_PARAMS = 16;
/// Maximum number of intermediate characters
pub const MAX_INTERMEDIATES = 2;
/// Maximum OSC string length
pub const MAX_OSC_LEN = 512;

/// DEC ANSI Parser
/// Implements the state machine from https://vt100.net/emu/dec_ansi_parser
pub const Parser = struct {
    state: State = .ground,
    /// Intermediate characters (0x20-0x2F range)
    intermediates: [MAX_INTERMEDIATES]u8 = undefined,
    intermediates_len: u8 = 0,
    /// CSI parameters
    params: [MAX_PARAMS]u16 = undefined,
    params_len: u8 = 0,
    /// Current parameter being built
    current_param: u16 = 0,
    param_has_value: bool = false,
    /// Private marker (e.g., '?' in CSI ? Ps n)
    private_marker: u8 = 0,
    /// Final character of sequence
    final_char: u8 = 0,
    /// OSC string buffer
    osc_data: [MAX_OSC_LEN]u8 = undefined,
    osc_len: u16 = 0,

    pub fn init() Parser {
        return .{};
    }

    /// Reset parser to initial state
    pub fn reset(self: *Parser) void {
        self.state = .ground;
        self.clear();
        self.clearOsc();
    }

    /// Reset parser state for new sequence
    pub fn clear(self: *Parser) void {
        self.intermediates_len = 0;
        self.params_len = 0;
        self.current_param = 0;
        self.param_has_value = false;
        self.private_marker = 0;
        self.final_char = 0;
    }

    /// Reset OSC data
    pub fn clearOsc(self: *Parser) void {
        self.osc_len = 0;
    }

    /// Get collected parameters
    pub fn getParams(self: *const Parser) []const u16 {
        return self.params[0..self.params_len];
    }

    /// Get parameter at index with default value
    pub fn getParam(self: *const Parser, index: usize, default: u16) u16 {
        if (index < self.params_len) {
            const p = self.params[index];
            return if (p == 0) default else p;
        }
        return default;
    }

    /// Get collected intermediates
    pub fn getIntermediates(self: *const Parser) []const u8 {
        return self.intermediates[0..self.intermediates_len];
    }

    /// Get OSC string data
    pub fn getOscData(self: *const Parser) []const u8 {
        return self.osc_data[0..self.osc_len];
    }

    /// Check if this is a private sequence (has '?' marker)
    pub fn isPrivate(self: *const Parser) bool {
        return self.private_marker == '?';
    }

    /// Process a single byte through the state machine
    /// Returns the action to take
    pub fn advance(self: *Parser, byte: u8) Action {
        const trans = table[@intFromEnum(self.state)][byte];

        // Perform action
        self.performAction(trans.action, byte);

        // Update state
        self.state = trans.state;

        return trans.action;
    }

    fn performAction(self: *Parser, action: Action, byte: u8) void {
        switch (action) {
            .clear => self.clear(),
            .collect => self.doCollect(byte),
            .param => self.doParam(byte),
            .osc_start => self.clearOsc(),
            .osc_put => self.oscPut(byte),
            .esc_dispatch, .csi_dispatch, .hook => {
                self.final_char = byte;
                self.finalizeParams();
            },
            else => {},
        }
    }

    /// Collect intermediate character or private marker
    fn doCollect(self: *Parser, byte: u8) void {
        if (byte >= 0x3C and byte <= 0x3F) {
            // Private marker
            self.private_marker = byte;
        } else if (self.intermediates_len < MAX_INTERMEDIATES) {
            self.intermediates[self.intermediates_len] = byte;
            self.intermediates_len += 1;
        }
    }

    /// Process parameter character
    fn doParam(self: *Parser, byte: u8) void {
        if (byte == ';') {
            // End current parameter, start new one
            if (self.params_len < MAX_PARAMS) {
                self.params[self.params_len] = if (self.param_has_value) self.current_param else 0;
                self.params_len += 1;
            }
            self.current_param = 0;
            self.param_has_value = false;
        } else if (byte >= '0' and byte <= '9') {
            self.param_has_value = true;
            self.current_param = self.current_param *| 10 +| (byte - '0');
        }
    }

    /// Finalize parameters (call before dispatch)
    fn finalizeParams(self: *Parser) void {
        if (self.param_has_value or self.params_len > 0) {
            if (self.params_len < MAX_PARAMS) {
                self.params[self.params_len] = if (self.param_has_value) self.current_param else 0;
                self.params_len += 1;
            }
        }
    }

    /// Add byte to OSC string
    fn oscPut(self: *Parser, byte: u8) void {
        if (self.osc_len < MAX_OSC_LEN) {
            self.osc_data[self.osc_len] = byte;
            self.osc_len += 1;
        }
    }
};

// =============================================================================
// Tests
// =============================================================================

test "Parser - initial state" {
    const parser = Parser.init();
    try std.testing.expectEqual(State.ground, parser.state);
    try std.testing.expectEqual(@as(u8, 0), parser.params_len);
    try std.testing.expectEqual(@as(u8, 0), parser.intermediates_len);
}

test "Parser - reset" {
    var parser = Parser.init();

    // Put parser in some state
    _ = parser.advance(0x1B);
    _ = parser.advance('[');
    _ = parser.advance('1');

    parser.reset();

    try std.testing.expectEqual(State.ground, parser.state);
    try std.testing.expectEqual(@as(u8, 0), parser.params_len);
}

test "Parser - CSI sequence basic" {
    var parser = Parser.init();

    // Parse "\x1b[31m" (set foreground red)
    var action = parser.advance(0x1B); // ESC
    try std.testing.expectEqual(Action.clear, action);
    try std.testing.expectEqual(State.escape, parser.state);

    action = parser.advance('['); // [
    try std.testing.expectEqual(Action.clear, action);
    try std.testing.expectEqual(State.csi_entry, parser.state);

    action = parser.advance('3'); // 3
    try std.testing.expectEqual(Action.param, action);
    try std.testing.expectEqual(State.csi_param, parser.state);

    action = parser.advance('1'); // 1
    try std.testing.expectEqual(Action.param, action);

    action = parser.advance('m'); // m (final)
    try std.testing.expectEqual(Action.csi_dispatch, action);
    try std.testing.expectEqual(State.ground, parser.state);
    try std.testing.expectEqual(@as(u8, 'm'), parser.final_char);

    const params = parser.getParams();
    try std.testing.expectEqual(@as(usize, 1), params.len);
    try std.testing.expectEqual(@as(u16, 31), params[0]);
}

test "Parser - CSI with multiple params" {
    var parser = Parser.init();

    // Parse "\x1b[1;31;40m" (bold, red fg, black bg)
    for ("\x1b[1;31;40m") |byte| {
        _ = parser.advance(byte);
    }

    try std.testing.expectEqual(State.ground, parser.state);
    try std.testing.expectEqual(@as(u8, 'm'), parser.final_char);

    const params = parser.getParams();
    try std.testing.expectEqual(@as(usize, 3), params.len);
    try std.testing.expectEqual(@as(u16, 1), params[0]);
    try std.testing.expectEqual(@as(u16, 31), params[1]);
    try std.testing.expectEqual(@as(u16, 40), params[2]);
}

test "Parser - CSI with empty params" {
    var parser = Parser.init();

    // Parse "\x1b[;5;m" (empty first and last params)
    for ("\x1b[;5;m") |byte| {
        _ = parser.advance(byte);
    }

    const params = parser.getParams();
    try std.testing.expectEqual(@as(usize, 3), params.len);
    try std.testing.expectEqual(@as(u16, 0), params[0]); // empty
    try std.testing.expectEqual(@as(u16, 5), params[1]);
    try std.testing.expectEqual(@as(u16, 0), params[2]); // empty
}

test "Parser - private CSI sequence" {
    var parser = Parser.init();

    // Parse "\x1b[?25h" (show cursor - DECTCEM)
    for ("\x1b[?25h") |byte| {
        _ = parser.advance(byte);
    }

    try std.testing.expectEqual(State.ground, parser.state);
    try std.testing.expectEqual(@as(u8, 'h'), parser.final_char);
    try std.testing.expectEqual(@as(u8, '?'), parser.private_marker);
    try std.testing.expect(parser.isPrivate());

    const params = parser.getParams();
    try std.testing.expectEqual(@as(usize, 1), params.len);
    try std.testing.expectEqual(@as(u16, 25), params[0]);
}

test "Parser - CSI cursor position" {
    var parser = Parser.init();

    // Parse "\x1b[10;20H" (cursor to row 10, col 20)
    for ("\x1b[10;20H") |byte| {
        _ = parser.advance(byte);
    }

    try std.testing.expectEqual(@as(u8, 'H'), parser.final_char);

    const params = parser.getParams();
    try std.testing.expectEqual(@as(usize, 2), params.len);
    try std.testing.expectEqual(@as(u16, 10), params[0]);
    try std.testing.expectEqual(@as(u16, 20), params[1]);
}

test "Parser - OSC sequence with BEL" {
    var parser = Parser.init();

    // Parse "\x1b]0;Window Title\x07" (set window title)
    var last_action: Action = .none;
    for ("\x1b]0;Window Title\x07") |byte| {
        last_action = parser.advance(byte);
    }

    try std.testing.expectEqual(Action.osc_end, last_action);
    try std.testing.expectEqual(State.ground, parser.state);
    try std.testing.expectEqualStrings("0;Window Title", parser.getOscData());
}

test "Parser - OSC sequence with ST" {
    var parser = Parser.init();

    // Parse "\x1b]2;Title\x1b\\" (set window title with ST terminator)
    for ("\x1b]2;Title") |byte| {
        _ = parser.advance(byte);
    }

    try std.testing.expectEqual(State.osc_string, parser.state);

    // ESC starts new sequence, effectively terminating OSC
    const action = parser.advance(0x1B);
    try std.testing.expectEqual(Action.clear, action);
    try std.testing.expectEqual(State.escape, parser.state);
}

test "Parser - escape sequence" {
    var parser = Parser.init();

    // Parse "\x1bD" (Index - IND)
    _ = parser.advance(0x1B);
    const action = parser.advance('D');

    try std.testing.expectEqual(Action.esc_dispatch, action);
    try std.testing.expectEqual(State.ground, parser.state);
    try std.testing.expectEqual(@as(u8, 'D'), parser.final_char);
}

test "Parser - escape with intermediate" {
    var parser = Parser.init();

    // Parse "\x1b#8" (DECALN - fill screen with E's)
    _ = parser.advance(0x1B);
    _ = parser.advance('#');
    const action = parser.advance('8');

    try std.testing.expectEqual(Action.esc_dispatch, action);
    try std.testing.expectEqual(State.ground, parser.state);
    try std.testing.expectEqual(@as(u8, '8'), parser.final_char);
    try std.testing.expectEqualStrings("#", parser.getIntermediates());
}

test "Parser - getParam with default" {
    var parser = Parser.init();

    // Parse "\x1b[;5H" (cursor position with default row)
    for ("\x1b[;5H") |byte| {
        _ = parser.advance(byte);
    }

    // First param is empty (0), should return default when 0
    try std.testing.expectEqual(@as(u16, 1), parser.getParam(0, 1));
    try std.testing.expectEqual(@as(u16, 5), parser.getParam(1, 1));
    // Out of bounds should return default
    try std.testing.expectEqual(@as(u16, 99), parser.getParam(5, 99));
}

test "Parser - print action" {
    var parser = Parser.init();

    const action = parser.advance('A');
    try std.testing.expectEqual(Action.print, action);
    try std.testing.expectEqual(State.ground, parser.state);
}

test "Parser - execute action for C0" {
    var parser = Parser.init();

    // Newline should execute
    var action = parser.advance('\n');
    try std.testing.expectEqual(Action.execute, action);
    try std.testing.expectEqual(State.ground, parser.state);

    // Carriage return
    action = parser.advance('\r');
    try std.testing.expectEqual(Action.execute, action);

    // Tab
    action = parser.advance('\t');
    try std.testing.expectEqual(Action.execute, action);

    // Bell
    action = parser.advance(0x07);
    try std.testing.expectEqual(Action.execute, action);
}

test "Parser - CAN cancels sequence" {
    var parser = Parser.init();

    // Start a CSI sequence
    _ = parser.advance(0x1B);
    _ = parser.advance('[');
    _ = parser.advance('1');

    try std.testing.expectEqual(State.csi_param, parser.state);

    // CAN should cancel and go to ground
    const action = parser.advance(0x18);
    try std.testing.expectEqual(Action.execute, action);
    try std.testing.expectEqual(State.ground, parser.state);
}

test "Parser - SUB cancels sequence" {
    var parser = Parser.init();

    // Start a CSI sequence
    _ = parser.advance(0x1B);
    _ = parser.advance('[');

    // SUB should cancel
    const action = parser.advance(0x1A);
    try std.testing.expectEqual(Action.execute, action);
    try std.testing.expectEqual(State.ground, parser.state);
}

test "Parser - ESC interrupts sequence" {
    var parser = Parser.init();

    // Start a CSI sequence
    _ = parser.advance(0x1B);
    _ = parser.advance('[');
    _ = parser.advance('1');

    // New ESC should start new sequence
    const action = parser.advance(0x1B);
    try std.testing.expectEqual(Action.clear, action);
    try std.testing.expectEqual(State.escape, parser.state);
}

test "Parser - 8-bit CSI" {
    var parser = Parser.init();

    // 0x9B is 8-bit CSI
    var action = parser.advance(0x9B);
    try std.testing.expectEqual(Action.clear, action);
    try std.testing.expectEqual(State.csi_entry, parser.state);

    // Continue with parameters
    _ = parser.advance('5');
    action = parser.advance('m');
    try std.testing.expectEqual(Action.csi_dispatch, action);
    try std.testing.expectEqual(@as(u16, 5), parser.getParams()[0]);
}

test "Parser - CSI ignore on invalid" {
    var parser = Parser.init();

    // Parse sequence with ':' which should trigger ignore
    for ("\x1b[1:2m") |byte| {
        _ = parser.advance(byte);
    }

    // Should end up in ground after final char
    try std.testing.expectEqual(State.ground, parser.state);
}

test "Parser - large parameter value" {
    var parser = Parser.init();

    // Parse with large number (should saturate, not overflow)
    for ("\x1b[99999m") |byte| {
        _ = parser.advance(byte);
    }

    try std.testing.expectEqual(State.ground, parser.state);
    // Value should be saturated at u16 max or the actual value if it fits
    const params = parser.getParams();
    try std.testing.expectEqual(@as(usize, 1), params.len);
}

test "Parser - DCS sequence" {
    var parser = Parser.init();

    // Parse "\x1bP1$r\x9c" (DCS with ST terminator)
    _ = parser.advance(0x1B);
    var action = parser.advance('P');
    try std.testing.expectEqual(Action.clear, action);
    try std.testing.expectEqual(State.dcs_entry, parser.state);

    _ = parser.advance('1');
    _ = parser.advance('$');
    action = parser.advance('r');
    try std.testing.expectEqual(Action.hook, action);
    try std.testing.expectEqual(State.dcs_passthrough, parser.state);

    // ST terminates
    action = parser.advance(0x9C);
    try std.testing.expectEqual(Action.unhook, action);
    try std.testing.expectEqual(State.ground, parser.state);
}

test "Parser - control chars during CSI" {
    var parser = Parser.init();

    // C0 controls should execute even during CSI
    _ = parser.advance(0x1B);
    _ = parser.advance('[');

    // Bell during CSI
    const action = parser.advance(0x07);
    try std.testing.expectEqual(Action.execute, action);
    // Should still be in csi_entry
    try std.testing.expectEqual(State.csi_entry, parser.state);
}

test "Parser - multiple sequences" {
    var parser = Parser.init();

    // Parse two sequences back to back
    for ("\x1b[31m") |byte| {
        _ = parser.advance(byte);
    }

    try std.testing.expectEqual(@as(u16, 31), parser.getParams()[0]);
    try std.testing.expectEqual(@as(u8, 'm'), parser.final_char);

    // Second sequence
    for ("\x1b[1A") |byte| {
        _ = parser.advance(byte);
    }

    try std.testing.expectEqual(@as(u16, 1), parser.getParams()[0]);
    try std.testing.expectEqual(@as(u8, 'A'), parser.final_char);
}

test "Parser - CSI with intermediate" {
    var parser = Parser.init();

    // Parse "\x1b[ q" (set cursor style with space intermediate)
    for ("\x1b[2 q") |byte| {
        _ = parser.advance(byte);
    }

    try std.testing.expectEqual(State.ground, parser.state);
    try std.testing.expectEqual(@as(u8, 'q'), parser.final_char);
    try std.testing.expectEqualStrings(" ", parser.getIntermediates());
    try std.testing.expectEqual(@as(u16, 2), parser.getParams()[0]);
}

test "transition table - ground printable" {
    const trans = table[@intFromEnum(State.ground)]['A'];
    try std.testing.expectEqual(Action.print, trans.action);
    try std.testing.expectEqual(State.ground, trans.state);
}

test "transition table - escape to csi" {
    const trans = table[@intFromEnum(State.escape)]['['];
    try std.testing.expectEqual(Action.clear, trans.action);
    try std.testing.expectEqual(State.csi_entry, trans.state);
}

test "transition table - anywhere ESC" {
    // ESC should work from any state
    for (0..std.meta.fields(State).len) |s| {
        const trans = table[s][0x1B];
        try std.testing.expectEqual(Action.clear, trans.action);
        try std.testing.expectEqual(State.escape, trans.state);
    }
}

const std = @import("std");
