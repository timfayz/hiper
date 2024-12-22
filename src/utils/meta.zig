// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

//! Public API:
//! - isStruct()
//! - isTuple()
//! - isNum()

const std = @import("std");
const meta = std.meta;

/// Checks comptime if `arg` is a struct (tuples are not considered structs).
pub inline fn isStruct(arg: anytype) bool {
    const info = @typeInfo(@TypeOf(arg));
    return info == .@"struct" and !info.@"struct".is_tuple;
}

test isStruct {
    const equal = std.testing.expectEqual;
    try equal(false, isStruct(.{1}));
    try equal(false, isStruct(struct { usize }{1}));
    try equal(true, isStruct(struct { field: usize }{ .field = 1 }));
}

/// Checks comptime if `arg` is a tuple (structs are not considered tuples).
pub inline fn isTuple(arg: anytype) bool {
    const info = @typeInfo(@TypeOf(arg));
    return info == .@"struct" and info.@"struct".is_tuple;
}

test isTuple {
    const equal = std.testing.expectEqual;
    try equal(true, isTuple(.{1}));
    try equal(true, isTuple(struct { usize }{1}));
    try equal(false, isTuple(struct { field: usize }{ .field = 1 }));
}

/// Checks comptime if `arg` is a number (integer or float).
pub inline fn isNum(arg: anytype) bool {
    return switch (@typeInfo(@TypeOf(arg))) {
        .int => true,
        .comptime_int => true,
        .float => true,
        .comptime_float => true,
        else => false,
    };
}

test isNum {
    const equal = std.testing.expectEqual;
    try equal(true, isNum(1));
    try equal(true, isNum(1.1));
    try equal(false, isNum(.{1}));
    try equal(false, isNum(usize));
}
