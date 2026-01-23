//! Immediate-mode layout engine for terminal UIs.
//!
//! Inspired by Clay (https://github.com/nicbarker/clay), this module provides
//! a hierarchical layout system where elements are opened and closed in pairs.
//!
//! ## Usage
//! ```zig
//! const Root = struct {
//!     pub var props = layout.NodeProps{ .sizing = .As(.fit, .fit) };
//!     pub fn render(ctx: *layout.Context) void {
//!         ctx.Text("Hello, world!");
//!     }
//! };
//!
//! var ctx = layout.Context.init(allocator, &screen);
//! const commands = try ctx.render(Root);
//! defer allocator.free(commands);
//! ```

const std = @import("std");
const ttyz = @import("ttyz.zig");
const math = std.math;
const lossyCast = math.lossyCast;

/// A command to render a node at its calculated position.
const RenderCommand = struct {
    node: Node,
};

/// Layout context that manages the node tree and performs layout calculations.
///
/// Use `OpenElement()` and `CloseElement()` pairs to build a hierarchy,
/// then call `render()` to get a list of render commands with calculated positions.
pub const Context = struct {
    /// Memory allocator used for node storage and render commands.
    allocator: std.mem.Allocator,
    /// Reference to the screen for dimension queries.
    screen: *ttyz.Screen,
    /// Storage for all nodes in the layout tree.
    nodes: std.MultiArrayList(Node),
    /// Storage for child node indices.
    childlist: std.ArrayList([32]Node.Index),
    /// Index of the currently open element (for nesting).
    current_node: Node.Index = .nil,

    /// Begin a new layout frame, clearing all previous nodes.
    /// Returns self for method chaining.
    pub fn begin(self: *Context) *Context {
        self.current_node = .nil;
        self.nodes.shrinkRetainingCapacity(0);
        self.childlist.shrinkRetainingCapacity(0);
        return self;
    }

    /// End the layout frame and calculate final positions.
    /// Returns a slice of render commands with calculated positions.
    /// The caller owns the returned slice and must free it with the allocator.
    pub fn end(self: *Context) ![]const RenderCommand {
        var renderCommands = std.ArrayList(RenderCommand).empty;
        var parent_child: [16][16:.nil]Node.Index = undefined;
        @memset(&parent_child, @splat(.nil));
        // create a mapping of parent to children
        var parent_child_count: [16]usize = std.mem.zeroes([16]usize);
        for (1.., self.nodes.items(.parent)[1..]) |child, par| {
            // the index of the parent for current node
            const node_idx: Node.Index = par;
            std.log.debug("parent: {d}, child: {d}", .{ node_idx.index(), child });
            const i = node_idx.index();
            parent_child[i][parent_child_count[i]] = .from(child);
            parent_child_count[i] += 1;
        }

        var idx_stack = std.ArrayList(Node.Index).empty;
        try idx_stack.append(self.allocator, .nil);
        while (idx_stack.pop()) |top| {
            const i = top.index();
            const root = self.nodes.get(i);
            var left_offset = root.layout.padding.left;
            var top_offset = root.layout.padding.top;
            const rc: RenderCommand = .{ .node = root };
            std.log.debug("root: {}", .{rc});
            try renderCommands.append(self.allocator, rc);
            const len = parent_child_count[i];
            const children = parent_child[i][0..len];
            for (children) |childi| {
                const c = childi.index();
                var child = self.nodes.get(c);
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
                self.nodes.set(c, child);
                try idx_stack.append(self.allocator, .from(c));
            }
        }
        return renderCommands.toOwnedSlice(self.allocator);
    }

    /// Clean up resources used by the context.
    pub fn deinit(self: *Context) void {
        self.nodes.deinit(self.allocator);
    }

    /// Create an iterator over all nodes in the tree.
    pub fn nodeIterator(self: *Context) NodeIterator {
        return NodeIterator{ .context = self, .index = 0 };
    }
    /// Iterator for traversing nodes in the layout tree.
    const NodeIterator = struct {
        context: *Context,
        index: usize,

        /// Get the next node that has the specified parent.
        pub fn nextWhereParent(self: *NodeIterator, parent_idx: ?Node.Index) ?struct { Node, usize } {
            while (self.next()) |node| {
                if (node.parent == parent_idx) return .{ node, self.index - 1 };
            }
            return null;
        }
        /// Get the next node in the tree, or null if exhausted.
        pub fn next(self: *NodeIterator) ?Node {
            if (self.index >= self.context.nodes.len) return null;
            const node = self.context.nodes.get(self.index);
            self.index += 1;
            return node;
        }
    };

    /// Open a new element with the given properties.
    /// Must be paired with a corresponding `CloseElement()` call.
    /// Elements can be nested to create a hierarchy.
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
            .style = .{ .color = np.color },
            .ui = UIElement.init(node),
            .parent = current_node,
        };
        const node_idx = self.nodes.addOne(self.allocator) catch return;
        self.nodes.set(node_idx, node);
        self.current_node = .from(node_idx);
    }

    /// Close the current element and update parent sizing.
    /// Calculates the element's final dimensions based on its children
    /// and updates the parent's size accordingly.
    pub fn CloseElement(self: *Context) void {
        const curr_idx = self.current_node;
        var cn = self.nodes.get(curr_idx.index());
        cn.ui.height += cn.layout.padding.top + cn.layout.padding.bottom;
        cn.ui.width += cn.layout.padding.left + cn.layout.padding.right;

        self.current_node = cn.parent;
        // if (self.current_node == .nil) return;
        const parent_idx = cn.parent;

        var pn = self.nodes.get(parent_idx.index());
        const children_count = self.countChildren(parent_idx);
        const child_gap: u16 = pn.layout.child_gap * @as(u16, @intCast(children_count - 1));

        switch (pn.layout.layout_direction) {
            .left_right => { // width axis
                cn.ui.width += child_gap;
                pn.ui.height = @max(pn.ui.height, cn.ui.y + cn.ui.height + 1);
                if (pn.layout.sizing.width == .fixed) return;
                pn.ui.width += cn.ui.width + 1;
            },
            .top_down => { // height axis
                cn.ui.height += child_gap;
                pn.ui.width = @max(pn.ui.width, cn.ui.x + cn.ui.width + 1);
                if (pn.layout.sizing.height == .fixed) return;
                pn.ui.height += cn.ui.height + 1;
            },
        }
        self.nodes.set(curr_idx.index(), cn);
        self.nodes.set(parent_idx.index(), pn);
    }

    /// Count the number of direct children of a given parent node.
    pub fn countChildren(self: *Context, parent_idx: Node.Index) usize {
        return std.mem.count(Node.Index, self.nodes.items(.parent), &.{parent_idx});
    }

    /// Add a text element as a child of the current element.
    /// This is a convenience method that opens and immediately closes a text node.
    pub fn Text(self: *Context, text: []const u8) void {
        self.OpenElement(.{
            .tag = .text,
            .text = text,
        });
        self.CloseElement();
    }

    /// Initialize a new layout context with the given allocator and screen.
    pub fn init(allocator: std.mem.Allocator, screen: *ttyz.Screen) Context {
        return .{
            .screen = screen,
            .allocator = allocator,
            .nodes = std.MultiArrayList(Node).empty,
            .childlist = std.ArrayList([32]Node.Index).empty,
        };
    }

    /// Render a root element type and return the calculated render commands.
    /// The root type must have `props` (NodeProps) and `render` (fn(*Context) void) declarations.
    pub fn render(self: *Context, root: type) ![]const RenderCommand {
        _ = self.begin();
        self.OpenElement(root.props);
        root.render(self);
        self.CloseElement();
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
    /// Controls the color of this element.
    color: ?[4]u8 = null,
    /// Controls the text of this element.
    text: ?[]const u8 = null,
};

/// A node in the layout tree representing a UI element.
pub const Node = struct {
    /// Optional unique identifier for this node.
    id: ?u8 = null,
    /// The type of this node (text or box).
    tag: Tag = .box,
    /// Index of the parent node in the tree.
    parent: Node.Index = .nil,
    /// Calculated UI properties (position and size).
    ui: UIElement,
    /// Visual styling properties.
    style: Style,
    /// Layout configuration for this node.
    layout: LayoutConfig,
    /// Text content (for text nodes).
    text: ?[]const u8 = null,

    /// Node type discriminator.
    const Tag = enum { text, box };

    /// Index type for referencing nodes in the tree.
    const Index = enum(u8) {
        nil = 0,
        _,
        pub fn from(i: usize) Index {
            return @enumFromInt(i);
        }
        pub fn index(self: Index) usize {
            return @intFromEnum(self);
        }
    };
    const default = Node{
        .style = .default,
        .layout = .default,
    };
};

/// Calculated UI properties representing an element's position and size.
pub const UIElement = struct {
    /// X position (column) in terminal coordinates.
    x: u16,
    /// Y position (row) in terminal coordinates.
    y: u16,
    /// Width in terminal columns.
    width: u16,
    /// Height in terminal rows.
    height: u16,

    /// Initialize a UIElement from a node's layout configuration.
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

/// Internal layout configuration for a node.
const LayoutConfig = struct {
    /// Controls the sizing of this element inside it's parent container.
    sizing: Sizing = .As(.fit, .fit),
    /// Controls padding (gap between bounding box and children).
    padding: Padding = .{},
    /// Controls the gap between child elements along the layout axis.
    child_gap: u16 = 0,
    /// Controls how child elements are aligned on each axis.
    child_alignment: ChildAlignment = .{ .x = .left, .y = .start },
    /// Controls the direction in which child elements are laid out.
    layout_direction: LayoutDirection = .top_down,
};

/// Visual styling properties for a node.
const Style = struct {
    /// Background color as RGBA (optional).
    color: ?[4]u8 = null,
};

/// Sizing configuration for width and height.
const Sizing = struct {
    width: SizingVariant,
    height: SizingVariant,

    /// Create a sizing configuration from width and height variants.
    pub fn As(width: SizingVariant, height: SizingVariant) Sizing {
        return .{ .width = width, .height = height };
    }
};

/// Sizing variant specifying how an element should be sized.
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

/// Padding configuration for an element's interior spacing.
const Padding = struct {
    top: u16 = 0,
    right: u16 = 0,
    bottom: u16 = 0,
    left: u16 = 0,

    /// Create padding with individual values for each side.
    pub fn From(top: u16, right: u16, bottom: u16, left: u16) Padding {
        return .{ .top = top, .right = right, .bottom = bottom, .left = left };
    }

    /// Create padding with the same value for all sides.
    pub fn All(value: u16) Padding {
        return .{ .top = value, .right = value, .bottom = value, .left = value };
    }
};

/// Configuration for how children are aligned within their parent.
const ChildAlignment = struct {
    x: enum { left, center, right },
    y: enum { start, center, end },
};

/// Direction for laying out child elements.
const LayoutDirection = enum {
    /// Children are laid out horizontally (left to right).
    left_right,
    /// Children are laid out vertically (top to bottom).
    top_down,
};

const panic = std.debug.panic;

/// A reusable element definition combining properties and a render function.
/// Can be created from a type with `props` and `render` declarations,
/// or from a tuple of (NodeProps, render function).
pub const Element = struct {
    /// Layout and styling properties for this element.
    props: NodeProps,
    /// Function to render this element's children.
    renderFn: fn (ctx: *Context) void,

    /// Render this element and its children to the context.
    pub fn render(self: *const Element, ctx: *Context) void {
        ctx.OpenElement(self.props);
        self.renderFn(ctx);
        ctx.CloseElement();
    }

    /// Create an Element from various input types.
    /// Accepts: a type with props/render, a tuple (NodeProps, fn), or just a render fn.
    pub fn from(root: anytype) Element {
        switch (@TypeOf(root)) {
            type => return fromType(root),
            struct { NodeProps, (fn (ctx: *Context) void) } => return fromTuple(root),
            fn (ctx: *Context) void => return fromTuple(.{ .{}, root }),
            else => @compileError("root must be a type"),
        }
    }

    /// Create an Element from a type with `props` and `render` declarations.
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

    /// Create an Element from a tuple of (NodeProps, render function).
    pub fn fromTuple(comptime root: struct { NodeProps, (fn (ctx: *Context) void) }) Element {
        return .{
            .props = root.@"0",
            .renderFn = root.@"1",
        };
    }
};
