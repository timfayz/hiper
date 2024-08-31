// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

//! Public API:
//! - indexOfSliceStart
//! - indexOfSliceEnd
//! - reverseSlice
//! - sliceStartSeg
//! - sliceEndSeg
//! - TruncMode
//! - sliceSeg
//! - isSliceSeg

const std = @import("std");
const num = @import("num.zig");

/// Retrieves the starting position of a slice in source.
pub inline fn indexOfSliceStart(source: anytype, slice: anytype) usize {
    return slice.ptr - source.ptr;
}

/// Retrieves the ending position of a slice in source.
pub inline fn indexOfSliceEnd(source: anytype, slice: anytype) usize {
    return slice.ptr - source.ptr +| slice.len;
}

test "+indexOfSliceStart/End" {
    const equal = std.testing.expectEqual;

    const in1 = "";
    try equal(0, indexOfSliceEnd(in1, in1[0..0]));

    const in2 = "0123456789";
    try equal(0, indexOfSliceEnd(in2, in2[0..0]));
    try equal(7, indexOfSliceEnd(in2, in2[3..7]));
    try equal(9, indexOfSliceEnd(in2, in2[3..9]));
    try equal(10, indexOfSliceEnd(in2, in2[3..10]));

    const in3 = "";
    try equal(0, indexOfSliceStart(in3, in3[0..0]));

    const in4 = "0123456789";
    try equal(0, indexOfSliceStart(in4, in4[0..0]));
    try equal(3, indexOfSliceStart(in4, in4[3..7]));
    try equal(9, indexOfSliceStart(in4, in4[9..10]));
    try equal(10, indexOfSliceStart(in4, in4[10..10]));
}

/// Reverses slice items in-place.
pub fn reverseSlice(slice: anytype) void {
    comptime {
        const T_info = @typeInfo(@TypeOf(slice));
        if (T_info != .Pointer and T_info.Pointer.size != .Slice)
            @compileError("argument must be a slice");
    }
    if (slice.len <= 1) return;
    var i: usize = 0;
    const swap_amt = slice.len / 2;
    const last_item_idx = slice.len - 1;
    while (i < swap_amt) : (i += 1) {
        const tmp = slice[i];
        slice[i] = slice[last_item_idx - i]; // swap lhs
        slice[last_item_idx - i] = tmp; // swap rhs
    }
}

test "+reverseInplace" {
    const t = std.testing;

    const case = struct {
        pub fn run(input: []const u8, expect: []const u8) !void {
            var buf: [32]u8 = undefined;
            for (input, 0..) |byte, i| buf[i] = byte;
            const actual = buf[0..input.len];
            reverseSlice(actual);
            try t.expectEqualStrings(expect, actual);
        }
    }.run;

    try case("", "");
    try case("1", "1");
    try case("12", "21");
    try case("123", "321");
    try case("1234", "4321");
    try case("12345", "54321");
}

/// Returns the first segment of the line with a specified length. If `seg_len`
/// is larger than the line length, the entire line is returned.
pub inline fn sliceStartSeg(T: type, slice: T, seg_len: usize) T {
    return slice[0..@min(slice.len, seg_len)];
}

/// Returns the last segment of the line with a specified length. If `seg_len`
/// is larger than the line length, the entire line is returned.
pub inline fn sliceEndSeg(T: type, slice: T, seg_len: usize) T {
    return slice[slice.len -| seg_len..];
}

test "+sliceStart/EndSeg" {
    const equal = std.testing.expectEqualStrings;
    try equal("", sliceStartSeg([]const u8, "", 0));
    try equal("", sliceStartSeg([]const u8, "abc", 0));
    try equal("a", sliceStartSeg([]const u8, "abc", 1));
    try equal("ab", sliceStartSeg([]const u8, "abc", 2));
    try equal("abc", sliceStartSeg([]const u8, "abc", 3));
    try equal("abc", sliceStartSeg([]const u8, "abc", 4));
    try equal("abc", sliceStartSeg([]const u8, "abc", 100));

    try equal("", sliceEndSeg([]const u8, "", 0));
    try equal("", sliceEndSeg([]const u8, "abc", 0));
    try equal("c", sliceEndSeg([]const u8, "abc", 1));
    try equal("bc", sliceEndSeg([]const u8, "abc", 2));
    try equal("abc", sliceEndSeg([]const u8, "abc", 3));
    try equal("abc", sliceEndSeg([]const u8, "abc", 4));
    try equal("abc", sliceEndSeg([]const u8, "abc", 100));
}

fn SliceSegInfo(T: type) type {
    return struct { slice: T, index_pos: usize };
}

pub const TruncMode = enum {
    /// This mode truncates the segment directly by slice bounds.
    hard,
    /// This mode truncates the segment by slice bounds but compensates for the
    /// truncated length by extending left or right until the cursor is too far
    /// from slice bounds.
    hard_flex,
    /// This mode truncates the segment by a constant length which always fits it
    /// within slice bounds, even with out-of-bounds indices.
    soft,
};

/// Returns a segment of `seg_len` from the slice centered around the index and
/// the relative position of the original index within the segment. Returned
/// index can be out of segment bounds if the original index was out of slice.
/// `trunc_mode` controls how segment is truncated if it exceeds `seg_len`. See
/// `TruncMode` for more details.
pub fn sliceSeg(
    T: type,
    slice: T,
    index: usize,
    seg_len: usize,
    comptime trunc_mode: TruncMode,
    comptime opt: struct {
        /// Shifts even segments right by one index relative to the cursor.
        even_rshift: bool = true,
    },
) SliceSegInfo(T) {
    if (slice.len == 0) return .{
        .slice = slice,
        .index_pos = index,
    };

    if (seg_len == 0) {
        const idx = @min(index, slice.len);
        return .{
            .slice = slice[idx..idx],
            .index_pos = index -| idx,
        };
    }

    const seg_is_even = seg_len & 1 == 0;
    const rshift_start: usize = if (opt.even_rshift and seg_is_even) 1 else 0;
    const rshift_end: usize = if (seg_is_even) rshift_start else 1;

    const dist = seg_len / 2;
    const dist_to_start = dist -| rshift_start;
    const dist_to_end = dist +| rshift_end;

    const seg_start = @min(
        index -| dist_to_start,
        switch (trunc_mode) {
            .hard => slice.len,
            .hard_flex => b: {
                const last_idx = slice.len -| 1;
                const overrun = index -| last_idx;
                break :b slice.len -| (seg_len -| overrun);
            },
            .soft => slice.len -| seg_len,
        },
    );
    const seg_end = @min(
        slice.len,
        switch (trunc_mode) {
            .hard => index +| dist_to_end,
            .hard_flex, .soft => seg_start +| seg_len,
        },
    );

    return .{
        .slice = slice[seg_start..seg_end],
        .index_pos = index - seg_start,
    };
}

test "+sliceSeg" {
    const t = std.testing;

    const equal = struct {
        fn run(
            expect_slice: []const u8,
            expect_index_pos: usize,
            result: SliceSegInfo([]const u8),
        ) !void {
            try t.expectEqualStrings(expect_slice, result.slice);
            try t.expectEqual(expect_index_pos, result.index_pos);
        }
    }.run;

    // Format:
    //
    // try equal(|expected slice|, |expected index_pos|, |fn result|)

    const T = []const u8;

    // Any truncation mode
    {
        // Zero segment or slice length
        try equal("", 10, sliceSeg(T, "", 10, 100, .hard, .{}));
        //         ^+                  ^+
        try equal("", 10, sliceSeg(T, "", 10, 0, .hard, .{}));
        //         ^+                  ^+
        try equal("", 0, sliceSeg(T, "abc", 0, 0, .hard, .{}));
        //         ^                  ^
        try equal("", 0, sliceSeg(T, "abc", 3, 0, .hard, .{}));
        //         ^                     ^
        try equal("", 2, sliceSeg(T, "abc", 5, 0, .hard, .{}));
        //           ^                     ^
    }

    // .soft truncation mode
    {
        // Bypass truncation
        try equal("abcd", 3, sliceSeg(T, "abcd", 3, 100, .soft, .{}));
        //            ^                      ^

        // Odd segment length
        try equal("abcd", 0, sliceSeg(T, "abcd", 0, 100, .soft, .{}));
        //         ^                      ^
        try equal("abc", 0, sliceSeg(T, "abcd", 0, 3, .soft, .{}));
        //         ^                     ^
        try equal("abc", 1, sliceSeg(T, "abcd", 1, 3, .soft, .{}));
        //          ^                     ^
        try equal("bcd", 1, sliceSeg(T, "abcd", 2, 3, .soft, .{}));
        //          ^                      ^
        try equal("bcd", 2, sliceSeg(T, "abcd", 3, 3, .soft, .{}));
        //           ^                      ^
        try equal("bcd", 3, sliceSeg(T, "abcd", 4, 3, .soft, .{}));
        //            ^                      ^
        try equal("bcd", 4, sliceSeg(T, "abcd", 5, 3, .soft, .{}));
        //             ^                      ^

        // Even segment length (right shifted)
        try equal("ab", 0, sliceSeg(T, "abcd", 0, 2, .soft, .{ .even_rshift = true }));
        //         ^                    ^
        try equal("bc", 0, sliceSeg(T, "abcd", 1, 2, .soft, .{ .even_rshift = true }));
        //         ^                     ^
        try equal("cd", 0, sliceSeg(T, "abcd", 2, 2, .soft, .{ .even_rshift = true }));
        //         ^                      ^
        try equal("cd", 1, sliceSeg(T, "abcd", 3, 2, .soft, .{ .even_rshift = true }));
        //          ^                      ^
        try equal("cd", 2, sliceSeg(T, "abcd", 4, 2, .soft, .{ .even_rshift = true }));
        //           ^                      ^
        try equal("cd", 3, sliceSeg(T, "abcd", 5, 2, .soft, .{ .even_rshift = true }));
        //            ^                      ^

        // Even segment length (left shifted)
        try equal("ab", 0, sliceSeg(T, "abcd", 0, 2, .soft, .{ .even_rshift = false }));
        //         ^                    ^
        try equal("ab", 1, sliceSeg(T, "abcd", 1, 2, .soft, .{ .even_rshift = false }));
        //          ^                    ^
        try equal("bc", 1, sliceSeg(T, "abcd", 2, 2, .soft, .{ .even_rshift = false }));
        //          ^                     ^
        try equal("cd", 1, sliceSeg(T, "abcd", 3, 2, .soft, .{ .even_rshift = false }));
        //          ^                      ^
        try equal("cd", 2, sliceSeg(T, "abcd", 4, 2, .soft, .{ .even_rshift = false }));
        //           ^                      ^
        try equal("cd", 3, sliceSeg(T, "abcd", 5, 2, .soft, .{ .even_rshift = false }));
        //            ^                      ^
    }

    // .hard truncation mode
    {
        // Bypass truncation
        try equal("abcd", 3, sliceSeg(T, "abcd", 3, 100, .hard, .{}));
        //            ^                      ^

        // Odd segment length
        try equal("ab", 0, sliceSeg(T, "abcd", 0, 3, .hard, .{}));
        //         ^                    ^
        try equal("abc", 1, sliceSeg(T, "abcd", 1, 3, .hard, .{}));
        //          ^                     ^
        try equal("bcd", 1, sliceSeg(T, "abcd", 2, 3, .hard, .{}));
        //          ^                      ^
        try equal("cd", 1, sliceSeg(T, "abcd", 3, 3, .hard, .{}));
        //          ^                      ^
        try equal("d", 1, sliceSeg(T, "abcd", 4, 3, .hard, .{}));
        //          ^                      ^
        try equal("", 1, sliceSeg(T, "abcd", 5, 3, .hard, .{}));
        //          ^                      ^
        try equal("", 2, sliceSeg(T, "abcd", 6, 3, .hard, .{}));
        //           ^                      ^

        // Even segment length (right shifted)
        try equal("ab", 0, sliceSeg(T, "abcd", 0, 2, .hard, .{ .even_rshift = true }));
        //         ^                    ^
        try equal("bc", 0, sliceSeg(T, "abcd", 1, 2, .hard, .{ .even_rshift = true }));
        //         ^                     ^
        try equal("cd", 0, sliceSeg(T, "abcd", 2, 2, .hard, .{ .even_rshift = true }));
        //         ^                      ^
        try equal("d", 0, sliceSeg(T, "abcd", 3, 2, .hard, .{ .even_rshift = true }));
        //         ^                      ^
        try equal("", 0, sliceSeg(T, "abcd", 4, 2, .hard, .{ .even_rshift = true }));
        //         ^                      ^
        try equal("", 1, sliceSeg(T, "abcd", 5, 2, .hard, .{ .even_rshift = true }));
        //          ^                      ^
        try equal("", 2, sliceSeg(T, "abcd", 6, 2, .hard, .{ .even_rshift = true }));
        //           ^                      ^

        // Even segment length (left shifted)
        try equal("a", 0, sliceSeg(T, "abcd", 0, 2, .hard, .{ .even_rshift = false }));
        //         ^                   ^
        try equal("ab", 1, sliceSeg(T, "abcd", 1, 2, .hard, .{ .even_rshift = false }));
        //          ^                    ^
        try equal("bc", 1, sliceSeg(T, "abcd", 2, 2, .hard, .{ .even_rshift = false }));
        //          ^                     ^
        try equal("cd", 1, sliceSeg(T, "abcd", 3, 2, .hard, .{ .even_rshift = false }));
        //          ^                      ^
        try equal("d", 1, sliceSeg(T, "abcd", 4, 2, .hard, .{ .even_rshift = false }));
        //          ^                      ^
        try equal("", 1, sliceSeg(T, "abcd", 5, 2, .hard, .{ .even_rshift = false }));
        //          ^                      ^
        try equal("", 2, sliceSeg(T, "abcd", 6, 2, .hard, .{ .even_rshift = false }));
        //           ^                      ^
    }

    // .hard_flex truncation mode
    {
        // Bypass truncation
        try equal("abcd", 3, sliceSeg(T, "abcd", 3, 100, .hard_flex, .{}));
        //            ^                      ^

        // Odd segment length
        try equal("abc", 0, sliceSeg(T, "abcd", 0, 3, .hard_flex, .{}));
        //         ^                     ^
        try equal("abc", 1, sliceSeg(T, "abcd", 1, 3, .hard_flex, .{}));
        //          ^                     ^
        try equal("bcd", 1, sliceSeg(T, "abcd", 2, 3, .hard_flex, .{}));
        //          ^                      ^
        try equal("bcd", 2, sliceSeg(T, "abcd", 3, 3, .hard_flex, .{}));
        //           ^                      ^
        try equal("cd", 2, sliceSeg(T, "abcd", 4, 3, .hard_flex, .{}));
        //           ^                      ^
        try equal("d", 2, sliceSeg(T, "abcd", 5, 3, .hard_flex, .{}));
        //           ^                      ^
        try equal("", 2, sliceSeg(T, "abcd", 6, 3, .hard_flex, .{}));
        //           ^                      ^

        // Even segment length (right shifted)
        try equal("ab", 0, sliceSeg(T, "abcd", 0, 2, .hard_flex, .{ .even_rshift = true }));
        //         ^                    ^
        try equal("bc", 0, sliceSeg(T, "abcd", 1, 2, .hard_flex, .{ .even_rshift = true }));
        //         ^                     ^
        try equal("cd", 0, sliceSeg(T, "abcd", 2, 2, .hard_flex, .{ .even_rshift = true }));
        //         ^                      ^
        try equal("cd", 1, sliceSeg(T, "abcd", 3, 2, .hard_flex, .{ .even_rshift = true }));
        //          ^                      ^
        try equal("d", 1, sliceSeg(T, "abcd", 4, 2, .hard_flex, .{ .even_rshift = true }));
        //          ^                      ^
        try equal("", 1, sliceSeg(T, "abcd", 5, 2, .hard_flex, .{ .even_rshift = true }));
        //          ^                      ^
        try equal("", 2, sliceSeg(T, "abcd", 6, 2, .hard_flex, .{ .even_rshift = true }));
        //           ^                      ^

        // Even segment length (left shifted)
        try equal("ab", 0, sliceSeg(T, "abcd", 0, 2, .hard_flex, .{ .even_rshift = false }));
        //         ^                    ^
        try equal("ab", 1, sliceSeg(T, "abcd", 1, 2, .hard_flex, .{ .even_rshift = false }));
        //          ^                    ^
        try equal("bc", 1, sliceSeg(T, "abcd", 2, 2, .hard_flex, .{ .even_rshift = false }));
        //          ^                     ^
        try equal("cd", 1, sliceSeg(T, "abcd", 3, 2, .hard_flex, .{ .even_rshift = false }));
        //          ^                      ^
        try equal("d", 1, sliceSeg(T, "abcd", 4, 2, .hard_flex, .{ .even_rshift = false }));
        //          ^                      ^
        try equal("", 1, sliceSeg(T, "abcd", 5, 2, .hard_flex, .{ .even_rshift = false }));
        //          ^                      ^
        try equal("", 2, sliceSeg(T, "abcd", 6, 2, .hard_flex, .{ .even_rshift = false }));
        //           ^                      ^
    }
}

/// Checks if the provided segment is a valid sub-slice of the given slice.
pub inline fn isSliceSeg(T: type, slice: []const T, seg: []const T) bool {
    const seg_ptr = @intFromPtr(seg.ptr);
    const slice_ptr = @intFromPtr(slice.ptr);
    return num.numInRangeInc(usize, seg_ptr, slice_ptr, slice_ptr + slice.len) and
        num.numInRangeInc(usize, seg_ptr + seg.len, slice_ptr, slice_ptr + slice.len);
}

test "+isSliceSeg" {
    const equal = std.testing.expectEqual;
    const slice: [11]u8 = "hello_world".*;

    try equal(true, isSliceSeg(u8, slice[0..], slice[0..0]));
    try equal(true, isSliceSeg(u8, slice[0..], slice[11..11]));
    try equal(true, isSliceSeg(u8, slice[0..], slice[0..1]));
    try equal(true, isSliceSeg(u8, slice[0..], slice[3..6]));
    try equal(true, isSliceSeg(u8, slice[0..], slice[10..11]));
    try equal(false, isSliceSeg(u8, slice[0..], "hello_world"));
    // intersecting
    try equal(true, isSliceSeg(u8, slice[0..5], slice[0..5])); // same
    try equal(true, isSliceSeg(u8, slice[0..0], slice[0..0]));
    try equal(true, isSliceSeg(u8, slice[11..11], slice[11..11])); // last zero
    try equal(false, isSliceSeg(u8, slice[0..5], slice[0..6]));
    try equal(false, isSliceSeg(u8, slice[0..5], slice[5..10]));
    try equal(false, isSliceSeg(u8, slice[5..10], slice[0..5]));
    try equal(false, isSliceSeg(u8, slice[0..0], slice[11..11]));
    try equal(false, isSliceSeg(u8, slice[0..6], slice[5..11]));
}
