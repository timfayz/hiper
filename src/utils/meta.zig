// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

//! Public API:
//! - isStruct()
//! - isSlice()
//! - isTuple()
//! - isTupleOf()
//! - isOneOf()
//! - isNum()
//! - isInt()
//! - isFloat()
//! - cPtr()

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

/// Checks comptime if `arg` is a slice.
pub inline fn isSlice(arg: anytype) bool {
    const info = @typeInfo(@TypeOf(arg));
    return info == .pointer and info.pointer.size == .slice;
}

test isSlice {
    const equal = std.testing.expectEqual;
    try equal(false, isSlice(1));
    try equal(true, isSlice(@as([]const u8, "hello")));
}

/// Checks comptime if `arg` is an optional type.
pub inline fn isOptional(arg: anytype) bool {
    const info = @typeInfo(@TypeOf(arg));
    return info == .optional;
}

test isOptional {
    const equal = std.testing.expectEqual;
    try equal(false, isOptional(1));
    try equal(true, isOptional(@as(?u8, 1)));
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
    try equal(true, isTupleOf(.{struct { u1, bool }{ 1, true }}, struct { u1, bool }));
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
    try equal(false, isOneOf(@as(u8, 1), .{f32}));
    try equal(false, isOneOf(@as(u8, 1), .{ f32, bool, usize }));
    try equal(true, isOneOf(@as(usize, 1), .{ f32, bool, usize }));
    try equal(true, isOneOf(.{1}, .{ f32, struct { comptime comptime_int = 1 } }));
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
}

/// Checks comptime if `arg` is an integer.
pub inline fn isInt(arg: anytype) bool {
    return switch (@typeInfo(@TypeOf(arg))) {
        .int => true,
        .comptime_int => true,
        else => false,
    };
}

test isInt {
    const equal = std.testing.expectEqual;
    try equal(true, isInt(1));
    try equal(false, isInt(1.1));
    try equal(false, isInt(.{1}));
}

/// Checks comptime if `arg` is a number (integer or float).
pub inline fn isFloat(arg: anytype) bool {
    return switch (@typeInfo(@TypeOf(arg))) {
        .float => true,
        .comptime_float => true,
        else => false,
    };
}

test isFloat {
    const equal = std.testing.expectEqual;
    try equal(false, isFloat(1));
    try equal(true, isFloat(1.1));
    try equal(false, isFloat(.{1}));
}

pub inline fn errorSet(arg: anytype) []const std.builtin.Type.Error {
    const info = @typeInfo(if (@TypeOf(arg) == type) arg else @TypeOf(arg));

    return comptime switch (info) {
        .error_set => |errors| errors.?,
        .error_union => |u| std.meta.fields(u.error_set),
        else => @compileError("type doesn't have error info"),
    };
}
