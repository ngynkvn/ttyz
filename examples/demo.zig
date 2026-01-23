const std = @import("std");
const ttyz = @import("ttyz");
const ansi = ttyz.ansi;
const E = ttyz.E; // Keep for GOTO and format strings
const termdraw = ttyz.termdraw;
const text = ttyz.text;

const Demo = struct {
    screen: *ttyz.Screen,
    current_tab: Tab = .overview,
    mouse_pos: struct { row: usize = 0, col: usize = 0 } = .{},
    click_count: usize = 0,
    key_history: [8]u8 = .{' '} ** 8,
    key_idx: usize = 0,
    color_offset: u8 = 0,
    frame: usize = 0,

    const Tab = enum { overview, colors, events, boxes, text_demo };
    const tabs = [_]Tab{ .overview, .colors, .events, .boxes, .text_demo };

    fn tabName(t: Tab) []const u8 {
        return switch (t) {
            .overview => "Overview",
            .colors => "Colors",
            .events => "Events",
            .boxes => "Boxes",
            .text_demo => "Text",
        };
    }

    fn nextTab(self: *Demo) void {
        const idx = @intFromEnum(self.current_tab);
        self.current_tab = tabs[(idx + 1) % tabs.len];
    }

    fn prevTab(self: *Demo) void {
        const idx = @intFromEnum(self.current_tab);
        self.current_tab = tabs[(idx + tabs.len - 1) % tabs.len];
    }

    fn recordKey(self: *Demo, key: u8) void {
        self.key_history[self.key_idx] = key;
        self.key_idx = (self.key_idx + 1) % self.key_history.len;
    }

    fn render(self: *Demo) !void {
        const s = self.screen;
        try s.home();

        // Draw header
        try self.drawHeader();

        // Draw tab bar
        try self.drawTabBar();

        // Draw content based on current tab
        switch (self.current_tab) {
            .overview => try self.drawOverview(),
            .colors => try self.drawColors(),
            .events => try self.drawEvents(),
            .boxes => try self.drawBoxes(),
            .text_demo => try self.drawTextDemo(),
        }

        // Draw footer
        try self.drawFooter();

        self.frame +%= 1;
    }

    fn drawHeader(self: *Demo) !void {
        const s = self.screen;
        const title = " ttyz Demo ";
        const padding = (s.width -| @as(u16, @intCast(title.len))) / 2;

        try s.print(ansi.bg.blue ++ ansi.fg.white ++ ansi.bold, .{});

        // Fill line with spaces
        var i: u16 = 0;
        while (i < s.width) : (i += 1) {
            try s.print(" ", .{});
        }

        try s.print(E.GOTO, .{ @as(u16, 1), padding });
        try s.print("{s}" ++ ansi.reset ++ "\r\n", .{title});
    }

    fn drawTabBar(self: *Demo) !void {
        const s = self.screen;
        try s.print(E.GOTO, .{ @as(u16, 3), @as(u16, 1) });

        for (tabs) |t| {
            const is_active = t == self.current_tab;
            if (is_active) {
                try s.print(ansi.bg.white ++ ansi.fg.black ++ ansi.bold, .{});
            } else {
                try s.print(ansi.faint, .{});
            }
            try s.print(" {s} " ++ ansi.reset ++ " ", .{tabName(t)});
        }
        try s.print("\r\n", .{});
    }

    fn drawOverview(self: *Demo) !void {
        const s = self.screen;
        const start_row: u16 = 5;

        try s.print(E.GOTO ++ ansi.bold ++ "Welcome to ttyz!" ++ ansi.reset ++ "\r\n", .{ start_row, @as(u16, 3) });

        const features = [_][]const u8{
            "A Zig library for terminal user interfaces",
            "",
            "Features:",
            "  * Raw mode terminal I/O with auto-restore",
            "  * Keyboard, mouse, and focus events",
            "  * Box drawing with Unicode characters",
            "  * 16, 256, and true color support",
            "  * Text utilities (padding, centering)",
            "  * Immediate-mode layout engine",
            "  * Kitty graphics protocol support",
            "",
            "Navigation:",
            "  Tab / Shift+Tab  - Switch tabs",
            "  Arrow keys       - Navigate",
            "  q / Esc          - Quit",
        };

        for (features, 0..) |line, i| {
            try s.print(E.GOTO ++ "{s}\r\n", .{ start_row + 2 + @as(u16, @intCast(i)), @as(u16, 5), line });
        }

        // Animated spinner
        const spinners = [_][]const u8{ "|", "/", "-", "\\" };
        const spinner = spinners[(self.frame / 8) % spinners.len];
        try s.print(E.GOTO ++ ansi.fg.cyan ++ "{s}" ++ ansi.reset, .{ start_row + 2, @as(u16, 3), spinner });
    }

    fn drawColors(self: *Demo) !void {
        const s = self.screen;
        const start_row: u16 = 5;

        // 16 basic colors
        try s.print(E.GOTO ++ ansi.bold ++ "16 Basic Colors:" ++ ansi.reset ++ "\r\n", .{ start_row, @as(u16, 3) });

        try s.print(E.GOTO, .{ start_row + 1, @as(u16, 3) });
        const bg_colors = [_][]const u8{ ansi.bg.black, ansi.bg.red, ansi.bg.green, ansi.bg.yellow, ansi.bg.blue, ansi.bg.magenta, ansi.bg.cyan, ansi.bg.white };

        for (bg_colors) |bg| {
            try s.print("{s}  " ++ ansi.reset, .{bg});
        }
        try s.print("  Normal\r\n", .{});

        try s.print(E.GOTO, .{ start_row + 2, @as(u16, 3) });
        const bright_bg = [_][]const u8{ ansi.bg.bright_black, ansi.bg.bright_red, ansi.bg.bright_green, ansi.bg.bright_yellow, ansi.bg.bright_blue, ansi.bg.bright_magenta, ansi.bg.bright_cyan, ansi.bg.bright_white };
        for (bright_bg) |bg| {
            try s.print("{s}  " ++ ansi.reset, .{bg});
        }
        try s.print("  Bright\r\n", .{});

        // 256 color palette
        try s.print(E.GOTO ++ ansi.bold ++ "\r\n256 Color Palette:" ++ ansi.reset ++ "\r\n", .{ start_row + 4, @as(u16, 3) });

        // Standard colors (0-15)
        try s.print(E.GOTO, .{ start_row + 5, @as(u16, 3) });
        var c: u8 = 0;
        while (c < 16) : (c += 1) {
            const color = (c +% self.color_offset) % 16;
            try s.print(E.SET_BG_256 ++ " " ++ E.RESET_STYLE, .{color});
        }

        // 216 colors (16-231) - show a slice
        try s.print(E.GOTO, .{ start_row + 6, @as(u16, 3) });
        c = 16;
        const offset = self.color_offset % 36;
        while (c < 16 + 36) : (c += 1) {
            const color = 16 + ((c - 16 + offset) % 216);
            try s.print(E.SET_BG_256 ++ " " ++ E.RESET_STYLE, .{color});
        }

        // Grayscale (232-255)
        try s.print(E.GOTO, .{ start_row + 7, @as(u16, 3) });
        for (232..256) |gray| {
            try s.print(E.SET_BG_256 ++ " " ++ E.RESET_STYLE, .{gray});
        }

        // True color gradient
        try s.print(E.GOTO ++ ansi.bold ++ "\r\nTrue Color (24-bit):" ++ ansi.reset ++ "\r\n", .{ start_row + 9, @as(u16, 3) });

        try s.print(E.GOTO, .{ start_row + 10, @as(u16, 3) });
        var x: u8 = 0;
        while (x < 64) : (x += 1) {
            const r = x * 4;
            const g: u8 = 128;
            const b = 255 - x * 4;
            try s.print(E.SET_TRUCOLOR_BG ++ " " ++ E.RESET_STYLE, .{ r, g, b });
        }

        // Text styles
        try s.print(E.GOTO ++ ansi.bold ++ "\r\nText Styles:" ++ ansi.reset ++ "\r\n", .{ start_row + 12, @as(u16, 3) });
        try s.print(E.GOTO, .{ start_row + 13, @as(u16, 3) });
        try s.print(ansi.bold ++ "Bold" ++ ansi.reset ++ "  ", .{});
        try s.print(ansi.faint ++ "Dim" ++ ansi.reset ++ "  ", .{});
        try s.print(ansi.italic ++ "Italic" ++ ansi.reset ++ "  ", .{});
        try s.print(ansi.underline ++ "Underline" ++ ansi.reset ++ "  ", .{});
        try s.print(ansi.reverse ++ "Reverse" ++ ansi.reset ++ "  ", .{});
        try s.print(ansi.crossed_out ++ "Strike" ++ ansi.reset, .{});

        // Animate color offset
        if (self.frame % 4 == 0) {
            self.color_offset +%= 1;
        }
    }

    fn drawEvents(self: *Demo) !void {
        const s = self.screen;
        const start_row: u16 = 5;

        try s.print(E.GOTO ++ ansi.bold ++ "Event Tracking:" ++ ansi.reset ++ "\r\n", .{ start_row, @as(u16, 3) });

        // Mouse position
        try s.print(E.GOTO ++ "Mouse Position: " ++ ansi.fg.green ++ "({}, {})" ++ ansi.reset ++ "    \r\n", .{ start_row + 2, @as(u16, 5), self.mouse_pos.row, self.mouse_pos.col });

        // Click count
        try s.print(E.GOTO ++ "Click Count:    " ++ ansi.fg.yellow ++ "{}" ++ ansi.reset ++ "    \r\n", .{ start_row + 3, @as(u16, 5), self.click_count });

        // Key history
        try s.print(E.GOTO ++ "Recent Keys:    " ++ ansi.fg.cyan, .{ start_row + 4, @as(u16, 5) });
        for (self.key_history) |k| {
            if (std.ascii.isPrint(k)) {
                try s.print("[{c}] ", .{k});
            } else {
                try s.print("[?] ", .{});
            }
        }
        try s.print(ansi.reset ++ "\r\n", .{});

        // Instructions
        try s.print(E.GOTO ++ ansi.faint ++ "Move your mouse, click, and press keys to see events" ++ ansi.reset, .{ start_row + 6, @as(u16, 5) });

        // Draw clickable button
        const btn_row = start_row + 9;
        const btn_col: u16 = 10;
        try s.print(E.GOTO ++ ansi.bg.blue ++ ansi.fg.white ++ " Click Me! " ++ ansi.reset, .{ btn_row, btn_col });

        // Show if mouse is over button
        if (self.mouse_pos.row == btn_row and self.mouse_pos.col >= btn_col and self.mouse_pos.col < btn_col + 12) {
            try s.print(E.GOTO ++ ansi.fg.green ++ " <-- Hovering!" ++ ansi.reset, .{ btn_row, btn_col + 12 });
        }
    }

    fn drawBoxes(self: *Demo) !void {
        const s = self.screen;

        // Draw several boxes
        try termdraw.box(&s.writer.interface, .{
            .x = 3,
            .y = 5,
            .width = 20,
            .height = 8,
            .color = .{ 255, 100, 100, 255 },
        });

        try termdraw.box(&s.writer.interface, .{
            .x = 25,
            .y = 5,
            .width = 20,
            .height = 8,
            .color = .{ 100, 255, 100, 255 },
        });

        try termdraw.box(&s.writer.interface, .{
            .x = 47,
            .y = 5,
            .width = 20,
            .height = 8,
            .color = .{ 100, 100, 255, 255 },
        });

        // Labels inside boxes
        try s.print(E.GOTO ++ ansi.fg.red ++ "Red Box" ++ ansi.reset, .{ @as(u16, 8), @as(u16, 9) });
        try s.print(E.GOTO ++ ansi.fg.green ++ "Green Box" ++ ansi.reset, .{ @as(u16, 8), @as(u16, 30) });
        try s.print(E.GOTO ++ ansi.fg.blue ++ "Blue Box" ++ ansi.reset, .{ @as(u16, 8), @as(u16, 53) });

        // Nested box
        try termdraw.box(&s.writer.interface, .{
            .x = 3,
            .y = 14,
            .width = 30,
            .height = 6,
            .color = .{ 255, 255, 0, 255 },
        });

        try termdraw.box(&s.writer.interface, .{
            .x = 5,
            .y = 15,
            .width = 26,
            .height = 4,
            .color = .{ 255, 128, 0, 255 },
        });

        try s.print(E.GOTO ++ "Nested boxes!", .{ @as(u16, 16), @as(u16, 10) });

        // Horizontal and vertical lines
        try termdraw.hline(&s.writer.interface, .{ .x = 40, .y = 14, .width = 25 });
        try termdraw.vline(&s.writer.interface, .{ .x = 52, .y = 14, .height = 6 });

        try s.print(E.GOTO ++ "Lines", .{ @as(u16, 15), @as(u16, 54) });
    }

    fn drawTextDemo(self: *Demo) !void {
        const s = self.screen;
        const start_row: u16 = 5;

        try s.print(E.GOTO ++ ansi.bold ++ "Text Utilities:" ++ ansi.reset ++ "\r\n", .{ start_row, @as(u16, 3) });

        // Padding demo
        var buf: [40]u8 = undefined;

        try s.print(E.GOTO ++ "padRight(\"Hello\", 20):", .{ start_row + 2, @as(u16, 3) });
        const padded_right = text.padRight("Hello", 20, &buf);
        try s.print(E.GOTO ++ ansi.bg.bright_black ++ "{s}" ++ ansi.reset ++ "|", .{ start_row + 2, @as(u16, 28), padded_right });

        try s.print(E.GOTO ++ "padLeft(\"Hello\", 20):", .{ start_row + 3, @as(u16, 3) });
        const padded_left = text.padLeft("Hello", 20, &buf);
        try s.print(E.GOTO ++ "|" ++ ansi.bg.bright_black ++ "{s}" ++ ansi.reset, .{ start_row + 3, @as(u16, 27), padded_left });

        // Display width
        try s.print(E.GOTO ++ "displayWidth(\"Hello\"):  {}", .{ start_row + 5, @as(u16, 3), text.displayWidth("Hello") });
        try s.print(E.GOTO ++ "displayWidth(\"\"): {}", .{ start_row + 6, @as(u16, 3), text.displayWidth("") });

        // Repeat
        try s.print(E.GOTO ++ "repeat('-', 30):", .{ start_row + 8, @as(u16, 3) });
        const repeated = text.repeat('-', 30, &buf);
        try s.print(E.GOTO ++ ansi.fg.cyan ++ "{s}" ++ ansi.reset, .{ start_row + 8, @as(u16, 22), repeated });

        // Colorz demo
        try s.print(E.GOTO ++ ansi.bold ++ "\r\nColorz Format Strings:" ++ ansi.reset, .{ start_row + 10, @as(u16, 3) });

        var clr = ttyz.colorz.wrap(&s.writer.interface);
        try s.print(E.GOTO, .{ start_row + 11, @as(u16, 3) });
        try clr.print("@[.green]Success@[.reset]: @[.bold]Operation complete@[.reset]", .{});

        try s.print(E.GOTO, .{ start_row + 12, @as(u16, 3) });
        try clr.print("@[.red]Error@[.reset]: @[.dim]Something went wrong@[.reset]", .{});

        try s.print(E.GOTO, .{ start_row + 13, @as(u16, 3) });
        try clr.print("@[.yellow]Warning@[.reset]: @[.cyan]Check your input@[.reset]", .{});
    }

    fn drawFooter(self: *Demo) !void {
        const s = self.screen;
        const footer_row = s.height;

        try s.print(E.GOTO ++ ansi.bg.bright_black ++ ansi.fg.white, .{ footer_row, @as(u16, 1) });

        // Fill line
        var i: u16 = 0;
        while (i < s.width) : (i += 1) {
            try s.print(" ", .{});
        }

        try s.print(E.GOTO ++ " Tab: Switch | q: Quit | Screen: {}x{} | Frame: {} ", .{ footer_row, @as(u16, 1), s.width, s.height, self.frame });
        try s.print(ansi.reset, .{});
    }
};

pub fn main(init: std.process.Init) !void {
    var s = try ttyz.Screen.init();
    defer _ = s.deinit() catch {};

    try s.start();

    var demo = Demo{ .screen = &s };

    while (s.running) {
        // Handle events
        while (s.pollEvent()) |event| {
            switch (event) {
                .key => |key| {
                    switch (key) {
                        .q, .Q, .esc => s.running = false,
                        .tab => demo.nextTab(),
                        else => {
                            const key_val = @intFromEnum(key);
                            if (key_val < 128) {
                                demo.recordKey(@intCast(key_val));
                            }
                        },
                    }
                },
                .mouse => |mouse| {
                    demo.mouse_pos.row = mouse.row;
                    demo.mouse_pos.col = mouse.col;
                    if (mouse.button_state == .pressed) {
                        demo.click_count += 1;
                    }
                },
                .interrupt => s.running = false,
                else => {},
            }
        }

        // Clear and render
        try s.clearScreen();
        try demo.render();
        try s.flush();

        // ~30 FPS
        init.io.sleep(std.Io.Duration.fromMilliseconds(33), .awake) catch {};
    }
}

pub const std_options: std.Options = .{
    .log_level = .info,
};
