//! Color showcase example
//!
//! Demonstrates 16, 256, and true color support along with text styles.

const std = @import("std");
const ttyz = @import("ttyz");
const E = ttyz.E;
const colorz = ttyz.colorz;

pub fn main() !void {
    var screen = try ttyz.Screen.init();
    defer _ = screen.deinit() catch {};

    try screen.clearScreen();
    try screen.home();

    var clr = colorz.wrap(&screen.writer.interface);

    // Title
    try clr.print("@[.bold]@[.cyan]Color Showcase@[.reset]\n\n", .{});

    // 16 basic colors - foreground
    try clr.print("@[.bold]16 Basic Colors (Foreground):@[.reset]\n  ", .{});
    inline for (.{ E.FG_BLACK, E.FG_RED, E.FG_GREEN, E.FG_YELLOW, E.FG_BLUE, E.FG_MAGENTA, E.FG_CYAN, E.FG_WHITE }) |fg| {
        try screen.print(fg ++ "ABC" ++ E.RESET_STYLE ++ " ", .{});
    }
    try screen.print("\n  ", .{});
    inline for (.{ E.FG_BRIGHT_BLACK, E.FG_BRIGHT_RED, E.FG_BRIGHT_GREEN, E.FG_BRIGHT_YELLOW, E.FG_BRIGHT_BLUE, E.FG_BRIGHT_MAGENTA, E.FG_BRIGHT_CYAN, E.FG_BRIGHT_WHITE }) |fg| {
        try screen.print(fg ++ "ABC" ++ E.RESET_STYLE ++ " ", .{});
    }
    try screen.print("\n\n", .{});

    // 16 basic colors - background
    try clr.print("@[.bold]16 Basic Colors (Background):@[.reset]\n  ", .{});
    inline for (.{ E.BG_BLACK, E.BG_RED, E.BG_GREEN, E.BG_YELLOW, E.BG_BLUE, E.BG_MAGENTA, E.BG_CYAN, E.BG_WHITE }) |bg| {
        try screen.print(bg ++ "   " ++ E.RESET_STYLE, .{});
    }
    try screen.print("\n  ", .{});
    inline for (.{ E.BG_BRIGHT_BLACK, E.BG_BRIGHT_RED, E.BG_BRIGHT_GREEN, E.BG_BRIGHT_YELLOW, E.BG_BRIGHT_BLUE, E.BG_BRIGHT_MAGENTA, E.BG_BRIGHT_CYAN, E.BG_BRIGHT_WHITE }) |bg| {
        try screen.print(bg ++ "   " ++ E.RESET_STYLE, .{});
    }
    try screen.print("\n\n", .{});

    // 256 colors
    try clr.print("@[.bold]256 Color Palette:@[.reset]\n", .{});

    // Standard colors (0-15)
    try screen.print("  Standard (0-15):   ", .{});
    var c: u8 = 0;
    while (c < 16) : (c += 1) {
        try screen.print(E.SET_BG_256 ++ "  " ++ E.RESET_STYLE, .{c});
    }
    try screen.print("\n", .{});

    // Color cube (16-231) - show slices
    try screen.print("  Color cube slice:  ", .{});
    c = 16;
    while (c < 52) : (c += 1) {
        try screen.print(E.SET_BG_256 ++ " " ++ E.RESET_STYLE, .{c});
    }
    try screen.print("\n", .{});

    // Grayscale (232-255)
    try screen.print("  Grayscale:         ", .{});
    for (232..256) |g| {
        try screen.print(E.SET_BG_256 ++ " " ++ E.RESET_STYLE, .{g});
    }
    try screen.print("\n\n", .{});

    // True color gradients
    try clr.print("@[.bold]True Color (24-bit):@[.reset]\n", .{});

    // Red gradient
    try screen.print("  Red:      ", .{});
    var i: u8 = 0;
    while (i < 32) : (i += 1) {
        const r = i * 8;
        try screen.print(E.SET_TRUCOLOR_BG ++ " " ++ E.RESET_STYLE, .{ r, @as(u8, 0), @as(u8, 0) });
    }
    try screen.print("\n", .{});

    // Rainbow gradient
    try screen.print("  Rainbow:  ", .{});
    i = 0;
    while (i < 32) : (i += 1) {
        const hue = @as(f32, @floatFromInt(i)) / 32.0;
        const rgb = hsvToRgb(hue, 1.0, 1.0);
        try screen.print(E.SET_TRUCOLOR_BG ++ " " ++ E.RESET_STYLE, .{ rgb[0], rgb[1], rgb[2] });
    }
    try screen.print("\n\n", .{});

    // Text styles
    try clr.print("@[.bold]Text Styles:@[.reset]\n", .{});
    try screen.print("  " ++ E.BOLD ++ "Bold" ++ E.RESET_STYLE ++ "  ", .{});
    try screen.print(E.DIM ++ "Dim" ++ E.RESET_STYLE ++ "  ", .{});
    try screen.print(E.ITALIC ++ "Italic" ++ E.RESET_STYLE ++ "  ", .{});
    try screen.print(E.UNDERLINE ++ "Underline" ++ E.RESET_STYLE ++ "  ", .{});
    try screen.print(E.REVERSE ++ "Reverse" ++ E.RESET_STYLE ++ "  ", .{});
    try screen.print(E.STRIKETHROUGH ++ "Strike" ++ E.RESET_STYLE ++ "\n\n", .{});

    // Colorz format strings
    try clr.print("@[.bold]Colorz Format Strings:@[.reset]\n", .{});
    try clr.print("  @[.green]Success:@[.reset] Operation completed\n", .{});
    try clr.print("  @[.yellow]Warning:@[.reset] Check configuration\n", .{});
    try clr.print("  @[.red]Error:@[.reset] Something went wrong\n", .{});
    try clr.print("  @[.bg_blue]@[.white]@[.bold] INFO @[.reset] Background + foreground + style\n", .{});
    try clr.print("  @[.italic]@[.cyan]Styled @[.magenta]rainbow @[.yellow]text@[.reset]\n\n", .{});

    // Colorz programmatic API
    try clr.print("@[.bold]Colorz Programmatic API:@[.reset]\n  ", .{});
    try clr.printColored(.green, "Green text", .{});
    try screen.print(" | ", .{});
    try clr.printStyled(.white, .red, .bold, " Alert ", .{});
    try screen.print(" | ", .{});
    try clr.setFg(.cyan);
    try clr.setStyle(.underline);
    try screen.print("Manual control", .{});
    try clr.reset();
    try screen.print("\n\n", .{});

    try screen.print("Press any key to exit...", .{});
    try screen.flush();

    _ = try screen.read(&.{});
}

/// Convert HSV to RGB (for rainbow gradient)
fn hsvToRgb(h: f32, s: f32, v: f32) [3]u8 {
    const i = @as(u32, @intFromFloat(h * 6));
    const f = h * 6 - @as(f32, @floatFromInt(i));
    const p = v * (1 - s);
    const q = v * (1 - f * s);
    const t = v * (1 - (1 - f) * s);

    const rgb: [3]f32 = switch (i % 6) {
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
