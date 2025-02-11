// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

//! Public API:
//! - Stack
//! - init()
//! - initFromSlice()
//! - initFromSliceFull()
//! - initFromSliceFilled()

const std = @import("std");
const generic = @import("generic.zig");
const IntFittingRange = std.math.IntFittingRange;

/// A generic stack implementation. Can be either fixed-array- or slice-based. If
/// `length` is null, the stack is slice-based and must be initialized from a
/// slice using `initFull`, `initEmpty`, or `initFilled`.
pub fn Stack(T: type, length: ?usize) type {
    if (length) |l| if (l == 0) @compileError("stack length cannot be zero");
    return struct {
        arr: if (length) |l| [l]T else []T = undefined,
        len: if (length) |l| IntFittingRange(0, l) else usize = 0,
        nil: bool = true,

        const Self = @This();
        pub const Error = generic.Error.OutOfSpace;
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

    // test internals
    {
        var stack1 = Stack(usize, 1){};
        try t.expectEqual(0, stack1.len); // (!) assert stack len is zero
        try t.expectEqual(1, stack1.cap()); // (!) assert stack capacity
        try t.expectEqual(true, stack1.empty()); // (!) assert stack is empty
        try t.expectEqual(false, stack1.full()); // (!) assert stack is not full
        try t.expectEqual(null, stack1.peekOrNull()); // (!) assert nothing on top

        try stack1.push(42); // (!) assert stack can be pushed
        try t.expectEqual(1, stack1.len); // (!) assert stack len is increased
        try t.expectEqual(false, stack1.empty()); // (!) assert stack is not empty
        try t.expectEqual(true, stack1.full()); // (!) assert stack is full
        try t.expectEqual(42, stack1.peek()); // (!) assert peeking works

        try t.expectError(error.OutOfSpace, stack1.push(1)); // (!) assert stack has no space left

        try t.expectEqual(42, stack1.popOrNull()); // (!) assert stack pops what was put
        try t.expectEqual(0, stack1.len); // (!) assert stack len is decreased
        try t.expectEqual(true, stack1.empty()); // (!) assert stack is empty again
        try t.expectEqual(false, stack1.full()); // (!) assert stack is not full again
        try t.expectEqual(null, stack1.popOrNull()); // (!) assert stack has nothing left to pop

        // (!) assert stack resetting works
        try stack1.push(42);
        stack1.reset();
        try t.expectEqual(true, stack1.empty());
        try t.expectEqual(null, stack1.popOrNull());

        // (!) assert getting slice of written elements works
        var stack2 = Stack(usize, 5){};
        try stack2.push(1);
        try stack2.push(2);
        try stack2.push(3);
        try t.expectEqualSlices(usize, &[_]usize{ 1, 2, 3 }, stack2.slice());
    }

    // normal use
    {
        // [buffer based]
        const stack_size = 10;
        var s = Stack(usize, stack_size){};
        s = init(usize, stack_size); // the same

        try t.expectEqual(stack_size, s.cap());

        // push
        for (0..stack_size) |i| {
            try t.expectEqual(i, s.len);
            try t.expectEqual(stack_size - i, s.left());
            try s.push(i);
        }
        try t.expectEqual(stack_size, s.len);
        try t.expectEqual(0, s.left());

        // pop
        var i: usize = s.len; // 10
        while (i > 0) : (i -= 1) {
            try t.expectEqual(i, s.len);
            try t.expectEqual(stack_size - s.len, s.left());
            try t.expectEqual(i - 1, s.popOrNull());
        }
        try t.expectEqual(0, s.len);
        try t.expectEqual(stack_size, s.left());

        // [slice based]
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
}
