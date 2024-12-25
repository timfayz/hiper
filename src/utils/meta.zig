// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

//! Public API:
//! - isStruct()
//! - isTuple()
//! - isNum()
//! - isInt()
//! - isFloat()

const std = @import("std");
const meta = std.meta;

/// Checks comptime if `arg` is a struct (tuples are not considered structs).
pub inline fn isStruct(arg: anytype) bool {
    const info = @typeInfo(@TypeOf(arg));
    return info == .@"struct" and !info.@"struct".is_tuple;
}

/// Checks comptime if `arg` is a tuple (structs are not considered tuples).
pub inline fn isTuple(arg: anytype) bool {
    const info = @typeInfo(@TypeOf(arg));
    return info == .@"struct" and info.@"struct".is_tuple;
}

test isStruct {
    const equal = std.testing.expectEqual;
    try equal(false, isStruct(.{1}));
    try equal(false, isStruct(struct { usize }{1}));
    try equal(true, isStruct(struct { field: usize }{ .field = 1 }));
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

/// Checks comptime if `arg` is an integer.
pub inline fn isInt(arg: anytype) bool {
    return switch (@typeInfo(@TypeOf(arg))) {
        .int => true,
        .comptime_int => true,
        else => false,
    };
}

/// Checks comptime if `arg` is a number (integer or float).
pub inline fn isFloat(arg: anytype) bool {
    return switch (@typeInfo(@TypeOf(arg))) {
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
}

test isInt {
    const equal = std.testing.expectEqual;
    try equal(true, isInt(1));
    try equal(false, isInt(1.1));
    try equal(false, isInt(.{1}));
}

test isFloat {
    const equal = std.testing.expectEqual;
    try equal(false, isFloat(1));
    try equal(true, isFloat(1.1));
    try equal(false, isFloat(.{1}));
}
