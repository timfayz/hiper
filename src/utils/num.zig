// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

//! Public API:
//! - typeIsNum
//! - countIntLen
//! - numInRangeInc
//! - numInRangeExc

const std = @import("std");

pub fn typeIsNum(T: type) void {
    if (@typeInfo(T) != .Int and @typeInfo(T) != .Float)
        @compileError("type must be a number, got " ++ @tagName(@typeInfo(T)));
}

/// Returns the number of digits in an integer.
pub fn countIntLen(int: usize) usize {
    if (int == 0) return 1;
    var len: usize = 1;
    var next: usize = int;
    while (true) {
        next /= 10;
        if (next > 0)
            len += 1
        else
            break;
    }
    return len;
}

test "+countIntLen" {
    const t = std.testing;

    try t.expectEqual(1, countIntLen(0));
    try t.expectEqual(1, countIntLen(1));
    try t.expectEqual(1, countIntLen(9));
    try t.expectEqual(2, countIntLen(10));
    try t.expectEqual(2, countIntLen(11));
    try t.expectEqual(2, countIntLen(99));
    try t.expectEqual(3, countIntLen(100));
    try t.expectEqual(3, countIntLen(101));
    try t.expectEqual(3, countIntLen(999));
    try t.expectEqual(
        std.fmt.comptimePrint("{d}", .{std.math.maxInt(u32)}).len,
        countIntLen(std.math.maxInt(u32)),
    );
}

pub inline fn numInRangeInc(T: type, num: T, min: T, max: T) bool {
    typeIsNum(T);
    return num >= min and num <= max;
}

pub inline fn numInRangeExc(T: type, num: T, min: T, max: T) bool {
    typeIsNum(T);
    return num > min and num < max;
}

test "+numInRange" {
    const expect = std.testing.expectEqual;

    // inclusive
    //                          |num| |min| |max|
    // reversed range
    try expect(false, numInRangeInc(u4, 0, 15, 0));
    try expect(false, numInRangeInc(u4, 7, 15, 0));
    try expect(false, numInRangeInc(u4, 15, 15, 0));
    // max type range
    try expect(true, numInRangeInc(u1, 0, 0, 1));
    try expect(true, numInRangeInc(u1, 1, 0, 1));
    // single number range
    try expect(true, numInRangeInc(u4, 15, 15, 15));
    // normal range
    try expect(true, numInRangeInc(u8, 5, 5, 10));
    try expect(true, numInRangeInc(u8, 7, 5, 10));
    try expect(true, numInRangeInc(u8, 10, 5, 10));
    try expect(false, numInRangeInc(u8, 4, 5, 10));
    try expect(false, numInRangeInc(u8, 11, 5, 10));
    // negative range
    try expect(true, numInRangeInc(i8, -10, -20, -10));
    try expect(true, numInRangeInc(i8, -20, -20, -10));
    try expect(true, numInRangeInc(i8, -15, -20, -10));
    try expect(false, numInRangeInc(i8, -21, -20, -10));
    try expect(false, numInRangeInc(i8, -9, -20, -10));

    // exclusive
    //
    // reversed range
    try expect(false, numInRangeExc(u4, 0, 15, 0));
    try expect(false, numInRangeExc(u4, 7, 15, 0));
    try expect(false, numInRangeExc(u4, 15, 15, 0));
    // max type range
    try expect(false, numInRangeExc(u1, 0, 0, 1));
    try expect(false, numInRangeExc(u1, 1, 0, 1));
    // single number range
    try expect(false, numInRangeExc(u4, 15, 15, 15));
    // normal range
    try expect(false, numInRangeExc(u8, 5, 5, 10));
    try expect(true, numInRangeExc(u8, 6, 5, 10));
    try expect(true, numInRangeExc(u8, 9, 5, 10));
    try expect(false, numInRangeExc(u8, 10, 5, 10));
    // negative range
    try expect(false, numInRangeExc(i8, -10, -20, -10));
    try expect(true, numInRangeExc(i8, -11, -20, -10));
    try expect(true, numInRangeExc(i8, -19, -20, -10));
    try expect(false, numInRangeExc(i8, -20, -20, -10));
}
