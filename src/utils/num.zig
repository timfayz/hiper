// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

//! Public API:
//! - orderPair()
//! - countIntLen()
//! - inRangeInc()
//! - inRangeExc()

const std = @import("std");

/// Returns a tuple of two numbers sorted in ascending order.
pub fn orderPair(
    num1: anytype,
    num2: anytype,
) struct { @TypeOf(num1), @TypeOf(num2) } {
    return if (num1 <= num2) .{ num1, num2 } else .{ num2, num1 };
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

test countIntLen {
    const equal = std.testing.expectEqual;

    try equal(1, countIntLen(0));
    try equal(1, countIntLen(1));
    try equal(1, countIntLen(9));
    try equal(2, countIntLen(10));
    try equal(2, countIntLen(11));
    try equal(2, countIntLen(99));
    try equal(3, countIntLen(100));
    try equal(3, countIntLen(101));
    try equal(3, countIntLen(999));
    try equal(
        std.fmt.comptimePrint("{d}", .{std.math.maxInt(u32)}).len,
        countIntLen(std.math.maxInt(u32)),
    );
}

pub fn inRangeInc(T: type, num: T, min: T, max: T) bool {
    return num >= min and num <= max;
}

pub fn inRangeExc(T: type, num: T, min: T, max: T) bool {
    return num > min and num < max;
}

test inRangeInc {
    const equal = std.testing.expectEqual;
    //                         |num| |min| |max|
    // reversed range
    try equal(false, inRangeInc(u4, 0, 15, 0));
    try equal(false, inRangeInc(u4, 7, 15, 0));
    try equal(false, inRangeInc(u4, 15, 15, 0));
    // single number range
    try equal(true, inRangeInc(u4, 15, 15, 15));
    // normal range
    try equal(true, inRangeInc(u8, 5, 5, 10));
    try equal(true, inRangeInc(u8, 7, 5, 10));
    try equal(true, inRangeInc(u8, 10, 5, 10));
    try equal(false, inRangeInc(u8, 4, 5, 10));
    try equal(false, inRangeInc(u8, 11, 5, 10));
    // negative range
    try equal(true, inRangeInc(i8, -10, -20, -10));
    try equal(true, inRangeInc(i8, -20, -20, -10));
    try equal(true, inRangeInc(i8, -15, -20, -10));
    try equal(false, inRangeInc(i8, -21, -20, -10));
    try equal(false, inRangeInc(i8, -9, -20, -10));
}

test inRangeExc {
    const equal = std.testing.expectEqual;
    //                         |num| |min| |max|
    // reversed range
    try equal(false, inRangeExc(u4, 0, 15, 0));
    try equal(false, inRangeExc(u4, 7, 15, 0));
    try equal(false, inRangeExc(u4, 15, 15, 0));
    // single number range
    try equal(false, inRangeExc(u4, 15, 15, 15));
    // normal range
    try equal(false, inRangeExc(u8, 5, 5, 10));
    try equal(true, inRangeExc(u8, 6, 5, 10));
    try equal(true, inRangeExc(u8, 9, 5, 10));
    try equal(false, inRangeExc(u8, 10, 5, 10));
    // negative range
    try equal(false, inRangeExc(i8, -10, -20, -10));
    try equal(true, inRangeExc(i8, -11, -20, -10));
    try equal(true, inRangeExc(i8, -19, -20, -10));
    try equal(false, inRangeExc(i8, -20, -20, -10));
}
