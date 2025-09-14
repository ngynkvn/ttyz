const std = @import("std");
const ttyz = @import("ttyz.zig");
const math = std.math;
const lossyCast = math.lossyCast;

const RenderCommand = struct {
    node: Node,
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
        var idx_stack = std.ArrayList(?Node.Index).empty;
        try idx_stack.append(self.allocator, null);
        while (idx_stack.pop()) |i| {
            var roots = self.nodeIterator();
            while (roots.nextWhereParent(i)) |r| {
                const root, const ri = r;
                var left_offset = root.layout.padding.left;
                var top_offset = root.layout.padding.top;
                var children = self.nodeIterator();
                const rc: RenderCommand = .{ .node = root };
                try renderCommands.append(self.allocator, rc);

                // Adjust children's position based on the root's position and padding
                while (children.nextWhereParent(ri)) |c| {
                    var child, const ci = c;
                    child.ui.x += root.ui.x + left_offset;
                    child.ui.y += root.ui.y + top_offset;
                    switch (root.layout.layout_direction) {
                        .left_right => {
                            left_offset += child.layout.padding.left + child.ui.width;
                        },
                        .top_down => {
                            top_offset += child.layout.padding.top + child.ui.height;
                        },
                    }
                    self.nodes.set(ci, child);
                }
                try idx_stack.append(self.allocator, ri);
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
        const current_node = self.current_node;
        var node: Node = undefined;
        node = .{
            .id = np.id,
            .tag = np.tag,
            .text = np.text,
            .layout = .{
                .sizing = np.sizing,
                .padding = np.padding,
                .child_gap = np.child_gap,
                .child_alignment = np.child_alignment,
                .layout_direction = np.layout_direction,
            },
            .style = .{ .background_color = np.background_color },
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
        const children_count = self.countChildren(parent_idx);
        const child_gap: u16 = pn.layout.child_gap * @as(u16, @intCast(children_count - 1));

        switch (pn.layout.layout_direction) {
            .left_right => { // width axis
                cn.ui.width += child_gap;
                if (pn.layout.sizing.width == .fixed) return;
                pn.ui.width += cn.ui.width;
                pn.ui.height = @max(pn.ui.height, cn.ui.y + cn.ui.height);
            },
            .top_down => { // height axis
                cn.ui.height += child_gap;
                if (pn.layout.sizing.height == .fixed) return;
                pn.ui.height += cn.ui.height;
                pn.ui.width = @max(pn.ui.width, cn.ui.x + cn.ui.width);
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

    pub fn render(self: *Context, root: type) ![]const RenderCommand {
        _ = self.begin();
        Element.from(root).render(self);
        return self.end();
    }
};

pub const NodeProps = struct {
    /// Controls the id of this element.
    id: ?u8 = null,
    /// Controls the tag of this element.
    tag: Node.Tag = .box,
    /// Controls the sizing of this element inside it's parent container, including FIT, GROW, PERCENT and FIXED sizing.
    sizing: Sizing = .As(.fit, .fit),
    /// Controls "padding" in pixels, which is a gap between the bounding box of this element and where its children will be placed.
    padding: Padding = .{},
    /// Controls the gap in pixels between child elements along the layout axis (horizontal gap for LEFT_TO_RIGHT, vertical gap for TOP_TO_BOTTOM).
    child_gap: u16 = 0,
    /// Controls how child elements are aligned on each axis.
    child_alignment: ChildAlignment = .{ .x = .left, .y = .start },
    /// Controls the direction in which child elements will be automatically laid out.
    layout_direction: LayoutDirection = .top_down,
    /// Controls the background color of this element.
    background_color: ?[4]u8 = null,
    /// Controls the text of this element.
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
        var ui = UIElement{ .x = 1, .y = 1, .width = 0, .height = 0 };
        const layout = node.layout;
        switch (layout.sizing.height) {
            .fixed => ui.height = layout.sizing.height.fixed,
            else => {},
        }
        switch (layout.sizing.width) {
            .fixed => ui.width = layout.sizing.width.fixed,
            else => {},
        }
        return ui;
    }
};

const LayoutConfig = struct {
    /// Controls the sizing of this element inside it's parent container, including FIT, GROW, PERCENT and FIXED sizing.
    sizing: Sizing = .As(.fit, .fit),
    /// Controls "padding" in pixels, which is a gap between the bounding box of this element and where its children will be placed.
    padding: Padding = .{}, // Controls "padding" in pixels, which is a gap between the bounding box of this element and where its children will be placed.
    /// Controls the gap in pixels between child elements along the layout axis (horizontal gap for LEFT_TO_RIGHT, vertical gap for TOP_TO_BOTTOM).
    child_gap: u16 = 0,
    /// Controls how child elements are aligned on each axis.
    child_alignment: ChildAlignment = .{ .x = .left, .y = .start },
    /// Controls the direction in which child elements will be automatically laid out.
    layout_direction: LayoutDirection = .top_down,
};

const Style = struct {
    /// Controls the background color of this element.
    background_color: ?[4]u8 = null,
};

const Sizing = struct {
    width: SizingVariant,
    height: SizingVariant,

    pub fn As(width: SizingVariant, height: SizingVariant) Sizing {
        return .{ .width = width, .height = height };
    }
};

const SizingVariant = union(enum) {
    /// Size of this element as a percentage of its parent's size.
    percent: f32,
    /// Size of this element as a minimum and maximum percentage of its parent's size.
    min_max: struct { min: f32, max: f32 },
    /// Size of this element as a fixed number of pixels.
    fixed: u16,
    /// Size of this element as a fit to its parent's size.
    fit: void,

    pub fn Percent(value: f32) SizingVariant {
        return .{ .percent = value };
    }
    pub fn MinMax(min: f32, max: f32) SizingVariant {
        return .{ .min_max = .{ .min = min, .max = max } };
    }
    pub fn Fixed(value: u16) SizingVariant {
        return .{ .fixed = value };
    }
    pub fn Fit() SizingVariant {
        return .{.fit};
    }
};

const Padding = struct {
    top: u16 = 0,
    right: u16 = 0,
    bottom: u16 = 0,
    left: u16 = 0,

    pub fn From(top: u16, right: u16, bottom: u16, left: u16) Padding {
        return .{ .top = top, .right = right, .bottom = bottom, .left = left };
    }

    pub fn All(value: u16) Padding {
        return .{ .top = value, .right = value, .bottom = value, .left = value };
    }
};

const ChildAlignment = struct {
    x: enum { left, center, right },
    y: enum { start, center, end },
};

const LayoutDirection = enum { left_right, top_down };

const panic = std.debug.panic;

pub const Element = struct {
    props: NodeProps,
    renderFn: fn (ctx: *Context) void,
    pub fn render(self: *const Element, ctx: *Context) void {
        ctx.OpenElement(self.props);
        self.renderFn(ctx);
        ctx.CloseElement();
    }
    pub fn from(root: anytype) Element {
        switch (@TypeOf(root)) {
            type => return fromType(root),
            struct { NodeProps, (fn (ctx: *Context) void) } => return fromTuple(root),
            fn (ctx: *Context) void => return fromTuple(.{ .{}, root }),
            else => @compileError("root must be a type"),
        }
    }

    pub fn fromType(comptime root: type) Element {
        if (!@hasDecl(root, "props"))
            @compileError("root must have a props field");
        if (!@hasDecl(root, "render"))
            @compileError("root must have a render field");
        return .{
            .props = root.props,
            .renderFn = root.render,
        };
    }

    pub fn fromTuple(comptime root: struct { NodeProps, (fn (ctx: *Context) void) }) Element {
        return .{
            .props = root.@"0",
            .renderFn = root.@"1",
        };
    }
};
