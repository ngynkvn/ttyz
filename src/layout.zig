//! Immediate-mode layout engine for terminal UIs.
//!
//! Provides a simple, defer-based API for building hierarchical layouts.
//!
//! ## Usage
//! ```zig
//! var ctx = layout.Context.init(allocator);
//! defer ctx.deinit();
//!
//! ctx.begin();
//! {
//!     ctx.open(.{ .direction = .horizontal, .padding = Padding.all(1) });
//!     defer ctx.close();
//!
//!     {
//!         ctx.open(.{ .width = .fixed(20), .border = true });
//!         defer ctx.close();
//!         ctx.text("Left Panel");
//!     }
//!     {
//!         ctx.open(.{ .border = true });
//!         defer ctx.close();
//!         ctx.text("Right Panel");
//!     }
//! }
//! const commands = try ctx.end(screen.width, screen.height);
//! ```

const std = @import("std");
const ttyz = @import("ttyz.zig");
const termdraw = @import("termdraw.zig");

/// Sizing mode for width or height.
pub const Size = union(enum) {
    /// Fit to content
    fit,
    /// Fixed number of cells
    fixed: u16,
    /// Percentage of parent (0.0-1.0)
    percent: f32,
    /// Bounded fit with min/max constraints
    min_max: struct { min: u16, max: u16 },
};

/// Padding configuration for an element's interior spacing.
pub const Padding = struct {
    top: u16 = 0,
    right: u16 = 0,
    bottom: u16 = 0,
    left: u16 = 0,

    /// Create padding with the same value for all sides.
    pub fn all(v: u16) Padding {
        return .{ .top = v, .right = v, .bottom = v, .left = v };
    }

    /// Create padding with individual values for each side.
    pub fn from(top: u16, right: u16, bottom: u16, left: u16) Padding {
        return .{ .top = top, .right = right, .bottom = bottom, .left = left };
    }
};

/// Direction for laying out child elements.
pub const Direction = enum {
    /// Children are laid out horizontally (left to right).
    horizontal,
    /// Children are laid out vertically (top to bottom).
    vertical,
};

/// Properties for configuring a layout node.
pub const Props = struct {
    /// Width sizing mode
    width: Size = .fit,
    /// Height sizing mode
    height: Size = .fit,
    /// Direction for laying out children
    direction: Direction = .vertical,
    /// Gap between children in cells
    gap: u16 = 0,
    /// Interior padding
    padding: Padding = .{},
    /// Optional background color (RGBA)
    color: ?[4]u8 = null,
    /// Whether to draw a border
    border: bool = false,
};

/// Index type for referencing nodes in the tree.
pub const Index = enum(u16) {
    root = 0,
    none = std.math.maxInt(u16),
    _,

    pub fn from(i: usize) Index {
        return @enumFromInt(i);
    }

    pub fn int(self: Index) usize {
        return @intFromEnum(self);
    }
};

/// A node in the layout tree.
pub const Node = struct {
    /// Index of parent node
    parent: Index = .root,
    /// Index of first child
    first_child: Index = .none,
    /// Index of next sibling
    next_sibling: Index = .none,
    /// Layout properties
    props: Props = .{},
    /// Text content (for text nodes)
    text: ?[]const u8 = null,

    // Calculated output
    x: u16 = 0,
    y: u16 = 0,
    width: u16 = 0,
    height: u16 = 0,
};

/// A command to render a node at its calculated position.
pub const RenderCommand = struct {
    tag: Tag,
    x: u16,
    y: u16,
    width: u16,
    height: u16,
    color: ?[4]u8 = null,
    text: ?[]const u8 = null,
    border: bool = false,

    pub const Tag = enum { box, text };

    /// Render this command to the screen.
    pub fn render(self: RenderCommand, screen: *ttyz.Screen) !void {
        const w = &screen.writer.interface;
        switch (self.tag) {
            .box => {
                if (self.border and self.width >= 2 and self.height >= 2) {
                    try termdraw.box(w, .{
                        .x = self.x,
                        .y = self.y,
                        .width = self.width,
                        .height = self.height,
                        .color = self.color,
                    });
                } else if (self.color) |color| {
                    // Fill with background color if no border
                    var buf: [32]u8 = undefined;
                    const color_str = std.fmt.bufPrint(&buf, ttyz.E.SET_TRUCOLOR, .{ color[0], color[1], color[2] }) catch return;
                    for (0..self.height) |row| {
                        var goto_buf: [16]u8 = undefined;
                        const goto = std.fmt.bufPrint(&goto_buf, ttyz.E.GOTO, .{ self.y + @as(u16, @intCast(row)), self.x }) catch return;
                        _ = try w.write(goto);
                        _ = try w.write(color_str);
                        for (0..self.width) |_| {
                            _ = try w.write(" ");
                        }
                    }
                    _ = try w.write(ttyz.E.RESET_COLORS);
                }
            },
            .text => {
                if (self.text) |txt| {
                    var buf: [16]u8 = undefined;
                    const goto = std.fmt.bufPrint(&buf, ttyz.E.GOTO, .{ self.y, self.x }) catch return;
                    _ = try w.write(goto);
                    _ = try w.write(txt);
                }
            },
        }
    }
};

/// Layout context that manages the node tree and performs layout calculations.
pub const Context = struct {
    /// Memory allocator used for node storage and render commands.
    allocator: std.mem.Allocator,
    /// Storage for all nodes in the layout tree.
    nodes: std.ArrayList(Node) = .empty,
    /// Stack of open node indices for nesting.
    node_stack: std.ArrayList(Index) = .empty,

    /// Initialize a new layout context.
    pub fn init(allocator: std.mem.Allocator) Context {
        return .{
            .allocator = allocator,
        };
    }

    /// Clean up resources used by the context.
    pub fn deinit(self: *Context) void {
        self.nodes.deinit(self.allocator);
        self.node_stack.deinit(self.allocator);
    }

    /// Begin a new layout frame, clearing all previous nodes.
    pub fn begin(self: *Context) void {
        self.nodes.clearRetainingCapacity();
        self.node_stack.clearRetainingCapacity();
        // Add implicit root node
        self.nodes.append(self.allocator, .{
            .parent = .none,
            .props = .{},
        }) catch {};
        self.node_stack.append(self.allocator, .root) catch {};
    }

    /// Open a new node with the given properties.
    /// Use with defer to automatically close.
    pub fn open(self: *Context, props: Props) void {
        const parent_idx = self.currentNode();
        const new_idx = Index.from(self.nodes.items.len);

        // Link as child of current node
        if (parent_idx != .none) {
            var parent = &self.nodes.items[parent_idx.int()];
            if (parent.first_child == .none) {
                parent.first_child = new_idx;
            } else {
                // Find last sibling and link
                var sibling_idx = parent.first_child;
                while (self.nodes.items[sibling_idx.int()].next_sibling != .none) {
                    sibling_idx = self.nodes.items[sibling_idx.int()].next_sibling;
                }
                self.nodes.items[sibling_idx.int()].next_sibling = new_idx;
            }
        }

        self.nodes.append(self.allocator, .{
            .parent = parent_idx,
            .props = props,
        }) catch {};
        self.node_stack.append(self.allocator, new_idx) catch {};
    }

    /// Close the current node.
    pub fn close(self: *Context) void {
        if (self.node_stack.items.len > 1) {
            _ = self.node_stack.pop();
        }
    }

    /// Add a text leaf node.
    pub fn text(self: *Context, content: []const u8) void {
        self.open(.{});
        self.nodes.items[self.nodes.items.len - 1].text = content;
        self.close();
    }

    /// Get the current node index.
    fn currentNode(self: *Context) Index {
        if (self.node_stack.items.len == 0) return .none;
        return self.node_stack.items[self.node_stack.items.len - 1];
    }

    /// End the layout frame, calculate positions, and return render commands.
    pub fn end(self: *Context, screen_width: u16, screen_height: u16) ![]RenderCommand {
        if (self.nodes.items.len == 0) return &.{};

        // Set root node dimensions to screen size
        self.nodes.items[0].width = screen_width;
        self.nodes.items[0].height = screen_height;
        self.nodes.items[0].x = 1;
        self.nodes.items[0].y = 1;

        // Pass 1: Calculate intrinsic sizes (post-order traversal)
        self.calculateIntrinsicSizes(0);

        // Pass 2: Resolve constraints and position children (pre-order traversal)
        self.resolveConstraints(0, screen_width, screen_height);

        // Pass 3: Generate render commands
        var commands = std.ArrayList(RenderCommand).empty;
        try self.generateCommands(0, &commands);

        return commands.toOwnedSlice(self.allocator);
    }

    /// Pass 1: Calculate intrinsic sizes bottom-up (post-order).
    fn calculateIntrinsicSizes(self: *Context, idx: usize) void {
        var node = &self.nodes.items[idx];

        // First, recursively calculate children
        var child_idx = node.first_child;
        while (child_idx != .none) {
            self.calculateIntrinsicSizes(child_idx.int());
            child_idx = self.nodes.items[child_idx.int()].next_sibling;
        }

        // Calculate intrinsic size from children if sizing is .fit
        const padding_h = node.props.padding.left + node.props.padding.right;
        const padding_v = node.props.padding.top + node.props.padding.bottom;

        // Handle text nodes
        if (node.text) |txt| {
            if (node.props.width == .fit) {
                node.width = @intCast(txt.len);
            }
            if (node.props.height == .fit) {
                node.height = 1;
            }
            return;
        }

        // Calculate from children
        var content_width: u16 = 0;
        var content_height: u16 = 0;
        var child_count: u16 = 0;

        child_idx = node.first_child;
        while (child_idx != .none) {
            const child = &self.nodes.items[child_idx.int()];
            child_count += 1;

            switch (node.props.direction) {
                .horizontal => {
                    content_width += child.width;
                    content_height = @max(content_height, child.height);
                },
                .vertical => {
                    content_width = @max(content_width, child.width);
                    content_height += child.height;
                },
            }
            child_idx = child.next_sibling;
        }

        // Add gaps
        if (child_count > 1) {
            const gaps = (child_count - 1) * node.props.gap;
            switch (node.props.direction) {
                .horizontal => content_width += gaps,
                .vertical => content_height += gaps,
            }
        }

        // Add border if present
        const border_size: u16 = if (node.props.border) 2 else 0;

        // Set intrinsic size for .fit
        if (node.props.width == .fit) {
            node.width = content_width + padding_h + border_size;
        }
        if (node.props.height == .fit) {
            node.height = content_height + padding_v + border_size;
        }
    }

    /// Pass 2: Resolve constraints and position children top-down (pre-order).
    fn resolveConstraints(self: *Context, idx: usize, available_width: u16, available_height: u16) void {
        var node = &self.nodes.items[idx];

        // Resolve own size based on parent's available space
        switch (node.props.width) {
            .fit => {}, // Already calculated
            .fixed => |w| node.width = w,
            .percent => |p| node.width = @intFromFloat(@as(f32, @floatFromInt(available_width)) * p),
            .min_max => |mm| node.width = @min(mm.max, @max(mm.min, node.width)),
        }
        switch (node.props.height) {
            .fit => {}, // Already calculated
            .fixed => |h| node.height = h,
            .percent => |p| node.height = @intFromFloat(@as(f32, @floatFromInt(available_height)) * p),
            .min_max => |mm| node.height = @min(mm.max, @max(mm.min, node.height)),
        }

        // Calculate content area
        const border_offset: u16 = if (node.props.border) 1 else 0;
        const content_x = node.x + node.props.padding.left + border_offset;
        const content_y = node.y + node.props.padding.top + border_offset;
        const content_width = node.width -| (node.props.padding.left + node.props.padding.right + border_offset * 2);
        const content_height = node.height -| (node.props.padding.top + node.props.padding.bottom + border_offset * 2);

        // Position and recurse into children
        var current_x = content_x;
        var current_y = content_y;
        var child_idx = node.first_child;

        while (child_idx != .none) {
            var child = &self.nodes.items[child_idx.int()];
            child.x = current_x;
            child.y = current_y;

            // Recurse with available space
            self.resolveConstraints(child_idx.int(), content_width, content_height);

            // Advance position
            switch (node.props.direction) {
                .horizontal => current_x += child.width + node.props.gap,
                .vertical => current_y += child.height + node.props.gap,
            }

            child_idx = child.next_sibling;
        }
    }

    /// Pass 3: Generate render commands.
    fn generateCommands(self: *Context, idx: usize, commands: *std.ArrayList(RenderCommand)) !void {
        const node = &self.nodes.items[idx];

        // Skip root node (index 0) for rendering
        if (idx > 0) {
            if (node.text) |txt| {
                try commands.append(self.allocator, .{
                    .tag = .text,
                    .x = node.x,
                    .y = node.y,
                    .width = node.width,
                    .height = node.height,
                    .text = txt,
                });
            } else {
                try commands.append(self.allocator, .{
                    .tag = .box,
                    .x = node.x,
                    .y = node.y,
                    .width = node.width,
                    .height = node.height,
                    .color = node.props.color,
                    .border = node.props.border,
                });
            }
        }

        // Recurse into children
        var child_idx = node.first_child;
        while (child_idx != .none) {
            try self.generateCommands(child_idx.int(), commands);
            child_idx = self.nodes.items[child_idx.int()].next_sibling;
        }
    }
};
