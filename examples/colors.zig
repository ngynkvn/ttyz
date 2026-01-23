//! Color showcase example
//!
//! Demonstrates 16, 256, and true color support along with text styles.

const std = @import("std");
const ttyz = @import("ttyz");
const E = ttyz.E;

pub fn main(_: std.process.Init) !void {
    var screen = try ttyz.Screen.init();
    defer _ = screen.deinit() catch {};

    try screen.clearScreen();
    try screen.home();

    // Title
    try screen.print(E.BOLD ++ E.FG_CYAN ++ "Color Showcase" ++ E.RESET_STYLE ++ "\r\n\r\n", .{});

    // 16 basic colors - foreground
    try screen.print(E.BOLD ++ "16 Basic Colors (Foreground):" ++ E.RESET_STYLE ++ "\r\n  ", .{});
    inline for (.{ E.FG_BLACK, E.FG_RED, E.FG_GREEN, E.FG_YELLOW, E.FG_BLUE, E.FG_MAGENTA, E.FG_CYAN, E.FG_WHITE }) |fg| {
        try screen.print(fg ++ "ABC" ++ E.RESET_STYLE ++ " ", .{});
    }
    try screen.print("\r\n  ", .{});
    inline for (.{ E.FG_BRIGHT_BLACK, E.FG_BRIGHT_RED, E.FG_BRIGHT_GREEN, E.FG_BRIGHT_YELLOW, E.FG_BRIGHT_BLUE, E.FG_BRIGHT_MAGENTA, E.FG_BRIGHT_CYAN, E.FG_BRIGHT_WHITE }) |fg| {
        try screen.print(fg ++ "ABC" ++ E.RESET_STYLE ++ " ", .{});
    }
    try screen.print("\r\n\r\n", .{});

    // 16 basic colors - background
    try screen.print(E.BOLD ++ "16 Basic Colors (Background):" ++ E.RESET_STYLE ++ "\r\n  ", .{});
    inline for (.{ E.BG_BLACK, E.BG_RED, E.BG_GREEN, E.BG_YELLOW, E.BG_BLUE, E.BG_MAGENTA, E.BG_CYAN, E.BG_WHITE }) |bg| {
        try screen.print(bg ++ "   " ++ E.RESET_STYLE, .{});
    }
    try screen.print("\r\n  ", .{});
    inline for (.{ E.BG_BRIGHT_BLACK, E.BG_BRIGHT_RED, E.BG_BRIGHT_GREEN, E.BG_BRIGHT_YELLOW, E.BG_BRIGHT_BLUE, E.BG_BRIGHT_MAGENTA, E.BG_BRIGHT_CYAN, E.BG_BRIGHT_WHITE }) |bg| {
        try screen.print(bg ++ "   " ++ E.RESET_STYLE, .{});
    }
    try screen.print("\r\n\r\n", .{});

    // 256 colors
    try screen.print(E.BOLD ++ "256 Color Palette:" ++ E.RESET_STYLE ++ "\r\n", .{});

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
    try screen.print(E.BOLD ++ "True Color (24-bit):" ++ E.RESET_STYLE ++ "\r\n", .{});

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
    try screen.print(E.BOLD ++ "Text Styles:" ++ E.RESET_STYLE ++ "\r\n", .{});
    try screen.print("  " ++ E.BOLD ++ "Bold" ++ E.RESET_STYLE ++ "  ", .{});
    try screen.print(E.DIM ++ "Dim" ++ E.RESET_STYLE ++ "  ", .{});
    try screen.print(E.ITALIC ++ "Italic" ++ E.RESET_STYLE ++ "  ", .{});
    try screen.print(E.UNDERLINE ++ "Underline" ++ E.RESET_STYLE ++ "  ", .{});
    try screen.print(E.REVERSE ++ "Reverse" ++ E.RESET_STYLE ++ "  ", .{});
    try screen.print(E.STRIKETHROUGH ++ "Strike" ++ E.RESET_STYLE ++ "\r\n\r\n", .{});

    // Example colored output
    try screen.print(E.BOLD ++ "Example Colored Output:" ++ E.RESET_STYLE ++ "\r\n", .{});
    try screen.print("  " ++ E.FG_GREEN ++ "Success:" ++ E.RESET_STYLE ++ " Operation completed\r\n", .{});
    try screen.print("  " ++ E.FG_YELLOW ++ "Warning:" ++ E.RESET_STYLE ++ " Check configuration\r\n", .{});
    try screen.print("  " ++ E.FG_RED ++ "Error:" ++ E.RESET_STYLE ++ " Something went wrong\r\n", .{});
    try screen.print("  " ++ E.BG_BLUE ++ E.FG_WHITE ++ E.BOLD ++ " INFO " ++ E.RESET_STYLE ++ " Background + foreground + style\r\n", .{});
    try screen.print("  " ++ E.ITALIC ++ E.FG_CYAN ++ "Styled " ++ E.FG_MAGENTA ++ "rainbow " ++ E.FG_YELLOW ++ "text" ++ E.RESET_STYLE ++ "\r\n\r\n", .{});

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
