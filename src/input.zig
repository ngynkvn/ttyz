const std = @import("std");
const tty = @import("tty.zig");
const posix = std.posix;
const system = posix.system;

pub const Command = enum { quit, enter, kh, kj, kk, kl, pause };
pub const Keymap = struct { key: []const u8, command: Command };
pub const default_keys = [_]Keymap{
    .{ .key = "\r", .command = .enter },
    .{ .key = "h", .command = .kh },
    .{ .key = "j", .command = .kj },
    .{ .key = "k", .command = .kk },
    .{ .key = "l", .command = .kl },
    .{ .key = "p", .command = .pause },
    // <C-c>
    .{ .key = "\x03", .command = .quit },
};

pub const InputHandler = struct {
    raw: *tty.RawMode,
    keymaps: []const Keymap,
    timer: std.time.Timer,
    poll_interval_ms: usize = 128,
    const npm = std.time.ns_per_ms;
    pub fn init(raw: *tty.RawMode, keymaps: ?[]Keymap) InputHandler {
        return InputHandler{
            .raw = raw,
            .timer = std.time.Timer.start() catch @panic("Your system does not support timers!"),
            .keymaps = keymaps orelse &default_keys,
        };
    }
    pub fn poll(self: *InputHandler) ?Command {
        if (self.timer.read() < self.poll_interval_ms * npm) return null;
        self.timer.reset();

        var buffer: [4]u8 = undefined;
        const n = self.raw.read(&buffer) catch @panic("Unable to read from tty");
        const read = buffer[0..n];

        for (self.keymaps) |keymap| {
            if (std.mem.startsWith(u8, read, keymap.key)) return keymap.command;
        }

        return null;
    }

    pub fn waitFor(self: *InputHandler) Command {
        return self.pollWaitFor();
    }

    pub fn pollWaitFor(self: *InputHandler) Command {
        var buffer: [4]u8 = undefined;
        while (true) {
            if (self.timer.read() < self.poll_interval_ms * npm) {
                std.Thread.sleep(self.poll_interval_ms * npm);
            }
            const n = self.raw.read(&buffer) catch @panic("Unable to read from tty");
            const read = buffer[0..n];
            for (self.keymaps) |keymap| {
                if (std.mem.startsWith(u8, read, keymap.key)) return keymap.command;
            }
        }
    }
};
