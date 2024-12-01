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
        pub fn check(expect: ?[]const u8, actual: ?[]const u8) !void {
            if (expect == null) return std.testing.expectEqual(null, actual);
            if (actual == null) return std.testing.expectEqual(expect, null);
            try std.testing.expectEqualStrings(expect.?, actual.?);
        }
    }.check;

    const input = "0123";
    try equal(null, intersect(u8, input[0..0], input[4..4])); // zero slices
    try equal(null, intersect(u8, input[0..2], input[2..4])); // touching boundaries

    try equal("2", intersect(u8, input[0..3], input[2..4])); // intersecting slices
    try equal("2", intersect(u8, input[2..4], input[0..3])); // (!) order

    try equal("12", intersect(u8, input[0..3], input[1..4])); // intersecting slices
    try equal("12", intersect(u8, input[1..4], input[0..3])); // (!) order

    try equal("0123", intersect(u8, input[0..4], input[0..4])); // same slices

    try equal("12", intersect(u8, input[0..4], input[1..3])); // one within other
    try equal("12", intersect(u8, input[1..3], input[0..4])); // (!) order
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
    try equal("0123", merge(u8, input[4..4], input[0..0])); // (!) order

    try equal("0123", merge(u8, input[0..2], input[2..4])); // normal slices
    try equal("0123", merge(u8, input[2..4], input[0..2])); // (!) order

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
    const equal = std.testing.expectEqual;
    try equal(Indices{ .start = 0, .end = 0 }, indicesStart("", 0));
    try equal(Indices{ .start = 0, .end = 0 }, indicesStart("012", 0));
    try equal(Indices{ .start = 0, .end = 1 }, indicesStart("012", 1));
    try equal(Indices{ .start = 0, .end = 2 }, indicesStart("012", 2));
    try equal(Indices{ .start = 0, .end = 3 }, indicesStart("012", 3));
    try equal(Indices{ .start = 0, .end = 3 }, indicesStart("012", 4));
}

/// Returns end slice indices of length `len`. Indices are bounded by slice
/// length.
pub fn indicesEnd(slice: anytype, len: usize) Indices {
    return .{ .start = slice.len -| len, .end = slice.len };
}

test indicesEnd {
    const equal = std.testing.expectEqual;
    try equal(Indices{ .start = 0, .end = 0 }, indicesEnd("", 0));
    try equal(Indices{ .start = 3, .end = 3 }, indicesEnd("012", 0));
    try equal(Indices{ .start = 2, .end = 3 }, indicesEnd("012", 1));
    try equal(Indices{ .start = 1, .end = 3 }, indicesEnd("012", 2));
    try equal(Indices{ .start = 0, .end = 3 }, indicesEnd("012", 3));
    try equal(Indices{ .start = 0, .end = 3 }, indicesEnd("012", 4));
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
            // adjust for the single item lost during integer division (ie. 3 / 2 = 1)
            break :blk .{ dist, dist + 1 };
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
    const equal = struct {
        fn run(
            expect_slice: []const u8,
            expect_index_pos: usize,
            // fn args
            slice: []const u8,
            index: usize,
            len: usize,
            comptime opt: Indices.Around.Options,
        ) !void {
            const res = indicesAround(slice, index, len, opt);
            try std.testing.expectEqualStrings(expect_slice, res.slice([]const u8, slice));
            try std.testing.expectEqual(expect_index_pos, res.index_pos);
        }
    }.run;

    // format:
    // try equal(|expected_seg|, |expected_index_pos|, |fn args|)

    // any truncation mode
    {
        // zero segment or slice length
        try equal("", 10, "", 10, 100, .{ .trunc_mode = .hard });
        try equal("", 10, "", 10, 0, .{ .trunc_mode = .hard });
        try equal("", 0, "012", 0, 0, .{ .trunc_mode = .hard });
        try equal("", 0, "012", 3, 0, .{ .trunc_mode = .hard });
        try equal("", 2, "012", 5, 0, .{ .trunc_mode = .hard });
    }

    // .soft truncation mode
    {
        // bypass truncation
        try equal("0123", 3, "0123", 3, 100, .{ .trunc_mode = .soft });

        // odd segment length
        try equal("0123", 0, "0123", 0, 100, .{ .trunc_mode = .soft });
        try equal("012", 0, "0123", 0, 3, .{ .trunc_mode = .soft });
        try equal("012", 1, "0123", 1, 3, .{ .trunc_mode = .soft });
        try equal("123", 1, "0123", 2, 3, .{ .trunc_mode = .soft });
        try equal("123", 2, "0123", 3, 3, .{ .trunc_mode = .soft });
        try equal("123", 3, "0123", 4, 3, .{ .trunc_mode = .soft });
        try equal("123", 4, "0123", 5, 3, .{ .trunc_mode = .soft });

        // even segment length (right shifted)
        try equal("01", 0, "0123", 0, 2, .{ .trunc_mode = .soft, .even_rshift = true });
        try equal("12", 0, "0123", 1, 2, .{ .trunc_mode = .soft, .even_rshift = true });
        try equal("23", 0, "0123", 2, 2, .{ .trunc_mode = .soft, .even_rshift = true });
        try equal("23", 1, "0123", 3, 2, .{ .trunc_mode = .soft, .even_rshift = true });
        try equal("23", 2, "0123", 4, 2, .{ .trunc_mode = .soft, .even_rshift = true });
        try equal("23", 3, "0123", 5, 2, .{ .trunc_mode = .soft, .even_rshift = true });

        // even segment length (left shifted)
        try equal("01", 0, "0123", 0, 2, .{ .trunc_mode = .soft, .even_rshift = false });
        try equal("01", 1, "0123", 1, 2, .{ .trunc_mode = .soft, .even_rshift = false });
        try equal("12", 1, "0123", 2, 2, .{ .trunc_mode = .soft, .even_rshift = false });
        try equal("23", 1, "0123", 3, 2, .{ .trunc_mode = .soft, .even_rshift = false });
        try equal("23", 2, "0123", 4, 2, .{ .trunc_mode = .soft, .even_rshift = false });
        try equal("23", 3, "0123", 5, 2, .{ .trunc_mode = .soft, .even_rshift = false });
    }

    // .hard truncation mode
    {
        // bypass truncation
        try equal("0123", 3, "0123", 3, 100, .{ .trunc_mode = .hard });

        // odd segment length
        try equal("01", 0, "0123", 0, 3, .{ .trunc_mode = .hard });
        try equal("012", 1, "0123", 1, 3, .{ .trunc_mode = .hard });
        try equal("123", 1, "0123", 2, 3, .{ .trunc_mode = .hard });
        try equal("23", 1, "0123", 3, 3, .{ .trunc_mode = .hard });
        try equal("3", 1, "0123", 4, 3, .{ .trunc_mode = .hard });
        try equal("", 1, "0123", 5, 3, .{ .trunc_mode = .hard });
        try equal("", 2, "0123", 6, 3, .{ .trunc_mode = .hard });

        // even segment length (right shifted)
        try equal("01", 0, "0123", 0, 2, .{ .trunc_mode = .hard, .even_rshift = true });
        try equal("12", 0, "0123", 1, 2, .{ .trunc_mode = .hard, .even_rshift = true });
        try equal("23", 0, "0123", 2, 2, .{ .trunc_mode = .hard, .even_rshift = true });
        try equal("3", 0, "0123", 3, 2, .{ .trunc_mode = .hard, .even_rshift = true });
        try equal("", 0, "0123", 4, 2, .{ .trunc_mode = .hard, .even_rshift = true });
        try equal("", 1, "0123", 5, 2, .{ .trunc_mode = .hard, .even_rshift = true });
        try equal("", 2, "0123", 6, 2, .{ .trunc_mode = .hard, .even_rshift = true });

        // even segment length (left shifted)
        try equal("0", 0, "0123", 0, 2, .{ .trunc_mode = .hard, .even_rshift = false });
        try equal("01", 1, "0123", 1, 2, .{ .trunc_mode = .hard, .even_rshift = false });
        try equal("12", 1, "0123", 2, 2, .{ .trunc_mode = .hard, .even_rshift = false });
        try equal("23", 1, "0123", 3, 2, .{ .trunc_mode = .hard, .even_rshift = false });
        try equal("3", 1, "0123", 4, 2, .{ .trunc_mode = .hard, .even_rshift = false });
        try equal("", 1, "0123", 5, 2, .{ .trunc_mode = .hard, .even_rshift = false });
        try equal("", 2, "0123", 6, 2, .{ .trunc_mode = .hard, .even_rshift = false });
    }

    // .hard_flex truncation mode
    {
        // bypass truncation
        try equal("0123", 3, "0123", 3, 100, .{ .trunc_mode = .hard_flex });

        // odd segment length
        try equal("012", 0, "0123", 0, 3, .{ .trunc_mode = .hard_flex });
        try equal("012", 1, "0123", 1, 3, .{ .trunc_mode = .hard_flex });
        try equal("123", 1, "0123", 2, 3, .{ .trunc_mode = .hard_flex });
        try equal("123", 2, "0123", 3, 3, .{ .trunc_mode = .hard_flex });
        try equal("23", 2, "0123", 4, 3, .{ .trunc_mode = .hard_flex });
        try equal("3", 2, "0123", 5, 3, .{ .trunc_mode = .hard_flex });
        try equal("", 2, "0123", 6, 3, .{ .trunc_mode = .hard_flex });

        // even segment length (right shifted)
        try equal("01", 0, "0123", 0, 2, .{ .trunc_mode = .hard_flex, .even_rshift = true });
        try equal("12", 0, "0123", 1, 2, .{ .trunc_mode = .hard_flex, .even_rshift = true });
        try equal("23", 0, "0123", 2, 2, .{ .trunc_mode = .hard_flex, .even_rshift = true });
        try equal("23", 1, "0123", 3, 2, .{ .trunc_mode = .hard_flex, .even_rshift = true });
        try equal("3", 1, "0123", 4, 2, .{ .trunc_mode = .hard_flex, .even_rshift = true });
        try equal("", 1, "0123", 5, 2, .{ .trunc_mode = .hard_flex, .even_rshift = true });
        try equal("", 2, "0123", 6, 2, .{ .trunc_mode = .hard_flex, .even_rshift = true });

        // even segment length (left shifted)
        try equal("01", 0, "0123", 0, 2, .{ .trunc_mode = .hard_flex, .even_rshift = false });
        try equal("01", 1, "0123", 1, 2, .{ .trunc_mode = .hard_flex, .even_rshift = false });
        try equal("12", 1, "0123", 2, 2, .{ .trunc_mode = .hard_flex, .even_rshift = false });
        try equal("23", 1, "0123", 3, 2, .{ .trunc_mode = .hard_flex, .even_rshift = false });
        try equal("3", 1, "0123", 4, 2, .{ .trunc_mode = .hard_flex, .even_rshift = false });
        try equal("", 1, "0123", 5, 2, .{ .trunc_mode = .hard_flex, .even_rshift = false });
        try equal("", 2, "0123", 6, 2, .{ .trunc_mode = .hard_flex, .even_rshift = false });
    }
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
        const range = if (pad == 0) 1 else (pad *| 2 +| 1); // 1 to include the cursor itself
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
    const case = struct {
        pub fn run(
            comptime input: []const u8,
            start: usize,
            end: usize,
            len: usize,
            comptime expect: struct {
                seg: []const u8,
                s_pos: usize,
                e_pos: usize,
                rng_len: usize,
                s_out: bool,
                e_out: bool,
            },
        ) !void {
            const res = indicesAroundRange(input, start, end, len);
            try std.testing.expectEqualStrings(expect.seg, input[res.start..res.end]);
            try std.testing.expectEqual(expect.s_pos, res.start_pos);
            try std.testing.expectEqual(expect.e_pos, res.end_pos);
            try std.testing.expectEqual(expect.rng_len, res.rangeLen());
            try std.testing.expectEqual(expect.s_out, res.startPosExceeds());
            try std.testing.expectEqual(expect.e_out, res.endPosExceeds());
        }
    }.run;

    // format:
    // try case(|input|, |start|, |end|, |len|, |expected seg, start_pos, end_pos, range_len, start_exceeds, end_exceeds|)

    // test empty input ranges
    try case("", 0, 0, 0, .{ .seg = "", .s_pos = 0, .e_pos = 0, .rng_len = 1, .s_out = false, .e_out = false });
    //        ^
    try case("", 5, 20, 4, .{ .seg = "", .s_pos = 5, .e_pos = 20, .rng_len = 16, .s_out = true, .e_out = true });
    //        ----^^^...

    // test out-of-bounds ranges
    try case("0123456789", 5, 20, 0, .{ .seg = "56789", .s_pos = 0, .e_pos = 15, .rng_len = 16, .s_out = false, .e_out = true });
    //             ^^^^^^^..
    try case("0123456789", 5, 20, 4, .{ .seg = "123456789", .s_pos = 4, .e_pos = 19, .rng_len = 16, .s_out = false, .e_out = true });
    //         ----^^^^^^^..
    try case("0123456789", 10, 11, 0, .{ .seg = "", .s_pos = 0, .e_pos = 1, .rng_len = 2, .s_out = false, .e_out = true });
    //                  ^^
    try case("0123456789", 11, 12, 0, .{ .seg = "", .s_pos = 1, .e_pos = 2, .rng_len = 2, .s_out = true, .e_out = true });
    //                   ^^
    try case("0123456789", 12, 20, 0, .{ .seg = "", .s_pos = 2, .e_pos = 10, .rng_len = 9, .s_out = true, .e_out = true });
    //                    ^^^..
    try case("0123456789", 12, 20, 4, .{ .seg = "89", .s_pos = 4, .e_pos = 12, .rng_len = 9, .s_out = true, .e_out = true });
    //                ----^^^..

    // test single-item ranges (start == end)
    try case("0123456789", 4, 4, 0, .{ .seg = "4", .s_pos = 0, .e_pos = 0, .rng_len = 1, .s_out = false, .e_out = false });
    //            ^
    try case("0123456789", 4, 4, 1, .{ .seg = "345", .s_pos = 1, .e_pos = 1, .rng_len = 1, .s_out = false, .e_out = false });
    //           -^-
    try case("0123456789", 4, 4, 2, .{ .seg = "23456", .s_pos = 2, .e_pos = 2, .rng_len = 1, .s_out = false, .e_out = false });
    //          --^--

    // test self ranges
    try case("0123456789", 4, 5, 0, .{ .seg = "45", .s_pos = 0, .e_pos = 1, .rng_len = 2, .s_out = false, .e_out = false });
    //            ^^
    try case("0123456789", 4, 5, 1, .{ .seg = "3456", .s_pos = 1, .e_pos = 2, .rng_len = 2, .s_out = false, .e_out = false });
    //           -^^-
    try case("0123456789", 4, 5, 2, .{ .seg = "234567", .s_pos = 2, .e_pos = 3, .rng_len = 2, .s_out = false, .e_out = false });
    //          --^^--
    try case("0123456789", 3, 5, 0, .{ .seg = "345", .s_pos = 0, .e_pos = 2, .rng_len = 3, .s_out = false, .e_out = false });
    //           ^^^
    try case("0123456789", 3, 5, 1, .{ .seg = "23456", .s_pos = 1, .e_pos = 3, .rng_len = 3, .s_out = false, .e_out = false });
    //          -^^^-
    try case("0123456789", 3, 5, 2, .{ .seg = "1234567", .s_pos = 2, .e_pos = 4, .rng_len = 3, .s_out = false, .e_out = false });
    //         --^^^--

    // test left out-of-bounds pad
    try case("0123456789", 0, 3, 2, .{ .seg = "012345", .s_pos = 0, .e_pos = 3, .rng_len = 4, .s_out = false, .e_out = false });
    //      --^^^^--

    // test right out-of-bounds pad
    try case("0123456789", 6, 9, 2, .{ .seg = "456789", .s_pos = 2, .e_pos = 5, .rng_len = 4, .s_out = false, .e_out = false });
    //            --^^^^--
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
    const slice: [11]u8 = "hello_world".*;

    try equal(true, isSegment(u8, slice[0..], slice[0..0]));
    try equal(true, isSegment(u8, slice[0..], slice[11..11]));
    try equal(true, isSegment(u8, slice[0..], slice[0..1]));
    try equal(true, isSegment(u8, slice[0..], slice[3..6]));
    try equal(true, isSegment(u8, slice[0..], slice[10..11]));
    try equal(false, isSegment(u8, slice[0..], "hello_world"));
    // intersecting
    try equal(true, isSegment(u8, slice[0..5], slice[0..5])); // same
    try equal(true, isSegment(u8, slice[0..0], slice[0..0]));
    try equal(true, isSegment(u8, slice[11..11], slice[11..11])); // last zero
    try equal(false, isSegment(u8, slice[0..5], slice[0..6]));
    try equal(false, isSegment(u8, slice[0..5], slice[5..10]));
    try equal(false, isSegment(u8, slice[5..10], slice[0..5]));
    try equal(false, isSegment(u8, slice[0..0], slice[11..11]));
    try equal(false, isSegment(u8, slice[0..6], slice[5..11]));
}

pub const MoveDir = enum { left, right };
pub const MoveError = error{ IsNotSeg, SegIsTooBig };

/// Moves a valid segment to the start or end of the given slice.
/// `max_seg_size` is a stack-allocated buffer to temporarily store
/// the segment during the move.
pub fn move(
    comptime dir: MoveDir,
    comptime max_seg_size: usize,
    T: type,
    slice: []T,
    seg: []const T,
) MoveError!void {
    // skip move if
    if (!isSegment(T, slice, seg)) return MoveError.IsNotSeg;
    if (seg.len > max_seg_size) return MoveError.SegIsTooBig;

    // no need to move if
    if (seg.len == 0 or seg.len == slice.len) return;
    switch (dir) {
        .right => if (indexOfEnd(slice, seg) == slice.len) return,
        .left => if (indexOfStart(slice, seg) == 0) return,
    }

    // make segment copy
    var buf: [max_seg_size]T = undefined;
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
    const case = struct {
        pub fn run(
            comptime dir: MoveDir,
            expected_slice: []const u8,
            expected_err: ?MoveError,
            slice: []u8,
            seg: []u8,
        ) !void {
            move(dir, 7, u8, slice, seg) catch |err| {
                if (expected_err == null) return err;
                try std.testing.expectEqual(expected_err.?, err);
                return;
            };
            if (expected_err != null) return error.ExpectedError;
            try std.testing.expectEqualStrings(expected_slice, slice);
        }
    }.run;

    // format:
    // try case(|move_dir|, |expected_slice|, |?expected_err|, |orig_slice|, |seg_to_move|)

    const origin = "0123456";
    var buf: [7]u8 = origin.*;
    const slice = buf[0..];

    // right
    //
    try case(.right, "3456012", null, slice, slice[0..3]);
    //                    ---
    buf = origin.*;

    try case(.right, "0126345", null, slice, slice[3..6]);
    //                    ---
    buf = origin.*;

    try case(.right, origin, null, slice, slice);
    //               same input
    buf = origin.*;

    try case(.right, origin, null, slice, slice[4..]);
    //               no need to move
    buf = origin.*;

    try case(.right, origin, null, slice, slice[7..]);
    //               zero length slice segment
    buf = origin.*;

    try case(.right, origin, null, slice, slice[3..3]);
    //               zero length slice segment
    buf = origin.*;

    try case(.right, "", MoveError.IsNotSeg, slice[0..4], slice[3..6]);
    //               not a valid slice segment
    buf = origin.*;

    var big_buf: [10]u8 = undefined;
    try case(.right, "", MoveError.SegIsTooBig, &big_buf, big_buf[0..]);
    //               slice segment is to big to copy
    buf = origin.*;

    // left
    //
    try case(.left, "1234560", null, slice, slice[1..]);
    //               ------
    buf = origin.*;

    try case(.left, "4560123", null, slice, slice[4..]);
    //               ---
    buf = origin.*;

    try case(.left, "6012345", null, slice, slice[6..]);
    //               -
    buf = origin.*;

    try case(.left, origin, null, slice, slice);
    //              same input
    buf = origin.*;

    try case(.left, origin, null, slice, slice[0..3]);
    //              no need to move
    buf = origin.*;

    try case(.left, origin, null, slice, slice[7..]);
    //              zero length slice segment
    buf = origin.*;

    try case(.left, origin, null, slice, slice[3..3]);
    //              zero length slice segment
    buf = origin.*;

    try case(.left, "", MoveError.IsNotSeg, slice[0..4], slice[3..6]);
    //              not a valid slice segment
    buf = origin.*;

    var big_buf2: [10]u8 = undefined;
    try case(.left, "", MoveError.SegIsTooBig, &big_buf2, big_buf2[0..]);
    //               slice segment is to big to copy
    buf = origin.*;
}

/// Moves a valid slice segment to the beginning of the given slice. Returns an
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
