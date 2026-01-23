const std = @import("std");
const cc = std.ascii.control_code;
/// https://sw.kovidgoyal.net/kitty/graphics-protocol/#control-data-reference
pub const Image = struct {
    pub fn setPayload(self: *Image, payload: []const u8) void {
        self.payload = payload;
    }
    pub fn filePath(self: *Image, path: []const u8) void {
        self.payload = path;
    }
    pub fn write(self: *Image, w: *std.io.Writer) !void {
        try w.writeAll(.{@as(u8, cc.esc)} ++ "_G");
        inline for (@typeInfo(@FieldType(Image, "params")).@"struct".fields) |field| {
            const value = @field(self.params, field.name);
            if (value != @field(Image.default.params, field.name)) {
                const fmt = comptime Image.Params.Format(field.name, field.type);
                try w.print(fmt, .{value});
            }
        }
        try w.writeByte(';');
        try w.printBase64(self.payload);
        try w.writeAll(.{@as(u8, cc.esc)} ++ "\\");
        try w.flush();
    }
    pub const default = Image{
        .payload = "",
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
    payload: []const u8,

    params: Params,
    const Params = struct {
        // zig fmt: off
        a: u8, q: u8,
        // Keys for image transmission
        f: usize, t: u8, s: usize,
        v: usize, S: usize, O: usize,
        i: usize, I: usize, p: usize,
        o: u8, m: usize,
        // Keys for image display
        x: usize, y: usize, w: usize,
        h: usize, X: usize, Y: usize,
        c: usize, r: usize, C: usize,
        U: usize, z: usize, P: usize,
        Q: usize, H: usize, V: usize,
        // zig fmt: on
        fn Format(comptime name: []const u8, T: type) []const u8 {
            return name ++ switch (T) {
                u8 => "={c}",
                usize => "={d}",
                else => unreachable,
            } ++ ",";
        }
    };
};
