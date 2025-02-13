// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

//! Public API:
//! - reverse()
//! - reversed()
//! - commonSeg()
//! - overlap()
//! - overlaps()
//! - contains()
//! - startIndex()
//! - endIndex()
//! - bound()
//! - trunc()
//! - truncIndices()
//! - MoveError
//! - moveSeg()
//! - moveSegLeft()
//! - moveSegRight()

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

/// Returns the shared sub-slice of two slices. Both slices must be from the
/// same source; use `contains` to verify this.
///
/// ```txt
/// [slice1 ] [ slice2]    (slices disjoint)
/// [                 ]    (common span)
///
/// [slice1   ]            (slices intersect)
///         [   slice2]
/// [                 ]    (common span)
/// ```
pub fn commonSeg(T: type, slice1: []const T, slice2: []const T) []const T {
    const start = if (@intFromPtr(slice1.ptr) < @intFromPtr(slice2.ptr)) slice1.ptr else slice2.ptr;
    const end1 = slice1.ptr + slice1.len;
    const end2 = slice2.ptr + slice2.len;
    const end = if (@intFromPtr(end1) > @intFromPtr(end2)) end1 else end2;
    return start[0 .. end - start];
}

test commonSeg {
    const equal = std.testing.expectEqualStrings;
    const input = "0123";

    try equal("0123", commonSeg(u8, input[0..0], input[4..4])); // zero slices
    try equal("0123", commonSeg(u8, input[4..4], input[0..0])); // reversed order
    try equal("0123", commonSeg(u8, input[0..2], input[2..4])); // normal slices
    try equal("0123", commonSeg(u8, input[2..4], input[0..2])); // reversed order
    try equal("0123", commonSeg(u8, input[0..3], input[1..4])); // intersected slices
    try equal("0123", commonSeg(u8, input[0..4], input[0..4])); // same slices
}

/// Returns the intersection of two slices. Both slices must be from the same
/// source; use `contains` to verify this.
///
/// ```txt
/// [slice1 ] [ slice2]    (disjoint slices)
///         null           (intersection)
///
/// [slice1   ]            (intersecting slices)
///         [   slice2]
///         [ ]            (intersection)
/// ```
fn overlap(T: type, slice1: []const T, slice2: []const T) ?[]const T {
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
    try equal(null, overlap(u64, arr[0..0], arr[4..4]));
    try equal(null, overlap(u64, arr[0..2], arr[2..4]));
    try equal(null, overlap(u64, arr[1..1], arr[0..4]));
    try equalSlices(u64, arr[1..3], overlap(u64, arr[0..3], arr[1..4]).?);
    try equalSlices(u64, arr[1..3], overlap(u64, arr[1..4], arr[0..3]).?);
    try equalSlices(u64, arr[0..], overlap(u64, arr[0..4], arr[0..4]).?);
}

/// Checks if the provided segment is a valid sub-slice.
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
pub fn contains(T: type, slice: []const T, seg: []const T) bool {
    return @intFromPtr(slice.ptr) <= @intFromPtr(seg.ptr) and
        @intFromPtr(slice.ptr + slice.len) >= @intFromPtr(seg.ptr + seg.len);
}

test contains {
    const equal = std.testing.expectEqual;
    const input: [11]u8 = "hello_world".*;

    try equal(true, contains(u8, input[0..], input[0..0]));
    try equal(true, contains(u8, input[0..], input[0..1]));
    try equal(true, contains(u8, input[0..], input[3..6]));
    try equal(true, contains(u8, input[0..], input[10..11]));
    try equal(true, contains(u8, input[0..], input[11..11]));
    try equal(false, contains(u8, input[0..], "hello_world"));

    // intersecting
    try equal(true, contains(u8, input[0..5], input[0..5]));
    try equal(true, contains(u8, input[0..0], input[0..0]));
    try equal(true, contains(u8, input[11..11], input[11..11]));
    try equal(false, contains(u8, input[0..5], input[0..]));
    try equal(false, contains(u8, input[0..5], input[5..]));
    try equal(false, contains(u8, input[0..6], input[5..]));
    try equal(false, contains(u8, input[5..], input[0..5]));
}

/// Retrieves the starting position of a segment in slice. Both slices must be
/// from the same source; use `contains` to verify this.
pub fn startIndex(slice: anytype, seg: anytype) usize {
    return seg.ptr - slice.ptr;
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

/// Retrieves the ending position of a segment in slice. Both slices must be from
/// the same source; use `contains` to verify this.
pub fn endIndex(slice: anytype, seg: anytype) usize {
    return (seg.ptr - slice.ptr) +| seg.len;
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

/// Returns `[start..end]` slice segment bounded to `slice.len`.
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
    comptime view_range: range.Rel,
    comptime trunc_mode: range.TruncMode,
    comptime opt: range.Rel.Options,
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
    comptime view_range: range.Rel,
    comptime trunc_mode: range.TruncMode,
    comptime opt: range.Rel.Options,
) range.Range {
    if (meta.isNum(index)) {
        var pair = view_range.toPair(opt);
        if (view_range == .left and pair.left > 0) pair.shift(.right, 1);
        return pair.toRange(index, range.initFromSlice(slice), trunc_mode);
    } else if (meta.isTuple(index) and index.len == 2) {
        const start, const end = num.orderPairAsc(index[0], index[1]);
        const pair = view_range.toPairWithExtra(end - start +| 1, opt);
        return pair.toRange(start, range.initFromSlice(slice), trunc_mode);
    }
}

test truncIndices {
    const equal = std.testing.expectEqualDeep;

    // [relative index]
    try equal(range.init(3, 6), truncIndices("01234567", 4, .{ .around = 3 }, .hard, .{}));
    //                                           ~^~
    try equal(range.init(2, 5), truncIndices("01234567", 4, .{ .left = 3 }, .hard, .{}));
    //                                          ~~^
    try equal(range.init(4, 7), truncIndices("01234567", 4, .{ .right = 3 }, .hard, .{}));
    //                                            ^~~

    // [relative range]
    try equal(range.init(3, 9), truncIndices("0123456789", .{ 4, 6 }, .{ .around = 3 }, .hard, .{}));
    //                                           ~^^^~~
    try equal(range.init(2, 7), truncIndices("0123456789", .{ 4, 6 }, .{ .left = 2 }, .hard, .{}));
    //                                          ~~^^^
    try equal(range.init(4, 9), truncIndices("0123456789", .{ 4, 6 }, .{ .right = 2 }, .hard, .{}));
    //                                            ^^^~~
}

pub const MoveError = err.InsufficientSpace || err.OutOfSlice;

/// Moves a valid segment to the start or end of the given slice. If a move is
/// required, the segment length must be less than the stack-allocated buffer
/// size, `buf_size`.
pub fn moveSeg(
    comptime dir: range.Dir,
    comptime buf_size: usize,
    T: type,
    slice: []T,
    seg: []const T,
) MoveError!void {
    if (!contains(T, slice, seg)) return MoveError.OutOfSlice;
    if (seg.len > buf_size) return MoveError.InsufficientSpace;
    if (seg.len == 0 or seg.len == slice.len) return;
    switch (dir) {
        .right => if (endIndex(slice, seg) == slice.len) return,
        .left => if (startIndex(slice, seg) == 0) return,
    }

    // make segment copy
    var buf: [buf_size]T = undefined;
    const seg_copy = buf[0..seg.len];
    mem.copyForwards(T, seg_copy, seg);

    // swap segment with its opposite side
    switch (dir) {
        // [ [seg][seg_rhs] ] (step 0)
        // [ [seg_rhs]..... ] (step 1)
        // [ [seg_rhs][seg] ] (step 2)
        .right => {
            const seg_rhs = slice[endIndex(slice, seg)..]; // step 0
            const start: usize = startIndex(slice, seg);
            const end: usize = start +| seg_rhs.len;
            mem.copyForwards(T, slice[start..end], seg_rhs); // step 1
            // copy seg to the end of slice
            mem.copyForwards(T, slice[slice.len -| seg_copy.len..], seg_copy); // step 2
        },
        // [ [seg_lhs][seg] ] (step 0)
        // [ .....[seg_lhs] ] (step 1)
        // [ [seg][seg_lhs] ] (step 2)
        .left => {
            const seg_lhs = slice[0..startIndex(slice, seg)]; // step 0
            const end: usize = endIndex(slice, seg);
            const start: usize = end -| seg_lhs.len;
            mem.copyBackwards(T, slice[start..end], seg_lhs); // step 1
            // copy seg to the beginning of the slice
            mem.copyForwards(T, slice[0..seg_copy.len], seg_copy); // step 2
        },
    }
}

test moveSeg {
    const equal = std.testing.expectEqualStrings;
    const equalErr = std.testing.expectError;

    const origin = "0123456";
    var buf: [7]u8 = origin.*;
    const slice = buf[0..];

    // [.right mode]

    try moveSeg(.right, 512, u8, slice, slice[0..3]);
    try equal("3456012", slice);
    //             ---
    buf = origin.*;

    try moveSeg(.right, 512, u8, slice, slice[3..6]);
    try equal("0126345", slice);
    //             ---
    buf = origin.*;

    try moveSeg(.right, 512, u8, slice, slice); // move is not required
    try equal("0123456", slice);
    buf = origin.*;

    try moveSeg(.right, 512, u8, slice, slice[4..]); // move is not required
    try equal("0123456", slice);
    buf = origin.*;

    try moveSeg(.right, 512, u8, slice, slice[7..]); // zero length segment
    try equal("0123456", slice);
    buf = origin.*;

    try moveSeg(.right, 512, u8, slice, slice[3..3]); // zero length segment
    try equal("0123456", slice);
    buf = origin.*;

    try equalErr(MoveError.OutOfSlice, moveSeg(.right, 512, u8, slice[0..4], slice[3..6]));
    try equalErr(MoveError.InsufficientSpace, moveSeg(.right, 1, u8, slice, slice[1..]));

    // [.left mode]

    try moveSeg(.left, 512, u8, slice, slice[1..]);
    try equal("1234560", slice);
    //         ------
    buf = origin.*;

    try moveSeg(.left, 512, u8, slice, slice[4..]);
    try equal("4560123", slice);
    //         ---
    buf = origin.*;

    try moveSeg(.left, 512, u8, slice, slice[6..]);
    try equal("6012345", slice);
    //         -
    buf = origin.*;

    try moveSeg(.left, 512, u8, slice, slice); // move is not required
    try equal("0123456", slice);

    try moveSeg(.left, 512, u8, slice, slice[0..3]); // move is not required
    try equal("0123456", slice);

    try moveSeg(.left, 512, u8, slice, slice[7..]); // zero length segment
    try equal("0123456", slice);

    try moveSeg(.left, 512, u8, slice, slice[3..3]); // zero length segment
    try equal("0123456", slice);

    try equalErr(MoveError.OutOfSlice, moveSeg(.left, 512, u8, slice[0..4], slice[3..6]));
    try equalErr(MoveError.InsufficientSpace, moveSeg(.left, 1, u8, slice, slice[1..]));
}

/// Moves a valid segment to the beginning of the given slice. Returns an
/// error if the segment is of different origin or its length exceeds
/// 1024. Use `moveSeg` directly to increase the length.
pub fn moveSegLeft(T: type, slice: []T, seg: []const T) MoveError!void {
    return moveSeg(.left, 1024, T, slice, seg);
}

/// Moves a valid slice segment to the end of the given slice. Returns an error
/// if the segment is different origins or its length exceeds 1024. Use `moveSeg`
/// directly to increase the length.
pub fn moveSegRight(T: type, slice: []T, seg: []const T) MoveError!void {
    return moveSeg(.right, 1024, T, slice, seg);
}
