const std = @import("std");
const ttyz = @import("ttyz.zig");
const _cast = ttyz._cast;

const RenderCommand = struct {
    node: Node,
    data: []const u8,
};
pub const Context = struct {
    allocator: std.mem.Allocator,
    screen: *ttyz.Screen,
    nodes: std.MultiArrayList(Node),
    current_node: ?Node.Index = null,
    renderCommands: std.ArrayList(RenderCommand),

    pub fn begin(self: *Context) *Context {
        self.current_node = null;
        self.nodes.shrinkRetainingCapacity(0);
        self.renderCommands.shrinkRetainingCapacity(0);
        return self;
    }

    pub fn end(self: *Context) ![]const RenderCommand {
        // create render commands for each node
        for (0..self.nodes.len) |i| {
            const node = self.nodes.get(i);
            const rc: RenderCommand = switch (node.tag) {
                .text => .{ .node = node, .data = node.text.? },
                .box => .{ .node = node, .data = "" },
            };
            try self.renderCommands.append(self.allocator, rc);
        }
        return self.renderCommands.toOwnedSlice(self.allocator);
    }

    pub fn deinit(self: *Context) void {
        self.nodes.deinit(self.allocator);
        self.renderCommands.deinit(self.allocator);
    }

    pub fn findRoots(self: *Context) []const Node {
        var roots = std.ArrayList(Node).empty;
        for (self.nodes.items) |n| {
            if (n.parent == null) roots.append(self.allocator, n) catch panic("Failed to append root node", .{});
        }
        return roots.toOwnedSlice(self.allocator) catch panic("Failed to allocate roots", .{});
    }

    pub fn OpenElement(self: *Context, n: NodeProps) void {
        self.addNodeElement(n);
    }

    pub fn CloseElement(self: *Context) void {
        const cn = self.nodes.get(self.current_node orelse return);
        self.current_node = cn.parent;
        const parent = cn.parent orelse return;
        var pn = self.nodes.get(parent);
        switch (pn.layout.layoutDirection) {
            .left_to_right => {
                pn.ui.width += cn.ui.width;
                pn.ui.height = @max(pn.ui.height, cn.ui.height);
            },
            .top_to_bottom => {
                pn.ui.width = @max(pn.ui.width, cn.ui.width);
                pn.ui.height += cn.ui.height;
            },
        }
        self.nodes.set(parent, pn);
    }

    pub fn Text(self: *Context, text: []const u8) void {
        self.OpenElement(.{
            .tag = .text,
            .text = text,
        });
        self.CloseElement();
    }

    pub fn setStyle(self: *Context, style: ?Style) void {
        if (self.current_node) |n| n.style = style orelse .default;
    }

    pub fn setLayout(self: *Context, layout: ?LayoutConfig) void {
        if (self.current_node) |n| n.layout = layout orelse .default;
    }

    pub fn addNodeElement(self: *Context, np: NodeProps) void {
        var node: Node = undefined;
        const current_node = self.current_node;
        node = .{
            .id = np.id,
            .tag = np.tag,
            .text = np.text,
            .layout = .{
                .sizing = np.sizing,
                .padding = np.padding,
                .childGap = np.childGap,
                .childAlignment = np.childAlignment,
                .layoutDirection = np.layoutDirection,
            },
            .style = .{ .backgroundColor = np.backgroundColor },
            .ui = .{},
            .parent = current_node,
        };
        node.ui.init();
        const nn = self.nodes.addOne(self.allocator) catch return;
        self.nodes.set(nn, node);
        self.current_node = nn;
    }

    pub fn init(allocator: std.mem.Allocator, screen: *ttyz.Screen) Context {
        return .{
            .screen = screen,
            .allocator = allocator,
            .nodes = std.MultiArrayList(Node).empty,
            .renderCommands = std.ArrayList(RenderCommand).empty,
        };
    }
};

pub const NodeProps = struct {
    id: ?u8 = null,
    tag: Node.Tag = .box,
    sizing: Sizing = .As(.fit, .fit), // Controls the sizing of this element inside it's parent container, including FIT, GROW, PERCENT and FIXED sizing.
    padding: Padding = .{}, // Controls "padding" in pixels, which is a gap between the bounding box of this element and where its children will be placed.
    childGap: u16 = 0, // Controls the gap in pixels between child elements along the layout axis (horizontal gap for LEFT_TO_RIGHT, vertical gap for TOP_TO_BOTTOM).
    childAlignment: ChildAlignment = .{ .x = .left, .y = .start }, // Controls how child elements are aligned on each axis.
    layoutDirection: LayoutDirection = .top_to_bottom, // Controls the direction in which child elements will be automatically laid out.
    backgroundColor: ?[4]u8 = null,
    text: ?[]const u8 = null,
};

pub const Node = struct {
    id: ?u8 = null,
    tag: Tag = .box,
    parent: ?Node.Index = null,
    ui: UIElement,
    style: Style,
    layout: LayoutConfig,
    text: ?[]const u8 = null,
    const Tag = enum { text, box };
    const Index = usize;
    const default = Node{
        .style = .default,
        .layout = .default,
    };
};

pub const UIElement = struct {
    x: u16 = 0,
    y: u16 = 0,
    width: u16 = 0,
    height: u16 = 0,

    pub fn init(ui: *UIElement) void {
        const node: *Node = @alignCast(@fieldParentPtr("ui", ui));
        const layout = node.layout;
        switch (layout.sizing.height) {
            .fixed => ui.height = _cast(u16, layout.sizing.height.fixed),
            else => {},
        }
        switch (layout.sizing.width) {
            .fixed => ui.width = _cast(u16, layout.sizing.width.fixed),
            else => {},
        }
    }
};

const LayoutConfig = struct {
    sizing: Sizing = .As(.fit, .fit), // Controls the sizing of this element inside it's parent container, including FIT, GROW, PERCENT and FIXED sizing.
    padding: Padding = .{}, // Controls "padding" in pixels, which is a gap between the bounding box of this element and where its children will be placed.
    childGap: u16 = 0, // Controls the gap in pixels between child elements along the layout axis (horizontal gap for LEFT_TO_RIGHT, vertical gap for TOP_TO_BOTTOM).
    childAlignment: ChildAlignment = .{ .x = .left, .y = .start }, // Controls how child elements are aligned on each axis.
    layoutDirection: LayoutDirection = .top_to_bottom, // Controls the direction in which child elements will be automatically laid out.

};

const Style = struct {
    backgroundColor: ?[4]u8 = null,
};

const Sizing = struct {
    width: SizingVariant,
    height: SizingVariant,

    pub fn As(width: SizingVariant, height: SizingVariant) Sizing {
        return .{ .width = width, .height = height };
    }
};

const SizingVariant = union(enum) {
    percent: f32,
    minMax: struct { min: f32, max: f32 },
    fixed: u32,
    fit: void,

    pub fn Percent(value: f32) SizingVariant {
        return .{ .percent = value };
    }
    pub fn MinMax(min: f32, max: f32) SizingVariant {
        return .{ .minMax = .{ .min = min, .max = max } };
    }
    pub fn Fixed(value: u32) SizingVariant {
        return .{ .fixed = value };
    }
};

const Padding = struct {
    top: u16 = 0,
    bottom: u16 = 0,
    left: u16 = 0,
    right: u16 = 0,

    pub fn All(value: u16) Padding {
        return .{ .top = value, .bottom = value, .left = value, .right = value };
    }
};

const ChildAlignment = struct {
    x: enum { left, center, right },
    y: enum { start, center, end },
};

const LayoutDirection = enum { left_to_right, top_to_bottom };

const panic = std.debug.panic;
