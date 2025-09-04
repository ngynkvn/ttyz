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

    pub fn begin(self: *Context) *Context {
        self.current_node = null;
        self.nodes.shrinkRetainingCapacity(0);
        return self;
    }

    pub fn end(self: *Context) ![]const RenderCommand {
        var renderCommands = std.ArrayList(RenderCommand).empty;
        var roots = self.nodeIterator();
        // todo: inefficient, fix this
        while (roots.nextWhereParent(null)) |r| {
            const root, const ri = r;
            try renderCommands.append(self.allocator, .{ .node = root, .data = "" });
            var left_offset = root.layout.padding.left;
            var top_offset = root.layout.padding.top;
            var children = self.nodeIterator();
            while (children.nextWhereParent(ri)) |c| {
                var child, _ = c;
                child.ui.x += root.ui.x + left_offset;
                child.ui.y += root.ui.y + top_offset;
                const rc: RenderCommand = switch (child.tag) {
                    .box => .{ .node = child, .data = "" },
                    .text => .{ .node = child, .data = child.text.? },
                };
                if (root.layout.layoutDirection == .left_to_right) {
                    left_offset += child.layout.padding.left + child.ui.width;
                } else {
                    top_offset += child.layout.padding.top + child.ui.height;
                }
                try renderCommands.append(self.allocator, rc);
            }
        }
        return renderCommands.toOwnedSlice(self.allocator);
    }

    pub fn deinit(self: *Context) void {
        self.nodes.deinit(self.allocator);
    }

    pub fn nodeIterator(self: *Context) NodeIterator {
        return NodeIterator{ .context = self, .index = 0 };
    }
    const NodeIterator = struct {
        context: *Context,
        index: usize,
        pub fn nextWhereParent(self: *NodeIterator, parent_idx: ?Node.Index) ?struct { Node, usize } {
            while (self.next()) |node| {
                if (node.parent == parent_idx) return .{ node, self.index - 1 };
            }
            return null;
        }
        pub fn next(self: *NodeIterator) ?Node {
            if (self.index >= self.context.nodes.len) return null;
            const node = self.context.nodes.get(self.index);
            self.index += 1;
            return node;
        }
    };

    pub fn OpenElement(self: *Context, np: NodeProps) void {
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
            .ui = UIElement.init(node),
            .parent = current_node,
        };
        const node_idx = self.nodes.addOne(self.allocator) catch return;
        self.nodes.set(node_idx, node);
        self.current_node = node_idx;
    }

    pub fn CloseElement(self: *Context) void {
        const curr_idx = self.current_node orelse return;
        var cn = self.nodes.get(curr_idx);
        cn.ui.height += cn.layout.padding.top + cn.layout.padding.bottom;
        cn.ui.width += cn.layout.padding.left + cn.layout.padding.right;
        self.nodes.set(curr_idx, cn);

        self.current_node = cn.parent;
        const parent_idx = cn.parent orelse return;

        var pn = self.nodes.get(parent_idx);
        const childrenCount = self.countChildren(parent_idx);
        const childGap: u16 = pn.layout.childGap * @as(u16, @intCast(childrenCount - 1));

        switch (pn.layout.layoutDirection) {
            .left_to_right => { // width axis
                if (pn.layout.sizing.width == .fixed) return;
                cn.ui.width += childGap;
                pn.ui.width += cn.ui.width;
                pn.ui.height = @max(pn.ui.height, cn.ui.height);
            },
            .top_to_bottom => { // height axis
                if (pn.layout.sizing.height == .fixed) return;
                cn.ui.height += childGap;
                pn.ui.width = @max(pn.ui.width, cn.ui.width);
                pn.ui.height += cn.ui.height;
            },
        }
        self.nodes.set(parent_idx, pn);
    }

    pub fn countChildren(self: *Context, parent_idx: Node.Index) usize {
        return std.mem.count(?usize, self.nodes.items(.parent), &.{parent_idx});
    }

    pub fn Text(self: *Context, text: []const u8) void {
        self.OpenElement(.{
            .tag = .text,
            .text = text,
        });
        self.CloseElement();
    }

    pub fn init(allocator: std.mem.Allocator, screen: *ttyz.Screen) Context {
        return .{
            .screen = screen,
            .allocator = allocator,
            .nodes = std.MultiArrayList(Node).empty,
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
    x: u16,
    y: u16,
    width: u16,
    height: u16,

    pub fn init(node: Node) UIElement {
        var ui = UIElement{
            .x = 1,
            .y = 1,
            .width = 2,
            .height = 2,
        };
        const layout = node.layout;
        switch (layout.sizing.height) {
            .fixed => ui.height = _cast(u16, layout.sizing.height.fixed),
            else => {},
        }
        switch (layout.sizing.width) {
            .fixed => ui.width = _cast(u16, layout.sizing.width.fixed),
            else => {},
        }
        return ui;
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
