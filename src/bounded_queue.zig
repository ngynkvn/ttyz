//! Bounded ring buffer queue for fixed-capacity FIFO operations.
//!
//! Wraps std.Deque with an externally-provided buffer for allocation-free queuing.
//! Used internally for the event queue.
//!
//! ## Example
//! ```zig
//! var buffer: [16]u32 = undefined;
//! var q = BoundedQueue(u32).init(&buffer);
//! try q.pushBackBounded(42);
//! const val = q.popFront(); // returns 42
//! ```

const std = @import("std");

/// A simple bounded ring buffer queue.
/// Wraps std.Deque with externally-managed memory.
pub fn BoundedQueue(comptime T: type) type {
    return struct {
        const Self = @This();
        const Deque = std.Deque(T);

        deque: Deque,

        /// Initialize with an external buffer.
        pub fn init(buffer: []T) Self {
            return .{ .deque = Deque.initBuffer(buffer) };
        }

        /// Add an item to the back of the queue.
        /// Returns error.OutOfMemory if the queue is full.
        pub fn pushBackBounded(self: *Self, item: T) !void {
            return self.deque.pushBackBounded(item);
        }

        /// Remove and return the front item, or null if empty.
        pub fn popFront(self: *Self) ?T {
            return self.deque.popFront();
        }

        /// Check if the queue is empty.
        pub fn isEmpty(self: *const Self) bool {
            return self.deque.len == 0;
        }

        /// Check if the queue is at capacity.
        pub fn isFull(self: *const Self) bool {
            return self.deque.len >= self.deque.buffer.len;
        }

        /// Get the current number of elements.
        pub fn count(self: *const Self) usize {
            return self.deque.len;
        }
    };
}

test "BoundedQueue basic operations" {
    var buffer: [4]u32 = undefined;
    var q = BoundedQueue(u32).init(&buffer);

    try q.pushBackBounded(1);
    try q.pushBackBounded(2);
    try q.pushBackBounded(3);

    try std.testing.expectEqual(@as(usize, 3), q.count());
    try std.testing.expectEqual(@as(?u32, 1), q.popFront());
    try std.testing.expectEqual(@as(?u32, 2), q.popFront());
    try std.testing.expectEqual(@as(usize, 1), q.count());

    try q.pushBackBounded(4);
    try q.pushBackBounded(5);
    try q.pushBackBounded(6);

    try std.testing.expectEqual(@as(usize, 4), q.count());
    try std.testing.expectError(error.OutOfMemory, q.pushBackBounded(7));
}
