// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

const std = @import("std");

pub inline fn init(T: type, comptime length: usize) Stack(T, length) {
    return Stack(T, length){};
}

pub fn Stack(T: type, length: usize) type {
    if (length == 0) @compileError("stack length cannot be zero");
    return struct {
        const Len = std.math.IntFittingRange(0, length);

        arr: [length]T = undefined,
        top: Len = 0,
        nil: bool = true, // signifies the stack is empty

        const Self = @This();
        pub const Error = error{NoSpaceLeft};

        pub fn pop(s: *Self) T {
            s.top -= 1;
            if (s.top == 0) s.nil = true;
            return s.arr[s.top];
        }

        pub fn popOrNull(s: *Self) ?T {
            if (s.nil) return null;
            s.top -= 1;
            if (s.top == 0) s.nil = true;
            return s.arr[s.top];
        }

        pub fn push(s: *Self, item: T) Error!void {
            if (s.top >= s.arr.len) return Error.NoSpaceLeft;
            s.arr[s.top] = item;
            s.top +|= 1;
            s.nil = false;
        }

        pub fn len(s: *Self) usize {
            return s.top;
        }

        pub fn cap(s: *Self) usize {
            return s.arr.len;
        }

        pub fn left(s: *Self) usize {
            return s.arr.len - s.top;
        }

        pub fn empty(s: *Self) bool {
            return s.nil == true;
        }

        pub fn full(s: *Self) bool {
            return s.top == s.arr.len;
        }

        pub fn reset(s: *Self) void {
            s.top = 0;
            s.nil = true;
        }

        pub fn slice(s: *Self) []T {
            return s.arr[0..s.top];
        }
    };
}

test "test Stack" {
    const t = std.testing;
    // test internals
    {
        var stack1 = Stack(usize, 1){};
        try t.expectEqual(1, stack1.cap()); // (!) assert stack capacity
        try t.expectEqual(true, stack1.empty()); // (!) assert stack is empty
        try t.expectEqual(false, stack1.full()); // (!) assert stack is not full

        try stack1.push(42); // (!) assert stack can be pushed
        try t.expectEqual(false, stack1.empty()); // (!) assert stack is not empty
        try t.expectEqual(true, stack1.full()); // (!) assert stack is full
        try t.expectError(error.NoSpaceLeft, stack1.push(42)); // (!) assert stack has no space left

        try t.expectEqual(42, stack1.popOrNull()); // (!) assert stack returned what was put
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
    // test general usage
    {
        const stack_size = 100;
        var s = Stack(usize, stack_size){};

        try t.expectEqual(stack_size, s.cap());

        // push
        for (0..stack_size) |i| {
            try t.expectEqual(i, s.len());
            try t.expectEqual(stack_size - i, s.left());
            try s.push(i);
        }
        try t.expectEqual(stack_size, s.len());
        try t.expectEqual(0, s.left());

        // pop
        var i: usize = s.len(); // 100
        while (i > 0) : (i -= 1) {
            try t.expectEqual(i, s.len());
            try t.expectEqual(stack_size - s.len(), s.left());
            try t.expectEqual(i - 1, s.popOrNull());
        }
        try t.expectEqual(0, s.len());
        try t.expectEqual(stack_size, s.left());
    }
}

pub inline fn initFromSliceFilled(T: type, slice: []T) StackFromSlice(T) {
    return StackFromSlice(T).initFilled(slice);
}

pub inline fn initFromSliceEmpty(T: type, slice: []T) StackFromSlice(T) {
    return StackFromSlice(T).initEmpty(slice);
}

pub inline fn initFromSliceSetLen(T: type, slice: []T, len: usize) StackFromSlice(T) {
    return StackFromSlice(T).initLen(slice, len);
}

pub fn StackFromSlice(T: type) type {
    return struct {
        slc: []T,
        top: usize,
        nil: bool,

        const Self = @This();
        pub const Error = error{NoSpaceLeft};

        pub fn initFilled(slc: []T) Self {
            return Self{
                .slc = slc,
                .nil = if (slc.len == 0) true else false,
                .top = slc.len,
            };
        }

        pub fn initEmpty(slc: []T) Self {
            return Self{ .slc = slc, .nil = true, .top = 0 };
        }

        pub fn initLen(slc: []T, length: usize) Self {
            if (length == 0) {
                return Self{ .slc = slc, .nil = true, .top = 0 };
            }
            return Self{
                .slc = slc,
                .nil = false,
                .top = if (length >= slc.len) slc.len else length,
            };
        }

        pub fn pop(s: *Self) T {
            s.top -= 1;
            if (s.top == 0) s.nil = true;
            return s.slc[s.top];
        }

        pub fn popOrNull(s: *Self) ?T {
            if (s.nil) return null;
            s.top -= 1;
            if (s.top == 0) s.nil = true;
            return s.slc[s.top];
        }

        pub fn push(s: *Self, item: T) Error!void {
            if (s.top >= s.slc.len) return Error.NoSpaceLeft;
            s.slc[s.top] = item;
            s.top +|= 1;
            s.nil = false;
        }

        pub fn len(s: *Self) usize {
            return s.top;
        }

        pub fn cap(s: *Self) usize {
            return s.slc.len;
        }

        pub fn left(s: *Self) usize {
            return s.slc.len - s.top;
        }

        pub fn empty(s: *Self) bool {
            return s.nil == true;
        }

        pub fn full(s: *Self) bool {
            return s.top == s.slc.len;
        }

        pub fn reset(s: *Self) void {
            s.top = 0;
            s.nil = true;
        }

        pub fn slice(s: *Self) []T {
            return s.slc[0..s.top];
        }
    };
}

test "test StackFromSlice" {
    const t = std.testing;

    var buf: [5]u8 = undefined;

    var stack1 = initFromSliceEmpty(u8, buf[0..]);
    try stack1.push('a');
    try stack1.push('b');
    try t.expectEqualSlices(u8, "ab", stack1.slice());

    var stack2 = initFromSliceSetLen(u8, buf[0..], 2);
    try stack2.push('c');
    try t.expectEqualSlices(u8, "abc", stack2.slice());

    buf[3] = 'd';
    buf[4] = 'e';

    var stack3 = initFromSliceFilled(u8, buf[0..]);
    try t.expectEqualSlices(u8, "abcde", stack3.slice());
}
