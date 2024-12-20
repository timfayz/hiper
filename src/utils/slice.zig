// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

//! Public API:
//! - reverse()
//! - intersect()
//! - span()
//! - indexOfStart()
//! - indexOfEnd()
//! - indices()
//! - View
//! - ViewMode
//! - ViewOptions
//! - viewStart()
//! - viewEnd()
//! - viewRelIndex()
//! - viewRelRange()
//! - segment()
//! - isSegment()
//! - MoveDir
//! - MoveError
//! - move()
//! - moveLeft()
//! - moveRight()

const std = @import("std");
const num = @import("num.zig");
const mem = std.mem;

/// Reverses slice items in-place.
pub fn reverse(slice: anytype) void {
    const info = @typeInfo(@TypeOf(slice));
    if (info != .pointer and info.Pointer.size != .slice)
        @compileError("argument must be a slice");
    if (slice.len <= 1) return;
    var i: usize = 0;
    const swap_amt = slice.len / 2;
    const last_item_idx = slice.len - 1;
    while (i < swap_amt) : (i += 1) {
        const tmp = slice[i]; // swap
        slice[i] = slice[last_item_idx - i];
        slice[last_item_idx - i] = tmp;
    }
}

test reverse {
    const case = struct {
        pub fn run(input: []const u8, expect: []const u8) !void {
            var buf: [32]u8 = undefined;
            for (input, 0..) |byte, i| buf[i] = byte;
            const actual = buf[0..input.len];
            reverse(actual);
            try std.testing.expectEqualStrings(expect, actual);
        }
    }.run;

    try case("", "");
    try case("1", "1");
    try case("12", "21");
    try case("123", "321");
    try case("1234", "4321");
    try case("12345", "54321");
}

/// Returns the intersection of two slices. Slices are assumed to share the same
/// source; use `isSegment` to verify this before calling.
///
/// ```txt
/// [slice1 ] [ slice2]    (disjoint slices)
///         null           (intersection)
///
/// [slice1   ]            (intersecting slices)
///         [   slice2]
///         [ ]            (intersection)
/// ```
pub fn intersect(T: type, slice1: []const T, slice2: []const T) ?[]T {
    var slice: []T = undefined;
    const ptr1 = @intFromPtr(slice1.ptr);
    const ptr2 = @intFromPtr(slice2.ptr);
    const start = @max(ptr1, ptr2);
    const end = @min(ptr1 + slice1.len, ptr2 + slice2.len);
    if (start >= end) return null;
    slice.ptr = @ptrFromInt(start);
    slice.len = end - start;
    return slice;
}

test intersect {
    const equal = struct {
        pub fn run(expect: ?[]const u8, actual: ?[]const u8) !void {
            if (expect == null) return std.testing.expectEqual(null, actual);
            if (actual == null) return std.testing.expectEqual(expect, null);
            try std.testing.expectEqualStrings(expect.?, actual.?);
        }
    }.run;

    const input = "0123";

    try equal(null, intersect(u8, input[0..0], input[4..4])); // zero slices
    try equal(null, intersect(u8, input[0..2], input[2..4])); // touching boundaries
    try equal("2", intersect(u8, input[0..3], input[2..4])); // intersecting slices
    try equal("2", intersect(u8, input[2..4], input[0..3])); // reversed order
    try equal("12", intersect(u8, input[0..3], input[1..4])); // intersecting slices
    try equal("12", intersect(u8, input[1..4], input[0..3])); // reversed order
    try equal("0123", intersect(u8, input[0..4], input[0..4])); // same slices
    try equal("12", intersect(u8, input[0..4], input[1..3])); // one within other
    try equal("12", intersect(u8, input[1..3], input[0..4])); // reversed order
}

/// Returns the inclusive span between two slices. Slices are assumed to share
/// the same source; use `isSegment` to verify this before calling.
///
/// ```txt
/// [slice1 ] [ slice2]    (slices disjoint)
/// [                 ]    (span)
///
/// [slice1   ]            (slices intersect)
///         [   slice2]
/// [                 ]    (span)
/// ```
pub fn span(T: type, slice1: []const T, slice2: []const T) []T {
    var slice: []T = undefined;
    const ptr1 = @intFromPtr(slice1.ptr);
    const ptr2 = @intFromPtr(slice2.ptr);
    const start = @min(ptr1, ptr2);
    const end = @max(ptr1 + slice1.len, ptr2 + slice2.len);
    slice.ptr = @ptrFromInt(start);
    slice.len = end - start;
    return slice;
}

test span {
    const equal = std.testing.expectEqualStrings;

    const input = "0123";

    try equal("0123", span(u8, input[0..0], input[4..4])); // zero slices
    try equal("0123", span(u8, input[4..4], input[0..0])); // reversed order
    try equal("0123", span(u8, input[0..2], input[2..4])); // normal slices
    try equal("0123", span(u8, input[2..4], input[0..2])); // reversed order
    try equal("0123", span(u8, input[0..3], input[1..4])); // intersected slices
    try equal("0123", span(u8, input[0..4], input[0..4])); // same slices
}

/// Retrieves the starting position of a segment in slice. Slices are assumed to
/// share the same source; use `isSegment` to verify this before calling.
pub fn indexOfStart(slice: anytype, seg: anytype) usize {
    return seg.ptr - slice.ptr;
}

test indexOfStart {
    const equal = std.testing.expectEqual;

    const empty = "";
    const input = "0123456789";

    try equal(0, indexOfStart(empty, empty[0..0]));
    try equal(0, indexOfStart(input, input[0..0]));
    try equal(3, indexOfStart(input, input[3..7]));
    try equal(9, indexOfStart(input, input[9..10]));
    try equal(10, indexOfStart(input, input[10..10]));
}

/// Retrieves the ending position of a segment in slice. Slices are assumed to
/// share the same source; use `isSegment` to verify this before calling.
pub fn indexOfEnd(slice: anytype, seg: anytype) usize {
    return (seg.ptr - slice.ptr) +| seg.len;
}

test indexOfEnd {
    const equal = std.testing.expectEqual;

    const empty = "";
    const input = "0123456789";

    try equal(0, indexOfEnd(empty, empty[0..0]));
    try equal(0, indexOfEnd(input, input[0..0]));
    try equal(7, indexOfEnd(input, input[3..7]));
    try equal(9, indexOfEnd(input, input[3..9]));
    try equal(10, indexOfEnd(input, input[3..10]));
}

/// Retrieves the starting and ending positions of a segment in slice. Slices
/// are assumed to share the same source; use `isSegment` to verify this before
/// calling.
pub fn indices(slice: anytype, seg: anytype) struct { usize, usize } {
    return .{ indexOfStart(slice, seg), indexOfEnd(slice, seg) };
}

const ViewTag = enum { none, index, range };

pub fn View(comptime tag: ViewTag) type {
    return struct {
        /// The start index of the view.
        start: usize,
        /// The end index of the view.
        end: usize,
        pos: switch (tag) {
            .none => struct {},
            .index => struct { index: usize = 0 },
            .range => struct { start: usize = 0, end: usize = 0 },
        } = .{},

        const Self = @This();

        /// Initializes View(any) with a tuple, matching the order of struct fields.
        pub fn init(fields: anytype) Self {
            return switch (tag) {
                .none => .{ .start = fields[0], .end = fields[1] },
                .index => .{ .start = fields[0], .end = fields[1], .pos = .{
                    .index = fields[2],
                } },
                .range => .{ .start = fields[0], .end = fields[1], .pos = .{
                    .start = fields[2],
                    .end = fields[3],
                } },
            };
        }

        /// Returns the retrieved view length.
        pub fn len(self: *const Self) usize {
            return self.end - self.start;
        }

        /// Returns `input[self.start..self.end]`.
        pub fn slice(self: *const Self, T: type, input: T) T {
            return input[self.start..self.end];
        }

        /// Returns `input[self.start..self.end]`, clamped to the bounds of `input`.
        pub fn sliceBounded(self: *const Self, T: type, input: T) T {
            return input[@min(self.start, input.len)..@min(self.end, input.len)];
        }

        pub usingnamespace if (tag == .index) struct {
            /// Checks if relative index position exceeds the actual view boundaries.
            pub fn indexPosExceeds(self: *const Self) bool {
                return self.pos.index > self.len();
            }
        } else if (tag == .range) struct {
            /// Checks if relative range start position exceeds the actual view
            /// boundaries.
            pub fn startPosExceeds(self: *const Self) bool {
                if (tag != .range) @compileError("available only in View(.range) mode");
                return self.pos.start > self.len();
            }

            /// Checks if relative range end position exceeds the actual view
            /// boundaries.
            pub fn endPosExceeds(self: *const Self) bool {
                if (tag != .range) @compileError("available only in View(.range) mode");
                return self.pos.end > self.len();
            }

            /// Returns the length of the requested view range.
            pub fn rangeLen(self: *const Self) usize {
                if (tag != .range) @compileError("available only in View(.range) mode");
                return self.pos.end - self.pos.start +| 1;
            }
        } else struct {};

        /// For debugging purposes only.
        fn render(self: *const Self, writer: anytype, input: []const u8) !void {
            // render input
            try writer.print(" {s} [{d}:{d}]\n", .{
                self.slice([]const u8, input),
                self.start,
                self.end,
            });
            if (tag == .index) {
                // render cursor ^
                try writer.print(" {[0]c: >[1]} [{[2]d}]\n", .{
                    '^', // [0]
                    self.pos.index + 1, // [1] pad before ^
                    self.pos.index, // [2]
                });
            } else if (tag == .range) {
                // render cursor ^ or ^~~^
                if (self.pos.start == self.pos.end)
                    try writer.print(" {[0]c: >[1]} [{[2]d}]", .{
                        '^', // [0]
                        self.pos.start + 1, // [1] pad before ^
                        self.pos.start, // [2]
                    })
                else
                    try writer.print(" {[0]c: >[1]}{[0]c:~>[2]} [{[3]d}:{[4]d}]", .{
                        '^', // [0]
                        self.pos.start + 1, // [1] pad before first ^
                        self.pos.end - self.pos.start, // [2] pad before second ^
                        self.pos.start, // [3]
                        self.pos.end, // [4]
                    });
                try writer.print(" len={d}\n", .{self.rangeLen()});
            }
        }
    };
}

pub const ViewMode = union(enum) {
    /// Retrieves the beginning of the slice.
    start: ?usize,
    /// Retrieves the end of the slice.
    end: ?usize,
    /// Retrieves the full slice.
    full: void,
    /// Retrieves a view centered on the cursor with a given length.
    around: struct { len: ?usize, min_pad: usize = 0 },
    /// Retrieves a view of the left side of the cursor with a given length.
    left: struct { len: ?usize, min_pad: usize = 0 },
    /// Retrieves a view of the right side of the cursor with a given length.
    right: struct { len: ?usize, min_pad: usize = 0 },
    /// Retrieves a view extended by a given length on both sides of the cursor.
    exp_sides: ?usize,
    /// Retrieves a view extended by a given length to the left of the cursor.
    exp_left: ?usize,
    /// Retrieves a view extended by a given length to the right of the cursor.
    exp_right: ?usize,
    /// Retrieves a view extended by custom lengths on the left and right sides.
    exp_custom: struct { left: usize, right: usize },

    pub fn len(self: ViewMode) usize {
        return if (switch (self) {
            inline .around, .left, .right => |mode| mode.len,
            .full => std.math.maxInt(usize),
            .exp_custom => |mode| mode.left + mode.right,
            inline else => |amt| amt,
        }) |val| val else std.math.maxInt(usize);
    }
};

pub const ViewOptions = struct {
    /// Defines how view primitives truncate view span on overrun.
    trunc_mode: TruncMode = .hard_flex,
    /// Extra shift to the precalculated view span.
    extra_shift: ?union(enum) { right: usize, left: usize } = null,
    /// Shifts uneven padding around the cursor by one to the right.
    rshift_uneven: bool = true,

    /// Controls how view primitives truncate a slice segment.
    pub const TruncMode = enum {
        /// Truncates segment directly by the slice bounds.
        hard,
        /// Truncates segment by the slice bounds but compensates for the truncated
        /// length by extending the segment left or right as much as possible.
        hard_flex,
        /// Truncated segment is of constant length that always fits within slice
        /// bounds, even with out-of-bounds indices.
        soft,
    };
};

/// Returns a slice beginning of the length `len`.
/// Indices are bounded by slice length.
pub fn viewStart(slice: anytype, len: usize) View(.none) {
    return .{ .start = 0, .end = @min(len, slice.len) };
}

/// Returns a slice ending of the length `len`.
/// Indices are bounded by slice length.
pub fn viewEnd(slice: anytype, len: usize) View(.none) {
    return .{ .start = slice.len -| len, .end = slice.len };
}

test viewStart {
    const equal = std.testing.expectEqualDeep;
    const T = View(.none);
    try equal(T{ .start = 0, .end = 0 }, viewStart("", 0)); // ""
    try equal(T{ .start = 0, .end = 0 }, viewStart("012", 0)); // ""
    try equal(T{ .start = 0, .end = 1 }, viewStart("012", 1)); // "0"
    try equal(T{ .start = 0, .end = 2 }, viewStart("012", 2)); // "01"
    try equal(T{ .start = 0, .end = 3 }, viewStart("012", 3)); // "012"
    try equal(T{ .start = 0, .end = 3 }, viewStart("012", 4)); // "012"
}

test viewEnd {
    const equal = std.testing.expectEqualDeep;
    const T = View(.none);
    try equal(T{ .start = 0, .end = 0 }, viewEnd("", 0)); // ""
    try equal(T{ .start = 3, .end = 3 }, viewEnd("012", 0)); // ""
    try equal(T{ .start = 2, .end = 3 }, viewEnd("012", 1)); // "2"
    try equal(T{ .start = 1, .end = 3 }, viewEnd("012", 2)); // "12"
    try equal(T{ .start = 0, .end = 3 }, viewEnd("012", 3)); // "012"
    try equal(T{ .start = 0, .end = 3 }, viewEnd("012", 4)); // "012"
}

/// Returns a slice segment of length `len` relative to the index and according
/// to the view `mode`. The returned index position may be out of bounds if the
/// original index is outside the slice.
pub fn viewRelIndex(
    input: anytype,
    index: usize,
    comptime mode: ViewMode,
    comptime opt: ViewOptions,
) View(.index) {
    return viewRel(.index, input, .{ index, index }, mode, true, opt);
}

/// Returns a slice segment of length `len` relative to `start`-`end` range and
/// according to the view `mode`. The returned positions (`pos.*`) may be out of
/// bounds if the original range is outside the slice.
pub fn viewRelRange(
    input: anytype,
    range: struct { usize, usize },
    comptime mode: ViewMode,
    comptime opt: ViewOptions,
) ?View(.range) {
    return viewRel(.range, input, range, mode, false, opt);
}

/// Implementation function for `viewRelIndex` and `viewRelRange`.
pub fn viewRel(
    comptime tag: ViewTag,
    input: anytype,
    range: struct { usize, usize },
    comptime mode: ViewMode,
    comptime allow_zero_len: bool,
    comptime opt: ViewOptions,
) if (allow_zero_len) View(tag) else ?View(tag) {
    const index_start, const index_end = num.orderPair(range[0], range[1]);
    const range_len = index_end - index_start +| 1; // +1 makes end inclusive
    const view_len = mode.len();

    const Span = struct { left: usize, right: usize };
    var view: ?Span = switch (mode) {
        .start => {
            const start, const end = .{ 0, @min(view_len, input.len) };
            return View(tag).init(.{ start, end, index_start, index_end });
        },
        .end => {
            const start, const end = .{ input.len -| view_len, input.len };
            return View(tag).init(.{ start, end, index_start -| start, index_end -| end });
        },
        .full => {
            const start, const end = .{ 0, input.len };
            return View(tag).init(.{ start, end, index_start, index_end });
        },
        .around => |m| if (range_len +| m.min_pad *| 2 > view_len) null else blk: {
            const avail_len = view_len - range_len;
            const side = avail_len / 2;
            var view: Span = .{ .left = side, .right = side +| range_len };
            if (avail_len & 1 != 0) { // compensate lost item during odd div
                if (opt.rshift_uneven) view.right +|= 1 else view.left +|= 1;
            }
            break :blk view;
        },
        .left => |m| if (range_len +| m.min_pad > view_len) null else blk: {
            break :blk .{ .left = view_len - range_len, .right = range_len };
        },
        .right => |m| if (range_len +| m.min_pad > view_len) null else blk: {
            break :blk .{ .left = 0, .right = view_len };
        },
        .exp_sides => .{ .left = view_len, .right = view_len +| range_len },
        .exp_left => .{ .left = view_len, .right = range_len },
        .exp_right => .{ .left = 0, .right = view_len +| range_len },
        .exp_custom => |m| .{ .left = m.left, .right = m.right +| range_len },
    };

    if (view) |*v| {
        if (opt.extra_shift) |shift| {
            switch (shift) {
                .left => |amt| {
                    v.left +|= amt;
                    v.right -|= amt;
                },
                .right => |amt| {
                    v.left -|= amt;
                    v.right +|= amt;
                },
            }
        }
        const span_len = v.left +| v.right; // final view len
        const start = @min(
            index_start -| v.left,
            switch (opt.trunc_mode) {
                .hard => input.len,
                .hard_flex => b: {
                    const range_end = index_start + (range_len -| 1);
                    const overrun = range_end -| (input.len -| 1);
                    break :b input.len -| (span_len -| overrun);
                },
                .soft => input.len -| span_len,
            },
        );
        const end = @min(
            input.len,
            switch (opt.trunc_mode) {
                .hard => index_start +| v.right,
                .hard_flex, .soft => start +| span_len,
            },
        );
        return View(tag).init(.{ start, end, index_start - start, index_end - start });
    }
    // null view means zero-length
    else if (allow_zero_len) {
        const i = @min(index_start, input.len);
        return View(tag).init(.{ i, i, index_start - i, index_end - i });
    } else return null;
}

test viewRelIndex {
    const input = "012345678"; // must be in sync with the first viewRelIndex arg
    const equal = struct {
        pub fn run(comptime expect: []const u8, extra: anytype, view: View(.index)) !void {
            var buf = std.BoundedArray(u8, 1024){};
            try view.render(buf.writer(), input);
            try std.testing.expectEqualStrings(expect ++ "\n", buf.slice());
            try std.testing.expectEqual(extra[0], view.indexPosExceeds());
        }
    }.run;

    // [.around] view mode
    {
        // exceeding len
        //
        try equal(
            \\ 012345678 [0:9]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 0, .{ .around = .{ .len = 100 } }, .{}));
        //                        ^
        try equal(
            \\ 012345678 [0:9]
            \\           ^ [10]
        , .{true}, viewRelIndex("012345678", 10, .{ .around = .{ .len = 100 } }, .{}));
        //                                 ^

        // zero len
        //
        try equal(
            \\  [4:4]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 4, .{ .around = .{ .len = 0 } }, .{ .trunc_mode = .hard }));
        //                            ^
        try equal(
            \\  [4:4]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 4, .{ .around = .{ .len = 0 } }, .{ .trunc_mode = .hard_flex }));
        //                            ^
        try equal(
            \\  [4:4]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 4, .{ .around = .{ .len = 0 } }, .{ .trunc_mode = .soft }));
        //                            ^
        try equal(
            \\  [9:9]
            \\           ^ [10]
        , .{true}, viewRelIndex("012345678", 19, .{ .around = .{ .len = 0 } }, .{ .trunc_mode = .hard }));
        //                                  ^
        try equal(
            \\  [9:9]
            \\           ^ [10]
        , .{true}, viewRelIndex("012345678", 19, .{ .around = .{ .len = 0 } }, .{ .trunc_mode = .hard_flex }));
        //                                  ^
        try equal(
            \\  [9:9]
            \\           ^ [10]
        , .{true}, viewRelIndex("012345678", 19, .{ .around = .{ .len = 0 } }, .{ .trunc_mode = .soft }));
        //                                  ^

        // odd len (1)
        //
        try equal(
            \\ 4 [4:5]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 4, .{ .around = .{ .len = 1 } }, .{ .trunc_mode = .hard }));
        //                            ^
        try equal(
            \\ 4 [4:5]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 4, .{ .around = .{ .len = 1 } }, .{ .trunc_mode = .hard_flex }));
        //                            ^
        try equal(
            \\ 4 [4:5]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 4, .{ .around = .{ .len = 1 } }, .{ .trunc_mode = .soft }));
        //                            ^
        // [.rshift_uneven = false]
        try equal(
            \\ 4 [4:5]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 4, .{ .around = .{ .len = 1 } }, .{ .rshift_uneven = false }));
        //                            ^

        try equal(
            \\  [9:9]
            \\  ^ [1]
        , .{true}, viewRelIndex("012345678", 10, .{ .around = .{ .len = 1 } }, .{ .trunc_mode = .hard }));
        //                                 ^
        try equal(
            \\  [9:9]
            \\  ^ [1]
        , .{true}, viewRelIndex("012345678", 10, .{ .around = .{ .len = 1 } }, .{ .trunc_mode = .hard_flex }));
        //                                 ^
        try equal(
            \\ 8 [8:9]
            \\   ^ [2]
        , .{true}, viewRelIndex("012345678", 10, .{ .around = .{ .len = 1 } }, .{ .trunc_mode = .soft }));
        //                               + ^

        // even len (4)
        //
        try equal(
            \\ 3456 [3:7]
            \\  ^ [1]
        , .{false}, viewRelIndex("012345678", 4, .{ .around = .{ .len = 4 } }, .{ .rshift_uneven = true }));
        //                           -^--
        // [.rshift_uneven = false]
        try equal(
            \\ 2345 [2:6]
            \\   ^ [2]
        , .{false}, viewRelIndex("012345678", 4, .{ .around = .{ .len = 4 } }, .{ .rshift_uneven = false }));
        //                          --^-

        // odd len (5)
        //
        try equal(
            \\ 23456 [2:7]
            \\   ^ [2]
        , .{false}, viewRelIndex("012345678", 4, .{ .around = .{ .len = 5 } }, .{ .trunc_mode = .hard }));
        //                          --^--
        try equal(
            \\ 012 [0:3]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 0, .{ .around = .{ .len = 5 } }, .{ .trunc_mode = .hard }));
        //                      --^--
        try equal(
            \\ 01234 [0:5]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 0, .{ .around = .{ .len = 5 } }, .{ .trunc_mode = .hard_flex }));
        //                      --^--++
        try equal(
            \\ 01234 [0:5]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 0, .{ .around = .{ .len = 5 } }, .{ .trunc_mode = .soft }));
        //                      --^--++

        try equal(
            \\ 78 [7:9]
            \\   ^ [2]
        , .{false}, viewRelIndex("012345678", 9, .{ .around = .{ .len = 5 } }, .{ .trunc_mode = .hard }));
        //                               --^--
        try equal(
            \\ 5678 [5:9]
            \\     ^ [4]
        , .{false}, viewRelIndex("012345678", 9, .{ .around = .{ .len = 5 } }, .{ .trunc_mode = .hard_flex }));
        //                             ++--^--
        try equal(
            \\ 45678 [4:9]
            \\      ^ [5]
        , .{false}, viewRelIndex("012345678", 9, .{ .around = .{ .len = 5 } }, .{ .trunc_mode = .soft }));
        //                            +++--^--
    }

    // [.right] view mode
    {
        try equal(
            \\  [4:4]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 4, .{ .right = .{ .len = 0 } }, .{}));
        //                            ^
        try equal(
            \\  [9:9]
            \\  ^ [1]
        , .{true}, viewRelIndex("012345678", 10, .{ .right = .{ .len = 0 } }, .{}));
        //                                 ^

        try equal(
            \\ 4567 [4:8]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 4, .{ .right = .{ .len = 4 } }, .{}));
        //                            ^---
        try equal(
            \\  [9:9]
            \\  ^ [1]
        , .{true}, viewRelIndex("012345678", 10, .{ .right = .{ .len = 4 } }, .{ .trunc_mode = .hard }));
        //                                  ^---
        try equal(
            \\ 78 [7:9]
            \\    ^ [3]
        , .{true}, viewRelIndex("012345678", 10, .{ .right = .{ .len = 4 } }, .{ .trunc_mode = .hard_flex }));
        //                              ++ ^---
        try equal(
            \\ 5678 [5:9]
            \\      ^ [5]
        , .{true}, viewRelIndex("012345678", 10, .{ .right = .{ .len = 4 } }, .{ .trunc_mode = .soft }));
        //                            ++++ ^---
    }

    // [.left] view mode
    {
        try equal(
            \\  [4:4]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 4, .{ .left = .{ .len = 0 } }, .{}));
        //                            ^
        try equal(
            \\  [9:9]
            \\  ^ [1]
        , .{true}, viewRelIndex("012345678", 10, .{ .left = .{ .len = 0 } }, .{}));
        //                                 ^

        try equal(
            \\ 1234 [1:5]
            \\    ^ [3]
        , .{false}, viewRelIndex("012345678", 4, .{ .left = .{ .len = 4 } }, .{}));
        //                         ---^
        try equal(
            \\ 78 [7:9]
            \\    ^ [3]
        , .{true}, viewRelIndex("012345678", 10, .{ .left = .{ .len = 4 } }, .{ .trunc_mode = .hard }));
        //                              ---^
        try equal(
            \\ 78 [7:9]
            \\    ^ [3]
        , .{true}, viewRelIndex("012345678", 10, .{ .left = .{ .len = 4 } }, .{ .trunc_mode = .hard_flex }));
        //                              ++~~
        //                              ---^
        try equal(
            \\ 5678 [5:9]
            \\      ^ [5]
        , .{true}, viewRelIndex("012345678", 10, .{ .left = .{ .len = 4 } }, .{ .trunc_mode = .soft }));
        //                            ++++
        //                              ---^
    }

    // [.exp_right] view mode
    {
        try equal(
            \\ 3 [3:4]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 3, .{ .exp_right = 0 }, .{}));
        //                           ^
        try equal(
            \\  [9:9]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 9, .{ .exp_right = 0 }, .{}));
        //                                 ^

        try equal(
            \\ 34567 [3:8]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 3, .{ .exp_right = 4 }, .{}));
        //                           ^----
        try equal(
            \\  [9:9]
            \\  ^ [1]
        , .{true}, viewRelIndex("012345678", 10, .{ .exp_right = 4 }, .{ .trunc_mode = .hard }));
        //                                 ^----
        try equal(
            \\ 678 [6:9]
            \\     ^ [4]
        , .{true}, viewRelIndex("012345678", 10, .{ .exp_right = 4 }, .{ .trunc_mode = .hard_flex }));
        //                             +++
        //                                 ^----
        try equal(
            \\ 45678 [4:9]
            \\       ^ [6]
        , .{true}, viewRelIndex("012345678", 10, .{ .exp_right = 4 }, .{ .trunc_mode = .soft }));
        //                           +++++ ^----
    }

    // [.exp_left] view mode
    {
        try equal(
            \\ 3 [3:4]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 3, .{ .exp_left = 0 }, .{}));
        //                           ^
        try equal(
            \\  [9:9]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 9, .{ .exp_left = 0 }, .{}));
        //                                 ^

        try equal(
            \\ 12345 [1:6]
            \\     ^ [4]
        , .{false}, viewRelIndex("012345678", 5, .{ .exp_left = 4 }, .{}));
        //                         ----^
        try equal(
            \\ 678 [6:9]
            \\     ^ [4]
        , .{true}, viewRelIndex("012345678", 10, .{ .exp_left = 4 }, .{ .trunc_mode = .hard }));
        //                             ----^
        try equal(
            \\ 678 [6:9]
            \\     ^ [4]
        , .{true}, viewRelIndex("012345678", 10, .{ .exp_left = 4 }, .{ .trunc_mode = .hard_flex }));
        //                             +++
        //                             ----^
        try equal(
            \\ 45678 [4:9]
            \\       ^ [6]
        , .{true}, viewRelIndex("012345678", 10, .{ .exp_left = 4 }, .{ .trunc_mode = .soft }));
        //                           +++++
        //                             ----^
    }

    // [.exp_sides] view mode
    {
        try equal(
            \\ 3 [3:4]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 3, .{ .exp_sides = 0 }, .{}));
        //                           ^
        try equal(
            \\  [9:9]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 9, .{ .exp_sides = 0 }, .{}));
        //                                 ^

        try equal(
            \\ 1234567 [1:8]
            \\    ^ [3]
        , .{false}, viewRelIndex("012345678", 4, .{ .exp_sides = 3 }, .{}));
        //                         ---^---
        try equal(
            \\ 78 [7:9]
            \\    ^ [3]
        , .{true}, viewRelIndex("012345678", 10, .{ .exp_sides = 3 }, .{ .trunc_mode = .hard }));
        //                              ---^---
        try equal(
            \\ 45678 [4:9]
            \\       ^ [6]
        , .{true}, viewRelIndex("012345678", 10, .{ .exp_sides = 3 }, .{ .trunc_mode = .hard_flex }));
        //                           +++++
        //                              ---^---
        try equal(
            \\ 2345678 [2:9]
            \\         ^ [8]
        , .{true}, viewRelIndex("012345678", 10, .{ .exp_sides = 3 }, .{ .trunc_mode = .soft }));
        //                         +++++++
        //                              ---^---
    }

    // [.exp_custom] view mode
    {
        try equal(
            \\ 1234567 [1:8]
            \\   ^ [2]
        , .{false}, viewRelIndex("012345678", 3, .{ .exp_custom = .{ .left = 2, .right = 4 } }, .{}));
        //                         --^----
    }

    // [.extra_shift]
    {
        try equal(
            \\ 3456 [3:7]
            \\  ^ [1]
        , .{false}, viewRelIndex("012345678", 4, .{ .left = .{ .len = 4 } }, .{ .extra_shift = .{ .right = 2 } }));
        //                         ---^>>
        try equal(
            \\ 2345 [2:6]
            \\   ^ [2]
        , .{false}, viewRelIndex("012345678", 4, .{ .right = .{ .len = 4 } }, .{ .extra_shift = .{ .left = 2 } }));
        //                          <<^---
    }
}

test viewRelRange {
    const input = "0123456789"; // must be in sync with first viewRelRange arg
    const equal = struct {
        pub fn run(comptime expect: []const u8, extra: anytype, view: ?View(.range)) !void {
            var buf = std.BoundedArray(u8, 1024){};
            const writer = buf.writer();
            if (view) |v| {
                try v.render(writer, input);
                try std.testing.expectEqualStrings(expect ++ "\n", buf.slice());
                try std.testing.expectEqual(extra[0], v.startPosExceeds());
                try std.testing.expectEqual(extra[1], v.endPosExceeds());
            } else {
                try writer.print(" null", .{});
                try std.testing.expectEqualStrings(expect, buf.slice());
            }
        }
    }.run;

    // [.around] view mode
    {
        // [start == end]
        //
        try equal(
            \\ 3 [3:4]
            \\ ^ [0] len=1
        , .{ false, false }, viewRelRange("0123456789", .{ 3, 3 }, .{ .around = .{ .len = 1 } }, .{}));
        //                                    ^
        try equal(
            \\ null
        , .{ false, false }, viewRelRange("0123456789", .{ 3, 3 }, .{ .right = .{ .len = 0 } }, .{}));
        //                                    ^
        try equal(
            \\  [10:10]
            \\  ^ [1] len=1
        , .{ true, true }, viewRelRange("0123456789", .{ 11, 11 }, .{ .right = .{ .len = 1 } }, .{}));
        //                                          ^

        // range fits view len
        //
        try equal(
            \\ 34 [3:5]
            \\ ^^ [0:1] len=2
        , .{ false, false }, viewRelRange("0123456789", .{ 3, 4 }, .{ .around = .{ .len = 2 } }, .{}));
        //                                    ^^
        try equal(
            \\ 3456 [3:7]
            \\ ^~~^ [0:3] len=4
        , .{ false, false }, viewRelRange("0123456789", .{ 3, 6 }, .{ .around = .{ .len = 4 } }, .{}));
        //                                    ^~~^
        try equal(
            \\ 89 [8:10]
            \\ ^~~^ [0:3] len=4
        , .{ false, true }, viewRelRange("0123456789", .{ 8, 11 }, .{ .around = .{ .len = 4 } }, .{}));
        //                                        ^~~^
        try equal(
            \\  [10:10]
            \\  ^~~^ [1:4] len=4
        , .{ true, true }, viewRelRange("0123456789", .{ 11, 14 }, .{ .around = .{ .len = 4 } }, .{}));
        //                                           ^~~^

        // [.min_pad]
        //
        try equal(
            \\ null
        , .{ false, false }, viewRelRange("0123456789", .{ 3, 4 }, .{ .around = .{ .len = 1, .min_pad = 0 } }, .{}));
        //                                    ^^
        try equal(
            \\ null
        , .{ false, false }, viewRelRange("0123456789", .{ 3, 7 }, .{ .around = .{ .len = 4, .min_pad = 0 } }, .{}));
        //                                    ^~~~^ [len=5]
        try equal(
            \\ 1234567 [1:8]
            \\   ^~^ [2:4] len=3
        , .{ false, false }, viewRelRange("0123456789", .{ 3, 5 }, .{ .around = .{ .len = 7, .min_pad = 2 } }, .{}));
        //                                  --^~^--
        try equal(
            \\ null
        , .{ false, false }, viewRelRange("0123456789", .{ 3, 5 }, .{ .around = .{ .len = 7, .min_pad = 3 } }, .{}));
        //                                 %--^~^--%

        // [.rshift_uneven = *]
        try equal(
            \\ 234567 [2:8]
            \\  ^~^ [1:3] len=3
        , .{ false, false }, viewRelRange("0123456789", .{ 3, 5 }, .{ .around = .{ .len = 6 } }, .{ .rshift_uneven = true }));
        //                                   -^~^--
        try equal(
            \\ 123456 [1:7]
            \\   ^~^ [2:4] len=3
        , .{ false, false }, viewRelRange("0123456789", .{ 3, 5 }, .{ .around = .{ .len = 6 } }, .{ .rshift_uneven = false }));
        //                                  --^~^-

        // [.trunc_mode = hard]
        try equal(
            \\ 01234 [0:5]
            \\ ^~^ [0:2] len=3
        , .{ false, false }, viewRelRange("0123456789", .{ 0, 2 }, .{ .around = .{ .len = 7 } }, .{ .trunc_mode = .hard }));
        //                               --^~^--
        try equal(
            \\ 56789 [5:10]
            \\   ^~^ [2:4] len=3
        , .{ false, false }, viewRelRange("0123456789", .{ 7, 9 }, .{ .around = .{ .len = 7 } }, .{ .trunc_mode = .hard }));
        //                                      --^~^--

        // [.trunc_mode = hard_flex]
        try equal(
            \\ 0123456 [0:7]
            \\ ^~^ [0:2] len=3
        , .{ false, false }, viewRelRange("0123456789", .{ 0, 2 }, .{ .around = .{ .len = 7 } }, .{ .trunc_mode = .hard_flex }));
        //                               --^~^--++
        try equal(
            \\ 3456789 [3:10]
            \\     ^~^ [4:6] len=3
        , .{ false, false }, viewRelRange("0123456789", .{ 7, 9 }, .{ .around = .{ .len = 7 } }, .{ .trunc_mode = .hard_flex }));
        //                                    ++--^~^--
        try equal(
            \\ 456789 [4:10]
            \\     ^~^ [4:6] len=3
        , .{ false, false }, viewRelRange("0123456789", .{ 8, 10 }, .{ .around = .{ .len = 7 } }, .{ .trunc_mode = .hard_flex }));
        //                                     ++--^~^--
        try equal(
            \\ 6789 [6:10]
            \\     ^~^ [4:6] len=3
        , .{ false, true }, viewRelRange("0123456789", .{ 10, 12 }, .{ .around = .{ .len = 7 } }, .{ .trunc_mode = .hard_flex }));
        //                                      ++--^~^--
    }

    // [.exp_sides] view mode
    {
        try equal(
            \\ 34 [3:5]
            \\ ^^ [0:1] len=2
        , .{ false, false }, viewRelRange("0123456789", .{ 3, 4 }, .{ .exp_sides = 0 }, .{}));
        //                                    ^^

        try equal(
            \\ 12345678 [1:9]
            \\   ^~~^ [2:5] len=4
        , .{ false, false }, viewRelRange("0123456789", .{ 3, 6 }, .{ .exp_sides = 2 }, .{}));
        //                                  --^~~^--
    }

    // [.exp_left] view mode
    {
        try equal(
            \\ 123456 [1:7]
            \\   ^~~^ [2:5] len=4
        , .{ false, false }, viewRelRange("0123456789", .{ 3, 6 }, .{ .exp_left = 2 }, .{}));
        //                                  --^~~^

        try equal(
            \\ 89 [8:10]
            \\   ^~~^ [2:5] len=4
        , .{ false, true }, viewRelRange("0123456789", .{ 10, 13 }, .{ .exp_left = 2 }, .{}));
        //                                        --^~~^

    }

    // [.exp_right] view mode
    {
        try equal(
            \\ 345678 [3:9]
            \\ ^~~^ [0:3] len=4
        , .{ false, false }, viewRelRange("0123456789", .{ 3, 6 }, .{ .exp_right = 2 }, .{}));
        //                                    ^~~^--
    }

    // [.exp_custom] view mode
    {
        try equal(
            \\ 12345678 [1:9]
            \\    ^~^ [3:5] len=3
        , .{ false, false }, viewRelRange("0123456789", .{ 4, 6 }, .{ .exp_custom = .{ .left = 3, .right = 2 } }, .{}));
        //                                  ---^~^--
    }
}

/// Returns a `[start..end]` slice segment with indices normalized to not
/// exceed the `slice.len`.
pub fn segment(T: type, slice: T, start: usize, end: usize) T {
    return slice[@min(start, slice.len)..@min(end, slice.len)];
}

test segment {
    const equal = std.testing.expectEqualStrings;

    try equal("", segment([]const u8, "0123", 0, 0));
    try equal("", segment([]const u8, "0123", 100, 100));
    try equal("", segment([]const u8, "0123", 3, 3));
    try equal("0", segment([]const u8, "0123", 0, 1));
    try equal("12", segment([]const u8, "0123", 1, 3));
    try equal("3", segment([]const u8, "0123", 3, 4));
}

/// Checks if the provided segment is a valid sub-slice of the given slice.
pub fn isSegment(T: type, slice: []const T, seg: []const T) bool {
    const slice_start = @intFromPtr(slice.ptr);
    const slice_end = @intFromPtr(slice.ptr + slice.len);
    const seg_start = @intFromPtr(seg.ptr);
    const seg_end = @intFromPtr(seg.ptr + seg.len);
    return num.inRangeInc(usize, seg_start, slice_start, slice_end) and
        num.inRangeInc(usize, seg_end, slice_start, slice_end);
}

test isSegment {
    const equal = std.testing.expectEqual;
    const input: [11]u8 = "hello_world".*;

    try equal(true, isSegment(u8, input[0..], input[0..0]));
    try equal(true, isSegment(u8, input[0..], input[11..11]));
    try equal(true, isSegment(u8, input[0..], input[0..1]));
    try equal(true, isSegment(u8, input[0..], input[3..6]));
    try equal(true, isSegment(u8, input[0..], input[10..11]));
    try equal(false, isSegment(u8, input[0..], "hello_world"));

    // intersecting
    try equal(true, isSegment(u8, input[0..5], input[0..5]));
    try equal(true, isSegment(u8, input[0..0], input[0..0]));
    try equal(true, isSegment(u8, input[11..11], input[11..11]));
    try equal(false, isSegment(u8, input[0..5], input[0..6]));
    try equal(false, isSegment(u8, input[0..5], input[5..10]));
    try equal(false, isSegment(u8, input[5..10], input[0..5]));
    try equal(false, isSegment(u8, input[0..0], input[11..11]));
    try equal(false, isSegment(u8, input[0..6], input[5..11]));
}

pub const MoveDir = enum { left, right };
pub const MoveError = error{ IsNotSeg, SegIsTooBig };

/// Moves a valid segment to the start or end of the given slice. If a move is
/// required, the segment length must be less than the stack-allocated buffer
/// size, `buf_size`.
pub fn move(
    comptime dir: MoveDir,
    comptime buf_size: usize,
    T: type,
    slice: []T,
    seg: []const T,
) MoveError!void {
    // skip move if
    if (!isSegment(T, slice, seg)) return MoveError.IsNotSeg;
    if (seg.len > buf_size) return MoveError.SegIsTooBig;

    // no need to move if
    if (seg.len == 0 or seg.len == slice.len) return;
    switch (dir) {
        .right => if (indexOfEnd(slice, seg) == slice.len) return,
        .left => if (indexOfStart(slice, seg) == 0) return,
    }

    // make segment copy
    var buf: [buf_size]T = undefined;
    const seg_copy = buf[0..seg.len];
    mem.copyForwards(T, seg_copy, seg);

    // swap slice segment with its opposite side
    switch (dir) {
        // [ [seg][seg_rhs] ] (step 0)
        // [ [seg_rhs]..... ] (step 1)
        // [ [seg_rhs][seg] ] (step 2)
        .right => {
            const seg_rhs = slice[indexOfEnd(slice, seg)..]; // step 0
            const start: usize = indexOfStart(slice, seg);
            const end: usize = start +| seg_rhs.len;
            mem.copyForwards(T, slice[start..end], seg_rhs); // step 1
            // copy seg to the end of slice
            mem.copyForwards(T, slice[slice.len -| seg_copy.len..], seg_copy); // step 2
        },
        // [ [seg_lhs][seg] ] (step 0)
        // [ .....[seg_lhs] ] (step 1)
        // [ [seg][seg_lhs] ] (step 2)
        .left => {
            const seg_lhs = slice[0..indexOfStart(slice, seg)]; // step 0
            const end: usize = indexOfEnd(slice, seg);
            const start: usize = end -| seg_lhs.len;
            mem.copyBackwards(T, slice[start..end], seg_lhs); // step 1
            // copy seg to the beginning of the slice
            mem.copyForwards(T, slice[0..seg_copy.len], seg_copy); // step 2
        },
    }
}

test move {
    const equal = std.testing.expectEqualStrings;
    const equalErr = std.testing.expectError;

    const origin = "0123456";
    var buf: [7]u8 = origin.*;
    const slice = buf[0..];

    // .right
    // -----------
    try move(.right, 512, u8, slice, slice[0..3]);
    try equal("3456012", slice);
    //             ---
    buf = origin.*;

    try move(.right, 512, u8, slice, slice[3..6]);
    try equal("0126345", slice);
    //             ---
    buf = origin.*;

    try move(.right, 512, u8, slice, slice); // move is not required
    try equal("0123456", slice);
    buf = origin.*;

    try move(.right, 512, u8, slice, slice[4..]); // move is not required
    try equal("0123456", slice);
    buf = origin.*;

    try move(.right, 512, u8, slice, slice[7..]); // zero length segment
    try equal("0123456", slice);
    buf = origin.*;

    try move(.right, 512, u8, slice, slice[3..3]); // zero length segment
    try equal("0123456", slice);
    buf = origin.*;

    // segment is non-valid sub-slice
    try equalErr(MoveError.IsNotSeg, move(.right, 512, u8, slice[0..4], slice[3..6]));

    // move a too-big-to-copy segment
    try equalErr(MoveError.SegIsTooBig, move(.right, 1, u8, slice, slice[1..]));

    // .left
    // -----------
    try move(.left, 512, u8, slice, slice[1..]);
    try equal("1234560", slice);
    //         ------
    buf = origin.*;

    try move(.left, 512, u8, slice, slice[4..]);
    try equal("4560123", slice);
    //         ---
    buf = origin.*;

    try move(.left, 512, u8, slice, slice[6..]);
    try equal("6012345", slice);
    //         -
    buf = origin.*;

    try move(.left, 512, u8, slice, slice); // move is not required
    try equal("0123456", slice);

    try move(.left, 512, u8, slice, slice[0..3]); // move is not required
    try equal("0123456", slice);

    try move(.left, 512, u8, slice, slice[7..]); // zero length segment
    try equal("0123456", slice);

    try move(.left, 512, u8, slice, slice[3..3]); // zero length segment
    try equal("0123456", slice);

    // move a non-valid segment
    try equalErr(MoveError.IsNotSeg, move(.left, 512, u8, slice[0..4], slice[3..6]));

    // move a too-big-to-copy segment
    try equalErr(MoveError.SegIsTooBig, move(.left, 1, u8, slice, slice[1..]));
}

/// Moves a valid segment to the beginning of the given slice. Returns an
/// error if the segment is of different origin or its length exceeds
/// 1024. Use `moveSeg` directly to increase the length.
pub fn moveLeft(T: type, slice: []T, seg: []const T) MoveError!void {
    return move(.left, 1024, T, slice, seg);
}

/// Moves a valid slice segment to the end of the given slice. Returns an error
/// if the segment is different origins or its length exceeds 1024. Use `moveSeg`
/// directly to increase the length.
pub fn moveRight(T: type, slice: []T, seg: []const T) MoveError!void {
    return move(.right, 1024, T, slice, seg);
}
