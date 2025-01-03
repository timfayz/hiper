// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

//! Public API:
//! - Span (or, const Span = @import("span.zig"))
//! - Dir
//! - Amount

const std = @import("std");

left: usize,
right: usize,

pub const Span = @This();
pub const Dir = enum { left, right };
pub const Rel = enum { none, index, range };
pub const Amount = struct {
    amt: union(enum) {
        left: ?usize,
        right: ?usize,
        around: ?usize,
        custom: Span,
    },
    rshift_uneven: bool = true,
    fit: ?struct { min_pad: usize = 0 } = .{},
    compensate: enum { none, all, part } = .none,

    /// Returns the total span length.
    pub fn len(self: Amount) usize {
        return switch (self.amt) {
            .custom => |amt| amt.left +| amt.right,
            inline else => |amt| amt orelse std.math.maxInt(usize),
        };
    }

    /// Checks if the span can fit the requested `length`.
    pub fn fits(self: Amount, length: usize) bool {
        return if (self.fit) |fit| b: {
            break :b switch (self.amt) {
                .around => length +| fit.min_pad *| 2 <= self.len(),
                inline .left, .right => length +| fit.min_pad <= self.len(),
                .custom => length <= self.len(),
            };
        } else true;
    }

    /// Checks if the span extends the view amount.
    pub fn extends(self: Amount) bool {
        return self.fit == null;
    }
};

pub fn init(amount: Amount, comptime pos: Dir, range: usize) ?Span {
    if (!amount.fits(range)) return null;
    var span: Span = .{ .left = 0, .right = 0 };
    switch (amount.amt) {
        .left => {
            span.left = if (amount.extends()) amount.len() else amount.len() - range;
            span.extend(pos, range);
        },
        .right => {
            span.right = if (amount.extends()) amount.len() else amount.len() - range;
            span.extend(pos, range);
        },
        .around => {
            const avail_len = if (amount.extends()) amount.len() else amount.len() - range;
            const side = avail_len / 2;
            span = .{ .left = side, .right = side };
            if (avail_len & 1 != 0) { // compensate lost item during odd div
                if (amount.rshift_uneven) span.right +|= 1 else span.left +|= 1;
            }
            span.extend(pos, range);
        },
        .custom => |amt| {
            span = .{ .left = amt.left, .right = amt.right };
            if (amount.extends()) span.extend(pos, range);
        },
    }
    return span;
}

/// Returns the total view length.
pub fn len(self: *const Span) usize {
    return self.left +| self.right;
}

pub fn shift(self: *Span, comptime dir: Dir, amt: usize) void {
    switch (dir) {
        .left => {
            self.left +|= amt;
            self.right -|= amt;
        },
        .right => {
            self.left -|= amt;
            self.right +|= amt;
        },
    }
}

pub fn extend(self: *Span, comptime dir: Dir, amt: usize) void {
    switch (dir) {
        .left => self.left +|= amt,
        .right => self.right +|= amt,
    }
}

test Amount {
    const equal = std.testing.expectEqual;
    const max = std.math.maxInt(usize);

    // [len()]
    try equal(max, (Amount{ .amt = .{ .left = null } }).len());
    try equal(max, (Amount{ .amt = .{ .right = null } }).len());
    try equal(max, (Amount{ .amt = .{ .around = null } }).len());

    try equal(10, (Amount{ .amt = .{ .left = 10 } }).len());
    try equal(10, (Amount{ .amt = .{ .right = 10 } }).len());
    try equal(10, (Amount{ .amt = .{ .around = 10 } }).len());
    try equal(10, (Amount{ .amt = .{ .custom = .{ .left = 4, .right = 6 } } }).len());

    // [extends()]
    try equal(true, (Amount{ .amt = .{ .left = 10 }, .fit = null }).extends());
    try equal(false, (Amount{ .amt = .{ .left = 10 } }).extends());

    // [fits()]
    try equal(true, (Amount{ .amt = .{ .left = 10 }, .fit = null }).fits(max));
    try equal(true, (Amount{ .amt = .{ .left = 10 } }).fits(10));
    try equal(false, (Amount{ .amt = .{ .left = 10 } }).fits(11));

    try equal(true, (Amount{ .amt = .{ .right = 10 }, .fit = null }).fits(max));
    try equal(true, (Amount{ .amt = .{ .right = 10 } }).fits(10));
    try equal(false, (Amount{ .amt = .{ .right = 10 } }).fits(11));

    try equal(true, (Amount{ .amt = .{ .around = 10 }, .fit = null }).fits(max));
    try equal(true, (Amount{ .amt = .{ .around = 10 } }).fits(10));
    try equal(false, (Amount{ .amt = .{ .around = 10 } }).fits(11));

    try equal(true, (Amount{ .amt = .{ .custom = .{ .left = 4, .right = 6 } }, .fit = null }).fits(max));
    try equal(true, (Amount{ .amt = .{ .custom = .{ .left = 4, .right = 6 } } }).fits(10));
    try equal(false, (Amount{ .amt = .{ .custom = .{ .left = 4, .right = 6 } } }).fits(11));
}

test Span {
    const equal = std.testing.expectEqualDeep;

    // .left
    try equal(Span{ .left = 10, .right = 0 }, Span.init(.{ .amt = .{ .left = 10 }, .fit = .{} }, .left, 4));
    try equal(Span{ .left = 6, .right = 4 }, Span.init(.{ .amt = .{ .left = 10 }, .fit = .{} }, .right, 4));

    // .right
    try equal(Span{ .left = 4, .right = 6 }, Span.init(.{ .amt = .{ .right = 10 }, .fit = .{} }, .left, 4));
    try equal(Span{ .left = 0, .right = 10 }, Span.init(.{ .amt = .{ .right = 10 }, .fit = .{} }, .right, 4));

    // .around
    try equal(Span{ .left = 2, .right = 8 }, Span.init(.{ .amt = .{ .around = 10 }, .fit = .{} }, .right, 5));
    try equal(Span{ .left = 7, .right = 3 }, Span.init(.{ .amt = .{ .around = 10 }, .fit = .{} }, .left, 5));
    try equal(Span{ .left = 8, .right = 2 }, Span.init(.{ .amt = .{ .around = 10 }, .fit = .{}, .rshift_uneven = false }, .left, 5));
}
