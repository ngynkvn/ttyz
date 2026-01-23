//! Layout system for splitting areas into sub-rectangles.
//!
//! Re-exports from frame/layout.zig for convenience.

const frame_layout = @import("frame/layout.zig");
pub const Direction = frame_layout.Direction;
pub const Constraint = frame_layout.Constraint;
pub const Layout = frame_layout.Layout;
pub const vertical = frame_layout.vertical;
pub const horizontal = frame_layout.horizontal;
