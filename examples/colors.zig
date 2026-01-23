//! Color showcase example
//!
//! Demonstrates 16, 256, and true color support along with text styles.

const std = @import("std");
const ttyz = @import("ttyz");
const ansi = ttyz.ansi;
const E = ttyz.E; // Keep for format strings (SET_BG_256, SET_TRUCOLOR_BG)

pub fn main(init: std.process.Init) !void {
    var screen = try ttyz.Screen.init(init.io);
    defer _ = screen.deinit() catch {};

    try screen.clearScreen();
    try screen.home();

    // Title
    try screen.print(ansi.bold ++ ansi.fg.cyan ++ "Color Showcase" ++ ansi.reset ++ "\r\n\r\n", .{});

    // 16 basic colors - foreground
    try screen.print(ansi.bold ++ "16 Basic Colors (Foreground):" ++ ansi.reset ++ "\r\n  ", .{});
    inline for (.{ ansi.fg.black, ansi.fg.red, ansi.fg.green, ansi.fg.yellow, ansi.fg.blue, ansi.fg.magenta, ansi.fg.cyan, ansi.fg.white }) |fg| {
        try screen.print(fg ++ "ABC" ++ ansi.reset ++ " ", .{});
    }
    try screen.print("\r\n  ", .{});
    inline for (.{ ansi.fg.bright_black, ansi.fg.bright_red, ansi.fg.bright_green, ansi.fg.bright_yellow, ansi.fg.bright_blue, ansi.fg.bright_magenta, ansi.fg.bright_cyan, ansi.fg.bright_white }) |fg| {
        try screen.print(fg ++ "ABC" ++ ansi.reset ++ " ", .{});
    }
    try screen.print("\r\n\r\n", .{});

    // 16 basic colors - background
    try screen.print(ansi.bold ++ "16 Basic Colors (Background):" ++ ansi.reset ++ "\r\n  ", .{});
    inline for (.{ ansi.bg.black, ansi.bg.red, ansi.bg.green, ansi.bg.yellow, ansi.bg.blue, ansi.bg.magenta, ansi.bg.cyan, ansi.bg.white }) |bg| {
        try screen.print(bg ++ "   " ++ ansi.reset, .{});
    }
    try screen.print("\r\n  ", .{});
    inline for (.{ ansi.bg.bright_black, ansi.bg.bright_red, ansi.bg.bright_green, ansi.bg.bright_yellow, ansi.bg.bright_blue, ansi.bg.bright_magenta, ansi.bg.bright_cyan, ansi.bg.bright_white }) |bg| {
        try screen.print(bg ++ "   " ++ ansi.reset, .{});
    }
    try screen.print("\r\n\r\n", .{});

    // 256 colors
    try screen.print(ansi.bold ++ "256 Color Palette:" ++ ansi.reset ++ "\r\n", .{});

    // Standard colors (0-15)
    try screen.print("  Standard (0-15):   ", .{});
    var c: u8 = 0;
    while (c < 16) : (c += 1) {
        try screen.print(E.SET_BG_256 ++ "  " ++ E.RESET_STYLE, .{c});
    }
    try screen.print("\r\n", .{});

    // Color cube (16-231) - show slices
    try screen.print("  Color cube slice:  ", .{});
    c = 16;
    while (c < 52) : (c += 1) {
        try screen.print(E.SET_BG_256 ++ " " ++ E.RESET_STYLE, .{c});
    }
    try screen.print("\r\n", .{});

    // Grayscale (232-255)
    try screen.print("  Grayscale:         ", .{});
    for (232..256) |g| {
        try screen.print(E.SET_BG_256 ++ " " ++ E.RESET_STYLE, .{g});
    }
    try screen.print("\r\n\r\n", .{});

    // True color gradients
    try screen.print(ansi.bold ++ "True Color (24-bit):" ++ ansi.reset ++ "\r\n", .{});

    // Red gradient
    try screen.print("  Red:      ", .{});
    var i: u8 = 0;
    while (i < 32) : (i += 1) {
        const r = i * 8;
        try screen.print(E.SET_TRUCOLOR_BG ++ " " ++ E.RESET_STYLE, .{ r, @as(u8, 0), @as(u8, 0) });
    }
    try screen.print("\r\n", .{});

    // Rainbow gradient
    try screen.print("  Rainbow:  ", .{});
    i = 0;
    while (i < 32) : (i += 1) {
        const hue = @as(f32, @floatFromInt(i)) / 32.0;
        const rgb = hsvToRgb(hue, 1.0, 1.0);
        try screen.print(E.SET_TRUCOLOR_BG ++ " " ++ E.RESET_STYLE, .{ rgb[0], rgb[1], rgb[2] });
    }
    try screen.print("\r\n\r\n", .{});

    // Text styles
    try screen.print(ansi.bold ++ "Text Styles:" ++ ansi.reset ++ "\r\n", .{});
    try screen.print("  " ++ ansi.bold ++ "Bold" ++ ansi.reset ++ "  ", .{});
    try screen.print(ansi.faint ++ "Dim" ++ ansi.reset ++ "  ", .{});
    try screen.print(ansi.italic ++ "Italic" ++ ansi.reset ++ "  ", .{});
    try screen.print(ansi.underline ++ "Underline" ++ ansi.reset ++ "  ", .{});
    try screen.print(ansi.reverse ++ "Reverse" ++ ansi.reset ++ "  ", .{});
    try screen.print(ansi.crossed_out ++ "Strike" ++ ansi.reset ++ "\r\n\r\n", .{});

    // Example colored output
    try screen.print(ansi.bold ++ "Example Colored Output:" ++ ansi.reset ++ "\r\n", .{});
    try screen.print("  " ++ ansi.fg.green ++ "Success:" ++ ansi.reset ++ " Operation completed\r\n", .{});
    try screen.print("  " ++ ansi.fg.yellow ++ "Warning:" ++ ansi.reset ++ " Check configuration\r\n", .{});
    try screen.print("  " ++ ansi.fg.red ++ "Error:" ++ ansi.reset ++ " Something went wrong\r\n", .{});
    try screen.print("  " ++ ansi.bg.blue ++ ansi.fg.white ++ ansi.bold ++ " INFO " ++ ansi.reset ++ " Background + foreground + style\r\n", .{});
    try screen.print("  " ++ ansi.italic ++ ansi.fg.cyan ++ "Styled " ++ ansi.fg.magenta ++ "rainbow " ++ ansi.fg.yellow ++ "text" ++ ansi.reset ++ "\r\n\r\n", .{});

    try screen.print("Press any key to exit...", .{});
    try screen.flush();

    var buf: [1]u8 = undefined;
    _ = try screen.read(&buf);
}

/// Convert HSV to RGB (for rainbow gradient)
fn hsvToRgb(h: f32, s: f32, v: f32) [3]u8 {
    const i_val = @as(u32, @intFromFloat(h * 6));
    const f = h * 6 - @as(f32, @floatFromInt(i_val));
    const p = v * (1 - s);
    const q = v * (1 - f * s);
    const t = v * (1 - (1 - f) * s);

    const rgb: [3]f32 = switch (i_val % 6) {
        0 => .{ v, t, p },
        1 => .{ q, v, p },
        2 => .{ p, v, t },
        3 => .{ p, q, v },
        4 => .{ t, p, v },
        else => .{ v, p, q },
    };

    return .{
        @intFromFloat(rgb[0] * 255),
        @intFromFloat(rgb[1] * 255),
        @intFromFloat(rgb[2] * 255),
    };
}
