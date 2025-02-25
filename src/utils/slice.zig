// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

//! Public API:
//! - reverse()
//! - reversed()
//! - common()
//! - overlap()
//! - overlaps()
//! - contains()
//! - extend()
//! - joint()
//! - join()
//! - startIndex()
//! - endIndex()
//! - bound()
//! - first()
//! - last()
//! - trunc()
//! - truncIndices()
//! - move()

const std = @import("std");
const num = @import("num.zig");
const Range = @import("span.zig").Range;
const Dir = @import("span.zig").Dir;
const err = @import("err.zig");
const meta = @import("meta.zig");
const mem = std.mem;
const t = std.testing;

/// Reverses slice items in-place.
pub fn reverse(slice: anytype) void {
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

/// Returns the slice with items reversed in-place.
pub fn reversed(T: type, slice: T) T {
    reverse(slice);
    return slice;
}

test reverse {
    const equal = struct {
        pub fn run(input: []const u8, expect: []const u8) !void {
            var buf: [32]u8 = undefined;
            for (input, 0..) |byte, i| buf[i] = byte;
            try t.expectEqualStrings(expect, reversed([]u8, buf[0..input.len]));
        }
    }.run;

    try equal("", "");
    try equal("1", "1");
    try equal("12", "21");
    try equal("123", "321");
    try equal("1234", "4321");
    try equal("12345", "54321");
}

/// Returns the shared sub-slice of two slices.
///
/// ```txt
/// [slice1 ] [ slice2]
/// [                 ]    (common segment)
///
/// [slice1   ]
///         [   slice2]
/// [                 ]    (common segment)
/// ```
pub fn common(T: type, slice1: T, slice2: T) T {
    const start = if (@intFromPtr(slice1.ptr) < @intFromPtr(slice2.ptr)) slice1.ptr else slice2.ptr;
    const end1 = slice1.ptr + slice1.len;
    const end2 = slice2.ptr + slice2.len;
    const end = if (@intFromPtr(end1) > @intFromPtr(end2)) end1 else end2;
    return start[0 .. end - start];
}

test common {
    const input = "0123";

    try t.expectEqualStrings("0123", common([]const u8, input[0..0], input[4..4])); // zero slices
    try t.expectEqualStrings("0123", common([]const u8, input[4..4], input[0..0])); // reversed order
    try t.expectEqualStrings("0123", common([]const u8, input[0..2], input[2..4])); // normal slices
    try t.expectEqualStrings("0123", common([]const u8, input[2..4], input[0..2])); // reversed order
    try t.expectEqualStrings("0123", common([]const u8, input[0..3], input[1..4])); // intersected slices
    try t.expectEqualStrings("0123", common([]const u8, input[0..4], input[0..4])); // same slices
}

/// Returns the intersection of two slices.
///
/// ```txt
/// [slice1 ] [ slice2]
///         null           (overlap)
///
/// [slice1   ]
///         [   slice2]
///         [ ]            (overlap)
/// ```
fn overlap(T: type, slice1: T, slice2: T) ?T {
    const start = if (@intFromPtr(slice1.ptr) > @intFromPtr(slice2.ptr)) slice1.ptr else slice2.ptr;
    const end1 = slice1.ptr + slice1.len;
    const end2 = slice2.ptr + slice2.len;
    const end = if (@intFromPtr(end1) < @intFromPtr(end2)) end1 else end2;
    return if (@intFromPtr(start) < @intFromPtr(end))
        start[0 .. end - start]
    else
        null;
}

test overlap {
    const arr = [4]u64{ 0, 1, 2, 3 };

    try t.expectEqual(null, overlap([]const u64, arr[0..0], arr[4..4]));
    try t.expectEqual(null, overlap([]const u64, arr[0..2], arr[2..4]));
    try t.expectEqual(null, overlap([]const u64, arr[1..1], arr[0..4]));
    try t.expectEqualSlices(u64, arr[1..3], overlap([]const u64, arr[0..3], arr[1..4]).?);
    try t.expectEqualSlices(u64, arr[1..3], overlap([]const u64, arr[1..4], arr[0..3]).?);
    try t.expectEqualSlices(u64, arr[0..], overlap([]const u64, arr[0..4], arr[0..4]).?);
}

/// Checks if the provided slices overlap.
pub fn overlaps(slice1: anytype, slice2: anytype) bool {
    const start = if (@intFromPtr(slice1.ptr) > @intFromPtr(slice2.ptr)) slice1.ptr else slice2.ptr;
    const end1 = slice1.ptr + slice1.len;
    const end2 = slice2.ptr + slice2.len;
    const end = if (@intFromPtr(end1) < @intFromPtr(end2)) end1 else end2;
    return if (@intFromPtr(start) < @intFromPtr(end)) true else false;
}

test overlaps {
    const input = "0123456789";

    try t.expectEqual(false, overlaps(input[0..0], input[0..]));
    try t.expectEqual(false, overlaps(input[0..3], input[3..]));
    try t.expectEqual(true, overlaps(input[0..4], input[3..]));
    try t.expectEqual(true, overlaps(input[0..], input[0..]));
}

/// Checks if the provided segment is a valid sub-slice.
pub fn contains(base: anytype, seg: anytype) bool {
    return @intFromPtr(base.ptr) <= @intFromPtr(seg.ptr) and
        @intFromPtr(base.ptr + base.len) >= @intFromPtr(seg.ptr + seg.len);
}

test contains {
    const input: [11]u8 = "hello_world".*;

    try t.expectEqual(true, contains(input[0..], input[0..0]));
    try t.expectEqual(true, contains(input[0..], input[0..1]));
    try t.expectEqual(true, contains(input[0..], input[3..6]));
    try t.expectEqual(true, contains(input[0..], input[10..11]));
    try t.expectEqual(true, contains(input[0..], input[11..11]));
    try t.expectEqual(false, contains(input[0..], "hello_world"));

    // intersecting
    try t.expectEqual(true, contains(input[0..5], input[0..5]));
    try t.expectEqual(true, contains(input[0..0], input[0..0]));
    try t.expectEqual(true, contains(input[11..11], input[11..11]));
    try t.expectEqual(false, contains(input[0..5], input[0..]));
    try t.expectEqual(false, contains(input[0..5], input[5..]));
    try t.expectEqual(false, contains(input[0..6], input[5..]));
    try t.expectEqual(false, contains(input[5..], input[0..5]));
}

/// Extends slice to the right or left by the given size (no safety checks).
pub fn extend(comptime dir: Dir, T: type, slice: T, size: usize) T {
    return if (dir == .right)
        slice.ptr[0 .. slice.len + size]
    else
        (slice.ptr - size)[0 .. slice.len + size];
}

test extend {
    const input = "0123456789";

    try t.expectEqualStrings("2345", extend(.right, []const u8, input[2..4], 2));
    try t.expectEqualStrings("2345", extend(.left, []const u8, input[4..6], 2));
}

/// Checks if two slices are contiguous in memory (in left-to-right order).
pub fn joint(slice1: anytype, slice2: anytype) bool {
    return @intFromPtr(slice1.ptr + slice1.len) == @intFromPtr(slice2.ptr);
}

test joint {
    const input = "0123456789";

    try t.expectEqual(true, joint(input[1..1], input[1..1]));
    try t.expectEqual(true, joint(input[1..1], input[1..2]));
    try t.expectEqual(true, joint(input[0..3], input[3..6]));
    try t.expectEqual(false, joint(input[0..2], input[3..6]));
    try t.expectEqual(false, joint(input[3..6], input[0..3]));
}

/// Extends slice to the right or left by the elements of extension (no safety checks).
pub fn join(comptime dir: Dir, T: type, base: T, extension: T) err.InvalidLayout!T {
    if (dir == .right) {
        if (!joint(base, extension)) return error.InvalidLayout;
        return base.ptr[0 .. base.len + extension.len];
    } else {
        if (!joint(extension, base)) return error.InvalidLayout;
        return extension.ptr[0 .. extension.len + base.len];
    }
}

test join {
    const input = "0123456789";

    try t.expectEqual(error.InvalidLayout, join(.right, []const u8, input[1..3], input[4..6]));
    try t.expectEqual(error.InvalidLayout, join(.left, []const u8, input[1..3], input[4..6]));
    try t.expectEqual(input[1..6], try join(.right, []const u8, input[1..3], input[3..6]));
    try t.expectEqual(input[1..6], try join(.left, []const u8, input[3..6], input[1..3]));
    try t.expectEqual(input[1..1], try join(.right, []const u8, input[1..1], input[1..1]));
    try t.expectEqual(input[1..1], try join(.left, []const u8, input[1..1], input[1..1]));
}

/// Retrieves the index of the segment start within the slice.
pub fn startIndex(base: anytype, seg: anytype) usize {
    return seg.ptr - base.ptr;
}

test startIndex {
    const empty = "";
    const input = "0123456789";

    try t.expectEqual(0, startIndex(empty, empty[0..0]));
    try t.expectEqual(0, startIndex(input, input[0..0]));
    try t.expectEqual(3, startIndex(input, input[3..7]));
    try t.expectEqual(3, startIndex(input[3..], input[6..7]));
    try t.expectEqual(10, startIndex(input, input[10..10]));
}

/// Retrieves the index of the segment end within the slice.
pub fn endIndex(base: anytype, seg: anytype) usize {
    return (seg.ptr - base.ptr) +| seg.len;
}

test endIndex {
    const empty = "";
    const input = "0123456789";

    try t.expectEqual(0, endIndex(empty, empty[0..0]));
    try t.expectEqual(0, endIndex(input, input[0..0]));
    try t.expectEqual(7, endIndex(input, input[3..7]));
    try t.expectEqual(9, endIndex(input, input[3..9]));
    try t.expectEqual(10, endIndex(input, input[3..10]));
}

/// Returns `[start..end]` slice segment bounded to the `slice.len`.
pub fn bound(T: type, slice: T, start: usize, end: usize) T {
    return slice[@min(start, slice.len)..@min(end, slice.len)];
}

test bound {
    try t.expectEqualStrings("", bound([]const u8, "0123", 0, 0));
    try t.expectEqualStrings("", bound([]const u8, "0123", 100, 100));
    try t.expectEqualStrings("0123", bound([]const u8, "0123", 0, 4));
    try t.expectEqualStrings("0", bound([]const u8, "0123", 0, 1));
    try t.expectEqualStrings("12", bound([]const u8, "0123", 1, 3));
    try t.expectEqualStrings("3", bound([]const u8, "0123", 3, 4));
}

/// Returns a slice of the first `len` elements, bounded by the slice length.
pub fn first(T: type, slice: T, len: usize) T {
    return slice[0..@min(len, slice.len)];
}

test first {
    try t.expectEqualStrings("", first([]const u8, "0123", 0));
    try t.expectEqualStrings("01", first([]const u8, "0123", 2));
    try t.expectEqualStrings("0123", first([]const u8, "0123", 10));
}

/// Returns a slice of the last `len` elements, bounded by the slice length.
pub fn last(T: type, slice: T, len: usize) T {
    return slice[slice.len -| len..slice.len];
}

test last {
    try t.expectEqualStrings("", last([]const u8, "0123", 0));
    try t.expectEqualStrings("23", last([]const u8, "0123", 2));
    try t.expectEqualStrings("0123", last([]const u8, "0123", 10));
}

/// Truncates slice at the specified index and view range.
pub fn trunc(
    T: type,
    slice: T,
    index: anytype,
    comptime view_range: Range.View,
    comptime trunc_mode: Range.TruncMode,
    comptime opt: Range.View.Options,
) T {
    return truncIndices(slice, index, view_range, trunc_mode, opt).slice(T, slice);
}

test trunc {
    // [around index]
    try t.expectEqualStrings("", trunc([]const u8, "01234567", 8, .{ .around = 0 }, .hard, .{}));
    //                                                      ^
    try t.expectEqualStrings("4", trunc([]const u8, "01234567", 4, .{ .around = 0 }, .hard, .{}));
    //                                                   ^
    try t.expectEqualStrings("345", trunc([]const u8, "01234567", 4, .{ .around = 2 }, .hard, .{}));
    //                                                    ~^~
    try t.expectEqualStrings("234", trunc([]const u8, "01234567", 4, .{ .left = 2 }, .hard, .{}));
    //                                                   ~~^
    try t.expectEqualStrings("456", trunc([]const u8, "01234567", 4, .{ .right = 2 }, .hard, .{}));
    //                                                     ^~~

    // [relative range]
    try t.expectEqualStrings("3456", trunc([]const u8, "0123456789", .{ 4, 4 }, .{ .around = 3 }, .hard, .{}));
    //                                                     ~^~~
    try t.expectEqualStrings("345678", trunc([]const u8, "0123456789", .{ 4, 6 }, .{ .around = 3 }, .hard, .{}));
    //                                                       ~^^^~~
    try t.expectEqualStrings("23456", trunc([]const u8, "0123456789", .{ 4, 6 }, .{ .left = 2 }, .hard, .{}));
    //                                                     ~~^^^
    try t.expectEqualStrings("45678", trunc([]const u8, "0123456789", .{ 4, 6 }, .{ .right = 2 }, .hard, .{}));
    //                                                       ^^^~~
}

/// Retrieves slice indices truncated at the specified index and view range.
pub fn truncIndices(
    slice: anytype,
    index: anytype,
    comptime view_range: Range.View,
    comptime trunc_mode: Range.TruncMode,
    comptime opt: Range.View.Options,
) Range {
    if (meta.isNum(index)) {
        var pair = view_range.toPairAddExtra(1, .right, opt);
        return pair.toRangeWithin(index, Range.initFromSlice(slice), trunc_mode);
    } else if (meta.isTuple(index) and index.len == 2) {
        const start, const end = num.orderPairAsc(index[0], index[1]);
        const pair = view_range.toPairAddExtra(end - start +| 1, .right, opt);
        return pair.toRangeWithin(start, Range.initFromSlice(slice), trunc_mode);
    }
}

test truncIndices {
    // [around index]
    try t.expectEqualDeep(Range.init(3, 6), truncIndices("01234567", 4, .{ .around = 2 }, .hard, .{}));
    //                                                       ~^~
    try t.expectEqualDeep(Range.init(2, 5), truncIndices("01234567", 4, .{ .left = 2 }, .hard, .{}));
    //                                                      ~~^
    try t.expectEqualDeep(Range.init(4, 7), truncIndices("01234567", 4, .{ .right = 2 }, .hard, .{}));
    //                                                        ^~~

    // [around range]
    try t.expectEqualDeep(Range.init(3, 9), truncIndices("0123456789", .{ 4, 6 }, .{ .around = 3 }, .hard, .{}));
    //                                                       ~^^^~~
    try t.expectEqualDeep(Range.init(2, 7), truncIndices("0123456789", .{ 4, 6 }, .{ .left = 2 }, .hard, .{}));
    //                                                      ~~^^^
    try t.expectEqualDeep(Range.init(4, 9), truncIndices("0123456789", .{ 4, 6 }, .{ .right = 2 }, .hard, .{}));
    //                                                        ^^^~~
}

/// Moves a valid segment to the start or end of the slice, returning an error
/// if it’s from a different origin or exceeds `buf_size`.
pub fn move(
    comptime dir: Dir,
    comptime buf_size: usize,
    T: type,
    base: []T,
    seg: []const T,
) (err.InsufficientSpace || err.InvalidOrigin)!void {
    if (!contains(base, seg)) return error.InvalidOrigin;
    if (seg.len > buf_size) return error.InsufficientSpace;
    if (seg.len == 0 or seg.len == base.len) return;
    switch (dir) {
        .right => if (endIndex(base, seg) == base.len) return,
        .left => if (startIndex(base, seg) == 0) return,
    }

    // make segment copy
    var buf: [buf_size]T = undefined;
    const seg_copy = buf[0..seg.len];
    mem.copyForwards(T, seg_copy, seg);

    // swap segment
    switch (dir) {
        // [ [seg][seg_rhs] ] (step 0)
        // [ [seg_rhs]..... ] (step 1)
        // [ [seg_rhs][seg] ] (step 2)
        .right => {
            const seg_rhs = base[endIndex(base, seg)..]; // step 0
            const start: usize = startIndex(base, seg);
            const end: usize = start +| seg_rhs.len;
            mem.copyForwards(T, base[start..end], seg_rhs); // step 1
            mem.copyForwards(T, base[base.len -| seg_copy.len..], seg_copy); // step 2
        },
        // [ [seg_lhs][seg] ] (step 0)
        // [ .....[seg_lhs] ] (step 1)
        // [ [seg][seg_lhs] ] (step 2)
        .left => {
            const seg_lhs = base[0..startIndex(base, seg)]; // step 0
            const end: usize = endIndex(base, seg);
            const start: usize = end -| seg_lhs.len;
            mem.copyBackwards(T, base[start..end], seg_lhs); // step 1
            mem.copyForwards(T, base[0..seg_copy.len], seg_copy); // step 2
        },
    }
}

test move {
    const origin = "0123456";
    var buf: [7]u8 = origin.*;
    const slice = buf[0..];

    // [.right mode]

    try move(.right, 512, u8, slice, slice[0..3]);
    try t.expectEqualStrings("3456012", slice);
    //                            ---
    buf = origin.*;

    try move(.right, 512, u8, slice, slice[3..6]);
    try t.expectEqualStrings("0126345", slice);
    //                            ---
    buf = origin.*;

    try move(.right, 512, u8, slice, slice); // move is not required
    try t.expectEqualStrings("0123456", slice);
    buf = origin.*;

    try move(.right, 512, u8, slice, slice[4..]); // move is not required
    try t.expectEqualStrings("0123456", slice);
    buf = origin.*;

    try move(.right, 512, u8, slice, slice[7..]); // zero length segment
    try t.expectEqualStrings("0123456", slice);
    buf = origin.*;

    try move(.right, 512, u8, slice, slice[3..3]); // zero length segment
    try t.expectEqualStrings("0123456", slice);
    buf = origin.*;

    try t.expectError(error.InvalidOrigin, move(.right, 512, u8, slice[0..4], slice[3..6]));
    try t.expectError(error.InsufficientSpace, move(.right, 1, u8, slice, slice[1..]));

    // [.left mode]

    try move(.left, 512, u8, slice, slice[1..]);
    try t.expectEqualStrings("1234560", slice);
    //                        ------
    buf = origin.*;

    try move(.left, 512, u8, slice, slice[4..]);
    try t.expectEqualStrings("4560123", slice);
    //                        ---
    buf = origin.*;

    try move(.left, 512, u8, slice, slice[6..]);
    try t.expectEqualStrings("6012345", slice);
    //                        -
    buf = origin.*;

    try move(.left, 512, u8, slice, slice); // move is not required
    try t.expectEqualStrings("0123456", slice);

    try move(.left, 512, u8, slice, slice[0..3]); // move is not required
    try t.expectEqualStrings("0123456", slice);

    try move(.left, 512, u8, slice, slice[7..]); // zero length segment
    try t.expectEqualStrings("0123456", slice);

    try move(.left, 512, u8, slice, slice[3..3]); // zero length segment
    try t.expectEqualStrings("0123456", slice);

    try t.expectError(error.InvalidOrigin, move(.left, 512, u8, slice[0..4], slice[3..6]));
    try t.expectError(error.InsufficientSpace, move(.left, 1, u8, slice, slice[1..]));
}

/// Swaps two contiguous segments of a slice, returning an error if they are
/// from different origins, non-contiguous, or exceed `buf_size`.
pub fn swap(
    comptime buf_size: usize,
    T: type,
    left: T,
    right: T,
) !void {
    const base = try join(.right, T, left, right);
    try move(.left, buf_size, u8, base, right);
}

test swap {
    const template = "01234567";
    var buf: [8]u8 = template.*;
    try swap(64, []u8, buf[0..4], buf[4..]);
    try std.testing.expectEqualStrings("45670123", buf[0..]);
}
