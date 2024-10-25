const std = @import("std");
const E = @import("escseq.zig");

const posix = std.posix;
const system = posix.system;

// Disable tty's SIGINT handling,
const START_SEQUENCE = E.ENTER_ALT_SCREEN ++ E.CURSOR_INVISIBLE;
const EXIT_SEQUENCE = E.EXIT_ALT_SCREEN ++ E.CURSOR_VISIBLE;
const TTY_HANDLE = "/dev/tty";

// Your main interface to the terminal
pub const Terminal = struct {
    orig_termios: posix.termios,
    tty: std.fs.File,
    width: u16,
    height: u16,
    buffer: std.ArrayList(u8),
    pub const Error = std.posix.WriteError;
    pub const CursorPos = struct { row: usize, col: usize };
    pub const FlagOpts = struct {
        // zig fmt: off
        const ECHO   = false;  // Disable echo input
        const ICANON = false;  // Read byte by byte
        const IEXTEN = false;  // Disable <C-v>
        const ISIG   = false;  // Disable <C-c> and <C-z>
        const IXON   = false;  // Disable <C-s> and <C-q>
        const ICRNL  = false;  // Disable <C-m>
        const BRKINT = false;  // Break condition sends SIGINT
        const INPCK  = false;  // Enable parity checking
        const ISTRIP = false;  // Strip 8th bit of input byte
        const OPOST  = false;  // Disable translating "\n" to "\r\n"
        const CSIZE  = .CS8;
        const MIN    = 1;
        const TIME   = 0;
        // zig fmt: on
    };

    /// Enter "raw mode", returning a struct that wraps around the provided tty file
    /// Entering raw mode will automatically send the sequence for entering an
    /// alternate screen (smcup) and hiding the cursor.
    /// Use `defer Terminal.deinit()` to reset on exit.
    /// Deferral will set the sequence for exiting alt screen (rmcup)
    ///
    /// Explanation here: https://viewsourcecode.org/snaptoken/kilo/02.enteringRawMode.html
    /// https://zig.news/lhp/want-to-create-a-tui-application-the-basics-of-uncooked-terminal-io-17gm
    pub fn init(allocator: std.mem.Allocator, flags: FlagOpts) !Terminal {
        const tty = try std.fs.openFileAbsolute(TTY_HANDLE, .{ .mode = .read_write });
        if (!tty.isTty()) {
            return error.NotATty;
        }
        const orig_termios = try posix.tcgetattr(tty.handle);
        var raw = orig_termios;
        _ = flags;
        // Some explanation of the flags can be found in the links above.
        // zig fmt: off
        raw.lflag.ECHO   = false;                 // Disable echo input
        raw.lflag.ICANON = false;                 // Read byte by byte
        raw.lflag.IEXTEN = false;                 // Disable <C-v>
        raw.lflag.ISIG   = false;                 // Disable <C-c> and <C-z>
        raw.iflag.IXON   = false;                 // Disable <C-s> and <C-q>
        raw.iflag.ICRNL  = false;                 // Disable <C-m>
        raw.iflag.BRKINT = false;                 // Break condition sends SIGINT
        raw.iflag.INPCK  = false;                 // Enable parity checking
        raw.iflag.ISTRIP = false;                 // Strip 8th bit of input byte
        raw.oflag.OPOST  = false;                 // Disable translating "\n" to "\r\n"
        raw.cflag.CSIZE  = .CS8;

        raw.cc[@intFromEnum(system.V.MIN)]  = 0;  // min bytes required for read
        raw.cc[@intFromEnum(system.V.TIME)] = 0;  // min time to wait for response, 100ms per unit
        // zig fmt: on

        const rc = system.tcsetattr(tty.handle, .FLUSH, &raw);
        if (posix.errno(rc) != .SUCCESS) return error.CouldNotSetTermiosFlags;

        // IOCGWINSZ (io control get window size (?)) is a request signal for window size
        var ws: posix.winsize = .{ .row = 0, .col = 0, .xpixel = 0, .ypixel = 0 };
        // Get the window size via ioctl(2) call to tty
        const result = system.ioctl(tty.handle, posix.T.IOCGWINSZ, @intFromPtr(&ws));
        if (posix.errno(result) != .SUCCESS) return error.IoctlReturnedNonZero;

        const width = ws.col;
        const height = ws.row;
        std.log.debug("windowsize is {}x{}", .{ width, height });
        _ = try tty.write(START_SEQUENCE);
        const buffer = std.ArrayList(u8).init(allocator);
        const term = .{
            .orig_termios = orig_termios,
            .tty = tty,
            .width = width,
            .height = height,
            .buffer = buffer,
        };
        return term;
    }
    pub fn deinit(self: *Terminal) void {
        defer self.buffer.deinit();
        _ = self.tty.write(EXIT_SEQUENCE) catch |e| std.log.err("error writing exit codes: {}", .{e});
        const rc = system.tcsetattr(self.tty.handle, .FLUSH, &self.orig_termios);
        if (posix.errno(rc) != .SUCCESS) std.log.err("error calling tcsetattr: {}", .{posix.errno(rc)});
    }

    /// Start writing to terminal with escape sequences. Fluent builder pattern.
    pub fn esc(self: *Terminal) EscBuilder {
        return EscBuilder{
            .term = self,
        };
    }
    /// TODO: collect errors and return on flush?
    pub const EscBuilder = struct {
        term: *Terminal,
        pub fn goto(self: EscBuilder, r: usize, c: usize) EscBuilder {
            self.term.print(E.GOTO, .{ r, c }) catch {};
            return self;
        }
        /// print to screen via fmt string
        pub fn print(self: EscBuilder, comptime fmt: []const u8, args: anytype) EscBuilder {
            self.term.printArgs(fmt, args, .{}) catch {};
            return self;
        }

        /// raw write
        pub fn write(self: EscBuilder, buf: []const u8) EscBuilder {
            _ = self.term.write(buf) catch {};
            return self;
        }
        /// example: `term.esc().ansi(&.{ .fg(.black), .bg(.green) })`
        pub fn ansi(self: EscBuilder, comptime mod: []const E.AnsiModifier) EscBuilder {
            self.term.ansi(mod) catch {};
            return self;
        }
        pub fn color(self: EscBuilder, comptime color_enum: E.AnsiColor) EscBuilder {
            self.term.color(color_enum) catch {};
            return self;
        }
        pub fn color24(self: EscBuilder, hex: u24) EscBuilder {
            self.term.color24(hex) catch {};
            return self;
        }
        pub fn sgr0(self: EscBuilder) EscBuilder {
            self.term.sgr0() catch {};
            return self;
        }
        pub fn flush(self: EscBuilder) !void {
            return self.term.flush();
        }
    };

    /// origin based on top left (row, col)
    pub fn goto(self: *Terminal, r: usize, c: usize) !void {
        return try self.print(E.GOTO, .{ r, c });
    }
    pub fn color(self: *Terminal, comptime color_enum: E.AnsiColor) !void {
        _ = try self.write(color_enum.esc());
    }
    fn join_modifiers(comptime mod: []const E.AnsiModifier) []const u8 {
        var buffer: []const u8 = "";
        for (mod) |m| {
            buffer = buffer ++ m.escseq;
        }
        return buffer;
    }
    pub fn ansi(self: *Terminal, comptime mod: []const E.AnsiModifier) !void {
        const buffer = comptime join_modifiers(mod);
        _ = try self.write(buffer);
    }
    pub fn color24(self: *Terminal, hex: u24) !void {
        const RGB = packed struct(u24) { r: u8, g: u8, b: u8 };
        const rgb: RGB = @bitCast(hex);
        return self.print(E.SET_ANSI24_FG, .{ rgb.r, rgb.g, rgb.b });
    }
    pub fn sgr0(self: *Terminal) !void {
        _ = try self.write(E.RESET_COLORS);
    }

    pub fn query(self: *Terminal) !CursorPos {
        _ = try self.tty.write(E.REPORT_CURSOR_POS);
        // TODO: make this more durable?
        var buf: [32]u8 = undefined;
        const n = try self.tty.read(&buf);
        if (!std.mem.startsWith(u8, &buf, E.ESC)) return error.UnknownResponse;
        const semi = std.mem.indexOf(u8, &buf, ";") orelse return error.ParseError;
        const row = try std.fmt.parseUnsigned(usize, buf[2..semi], 10);
        const col = try std.fmt.parseUnsigned(usize, buf[semi + 1 .. n - 1], 10);
        return .{ .row = row, .col = col };
    }

    /// read input
    pub fn read(self: *Terminal, buffer: []u8) !usize {
        return self.tty.read(buffer);
    }
    /// raw write
    pub fn write(self: *Terminal, buf: []const u8) !usize {
        return self.buffer.writer().write(buf);
    }
    /// raw write
    pub fn clear(self: *Terminal) !usize {
        return self.buffer.writer().write(E.CLEAR_SCREEN);
    }

    /// print to screen via fmt string
    pub fn print(self: *Terminal, comptime fmt: []const u8, args: anytype) !void {
        return self.printArgs(fmt, args, .{});
    }

    pub const WriteArgs = struct { cursor: enum { Stay, Restore } = .Stay, sleep: usize = 0 };
    pub fn printArgs(self: *Terminal, comptime fmt: []const u8, args: anytype, wargs: WriteArgs) !void {
        _ = if (wargs.cursor == .Restore) try self.buffer.writer().write(E.CURSOR_SAVE_POS);
        try self.buffer.writer().print(fmt, args);
        _ = if (wargs.cursor == .Restore) try self.buffer.writer().write(E.CURSOR_RESTORE_POS);
    }

    pub fn flush(self: *Terminal) !void {
        try self.tty.writeAll(self.buffer.items);
        self.buffer.clearRetainingCapacity();
    }
};
