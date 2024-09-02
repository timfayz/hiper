// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

//! Public API:
//! - reverseSlice()
//! - intersectSlices()
//! - mergeSlices()
//! - indexOfSliceStart()
//! - indexOfSliceEnd()
//! - SliceIndices
//! - sliceIndices()
//! - sliceStart()
//! - sliceStartIndices()
//! - sliceEnd()
//! - sliceEndIndices()
//! - sliceRange()
//! - SliceAroundOptions
//! - SliceAroundMode
//! - SliceAroundInfo()
//! - sliceAround()
//! - SliceAroundIndices
//! - sliceAroundIndices()
//! - isSubSlice()

const std = @import("std");
const num = @import("num.zig");

/// Reverses slice items in-place.
pub fn reverseSlice(slice: anytype) void {
    comptime {
        const T_info = @typeInfo(@TypeOf(slice));
        if (T_info != .pointer and T_info.Pointer.size != .slice)
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

test "+reverseSlice" {
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

/// Returns the intersection of two slices. Note: This function works correctly
/// only if both slices originate from the same source.
/// ```txt
/// [slice1+] [+slice2]    (slices disjoint)
///         null
///
/// [slice1+++]            (slices intersect)
///         [+++slice2]
///         [+]            (intersection)
/// ```
pub fn intersectSlices(T: type, slice1: T, slice2: T) ?T {
    var slice: T = undefined;
    const ptr1 = @intFromPtr(slice1.ptr);
    const ptr2 = @intFromPtr(slice2.ptr);
    const start = @max(ptr1, ptr2);
    const end = @min(ptr1 + slice1.len, ptr2 + slice2.len);
    if (start >= end) return null;
    slice.ptr = @ptrFromInt(start);
    slice.len = end - start;
    return slice;
}

test "+intersectSlices" {
    const equal = struct {
        pub fn check(expect: ?[]const u8, actual: ?[]const u8) !void {
            if (expect == null) return std.testing.expectEqual(null, actual);
            if (actual == null) return std.testing.expectEqual(expect, null);
            try std.testing.expectEqualStrings(expect.?, actual.?);
        }
    }.check;

    const in1 = "abcd";
    try equal(null, intersectSlices([]const u8, in1[0..0], in1[4..4])); // zero slices
    try equal(null, intersectSlices([]const u8, in1[0..2], in1[2..4])); // touching boundaries

    try equal("c", intersectSlices([]const u8, in1[0..3], in1[2..4])); // intersecting slices
    try equal("c", intersectSlices([]const u8, in1[2..4], in1[0..3])); // (!) order

    try equal("bc", intersectSlices([]const u8, in1[0..3], in1[1..4])); // intersecting slices
    try equal("bc", intersectSlices([]const u8, in1[1..4], in1[0..3])); // (!) order

    try equal("abcd", intersectSlices([]const u8, in1[0..4], in1[0..4])); // same slices

    try equal("bc", intersectSlices([]const u8, in1[0..4], in1[1..3])); // one within other
    try equal("bc", intersectSlices([]const u8, in1[1..3], in1[0..4])); // (!) order
}

/// Returns the union of two slices. Note: This function works correctly only if
/// both slices originate from the same source.
/// ```txt
/// [slice1+] [+slice2]    (slices disjoint)
/// |+++++++++++++++++|    (merged)
///
/// [slice1+++]            (slices intersect)
///         [+++slice2]
/// |+++++++++++++++++|    (merged)
/// ```
pub fn mergeSlices(
    T: type,
    slice1: T,
    slice2: T,
) T {
    var slice: T = undefined;
    const ptr1 = @intFromPtr(slice1.ptr);
    const ptr2 = @intFromPtr(slice2.ptr);
    const start = @min(ptr1, ptr2);
    const end = @max(ptr1 + slice1.len, ptr2 + slice2.len);
    slice.ptr = @ptrFromInt(start);
    slice.len = end - start;
    return slice;
}

test "+mergeSlices" {
    const equal = std.testing.expectEqualStrings;
    const in1 = "abcd";
    try equal("abcd", mergeSlices([]const u8, in1[0..0], in1[4..4])); // zero slices
    try equal("abcd", mergeSlices([]const u8, in1[4..4], in1[0..0])); // (!) order

    try equal("abcd", mergeSlices([]const u8, in1[0..2], in1[2..4])); // normal slices
    try equal("abcd", mergeSlices([]const u8, in1[2..4], in1[0..2])); // (!) order

    try equal("abcd", mergeSlices([]const u8, in1[0..3], in1[1..4])); // intersected slices

    try equal("abcd", mergeSlices([]const u8, in1[0..4], in1[0..4])); // same slices
}

/// Retrieves the starting position of a slice in source.
pub inline fn indexOfSliceStart(source: anytype, slice: anytype) usize {
    return slice.ptr - source.ptr;
}

/// Retrieves the ending position of a slice in source.
pub inline fn indexOfSliceEnd(source: anytype, slice: anytype) usize {
    return (slice.ptr - source.ptr) +| slice.len;
}

test "+indexOfSliceStart, indexOfSliceEnd" {
    const equal = std.testing.expectEqual;

    const empty = "";
    const input = "0123456789";

    try equal(0, indexOfSliceEnd(empty, empty[0..0]));
    try equal(0, indexOfSliceEnd(input, input[0..0]));
    try equal(7, indexOfSliceEnd(input, input[3..7]));
    try equal(9, indexOfSliceEnd(input, input[3..9]));
    try equal(10, indexOfSliceEnd(input, input[3..10]));

    try equal(0, indexOfSliceStart(empty, empty[0..0]));
    try equal(0, indexOfSliceStart(input, input[0..0]));
    try equal(3, indexOfSliceStart(input, input[3..7]));
    try equal(9, indexOfSliceStart(input, input[9..10]));
    try equal(10, indexOfSliceStart(input, input[10..10]));
}

/// Return structure for `sliceIndices()`, `sliceStartIndices()` and
/// `sliceEndIndices()`.
pub const SliceIndices = struct {
    start: usize,
    end: usize,
};

/// Retrieves the starting and ending positions of a slice in source.
pub inline fn sliceIndices(source: anytype, slice: anytype) SliceIndices {
    return .{
        .start = indexOfSliceStart(source, slice),
        .end = indexOfSliceEnd(source, slice),
    };
}

/// Returns the beginning of a slice with a specified length. If `len`
/// is larger than the slice length, the entire slice is returned.
pub inline fn sliceStart(T: type, slice: T, len: usize) T {
    return slice[0..@min(slice.len, len)];
}

/// Returns indices corresponding to the slice start with specified length. If
/// `len` is greater than `slice.len`, the `slice.len` is used as an end index.
pub inline fn sliceStartIndices(slice: anytype, len: usize) SliceIndices {
    return .{ .start = 0, .end = @min(slice.len, len) };
}

/// Returns the ending of a slice with a specified length. If `len`
/// is larger than the slice length, the entire slice is returned.
pub inline fn sliceEnd(T: type, slice: T, len: usize) T {
    return slice[slice.len -| len..];
}

/// Returns indices corresponding to the slice end with specified length. If
/// `len` is greater than `slice.len`, returns full (`0..slice.len`) range.
pub inline fn sliceEndIndices(slice: anytype, len: usize) SliceIndices {
    return .{ .start = slice.len -| len, .end = slice.len };
}

test "+sliceStart, sliceStartIndices, sliceEnd, sliceEndIndices" {
    const t = std.testing;
    const case = struct {
        fn run(comptime mode: enum { start, end }, expect: []const u8, T: type, slice: anytype, len: usize) !void {
            const seg = if (mode == .start) sliceStart(T, slice, len) else sliceEnd(T, slice, len);
            try t.expectEqualStrings(expect, seg);
            const idx = if (mode == .start) sliceStartIndices(slice, len) else sliceEndIndices(slice, len);
            try t.expectEqual(indexOfSliceStart(slice, seg), idx.start);
            try t.expectEqual(indexOfSliceEnd(slice, seg), idx.end);
        }
    }.run;

    // format: try case(|fn|, |expect|, |slice type|, |input|, |len|)

    try case(.start, "", []const u8, "", 0);
    try case(.start, "", []const u8, "abc", 0);
    try case(.start, "a", []const u8, "abc", 1);
    try case(.start, "ab", []const u8, "abc", 2);
    try case(.start, "abc", []const u8, "abc", 3);
    try case(.start, "abc", []const u8, "abc", 4);
    try case(.start, "abc", []const u8, "abc", 100);

    try case(.end, "", []const u8, "", 0);
    try case(.end, "", []const u8, "abc", 0);
    try case(.end, "c", []const u8, "abc", 1);
    try case(.end, "bc", []const u8, "abc", 2);
    try case(.end, "abc", []const u8, "abc", 3);
    try case(.end, "abc", []const u8, "abc", 4);
    try case(.end, "abc", []const u8, "abc", 100);
}

/// Returns a normal `[start..end]` slice with indices normalized to not
/// exceed the `slice.len`.
pub fn sliceRange(T: type, slice: T, start: usize, end: usize) T {
    return slice[@min(slice.len, start)..@min(slice.len, end)];
}

test "+sliceRange" {
    const equal = std.testing.expectEqualStrings;
    try equal("", sliceRange([]const u8, "abcd", 0, 0));
    try equal("", sliceRange([]const u8, "abcd", 100, 100));
    try equal("", sliceRange([]const u8, "abcd", 3, 3));
    try equal("a", sliceRange([]const u8, "abcd", 0, 1));
    try equal("bc", sliceRange([]const u8, "abcd", 1, 3));
    try equal("d", sliceRange([]const u8, "abcd", 3, 4));
}

/// Options for `sliceAround()`.
pub const SliceAroundOptions = struct {
    /// Shifts even-length ranges by one index to the right.
    even_rshift: bool = true,
    /// See `SliceAroundMode` for details.
    slicing_mode: SliceAroundMode,
};

/// Controls how `sliceAround()` truncates a slice segment.
pub const SliceAroundMode = enum {
    /// Truncates directly by the slice bounds.
    hard,
    /// Truncates by the slice bounds but compensates for the truncated length
    /// by extending left or right as much as possible.
    hard_flex,
    /// Truncates to a constant length that always fits within slice bounds,
    /// even with out-of-bounds indices.
    soft,
};

/// Return structure of `sliceAround`.
pub fn SliceAroundInfo(T: type) type {
    return struct { slice: T, index_pos: usize };
}

/// Returns a slice segment of length `len` centered around the index, along
/// with relative position of the original index within the segment. The returned
/// index can be out of segment bounds if the original index was out of slice.
/// See `SliceAroundOptions` for additional options.
pub fn sliceAround(
    T: type,
    slice: T,
    index: usize,
    len: usize,
    comptime opt: SliceAroundOptions,
) SliceAroundInfo(T) {
    const info = sliceAroundIndices(slice, index, len, opt);
    return .{
        .slice = slice[info.start..info.end],
        .index_pos = info.index_pos,
    };
}

/// Return structure of `sliceAroundIndices()`.
const SliceAroundIndices = struct {
    start: usize,
    end: usize,
    index_pos: usize,
};

/// Returns the start and end indices of a slice segment of length `len`
/// centered around the index, along with the relative position of the original
/// index within the segment. The returned index can be out of segment bounds if
/// the original index was out of slice. See `SliceAroundOptions` for additional
/// options.
pub fn sliceAroundIndices(
    slice: anytype,
    index: usize,
    len: usize,
    comptime opt: SliceAroundOptions,
) SliceAroundIndices {
    if (slice.len == 0) return .{
        .start = 0,
        .end = 0,
        .index_pos = index,
    };

    if (len == 0) {
        const idx = @min(index, slice.len);
        return .{
            .start = idx,
            .end = idx,
            .index_pos = index -| idx,
        };
    }

    const len_is_even = len & 1 == 0;
    const rshift_start: usize = if (opt.even_rshift and len_is_even) 1 else 0;
    const rshift_end: usize = if (len_is_even) rshift_start else 1;

    const dist = len / 2;
    const dist_to_start = dist -| rshift_start;
    const dist_to_end = dist +| rshift_end;

    const start = @min(
        index -| dist_to_start,
        switch (opt.slicing_mode) {
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
        switch (opt.slicing_mode) {
            .hard => index +| dist_to_end,
            .hard_flex, .soft => start +| len,
        },
    );

    return .{
        .start = start,
        .end = end,
        .index_pos = index - start,
    };
}

test "+sliceAround" {
    const t = std.testing;

    const equal = struct {
        fn run(
            expect_slice: []const u8,
            expect_index_pos: usize,
            result: SliceAroundInfo([]const u8),
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
        try equal("", 10, sliceAround(T, "", 10, 100, .{ .slicing_mode = .hard }));
        //         ^+                     ^+
        try equal("", 10, sliceAround(T, "", 10, 0, .{ .slicing_mode = .hard }));
        //         ^+                     ^+
        try equal("", 0, sliceAround(T, "abc", 0, 0, .{ .slicing_mode = .hard }));
        //         ^                     ^
        try equal("", 0, sliceAround(T, "abc", 3, 0, .{ .slicing_mode = .hard }));
        //         ^                        ^
        try equal("", 2, sliceAround(T, "abc", 5, 0, .{ .slicing_mode = .hard }));
        //           ^                        ^
    }

    // .soft truncation mode
    {
        // Bypass truncation
        try equal("abcd", 3, sliceAround(T, "abcd", 3, 100, .{ .slicing_mode = .soft }));
        //            ^                      ^

        // Odd segment length
        try equal("abcd", 0, sliceAround(T, "abcd", 0, 100, .{ .slicing_mode = .soft }));
        //         ^                         ^
        try equal("abc", 0, sliceAround(T, "abcd", 0, 3, .{ .slicing_mode = .soft }));
        //         ^                        ^
        try equal("abc", 1, sliceAround(T, "abcd", 1, 3, .{ .slicing_mode = .soft }));
        //          ^                        ^
        try equal("bcd", 1, sliceAround(T, "abcd", 2, 3, .{ .slicing_mode = .soft }));
        //          ^                         ^
        try equal("bcd", 2, sliceAround(T, "abcd", 3, 3, .{ .slicing_mode = .soft }));
        //           ^                         ^
        try equal("bcd", 3, sliceAround(T, "abcd", 4, 3, .{ .slicing_mode = .soft }));
        //            ^                         ^
        try equal("bcd", 4, sliceAround(T, "abcd", 5, 3, .{ .slicing_mode = .soft }));
        //             ^                         ^

        // Even segment length (right shifted)
        try equal("ab", 0, sliceAround(T, "abcd", 0, 2, .{ .slicing_mode = .soft, .even_rshift = true }));
        //         ^                       ^
        try equal("bc", 0, sliceAround(T, "abcd", 1, 2, .{ .slicing_mode = .soft, .even_rshift = true }));
        //         ^                        ^
        try equal("cd", 0, sliceAround(T, "abcd", 2, 2, .{ .slicing_mode = .soft, .even_rshift = true }));
        //         ^                         ^
        try equal("cd", 1, sliceAround(T, "abcd", 3, 2, .{ .slicing_mode = .soft, .even_rshift = true }));
        //          ^                         ^
        try equal("cd", 2, sliceAround(T, "abcd", 4, 2, .{ .slicing_mode = .soft, .even_rshift = true }));
        //           ^                         ^
        try equal("cd", 3, sliceAround(T, "abcd", 5, 2, .{ .slicing_mode = .soft, .even_rshift = true }));
        //            ^                         ^

        // Even segment length (left shifted)
        try equal("ab", 0, sliceAround(T, "abcd", 0, 2, .{ .slicing_mode = .soft, .even_rshift = false }));
        //         ^                       ^
        try equal("ab", 1, sliceAround(T, "abcd", 1, 2, .{ .slicing_mode = .soft, .even_rshift = false }));
        //          ^                       ^
        try equal("bc", 1, sliceAround(T, "abcd", 2, 2, .{ .slicing_mode = .soft, .even_rshift = false }));
        //          ^                        ^
        try equal("cd", 1, sliceAround(T, "abcd", 3, 2, .{ .slicing_mode = .soft, .even_rshift = false }));
        //          ^                         ^
        try equal("cd", 2, sliceAround(T, "abcd", 4, 2, .{ .slicing_mode = .soft, .even_rshift = false }));
        //           ^                         ^
        try equal("cd", 3, sliceAround(T, "abcd", 5, 2, .{ .slicing_mode = .soft, .even_rshift = false }));
        //            ^                         ^
    }

    // .hard truncation mode
    {
        // Bypass truncation
        try equal("abcd", 3, sliceAround(T, "abcd", 3, 100, .{ .slicing_mode = .hard }));
        //            ^                         ^

        // Odd segment length
        try equal("ab", 0, sliceAround(T, "abcd", 0, 3, .{ .slicing_mode = .hard }));
        //         ^                       ^
        try equal("abc", 1, sliceAround(T, "abcd", 1, 3, .{ .slicing_mode = .hard }));
        //          ^                        ^
        try equal("bcd", 1, sliceAround(T, "abcd", 2, 3, .{ .slicing_mode = .hard }));
        //          ^                         ^
        try equal("cd", 1, sliceAround(T, "abcd", 3, 3, .{ .slicing_mode = .hard }));
        //          ^                         ^
        try equal("d", 1, sliceAround(T, "abcd", 4, 3, .{ .slicing_mode = .hard }));
        //          ^                         ^
        try equal("", 1, sliceAround(T, "abcd", 5, 3, .{ .slicing_mode = .hard }));
        //          ^                         ^
        try equal("", 2, sliceAround(T, "abcd", 6, 3, .{ .slicing_mode = .hard }));
        //           ^                         ^

        // Even segment length (right shifted)
        try equal("ab", 0, sliceAround(T, "abcd", 0, 2, .{ .slicing_mode = .hard, .even_rshift = true }));
        //         ^                       ^
        try equal("bc", 0, sliceAround(T, "abcd", 1, 2, .{ .slicing_mode = .hard, .even_rshift = true }));
        //         ^                        ^
        try equal("cd", 0, sliceAround(T, "abcd", 2, 2, .{ .slicing_mode = .hard, .even_rshift = true }));
        //         ^                         ^
        try equal("d", 0, sliceAround(T, "abcd", 3, 2, .{ .slicing_mode = .hard, .even_rshift = true }));
        //         ^                         ^
        try equal("", 0, sliceAround(T, "abcd", 4, 2, .{ .slicing_mode = .hard, .even_rshift = true }));
        //         ^                         ^
        try equal("", 1, sliceAround(T, "abcd", 5, 2, .{ .slicing_mode = .hard, .even_rshift = true }));
        //          ^                         ^
        try equal("", 2, sliceAround(T, "abcd", 6, 2, .{ .slicing_mode = .hard, .even_rshift = true }));
        //           ^                         ^

        // Even segment length (left shifted)
        try equal("a", 0, sliceAround(T, "abcd", 0, 2, .{ .slicing_mode = .hard, .even_rshift = false }));
        //         ^                      ^
        try equal("ab", 1, sliceAround(T, "abcd", 1, 2, .{ .slicing_mode = .hard, .even_rshift = false }));
        //          ^                       ^
        try equal("bc", 1, sliceAround(T, "abcd", 2, 2, .{ .slicing_mode = .hard, .even_rshift = false }));
        //          ^                        ^
        try equal("cd", 1, sliceAround(T, "abcd", 3, 2, .{ .slicing_mode = .hard, .even_rshift = false }));
        //          ^                         ^
        try equal("d", 1, sliceAround(T, "abcd", 4, 2, .{ .slicing_mode = .hard, .even_rshift = false }));
        //          ^                         ^
        try equal("", 1, sliceAround(T, "abcd", 5, 2, .{ .slicing_mode = .hard, .even_rshift = false }));
        //          ^                         ^
        try equal("", 2, sliceAround(T, "abcd", 6, 2, .{ .slicing_mode = .hard, .even_rshift = false }));
        //           ^                         ^
    }

    // .hard_flex truncation mode
    {
        // Bypass truncation
        try equal("abcd", 3, sliceAround(T, "abcd", 3, 100, .{ .slicing_mode = .hard_flex }));
        //            ^                         ^

        // Odd segment length
        try equal("abc", 0, sliceAround(T, "abcd", 0, 3, .{ .slicing_mode = .hard_flex }));
        //         ^                        ^
        try equal("abc", 1, sliceAround(T, "abcd", 1, 3, .{ .slicing_mode = .hard_flex }));
        //          ^                        ^
        try equal("bcd", 1, sliceAround(T, "abcd", 2, 3, .{ .slicing_mode = .hard_flex }));
        //          ^                         ^
        try equal("bcd", 2, sliceAround(T, "abcd", 3, 3, .{ .slicing_mode = .hard_flex }));
        //           ^                         ^
        try equal("cd", 2, sliceAround(T, "abcd", 4, 3, .{ .slicing_mode = .hard_flex }));
        //           ^                         ^
        try equal("d", 2, sliceAround(T, "abcd", 5, 3, .{ .slicing_mode = .hard_flex }));
        //           ^                         ^
        try equal("", 2, sliceAround(T, "abcd", 6, 3, .{ .slicing_mode = .hard_flex }));
        //           ^                         ^

        // Even segment length (right shifted)
        try equal("ab", 0, sliceAround(T, "abcd", 0, 2, .{ .slicing_mode = .hard_flex, .even_rshift = true }));
        //         ^                       ^
        try equal("bc", 0, sliceAround(T, "abcd", 1, 2, .{ .slicing_mode = .hard_flex, .even_rshift = true }));
        //         ^                        ^
        try equal("cd", 0, sliceAround(T, "abcd", 2, 2, .{ .slicing_mode = .hard_flex, .even_rshift = true }));
        //         ^                         ^
        try equal("cd", 1, sliceAround(T, "abcd", 3, 2, .{ .slicing_mode = .hard_flex, .even_rshift = true }));
        //          ^                         ^
        try equal("d", 1, sliceAround(T, "abcd", 4, 2, .{ .slicing_mode = .hard_flex, .even_rshift = true }));
        //          ^                         ^
        try equal("", 1, sliceAround(T, "abcd", 5, 2, .{ .slicing_mode = .hard_flex, .even_rshift = true }));
        //          ^                         ^
        try equal("", 2, sliceAround(T, "abcd", 6, 2, .{ .slicing_mode = .hard_flex, .even_rshift = true }));
        //           ^                         ^

        // Even segment length (left shifted)
        try equal("ab", 0, sliceAround(T, "abcd", 0, 2, .{ .slicing_mode = .hard_flex, .even_rshift = false }));
        //         ^                       ^
        try equal("ab", 1, sliceAround(T, "abcd", 1, 2, .{ .slicing_mode = .hard_flex, .even_rshift = false }));
        //          ^                       ^
        try equal("bc", 1, sliceAround(T, "abcd", 2, 2, .{ .slicing_mode = .hard_flex, .even_rshift = false }));
        //          ^                        ^
        try equal("cd", 1, sliceAround(T, "abcd", 3, 2, .{ .slicing_mode = .hard_flex, .even_rshift = false }));
        //          ^                         ^
        try equal("d", 1, sliceAround(T, "abcd", 4, 2, .{ .slicing_mode = .hard_flex, .even_rshift = false }));
        //          ^                         ^
        try equal("", 1, sliceAround(T, "abcd", 5, 2, .{ .slicing_mode = .hard_flex, .even_rshift = false }));
        //          ^                         ^
        try equal("", 2, sliceAround(T, "abcd", 6, 2, .{ .slicing_mode = .hard_flex, .even_rshift = false }));
        //           ^                         ^
    }
}

/// Checks if the provided segment is a valid sub-slice of the given slice.
pub inline fn isSubSlice(T: type, slice: []const T, sub: []const T) bool {
    const seg_ptr = @intFromPtr(sub.ptr);
    const slice_ptr = @intFromPtr(slice.ptr);
    return num.numInRangeInc(usize, seg_ptr, slice_ptr, slice_ptr + slice.len) and
        num.numInRangeInc(usize, seg_ptr + sub.len, slice_ptr, slice_ptr + slice.len);
}

test "+isSubSlice" {
    const equal = std.testing.expectEqual;
    const slice: [11]u8 = "hello_world".*;

    try equal(true, isSubSlice(u8, slice[0..], slice[0..0]));
    try equal(true, isSubSlice(u8, slice[0..], slice[11..11]));
    try equal(true, isSubSlice(u8, slice[0..], slice[0..1]));
    try equal(true, isSubSlice(u8, slice[0..], slice[3..6]));
    try equal(true, isSubSlice(u8, slice[0..], slice[10..11]));
    try equal(false, isSubSlice(u8, slice[0..], "hello_world"));
    // intersecting
    try equal(true, isSubSlice(u8, slice[0..5], slice[0..5])); // same
    try equal(true, isSubSlice(u8, slice[0..0], slice[0..0]));
    try equal(true, isSubSlice(u8, slice[11..11], slice[11..11])); // last zero
    try equal(false, isSubSlice(u8, slice[0..5], slice[0..6]));
    try equal(false, isSubSlice(u8, slice[0..5], slice[5..10]));
    try equal(false, isSubSlice(u8, slice[5..10], slice[0..5]));
    try equal(false, isSubSlice(u8, slice[0..0], slice[11..11]));
    try equal(false, isSubSlice(u8, slice[0..6], slice[5..11]));
}
