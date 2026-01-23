const std = @import("std");
const cc = std.ascii.control_code;
const b64Encoder = std.base64.standard_no_pad.Encoder;
/// https://sw.kovidgoyal.net/kitty/graphics-protocol/#control-data-reference
pub const Image = struct {
    pub fn filePath(self: *Image, path: []const u8) void {
        self.path = path;
    }
    pub fn write(self: *Image, w: *std.io.Writer) !void {
        try w.writeAll(.{@as(u8, cc.esc)} ++ "_G");
        inline for (@typeInfo(@FieldType(Image, "params")).@"struct".fields) |field| {
            const value = @field(self.params, field.name);
            if (value != @field(Image.default.params, field.name)) {
                const fmt = Image.Params.Format(@TypeOf(value), value);
                try w.print(field.name ++ "={f},", .{fmt});
            }
        }
        try w.writeAll("p=0");
        try w.writeByte(';');
        try b64Encoder.encodeWriter(w, self.path);
        try w.writeAll(.{@as(u8, cc.esc)} ++ "\\");
        try w.flush();
    }
    pub const default = Image{
        .path = "",
        // zig fmt: off
        .params = .{
            .a = 't', .q = 0,
            // Keys for image transmission
            .f = 32, .t = 'd', .s = 0, 
            .v = 0, .S = 0, .O = 0, 
            .i = 0, .I = 0, .p = 0,
            .o = 0, .m = 0,
            // Keys for image display
            .x = 0, .y = 0, .w = 0,
            .h = 0, .X = 0, .Y = 0,
            .c = 0, .r = 0, .C = 0,
            .U = 0, .z = 0, .P = 0,
            .Q = 0, .H = 0, .V = 0,
        },
        // zig fmt: on
    };
    path: []const u8,
    params: Params,
    const Params = struct {
        // zig fmt: off
        a: u8, q: u8,
        // Keys for image transmission
        f: usize, t: u8, s: usize,
        v: usize, S: usize, O: usize,
        i: usize, I: usize, p: usize,
        o: u1, m: u1,
        // Keys for image display
        x: usize, y: usize, w: usize,
        h: usize, X: usize, Y: usize,
        c: usize, r: usize, C: usize,
        U: usize, z: usize, P: usize,
        Q: usize, H: usize, V: usize,
        // zig fmt: on

        fn _char(value: u8, w: *std.io.Writer) error{WriteFailed}!void {
            try w.print("{c}", .{value});
        }
        fn _int(value: usize, w: *std.io.Writer) error{WriteFailed}!void {
            try w.print("{d}", .{value});
        }
        fn _u1(value: u1, w: *std.io.Writer) error{WriteFailed}!void {
            try w.print("{d}", .{value});
        }
        fn _usize(value: usize, w: *std.io.Writer) error{WriteFailed}!void {
            try w.print("{d}", .{value});
        }
        fn FormatFn(T: type) fn (T, *std.io.Writer) error{WriteFailed}!void {
            return switch (T) {
                u8 => _char,
                u1 => _u1,
                usize => _usize,
                else => unreachable,
            };
        }
        fn Format(T: type, value: T) std.fmt.Alt(T, FormatFn(T)) {
            return .{ .data = value };
        }
    };
};
