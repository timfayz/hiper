// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

const std = @import("std");
const Stack = @import("stack.zig");

/// Retrieves the ending position of a line.
pub fn indexOfLineEnd(input: [:0]const u8, index: usize) usize {
    if (index >= input.len) return input.len;
    return indexOfLineEndImpl(input, index);
}

/// Retrieves the starting position of a line.
pub fn indexOfLineStart(input: [:0]const u8, index: usize) usize {
    if (index >= input.len)
        return indexOfLineStartImpl(input, input.len);
    return indexOfLineStartImpl(input, index);
}

/// Retrieves the ending position of a line without boundary checks.
inline fn indexOfLineEndImpl(input: [:0]const u8, index: usize) usize {
    var i: usize = index;
    while (true) : (i += 1) {
        if (input[i] == '\n') break;
        if (i == input.len) break;
    }
    return i;
}

/// Retrieves the starting position of a line without boundary checks.
inline fn indexOfLineStartImpl(input: [:0]const u8, index: usize) usize {
    var i: usize = index;
    if (i == 0 and input[i] == '\n') return 0;
    if (i != 0 and input[i] == '\n') i -= 1; // step back
    while (true) : (i -= 1) {
        if (input[i] == '\n') {
            i += 1;
            break;
        }
        if (i == 0) break;
    }
    return i;
}

test "+indexOfLineEnd/Start" {
    const t = std.testing;

    const case = struct {
        pub fn runStart(input: [:0]const u8, args: struct { index: usize, expect: usize }) !void {
            try t.expectEqual(args.expect, indexOfLineStart(input, args.index));
        }

        pub fn runEnd__(input: [:0]const u8, args: struct { index: usize, expect: usize }) !void {
            try t.expectEqual(args.expect, indexOfLineEnd(input, args.index));
        }
    };

    try case.runStart("", .{ .index = 0, .expect = 0 });
    try case.runEnd__("", .{ .index = 0, .expect = 0 });

    try case.runStart("\n", .{ .index = 0, .expect = 0 });
    try case.runEnd__("\n", .{ .index = 0, .expect = 0 });
    //                 ^
    try case.runStart("\n\n", .{ .index = 0, .expect = 0 });
    try case.runEnd__("\n\n", .{ .index = 0, .expect = 0 });
    //                 ^
    try case.runStart("\n\n", .{ .index = 1, .expect = 1 });
    try case.runEnd__("\n\n", .{ .index = 1, .expect = 1 });
    //                   ^
    try case.runStart("\n\n\n", .{ .index = 1, .expect = 1 });
    try case.runEnd__("\n\n\n", .{ .index = 1, .expect = 1 });
    //                   ^
    try case.runStart("line", .{ .index = 2, .expect = 0 });
    try case.runEnd__("line", .{ .index = 2, .expect = 4 });
    //                   ^
    try case.runStart("line", .{ .index = 4, .expect = 0 });
    try case.runEnd__("line", .{ .index = 4, .expect = 4 });
    //                     ^
    try case.runStart("line\n", .{ .index = 5, .expect = 5 });
    try case.runEnd__("line\n", .{ .index = 5, .expect = 5 });
    //                       ^
    // correct behavior for 0-terminated strings ("line\n"[5..5] -> "")

    try case.runStart("\nline2\n", .{ .index = 3, .expect = 1 });
    try case.runEnd__("\nline2\n", .{ .index = 3, .expect = 6 });
    //                   ^ ^  ^
    //                   1 3  6
}

/// Retrieves the ending position of a slice in source.
pub inline fn indexOfSliceEnd(source: anytype, slice: anytype) usize {
    return slice.ptr - source.ptr +| slice.len;
}

/// Retrieves the starting position of a slice in source.
pub inline fn indexOfSliceStart(source: anytype, slice: anytype) usize {
    return slice.ptr - source.ptr;
}

test "+indexOfSliceStart/End" {
    const t = std.testing;

    const in1 = "";
    try t.expectEqual(0, indexOfSliceEnd(in1, in1[0..0]));
    const in2 = "0123456789";
    try t.expectEqual(0, indexOfSliceEnd(in2, in2[0..0]));
    try t.expectEqual(7, indexOfSliceEnd(in2, in2[3..7]));
    try t.expectEqual(9, indexOfSliceEnd(in2, in2[3..9]));
    try t.expectEqual(10, indexOfSliceEnd(in2, in2[3..10]));

    const in3 = "";
    try t.expectEqual(0, indexOfSliceStart(in3, in3[0..0]));
    const in4 = "0123456789";
    try t.expectEqual(0, indexOfSliceStart(in4, in4[0..0]));
    try t.expectEqual(3, indexOfSliceStart(in4, in4[3..7]));
    try t.expectEqual(9, indexOfSliceStart(in4, in4[9..10]));
    try t.expectEqual(10, indexOfSliceStart(in4, in4[10..10]));
}

/// Returns the number of digits in an integer.
pub fn intLen(int: usize) usize {
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

test "+intLen" {
    const t = std.testing;

    try t.expectEqual(1, intLen(0));
    try t.expectEqual(1, intLen(1));
    try t.expectEqual(1, intLen(9));
    try t.expectEqual(2, intLen(10));
    try t.expectEqual(2, intLen(11));
    try t.expectEqual(2, intLen(99));
    try t.expectEqual(3, intLen(100));
    try t.expectEqual(3, intLen(101));
    try t.expectEqual(3, intLen(999));
    try t.expectEqual(
        std.fmt.comptimePrint("{d}", .{std.math.maxInt(u32)}).len,
        intLen(std.math.maxInt(u32)),
    );
}

/// Returns the line number at the specified index in `input`. Line numbers
/// start from 1.
pub fn lineNumAt(input: [:0]const u8, index: usize) usize {
    const idx = if (index > input.len) input.len else index; // normalize

    // spacial case: index at the first empty line
    if (idx == 0 and input[0] == '\n') return 1;

    // general case
    var line_number: usize = 1;
    var i: usize = 0;
    while (i < idx) : (i += 1) {
        if (input[i] == '\n') line_number += 1;
    }
    return line_number;
}

test "+lineNumAt" {
    const t = std.testing;

    try t.expectEqual(1, lineNumAt("", 0));
    try t.expectEqual(1, lineNumAt("", 100));

    try t.expectEqual(1, lineNumAt("\n", 0));
    //                              ^ (1 line)
    try t.expectEqual(2, lineNumAt("\n", 1));
    //                                ^ (2 line)
    try t.expectEqual(2, lineNumAt("\n", 100));
    //                                ^ (2 line)
    try t.expectEqual(2, lineNumAt("\n\n", 1));
    //                                ^ (2 line)
    try t.expectEqual(3, lineNumAt("\n\n", 2));
    //                                  ^ (3 line)

    try t.expectEqual(1, lineNumAt("l1\nl2\nl3", 0));
    //                              ^ (1 line)
    try t.expectEqual(2, lineNumAt("l1\nl2\nl3", 3));
    //                                  ^ (2 line)
    try t.expectEqual(3, lineNumAt("l1\nl2\nl3", 6));
    //                                      ^ (3 line)
}

/// Reverses slice items in-place.
pub fn reverseSlice(T: type, items: []T) void {
    if (items.len <= 1) return;
    var i: usize = 0;
    const swap_amt = items.len / 2;
    const last_item_idx = items.len - 1;
    while (i < swap_amt) : (i += 1) {
        const tmp = items[i];
        items[i] = items[last_item_idx - i]; // swap lhs
        items[last_item_idx - i] = tmp; // swap rhs
    }
}

test "+reverseInplace" {
    const t = std.testing;

    const run = struct {
        pub fn case(input: []const u8, expect: []const u8) !void {
            var buf: [32]u8 = undefined;
            for (input, 0..) |byte, i| buf[i] = byte;
            const actual = buf[0..input.len];
            reverseSlice(u8, actual);
            try t.expectEqualStrings(expect, actual);
        }
    };

    try run.case("", "");
    try run.case("1", "1");
    try run.case("12", "21");
    try run.case("123", "321");
    try run.case("1234", "4321");
    try run.case("12345", "54321");
}

fn readLineImpl(
    comptime mode: enum { forward, backward },
    stack: [][]const u8,
    input: [:0]const u8,
    index: usize,
    amount: usize,
) struct { [][]const u8, usize } {
    if (stack.len == 0 or amount == 0) return .{ stack[0..0], 0 };

    // current line
    var line_start = indexOfLineStart(input, index);
    var line_end = indexOfLineEnd(input, index);

    var s = Stack.initFromSliceEmpty([]const u8, stack);
    s.push(input[line_start..line_end]) catch unreachable;

    // relative position in line
    const index_rel_pos = index - line_start;

    var i: usize = amount - 1;
    while (i != 0 and !s.full()) : (i -= 1) {
        switch (mode) {
            .forward => {
                if (line_end >= input.len) break;
                const start_shifted = line_end + 1;
                line_start = start_shifted;
                line_end = indexOfLineEnd(input, start_shifted);
            },
            .backward => {
                if (line_start == 0) break;
                const end_shifted = line_start - 1;
                line_end = end_shifted;
                line_start = indexOfLineStart(input, end_shifted);
            },
        }
        s.push(input[line_start..line_end]) catch unreachable;
    }

    if (mode == .backward) reverseSlice([]const u8, s.slice());
    return .{ s.slice(), index_rel_pos };
}

/// Reads lines from the input at a specified index, pushing slices onto `stack`
/// until either the stack is full or the `amount` of lines are read. Returns the
/// slice of retrieved lines with the index's relative position within the current
/// line (always `stack[0]`). If `stack` is empty, nothing will be read.
pub inline fn readLinesForward(
    stack: [][]const u8,
    input: [:0]const u8,
    index: usize,
    amount: usize,
) struct { [][]const u8, usize } {
    return readLineImpl(.forward, stack, input, index, amount);
}

/// Reads lines from the input at a specified index backward, pushing slices
/// onto `stack` until either the stack is full or the `amount` of lines are
/// read. Returns the slice of retrieved lines with the index's relative position
/// within the current line (always `stack[stack.len - 1]`). If `stack` is empty,
/// nothing will be read. Lines are returned in normal order.
pub inline fn readLinesBackward(
    stack: [][]const u8,
    input: [:0]const u8,
    index: usize,
    amount: usize,
) struct { [][]const u8, usize } {
    return readLineImpl(.backward, stack, input, index, amount);
}

test "+readLinesForward/Backward" {
    const t = std.testing;

    const run = struct {
        fn case(
            mode: enum { forward, backward },
            input: [:0]const u8,
            index: usize,
            expect: anytype,
            args: struct { amount: usize, rel_pos: usize },
        ) !void {
            const expect_arr = std.meta.fields(@TypeOf(expect));
            const expect_lines: [expect_arr.len][]const u8 = expect;

            var stack: [32][]const u8 = undefined;
            const actual_lines, const actual_pos = switch (mode) {
                .forward => readLinesForward(&stack, input, index, args.amount),
                .backward => readLinesBackward(&stack, input, index, args.amount),
            };

            try t.expectEqual(expect_lines.len, actual_lines.len);
            for (expect_lines, actual_lines) |expected, actual| {
                try t.expectEqualStrings(expected, actual);
            }
            try t.expectEqual(args.rel_pos, actual_pos);
        }
    };

    const input = "first\nsecond\nthird";
    //             ^0   ^5      ^12    ^18
    //                      ^8(rel_pos:2)

    try run.case(.forward, input, 0, .{}, .{ .amount = 0, .rel_pos = 0 });
    try run.case(.forward, input, 0, .{"first"}, .{ .amount = 1, .rel_pos = 0 });
    try run.case(.forward, input, 3, .{"first"}, .{ .amount = 1, .rel_pos = 3 });
    try run.case(.forward, input, 5, .{"first"}, .{ .amount = 1, .rel_pos = 5 });
    try run.case(.forward, input, 6, .{"second"}, .{ .amount = 1, .rel_pos = 0 });
    try run.case(.forward, input, 8, .{ "second", "third" }, .{ .amount = 2, .rel_pos = 2 });
    try run.case(.forward, input, 18, .{"third"}, .{ .amount = 2, .rel_pos = 5 });

    try run.case(.backward, input, 0, .{}, .{ .amount = 0, .rel_pos = 0 });
    try run.case(.backward, input, 0, .{"first"}, .{ .amount = 1, .rel_pos = 0 });
    try run.case(.backward, input, 3, .{"first"}, .{ .amount = 1, .rel_pos = 3 });
    try run.case(.backward, input, 5, .{"first"}, .{ .amount = 1, .rel_pos = 5 });
    try run.case(.backward, input, 6, .{"second"}, .{ .amount = 1, .rel_pos = 0 });
    try run.case(.backward, input, 8, .{ "first", "second" }, .{ .amount = 2, .rel_pos = 2 });
    try run.case(.backward, input, 18, .{ "second", "third" }, .{ .amount = 2, .rel_pos = 5 });
}

const IndexInfo = struct { rel_pos: usize, line_num: usize };

/// Reads lines around a specified index in the input. Returns a slice of
/// retrieved lines with the relative position of the index within the current
/// line and its line number. Function works in three modes:
///
/// * If `backward = 0` and `forward >= 1`, reads forward only, exactly as `readLinesForward`.
/// * If `backward >= 1` and `forward = 0`, reads backward only, exactly as `readLinesBackward`.
/// * If `backward > 0` and `forward > 0`, reads the current line + extra lines backward/forward as specified.
///
/// The number of lines read depends on the available `stack.len` and the
/// requested `amount`.
pub fn readLinesAround(
    stack: [][]const u8,
    input: [:0]const u8,
    index: usize,
    amount: struct { backward: usize = 0, forward: usize = 0 },
) struct { [][]const u8, IndexInfo } {
    if (stack.len == 0 or (amount.backward == 0 and amount.forward == 0)) {
        return .{ stack[0..0], .{ .rel_pos = 0, .line_num = 0 } };
    } else if (amount.backward == 0) {
        const lines, const index_rel_pos = readLinesForward(stack, input, index, amount.forward);
        return .{ lines, .{ .rel_pos = index_rel_pos, .line_num = 0 } };
    } else if (amount.forward == 0) {
        const lines, const index_rel_pos = readLinesBackward(stack, input, index, amount.backward);
        return .{ lines, .{ .rel_pos = index_rel_pos, .line_num = 0 } };
    } else {
        const lines_backward, const index_rel_pos = readLinesBackward(stack, input, index, amount.backward + 1);
        const curr_line = lines_backward[lines_backward.len -| 1];
        const next_index = indexOfSliceEnd(input, curr_line) + 1;
        const lines_around = blk: {
            if (next_index < input.len) {
                const lines_forward, _ = readLinesForward(stack[lines_backward.len..], input, next_index, amount.forward);
                break :blk stack[0 .. lines_backward.len + lines_forward.len];
            } else {
                break :blk lines_backward;
            }
        };
        return .{ lines_around, .{ .rel_pos = index_rel_pos, .line_num = lines_backward.len - 1 } };
    }
}

test "+readLinesAround" {
    const t = std.testing;
    _ = t; // autofix

    const input = "one\ntwo\nthree\nfour\nfive";
    _ = input; // autofix
    //             ^0 ^3   ^7     ^13   ^18   ^23

}
