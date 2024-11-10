// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

//! Public API:
//! - reverse()
//! - intersect()
//! - merge()
//! - indexOfStart()
//! - indexOfEnd()
//! - Indices
//! - seg()
//! - segIndices()
//! - segStart()
//! - segStartIndices()
//! - segEnd()
//! - segEndIndices()
//! - SegAroundOptions
//! - SegAroundMode
//! - SegAroundInfo
//! - segAround()
//! - SegAroundIndices
//! - segAroundIndices()
//! - isSeg()
//! - moveSegLeft()
//! - moveSegRight()
//! - MoveSegError
//! - MoveSegDirection

const std = @import("std");
const num = @import("num.zig");

/// Reverses slice items in-place.
pub fn reverse(slice: anytype) void {
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

test "+reverse" {
    const t = std.testing;

    const case = struct {
        pub fn run(input: []const u8, expect: []const u8) !void {
            var buf: [32]u8 = undefined;
            for (input, 0..) |byte, i| buf[i] = byte;
            const actual = buf[0..input.len];
            reverse(actual);
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
pub fn intersect(T: type, slice1: T, slice2: T) ?T {
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

test "+intersect" {
    const equal = struct {
        pub fn check(expect: ?[]const u8, actual: ?[]const u8) !void {
            if (expect == null) return std.testing.expectEqual(null, actual);
            if (actual == null) return std.testing.expectEqual(expect, null);
            try std.testing.expectEqualStrings(expect.?, actual.?);
        }
    }.check;

    const in1 = "abcd";
    try equal(null, intersect([]const u8, in1[0..0], in1[4..4])); // zero slices
    try equal(null, intersect([]const u8, in1[0..2], in1[2..4])); // touching boundaries

    try equal("c", intersect([]const u8, in1[0..3], in1[2..4])); // intersecting slices
    try equal("c", intersect([]const u8, in1[2..4], in1[0..3])); // (!) order

    try equal("bc", intersect([]const u8, in1[0..3], in1[1..4])); // intersecting slices
    try equal("bc", intersect([]const u8, in1[1..4], in1[0..3])); // (!) order

    try equal("abcd", intersect([]const u8, in1[0..4], in1[0..4])); // same slices

    try equal("bc", intersect([]const u8, in1[0..4], in1[1..3])); // one within other
    try equal("bc", intersect([]const u8, in1[1..3], in1[0..4])); // (!) order
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
pub fn merge(
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

test "+merge" {
    const equal = std.testing.expectEqualStrings;
    const in1 = "abcd";
    try equal("abcd", merge([]const u8, in1[0..0], in1[4..4])); // zero slices
    try equal("abcd", merge([]const u8, in1[4..4], in1[0..0])); // (!) order

    try equal("abcd", merge([]const u8, in1[0..2], in1[2..4])); // normal slices
    try equal("abcd", merge([]const u8, in1[2..4], in1[0..2])); // (!) order

    try equal("abcd", merge([]const u8, in1[0..3], in1[1..4])); // intersected slices

    try equal("abcd", merge([]const u8, in1[0..4], in1[0..4])); // same slices
}

/// Retrieves the starting position of a slice in source.
pub inline fn indexOfStart(source: anytype, slice: anytype) usize {
    return slice.ptr - source.ptr;
}

/// Retrieves the ending position of a slice in source.
pub inline fn indexOfEnd(source: anytype, slice: anytype) usize {
    return (slice.ptr - source.ptr) +| slice.len;
}

test "+indexOfStart, indexOfEnd" {
    const equal = std.testing.expectEqual;

    const empty = "";
    const input = "0123456789";

    try equal(0, indexOfEnd(empty, empty[0..0]));
    try equal(0, indexOfEnd(input, input[0..0]));
    try equal(7, indexOfEnd(input, input[3..7]));
    try equal(9, indexOfEnd(input, input[3..9]));
    try equal(10, indexOfEnd(input, input[3..10]));

    try equal(0, indexOfStart(empty, empty[0..0]));
    try equal(0, indexOfStart(input, input[0..0]));
    try equal(3, indexOfStart(input, input[3..7]));
    try equal(9, indexOfStart(input, input[9..10]));
    try equal(10, indexOfStart(input, input[10..10]));
}

/// Return structure for `segIndices()`, `segStartIndices()` and
/// `segEndIndices()`.
pub const Indices = struct {
    start: usize,
    end: usize,
};

/// Returns a normal `[start..end]` slice segment with indices normalized to not
/// exceed the `slice.len`.
pub fn seg(T: type, slice: T, start: usize, end: usize) T {
    return slice[@min(slice.len, start)..@min(slice.len, end)];
}

test "+seg" {
    const equal = std.testing.expectEqualStrings;
    try equal("", seg([]const u8, "abcd", 0, 0));
    try equal("", seg([]const u8, "abcd", 100, 100));
    try equal("", seg([]const u8, "abcd", 3, 3));
    try equal("a", seg([]const u8, "abcd", 0, 1));
    try equal("bc", seg([]const u8, "abcd", 1, 3));
    try equal("d", seg([]const u8, "abcd", 3, 4));
}

/// Retrieves the starting and ending positions of a slice in source.
pub inline fn segIndices(source: anytype, slice: anytype) Indices {
    return .{
        .start = indexOfStart(source, slice),
        .end = indexOfEnd(source, slice),
    };
}

/// Returns the beginning slice segment with a specified length. If `len` is
/// larger than the slice length, the entire slice is returned.
pub inline fn segStart(T: type, slice: T, len: usize) T {
    return slice[0..@min(slice.len, len)];
}

/// Returns indices corresponding to the beginning slice segment with specified
/// length. If `len` is larger than `slice.len`, the `slice.len` is used as an
/// end index.
pub inline fn segStartIndices(slice: anytype, len: usize) Indices {
    return .{ .start = 0, .end = @min(slice.len, len) };
}

/// Returns the ending slice segment with a specified length. If `len`
/// is larger than the slice length, the entire slice is returned.
pub inline fn segEnd(T: type, slice: T, len: usize) T {
    return slice[slice.len -| len..];
}

/// Returns indices corresponding to the ending slice segment with specified
/// length. If `len` is larger than `slice.len`, returns full (`0..slice.len`)
/// range.
pub inline fn segEndIndices(slice: anytype, len: usize) Indices {
    return .{ .start = slice.len -| len, .end = slice.len };
}

test "+segStart, segStartIndices, segEnd, segEndIndices" {
    const t = std.testing;
    const case = struct {
        fn run(comptime mode: enum { start, end }, expect: []const u8, T: type, slice: anytype, len: usize) !void {
            const sg = if (mode == .start) segStart(T, slice, len) else segEnd(T, slice, len);
            try t.expectEqualStrings(expect, sg);
            const idx = if (mode == .start) segStartIndices(slice, len) else segEndIndices(slice, len);
            try t.expectEqual(indexOfStart(slice, sg), idx.start);
            try t.expectEqual(indexOfEnd(slice, sg), idx.end);
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

/// Options for `segAround()`.
pub const SegAroundOptions = struct {
    /// Shifts even-length ranges by one index to the right.
    even_rshift: bool = true,
    /// See `SegAroundMode` for details.
    slicing_mode: SegAroundMode = .hard_flex,
};

/// Controls how `segAround()` truncates a slice segment.
/// See `segAround()` tests for detailed examples of each mode.
pub const SegAroundMode = enum {
    /// Truncates segment directly by the slice bounds.
    hard,
    /// Truncates segment by the slice bounds but compensates for the truncated
    /// length by extending the segment left or right as much as possible.
    hard_flex,
    /// Truncated segment is of constant length that always fits within slice
    /// bounds, even with out-of-bounds indices.
    soft,
};

/// Return structure of `segAround()`.
pub fn SegAroundInfo(T: type) type {
    return struct { slice: T, index_pos: usize };
}

/// Returns a slice segment of length `len` centered around the index, along
/// with relative position of the original index within the segment. The returned
/// index can be out of segment bounds if the original index was out of slice.
/// See `SegAroundOptions` for additional options.
pub fn segAround(
    T: type,
    slice: T,
    index: usize,
    len: usize,
    comptime opt: SegAroundOptions,
) SegAroundInfo(T) {
    const info = segAroundIndices(slice, index, len, opt);
    return .{
        .slice = slice[info.start..info.end],
        .index_pos = info.index_pos,
    };
}

/// Return structure of `segAroundIndices()`.
const SegAroundIndices = struct {
    start: usize,
    end: usize,
    index_pos: usize,
};

/// Returns the start and end indices of a slice segment of length `len`
/// centered around the index, along with the relative position of the original
/// index within the segment. The returned index can be out of segment bounds if
/// the original index was out of slice. See `SegAroundOptions` for additional
/// options.
pub fn segAroundIndices(
    slice: anytype,
    index: usize,
    len: usize,
    comptime opt: SegAroundOptions,
) SegAroundIndices {
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

test "+segAround" {
    const t = std.testing;

    const equal = struct {
        fn run(
            expect_slice: []const u8,
            expect_index_pos: usize,
            result: SegAroundInfo([]const u8),
        ) !void {
            try t.expectEqualStrings(expect_slice, result.slice);
            try t.expectEqual(expect_index_pos, result.index_pos);
        }
    }.run;

    // Format:
    //
    // try equal(|expected seg|, |expected index_pos|, |fn result|)

    const T = []const u8;

    // Any truncation mode
    {
        // Zero segment or slice length
        try equal("", 10, segAround(T, "", 10, 100, .{ .slicing_mode = .hard }));
        //         ^+                     ^+
        try equal("", 10, segAround(T, "", 10, 0, .{ .slicing_mode = .hard }));
        //         ^+                     ^+
        try equal("", 0, segAround(T, "abc", 0, 0, .{ .slicing_mode = .hard }));
        //         ^                     ^
        try equal("", 0, segAround(T, "abc", 3, 0, .{ .slicing_mode = .hard }));
        //         ^                        ^
        try equal("", 2, segAround(T, "abc", 5, 0, .{ .slicing_mode = .hard }));
        //           ^                        ^
    }

    // .soft truncation mode
    {
        // Bypass truncation
        try equal("abcd", 3, segAround(T, "abcd", 3, 100, .{ .slicing_mode = .soft }));
        //            ^                      ^

        // Odd segment length
        try equal("abcd", 0, segAround(T, "abcd", 0, 100, .{ .slicing_mode = .soft }));
        //         ^                         ^
        try equal("abc", 0, segAround(T, "abcd", 0, 3, .{ .slicing_mode = .soft }));
        //         ^                        ^
        try equal("abc", 1, segAround(T, "abcd", 1, 3, .{ .slicing_mode = .soft }));
        //          ^                        ^
        try equal("bcd", 1, segAround(T, "abcd", 2, 3, .{ .slicing_mode = .soft }));
        //          ^                         ^
        try equal("bcd", 2, segAround(T, "abcd", 3, 3, .{ .slicing_mode = .soft }));
        //           ^                         ^
        try equal("bcd", 3, segAround(T, "abcd", 4, 3, .{ .slicing_mode = .soft }));
        //            ^                         ^
        try equal("bcd", 4, segAround(T, "abcd", 5, 3, .{ .slicing_mode = .soft }));
        //             ^                         ^

        // Even segment length (right shifted)
        try equal("ab", 0, segAround(T, "abcd", 0, 2, .{ .slicing_mode = .soft, .even_rshift = true }));
        //         ^                       ^
        try equal("bc", 0, segAround(T, "abcd", 1, 2, .{ .slicing_mode = .soft, .even_rshift = true }));
        //         ^                        ^
        try equal("cd", 0, segAround(T, "abcd", 2, 2, .{ .slicing_mode = .soft, .even_rshift = true }));
        //         ^                         ^
        try equal("cd", 1, segAround(T, "abcd", 3, 2, .{ .slicing_mode = .soft, .even_rshift = true }));
        //          ^                         ^
        try equal("cd", 2, segAround(T, "abcd", 4, 2, .{ .slicing_mode = .soft, .even_rshift = true }));
        //           ^                         ^
        try equal("cd", 3, segAround(T, "abcd", 5, 2, .{ .slicing_mode = .soft, .even_rshift = true }));
        //            ^                         ^

        // Even segment length (left shifted)
        try equal("ab", 0, segAround(T, "abcd", 0, 2, .{ .slicing_mode = .soft, .even_rshift = false }));
        //         ^                       ^
        try equal("ab", 1, segAround(T, "abcd", 1, 2, .{ .slicing_mode = .soft, .even_rshift = false }));
        //          ^                       ^
        try equal("bc", 1, segAround(T, "abcd", 2, 2, .{ .slicing_mode = .soft, .even_rshift = false }));
        //          ^                        ^
        try equal("cd", 1, segAround(T, "abcd", 3, 2, .{ .slicing_mode = .soft, .even_rshift = false }));
        //          ^                         ^
        try equal("cd", 2, segAround(T, "abcd", 4, 2, .{ .slicing_mode = .soft, .even_rshift = false }));
        //           ^                         ^
        try equal("cd", 3, segAround(T, "abcd", 5, 2, .{ .slicing_mode = .soft, .even_rshift = false }));
        //            ^                         ^
    }

    // .hard truncation mode
    {
        // Bypass truncation
        try equal("abcd", 3, segAround(T, "abcd", 3, 100, .{ .slicing_mode = .hard }));
        //            ^                         ^

        // Odd segment length
        try equal("ab", 0, segAround(T, "abcd", 0, 3, .{ .slicing_mode = .hard }));
        //         ^                       ^
        try equal("abc", 1, segAround(T, "abcd", 1, 3, .{ .slicing_mode = .hard }));
        //          ^                        ^
        try equal("bcd", 1, segAround(T, "abcd", 2, 3, .{ .slicing_mode = .hard }));
        //          ^                         ^
        try equal("cd", 1, segAround(T, "abcd", 3, 3, .{ .slicing_mode = .hard }));
        //          ^                         ^
        try equal("d", 1, segAround(T, "abcd", 4, 3, .{ .slicing_mode = .hard }));
        //          ^                         ^
        try equal("", 1, segAround(T, "abcd", 5, 3, .{ .slicing_mode = .hard }));
        //          ^                         ^
        try equal("", 2, segAround(T, "abcd", 6, 3, .{ .slicing_mode = .hard }));
        //           ^                         ^

        // Even segment length (right shifted)
        try equal("ab", 0, segAround(T, "abcd", 0, 2, .{ .slicing_mode = .hard, .even_rshift = true }));
        //         ^                       ^
        try equal("bc", 0, segAround(T, "abcd", 1, 2, .{ .slicing_mode = .hard, .even_rshift = true }));
        //         ^                        ^
        try equal("cd", 0, segAround(T, "abcd", 2, 2, .{ .slicing_mode = .hard, .even_rshift = true }));
        //         ^                         ^
        try equal("d", 0, segAround(T, "abcd", 3, 2, .{ .slicing_mode = .hard, .even_rshift = true }));
        //         ^                         ^
        try equal("", 0, segAround(T, "abcd", 4, 2, .{ .slicing_mode = .hard, .even_rshift = true }));
        //         ^                         ^
        try equal("", 1, segAround(T, "abcd", 5, 2, .{ .slicing_mode = .hard, .even_rshift = true }));
        //          ^                         ^
        try equal("", 2, segAround(T, "abcd", 6, 2, .{ .slicing_mode = .hard, .even_rshift = true }));
        //           ^                         ^

        // Even segment length (left shifted)
        try equal("a", 0, segAround(T, "abcd", 0, 2, .{ .slicing_mode = .hard, .even_rshift = false }));
        //         ^                      ^
        try equal("ab", 1, segAround(T, "abcd", 1, 2, .{ .slicing_mode = .hard, .even_rshift = false }));
        //          ^                       ^
        try equal("bc", 1, segAround(T, "abcd", 2, 2, .{ .slicing_mode = .hard, .even_rshift = false }));
        //          ^                        ^
        try equal("cd", 1, segAround(T, "abcd", 3, 2, .{ .slicing_mode = .hard, .even_rshift = false }));
        //          ^                         ^
        try equal("d", 1, segAround(T, "abcd", 4, 2, .{ .slicing_mode = .hard, .even_rshift = false }));
        //          ^                         ^
        try equal("", 1, segAround(T, "abcd", 5, 2, .{ .slicing_mode = .hard, .even_rshift = false }));
        //          ^                         ^
        try equal("", 2, segAround(T, "abcd", 6, 2, .{ .slicing_mode = .hard, .even_rshift = false }));
        //           ^                         ^
    }

    // .hard_flex truncation mode
    {
        // Bypass truncation
        try equal("abcd", 3, segAround(T, "abcd", 3, 100, .{ .slicing_mode = .hard_flex }));
        //            ^                         ^

        // Odd segment length
        try equal("abc", 0, segAround(T, "abcd", 0, 3, .{ .slicing_mode = .hard_flex }));
        //         ^                        ^
        try equal("abc", 1, segAround(T, "abcd", 1, 3, .{ .slicing_mode = .hard_flex }));
        //          ^                        ^
        try equal("bcd", 1, segAround(T, "abcd", 2, 3, .{ .slicing_mode = .hard_flex }));
        //          ^                         ^
        try equal("bcd", 2, segAround(T, "abcd", 3, 3, .{ .slicing_mode = .hard_flex }));
        //           ^                         ^
        try equal("cd", 2, segAround(T, "abcd", 4, 3, .{ .slicing_mode = .hard_flex }));
        //           ^                         ^
        try equal("d", 2, segAround(T, "abcd", 5, 3, .{ .slicing_mode = .hard_flex }));
        //           ^                         ^
        try equal("", 2, segAround(T, "abcd", 6, 3, .{ .slicing_mode = .hard_flex }));
        //           ^                         ^

        // Even segment length (right shifted)
        try equal("ab", 0, segAround(T, "abcd", 0, 2, .{ .slicing_mode = .hard_flex, .even_rshift = true }));
        //         ^                       ^
        try equal("bc", 0, segAround(T, "abcd", 1, 2, .{ .slicing_mode = .hard_flex, .even_rshift = true }));
        //         ^                        ^
        try equal("cd", 0, segAround(T, "abcd", 2, 2, .{ .slicing_mode = .hard_flex, .even_rshift = true }));
        //         ^                         ^
        try equal("cd", 1, segAround(T, "abcd", 3, 2, .{ .slicing_mode = .hard_flex, .even_rshift = true }));
        //          ^                         ^
        try equal("d", 1, segAround(T, "abcd", 4, 2, .{ .slicing_mode = .hard_flex, .even_rshift = true }));
        //          ^                         ^
        try equal("", 1, segAround(T, "abcd", 5, 2, .{ .slicing_mode = .hard_flex, .even_rshift = true }));
        //          ^                         ^
        try equal("", 2, segAround(T, "abcd", 6, 2, .{ .slicing_mode = .hard_flex, .even_rshift = true }));
        //           ^                         ^

        // Even segment length (left shifted)
        try equal("ab", 0, segAround(T, "abcd", 0, 2, .{ .slicing_mode = .hard_flex, .even_rshift = false }));
        //         ^                       ^
        try equal("ab", 1, segAround(T, "abcd", 1, 2, .{ .slicing_mode = .hard_flex, .even_rshift = false }));
        //          ^                       ^
        try equal("bc", 1, segAround(T, "abcd", 2, 2, .{ .slicing_mode = .hard_flex, .even_rshift = false }));
        //          ^                        ^
        try equal("cd", 1, segAround(T, "abcd", 3, 2, .{ .slicing_mode = .hard_flex, .even_rshift = false }));
        //          ^                         ^
        try equal("d", 1, segAround(T, "abcd", 4, 2, .{ .slicing_mode = .hard_flex, .even_rshift = false }));
        //          ^                         ^
        try equal("", 1, segAround(T, "abcd", 5, 2, .{ .slicing_mode = .hard_flex, .even_rshift = false }));
        //          ^                         ^
        try equal("", 2, segAround(T, "abcd", 6, 2, .{ .slicing_mode = .hard_flex, .even_rshift = false }));
        //           ^                         ^
    }
}

/// Checks if the provided segment is a valid sub-slice of the given slice.
pub inline fn isSeg(T: type, slice: []const T, sub: []const T) bool {
    const seg_ptr = @intFromPtr(sub.ptr);
    const slice_ptr = @intFromPtr(slice.ptr);
    return num.numInRangeInc(usize, seg_ptr, slice_ptr, slice_ptr + slice.len) and
        num.numInRangeInc(usize, seg_ptr + sub.len, slice_ptr, slice_ptr + slice.len);
}

test "+isSeg" {
    const equal = std.testing.expectEqual;
    const slice: [11]u8 = "hello_world".*;

    try equal(true, isSeg(u8, slice[0..], slice[0..0]));
    try equal(true, isSeg(u8, slice[0..], slice[11..11]));
    try equal(true, isSeg(u8, slice[0..], slice[0..1]));
    try equal(true, isSeg(u8, slice[0..], slice[3..6]));
    try equal(true, isSeg(u8, slice[0..], slice[10..11]));
    try equal(false, isSeg(u8, slice[0..], "hello_world"));
    // intersecting
    try equal(true, isSeg(u8, slice[0..5], slice[0..5])); // same
    try equal(true, isSeg(u8, slice[0..0], slice[0..0]));
    try equal(true, isSeg(u8, slice[11..11], slice[11..11])); // last zero
    try equal(false, isSeg(u8, slice[0..5], slice[0..6]));
    try equal(false, isSeg(u8, slice[0..5], slice[5..10]));
    try equal(false, isSeg(u8, slice[5..10], slice[0..5]));
    try equal(false, isSeg(u8, slice[0..0], slice[11..11]));
    try equal(false, isSeg(u8, slice[0..6], slice[5..11]));
}

// Moves a valid sub-slice to the beginning of the given slice. The function
// returns an error if slices are from different origins or the sub-slice length
// exceeds 1024. Use `moveSegImpl()` directly to increase the length.
pub fn moveSegLeft(T: type, slice: []T, sub: []T) MoveSegError!void {
    return moveSegImpl(.left, 1024, T, slice, sub);
}

// Moves a valid sub-slice to the end of the given slice. The function returns
// an error if slices are from different origins or the sub-slice length exceeds
// 1024. Use `moveSegImpl()` directly to increase the length.
pub fn moveSegRight(T: type, slice: []T, sub: []T) MoveSegError!void {
    return moveSegImpl(.right, 1024, T, slice, sub);
}

pub const MoveSegError = error{ IsNotSeg, SegIsTooBig };
pub const MoveSegDirection = enum { left, right };

/// Implementation function.
pub fn moveSegImpl(
    comptime dir: MoveSegDirection,
    comptime max_sub_size: usize,
    T: type,
    slice: []T,
    sub: []T,
) MoveSegError!void {
    if (!isSeg(T, slice, sub)) return MoveSegError.IsNotSeg;
    if (sub.len > max_sub_size) return MoveSegError.SegIsTooBig;

    // no need to move if
    if (sub.len == 0 or sub.len == slice.len) return;
    switch (dir) {
        .right => if (indexOfEnd(slice, sub) == slice.len) return,
        .left => if (indexOfStart(slice, sub) == 0) return,
    }

    // copy sub
    var buf: [max_sub_size]T = undefined;
    std.mem.copyForwards(T, &buf, sub);
    const sub_copy = buf[0..sub.len];

    // swap sub-slice with its opposite side
    switch (dir) {
        // [ [sub] [sub_rhs] ]
        // [ [rhs_dst]       ]
        .right => {
            const sub_rhs = slice[indexOfEnd(slice, sub)..];
            const dst_start: usize = indexOfStart(slice, sub);
            const dst_end: usize = dst_start +| sub_rhs.len;
            std.mem.copyForwards(T, slice[dst_start..dst_end], sub_rhs);

            // copy sub to the end of slice
            std.mem.copyForwards(T, slice[slice.len -| sub_copy.len..], sub_copy);
        },
        // [ [sub_lhs] [sub] ]
        // [       [lhs_dst] ]
        .left => {
            const sub_lhs = slice[0..indexOfStart(slice, sub)];
            const dst_end: usize = indexOfEnd(slice, sub);
            const dst_start: usize = dst_end -| sub_lhs.len;
            std.mem.copyBackwards(T, slice[dst_start..dst_end], sub_lhs);

            // copy sub to the beginning of the slice
            std.mem.copyForwards(T, slice[0..sub_copy.len], sub_copy);
        },
    }
}

test "+moveSeg" {
    const t = std.testing;
    const Err = MoveSegError;

    const case = struct {
        pub fn run(
            comptime dir: MoveSegDirection,
            expected_slice: []const u8,
            expected_err: ?MoveSegError,
            slice: []u8,
            sub: []u8,
        ) !void {
            moveSegImpl(dir, 7, u8, slice, sub) catch |err| {
                if (expected_err == null) return err;
                try t.expectEqual(expected_err.?, err);
                return;
            };
            if (expected_err != null) return error.ExpectedError;
            try t.expectEqualStrings(expected_slice, slice);
        }
    }.run;

    // format:
    // try case(|move_dir|, |expected_slice|, |?expected_err|, |orig_slice|, |sub_to_move|)

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
    //               zero length sub-slice
    buf = origin.*;

    try case(.right, origin, null, slice, slice[3..3]);
    //               zero length sub-slice
    buf = origin.*;

    try case(.right, "", Err.IsNotSeg, slice[0..4], slice[3..6]);
    //               not a valid sub-slice
    buf = origin.*;

    var big_buf: [10]u8 = undefined;
    try case(.right, "", Err.SegIsTooBig, &big_buf, big_buf[0..]);
    //               sub slice is to big to copy
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
    //              zero length sub-slice
    buf = origin.*;

    try case(.left, origin, null, slice, slice[3..3]);
    //              zero length sub-slice
    buf = origin.*;

    try case(.left, "", Err.IsNotSeg, slice[0..4], slice[3..6]);
    //              not a valid sub-slice
    buf = origin.*;

    var big_buf2: [10]u8 = undefined;
    try case(.left, "", Err.SegIsTooBig, &big_buf2, big_buf2[0..]);
    //               sub slice is to big to copy
    buf = origin.*;
}
