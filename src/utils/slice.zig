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
//! - continuous()
//! - join()
//! - startIndex()
//! - endIndex()
//! - bound()
//! - trunc()
//! - truncIndices()
//! - move()

const std = @import("std");
const num = @import("num.zig");
const range = @import("range.zig");
const err = @import("err.zig");
const meta = @import("meta.zig");
const mem = std.mem;

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
            try std.testing.expectEqualStrings(expect, reversed([]u8, buf[0..input.len]));
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
    const equal = std.testing.expectEqualStrings;
    const input = "0123";

    try equal("0123", common([]const u8, input[0..0], input[4..4])); // zero slices
    try equal("0123", common([]const u8, input[4..4], input[0..0])); // reversed order
    try equal("0123", common([]const u8, input[0..2], input[2..4])); // normal slices
    try equal("0123", common([]const u8, input[2..4], input[0..2])); // reversed order
    try equal("0123", common([]const u8, input[0..3], input[1..4])); // intersected slices
    try equal("0123", common([]const u8, input[0..4], input[0..4])); // same slices
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
    const equal = std.testing.expectEqual;
    const equalSlices = std.testing.expectEqualSlices;

    const arr = [4]u64{ 0, 1, 2, 3 };
    try equal(null, overlap([]const u64, arr[0..0], arr[4..4]));
    try equal(null, overlap([]const u64, arr[0..2], arr[2..4]));
    try equal(null, overlap([]const u64, arr[1..1], arr[0..4]));
    try equalSlices(u64, arr[1..3], overlap([]const u64, arr[0..3], arr[1..4]).?);
    try equalSlices(u64, arr[1..3], overlap([]const u64, arr[1..4], arr[0..3]).?);
    try equalSlices(u64, arr[0..], overlap([]const u64, arr[0..4], arr[0..4]).?);
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
    const equal = std.testing.expectEqual;
    const input = "0123456789";

    try equal(false, overlaps(input[0..0], input[0..]));
    try equal(false, overlaps(input[0..3], input[3..]));
    try equal(true, overlaps(input[0..4], input[3..]));
    try equal(true, overlaps(input[0..], input[0..]));
}

/// Checks if the provided segment is a valid sub-slice.
pub fn contains(base: anytype, seg: anytype) bool {
    return @intFromPtr(base.ptr) <= @intFromPtr(seg.ptr) and
        @intFromPtr(base.ptr + base.len) >= @intFromPtr(seg.ptr + seg.len);
}

test contains {
    const equal = std.testing.expectEqual;
    const input: [11]u8 = "hello_world".*;

    try equal(true, contains(input[0..], input[0..0]));
    try equal(true, contains(input[0..], input[0..1]));
    try equal(true, contains(input[0..], input[3..6]));
    try equal(true, contains(input[0..], input[10..11]));
    try equal(true, contains(input[0..], input[11..11]));
    try equal(false, contains(input[0..], "hello_world"));

    // intersecting
    try equal(true, contains(input[0..5], input[0..5]));
    try equal(true, contains(input[0..0], input[0..0]));
    try equal(true, contains(input[11..11], input[11..11]));
    try equal(false, contains(input[0..5], input[0..]));
    try equal(false, contains(input[0..5], input[5..]));
    try equal(false, contains(input[0..6], input[5..]));
    try equal(false, contains(input[5..], input[0..5]));
}

/// Extends slice to the right or left by the given size (no safety checks).
pub fn extend(comptime dir: range.Dir, T: type, slice: T, size: usize) T {
    return if (dir == .right)
        slice.ptr[0 .. slice.len + size]
    else
        (slice.ptr - size)[0 .. slice.len + size];
}

test extend {
    const equal = std.testing.expectEqualStrings;

    const input = "0123456789";
    try equal("2345", extend(.right, []const u8, input[2..4], 2));
    try equal("2345", extend(.left, []const u8, input[4..6], 2));
}

/// Checks if two slices are contiguous in memory (in left-to-right order).
pub fn continuous(slice1: anytype, slice2: anytype) bool {
    return @intFromPtr(slice1.ptr + slice1.len) == @intFromPtr(slice2.ptr);
}

test continuous {
    const equal = std.testing.expectEqual;

    const input = "0123456789";
    try equal(true, continuous(input[1..1], input[1..1]));
    try equal(true, continuous(input[1..1], input[1..2]));
    try equal(true, continuous(input[0..3], input[3..6]));
    try equal(false, continuous(input[0..2], input[3..6]));
    try equal(false, continuous(input[3..6], input[0..3]));
}

/// Extends slice to the right or left by the elements of extension (no safety checks).
pub fn join(comptime dir: range.Dir, T: type, base: T, extension: T) err.InvalidLayout!T {
    if (dir == .right) {
        if (!continuous(base, extension)) return error.InvalidLayout;
        return base.ptr[0 .. base.len + extension.len];
    } else {
        if (!continuous(extension, base)) return error.InvalidLayout;
        return extension.ptr[0 .. extension.len + base.len];
    }
}

test join {
    const equal = std.testing.expectEqual;

    const input = "0123456789";
    try equal(error.InvalidLayout, join(.right, []const u8, input[1..3], input[4..6]));
    try equal(error.InvalidLayout, join(.left, []const u8, input[1..3], input[4..6]));
    try equal(input[1..6], try join(.right, []const u8, input[1..3], input[3..6]));
    try equal(input[1..6], try join(.left, []const u8, input[3..6], input[1..3]));
    try equal(input[1..1], try join(.right, []const u8, input[1..1], input[1..1]));
    try equal(input[1..1], try join(.left, []const u8, input[1..1], input[1..1]));
}

/// Retrieves the index of the segment start within the slice.
pub fn startIndex(base: anytype, seg: anytype) usize {
    return seg.ptr - base.ptr;
}

test startIndex {
    const equal = std.testing.expectEqual;

    const empty = "";
    const input = "0123456789";

    try equal(0, startIndex(empty, empty[0..0]));
    try equal(0, startIndex(input, input[0..0]));
    try equal(3, startIndex(input, input[3..7]));
    try equal(3, startIndex(input[3..], input[6..7]));
    try equal(10, startIndex(input, input[10..10]));
}

/// Retrieves the index of the segment end within the slice.
pub fn endIndex(base: anytype, seg: anytype) usize {
    return (seg.ptr - base.ptr) +| seg.len;
}

test endIndex {
    const equal = std.testing.expectEqual;

    const empty = "";
    const input = "0123456789";

    try equal(0, endIndex(empty, empty[0..0]));
    try equal(0, endIndex(input, input[0..0]));
    try equal(7, endIndex(input, input[3..7]));
    try equal(9, endIndex(input, input[3..9]));
    try equal(10, endIndex(input, input[3..10]));
}

/// Returns `[start..end]` slice segment bounded to the `slice.len`.
pub fn bound(T: type, slice: T, start: usize, end: usize) T {
    return slice[@min(start, slice.len)..@min(end, slice.len)];
}

test bound {
    const equal = std.testing.expectEqualStrings;

    try equal("", bound([]const u8, "0123", 0, 0));
    try equal("", bound([]const u8, "0123", 100, 100));
    try equal("0123", bound([]const u8, "0123", 0, 4));
    try equal("0", bound([]const u8, "0123", 0, 1));
    try equal("12", bound([]const u8, "0123", 1, 3));
    try equal("3", bound([]const u8, "0123", 3, 4));
}

/// Truncates slice at the specified index and view range.
pub fn trunc(
    T: type,
    slice: T,
    index: anytype,
    comptime view_range: range.View,
    comptime trunc_mode: range.TruncMode,
    comptime opt: range.View.Options,
) T {
    return truncIndices(slice, index, view_range, trunc_mode, opt).slice(T, slice);
}

test trunc {
    const equal = std.testing.expectEqualStrings;

    // [relative index]
    try equal("", trunc([]const u8, "01234567", 4, .{ .around = 0 }, .hard, .{}));
    //                                   ^
    try equal("345", trunc([]const u8, "01234567", 4, .{ .around = 3 }, .hard, .{}));
    //                                     ~^~
    try equal("234", trunc([]const u8, "01234567", 4, .{ .left = 3 }, .hard, .{}));
    //                                    ~~^
    try equal("456", trunc([]const u8, "01234567", 4, .{ .right = 3 }, .hard, .{}));
    //                                      ^~~

    // [relative range]
    try equal("345678", trunc([]const u8, "0123456789", .{ 4, 6 }, .{ .around = 3 }, .hard, .{}));
    //                                        ~^^^~~
    try equal("23456", trunc([]const u8, "0123456789", .{ 4, 6 }, .{ .left = 2 }, .hard, .{}));
    //                                      ~~^^^
    try equal("45678", trunc([]const u8, "0123456789", .{ 4, 6 }, .{ .right = 2 }, .hard, .{}));
    //                                        ^^^~~
}

/// Retrieves slice indices truncated at the specified index and view range.
pub fn truncIndices(
    slice: anytype,
    index: anytype,
    comptime view_range: range.View,
    comptime trunc_mode: range.TruncMode,
    comptime opt: range.View.Options,
) range.Range {
    if (meta.isNum(index)) {
        var pair = view_range.toPair(opt);
        if (view_range == .left and pair.left > 0) pair.shift(.right, 1);
        return pair.toRange(index, range.initFromSlice(slice), trunc_mode);
    } else if (meta.isTuple(index) and index.len == 2) {
        const start, const end = num.orderPairAsc(index[0], index[1]);
        const pair = view_range.toPairAddExtra(end - start +| 1, .right, opt);
        return pair.toRange(start, range.initFromSlice(slice), trunc_mode);
    }
}

test truncIndices {
    const equal = std.testing.expectEqualDeep;

    // [around index]
    try equal(range.init(3, 6), truncIndices("01234567", 4, .{ .around = 3 }, .hard, .{}));
    //                                           ~^~
    try equal(range.init(2, 5), truncIndices("01234567", 4, .{ .left = 3 }, .hard, .{}));
    //                                          ~~^
    try equal(range.init(4, 7), truncIndices("01234567", 4, .{ .right = 3 }, .hard, .{}));
    //                                            ^~~

    // [around range]
    try equal(range.init(3, 9), truncIndices("0123456789", .{ 4, 6 }, .{ .around = 3 }, .hard, .{}));
    //                                           ~^^^~~
    try equal(range.init(2, 7), truncIndices("0123456789", .{ 4, 6 }, .{ .left = 2 }, .hard, .{}));
    //                                          ~~^^^
    try equal(range.init(4, 9), truncIndices("0123456789", .{ 4, 6 }, .{ .right = 2 }, .hard, .{}));
    //                                            ^^^~~
}

/// Moves a valid segment to the start or end of the given slice. Returns an
/// error if the segment comes from a different origin or its length exceeds
/// stack-allocated `buf_size`.
pub fn move(
    comptime dir: range.Dir,
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
    const equal = std.testing.expectEqualStrings;
    const equalErr = std.testing.expectError;

    const origin = "0123456";
    var buf: [7]u8 = origin.*;
    const slice = buf[0..];

    // [.right mode]

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

    try equalErr(error.InvalidOrigin, move(.right, 512, u8, slice[0..4], slice[3..6]));
    try equalErr(error.InsufficientSpace, move(.right, 1, u8, slice, slice[1..]));

    // [.left mode]

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

    try equalErr(error.InvalidOrigin, move(.left, 512, u8, slice[0..4], slice[3..6]));
    try equalErr(error.InsufficientSpace, move(.left, 1, u8, slice, slice[1..]));
}
