// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

//! Public API:
//! - indexOfLineEnd
//! - indexOfLineStart
//! - indexOfSliceEnd
//! - indexOfSliceStart
//! - reverseSlice
//! - countIntLen
//! - countLineNum
//! - readLine
//! - readLinesForward
//! - readLinesBackward
//! - readLines

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

    try case.runStart("", .{ .index = 100, .expect = 0 });
    try case.runEnd__("", .{ .index = 100, .expect = 0 });

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

/// Reverses slice items in-place.
pub fn reverseSlice(slice: anytype) void {
    comptime {
        const T_info = @typeInfo(@TypeOf(slice));
        if (T_info != .Pointer and T_info.Pointer.size != .Slice)
            @compileError("argument must be a slice");
    }
    if (slice.len <= 1) return;
    var i: usize = 0;
    const swap_amt = slice.len / 2;
    const last_item_idx = slice.len - 1;
    while (i < swap_amt) : (i += 1) {
        const tmp = slice[i];
        slice[i] = slice[last_item_idx - i]; // swap lhs
        slice[last_item_idx - i] = tmp; // swap rhs
    }
}

test "+reverseInplace" {
    const t = std.testing;

    const case = struct {
        pub fn run(input: []const u8, expect: []const u8) !void {
            var buf: [32]u8 = undefined;
            for (input, 0..) |byte, i| buf[i] = byte;
            const actual = buf[0..input.len];
            reverseSlice(actual);
            try t.expectEqualStrings(expect, actual);
        }
    }.run;

    try case("", "");
    try case("1", "1");
    try case("12", "21");
    try case("123", "321");
    try case("1234", "4321");
    try case("12345", "54321");
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

/// Returns the line number at the specified index in `input`. Line numbers
/// start from 1.
pub fn countLineNum(input: [:0]const u8, index: usize) usize {
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

test "+countLineNum" {
    const t = std.testing;

    try t.expectEqual(1, countLineNum("", 0));
    try t.expectEqual(1, countLineNum("", 100));

    try t.expectEqual(1, countLineNum("\n", 0));
    //                                 ^ (1 line)
    try t.expectEqual(2, countLineNum("\n", 1));
    //                                   ^ (2 line)
    try t.expectEqual(2, countLineNum("\n", 100));
    //                                   ^ (2 line)
    try t.expectEqual(2, countLineNum("\n\n", 1));
    //                                   ^ (2 line)
    try t.expectEqual(3, countLineNum("\n\n", 2));
    //                                     ^ (3 line)

    try t.expectEqual(1, countLineNum("l1\nl2\nl3", 0));
    //                                 ^ (1 line)
    try t.expectEqual(2, countLineNum("l1\nl2\nl3", 3));
    //                                     ^ (2 line)
    try t.expectEqual(3, countLineNum("l1\nl2\nl3", 6));
    //                                         ^ (3 line)
}

const LineInfo = struct {
    item: []const u8,
    index_rel_pos: usize,
    line_num: usize,
};

/// Reads a line from the input starting at the specified index.
///
/// Returns:
/// * Line at the specified index.
/// * Index's relative position (IRP) within the current line.
/// * Line number if `detect_line_num` is true; otherwise, `0`.
///
/// If IRP exceeds the current line length, the index is either on a new line
/// or at the end of the stream (EOF).
pub fn readLine(
    input: [:0]const u8,
    index: usize,
    detect_line_num: bool,
) LineInfo {
    const idx = if (index > input.len) input.len else index; // normalize
    const line_start = indexOfLineStartImpl(input, idx);
    const line_end = indexOfLineEndImpl(input, idx);
    const index_rel_pos = idx - line_start;
    return .{
        .item = input[line_start..line_end],
        .index_rel_pos = index_rel_pos,
        .line_num = blk: {
            if (detect_line_num) {
                break :blk countLineNum(input, line_start);
            } else break :blk 0;
        },
    };
}

test "+readLine" {
    const t = std.testing;

    const case = struct {
        fn run(
            input: [:0]const u8,
            index: usize,
            detect_ln: bool,
            expect_line: []const u8,
            args: struct {
                exp_pos: usize,
                exp_ln: usize,
            },
        ) !void {
            const actual_line = readLine(input, index, detect_ln);
            try t.expectEqualStrings(expect_line, actual_line.item);
            try t.expectEqual(args.exp_pos, actual_line.index_rel_pos);
            try t.expectEqual(args.exp_ln, actual_line.line_num);
        }
    }.run;

    //       |input| |idx| |detect_ln| |expect_line| |expect items|
    try case("", 0, false, "", .{ .exp_pos = 0, .exp_ln = 0 });
    try case("", 0, true, "", .{ .exp_pos = 0, .exp_ln = 1 });

    try case("one", 0, false, "one", .{ .exp_pos = 0, .exp_ln = 0 });
    try case("one", 1, true, "one", .{ .exp_pos = 1, .exp_ln = 1 });
    try case("one", 3, true, "one", .{ .exp_pos = 3, .exp_ln = 1 });
    try case("one", 100, true, "one", .{ .exp_pos = 3, .exp_ln = 1 });
    //        ^0 ^3
    try case("\n", 0, true, "", .{ .exp_pos = 0, .exp_ln = 1 });
    //        ^
    try case("\n", 1, true, "", .{ .exp_pos = 0, .exp_ln = 2 });
    //          ^
    try case("\nx", 2, true, "x", .{ .exp_pos = 1, .exp_ln = 2 });
    //           ^
    try case("\nx", 1, true, "x", .{ .exp_pos = 0, .exp_ln = 2 });
    //          ^
}

/// Represents the result of a single-direction line reading.
pub const LinesInfo = struct {
    items: [][]const u8,
    index_rel_pos: usize,
    line_num: usize,
};

/// Implementation function. Reads lines in both directions.
fn readLinesImpl(
    comptime mode: enum { forward, backward },
    buf: [][]const u8,
    input: [:0]const u8,
    index: usize,
    amount: usize,
    detect_line_num: bool,
) LinesInfo {
    if (buf.len == 0 or amount == 0)
        return .{
            .items = buf[0..0],
            .index_rel_pos = 0,
            .line_num = 0,
        };

    const idx = if (index > input.len) input.len else index; // normalize
    var line_start = indexOfLineStartImpl(input, idx);
    var line_end = indexOfLineEndImpl(input, idx);
    const index_rel_pos = idx - line_start;

    var s = Stack.initFromSliceEmpty([]const u8, buf);
    s.push(input[line_start..line_end]) catch unreachable; // current line

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
    if (mode == .backward) reverseSlice(s.slice());

    return .{
        .items = s.slice(),
        .index_rel_pos = index_rel_pos,
        .line_num = blk: {
            if (detect_line_num) {
                const first_line = s.slice()[0];
                const updated_index = indexOfSliceStart(input, first_line);
                break :blk countLineNum(input, updated_index);
            } else break :blk 0;
        },
    };
}

/// Reads lines from the input starting at the specified index. Retrieves lines
/// until either the `buf` is full or the specified `amount` is reached.
///
/// Returns:
/// * Slice of the retrieved lines.
/// * Index's relative position (IRP) within the first line (always `buf[0]`).
/// * Line number of the first line in the slice (starting from 1) if
///   `detect_line_num` is true; otherwise, `0`. Also returns `0` if
///   `buf.len == 0`.
///
/// If IRP exceeds the current line length, the index is either on a new line
/// or at the end of the stream (EOF). If `buf.len == 0`, nothing is read.
pub inline fn readLinesForward(
    buf: [][]const u8,
    input: [:0]const u8,
    index: usize,
    amount: usize,
    detect_line_num: bool,
) LinesInfo {
    return readLinesImpl(.forward, buf, input, index, amount, detect_line_num);
}

/// Reads lines from the input starting at the specified index backwards.
/// Retrieves lines until either the `buf` is full or the specified `amount`
/// is reached.
///
/// Returns:
/// * Slice of the retrieved lines.
/// * Index's relative position (IRP) within the first line
///   (always `buf[buf.len - 1]`).
/// * Line number of the first line in the slice (starting from 1) if
///   `detect_line_num` is true; otherwise, `0`. Also returns `0` if
///   `buf.len == 0`.
///
/// If IRP exceeds the current line length, the index is either on a new line
/// or at the end of the stream (EOF). If `buf.len == 0`, nothing is read.
/// Lines are returned in normal order.
pub inline fn readLinesBackward(
    buf: [][]const u8,
    input: [:0]const u8,
    index: usize,
    amount: usize,
    detect_line_num: bool,
) LinesInfo {
    return readLinesImpl(.backward, buf, input, index, amount, detect_line_num);
}

test "+readLinesForward/Backward" {
    const t = std.testing;

    const case = struct {
        fn run(
            mode: enum { frwd, back },
            input: [:0]const u8,
            index: usize,
            amount: usize,
            detect_ln: bool,
            expect: anytype,
            args: struct {
                exp_pos: usize,
                exp_ln: usize,
            },
        ) !void {
            const expect_lines: [std.meta.fields(@TypeOf(expect)).len][]const u8 = expect;

            var stack: [32][]const u8 = undefined;
            const actual_lines = switch (mode) {
                .frwd => readLinesForward(&stack, input, index, amount, detect_ln),
                .back => readLinesBackward(&stack, input, index, amount, detect_ln),
            };

            try t.expectEqual(expect_lines.len, actual_lines.items.len);
            for (expect_lines, actual_lines.items) |e, a| try t.expectEqualStrings(e, a);
            try t.expectEqual(args.exp_pos, actual_lines.index_rel_pos);
            try t.expectEqual(args.exp_ln, actual_lines.line_num);
        }
    }.run;

    const in = "first\nsecond\nthird";
    //             ^0   ^5      ^12    ^18
    //                      ^8(rel_pos:2)

    //                |idx| |amt| |detect_ln| |expect items|
    try case(.frwd, in, 0, 0, false, .{}, .{ .exp_pos = 0, .exp_ln = 0 });
    try case(.frwd, in, 0, 1, false, .{"first"}, .{ .exp_pos = 0, .exp_ln = 0 });
    try case(.frwd, in, 3, 1, false, .{"first"}, .{ .exp_pos = 3, .exp_ln = 0 });
    try case(.frwd, in, 5, 1, false, .{"first"}, .{ .exp_pos = 5, .exp_ln = 0 });
    try case(.frwd, in, 6, 1, false, .{"second"}, .{ .exp_pos = 0, .exp_ln = 0 });
    try case(.frwd, in, 8, 2, false, .{ "second", "third" }, .{ .exp_pos = 2, .exp_ln = 0 });
    try case(.frwd, in, 18, 2, false, .{"third"}, .{ .exp_pos = 5, .exp_ln = 0 });
    try case(.frwd, in, 100, 2, false, .{"third"}, .{ .exp_pos = 5, .exp_ln = 0 });

    try case(.back, in, 0, 0, false, .{}, .{ .exp_pos = 0, .exp_ln = 0 });
    try case(.back, in, 0, 1, false, .{"first"}, .{ .exp_pos = 0, .exp_ln = 0 });
    try case(.back, in, 3, 1, false, .{"first"}, .{ .exp_pos = 3, .exp_ln = 0 });
    try case(.back, in, 5, 1, false, .{"first"}, .{ .exp_pos = 5, .exp_ln = 0 });
    try case(.back, in, 6, 1, false, .{"second"}, .{ .exp_pos = 0, .exp_ln = 0 });
    try case(.back, in, 8, 2, false, .{ "first", "second" }, .{ .exp_pos = 2, .exp_ln = 0 });
    try case(.back, in, 18, 2, false, .{ "second", "third" }, .{ .exp_pos = 5, .exp_ln = 0 });

    // automatic line number detection
    try case(.frwd, in, 0, 0, true, .{}, .{ .exp_pos = 0, .exp_ln = 0 });
    try case(.frwd, in, 5, 1, true, .{"first"}, .{ .exp_pos = 5, .exp_ln = 1 });
    try case(.frwd, in, 6, 1, true, .{"second"}, .{ .exp_pos = 0, .exp_ln = 2 });
    try case(.frwd, in, 8, 2, true, .{ "second", "third" }, .{ .exp_pos = 2, .exp_ln = 2 });

    try case(.back, in, 0, 0, true, .{}, .{ .exp_pos = 0, .exp_ln = 0 });
    try case(.back, in, 6, 1, true, .{"second"}, .{ .exp_pos = 0, .exp_ln = 2 });
    try case(.back, in, 8, 2, true, .{ "first", "second" }, .{ .exp_pos = 2, .exp_ln = 1 });
    try case(.back, in, 18, 2, true, .{ "second", "third" }, .{ .exp_pos = 5, .exp_ln = 2 });
}

/// Represents the result of a bi-directional line reading.
const LinesAroundInfo = struct {
    items: [][]const u8,
    curr_line_pos: usize,
    index_rel_pos: usize,
    line_num: usize,
};

/// Reads lines around a specified index in the input. Retrieves lines until
/// either the `buf` is full or the specified `amount` is reached (starting
/// backwards first, then moving forward).
///
/// Returns:
/// * Slice of the retrieved lines.
/// * Current line's position within the slice.
/// * Index's relative position within the current line.
/// * Line number of the first line in the slice (starting from 1) if
///   `detect_line_num` is true; otherwise, `0`. Also returns `0` if
///   `buf.len == 0`.
///
/// Function operates in three modes:
/// * If `backward = 0` and `forward >= 1`, reads forward only, exactly as `readLinesForward`.
/// * If `backward >= 1` and `forward = 0`, reads backward only, exactly as `readLinesBackward`.
/// * If `backward >= 1` and `forward >= 1`, reads current line + *extra* lines backward/forward as specified.
pub fn readLines(
    buf: [][]const u8,
    input: [:0]const u8,
    index: usize,
    detect_line_num: bool,
    amount: struct { backward: usize = 0, forward: usize = 0 },
) LinesAroundInfo {
    if (buf.len == 0 or (amount.backward == 0 and amount.forward == 0)) {
        return .{
            .items = buf[0..0],
            .curr_line_pos = 0,
            .index_rel_pos = 0,
            .line_num = 0,
        };
    } else if (amount.backward == 0) {
        const lines = readLinesForward(buf, input, index, amount.forward, detect_line_num);
        return .{
            .items = lines.items,
            .curr_line_pos = 0,
            .index_rel_pos = lines.index_rel_pos,
            .line_num = lines.line_num,
        };
    } else if (amount.forward == 0) {
        const lines = readLinesBackward(buf, input, index, amount.backward, detect_line_num);
        return .{
            .items = lines.items,
            .curr_line_pos = lines.items.len -| 1,
            .index_rel_pos = lines.index_rel_pos,
            .line_num = lines.line_num,
        };
    } else { // bi-directional read
        const lines = readLinesBackward(buf, input, index, amount.backward + 1, detect_line_num);
        const l_backward = lines.items;
        const curr_line = l_backward[l_backward.len -| 1];

        const lines_merged = blk: {
            const next_index = indexOfSliceEnd(input, curr_line) + 1;
            if (next_index < input.len) {
                const l_forward = readLinesForward(
                    buf[l_backward.len..],
                    input,
                    next_index,
                    amount.forward,
                    false,
                );
                break :blk buf[0 .. l_backward.len + l_forward.items.len];
            } else {
                break :blk l_backward;
            }
        };

        return .{
            .items = lines_merged,
            .curr_line_pos = lines.items.len - 1,
            .index_rel_pos = lines.index_rel_pos,
            .line_num = lines.line_num,
        };
    }
}

test "+readLinesAround" {
    const t = std.testing;

    const case = struct {
        fn run(
            input: [:0]const u8,
            index: usize,
            backward: usize,
            forward: usize,
            detect_ln: bool,
            expect: anytype,
            args: struct { exp_pos: usize, exp_clp: usize, exp_ln: usize },
        ) !void {
            const expect_lines: [std.meta.fields(@TypeOf(expect)).len][]const u8 = expect;

            var buf: [32][]const u8 = undefined;
            const actual = readLines(&buf, input, index, detect_ln, .{
                .backward = backward,
                .forward = forward,
            });

            try t.expectEqual(expect_lines.len, actual.items.len);
            for (expect_lines, actual.items) |e, a| try t.expectEqualStrings(e, a);
            try t.expectEqual(args.exp_clp, actual.curr_line_pos);
            try t.expectEqual(args.exp_pos, actual.index_rel_pos);
            try t.expectEqual(args.exp_pos, actual.index_rel_pos);
            try t.expectEqual(args.exp_ln, actual.line_num);
        }
    }.run;

    const in = "one\ntwo\nthree\nfour\nfive";
    //             ^0 ^3   ^7     ^13   ^18   ^23

    //         |idx| |amt_back| |amt_frwd| |detect_ln| |expect items|
    try case(in, 100, 0, 0, false, .{}, .{ .exp_pos = 0, .exp_clp = 0, .exp_ln = 0 });
    try case(in, 100, 0, 0, true, .{}, .{ .exp_pos = 0, .exp_clp = 0, .exp_ln = 0 });
    try case(in, 0, 0, 0, false, .{}, .{ .exp_pos = 0, .exp_clp = 0, .exp_ln = 0 });
    try case(in, 0, 0, 0, true, .{}, .{ .exp_pos = 0, .exp_clp = 0, .exp_ln = 0 });

    try case(in, 8, 1, 0, false, .{"three"}, .{ .exp_pos = 0, .exp_clp = 0, .exp_ln = 0 });
    try case(in, 8, 1, 0, true, .{"three"}, .{ .exp_pos = 0, .exp_clp = 0, .exp_ln = 3 });

    try case(in, 8, 0, 1, false, .{"three"}, .{ .exp_pos = 0, .exp_clp = 0, .exp_ln = 0 });
    try case(in, 8, 0, 1, true, .{"three"}, .{ .exp_pos = 0, .exp_clp = 0, .exp_ln = 3 });

    try case(in, 12, 1, 0, false, .{"three"}, .{ .exp_pos = 4, .exp_clp = 0, .exp_ln = 0 });
    try case(in, 12, 0, 1, false, .{"three"}, .{ .exp_pos = 4, .exp_clp = 0, .exp_ln = 0 });

    try case(in, 12, 2, 0, true, .{ "two", "three" }, .{ .exp_pos = 4, .exp_clp = 1, .exp_ln = 2 });
    try case(in, 12, 0, 2, true, .{ "three", "four" }, .{ .exp_pos = 4, .exp_clp = 0, .exp_ln = 3 });

    try case(in, 23, 5, 5, true, .{
        "one",
        "two",
        "three",
        "four",
        "five",
    }, .{ .exp_pos = 4, .exp_clp = 4, .exp_ln = 1 });
    try case(in, 0, 5, 5, true, .{
        "one",
        "two",
        "three",
        "four",
        "five",
    }, .{ .exp_pos = 0, .exp_clp = 0, .exp_ln = 1 });
}
