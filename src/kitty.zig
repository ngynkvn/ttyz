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

    pub fn writePreamble(self: *Image, w: *std.Io.Writer) !void {
        try w.writeAll(.{@as(u8, cc.esc)} ++ "_G");
        const pfields = @typeInfo(@FieldType(Image, "params")).@"struct".fields;
        inline for (pfields) |field| {
            const value = @field(self.params, field.name);
            const ctype = std.meta.Child(field.type);
            const fmt = comptime Image.Params.Format(field.name, ctype);
            if (value) |v| try w.print(fmt, .{v});
        }
        try w.writeByte(';');
    }

    pub fn writePayload(self: *Image, w: *std.Io.Writer) !void {
        try w.printBase64(self.payload);
        try w.writeAll(.{@as(u8, cc.esc)} ++ "\\");
    }

    pub fn write(self: *Image, w: *std.Io.Writer) !void {
        try self.writePreamble(w);
        try self.writePayload(w);
        try w.flush();
    }

    payload: []const u8,
    params: Params,

    pub const default = Image{
        .payload = "",
        .params = .{ .a = 't', .f = 32, .t = 'd' },
    };

    const Params = struct {
        // zig fmt: off
        a: ?u8 = null, q: ?u8 = null,
        // Keys for image transmission
        f: ?usize = null, t: ?u8 = null, s: ?usize = null,
        v: ?usize = null, S: ?usize = null, O: ?usize = null,
        i: ?usize = null, I: ?usize = null, p: ?usize = null,
        o: ?u8 = null, m: ?usize = null,
        // Keys for image display
        x: ?usize = null, y: ?usize = null, w: ?usize = null,
        h: ?usize = null, X: ?usize = null, Y: ?usize = null,
        c: ?usize = null, r: ?usize = null, C: ?usize = null,
        U: ?usize = null, z: ?usize = null, P: ?usize = null,
        Q: ?usize = null, H: ?usize = null, V: ?usize = null,
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
