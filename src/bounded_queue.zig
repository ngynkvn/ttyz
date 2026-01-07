const std = @import("std");

/// A simple bounded ring buffer queue with a fixed capacity.
/// This is a drop-in replacement for std.Deque for fixed-size buffers.
pub fn BoundedQueue(comptime T: type, comptime capacity: usize) type {
    return struct {
        const Self = @This();

        buffer: [capacity]T = undefined,
        head: usize = 0,
        tail: usize = 0,
        len: usize = 0,

        pub fn init() Self {
            return .{};
        }

        pub fn pushBack(self: *Self, item: T) error{Overflow}!void {
            if (self.len >= capacity) return error.Overflow;
            self.buffer[self.tail] = item;
            self.tail = (self.tail + 1) % capacity;
            self.len += 1;
        }

        pub fn pushBackBounded(self: *Self, item: T) error{Overflow}!void {
            return self.pushBack(item);
        }

        pub fn popFront(self: *Self) ?T {
            if (self.len == 0) return null;
            const item = self.buffer[self.head];
            self.head = (self.head + 1) % capacity;
            self.len -= 1;
            return item;
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.len == 0;
        }

        pub fn isFull(self: *const Self) bool {
            return self.len >= capacity;
        }

        pub fn count(self: *const Self) usize {
            return self.len;
        }
    };
}

test "BoundedQueue basic operations" {
    var q = BoundedQueue(u32, 4).init();

    try q.pushBack(1);
    try q.pushBack(2);
    try q.pushBack(3);

    try std.testing.expectEqual(@as(usize, 3), q.count());
    try std.testing.expectEqual(@as(?u32, 1), q.popFront());
    try std.testing.expectEqual(@as(?u32, 2), q.popFront());
    try std.testing.expectEqual(@as(usize, 1), q.count());

    try q.pushBack(4);
    try q.pushBack(5);
    try q.pushBack(6);

    try std.testing.expectEqual(@as(usize, 4), q.count());
    try std.testing.expectError(error.Overflow, q.pushBack(7));
}
