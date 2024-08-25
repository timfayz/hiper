// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

//! Public API:
//! - indexOfSliceStart
//! - indexOfSliceEnd
//! - reverseSlice
//! - sliceStartSeg
//! - sliceEndSeg
//! - sliceSeg
//! - isSliceSeg

const std = @import("std");
const nm = @import("num.zig");

/// Retrieves the starting position of a slice in source.
pub inline fn indexOfSliceStart(source: anytype, slice: anytype) usize {
    return slice.ptr - source.ptr;
}

/// Retrieves the ending position of a slice in source.
pub inline fn indexOfSliceEnd(source: anytype, slice: anytype) usize {
    return slice.ptr - source.ptr +| slice.len;
}

test "+indexOfSliceStart/End" {
    const t = std.testing;

    const in1 = "";
    try t.expectEqual(0, indexOfSliceEnd(in1, in1[0..0]));
    const in2 = "0123456789";
    try t.expectEqual(0, indexOfSliceEnd(in2, in2[0..0]));
    try t.expectEqual(7, indexOfSliceEnd(in2, in2[3..7]));
    try t.expectEqual(9, indexOfSliceEnd(in2, in2[3..9]));
    try t.expectEqual(10, indexOfSliceEnd(in2, in2[3..10]));

    const in3 = "";
    try t.expectEqual(0, indexOfSliceStart(in3, in3[0..0]));
    const in4 = "0123456789";
    try t.expectEqual(0, indexOfSliceStart(in4, in4[0..0]));
    try t.expectEqual(3, indexOfSliceStart(in4, in4[3..7]));
    try t.expectEqual(9, indexOfSliceStart(in4, in4[9..10]));
    try t.expectEqual(10, indexOfSliceStart(in4, in4[10..10]));
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
    try equal("", sliceStartSeg([]const u8, "ABC", 0));
    try equal("A", sliceStartSeg([]const u8, "ABC", 1));
    try equal("AB", sliceStartSeg([]const u8, "ABC", 2));
    try equal("ABC", sliceStartSeg([]const u8, "ABC", 3));
    try equal("ABC", sliceStartSeg([]const u8, "ABC", 4));
    try equal("ABC", sliceStartSeg([]const u8, "ABC", 100));

    try equal("", sliceEndSeg([]const u8, "", 0));
    try equal("", sliceEndSeg([]const u8, "ABC", 0));
    try equal("C", sliceEndSeg([]const u8, "ABC", 1));
    try equal("BC", sliceEndSeg([]const u8, "ABC", 2));
    try equal("ABC", sliceEndSeg([]const u8, "ABC", 3));
    try equal("ABC", sliceEndSeg([]const u8, "ABC", 4));
    try equal("ABC", sliceEndSeg([]const u8, "ABC", 100));
}

fn SliceSegInfo(T: type) type {
    return struct { slice: T, index_pos: usize };
}

/// Returns a segment of `seg_len` from the slice centered around the `index`
/// and the relative position of the original index within the segment.
pub fn sliceSeg(
    T: type,
    slice: T,
    index: usize,
    seg_len: usize,
    hard_mode: bool,
    comptime opt: struct {
        even_rshift: bool = true,
    },
) SliceSegInfo(T) {
    if (seg_len > slice.len)
        return .{ .slice = slice, .index_pos = index };

    const extra: usize =
        if (seg_len & 1 == 0 and // seg_len is even
        opt.even_rshift and index != 0) 1 else 0;
    const view_start = @min(
        index -| seg_len / 2 + extra,
        if (hard_mode) slice.len else slice.len - seg_len,
    );
    const view_end = @min(view_start + seg_len, slice.len);

    return .{
        .slice = slice[view_start..view_end],
        .index_pos = index - view_start,
    };
}

test "+sliceSeg" {
    const t = std.testing;
    const case = struct {
        fn run(
            line: []const u8,
            hard_mode: bool,
            index: usize,
            expect_line: []const u8,
            comptime args: struct {
                seg_len: usize,
                exp_pos: usize,
                even_rshift: bool = true,
            },
        ) !void {
            const info = sliceSeg([]const u8, line, index, args.seg_len, hard_mode, .{
                .even_rshift = args.even_rshift,
            });
            try t.expectEqualStrings(expect_line, info.slice);
            try t.expectEqual(args.exp_pos, info.index_pos);
        }
    }.run;

    //                 |idx| |exp_line|
    try case("", false, 0, "", .{ .seg_len = 0, .exp_pos = 0 });
    //        ^             ^
    try case("", false, 0, "", .{ .seg_len = 100, .exp_pos = 0 });
    //        ^             ^
    try case("", false, 100, "", .{ .seg_len = 0, .exp_pos = 100 });
    //        ..^             ..^

    // Soft mode
    //
    // Odd segment length
    try case("ABCDE", false, 0, "ABCDE", .{ .seg_len = 100, .exp_pos = 0 });
    //        ^                  ^
    try case("ABCDE", false, 0, "ABC", .{ .seg_len = 3, .exp_pos = 0 });
    //        ^                  ^
    try case("ABCDE", false, 1, "ABC", .{ .seg_len = 3, .exp_pos = 1 });
    //         ^                  ^
    try case("ABCDE", false, 2, "BCD", .{ .seg_len = 3, .exp_pos = 1 });
    //          ^                 ^
    try case("ABCDE", false, 3, "CDE", .{ .seg_len = 3, .exp_pos = 1 });
    //           ^                ^
    try case("ABCDE", false, 4, "CDE", .{ .seg_len = 3, .exp_pos = 2 });
    //            ^                ^
    try case("ABCDE", false, 5, "CDE", .{ .seg_len = 3, .exp_pos = 3 });
    //             ^                ^
    try case("ABCDE", false, 6, "CDE", .{ .seg_len = 3, .exp_pos = 4 });
    //              ^                ^

    // Even segment length
    try case("ABCD", false, 0, "AB", .{ .seg_len = 2, .exp_pos = 0 });
    //        ^                 ^
    try case("ABCD", false, 1, "BC", .{ .seg_len = 2, .exp_pos = 0 });
    //         ^                ^
    try case("ABCD", false, 2, "CD", .{ .seg_len = 2, .exp_pos = 0 });
    //          ^                ^
    try case("ABCD", false, 3, "CD", .{ .seg_len = 2, .exp_pos = 1 });
    //           ^               ^
    try case("ABCD", false, 4, "CD", .{ .seg_len = 2, .exp_pos = 2 });
    //            ^               ^
    try case("ABCD", false, 5, "CD", .{ .seg_len = 2, .exp_pos = 3 });
    //             ^               ^

    // Even segment length (left shift)
    try case("ABCD", false, 0, "AB", .{ .seg_len = 2, .exp_pos = 0, .even_rshift = false });
    //        ^                 ^
    try case("ABCD", false, 1, "AB", .{ .seg_len = 2, .exp_pos = 1, .even_rshift = false });
    //         ^                 ^
    try case("ABCD", false, 2, "BC", .{ .seg_len = 2, .exp_pos = 1, .even_rshift = false });
    //          ^                ^
    try case("ABCD", false, 3, "CD", .{ .seg_len = 2, .exp_pos = 1, .even_rshift = false });
    //           ^               ^
    try case("ABCD", false, 4, "CD", .{ .seg_len = 2, .exp_pos = 2, .even_rshift = false });
    //            ^               ^
    try case("ABCD", false, 5, "CD", .{ .seg_len = 2, .exp_pos = 3, .even_rshift = false });
    //             ^               ^

    // Hard mode
    //
    try case("ABCDE", true, 0, "ABCDE", .{ .seg_len = 100, .exp_pos = 0 });
    //        ^                  ^
    try case("ABCDE", true, 0, "ABC", .{ .seg_len = 3, .exp_pos = 0 });
    //        ^                  ^
    try case("ABCDE", true, 1, "ABC", .{ .seg_len = 3, .exp_pos = 1 });
    //         ^                  ^
    try case("ABCDE", true, 2, "BCD", .{ .seg_len = 3, .exp_pos = 1 });
    //          ^                 ^
    try case("ABCDE", true, 3, "CDE", .{ .seg_len = 3, .exp_pos = 1 });
    //           ^                ^
    try case("ABCDE", true, 4, "DE", .{ .seg_len = 3, .exp_pos = 1 });
    //            ^               ^
    try case("ABCDE", true, 5, "E", .{ .seg_len = 3, .exp_pos = 1 });
    //             ^              ^
    try case("ABCDE", true, 6, "", .{ .seg_len = 3, .exp_pos = 1 });
    //              ^             ^
    try case("ABCDE", true, 7, "", .{ .seg_len = 3, .exp_pos = 2 });
    //               ^             ^

    // Even segment length
    try case("ABCD", true, 0, "AB", .{ .seg_len = 2, .exp_pos = 0 });
    //        ^                 ^
    try case("ABCD", true, 1, "BC", .{ .seg_len = 2, .exp_pos = 0 });
    //         ^                ^
    try case("ABCD", true, 2, "CD", .{ .seg_len = 2, .exp_pos = 0 });
    //          ^                ^
    try case("ABCD", true, 3, "D", .{ .seg_len = 2, .exp_pos = 0 });
    //           ^              ^
    try case("ABCD", true, 4, "", .{ .seg_len = 2, .exp_pos = 0 });
    //            ^             ^
    try case("ABCD", true, 5, "", .{ .seg_len = 2, .exp_pos = 1 });
    //             ^             ^

    // Even segment length (left shift)
    try case("ABCD", true, 0, "AB", .{ .seg_len = 2, .exp_pos = 0, .even_rshift = false });
    //        ^                 ^
    try case("ABCD", true, 1, "AB", .{ .seg_len = 2, .exp_pos = 1, .even_rshift = false });
    //         ^                 ^
    try case("ABCD", true, 2, "BC", .{ .seg_len = 2, .exp_pos = 1, .even_rshift = false });
    //          ^                ^
    try case("ABCD", true, 3, "CD", .{ .seg_len = 2, .exp_pos = 1, .even_rshift = false });
    //           ^               ^
    try case("ABCD", true, 4, "D", .{ .seg_len = 2, .exp_pos = 1, .even_rshift = false });
    //            ^              ^
    try case("ABCD", true, 5, "", .{ .seg_len = 2, .exp_pos = 1, .even_rshift = false });
    //             ^             ^

}

/// Checks if the provided segment is a valid sub-slice of the given slice.
pub inline fn isSliceSeg(T: type, slice: []const T, seg: []const T) bool {
    const seg_ptr = @intFromPtr(seg.ptr);
    const slice_ptr = @intFromPtr(slice.ptr);
    return nm.numInRangeInc(usize, seg_ptr, slice_ptr, slice_ptr + slice.len) and
        nm.numInRangeInc(usize, seg_ptr + seg.len, slice_ptr, slice_ptr + slice.len);
}

test "+sliceSegIn" {
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

