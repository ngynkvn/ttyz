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
    // none,
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
    pub fn advance(self: *Parser, byte: u8) ?Action {
        const trans = table[@intFromEnum(self.state)][byte];

        // Perform action
        if (trans.action) |action| self.performAction(action, byte);
        // Update state
        if (trans.state) |state| self.state = state;

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

const TransitionTable = @import("parser/table.zig").table;
const table = TransitionTable;
