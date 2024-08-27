// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

//! Public API:
//! - indexOfLineStart
//! - indexOfLineEnd
//! - countLineNum
//! - readLine
//! - readLines

const std = @import("std");
const nm = @import("num.zig");
const stack = @import("stack.zig");
const slice = @import("slice.zig");

/// Retrieves the ending position of a line.
pub fn indexOfLineEnd(input: []const u8, index: usize) usize {
    if (index >= input.len or input.len == 0) return input.len;
    var end: usize = index;
    while (end < input.len) : (end += 1) {
        if (input[end] == '\n') break;
    }
    return end;
}

/// Retrieves the starting position of a line.
pub fn indexOfLineStart(input: []const u8, index: usize) usize {
    if (input.len == 0 or index == 0) return 0;
    var start: usize = if (index > input.len) input.len else index;
    // step back from end
    if (start == input.len or input[start] == '\n') start -|= 1;
    while (true) : (start -= 1) {
        if (input[start] == '\n') {
            start += 1;
            break;
        }
        if (start == 0) break;
    }
    return start;
}

test "+indexOfLineEnd/Start" {
    const t = std.testing;

    const lineStart = struct {
        pub fn run(input: []const u8, args: struct { idx: usize, expect: usize }) !void {
            try t.expectEqual(args.expect, indexOfLineStart(input, args.idx));
        }
    }.run;

    const lineEnd__ = struct {
        pub fn lineEnd__(input: []const u8, args: struct { idx: usize, expect: usize }) !void {
            try t.expectEqual(args.expect, indexOfLineEnd(input, args.idx));
        }
    }.lineEnd__;

    try lineStart("", .{ .idx = 0, .expect = 0 });
    try lineEnd__("", .{ .idx = 0, .expect = 0 });

    try lineStart("", .{ .idx = 100, .expect = 0 });
    try lineEnd__("", .{ .idx = 100, .expect = 0 });

    try lineStart("\n", .{ .idx = 0, .expect = 0 });
    try lineEnd__("\n", .{ .idx = 0, .expect = 0 });
    //             ^
    try lineStart("\n\n", .{ .idx = 0, .expect = 0 });
    try lineEnd__("\n\n", .{ .idx = 0, .expect = 0 });
    //             ^
    try lineStart("\n\n", .{ .idx = 1, .expect = 1 });
    try lineEnd__("\n\n", .{ .idx = 1, .expect = 1 });
    //               ^
    try lineStart("\n\n\n", .{ .idx = 1, .expect = 1 });
    try lineEnd__("\n\n\n", .{ .idx = 1, .expect = 1 });
    //               ^
    try lineStart("line", .{ .idx = 2, .expect = 0 });
    try lineEnd__("line", .{ .idx = 2, .expect = 4 });
    //               ^
    try lineStart("line", .{ .idx = 6, .expect = 0 });
    try lineEnd__("line", .{ .idx = 6, .expect = 4 });
    //                  ^+
    try lineStart("\nc", .{ .idx = 1, .expect = 1 });
    try lineEnd__("\nc", .{ .idx = 1, .expect = 2 });
    //               ^
    try lineStart("\nline2\n", .{ .idx = 3, .expect = 1 });
    try lineEnd__("\nline2\n", .{ .idx = 3, .expect = 6 });
    //               ^ ^  ^
    //               1 3  6
}

/// Returns the line number at the specified index in `input`. Line numbers
/// start from 1.
pub fn countLineNum(input: []const u8, index: usize) usize {
    if (input.len == 0) return 1;
    if (index == 0 and input[0] == '\n') return 1; // spacial case
    const until = @min(input.len, index); // normalize
    var line_num: usize = 1;
    var i: usize = 0;
    while (i < until) : (i += 1) {
        if (input[i] == '\n') line_num += 1;
    }
    return line_num;
}

test "+countLineNum" {
    const expectLine = std.testing.expectEqual;

    try expectLine(1, countLineNum("", 0));
    try expectLine(1, countLineNum("", 100));
    try expectLine(1, countLineNum("\n", 0));
    //                              ^
    try expectLine(2, countLineNum("\n", 1));
    //                                ^
    try expectLine(2, countLineNum("\n", 100));
    //                                ^
    try expectLine(2, countLineNum("\n\n", 1));
    //                                ^
    try expectLine(3, countLineNum("\n\n", 2));
    //                                  ^
    try expectLine(1, countLineNum("l1\nl2\nl3", 0));
    //                              ^
    try expectLine(2, countLineNum("l1\nl2\nl3", 3));
    //                                  ^
    try expectLine(3, countLineNum("l1\nl2\nl3", 6));
    //                                      ^
}

/// Represents the result of a single-line reading.
const LineInfo = struct {
    line: ?[]const u8,
    index_pos: usize,
    line_num: usize,
};

/// Reads a line from the input starting at the specified index.
///
/// Returns:
/// * Line at the specified index.
/// * Index position within the current line.
/// * Line number if `detect_line_num` is true; otherwise, `0`.
///
/// If index position exceeds the current line length, the index is either on a
/// new line or at the end of the stream (EOF).
pub fn readLine(
    input: []const u8,
    index: usize,
    detect_line_num: bool,
) LineInfo {
    if (index > input.len)
        return .{ .line = null, .index_pos = 0, .line_num = 0 };
    const line_start = indexOfLineStart(input, index);
    const line_end = indexOfLineEnd(input, index);
    const index_pos = index - line_start;
    return .{
        .line = input[line_start..line_end],
        .index_pos = index_pos,
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
            input: []const u8,
            index: usize,
            detect_line_num: bool,
            expect_line: ?[]const u8,
            expect: struct {
                pos: usize,
                ln: usize,
            },
        ) !void {
            const actual_line = readLine(input, index, detect_line_num);
            if (expect_line != null and actual_line.line != null)
                try t.expectEqualStrings(expect_line.?, actual_line.line.?)
            else
                try t.expectEqual(expect_line, actual_line.line);
            try t.expectEqual(expect.pos, actual_line.index_pos);
            try t.expectEqual(expect.ln, actual_line.line_num);
        }
    }.run;

    //      |input| |idx| |detect_ln| |expect_line| |expect items|
    try case("", 0, false, "", .{ .pos = 0, .ln = 0 });
    try case("", 0, true, "", .{ .pos = 0, .ln = 1 });
    try case("", 100, false, null, .{ .pos = 0, .ln = 0 });

    try case("\n", 0, true, "", .{ .pos = 0, .ln = 1 });
    //        ^
    try case("\n", 1, true, "", .{ .pos = 0, .ln = 2 });
    //          ^
    try case("\none", 4, true, "one", .{ .pos = 3, .ln = 2 });
    //             ^
    try case("\n", 100, true, null, .{ .pos = 0, .ln = 0 });
    //           ^+
    try case("one", 100, true, null, .{ .pos = 0, .ln = 0 });
    //            ^+
    try case("one", 0, false, "one", .{ .pos = 0, .ln = 0 });
    //        ^
    try case("one", 2, true, "one", .{ .pos = 2, .ln = 1 });
    //          ^
    try case("one\n", 0, false, "one", .{ .pos = 0, .ln = 0 });
    //        ^
    try case("one\n", 2, true, "one", .{ .pos = 2, .ln = 1 });
    //          ^
    try case("one\n", 3, true, "one", .{ .pos = 3, .ln = 1 });
    //           ^
    try case("one\ntwo", 3, true, "one", .{ .pos = 3, .ln = 1 });
    //           ^
    try case("one\ntwo", 4, true, "two", .{ .pos = 0, .ln = 2 });
    //             ^
    try case("one\ntwo", 6, true, "two", .{ .pos = 2, .ln = 2 });
    //               ^
}

/// Represents the result of multi-line reading.
pub const LinesInfo = struct {
    lines: [][]const u8,
    first_line_num: usize,
    curr_line_pos: usize,
    index_pos: usize,
};

/// Implementation function. Reads lines in both directions.
fn readLinesImpl(
    comptime mode: enum { forward, backward },
    buf: [][]const u8,
    input: []const u8,
    index: usize,
    amount: usize,
    detect_line_num: bool,
) LinesInfo {
    if (index > input.len or buf.len == 0 or amount == 0)
        return .{
            .lines = buf[0..0],
            .first_line_num = 0,
            .curr_line_pos = 0,
            .index_pos = 0,
        };

    var line_start = indexOfLineStart(input, index);
    var line_end = indexOfLineEnd(input, index);
    const index_pos = index - line_start;

    var s = stack.initFromSliceEmpty([]const u8, buf);
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
    if (mode == .backward) slice.reverseSlice(s.slice());

    return .{
        .lines = s.slice(),
        .curr_line_pos = if (mode == .backward) s.slice().len -| 1 else 0,
        .index_pos = index_pos,
        .first_line_num = blk: {
            if (detect_line_num) {
                const first_line = s.slice()[0];
                const first_line_start = slice.indexOfSliceStart(input, first_line);
                break :blk countLineNum(input, first_line_start);
            } else break :blk 0;
        },
    };
}

test "+readLinesImpl" {
    const t = std.testing;

    const case = struct {
        fn run(
            comptime mode: enum { forward, backward },
            input: []const u8,
            index: usize,
            amount: usize,
            detect_ln: bool,
            expect_ln: anytype,
            expect: struct {
                clp: usize,
                pos: usize,
                fln: usize,
            },
        ) !void {
            var buf: [32][]const u8 = undefined;
            const m = if (mode == .forward) .forward else .backward;
            const actual_lines = readLinesImpl(m, &buf, input, index, amount, detect_ln);
            const expect_lines: [std.meta.fields(@TypeOf(expect_ln)).len][]const u8 = expect_ln;
            try t.expectEqual(expect_lines.len, actual_lines.lines.len);
            for (expect_lines, actual_lines.lines) |e, a| try t.expectEqualStrings(e, a);
            try t.expectEqual(expect.clp, actual_lines.curr_line_pos);
            try t.expectEqual(expect.pos, actual_lines.index_pos);
            try t.expectEqual(expect.fln, actual_lines.first_line_num);
        }
    }.run;

    const input = "first\nsecond\nthird\n";
    //             ^0   ^5      ^12    ^18
    //                      ^8(rel_pos:2)

    // forward
    //                      |idx| |amt| |detect_ln| |expect items|
    try case(.forward, input, 0, 0, false, .{}, .{ .pos = 0, .clp = 0, .fln = 0 });
    try case(.forward, input, 0, 1, false, .{"first"}, .{ .pos = 0, .clp = 0, .fln = 0 });
    try case(.forward, input, 3, 1, false, .{"first"}, .{ .pos = 3, .clp = 0, .fln = 0 });
    try case(.forward, input, 5, 1, false, .{"first"}, .{ .pos = 5, .clp = 0, .fln = 0 });
    try case(.forward, input, 6, 1, false, .{"second"}, .{ .pos = 0, .clp = 0, .fln = 0 });
    try case(.forward, input, 12, 1, false, .{"second"}, .{ .pos = 6, .clp = 0, .fln = 0 });
    try case(.forward, input, 8, 2, false, .{ "second", "third" }, .{ .pos = 2, .clp = 0, .fln = 0 });
    try case(.forward, input, 17, 2, false, .{ "third", "" }, .{ .pos = 4, .clp = 0, .fln = 0 });
    // edge cases
    try case(.forward, input, 19, 2, false, .{""}, .{ .pos = 0, .clp = 0, .fln = 0 });
    try case(.forward, input, 100, 2, false, .{}, .{ .pos = 0, .clp = 0, .fln = 0 });

    // backward
    //
    try case(.backward, input, 0, 0, false, .{}, .{ .pos = 0, .clp = 0, .fln = 0 });
    try case(.backward, input, 0, 1, false, .{"first"}, .{ .pos = 0, .clp = 0, .fln = 0 });
    try case(.backward, input, 3, 1, false, .{"first"}, .{ .pos = 3, .clp = 0, .fln = 0 });
    try case(.backward, input, 5, 1, false, .{"first"}, .{ .pos = 5, .clp = 0, .fln = 0 });
    try case(.backward, input, 6, 1, false, .{"second"}, .{ .pos = 0, .clp = 0, .fln = 0 });
    try case(.backward, input, 12, 1, false, .{"second"}, .{ .pos = 6, .clp = 0, .fln = 0 });
    try case(.backward, input, 8, 2, false, .{ "first", "second" }, .{ .pos = 2, .clp = 1, .fln = 0 });
    try case(.backward, input, 17, 2, false, .{ "second", "third" }, .{ .pos = 4, .clp = 1, .fln = 0 });

    // automatic line number detection
    try case(.forward, input, 0, 0, true, .{}, .{ .pos = 0, .clp = 0, .fln = 0 });
    try case(.forward, input, 5, 1, true, .{"first"}, .{ .pos = 5, .clp = 0, .fln = 1 });
    try case(.forward, input, 6, 1, true, .{"second"}, .{ .pos = 0, .clp = 0, .fln = 2 });
    try case(.forward, input, 8, 2, true, .{ "second", "third" }, .{ .pos = 2, .clp = 0, .fln = 2 });
    try case(.forward, input, 19, 2, true, .{""}, .{ .pos = 0, .clp = 0, .fln = 4 });

    try case(.backward, input, 0, 0, true, .{}, .{ .pos = 0, .clp = 0, .fln = 0 });
    try case(.backward, input, 6, 1, true, .{"second"}, .{ .pos = 0, .clp = 0, .fln = 2 });
    try case(.backward, input, 8, 2, true, .{ "first", "second" }, .{ .pos = 2, .clp = 1, .fln = 1 });
    try case(.backward, input, 17, 2, true, .{ "second", "third" }, .{ .pos = 4, .clp = 1, .fln = 2 });
    try case(.backward, input, 19, 2, true, .{ "third", "" }, .{ .pos = 0, .clp = 1, .fln = 3 });
}

pub const ReadMode = union(enum) {
    /// Read a specified amount of lines, moving backward.
    backward: usize,
    /// Read a specified amount of lines, moving forward.
    forward: usize,
    /// Read a specified amount of lines in both directions.
    /// Backward first, then forward. Current line is in backward range.
    bi: struct { backward: usize, forward: usize },
    /// Reads a specified range of lines around the cursor, distributing range
    /// within available input boundaries.
    range_soft: usize,
    /// Reads a specified range of lines around the cursor, cutting off lines
    /// that fall outside the available input boundaries.
    range_hard: usize,
};

pub fn readLines(
    buf: [][]const u8,
    input: []const u8,
    index: usize,
    detect_line_num: bool,
    mode: ReadMode,
) LinesInfo {
    if (index > input.len or buf.len == 0) return .{
        .lines = buf[0..0],
        .first_line_num = 0,
        .curr_line_pos = 0,
        .index_pos = 0,
    };
    switch (mode) {
        .forward => return readLinesImpl(.forward, buf, input, index, mode.forward, detect_line_num),
        .backward => return readLinesImpl(.backward, buf, input, index, mode.backward, detect_line_num),
        .bi => {
            const backward = readLinesImpl(.backward, buf, input, index, mode.bi.backward, detect_line_num);
            const backward_empty = backward.lines.len == 0;
            const next_index = b: {
                if (backward_empty) break :b index else {
                    const curr_line = backward.lines[backward.curr_line_pos];
                    break :b slice.indexOfSliceEnd(input, curr_line) + 1;
                }
            };
            const buf_left = buf[backward.lines.len..];
            const forward = readLinesImpl(.forward, buf_left, input, next_index, mode.bi.forward, detect_line_num);
            return .{
                .lines = buf[0 .. backward.lines.len + forward.lines.len],
                .curr_line_pos = backward.curr_line_pos,
                .first_line_num = if (backward_empty) forward.first_line_num else backward.first_line_num,
                .index_pos = if (backward_empty) forward.index_pos else backward.index_pos,
            };
        },
        inline .range_soft, .range_hard => |range, range_mode| {
            switch (range) {
                0 => return .{
                    .lines = buf[0..0],
                    .first_line_num = 0,
                    .curr_line_pos = 0,
                    .index_pos = 0,
                },
                1 => return readLinesImpl(.forward, buf, input, index, 1, detect_line_num),
                else => {
                    // calculate the amount to read both backward and forward.
                    const rshift_even = true; // hardcoded for now
                    // for range=4: true => 1back, 1curr, 2for; false => 2back, 1curr, 1for
                    const read = ReadMode{
                        .bi = if (range & 1 == 0) .{ // even
                            .backward = if (rshift_even) range / 2 else range / 2 + 1,
                            .forward = if (rshift_even) range / 2 else range / 2 - 1,
                        } else .{ // odd
                            .backward = range / 2 + 1, // backward includes current line
                            .forward = range / 2,
                        },
                    };
                    switch (range_mode) {
                        .range_hard => {
                            return readLines(buf, input, index, detect_line_num, read);
                        },
                        .range_soft => {
                            // 1. read the planned number of lines backward and forward
                            const info = readLines(buf, input, index, detect_line_num, read);
                            const total_read = info.lines.len;
                            const total_read_plan = read.bi.backward + read.bi.forward;
                            const total_read_left = total_read_plan - total_read;
                            const read_backward = info.curr_line_pos + 1;
                            const read_forward = info.lines.len - info.curr_line_pos;
                            const buf_left = buf[total_read..];

                            if (buf_left.len == 0 or total_read_left == 0 or
                                (read_backward < read.bi.backward and read_forward < read.bi.forward))
                                return info; // no space left or no lines left to read

                            // 2. compensate for any deficit
                            if (read_backward < read.bi.backward) { // deficit in backward read, compensate by reading forward
                                const rightmost_line_read = info.lines[info.lines.len -| 1];
                                const next_rightmost_index = slice.indexOfSliceEnd(input, rightmost_line_read) + 1;
                                const compensated = readLinesImpl(.forward, buf_left, input, next_rightmost_index, total_read_left, detect_line_num);
                                return .{
                                    .lines = buf[0 .. total_read + compensated.lines.len],
                                    .curr_line_pos = info.curr_line_pos,
                                    .first_line_num = info.first_line_num,
                                    .index_pos = info.index_pos,
                                };
                            } else { // deficit in forward read, compensate by reading backward
                                const leftmost_line_read = info.lines[0]; // safe, index <= input.len always produces at least one line
                                const next_leftmost_index = slice.indexOfSliceStart(input, leftmost_line_read) -| 1;
                                const compensated = readLinesImpl(.backward, buf_left, input, next_leftmost_index, total_read_left, detect_line_num);
                                _ = compensated; // autofix
                                @panic("not implemented");
                            }
                        },
                        else => unreachable,
                    }
                },
            }
        },
    }
}

test "+readLines" {
    const t = std.testing;

    const case = struct {
        fn run(
            input: []const u8,
            index: usize,
            detect_ln: bool,
            mode: ReadMode,
            expect_lns: anytype,
            expect: struct { pos: usize, clp: usize, fln: usize },
        ) !void {
            var buf: [32][]const u8 = undefined;
            const actual = readLines(&buf, input, index, detect_ln, mode);
            const expect_lines: [std.meta.fields(@TypeOf(expect_lns)).len][]const u8 = expect_lns;
            try t.expectEqual(expect_lines.len, actual.lines.len);
            for (expect_lines, actual.lines) |e, a| try t.expectEqualStrings(e, a);
            try t.expectEqual(expect.clp, actual.curr_line_pos);
            try t.expectEqual(expect.pos, actual.index_pos);
            try t.expectEqual(expect.fln, actual.first_line_num);
        }
    }.run;

    const input = "one\ntwo\nthree\nfour\n";
    //             ^0 ^3   ^7     ^13   ^18

    // bidirectional read
    //
    try case(input, 0, true, .{ .bi = .{ .backward = 0, .forward = 0 } }, .{}, .{ .pos = 0, .clp = 0, .fln = 0 });
    try case(input, 100, true, .{ .bi = .{ .backward = 10, .forward = 10 } }, .{}, .{ .pos = 0, .clp = 0, .fln = 0 });

    try case(input, 8, false, .{ .bi = .{ .backward = 1, .forward = 0 } }, .{"three"}, .{ .pos = 0, .clp = 0, .fln = 0 });
    try case(input, 8, true, .{ .bi = .{ .backward = 1, .forward = 0 } }, .{"three"}, .{ .pos = 0, .clp = 0, .fln = 3 });
    try case(input, 8, false, .{ .bi = .{ .backward = 0, .forward = 1 } }, .{"three"}, .{ .pos = 0, .clp = 0, .fln = 0 });
    try case(input, 8, true, .{ .bi = .{ .backward = 0, .forward = 1 } }, .{"three"}, .{ .pos = 0, .clp = 0, .fln = 3 });

    try case(input, 12, false, .{ .bi = .{ .backward = 1, .forward = 0 } }, .{"three"}, .{ .pos = 4, .clp = 0, .fln = 0 });
    try case(input, 12, false, .{ .bi = .{ .backward = 0, .forward = 1 } }, .{"three"}, .{ .pos = 4, .clp = 0, .fln = 0 });
    try case(input, 12, true, .{ .bi = .{ .backward = 2, .forward = 0 } }, .{ "two", "three" }, .{ .pos = 4, .clp = 1, .fln = 2 });
    try case(input, 12, true, .{ .bi = .{ .backward = 0, .forward = 2 } }, .{ "three", "four" }, .{ .pos = 4, .clp = 0, .fln = 3 });

    try case(input, 19, true, .{ .bi = .{ .backward = 5, .forward = 5 } }, .{
        "one",
        "two",
        "three",
        "four",
        "",
    }, .{ .pos = 0, .clp = 4, .fln = 1 });
    try case(input, 0, true, .{ .bi = .{ .backward = 5, .forward = 5 } }, .{
        "one",
        "two",
        "three",
        "four",
        "",
    }, .{ .pos = 0, .clp = 0, .fln = 1 });

    // range hard
    //
    try case(input, 0, true, .{ .range_hard = 1 }, .{"one"}, .{ .pos = 0, .clp = 0, .fln = 1 });
    //                                                ^
    try case(input, 19, true, .{ .range_hard = 1 }, .{""}, .{ .pos = 0, .clp = 0, .fln = 5 });
    //                                                ^
    try case(input, 0, true, .{ .range_hard = 2 }, .{ "one", "two" }, .{ .pos = 0, .clp = 0, .fln = 1 });
    //                                                 ^
    try case(input, 19, true, .{ .range_hard = 2 }, .{""}, .{ .pos = 0, .clp = 0, .fln = 5 });
    //                                                ^
    try case(input, 0, true, .{ .range_hard = 3 }, .{ "one", "two" }, .{ .pos = 0, .clp = 0, .fln = 1 });
    //                                                 ^
    try case(input, 19, true, .{ .range_hard = 3 }, .{ "four", "" }, .{ .pos = 0, .clp = 1, .fln = 4 });
    //                                                         ^
    try case(input, 10, true, .{ .range_hard = 3 }, .{ "two", "three", "four" }, .{ .pos = 2, .clp = 1, .fln = 2 });
    //                                                           ^
    try case(input, 6, true, .{ .range_hard = 4 }, .{ "one", "two", "three", "four" }, .{ .pos = 2, .clp = 1, .fln = 1 });
    //                                                          ^
    try case(input, 15, true, .{ .range_hard = 4 }, .{ "three", "four", "" }, .{ .pos = 1, .clp = 1, .fln = 3 });
    //                                                            ^

    // range soft
    //
    try case(input, 0, true, .{ .range_soft = 1 }, .{"one"}, .{ .pos = 0, .clp = 0, .fln = 1 });
    //                                                ^
    try case(input, 0, true, .{ .range_soft = 3 }, .{ "one", "two", "three" }, .{ .pos = 0, .clp = 0, .fln = 1 });
    //                                                 ^
    try case(input, 9, true, .{ .range_soft = 3 }, .{ "two", "three", "four" }, .{ .pos = 1, .clp = 1, .fln = 2 });
    //                                                         ^
    try case(input, 0, true, .{ .range_soft = 4 }, .{ "one", "two", "three", "four" }, .{ .pos = 0, .clp = 0, .fln = 1 });
    //                                                 ^

}
