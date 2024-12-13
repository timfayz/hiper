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

/// Indices of a retrieved segment.
pub const View = struct {
    /// The start index of the segment.
    start: usize,
    /// The end index of the segment.
    end: usize,

    pub usingnamespace Shared(View);

    fn Shared(Self: type) type {
        return struct {
            /// Returns the retrieved segment length.
            pub fn len(self: *const Self) usize {
                return self.end - self.start;
            }

            /// Returns `input[self.start..self.end]`.
            pub fn slice(self: *const Self, T: type, input: T) T {
                return input[self.start..self.end];
            }
        };
    }

    /// Wraps `View` into `View.RelIndex`.
    pub fn toRelIndex(self: *const View, index: usize) RelIndex {
        return .{
            .start = self.start,
            .end = self.end,
            .index_pos = index - self.start,
        };
    }

    /// Wraps `View` into `View.RelRange`.
    pub fn toRelRange(self: *const View, start: usize, end: usize) RelRange {
        return .{
            .start = self.start,
            .end = self.end,
            .start_pos = start - self.start,
            .end_pos = end - self.start,
        };
    }

    /// Options for view primitives.
    pub const Options = struct {
        /// Defines how view primitives truncate view span on overrun.
        trunc_mode: TruncMode = .hard_flex,
        /// Extra shift to the precalculated view span.
        extra_shift: ?union(enum) { right: usize, left: usize } = null,
        /// Shifts uneven padding around the index/range by one to the right.
        rshift_uneven: bool = true,
        /// Minimum padding around the view size before returning null.
        /// Applies only to the `.around` range-relative view mode.
        min_pad: usize = 0,

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

    /// Indices of a retrieved segment around an index.
    pub const RelIndex = struct {
        /// The start index of the segment.
        start: usize,
        /// The end index of the segment.
        end: usize,
        /// Position of the original `index` relative to the segment.
        index_pos: usize,

        pub usingnamespace Shared(RelIndex);

        /// Checks if the relative index position exceeds the actual segment
        /// boundaries.
        pub fn indexPosExceeds(self: *const RelIndex) bool {
            return self.index_pos > self.len();
        }

        /// Wraps `View.RelIndex` into `View.RelRange`.
        pub fn toRelRange(self: *const RelIndex) RelRange {
            return .{
                .start = self.start,
                .end = self.end,
                .start_pos = self.index_pos,
                .end_pos = self.index_pos,
            };
        }

        pub fn debugRender(self: *const RelIndex, writer: anytype, input: []const u8) !void {
            // render input
            try writer.print(" {s} [{d}:{d}]\n", .{
                self.slice([]const u8, input),
                self.start,
                self.end,
            });
            // render cursor ^
            try writer.print(" {[0]c: >[1]} [{[2]d}]", .{
                '^', // [0]
                self.index_pos + 1, // [1] pad before ^
                self.index_pos, // [2]
            });
        }
    };

    /// Indices of a retrieved segment within a range.
    pub const RelRange = struct {
        /// The start index of the segment.
        start: usize,
        /// The end index of the segment.
        end: usize,
        /// Position of the original `start` index relative to the segment.
        start_pos: usize,
        /// Position of the original `end` index relative to the segment.
        end_pos: usize,

        pub usingnamespace Shared(RelRange);

        /// Returns the length of the requested segment range.
        pub fn rangeLen(self: *const RelRange) usize {
            return self.end_pos - self.start_pos +| 1;
        }

        /// Checks if the relative range start position exceeds the actual segment
        /// boundaries.
        pub fn startPosExceeds(self: *const RelRange) bool {
            return self.start_pos > self.len();
        }

        /// Checks if the relative range end position exceeds the actual segment
        /// boundaries.
        pub fn endPosExceeds(self: *const RelRange) bool {
            return self.end_pos > self.len();
        }

        pub fn debugRender(self: *const RelRange, writer: anytype, input: []const u8) !void {
            // render input
            try writer.print(" {s} [{d}:{d}]\n", .{
                self.slice([]const u8, input),
                self.start,
                self.end,
            });
            // render cursor ^ or ^~~^
            if (self.start_pos == self.end_pos)
                try writer.print(" {[0]c: >[1]} [{[2]d}]", .{
                    '^', // [0]
                    self.start_pos + 1, // [1] pad before ^
                    self.start_pos, // [2]
                })
            else
                try writer.print(" {[0]c: >[1]}{[0]c:~>[2]} [{[3]d}:{[4]d}]", .{
                    '^', // [0]
                    self.start_pos + 1, // [1] pad before first ^
                    self.end_pos - self.start_pos, // [2] pad before second ^
                    self.start_pos, // [3]
                    self.end_pos, // [4]
                });
            try writer.print(" len={d}", .{self.rangeLen()});
        }
    };

    /// Modes for positioning slice views relative to an index or range.
    pub const Mode = union(enum) {
        /// Centers view on index/range, splitting length equally on both sides.
        around: usize,
        /// Positions view to the left, including index/range in its length.
        left: usize,
        /// Positions view to the right, including index/range in its length.
        right: usize,
        /// Expands view sides around index/range by the length.
        exp_sides: usize,
        /// Expands the left side of view relative to index/range by length.
        exp_left: usize,
        /// Expands the right side of view relative to index/range by length.
        exp_right: usize,
        /// Custom left and right spans relative to index/range.
        exp_custom: Span,

        pub fn len(self: Mode) usize {
            return switch (self) {
                .exp_custom => |amt| amt.left + amt.right,
                inline else => |amt| amt,
            };
        }
    };

    /// Helper to calculate correct start:end indices for different view modes.
    const Span = struct {
        left: usize,
        right: usize,

        pub fn shiftLeft(self: *Span, amt: usize) void {
            self.left +|= amt;
            self.right -|= amt;
        }

        pub fn shiftRight(self: *Span, amt: usize) void {
            self.left -|= amt;
            self.right +|= amt;
        }

        pub fn len(self: *const Span) usize {
            return self.left +| self.right;
        }

        pub fn init(
            mode: View.Mode,
            middle_len: usize,
            comptime opt: View.Options,
        ) ?Span {
            var view: View.Span = undefined;
            switch (mode) {
                inline .around, .left, .right => |view_len, tag| {
                    // check if the range fits
                    if (middle_len +| opt.min_pad *| 2 > view_len)
                        return null;
                    // otherwise distribute available space
                    const len_left = view_len - middle_len;
                    switch (tag) {
                        .around => {
                            const pad = len_left / 2;
                            view = View.Span{ .left = pad, .right = pad };
                            if (len_left & 1 != 0) { // compensate lost item during odd division
                                if (opt.rshift_uneven) view.right +|= 1 else view.left +|= 1;
                            }
                        },
                        .left => view = View.Span{ .left = len_left, .right = 0 },
                        .right => view = View.Span{ .left = 0, .right = len_left },
                        else => unreachable,
                    }
                },
                .exp_sides => |view_len| view = View.Span{ .left = view_len, .right = view_len },
                .exp_left => |view_len| view = View.Span{ .left = view_len, .right = 0 },
                .exp_right => |view_len| view = View.Span{ .left = 0, .right = view_len },
                .exp_custom => |view_len| view = View.Span{ .left = view_len.left, .right = view_len.right },
            }

            // include cursor's thickness
            view.right +|= middle_len;

            // extra shift
            if (opt.extra_shift) |shift| {
                switch (shift) {
                    .left => |amt| view.shiftLeft(amt),
                    .right => |amt| view.shiftRight(amt),
                }
            }

            return view;
        }

        pub fn retrieve(
            self: *const Span,
            slice: anytype,
            index: usize,
            index_width: usize,
            comptime opt: View.Options,
        ) View {
            const span_len = self.len();
            const slice_start = @min(
                index -| self.left,
                switch (opt.trunc_mode) {
                    .hard => slice.len,
                    .hard_flex => b: {
                        const index_end = index + (index_width -| 1);
                        const overrun = index_end -| (slice.len -| 1);
                        break :b slice.len -| (span_len -| overrun);
                    },
                    .soft => slice.len -| span_len,
                },
            );
            const slice_end = @min(
                slice.len,
                switch (opt.trunc_mode) {
                    .hard => index +| self.right,
                    .hard_flex, .soft => slice_start +| span_len,
                },
            );
            return .{ .start = slice_start, .end = slice_end };
        }
    };
};

/// Returns a slice beginning of the length `len`.
/// Indices are bounded by slice length.
pub fn viewStart(slice: anytype, len: usize) View {
    return .{ .start = 0, .end = @min(slice.len, len) };
}

test viewStart {
    const equal = std.testing.expectEqualDeep;

    try equal(View{ .start = 0, .end = 0 }, viewStart("", 0)); // ""
    try equal(View{ .start = 0, .end = 0 }, viewStart("012", 0)); // ""
    try equal(View{ .start = 0, .end = 1 }, viewStart("012", 1)); // "0"
    try equal(View{ .start = 0, .end = 2 }, viewStart("012", 2)); // "01"
    try equal(View{ .start = 0, .end = 3 }, viewStart("012", 3)); // "012"
    try equal(View{ .start = 0, .end = 3 }, viewStart("012", 4)); // "012"
}

/// Returns a slice ending of the length `len`.
/// Indices are bounded by slice length.
pub fn viewEnd(slice: anytype, len: usize) View {
    return .{ .start = slice.len -| len, .end = slice.len };
}

test viewEnd {
    const equal = std.testing.expectEqualDeep;

    try equal(View{ .start = 0, .end = 0 }, viewEnd("", 0)); // ""
    try equal(View{ .start = 3, .end = 3 }, viewEnd("012", 0)); // ""
    try equal(View{ .start = 2, .end = 3 }, viewEnd("012", 1)); // "2"
    try equal(View{ .start = 1, .end = 3 }, viewEnd("012", 2)); // "12"
    try equal(View{ .start = 0, .end = 3 }, viewEnd("012", 3)); // "012"
    try equal(View{ .start = 0, .end = 3 }, viewEnd("012", 4)); // "012"
}

/// Returns a slice segment of length `len` relative to the index and according
/// to the view `mode`. The returned index position may be out of bounds if the
/// original index is outside the slice. See tests for examples of how
/// `View.Size.Mode` and `View.Options.TruncMode` work.
pub fn viewRelIndex(
    slice: anytype,
    index: usize,
    mode: View.Mode,
    comptime opt: View.Options,
) View.RelIndex {
    var view: View.Span = View.Span.init(mode, 1, opt) orelse { // zero len view
        const i = @min(index, slice.len);
        return .{ .start = i, .end = i, .index_pos = index -| i };
    };
    return view.retrieve(slice, index, 0, opt).toRelIndex(index);
}

test viewRelIndex {
    // if (true) return;
    const input = "012345678"; // must be in sync with the first viewRelIndex arg
    const equal = struct {
        pub fn run(expect: []const u8, extra: anytype, view: View.RelIndex) !void {
            var buf = std.BoundedArray(u8, 1024){};
            try view.debugRender(buf.writer(), input);
            try std.testing.expectEqualStrings(expect, buf.slice());
            try std.testing.expectEqual(extra[0], view.indexPosExceeds());
        }
    }.run;

    // exceeding view len
    // -------------------
    {
        try equal(
            \\ 012345678 [0:9]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 0, .{ .around = 100 }, .{}));
        //                        ^
        try equal(
            \\ 012345678 [0:9]
            \\            ^ [11]
        , .{true}, viewRelIndex("012345678", 11, .{ .around = 100 }, .{}));
        //                                  ^
    }

    // [.around]
    // -------------------
    // [.trunc_mode = *]
    {
        // zero len
        //
        try equal(
            \\  [4:4]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 4, .{ .around = 0 }, .{ .trunc_mode = .hard }));
        //                            ^
        try equal(
            \\  [4:4]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 4, .{ .around = 0 }, .{ .trunc_mode = .hard_flex }));
        //                            ^
        try equal(
            \\  [4:4]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 4, .{ .around = 0 }, .{ .trunc_mode = .soft }));
        //                            ^

        try equal(
            \\  [9:9]
            \\  ^ [1]
        , .{true}, viewRelIndex("012345678", 10, .{ .around = 0 }, .{ .trunc_mode = .hard }));
        //                                  ^
        try equal(
            \\  [9:9]
            \\  ^ [1]
        , .{true}, viewRelIndex("012345678", 10, .{ .around = 0 }, .{ .trunc_mode = .hard_flex }));
        //                                  ^
        try equal(
            \\  [9:9]
            \\  ^ [1]
        , .{true}, viewRelIndex("012345678", 10, .{ .around = 0 }, .{ .trunc_mode = .soft }));
        //                                  ^

        // odd len (1)
        //
        try equal(
            \\ 4 [4:5]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 4, .{ .around = 1 }, .{ .trunc_mode = .hard }));
        //                            ^
        try equal(
            \\ 4 [4:5]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 4, .{ .around = 1 }, .{ .trunc_mode = .hard_flex }));
        //                            ^
        try equal(
            \\ 4 [4:5]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 4, .{ .around = 1 }, .{ .trunc_mode = .soft }));
        //                            ^

        // [.rshift_uneven = false]
        try equal(
            \\ 4 [4:5]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 4, .{ .around = 1 }, .{ .rshift_uneven = false }));
        //                            ^

        try equal(
            \\  [9:9]
            \\  ^ [1]
        , .{true}, viewRelIndex("012345678", 10, .{ .around = 1 }, .{ .trunc_mode = .hard }));
        //                                 ^
        try equal(
            \\  [9:9]
            \\  ^ [1]
        , .{true}, viewRelIndex("012345678", 10, .{ .around = 1 }, .{ .trunc_mode = .hard_flex }));
        //                                 ^
        try equal(
            \\ 8 [8:9]
            \\   ^ [2]
        , .{true}, viewRelIndex("012345678", 10, .{ .around = 1 }, .{ .trunc_mode = .soft }));
        //                                 ^

        // even len (2)
        //
        try equal(
            \\ 45 [4:6]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 4, .{ .around = 2 }, .{}));
        //                            ^-

        // [.rshift_uneven = false]
        try equal(
            \\ 34 [3:5]
            \\  ^ [1]
        , .{false}, viewRelIndex("012345678", 4, .{ .around = 2 }, .{ .rshift_uneven = false }));
        //                           -^

        // even len (4)
        //
        try equal(
            \\ 3456 [3:7]
            \\  ^ [1]
        , .{false}, viewRelIndex("012345678", 4, .{ .around = 4 }, .{ .rshift_uneven = true }));
        //                           -^--

        // [.rshift_uneven = false]
        try equal(
            \\ 2345 [2:6]
            \\   ^ [2]
        , .{false}, viewRelIndex("012345678", 4, .{ .around = 4 }, .{ .rshift_uneven = false }));
        //                          --^-

        try equal(
            \\ 012 [0:3]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 0, .{ .around = 4 }, .{ .trunc_mode = .hard, .rshift_uneven = true }));
        //                       -^--
        try equal(
            \\ 0123 [0:4]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 0, .{ .around = 4 }, .{ .trunc_mode = .hard_flex, .rshift_uneven = true }));
        //                       -^--+
        try equal(
            \\ 0123 [0:4]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 0, .{ .around = 4 }, .{ .trunc_mode = .soft, .rshift_uneven = true }));
        //                       -^--+

        // [.rshift_uneven = false]
        try equal(
            \\ 01 [0:2]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 0, .{ .around = 4 }, .{ .trunc_mode = .hard, .rshift_uneven = false }));
        //                      --^-
        try equal(
            \\ 0123 [0:4]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 0, .{ .around = 4 }, .{ .trunc_mode = .hard_flex, .rshift_uneven = false }));
        //                      --^-++
        try equal(
            \\ 0123 [0:4]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 0, .{ .around = 4 }, .{ .trunc_mode = .soft, .rshift_uneven = false }));
        //                      --^-++

        try equal(
            \\ 8 [8:9]
            \\  ^ [1]
        , .{false}, viewRelIndex("012345678", 9, .{ .around = 4 }, .{ .trunc_mode = .hard, .rshift_uneven = true }));
        //                                -^--
        try equal(
            \\ 678 [6:9]
            \\    ^ [3]
        , .{false}, viewRelIndex("012345678", 9, .{ .around = 4 }, .{ .trunc_mode = .hard_flex, .rshift_uneven = true }));
        //                              ++-^--
        try equal(
            \\ 5678 [5:9]
            \\     ^ [4]
        , .{false}, viewRelIndex("012345678", 9, .{ .around = 4 }, .{ .trunc_mode = .soft, .rshift_uneven = true }));
        //                             +++-^--

        // [.rshift_uneven = false]
        try equal(
            \\ 78 [7:9]
            \\   ^ [2]
        , .{false}, viewRelIndex("012345678", 9, .{ .around = 4 }, .{ .trunc_mode = .hard, .rshift_uneven = false }));
        //                               --^-
        try equal(
            \\ 678 [6:9]
            \\    ^ [3]
        , .{false}, viewRelIndex("012345678", 9, .{ .around = 4 }, .{ .trunc_mode = .hard_flex, .rshift_uneven = false }));
        //                              +--^-
        try equal(
            \\ 5678 [5:9]
            \\     ^ [4]
        , .{false}, viewRelIndex("012345678", 9, .{ .around = 4 }, .{ .trunc_mode = .soft, .rshift_uneven = false }));
        //                             ++--^-

        // odd len (5)
        //
        try equal(
            \\ 23456 [2:7]
            \\   ^ [2]
        , .{false}, viewRelIndex("012345678", 4, .{ .around = 5 }, .{ .trunc_mode = .hard }));
        //                          --^--

        try equal(
            \\ 012 [0:3]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 0, .{ .around = 5 }, .{ .trunc_mode = .hard }));
        //                      --^--
        try equal(
            \\ 01234 [0:5]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 0, .{ .around = 5 }, .{ .trunc_mode = .hard_flex }));
        //                      --^--++
        try equal(
            \\ 01234 [0:5]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 0, .{ .around = 5 }, .{ .trunc_mode = .soft }));
        //                      --^--++

        try equal(
            \\ 78 [7:9]
            \\   ^ [2]
        , .{false}, viewRelIndex("012345678", 9, .{ .around = 5 }, .{ .trunc_mode = .hard }));
        //                               --^--
        try equal(
            \\ 5678 [5:9]
            \\     ^ [4]
        , .{false}, viewRelIndex("012345678", 9, .{ .around = 5 }, .{ .trunc_mode = .hard_flex }));
        //                             ++--^--
        try equal(
            \\ 45678 [4:9]
            \\      ^ [5]
        , .{false}, viewRelIndex("012345678", 9, .{ .around = 5 }, .{ .trunc_mode = .soft }));
        //                            +++--^--
    }

    // [.right]
    // -------------------
    // [.trunc_mode = *]
    {
        try equal(
            \\  [4:4]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 4, .{ .right = 0 }, .{}));
        //                            ^
        try equal(
            \\  [9:9]
            \\  ^ [1]
        , .{true}, viewRelIndex("012345678", 10, .{ .right = 0 }, .{}));
        //                                 ^

        try equal(
            \\ 4567 [4:8]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 4, .{ .right = 4 }, .{}));
        //                            ^---
        try equal(
            \\  [9:9]
            \\  ^ [1]
        , .{true}, viewRelIndex("012345678", 10, .{ .right = 4 }, .{ .trunc_mode = .hard }));
        //                                  ^---
        try equal(
            \\ 78 [7:9]
            \\    ^ [3]
        , .{true}, viewRelIndex("012345678", 10, .{ .right = 4 }, .{ .trunc_mode = .hard_flex }));
        //                              ++ ^---
        try equal(
            \\ 5678 [5:9]
            \\      ^ [5]
        , .{true}, viewRelIndex("012345678", 10, .{ .right = 4 }, .{ .trunc_mode = .soft }));
        //                            ++++ ^---
    }

    // [.left]
    // -------------------
    // [.trunc_mode = *]
    {
        try equal(
            \\  [4:4]
            \\ ^ [0]
        , .{false}, viewRelIndex("012345678", 4, .{ .left = 0 }, .{}));
        //                            ^
        try equal(
            \\  [9:9]
            \\  ^ [1]
        , .{true}, viewRelIndex("012345678", 10, .{ .left = 0 }, .{}));
        //                                 ^

        try equal(
            \\ 1234 [1:5]
            \\    ^ [3]
        , .{false}, viewRelIndex("012345678", 4, .{ .left = 4 }, .{}));
        //                         ---^
        try equal(
            \\ 78 [7:9]
            \\    ^ [3]
        , .{true}, viewRelIndex("012345678", 10, .{ .left = 4 }, .{ .trunc_mode = .hard }));
        //                              ---^
        try equal(
            \\ 78 [7:9]
            \\    ^ [3]
        , .{true}, viewRelIndex("012345678", 10, .{ .left = 4 }, .{ .trunc_mode = .hard_flex }));
        //                              ++~~
        //                              ---^
        try equal(
            \\ 5678 [5:9]
            \\      ^ [5]
        , .{true}, viewRelIndex("012345678", 10, .{ .left = 4 }, .{ .trunc_mode = .soft }));
        //                            ++++
        //                              ---^
    }

    // [.exp_right]
    // -------------------
    // [.trunc_mode = *]
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

    // [.exp_left]
    // -------------------
    // [.trunc_mode = *]
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

    // [.exp_sides]
    // -------------------
    // [.trunc_mode = *]
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

    // [.exp_custom]
    // -------------------
    // [.trunc_mode = *]
    {
        try equal(
            \\ 1234567 [1:8]
            \\   ^ [2]
        , .{false}, viewRelIndex("012345678", 3, .{ .exp_custom = .{ .left = 2, .right = 4 } }, .{}));
        //                         --^----
    }

    // [.extra_shift = *]
    // -------------------
    {
        try equal(
            \\ 3456 [3:7]
            \\  ^ [1]
        , .{false}, viewRelIndex("012345678", 4, .{ .left = 4 }, .{ .extra_shift = .{ .right = 2 } }));
        //                         ---^>>
        try equal(
            \\ 2345 [2:6]
            \\   ^ [2]
        , .{false}, viewRelIndex("012345678", 4, .{ .right = 4 }, .{ .extra_shift = .{ .left = 2 } }));
        //                          <<^---
    }
}

/// Returns a slice segment of length `len` relative to `start`-`end` range and
/// according to the view `mode`. The returned positions (`*_pos`) may be out of
/// bounds if the original range is outside the slice.
pub fn viewRelRange(
    slice: anytype,
    start: usize,
    end: usize,
    mode: View.Mode,
    comptime opt: View.Options,
) ?View.RelRange {
    if (start == end)
        return viewRelIndex(slice, start, mode, opt).toRelRange();

    // ensure start <= end
    const s, const e = if (start < end) .{ start, end } else .{ end, start };
    const range_len = e - s +| 1; // +1 makes end inclusive

    const view = View.Span.init(mode, range_len, opt) orelse return null;
    return view.retrieve(slice, s, range_len, opt).toRelRange(s, e);
}

test viewRelRange {
    // if (true) return;
    const input = "0123456789"; // must be in sync with first viewRelRange arg
    const equal = struct {
        pub fn run(expect: []const u8, extra: anytype, view: ?View.RelRange) !void {
            var buf = std.BoundedArray(u8, 1024){};
            const writer = buf.writer();
            if (view) |v| {
                try v.debugRender(writer, input);
                try std.testing.expectEqualStrings(expect, buf.slice());
                try std.testing.expectEqual(extra[0], v.startPosExceeds());
                try std.testing.expectEqual(extra[1], v.endPosExceeds());
            } else {
                try writer.print(" null", .{});
                try std.testing.expectEqualStrings(expect, buf.slice());
            }
        }
    }.run;

    // [start == end]
    // ----------------
    // fallback to viewRelIndex
    {
        try equal(
            \\ 3456 [3:7]
            \\ ^ [0] len=1
        , .{ false, false }, viewRelRange("0123456789", 3, 3, .{ .right = 4 }, .{}));
        //                                    ^
        try equal(
            \\  [3:3]
            \\ ^ [0] len=1
        , .{ false, false }, viewRelRange("0123456789", 3, 3, .{ .right = 0 }, .{}));
        //                                    ^
        try equal(
            \\  [10:10]
            \\  ^ [1] len=1
        , .{ true, true }, viewRelRange("0123456789", 11, 11, .{ .right = 0 }, .{}));
        //                                          ^
    }

    // [.around] view mode
    // ----------------
    {
        // range fits view len
        //
        try equal(
            \\ 34 [3:5]
            \\ ^^ [0:1] len=2
        , .{ false, false }, viewRelRange("0123456789", 3, 4, .{ .around = 2 }, .{}));
        //                                    ^^
        try equal(
            \\ 3456 [3:7]
            \\ ^~~^ [0:3] len=4
        , .{ false, false }, viewRelRange("0123456789", 3, 6, .{ .around = 4 }, .{}));
        //                                    ^~~^
        try equal(
            \\ 89 [8:10]
            \\ ^~~^ [0:3] len=4
        , .{ false, true }, viewRelRange("0123456789", 8, 11, .{ .around = 4 }, .{}));
        //                                        ^~~^
        try equal(
            \\  [10:10]
            \\  ^~~^ [1:4] len=4
        , .{ true, true }, viewRelRange("0123456789", 11, 14, .{ .around = 4 }, .{}));
        //                                           ^~~^

        // [.min_pad] range doesn't fit view len
        //
        try equal(
            \\ null
        , .{ false, false }, viewRelRange("0123456789", 3, 4, .{ .around = 1 }, .{ .min_pad = 0 }));
        //                                    ^^
        try equal(
            \\ null
        , .{ false, false }, viewRelRange("0123456789", 3, 7, .{ .around = 4 }, .{ .min_pad = 0 }));
        //                                    ^~~~^ [len=5]
        try equal(
            \\ 1234567 [1:8]
            \\   ^~^ [2:4] len=3
        , .{ false, false }, viewRelRange("0123456789", 3, 5, .{ .around = 7 }, .{ .min_pad = 2 }));
        //                                  --^~^--
        try equal(
            \\ null
        , .{ false, false }, viewRelRange("0123456789", 3, 5, .{ .around = 7 }, .{ .min_pad = 3 }));
        //                                 %--^~^--%

        // [.rshift_uneven = *]
        try equal(
            \\ 234567 [2:8]
            \\  ^~^ [1:3] len=3
        , .{ false, false }, viewRelRange("0123456789", 3, 5, .{ .around = 6 }, .{ .rshift_uneven = true }));
        //                                   -^~^--
        try equal(
            \\ 123456 [1:7]
            \\   ^~^ [2:4] len=3
        , .{ false, false }, viewRelRange("0123456789", 3, 5, .{ .around = 6 }, .{ .rshift_uneven = false }));
        //                                  --^~^-

        // [.trunc_mode = hard]
        try equal(
            \\ 01234 [0:5]
            \\ ^~^ [0:2] len=3
        , .{ false, false }, viewRelRange("0123456789", 0, 2, .{ .around = 7 }, .{ .trunc_mode = .hard }));
        //                               --^~^--
        try equal(
            \\ 56789 [5:10]
            \\   ^~^ [2:4] len=3
        , .{ false, false }, viewRelRange("0123456789", 7, 9, .{ .around = 7 }, .{ .trunc_mode = .hard }));
        //                                      --^~^--

        // [.trunc_mode = hard_flex]
        try equal(
            \\ 0123456 [0:7]
            \\ ^~^ [0:2] len=3
        , .{ false, false }, viewRelRange("0123456789", 0, 2, .{ .around = 7 }, .{ .trunc_mode = .hard_flex }));
        //                               --^~^--++
        try equal(
            \\ 3456789 [3:10]
            \\     ^~^ [4:6] len=3
        , .{ false, false }, viewRelRange("0123456789", 7, 9, .{ .around = 7 }, .{ .trunc_mode = .hard_flex }));
        //                                    ++--^~^--
        try equal(
            \\ 456789 [4:10]
            \\     ^~^ [4:6] len=3
        , .{ false, false }, viewRelRange("0123456789", 8, 10, .{ .around = 7 }, .{ .trunc_mode = .hard_flex }));
        //                                     ++--^~^--
        try equal(
            \\ 6789 [6:10]
            \\     ^~^ [4:6] len=3
        , .{ false, true }, viewRelRange("0123456789", 10, 12, .{ .around = 7 }, .{ .trunc_mode = .hard_flex }));
        //                                      ++--^~^--
    }

    // [.exp_sides] view mode
    // ----------------
    {
        try equal(
            \\ 34 [3:5]
            \\ ^^ [0:1] len=2
        , .{ false, false }, viewRelRange("0123456789", 3, 4, .{ .exp_sides = 0 }, .{}));
        //                                    ^^

        try equal(
            \\ 12345678 [1:9]
            \\   ^~~^ [2:5] len=4
        , .{ false, false }, viewRelRange("0123456789", 3, 6, .{ .exp_sides = 2 }, .{}));
        //                                  --^~~^--
    }

    // [.exp_left] view mode
    // ----------------
    {
        try equal(
            \\ 123456 [1:7]
            \\   ^~~^ [2:5] len=4
        , .{ false, false }, viewRelRange("0123456789", 3, 6, .{ .exp_left = 2 }, .{}));
        //                                  --^~~^

        try equal(
            \\ 89 [8:10]
            \\   ^~~^ [2:5] len=4
        , .{ false, true }, viewRelRange("0123456789", 10, 13, .{ .exp_left = 2 }, .{}));
        //                                        --^~~^

    }

    // [.exp_right] view mode
    // ----------------
    {
        try equal(
            \\ 345678 [3:9]
            \\ ^~~^ [0:3] len=4
        , .{ false, false }, viewRelRange("0123456789", 3, 6, .{ .exp_right = 2 }, .{}));
        //                                    ^~~^--
    }

    // [.exp_custom] view mode
    // ----------------
    {
        try equal(
            \\ 12345678 [1:9]
            \\    ^~^ [3:5] len=3
        , .{ false, false }, viewRelRange("0123456789", 4, 6, .{ .exp_custom = .{ .left = 3, .right = 2 } }, .{}));
        //                                  ---^~^--
    }
}

/// Returns a `[start..end]` slice segment with indices normalized to not
/// exceed the `slice.len`.
pub fn segment(T: type, slice: T, start: usize, end: usize) T {
    return slice[@min(slice.len, start)..@min(slice.len, end)];
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
    return num.isInRangeInc(usize, seg_start, slice_start, slice_end) and
        num.isInRangeInc(usize, seg_end, slice_start, slice_end);
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
