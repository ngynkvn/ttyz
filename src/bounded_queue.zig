//! Bounded ring buffer queue for fixed-capacity FIFO operations.
//!
//! Wraps std.Deque with a fixed-size buffer for allocation-free queuing.
//! Used internally for the event queue.
//!
//! ## Example
//! ```zig
//! var q = BoundedQueue(u32, 16){};
//! q.setup();
//! try q.pushBackBounded(42);
//! const val = q.popFront(); // returns 42
//! ```

const std = @import("std");

/// A simple bounded ring buffer queue with a fixed capacity.
/// Wraps std.Deque with externally-managed memory.
pub fn BoundedQueue(comptime T: type, comptime capacity: usize) type {
    return struct {
        const Self = @This();
        const Deque = std.Deque(T);

        buffer: [capacity]T = undefined,
        deque: Deque = Deque.empty,
        initialized: bool = false,

        pub fn init() Self {
            return .{};
        }

        /// Initialize the deque to use the buffer. Must be called after the
        /// struct is in its final memory location.
        fn ensureInit(self: *Self) void {
            if (!self.initialized) {
                self.deque = Deque.initBuffer(&self.buffer);
                self.initialized = true;
            }
        }

        /// Add an item to the back of the queue.
        /// Returns error.OutOfMemory if the queue is full.
        pub fn pushBackBounded(self: *Self, item: T) !void {
            self.ensureInit();
            return self.deque.pushBackBounded(item);
        }

        /// Remove and return the front item, or null if empty.
        pub fn popFront(self: *Self) ?T {
            self.ensureInit();
            return self.deque.popFront();
        }

        /// Check if the queue is empty.
        pub fn isEmpty(self: *Self) bool {
            self.ensureInit();
            return self.deque.len == 0;
        }

        /// Check if the queue is at capacity.
        pub fn isFull(self: *Self) bool {
            self.ensureInit();
            return self.deque.len >= capacity;
        }

        /// Get the current number of elements.
        pub fn count(self: *Self) usize {
            self.ensureInit();
            return self.deque.len;
        }
    };
}

test "BoundedQueue basic operations" {
    var q = BoundedQueue(u32, 4).init();

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
