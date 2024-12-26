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

/// Checks comptime if `arg` is a tuple of type `T` elements.
pub inline fn isTupleOf(arg: anytype, T: type) bool {
    if (!isTuple(arg)) return false;
    inline for (meta.fields(@TypeOf(arg))) |field|
        if (field.type != T) return false;
    return true;
}

test isTupleOf {
    const equal = std.testing.expectEqual;
    try equal(true, isTupleOf(.{ true, false }, bool));
    try equal(true, isTupleOf(.{ 1, 2 }, comptime_int));
    try equal(false, isTupleOf(.{ 1, @as(f32, 2) }, comptime_int));
    try equal(true, isTupleOf(.{struct { u1 }{1}}, struct { u1 }));
    try equal(false, isTupleOf(struct { u1 }{1}, struct { u1 }));
    try equal(false, isTupleOf(1, u1));
}

/// Checks comptime if `arg` is one of the types in `types` tuple.
pub inline fn isOneOf(arg: anytype, types: anytype) bool {
    inline for (meta.fields(@TypeOf(types))) |field| {
        if (@TypeOf(arg) == @field(types, field.name)) return true;
    }
    return false;
}

test isOneOf {
    const equal = std.testing.expectEqual;
    try equal(true, isOneOf(@as(usize, 1), .{ f32, bool, usize }));
    try equal(false, isOneOf(@as(u8, 1), .{ f32, bool, usize }));
    try equal(false, isOneOf(@as(u8, 1), .{f32}));
    try equal(true, isOneOf(.{1}, .{struct { comptime comptime_int = 1 }}));
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
