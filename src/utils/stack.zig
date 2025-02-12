// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

//! Public API:
//! - Stack
//! - init()
//! - initFromSlice()
//! - initFromSliceFull()
//! - initFromSliceFilled()

const std = @import("std");
const err = @import("err.zig");
const IntFittingRange = std.math.IntFittingRange;

/// A generic stack implementation. Can be either fixed-array or slice-based. If
/// `length` is null, the stack is slice-based and must be initialized from a
/// slice using `initFull`, `initEmpty`, or `initFilled`.
pub fn Stack(T: type, length: ?usize) type {
    if (length) |l| if (l == 0) @compileError("stack length cannot be zero");
    return struct {
        arr: if (length) |l| [l]T else []T = undefined,
        len: if (length) |l| IntFittingRange(0, l) else usize = 0,
        nil: bool = true,

        const Self = @This();
        pub const Error = err.OutOfSpace;
        pub const Writer = std.io.Writer(*Self, Error, write);

        pub usingnamespace if (length == null) struct {
            pub fn initFull(slc: []T) Self {
                return .{
                    .arr = slc,
                    .nil = if (slc.len == 0) true else false,
                    .len = slc.len,
                };
            }

            pub fn initEmpty(slc: []T) Self {
                return .{ .arr = slc, .nil = true, .len = 0 };
            }

            pub fn initFilled(slc: []T, size: usize) Self {
                return if (size == 0) .{ .arr = slc, .nil = true, .len = 0 } else .{
                    .arr = slc,
                    .nil = false,
                    .len = if (size >= slc.len) slc.len else size,
                };
            }
        } else struct {};

        pub fn peek(s: *Self) T {
            return s.arr[s.len - 1];
        }

        pub fn peekOrNull(s: *Self) ?T {
            if (s.nil) return null;
            return s.arr[s.len - 1];
        }

        pub fn pop(s: *Self) T {
            s.len -= 1; // underflow is intentional
            if (s.len == 0) s.nil = true;
            return s.arr[s.len];
        }

        pub fn popOrNull(s: *Self) ?T {
            if (s.nil) return null;
            s.len -= 1;
            if (s.len == 0) s.nil = true;
            return s.arr[s.len];
        }

        pub fn push(s: *Self, item: T) Error!void {
            if (s.len >= s.arr.len) return Error.OutOfSpace;
            s.arr[s.len] = item;
            s.len +|= 1;
            s.nil = false;
        }

        pub fn cap(s: *Self) usize {
            return s.arr.len;
        }

        pub fn left(s: *Self) usize {
            return s.arr.len - s.len;
        }

        pub fn empty(s: *Self) bool {
            return s.nil == true;
        }

        pub fn full(s: *Self) bool {
            return s.len == s.arr.len;
        }

        pub fn makeFull(s: *Self) void {
            s.nil = false;
            s.len = s.arr.len;
        }

        pub fn reset(s: *Self) void {
            s.len = 0;
            s.nil = true;
        }

        pub fn slice(s: *Self) []T {
            return s.arr[0..s.len];
        }

        pub fn sliceRest(s: *Self) []T {
            return s.arr[s.len..];
        }

        pub fn write(s: *Self, item: T) Error!usize {
            try s.push(item);
            return 1;
        }

        pub fn writer(s: *Self) Writer {
            return Writer{ .context = s };
        }
    };
}

pub fn init(T: type, comptime len: usize) Stack(T, len) {
    return .{};
}

pub fn initFromSlice(T: type, slice: []T) Stack(T, null) {
    return Stack(T, null).initEmpty(slice);
}

pub fn initFromSliceFull(T: type, slice: []T) Stack(T, null) {
    return Stack(T, null).initFull(slice);
}

pub fn initFromSliceFilled(T: type, slice: []T, size: usize) Stack(T, null) {
    return Stack(T, null).initFilled(slice, size);
}

test Stack {
    const t = std.testing;
    // [array-based]

    const s_size = 10;
    var s = Stack(usize, s_size){};
    s = init(usize, s_size); // the same

    try t.expectEqual(s_size, s.cap());
    try t.expectEqual(0, s.len);
    try t.expectEqual(true, s.empty());
    try t.expectEqual(false, s.full());

    // push
    for (0..s_size) |i| {
        try t.expectEqual(i, s.len);
        try t.expectEqual(s_size - i, s.left());
        try s.push(i);
    }

    try t.expectEqual(s_size, s.len);
    try t.expectEqual(0, s.left());
    try t.expectEqual(true, s.full());
    try t.expectEqual(9, s.peek());
    try t.expectError(error.OutOfSpace, s.push(1));

    // pop
    var i: usize = s.len; // 10
    while (i > 0) : (i -= 1) {
        try t.expectEqual(i, s.len);
        try t.expectEqual(s_size - s.len, s.left());
        try t.expectEqual(i - 1, s.popOrNull());
    }

    try t.expectEqual(0, s.len);
    try t.expectEqual(s_size, s.left());
    try t.expectEqual(false, s.full());
    try t.expectEqual(null, s.peekOrNull());

    s.makeFull();
    try t.expectEqual(true, s.full());

    // [slice-based]

    var buf: [5]u8 = undefined;

    var s1 = initFromSlice(u8, buf[0..]);
    try t.expectEqual(5, s1.sliceRest().len);

    try s1.push('a');
    try s1.push('b');
    try t.expectEqualSlices(u8, "ab", s1.slice());
    try t.expectEqual(3, s1.sliceRest().len);

    var s2 = initFromSliceFilled(u8, buf[0..], 2);
    try s2.push('c');
    try t.expectEqualSlices(u8, "abc", s2.slice());
    try t.expectEqual(2, s2.sliceRest().len);

    buf[3] = 'd';
    buf[4] = 'e';

    var s3 = initFromSliceFull(u8, buf[0..]);
    try t.expectEqualSlices(u8, "abcde", s3.slice());
    try t.expectEqual(0, s3.sliceRest().len);
}
