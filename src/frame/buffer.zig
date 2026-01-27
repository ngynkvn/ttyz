//! 2D cell grid for terminal buffer management.

const Allocator = std.mem.Allocator;
const assert = std.debug.assert;


/// A 2D grid of cells representing the terminal buffer.
pub const Buffer = struct {
    cells: []Cell,
    width: u16,
    height: u16,
    allocator: Allocator,

    /// Initialize a new buffer with the given dimensions.
    /// Invariant: width * height must not overflow usize.
    pub fn init(allocator: Allocator, width: u16, height: u16) !Buffer {
        const size = @as(usize, width) * @as(usize, height);
        // Ensure we're not creating an empty buffer unintentionally
        // (an intentionally empty buffer is allowed but logged in debug)
        if (width == 0 or height == 0) {
            assert(size == 0); // Sanity check: if either dimension is 0, size must be 0
        }
        const cells = try allocator.alloc(Cell, size);
        @memset(cells, Cell{});
        return .{
            .cells = cells,
            .width = width,
            .height = height,
            .allocator = allocator,
        };
    }

    /// Free the buffer's memory.
    pub fn deinit(self: *Buffer) void {
        self.allocator.free(self.cells);
    }

    /// Resize the buffer to new dimensions.
    /// Existing content is discarded.
    pub fn resize(self: *Buffer, width: u16, height: u16) !void {
        const size = @as(usize, width) * @as(usize, height);
        self.allocator.free(self.cells);
        self.cells = try self.allocator.alloc(Cell, size);
        @memset(self.cells, Cell{});
        self.width = width;
        self.height = height;
    }

    /// Clear the buffer to default cells.
    pub fn clear(self: *Buffer) void {
        @memset(self.cells, Cell{});
    }

    /// Get the index for a given position.
    fn index(self: *const Buffer, x: u16, y: u16) ?usize {
        if (x >= self.width or y >= self.height) return null;
        const idx = @as(usize, y) * @as(usize, self.width) + @as(usize, x);
        // Invariant: computed index must be within allocated cells
        assert(idx < self.cells.len);
        return idx;
    }

    /// Get the cell at the given position.
    pub fn get(self: *const Buffer, x: u16, y: u16) Cell {
        const idx = self.index(x, y) orelse return Cell{};
        return self.cells[idx];
    }

    /// Set the cell at the given position.
    pub fn set(self: *Buffer, x: u16, y: u16, cell: Cell) void {
        const idx = self.index(x, y) orelse return;
        self.cells[idx] = cell;
    }

    /// Set just the character at the given position.
    pub fn setChar(self: *Buffer, x: u16, y: u16, char: u21) void {
        const idx = self.index(x, y) orelse return;
        self.cells[idx].char = char;
    }

    /// Get the entire buffer area as a Rect.
    pub fn area(self: *const Buffer) Rect {
        return .{ .x = 0, .y = 0, .width = self.width, .height = self.height };
    }

    /// Get a mutable pointer to a cell (for in-place modification).
    pub fn getPtr(self: *Buffer, x: u16, y: u16) ?*Cell {
        const idx = self.index(x, y) orelse return null;
        return &self.cells[idx];
    }
};

test "Buffer basic operations" {
    var buffer = try Buffer.init(std.testing.allocator, 10, 5);
    defer buffer.deinit();

    buffer.set(3, 2, .{ .char = 'X' });
    const cell = buffer.get(3, 2);
    try std.testing.expectEqual(@as(u21, 'X'), cell.char);
}

test "Buffer bounds checking" {
    var buffer = try Buffer.init(std.testing.allocator, 10, 5);
    defer buffer.deinit();

    // Out of bounds should return default cell
    const cell = buffer.get(100, 100);
    try std.testing.expectEqual(@as(u21, ' '), cell.char);

    // Out of bounds set should be no-op
    buffer.set(100, 100, .{ .char = 'X' });
}

test "Buffer resize" {
    var buffer = try Buffer.init(std.testing.allocator, 10, 5);
    defer buffer.deinit();

    buffer.set(3, 2, .{ .char = 'X' });
    try buffer.resize(20, 10);

    // Content should be cleared after resize
    const cell = buffer.get(3, 2);
    try std.testing.expectEqual(@as(u21, ' '), cell.char);
}

const std = @import("std");
const Cell = @import("types.zig").Cell;
const Rect = @import("rect.zig").Rect;
