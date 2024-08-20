// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

//! Public API:
//! - indexOfLineStart
//! - indexOfLineEnd
//! - countIntLen
//! - countLineNum
//! - readLine
//! - readLines

const std = @import("std");
const stack = @import("stack.zig");
const slice = @import("slice.zig");

/// Retrieves the ending position of a line. If `index > input.len`, returns
/// `input.len`.
pub fn indexOfLineEnd(input: []const u8, index: usize) usize {
    if (index >= input.len or input.len == 0) return input.len;
    var i: usize = index;
    while (i < input.len) : (i += 1) {
        if (input[i] == '\n') break;
    }
    return i;
}

/// Retrieves the starting position of a line. If `index > input.len`, returns
/// `input.len`.
pub fn indexOfLineStart(input: []const u8, index: usize) usize {
    if (index >= input.len or input.len == 0) return input.len;
    var i: usize = index;
    if (i == 0 and input[i] == '\n') return 0;
    if (input[i] == '\n') i -|= 1; // step back from line end
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
        pub fn start(input: []const u8, args: struct { index: usize, expect: usize }) !void {
            try t.expectEqual(args.expect, indexOfLineStart(input, args.index));
        }

        pub fn end__(input: []const u8, args: struct { index: usize, expect: usize }) !void {
            try t.expectEqual(args.expect, indexOfLineEnd(input, args.index));
        }
    };

    try case.start("", .{ .index = 0, .expect = 0 });
    try case.end__("", .{ .index = 0, .expect = 0 });

    try case.start("", .{ .index = 100, .expect = 0 });
    try case.end__("", .{ .index = 100, .expect = 0 });

    try case.start("\n", .{ .index = 0, .expect = 0 });
    try case.end__("\n", .{ .index = 0, .expect = 0 });
    //              ^
    try case.start("\n\n", .{ .index = 0, .expect = 0 });
    try case.end__("\n\n", .{ .index = 0, .expect = 0 });
    //              ^
    try case.start("\n\n", .{ .index = 1, .expect = 1 });
    try case.end__("\n\n", .{ .index = 1, .expect = 1 });
    //                ^
    try case.start("\n\n\n", .{ .index = 1, .expect = 1 });
    try case.end__("\n\n\n", .{ .index = 1, .expect = 1 });
    //                ^
    try case.start("line", .{ .index = 2, .expect = 0 });
    try case.end__("line", .{ .index = 2, .expect = 4 });
    //                ^
    try case.start("line", .{ .index = 4, .expect = 4 });
    try case.end__("line", .{ .index = 6, .expect = 4 });
    //                   ^
    try case.start("\nc", .{ .index = 1, .expect = 1 });
    try case.end__("\nc", .{ .index = 1, .expect = 2 });
    //                ^
    try case.start("\nline2\n", .{ .index = 3, .expect = 1 });
    try case.end__("\nline2\n", .{ .index = 3, .expect = 6 });
    //                ^ ^  ^
    //                1 3  6
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

const LineInfo = struct {
    line: []const u8,
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
    const idx = if (index > input.len) input.len else index; // normalize
    const line_start = indexOfLineStart(input, idx);
    const line_end = indexOfLineEnd(input, idx);
    const index_pos = idx - line_start;
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
            expect_line: []const u8,
            expect: struct {
                pos: usize,
                ln: usize,
            },
        ) !void {
            const actual_line = readLine(input, index, detect_line_num);
            try t.expectEqualStrings(expect_line, actual_line.line);
            try t.expectEqual(expect.pos, actual_line.index_pos);
            try t.expectEqual(expect.ln, actual_line.line_num);
        }
    }.run;

    //      |input| |idx| |detect_ln| |expect_line| |expect items|
    try case("", 0, false, "", .{ .pos = 0, .ln = 0 });
    try case("", 0, true, "", .{ .pos = 0, .ln = 1 });
    try case("\n", 0, true, "", .{ .pos = 0, .ln = 1 });
    //        ^
    try case("\n", 1, true, "", .{ .pos = 0, .ln = 2 });
    //          ^
    try case("\n", 100, true, "", .{ .pos = 0, .ln = 2 });
    //           ^+
    try case("one", 100, true, "", .{ .pos = 0, .ln = 1 });
    //            ^+
    try case("one", 0, false, "one", .{ .pos = 0, .ln = 0 });
    //        ^
    try case("one", 1, true, "one", .{ .pos = 1, .ln = 1 });
    //         ^
    try case("one", 2, true, "one", .{ .pos = 2, .ln = 1 });
    //          ^
    try case("one\n", 0, false, "one", .{ .pos = 0, .ln = 0 });
    //        ^
    try case("one\n", 1, true, "one", .{ .pos = 1, .ln = 1 });
    //         ^
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

/// Represents the result of a single-direction line reading.
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
    if (index >= input.len or buf.len == 0 or amount == 0)
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
            try t.expectEqual(expect.pos, actual_lines.index_pos);
            try t.expectEqual(expect.fln, actual_lines.first_line_num);
        }
    }.run;

    const input = "first\nsecond\nthird\n";
    //             ^0   ^5      ^12    ^18
    //                      ^8(rel_pos:2)

    //                      |idx| |amt| |detect_ln| |expect items|
    try case(.forward, input, 0, 0, false, .{}, .{ .pos = 0, .fln = 0 });
    try case(.forward, input, 0, 1, false, .{"first"}, .{ .pos = 0, .fln = 0 });
    try case(.forward, input, 3, 1, false, .{"first"}, .{ .pos = 3, .fln = 0 });
    try case(.forward, input, 5, 1, false, .{"first"}, .{ .pos = 5, .fln = 0 });
    try case(.forward, input, 6, 1, false, .{"second"}, .{ .pos = 0, .fln = 0 });
    try case(.forward, input, 12, 1, false, .{"second"}, .{ .pos = 6, .fln = 0 });
    try case(.forward, input, 8, 2, false, .{ "second", "third" }, .{ .pos = 2, .fln = 0 });
    try case(.forward, input, 17, 2, false, .{ "third", "" }, .{ .pos = 4, .fln = 0 });
    try case(.forward, input, 100, 2, false, .{}, .{ .pos = 0, .fln = 0 });

    try case(.backward, input, 0, 0, false, .{}, .{ .pos = 0, .fln = 0 });
    try case(.backward, input, 0, 1, false, .{"first"}, .{ .pos = 0, .fln = 0 });
    try case(.backward, input, 3, 1, false, .{"first"}, .{ .pos = 3, .fln = 0 });
    try case(.backward, input, 5, 1, false, .{"first"}, .{ .pos = 5, .fln = 0 });
    try case(.backward, input, 6, 1, false, .{"second"}, .{ .pos = 0, .fln = 0 });
    try case(.backward, input, 12, 1, false, .{"second"}, .{ .pos = 6, .fln = 0 });
    try case(.backward, input, 8, 2, false, .{ "first", "second" }, .{ .pos = 2, .fln = 0 });
    try case(.backward, input, 17, 2, false, .{ "second", "third" }, .{ .pos = 4, .fln = 0 });

    // automatic line number detection
    try case(.forward, input, 0, 0, true, .{}, .{ .pos = 0, .fln = 0 });
    try case(.forward, input, 5, 1, true, .{"first"}, .{ .pos = 5, .fln = 1 });
    try case(.forward, input, 6, 1, true, .{"second"}, .{ .pos = 0, .fln = 2 });
    try case(.forward, input, 8, 2, true, .{ "second", "third" }, .{ .pos = 2, .fln = 2 });

    try case(.backward, input, 0, 0, true, .{}, .{ .pos = 0, .fln = 0 });
    try case(.backward, input, 6, 1, true, .{"second"}, .{ .pos = 0, .fln = 2 });
    try case(.backward, input, 8, 2, true, .{ "first", "second" }, .{ .pos = 2, .fln = 1 });
    try case(.backward, input, 17, 2, true, .{ "second", "third" }, .{ .pos = 4, .fln = 2 });
}

pub const ReadMode = union(enum) {
    backward: usize,
    forward: usize,
    /// backward first, current line is in backward range
    bi: struct { backward: usize, forward: usize },
    range_soft: usize,
    range_hard: usize,
};

pub fn readLines(
    buf: [][]const u8,
    input: []const u8,
    index: usize,
    detect_line_num: bool,
    mode: ReadMode,
) LinesInfo {
    if (buf.len == 0) return .{
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
        else => @panic("unimplemented"),
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

    const input = "one\ntwo\nthree\nfour\nfive";
    //             ^0 ^3   ^7     ^13   ^18  ^22

    try case(input, 0, false, .{ .bi = .{ .backward = 0, .forward = 0 } }, .{}, .{ .pos = 0, .clp = 0, .fln = 0 });
    try case(input, 100, false, .{ .bi = .{ .backward = 0, .forward = 0 } }, .{}, .{ .pos = 0, .clp = 0, .fln = 0 });
    try case(input, 100, false, .{ .bi = .{ .backward = 10, .forward = 10 } }, .{}, .{ .pos = 0, .clp = 0, .fln = 0 });

    try case(input, 8, false, .{ .bi = .{ .backward = 1, .forward = 0 } }, .{"three"}, .{ .pos = 0, .clp = 0, .fln = 0 });
    try case(input, 8, true, .{ .bi = .{ .backward = 1, .forward = 0 } }, .{"three"}, .{ .pos = 0, .clp = 0, .fln = 3 });

    try case(input, 8, false, .{ .bi = .{ .backward = 0, .forward = 1 } }, .{"three"}, .{ .pos = 0, .clp = 0, .fln = 0 });
    try case(input, 8, true, .{ .bi = .{ .backward = 0, .forward = 1 } }, .{"three"}, .{ .pos = 0, .clp = 0, .fln = 3 });

    try case(input, 12, false, .{ .bi = .{ .backward = 1, .forward = 0 } }, .{"three"}, .{ .pos = 4, .clp = 0, .fln = 0 });
    try case(input, 12, false, .{ .bi = .{ .backward = 0, .forward = 1 } }, .{"three"}, .{ .pos = 4, .clp = 0, .fln = 0 });

    try case(input, 12, true, .{ .bi = .{ .backward = 2, .forward = 0 } }, .{ "two", "three" }, .{ .pos = 4, .clp = 1, .fln = 2 });
    try case(input, 12, true, .{ .bi = .{ .backward = 0, .forward = 2 } }, .{ "three", "four" }, .{ .pos = 4, .clp = 0, .fln = 3 });

    try case(input, 22, true, .{
        .bi = .{ .backward = 5, .forward = 5 },
    }, .{ "one", "two", "three", "four", "five" }, .{ .pos = 3, .clp = 4, .fln = 1 });
    try case(input, 0, true, .{
        .bi = .{ .backward = 5, .forward = 5 },
    }, .{ "one", "two", "three", "four", "five" }, .{ .pos = 0, .clp = 0, .fln = 1 });
}
