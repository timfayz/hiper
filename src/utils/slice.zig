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

    pub usingnamespace Shared(@This());

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

    /// Options for view primitives.
    pub const Options = struct {
        /// Shifts an even-length view span by one index to the right.
        even_rshift: bool = true,
        /// Defines how view primitives truncate view span on overrun.
        trunc_mode: TruncMode = .hard_flex,
        /// Extra shift to the precalculated view span.
        shift: ?ExtraShift = null,

        pub const ExtraShift = union(enum) {
            right: usize,
            left: usize,
        };

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

        pub usingnamespace Shared(@This());

        /// Checks if the relative index position exceeds the actual segment
        /// boundaries.
        pub fn indexPosExceeds(self: *const @This()) bool {
            return self.index_pos > self.end;
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

        pub const Mode = union(enum) {
            within: union(enum) {},
            extend: union(View.Size.Mode) {
                around: usize,
                side: usize,
                left: usize,
                right: usize,
            },
        };

        pub usingnamespace Shared(@This());

        /// Returns the length of the requested segment range.
        pub fn rangeLen(self: *const @This()) usize {
            return self.end_pos - self.start_pos +| 1;
        }

        /// Checks if the relative range start position exceeds the actual segment
        /// boundaries.
        pub fn startPosExceeds(self: *const @This()) bool {
            return self.start_pos > self.len();
        }

        /// Checks if the relative range end position exceeds the actual segment
        /// boundaries.
        pub fn endPosExceeds(self: *const @This()) bool {
            return self.end_pos > self.len();
        }
    };

    /// Helper to calculate correct start and end indices for a view mode.
    const Size = struct {
        left: usize,
        right: usize,

        pub const Mode = enum { around, side, left, right };

        pub fn initRelIndex(comptime mode: Mode, size: usize, comptime opt: View.Options) Size {
            var dist: Size = undefined;
            switch (mode) {
                .around => {
                    dist = Size{ .left = size / 2, .right = size / 2 };
                    if (size & 1 != 0) dist.right +|= 1 // +1 compensates cursor during odd division
                    else if (opt.even_rshift) dist.shiftRight(1);
                },
                .side => dist = Size{ .left = size, .right = size +| 1 }, // +1 includes cursor itself
                .left => dist = Size{ .left = size, .right = 1 }, // +1 includes cursor itself
                .right => dist = Size{ .left = 0, .right = size +| 1 }, // +1 includes cursor itself
            }
            if (opt.shift) |shift| {
                switch (shift) {
                    .right => |amt| dist.shiftRight(amt),
                    .left => |amt| dist.shiftLeft(amt),
                }
            }
            return dist;
        }

        pub fn initRelRange(comptime mode: Mode, size: usize, comptime opt: View.Options) Size {
            var dist: Size = undefined;
            switch (mode) {
                .around => dist = Size{ .left = size / 2, .right = size / 2 },
                .side => dist = Size{ .left = size, .right = size },
                .left => dist = Size{ .left = size, .right = 0 },
                .right => dist = Size{ .left = 0, .right = size },
            }
            if (opt.shift) |shift| {
                switch (shift) {
                    .right => |amt| dist.shiftRight(amt),
                    .left => |amt| dist.shiftLeft(amt),
                }
            }
            return dist;
        }

        pub fn shiftLeft(self: *Size, amt: usize) void {
            self.left +|= amt;
            self.right -|= amt;
        }

        pub fn shiftRight(self: *Size, amt: usize) void {
            self.left -|= amt;
            self.right +|= amt;
        }

        pub fn len(self: *const Size) usize {
            return self.left + self.right;
        }

        pub fn indicesRelIndex(
            self: *const Size,
            slice: anytype,
            index: usize,
            comptime trunc_mode: View.Options.TruncMode,
        ) struct { usize, usize } {
            const dist = self.len();
            const start = @min(
                index -| self.left,
                switch (trunc_mode) {
                    .hard => slice.len,
                    .hard_flex => b: {
                        const overrun = index -| (slice.len -| 1);
                        break :b slice.len -| (dist -| overrun);
                    },
                    .soft => slice.len -| dist,
                },
            );
            const end = @min(
                slice.len,
                switch (trunc_mode) {
                    .hard => index +| self.right,
                    .hard_flex, .soft => start +| dist,
                },
            );
            return .{ start, end };
        }

        pub fn indicesRelRange(
            self: *const Size,
            slice: anytype,
            index_start: usize,
            index_end: usize,
            comptime trunc_mode: View.Options.TruncMode,
        ) struct { usize, usize } {
            const dist = self.len();
            const start = @min(
                index_start -| self.left,
                switch (trunc_mode) {
                    .hard => slice.len,
                    .hard_flex => b: {
                        const overrun = index_start -| (slice.len -| 1);
                        break :b slice.len -| (dist -| overrun);
                    },
                    .soft => slice.len -| dist,
                },
            );
            const end = @min(
                slice.len,
                switch (trunc_mode) {
                    .hard => index_end +| self.right,
                    .hard_flex, .soft => index_end +| (index_start -| start),
                },
            );
            return .{ start, end +| 1 };
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
    comptime mode: View.Size.Mode,
    len: usize,
    comptime opt: View.Options,
) View.RelIndex {
    if (slice.len == 0)
        return .{ .start = 0, .end = 0, .index_pos = index };

    if (len == 0) {
        const i = @min(index, slice.len);
        return .{ .start = i, .end = i, .index_pos = index -| i };
    }

    var view = View.Size.initRelIndex(mode, len, opt);
    const start, const end = view.indicesRelIndex(slice, index, opt.trunc_mode);

    return .{ .start = start, .end = end, .index_pos = index - start };
}

test viewRelIndex {
    const RelIndex = View.RelIndex;
    const equal = std.testing.expectEqualDeep;

    // any
    // ----------------
    // zero length
    try equal(RelIndex{ .start = 0, .end = 0, .index_pos = 10 }, viewRelIndex("", 10, .around, 100, .{})); // ""
    //                                                                        ..-^-..
    try equal(RelIndex{ .start = 0, .end = 0, .index_pos = 10 }, viewRelIndex("", 10, .around, 0, .{})); // ""
    //                                                                           ^
    try equal(RelIndex{ .start = 0, .end = 0, .index_pos = 0 }, viewRelIndex("0123", 0, .around, 0, .{})); // ""
    //                                                                        ^
    try equal(RelIndex{ .start = 3, .end = 3, .index_pos = 0 }, viewRelIndex("0123", 3, .around, 0, .{})); // ""
    //                                                                           ^
    try equal(RelIndex{ .start = 4, .end = 4, .index_pos = 1 }, viewRelIndex("0123", 5, .around, 0, .{})); // ""
    //                                                                             ^

    // .around view len
    // ----------------
    // .trunc_mode = .soft
    //
    // max length
    try equal(RelIndex{ .start = 0, .end = 4, .index_pos = 3 }, viewRelIndex("0123", 3, .around, 100, .{ .trunc_mode = .soft })); // "0123"
    //                                                                        ..-^-..
    //

    // odd length
    try equal(RelIndex{ .start = 0, .end = 3, .index_pos = 0 }, viewRelIndex("0123", 0, .around, 3, .{ .trunc_mode = .soft })); // "012"
    //                                                                       -^-+
    try equal(RelIndex{ .start = 0, .end = 3, .index_pos = 1 }, viewRelIndex("0123", 1, .around, 3, .{ .trunc_mode = .soft })); // "012"
    //                                                                        -^-
    try equal(RelIndex{ .start = 1, .end = 4, .index_pos = 1 }, viewRelIndex("0123", 2, .around, 3, .{ .trunc_mode = .soft })); // "123"
    //                                                                         -^-
    try equal(RelIndex{ .start = 1, .end = 4, .index_pos = 2 }, viewRelIndex("0123", 3, .around, 3, .{ .trunc_mode = .soft })); // "123"
    //                                                                         +-^-
    try equal(RelIndex{ .start = 1, .end = 4, .index_pos = 3 }, viewRelIndex("0123", 4, .around, 3, .{ .trunc_mode = .soft })); // "123"
    //                                                                         +++^
    try equal(RelIndex{ .start = 1, .end = 4, .index_pos = 4 }, viewRelIndex("0123", 5, .around, 3, .{ .trunc_mode = .soft })); // "123"
    //                                                                         +++ ^

    // even length (.even_rshift = true)
    try equal(RelIndex{ .start = 0, .end = 2, .index_pos = 0 }, viewRelIndex("0123", 0, .around, 2, .{ .trunc_mode = .soft, .even_rshift = true })); // "01"
    //                                                                        ^-
    try equal(RelIndex{ .start = 1, .end = 3, .index_pos = 0 }, viewRelIndex("0123", 1, .around, 2, .{ .trunc_mode = .soft, .even_rshift = true })); // "12"
    //                                                                         ^-
    try equal(RelIndex{ .start = 2, .end = 4, .index_pos = 0 }, viewRelIndex("0123", 2, .around, 2, .{ .trunc_mode = .soft, .even_rshift = true })); // "23"
    //                                                                          ^-
    try equal(RelIndex{ .start = 2, .end = 4, .index_pos = 1 }, viewRelIndex("0123", 3, .around, 2, .{ .trunc_mode = .soft, .even_rshift = true })); // "23"
    //                                                                          +^
    try equal(RelIndex{ .start = 2, .end = 4, .index_pos = 2 }, viewRelIndex("0123", 4, .around, 2, .{ .trunc_mode = .soft, .even_rshift = true })); // "23"
    //                                                                          ++^
    try equal(RelIndex{ .start = 2, .end = 4, .index_pos = 3 }, viewRelIndex("0123", 5, .around, 2, .{ .trunc_mode = .soft, .even_rshift = true })); // "23"
    //                                                                          ++ ^

    // even length (.even_rshift = false)
    try equal(RelIndex{ .start = 0, .end = 2, .index_pos = 0 }, viewRelIndex("0123", 0, .around, 2, .{ .trunc_mode = .soft, .even_rshift = false })); // "01"
    //                                                                        ^+
    try equal(RelIndex{ .start = 0, .end = 2, .index_pos = 1 }, viewRelIndex("0123", 1, .around, 2, .{ .trunc_mode = .soft, .even_rshift = false })); // "01"
    //                                                                        -^
    try equal(RelIndex{ .start = 1, .end = 3, .index_pos = 1 }, viewRelIndex("0123", 2, .around, 2, .{ .trunc_mode = .soft, .even_rshift = false })); // "12"
    //                                                                         -^
    try equal(RelIndex{ .start = 2, .end = 4, .index_pos = 1 }, viewRelIndex("0123", 3, .around, 2, .{ .trunc_mode = .soft, .even_rshift = false })); // "23"
    //                                                                          -^
    try equal(RelIndex{ .start = 2, .end = 4, .index_pos = 2 }, viewRelIndex("0123", 4, .around, 2, .{ .trunc_mode = .soft, .even_rshift = false })); // "23"
    //                                                                          +-^
    try equal(RelIndex{ .start = 2, .end = 4, .index_pos = 3 }, viewRelIndex("0123", 5, .around, 2, .{ .trunc_mode = .soft, .even_rshift = false })); // "23"
    //                                                                          ++ ^

    // .trunc_mode = .hard
    //
    // max length
    try equal(RelIndex{ .start = 0, .end = 4, .index_pos = 3 }, viewRelIndex("0123", 3, .around, 100, .{ .trunc_mode = .hard })); // "0123"
    //                                                                        ..-^-..

    // odd length
    try equal(RelIndex{ .start = 0, .end = 2, .index_pos = 0 }, viewRelIndex("0123", 0, .around, 3, .{ .trunc_mode = .hard })); // "01"
    //                                                                       -^-
    try equal(RelIndex{ .start = 0, .end = 3, .index_pos = 1 }, viewRelIndex("0123", 1, .around, 3, .{ .trunc_mode = .hard })); // "012"
    //                                                                        -^-
    try equal(RelIndex{ .start = 1, .end = 4, .index_pos = 1 }, viewRelIndex("0123", 2, .around, 3, .{ .trunc_mode = .hard })); // "123"
    //                                                                         -^-
    try equal(RelIndex{ .start = 2, .end = 4, .index_pos = 1 }, viewRelIndex("0123", 3, .around, 3, .{ .trunc_mode = .hard })); // "23"
    //                                                                          -^-
    try equal(RelIndex{ .start = 3, .end = 4, .index_pos = 1 }, viewRelIndex("0123", 4, .around, 3, .{ .trunc_mode = .hard })); // "3"
    //                                                                           -^-
    try equal(RelIndex{ .start = 4, .end = 4, .index_pos = 1 }, viewRelIndex("0123", 5, .around, 3, .{ .trunc_mode = .hard })); // ""
    //                                                                            -^-

    // even length (.even_rshift = true)
    try equal(RelIndex{ .start = 0, .end = 2, .index_pos = 0 }, viewRelIndex("0123", 0, .around, 2, .{ .trunc_mode = .hard, .even_rshift = true })); // "01"
    //                                                                        ^-
    try equal(RelIndex{ .start = 1, .end = 3, .index_pos = 0 }, viewRelIndex("0123", 1, .around, 2, .{ .trunc_mode = .hard, .even_rshift = true })); // "12"
    //                                                                         ^-
    try equal(RelIndex{ .start = 2, .end = 4, .index_pos = 0 }, viewRelIndex("0123", 2, .around, 2, .{ .trunc_mode = .hard, .even_rshift = true })); // "23"
    //                                                                          ^-
    try equal(RelIndex{ .start = 3, .end = 4, .index_pos = 0 }, viewRelIndex("0123", 3, .around, 2, .{ .trunc_mode = .hard, .even_rshift = true })); // "3"
    //                                                                           ^-
    try equal(RelIndex{ .start = 4, .end = 4, .index_pos = 0 }, viewRelIndex("0123", 4, .around, 2, .{ .trunc_mode = .hard, .even_rshift = true })); // ""
    //                                                                            ^-
    try equal(RelIndex{ .start = 4, .end = 4, .index_pos = 1 }, viewRelIndex("0123", 5, .around, 2, .{ .trunc_mode = .hard, .even_rshift = true })); // ""
    //                                                                             ^-

    // even length (.even_rshift = false)
    try equal(RelIndex{ .start = 0, .end = 1, .index_pos = 0 }, viewRelIndex("0123", 0, .around, 2, .{ .trunc_mode = .hard, .even_rshift = false })); // "0"
    //                                                                       -^
    try equal(RelIndex{ .start = 0, .end = 2, .index_pos = 1 }, viewRelIndex("0123", 1, .around, 2, .{ .trunc_mode = .hard, .even_rshift = false })); // "01"
    //                                                                        -^
    try equal(RelIndex{ .start = 1, .end = 3, .index_pos = 1 }, viewRelIndex("0123", 2, .around, 2, .{ .trunc_mode = .hard, .even_rshift = false })); // "12"
    //                                                                         -^
    try equal(RelIndex{ .start = 2, .end = 4, .index_pos = 1 }, viewRelIndex("0123", 3, .around, 2, .{ .trunc_mode = .hard, .even_rshift = false })); // "23"
    //                                                                          -^
    try equal(RelIndex{ .start = 3, .end = 4, .index_pos = 1 }, viewRelIndex("0123", 4, .around, 2, .{ .trunc_mode = .hard, .even_rshift = false })); // "3"
    //                                                                           -^
    try equal(RelIndex{ .start = 4, .end = 4, .index_pos = 1 }, viewRelIndex("0123", 5, .around, 2, .{ .trunc_mode = .hard, .even_rshift = false })); // ""
    //                                                                            -^
    try equal(RelIndex{ .start = 4, .end = 4, .index_pos = 2 }, viewRelIndex("0123", 6, .around, 2, .{ .trunc_mode = .hard, .even_rshift = false })); // ""
    //                                                                             -^

    // .trunc_mode = .hard_flex
    //
    // max length
    try equal(RelIndex{ .start = 0, .end = 4, .index_pos = 3 }, viewRelIndex("0123", 3, .around, 100, .{ .trunc_mode = .hard_flex })); // "0123"
    //                                                                        ..-^-..

    // odd length
    try equal(RelIndex{ .start = 0, .end = 3, .index_pos = 0 }, viewRelIndex("0123", 0, .around, 3, .{ .trunc_mode = .hard_flex })); // "012"
    //                                                                        ^-+
    try equal(RelIndex{ .start = 0, .end = 3, .index_pos = 1 }, viewRelIndex("0123", 1, .around, 3, .{ .trunc_mode = .hard_flex })); // "012"
    //                                                                        -^-
    try equal(RelIndex{ .start = 1, .end = 4, .index_pos = 1 }, viewRelIndex("0123", 2, .around, 3, .{ .trunc_mode = .hard_flex })); // "123"
    //                                                                         -^-
    try equal(RelIndex{ .start = 1, .end = 4, .index_pos = 2 }, viewRelIndex("0123", 3, .around, 3, .{ .trunc_mode = .hard_flex })); // "123"
    //                                                                         +-^
    try equal(RelIndex{ .start = 2, .end = 4, .index_pos = 2 }, viewRelIndex("0123", 4, .around, 3, .{ .trunc_mode = .hard_flex })); // "23"
    //                                                                          +-^
    try equal(RelIndex{ .start = 3, .end = 4, .index_pos = 2 }, viewRelIndex("0123", 5, .around, 3, .{ .trunc_mode = .hard_flex })); // "3"
    //                                                                           +-^
    try equal(RelIndex{ .start = 4, .end = 4, .index_pos = 2 }, viewRelIndex("0123", 6, .around, 3, .{ .trunc_mode = .hard_flex })); // ""
    //                                                                             -^-

    // even length (.even_rshift = true)
    try equal(RelIndex{ .start = 0, .end = 2, .index_pos = 0 }, viewRelIndex("0123", 0, .around, 2, .{ .trunc_mode = .hard_flex, .even_rshift = true })); // "01"
    //                                                                        ^-
    try equal(RelIndex{ .start = 1, .end = 3, .index_pos = 0 }, viewRelIndex("0123", 1, .around, 2, .{ .trunc_mode = .hard_flex, .even_rshift = true })); // "12"
    //                                                                         ^-
    try equal(RelIndex{ .start = 2, .end = 4, .index_pos = 0 }, viewRelIndex("0123", 2, .around, 2, .{ .trunc_mode = .hard_flex, .even_rshift = true })); // "23"
    //                                                                          ^-
    try equal(RelIndex{ .start = 2, .end = 4, .index_pos = 1 }, viewRelIndex("0123", 3, .around, 2, .{ .trunc_mode = .hard_flex, .even_rshift = true })); // "23"
    //                                                                          +^
    try equal(RelIndex{ .start = 3, .end = 4, .index_pos = 1 }, viewRelIndex("0123", 4, .around, 2, .{ .trunc_mode = .hard_flex, .even_rshift = true })); // "3"
    //                                                                           +^
    try equal(RelIndex{ .start = 4, .end = 4, .index_pos = 1 }, viewRelIndex("0123", 5, .around, 2, .{ .trunc_mode = .hard_flex, .even_rshift = true })); // ""
    //                                                                             ^-
    try equal(RelIndex{ .start = 4, .end = 4, .index_pos = 2 }, viewRelIndex("0123", 6, .around, 2, .{ .trunc_mode = .hard_flex, .even_rshift = true })); // ""
    //                                                                              ^-

    // even length (.even_rshift = false)
    try equal(RelIndex{ .start = 0, .end = 2, .index_pos = 0 }, viewRelIndex("0123", 0, .around, 2, .{ .trunc_mode = .hard_flex, .even_rshift = false })); // "01"
    //                                                                        ^+
    try equal(RelIndex{ .start = 0, .end = 2, .index_pos = 1 }, viewRelIndex("0123", 1, .around, 2, .{ .trunc_mode = .hard_flex, .even_rshift = false })); // "01"
    //                                                                        -^
    try equal(RelIndex{ .start = 1, .end = 3, .index_pos = 1 }, viewRelIndex("0123", 2, .around, 2, .{ .trunc_mode = .hard_flex, .even_rshift = false })); // "12"
    //                                                                         -^
    try equal(RelIndex{ .start = 2, .end = 4, .index_pos = 1 }, viewRelIndex("0123", 3, .around, 2, .{ .trunc_mode = .hard_flex, .even_rshift = false })); // "23"
    //                                                                          -^
    try equal(RelIndex{ .start = 3, .end = 4, .index_pos = 1 }, viewRelIndex("0123", 4, .around, 2, .{ .trunc_mode = .hard_flex, .even_rshift = false })); // "3"
    //                                                                           -^
    try equal(RelIndex{ .start = 4, .end = 4, .index_pos = 1 }, viewRelIndex("0123", 5, .around, 2, .{ .trunc_mode = .hard_flex, .even_rshift = false })); // ""
    //                                                                            -^
    try equal(RelIndex{ .start = 4, .end = 4, .index_pos = 2 }, viewRelIndex("0123", 6, .around, 2, .{ .trunc_mode = .hard_flex, .even_rshift = false })); // ""
    //                                                                             -^

    // .left view len
    // ----------------
    try equal(RelIndex{ .start = 1, .end = 4, .index_pos = 2 }, viewRelIndex("0123", 3, .left, 2, .{ .trunc_mode = .hard_flex }));
    //                                                                         --^
    try equal(RelIndex{ .start = 0, .end = 3, .index_pos = 1 }, viewRelIndex("0123", 1, .left, 2, .{ .trunc_mode = .hard_flex }));
    //                                                                       --^+
    try equal(RelIndex{ .start = 0, .end = 3, .index_pos = 0 }, viewRelIndex("0123", 0, .left, 2, .{ .trunc_mode = .hard_flex }));
    //                                                                      --^++

    // .right view len
    // ----------------
    try equal(RelIndex{ .start = 1, .end = 4, .index_pos = 0 }, viewRelIndex("0123", 1, .right, 2, .{ .trunc_mode = .hard_flex }));
    //                                                                         ^--
    try equal(RelIndex{ .start = 1, .end = 4, .index_pos = 1 }, viewRelIndex("0123", 2, .right, 2, .{ .trunc_mode = .hard_flex }));
    //                                                                         +^--
    try equal(RelIndex{ .start = 1, .end = 4, .index_pos = 2 }, viewRelIndex("0123", 3, .right, 2, .{ .trunc_mode = .hard_flex }));
    //                                                                         ++^--

    // .side view len
    // ----------------
    try equal(RelIndex{ .start = 1, .end = 4, .index_pos = 1 }, viewRelIndex("0123", 2, .side, 1, .{ .trunc_mode = .hard_flex }));
    //                                                                         -^-
    try equal(RelIndex{ .start = 0, .end = 4, .index_pos = 2 }, viewRelIndex("0123", 2, .side, 2, .{ .trunc_mode = .hard_flex }));
    //                                                                        --^--
    try equal(RelIndex{ .start = 0, .end = 3, .index_pos = 0 }, viewRelIndex("0123", 0, .side, 1, .{ .trunc_mode = .hard_flex }));
    //                                                                       -^-+
}

/// Returns a slice segment of length `len` relative to `start`-`end` range and
/// according to the view `mode`. The returned positions (`*_pos`) may be out of
/// bounds if the original range is outside the slice.
pub fn viewRelRange(
    slice: anytype,
    start: usize,
    end: usize,
    comptime mode: View.Size.Mode,
    len: usize,
    comptime opt: View.Options,
) ?View.RelRange {
    if (start == end) {
        const s = viewRelIndex(slice, start, mode, len, opt);
        return .{ .start = s.start, .end = s.end, .start_pos = s.index_pos, .end_pos = s.index_pos };
    }

    // ensure start <= end
    const s, const e = if (start < end) .{ start, end } else .{ end, start };
    // if (mode == .around and (e - s +| 1) > len) return null;
    // .within = .{.len = 30}
    // .extend = .{.around = 30}

    const view = View.Size.initRelRange(mode, len, opt);
    const view_start, const view_end = view.indicesRelRange(slice, s, e, opt.trunc_mode);
    return .{
        .start = view_start,
        .end = view_end,
        .start_pos = s - view_start,
        .end_pos = e - view_start,
    };
}

test viewRelRange {
    const input = "0123456789"; // must be in sync with first `viewRelRange` arg
    const equalVis = struct {
        pub fn run(
            expect: ?[]const u8,
            extra: anytype,
            view: ?View.RelRange,
        ) !void {
            if (view) |v| {
                try std.testing.expect(expect != null);

                var buf = std.BoundedArray(u8, 1024){};
                const w = buf.writer();

                // render input
                try w.print(" {s} [{d}:{d}]\n", .{ v.slice([]const u8, input), v.start, v.end });
                // render cursor
                if (v.start_pos == v.end_pos)
                    try w.print(" {[0]c: >[1]} [{[2]d}]", .{ '^', v.start_pos + 1, v.start_pos })
                else
                    try w.print(" {[0]c: >[1]}{[0]c:~>[2]} [{[3]d}:{[4]d}] len={[5]d}", .{
                        '^', // 0
                        v.start_pos + 1, // 1
                        v.end_pos - v.start_pos, // 2
                        v.start_pos, // 3
                        v.end_pos, // 4
                        v.rangeLen(), // 5
                    });
                try std.testing.expectEqualStrings(expect.?, buf.slice());
                try std.testing.expectEqual(extra[0], v.startPosExceeds());
                try std.testing.expectEqual(extra[1], v.endPosExceeds());
            } else {
                try std.testing.expect(expect == null);
            }
        }
    }.run;

    try equalVis(
        \\ 3456 [3:7]
        \\ ^~~^ [0:3] len=4
    , .{ false, false }, viewRelRange("0123456789", 3, 6, .side, 0, .{}));

    // try equalVis(null, .{ false, false }, viewRelRange("0123456789", 3, 6, .around, 0, .{}));
    //                                                     ^~~^ len=0
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
