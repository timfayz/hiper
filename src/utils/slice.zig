// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

//! Public API:
//! - reverse()
//! - intersect()
//! - merge()
//! - indexOfStart()
//! - indexOfEnd()
//! - Indices
//! - indices()
//! - indicesStart()
//! - indicesEnd()
//! - indicesAround()
//! - indicesAroundRange()
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

/// Returns the union of two slices. Slices are assumed to share the same
/// source; use `isSegment` to verify this before calling.
///
/// ```txt
/// [slice1 ] [ slice2]    (slices disjoint)
/// [                 ]    (merged)
///
/// [slice1   ]            (slices intersect)
///         [   slice2]
/// [                 ]    (merged)
/// ```
pub fn merge(T: type, slice1: []const T, slice2: []const T) []T {
    var slice: []T = undefined;
    const ptr1 = @intFromPtr(slice1.ptr);
    const ptr2 = @intFromPtr(slice2.ptr);
    const start = @min(ptr1, ptr2);
    const end = @max(ptr1 + slice1.len, ptr2 + slice2.len);
    slice.ptr = @ptrFromInt(start);
    slice.len = end - start;
    return slice;
}

test merge {
    const equal = std.testing.expectEqualStrings;

    const input = "0123";

    try equal("0123", merge(u8, input[0..0], input[4..4])); // zero slices
    try equal("0123", merge(u8, input[4..4], input[0..0])); // reversed order
    try equal("0123", merge(u8, input[0..2], input[2..4])); // normal slices
    try equal("0123", merge(u8, input[2..4], input[0..2])); // reversed order
    try equal("0123", merge(u8, input[0..3], input[1..4])); // intersected slices
    try equal("0123", merge(u8, input[0..4], input[0..4])); // same slices
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

/// Retrieved indices of a segment.
pub const Indices = struct {
    /// The start index of the segment.
    start: usize,
    /// The end index of the segment.
    end: usize,

    pub usingnamespace Shared(Indices);

    pub const Around = struct {
        /// The start index of the segment.
        start: usize,
        /// The end index of the segment.
        end: usize,
        /// Position of the original `index` relative to the segment.
        index_pos: usize,

        pub usingnamespace Shared(Around);
        /// Checks if the relative index position exceeds the actual segment
        /// boundaries.
        pub fn indexPosExceeds(self: *const Around) bool {
            return self.index_pos > self.end;
        }

        /// Options for `indicesAround`.
        pub const Options = struct {
            /// Shifts even-length ranges by one index to the right.
            even_rshift: bool = true,
            /// See `Segment.Around.Mode` for details.
            trunc_mode: Mode = .hard_flex,
        };

        /// Controls how `indicesAround` truncates a slice segment.
        /// See `indicesAround` tests for detailed examples of each mode.
        pub const Mode = enum {
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

    pub const Range = struct {
        /// The start index of the segment.
        start: usize,
        /// The end index of the segment.
        end: usize,
        /// Position of the original `start` index relative to the segment.
        start_pos: usize,
        /// Position of the original `end` index relative to the segment.
        end_pos: usize,

        pub usingnamespace Shared(Range);
        /// Returns the length of the requested segment range.
        pub fn rangeLen(self: *const Range) usize {
            return self.end_pos - self.start_pos +| 1;
        }

        /// Checks if the relative range start position exceeds the actual segment
        /// boundaries.
        pub fn startPosExceeds(self: *const Range) bool {
            return self.start_pos > self.segLen();
        }

        /// Checks if the relative range end position exceeds the actual segment
        /// boundaries.
        pub fn endPosExceeds(self: *const Range) bool {
            return self.end_pos > self.segLen();
        }
    };

    pub const Split = union(enum) {
        solid: Indices.Range,
        split: [2]Indices.Around,
    };

    fn Shared(Self: type) type {
        return struct {
            /// Returns the retrieved segment length.
            pub fn segLen(self: *const Self) usize {
                return self.end - self.start;
            }

            /// Returns `input[self.start..self.end]`.
            pub fn slice(self: *const Self, T: type, input: T) T {
                return input[self.start..self.end];
            }
        };
    }
};

/// Retrieves the starting and ending positions of a segment in slice. Slices
/// are assumed to share the same source; use `isSegment` to verify this before
/// calling.
pub fn indices(slice: anytype, seg: anytype) Indices {
    return .{ .start = indexOfStart(slice, seg), .end = indexOfEnd(slice, seg) };
}

/// Returns start slice indices of length `len`. Indices are bounded by slice
/// length.
pub fn indicesStart(slice: anytype, len: usize) Indices {
    return .{ .start = 0, .end = @min(slice.len, len) };
}

test indicesStart {
    const equal = std.testing.expectEqualDeep;

    try equal(Indices{ .start = 0, .end = 0 }, indicesStart("", 0)); // ""
    try equal(Indices{ .start = 0, .end = 0 }, indicesStart("012", 0)); // ""
    try equal(Indices{ .start = 0, .end = 1 }, indicesStart("012", 1)); // "0"
    try equal(Indices{ .start = 0, .end = 2 }, indicesStart("012", 2)); // "01"
    try equal(Indices{ .start = 0, .end = 3 }, indicesStart("012", 3)); // "012"
    try equal(Indices{ .start = 0, .end = 3 }, indicesStart("012", 4)); // "012"
}

/// Returns end slice indices of length `len`. Indices are bounded by slice
/// length.
pub fn indicesEnd(slice: anytype, len: usize) Indices {
    return .{ .start = slice.len -| len, .end = slice.len };
}

test indicesEnd {
    const equal = std.testing.expectEqualDeep;

    try equal(Indices{ .start = 0, .end = 0 }, indicesEnd("", 0)); // ""
    try equal(Indices{ .start = 3, .end = 3 }, indicesEnd("012", 0)); // ""
    try equal(Indices{ .start = 2, .end = 3 }, indicesEnd("012", 1)); // "2"
    try equal(Indices{ .start = 1, .end = 3 }, indicesEnd("012", 2)); // "12"
    try equal(Indices{ .start = 0, .end = 3 }, indicesEnd("012", 3)); // "012"
    try equal(Indices{ .start = 0, .end = 3 }, indicesEnd("012", 4)); // "012"
}

/// Returns the start and end indices of a slice segment of length `len`
/// centered around the index, along with the relative position of the original
/// index within the segment. The returned index position can be out of segment
/// bounds if the original index was out of slice. See `SegAroundOptions` for
/// additional options.
pub fn indicesAround(
    slice: anytype,
    index: usize,
    len: usize,
    comptime opt: Indices.Around.Options,
) Indices.Around {
    if (slice.len == 0)
        return .{ .start = 0, .end = 0, .index_pos = index };

    if (len == 0) {
        const i = @min(index, slice.len);
        return .{ .start = i, .end = i, .index_pos = index -| i };
    }

    const dist = len / 2;
    const dist_to_start, const dist_to_end = blk: {
        if (len & 1 == 0) { // even
            break :blk if (opt.even_rshift) .{ dist -| 1, dist +| 1 } else .{ dist, dist };
        } else { // odd
            // +1 to compensate lost item during integer division (ie. 3 / 2 = 1)
            break :blk .{ dist, dist +| 1 };
        }
    };

    const start = @min(
        index -| dist_to_start,
        switch (opt.trunc_mode) {
            .hard => slice.len,
            .hard_flex => b: {
                const last_idx = slice.len -| 1;
                const overrun = index -| last_idx;
                break :b slice.len -| (len -| overrun);
            },
            .soft => slice.len -| len,
        },
    );
    const end = @min(
        slice.len,
        switch (opt.trunc_mode) {
            .hard => index +| dist_to_end,
            .hard_flex, .soft => start +| len,
        },
    );
    return .{ .start = start, .end = end, .index_pos = index - start };
}

test indicesAround {
    const equal = std.testing.expectEqualDeep;
    const Around = Indices.Around;

    // any trunc mode
    // --------------
    // zero length
    try equal(Around{ .start = 0, .end = 0, .index_pos = 10 }, indicesAround("", 10, 100, .{})); // ""
    try equal(Around{ .start = 0, .end = 0, .index_pos = 10 }, indicesAround("", 10, 0, .{})); // ""
    try equal(Around{ .start = 0, .end = 0, .index_pos = 0 }, indicesAround("012", 0, 0, .{})); // ""
    try equal(Around{ .start = 3, .end = 3, .index_pos = 0 }, indicesAround("012", 3, 0, .{})); // ""
    try equal(Around{ .start = 3, .end = 3, .index_pos = 2 }, indicesAround("012", 5, 0, .{})); // ""

    // .soft mode
    // --------------
    // max length
    try equal(Around{ .start = 0, .end = 4, .index_pos = 3 }, indicesAround("0123", 3, 100, .{ .trunc_mode = .soft })); // "0123"

    // odd length
    try equal(Around{ .start = 0, .end = 4, .index_pos = 0 }, indicesAround("0123", 0, 100, .{ .trunc_mode = .soft })); // "0123"
    try equal(Around{ .start = 0, .end = 3, .index_pos = 0 }, indicesAround("0123", 0, 3, .{ .trunc_mode = .soft })); // "012"
    try equal(Around{ .start = 0, .end = 3, .index_pos = 1 }, indicesAround("0123", 1, 3, .{ .trunc_mode = .soft })); // "012"
    try equal(Around{ .start = 1, .end = 4, .index_pos = 1 }, indicesAround("0123", 2, 3, .{ .trunc_mode = .soft })); // "123"
    try equal(Around{ .start = 1, .end = 4, .index_pos = 2 }, indicesAround("0123", 3, 3, .{ .trunc_mode = .soft })); // "123"
    try equal(Around{ .start = 1, .end = 4, .index_pos = 3 }, indicesAround("0123", 4, 3, .{ .trunc_mode = .soft })); // "123"
    try equal(Around{ .start = 1, .end = 4, .index_pos = 4 }, indicesAround("0123", 5, 3, .{ .trunc_mode = .soft })); // "123"

    // even length (right shifted)
    try equal(Around{ .start = 0, .end = 2, .index_pos = 0 }, indicesAround("0123", 0, 2, .{ .trunc_mode = .soft, .even_rshift = true })); // "01"
    try equal(Around{ .start = 1, .end = 3, .index_pos = 0 }, indicesAround("0123", 1, 2, .{ .trunc_mode = .soft, .even_rshift = true })); // "12"
    try equal(Around{ .start = 2, .end = 4, .index_pos = 0 }, indicesAround("0123", 2, 2, .{ .trunc_mode = .soft, .even_rshift = true })); // "23"
    try equal(Around{ .start = 2, .end = 4, .index_pos = 1 }, indicesAround("0123", 3, 2, .{ .trunc_mode = .soft, .even_rshift = true })); // "23"
    try equal(Around{ .start = 2, .end = 4, .index_pos = 2 }, indicesAround("0123", 4, 2, .{ .trunc_mode = .soft, .even_rshift = true })); // "23"
    try equal(Around{ .start = 2, .end = 4, .index_pos = 3 }, indicesAround("0123", 5, 2, .{ .trunc_mode = .soft, .even_rshift = true })); // "23"

    // even length (left shifted)
    try equal(Around{ .start = 0, .end = 2, .index_pos = 0 }, indicesAround("0123", 0, 2, .{ .trunc_mode = .soft, .even_rshift = false })); // "01"
    try equal(Around{ .start = 0, .end = 2, .index_pos = 1 }, indicesAround("0123", 1, 2, .{ .trunc_mode = .soft, .even_rshift = false })); // "01"
    try equal(Around{ .start = 1, .end = 3, .index_pos = 1 }, indicesAround("0123", 2, 2, .{ .trunc_mode = .soft, .even_rshift = false })); // "12"
    try equal(Around{ .start = 2, .end = 4, .index_pos = 1 }, indicesAround("0123", 3, 2, .{ .trunc_mode = .soft, .even_rshift = false })); // "23"
    try equal(Around{ .start = 2, .end = 4, .index_pos = 2 }, indicesAround("0123", 4, 2, .{ .trunc_mode = .soft, .even_rshift = false })); // "23"
    try equal(Around{ .start = 2, .end = 4, .index_pos = 3 }, indicesAround("0123", 5, 2, .{ .trunc_mode = .soft, .even_rshift = false })); // "23"

    // .hard mode
    // --------------
    // max length
    try equal(Around{ .start = 0, .end = 4, .index_pos = 3 }, indicesAround("0123", 3, 100, .{ .trunc_mode = .hard })); // "0123"

    // odd length
    try equal(Around{ .start = 0, .end = 2, .index_pos = 0 }, indicesAround("0123", 0, 3, .{ .trunc_mode = .hard })); // "01"
    try equal(Around{ .start = 0, .end = 3, .index_pos = 1 }, indicesAround("0123", 1, 3, .{ .trunc_mode = .hard })); // "012"
    try equal(Around{ .start = 1, .end = 4, .index_pos = 1 }, indicesAround("0123", 2, 3, .{ .trunc_mode = .hard })); // "123"
    try equal(Around{ .start = 2, .end = 4, .index_pos = 1 }, indicesAround("0123", 3, 3, .{ .trunc_mode = .hard })); // "23"
    try equal(Around{ .start = 3, .end = 4, .index_pos = 1 }, indicesAround("0123", 4, 3, .{ .trunc_mode = .hard })); // "3"
    try equal(Around{ .start = 4, .end = 4, .index_pos = 1 }, indicesAround("0123", 5, 3, .{ .trunc_mode = .hard })); // ""
    try equal(Around{ .start = 4, .end = 4, .index_pos = 2 }, indicesAround("0123", 6, 3, .{ .trunc_mode = .hard })); // ""

    // even length (right shifted)
    try equal(Around{ .start = 0, .end = 2, .index_pos = 0 }, indicesAround("0123", 0, 2, .{ .trunc_mode = .hard, .even_rshift = true })); // "01"
    try equal(Around{ .start = 1, .end = 3, .index_pos = 0 }, indicesAround("0123", 1, 2, .{ .trunc_mode = .hard, .even_rshift = true })); // "12"
    try equal(Around{ .start = 2, .end = 4, .index_pos = 0 }, indicesAround("0123", 2, 2, .{ .trunc_mode = .hard, .even_rshift = true })); // "23"
    try equal(Around{ .start = 3, .end = 4, .index_pos = 0 }, indicesAround("0123", 3, 2, .{ .trunc_mode = .hard, .even_rshift = true })); // "3"
    try equal(Around{ .start = 4, .end = 4, .index_pos = 0 }, indicesAround("0123", 4, 2, .{ .trunc_mode = .hard, .even_rshift = true })); // ""
    try equal(Around{ .start = 4, .end = 4, .index_pos = 1 }, indicesAround("0123", 5, 2, .{ .trunc_mode = .hard, .even_rshift = true })); // ""
    try equal(Around{ .start = 4, .end = 4, .index_pos = 2 }, indicesAround("0123", 6, 2, .{ .trunc_mode = .hard, .even_rshift = true })); // ""

    // even length (left shifted)
    try equal(Around{ .start = 0, .end = 1, .index_pos = 0 }, indicesAround("0123", 0, 2, .{ .trunc_mode = .hard, .even_rshift = false })); // "0"
    try equal(Around{ .start = 0, .end = 2, .index_pos = 1 }, indicesAround("0123", 1, 2, .{ .trunc_mode = .hard, .even_rshift = false })); // "01"
    try equal(Around{ .start = 1, .end = 3, .index_pos = 1 }, indicesAround("0123", 2, 2, .{ .trunc_mode = .hard, .even_rshift = false })); // "12"
    try equal(Around{ .start = 2, .end = 4, .index_pos = 1 }, indicesAround("0123", 3, 2, .{ .trunc_mode = .hard, .even_rshift = false })); // "23"
    try equal(Around{ .start = 3, .end = 4, .index_pos = 1 }, indicesAround("0123", 4, 2, .{ .trunc_mode = .hard, .even_rshift = false })); // "3"
    try equal(Around{ .start = 4, .end = 4, .index_pos = 1 }, indicesAround("0123", 5, 2, .{ .trunc_mode = .hard, .even_rshift = false })); // ""
    try equal(Around{ .start = 4, .end = 4, .index_pos = 2 }, indicesAround("0123", 6, 2, .{ .trunc_mode = .hard, .even_rshift = false })); // ""

    // .hard_flex mode
    // --------------
    // max length
    try equal(Around{ .start = 0, .end = 4, .index_pos = 3 }, indicesAround("0123", 3, 100, .{ .trunc_mode = .hard_flex })); // "0123"

    // odd length
    try equal(Around{ .start = 0, .end = 3, .index_pos = 0 }, indicesAround("0123", 0, 3, .{ .trunc_mode = .hard_flex })); // "012"
    try equal(Around{ .start = 0, .end = 3, .index_pos = 1 }, indicesAround("0123", 1, 3, .{ .trunc_mode = .hard_flex })); // "012"
    try equal(Around{ .start = 1, .end = 4, .index_pos = 1 }, indicesAround("0123", 2, 3, .{ .trunc_mode = .hard_flex })); // "123"
    try equal(Around{ .start = 1, .end = 4, .index_pos = 2 }, indicesAround("0123", 3, 3, .{ .trunc_mode = .hard_flex })); // "123"
    try equal(Around{ .start = 2, .end = 4, .index_pos = 2 }, indicesAround("0123", 4, 3, .{ .trunc_mode = .hard_flex })); // "23"
    try equal(Around{ .start = 3, .end = 4, .index_pos = 2 }, indicesAround("0123", 5, 3, .{ .trunc_mode = .hard_flex })); // "3"
    try equal(Around{ .start = 4, .end = 4, .index_pos = 2 }, indicesAround("0123", 6, 3, .{ .trunc_mode = .hard_flex })); // ""

    // even length (right shifted)
    try equal(Around{ .start = 0, .end = 2, .index_pos = 0 }, indicesAround("0123", 0, 2, .{ .trunc_mode = .hard_flex, .even_rshift = true })); // "01"
    try equal(Around{ .start = 1, .end = 3, .index_pos = 0 }, indicesAround("0123", 1, 2, .{ .trunc_mode = .hard_flex, .even_rshift = true })); // "12"
    try equal(Around{ .start = 2, .end = 4, .index_pos = 0 }, indicesAround("0123", 2, 2, .{ .trunc_mode = .hard_flex, .even_rshift = true })); // "23"
    try equal(Around{ .start = 2, .end = 4, .index_pos = 1 }, indicesAround("0123", 3, 2, .{ .trunc_mode = .hard_flex, .even_rshift = true })); // "23"
    try equal(Around{ .start = 3, .end = 4, .index_pos = 1 }, indicesAround("0123", 4, 2, .{ .trunc_mode = .hard_flex, .even_rshift = true })); // "3"
    try equal(Around{ .start = 4, .end = 4, .index_pos = 1 }, indicesAround("0123", 5, 2, .{ .trunc_mode = .hard_flex, .even_rshift = true })); // ""
    try equal(Around{ .start = 4, .end = 4, .index_pos = 2 }, indicesAround("0123", 6, 2, .{ .trunc_mode = .hard_flex, .even_rshift = true })); // ""

    // even length (left shifted)
    try equal(Around{ .start = 0, .end = 2, .index_pos = 0 }, indicesAround("0123", 0, 2, .{ .trunc_mode = .hard_flex, .even_rshift = false })); // "01"
    try equal(Around{ .start = 0, .end = 2, .index_pos = 1 }, indicesAround("0123", 1, 2, .{ .trunc_mode = .hard_flex, .even_rshift = false })); // "01"
    try equal(Around{ .start = 1, .end = 3, .index_pos = 1 }, indicesAround("0123", 2, 2, .{ .trunc_mode = .hard_flex, .even_rshift = false })); // "12"
    try equal(Around{ .start = 2, .end = 4, .index_pos = 1 }, indicesAround("0123", 3, 2, .{ .trunc_mode = .hard_flex, .even_rshift = false })); // "23"
    try equal(Around{ .start = 3, .end = 4, .index_pos = 1 }, indicesAround("0123", 4, 2, .{ .trunc_mode = .hard_flex, .even_rshift = false })); // "3"
    try equal(Around{ .start = 4, .end = 4, .index_pos = 1 }, indicesAround("0123", 5, 2, .{ .trunc_mode = .hard_flex, .even_rshift = false })); // ""
    try equal(Around{ .start = 4, .end = 4, .index_pos = 2 }, indicesAround("0123", 6, 2, .{ .trunc_mode = .hard_flex, .even_rshift = false })); // ""
}

/// Returns indices of a slice segment within the `start`:`end` range, extended
/// by `pad` elements around each side, along with the relative positions of the
/// original `start` and `end` indices within the segment. The `end` index is
/// inclusive. The returned positions (`*_pos`) may fall outside the segment
/// if the original `start` or `end` indices were out of slice bounds.
pub fn indicesAroundRange(
    slice: anytype,
    start: usize,
    end: usize,
    pad: usize,
) Indices.Range {
    if (start == end) {
        const range = if (pad == 0) 1 else (pad *| 2 +| 1); // +1 to include the cursor itself
        const s = indicesAround(slice, start, range, .{ .trunc_mode = .hard_flex });
        return .{ .start = s.start, .end = s.end, .start_pos = s.index_pos, .end_pos = s.index_pos };
    }
    // ensure start <= end
    const s, const e = if (start < end) .{ start, end } else .{ end, start };
    const seg_start = @min(slice.len, s -| pad);
    const seg_end = @min(slice.len, e +| pad +| 1); // +1 ensures end index is inclusive
    return .{
        .start = seg_start,
        .end = seg_end,
        .start_pos = s - seg_start,
        .end_pos = e - seg_start,
    };
}

test indicesAroundRange {
    const Range = Indices.Range;
    const equal = struct {
        pub fn run(
            comptime expect: Range,
            comptime extra: struct { range: usize, s_out: bool, e_out: bool },
            actual: Range,
        ) !void {
            try std.testing.expectEqualDeep(expect, actual);
            try std.testing.expectEqual(extra.range, actual.rangeLen());
            try std.testing.expectEqual(extra.s_out, actual.startPosExceeds());
            try std.testing.expectEqual(extra.e_out, actual.endPosExceeds());
        }
    }.run;

    // empty input ranges
    try equal(Range{ .start = 0, .end = 0, .start_pos = 0, .end_pos = 0 }, .{ .range = 1, .s_out = false, .e_out = false }, //
        indicesAroundRange("", 0, 0, 0));
    try equal(Range{ .start = 0, .end = 0, .start_pos = 5, .end_pos = 20 }, .{ .range = 16, .s_out = true, .e_out = true }, //
        indicesAroundRange("", 5, 20, 4));

    // out-of-bounds ranges
    try equal(Range{ .start = 5, .end = 10, .start_pos = 0, .end_pos = 15 }, .{ .range = 16, .s_out = false, .e_out = true }, // "56789"
        indicesAroundRange("0123456789", 5, 20, 0));
    //                           ^^^^^^^..
    try equal(Range{ .start = 1, .end = 10, .start_pos = 4, .end_pos = 19 }, .{ .range = 16, .s_out = false, .e_out = true }, // "123456789"
        indicesAroundRange("0123456789", 5, 20, 4));
    //                       ----^^^^^^^..
    try equal(Range{ .start = 10, .end = 10, .start_pos = 0, .end_pos = 1 }, .{ .range = 2, .s_out = false, .e_out = true }, // ""
        indicesAroundRange("0123456789", 10, 11, 0));
    //                                ^^
    try equal(Range{ .start = 10, .end = 10, .start_pos = 1, .end_pos = 2 }, .{ .range = 2, .s_out = true, .e_out = true }, // ""
        indicesAroundRange("0123456789", 11, 12, 0));
    //                                 ^^
    try equal(Range{ .start = 10, .end = 10, .start_pos = 2, .end_pos = 10 }, .{ .range = 9, .s_out = true, .e_out = true }, // ""
        indicesAroundRange("0123456789", 12, 20, 0));
    //                                  ^^^..
    try equal(Range{ .start = 8, .end = 10, .start_pos = 4, .end_pos = 12 }, .{ .range = 9, .s_out = true, .e_out = true }, // "89"
        indicesAroundRange("0123456789", 12, 20, 4));
    //                              ----^^^..

    // single-item ranges (start == end)
    try equal(Range{ .start = 4, .end = 5, .start_pos = 0, .end_pos = 0 }, .{ .range = 1, .s_out = false, .e_out = false }, // "4"
        indicesAroundRange("0123456789", 4, 4, 0));
    //                          ^
    try equal(Range{ .start = 3, .end = 6, .start_pos = 1, .end_pos = 1 }, .{ .range = 1, .s_out = false, .e_out = false }, // "345"
        indicesAroundRange("0123456789", 4, 4, 1));
    //                         -^-
    try equal(Range{ .start = 2, .end = 7, .start_pos = 2, .end_pos = 2 }, .{ .range = 1, .s_out = false, .e_out = false }, // "23456"
        indicesAroundRange("0123456789", 4, 4, 2));
    //                        --^--

    // self ranges
    try equal(Range{ .start = 4, .end = 6, .start_pos = 0, .end_pos = 1 }, .{ .range = 2, .s_out = false, .e_out = false }, // "45"
        indicesAroundRange("0123456789", 4, 5, 0));
    //                          ^^
    try equal(Range{ .start = 3, .end = 7, .start_pos = 1, .end_pos = 2 }, .{ .range = 2, .s_out = false, .e_out = false }, // "3456"
        indicesAroundRange("0123456789", 4, 5, 1));
    //                         -^^-
    try equal(Range{ .start = 2, .end = 8, .start_pos = 2, .end_pos = 3 }, .{ .range = 2, .s_out = false, .e_out = false }, // "234567"
        indicesAroundRange("0123456789", 4, 5, 2));
    //                        --^^--
    try equal(Range{ .start = 3, .end = 6, .start_pos = 0, .end_pos = 2 }, .{ .range = 3, .s_out = false, .e_out = false }, // "345"
        indicesAroundRange("0123456789", 3, 5, 0));
    //                         ^^^
    try equal(Range{ .start = 2, .end = 7, .start_pos = 1, .end_pos = 3 }, .{ .range = 3, .s_out = false, .e_out = false }, // "23456"
        indicesAroundRange("0123456789", 3, 5, 1));
    //                        -^^^-
    try equal(Range{ .start = 1, .end = 8, .start_pos = 2, .end_pos = 4 }, .{ .range = 3, .s_out = false, .e_out = false }, // "1234567"
        indicesAroundRange("0123456789", 3, 5, 2));
    //                       --^^^--

    // left out-of-bounds pad
    try equal(Range{ .start = 0, .end = 6, .start_pos = 0, .end_pos = 3 }, .{ .range = 4, .s_out = false, .e_out = false }, // "012345"
        indicesAroundRange("0123456789", 0, 3, 2));
    //                    --^^^^--

    // right out-of-bounds pad
    try equal(Range{ .start = 4, .end = 10, .start_pos = 2, .end_pos = 5 }, .{ .range = 4, .s_out = false, .e_out = false }, // "456789"
        indicesAroundRange("0123456789", 6, 9, 2));
    //                          --^^^^--
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
