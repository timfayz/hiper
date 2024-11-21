// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

//! Public API:
//! - indexOfLineStart()
//! - indexOfLineEnd()
//! - countLineNum()
//! - CurrLineNum
//! - ReadLineInfo
//! - readLine()
//! - ReadRequest
//! - ReadLinesInfo
//! - readLines()

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

test "+indexOfLineEnd, indexOfLineStart" {
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

/// Counts the line number in `input` up to the specified `end` index,
/// starting from `start` and reading forward. If `start` is greater than `end`,
/// they are reversed automatically. Returns 1 if `start == end`. Line numbering
/// begins at 1.
pub fn countLineNumForward(input: []const u8, start: usize, end: usize) usize {
    if (input.len == 0) return 1;

    var from: usize, var until = if (start < end) .{ start, end } else .{ end, start };
    if (until >= input.len) until = input.len; // normalize

    var line_num: usize = 1;
    while (from < until) : (from += 1) {
        if (input[from] == '\n') line_num += 1;
    }
    return line_num;
}

/// Counts the line number in `input` up to the specified `end` index,
/// starting from `start` and reading backward. If `end` is greater than `start`,
/// they are reversed automatically. Returns 1 if `start == end`. Line numbering
/// begins at 1.
pub fn countLineNumBackward(input: []const u8, start: usize, end: usize) usize {
    if (input.len == 0) return 1;

    var from: usize, const until = if (start > end) .{ start, end } else .{ end, start };

    var line_num: usize = 1;
    if (from >= input.len) {
        // special case: count empty trailing line
        if (input[input.len - 1] == '\n') line_num += 1;
        from = input.len - 1; // normalize
    }
    // special case: avoid double-counting the current line
    if (input[from] == '\n') line_num -= 1;

    while (true) : (from -|= 1) {
        if (input[from] == '\n') line_num += 1;
        if (from <= until) break;
    }
    return line_num;
}

test "+countLineNumForward, countLineNumBackward" {
    const expectLine = std.testing.expectEqual;

    // forward
    //
    try expectLine(1, countLineNumForward("", 0, 0));
    try expectLine(1, countLineNumForward("", 0, 100));
    try expectLine(1, countLineNumForward("", 100, 0));
    try expectLine(1, countLineNumForward("", 100, 100));
    try expectLine(2, countLineNumForward("\n", 0, 1));
    //                                     ^ ^
    try expectLine(2, countLineNumForward("\n", 0, 100));
    //                                     ^ ^
    try expectLine(2, countLineNumForward("\n", 100, 0)); // reversed
    //                                     ^ ^
    try expectLine(2, countLineNumForward("\n\n", 0, 1));
    //                                     ^ ^
    try expectLine(3, countLineNumForward("\n\n", 0, 2));
    //                                     ^   ^
    try expectLine(2, countLineNumForward("\n\n", 1, 2)); // partial range
    //                                       ^ ^
    try expectLine(2, countLineNumForward("\n\n", 2, 1)); // reversed
    //                                       ^ ^
    try expectLine(1, countLineNumForward("l1\nl2\nl3", 0, 0));
    //                                     ^
    try expectLine(2, countLineNumForward("l1\nl2\nl3", 0, 3));
    //                                     ^   ^
    try expectLine(3, countLineNumForward("l1\nl2\nl3", 0, 6));
    //                                     ^       ^
    try expectLine(3, countLineNumForward("l1\nl2\nl3", 2, 6)); // partial range
    //                                       ^     ^
    try expectLine(3, countLineNumForward("l1\nl2\nl3", 6, 2)); // reversed
    //                                       ^     ^
    try expectLine(3, countLineNumForward("l1\nl2\nl3", 0, 7)); // full range
    //                                     ^        ^
    try expectLine(3, countLineNumForward("l1\nl2\nl3", 7, 0)); // reversed
    //                                     ^        ^

    // backward
    //
    try expectLine(1, countLineNumBackward("", 0, 0));
    try expectLine(1, countLineNumBackward("", 0, 100));
    try expectLine(1, countLineNumBackward("", 100, 0));
    try expectLine(1, countLineNumBackward("", 100, 100));
    try expectLine(2, countLineNumBackward("\n", 0, 1));
    //                                      ^ ^
    try expectLine(2, countLineNumBackward("\n", 0, 100));
    //                                      ^ ^
    try expectLine(2, countLineNumBackward("\n", 100, 0)); // reversed
    //                                      ^ ^
    try expectLine(2, countLineNumBackward("\n\n", 0, 1));
    //                                      ^ ^
    try expectLine(3, countLineNumBackward("\n\n", 0, 2));
    //                                      ^   ^
    try expectLine(2, countLineNumBackward("\n\n", 1, 2)); // partial range
    //                                        ^ ^
    try expectLine(2, countLineNumBackward("\n\n", 2, 1)); // reversed
    //                                        ^ ^
    try expectLine(1, countLineNumBackward("l1\nl2\nl3", 0, 0));
    //                                      ^
    try expectLine(2, countLineNumBackward("l1\nl2\nl3", 0, 3));
    //                                      ^   ^
    try expectLine(3, countLineNumBackward("l1\nl2\nl3", 0, 6));
    //                                      ^       ^
    try expectLine(3, countLineNumBackward("l1\nl2\nl3", 2, 6)); // partial range
    //                                        ^     ^
    try expectLine(3, countLineNumBackward("l1\nl2\nl3", 6, 2)); // reversed
    //                                        ^     ^
    try expectLine(3, countLineNumBackward("l1\nl2\nl3", 0, 7)); // full range
    //                                      ^        ^
    try expectLine(3, countLineNumBackward("l1\nl2\nl3", 7, 0)); // reversed
    //                                      ^        ^
}

/// Specifies how the current line number is determined during reading.
pub const CurrLineNum = union(enum) {
    /// Sets a specific line number.
    set: usize,
    /// Detects the line number automatically.
    detect,
};

/// The result of a single-line reading.
pub const ReadLineInfo = struct {
    /// The retrieved line, or `null` if no line was read.
    line: ?[]const u8,
    /// The detected or specified line number (starting from 1).
    /// If no line was read, this value is `0`.
    line_num: usize,
    /// The index position within the current line.
    index_pos: usize,
};

/// Retrieves a line from the input starting at the specified index. Returns the
/// retrieved line, the line number (starting from 1; detected if `curr_ln` is
/// `.detect`, otherwise set to the specified value), and the index position
/// within the line. If the position exceeds the current line's length, the index
/// will point to either the next line or the end of the stream (EOF). For more
/// details about the returned data, see `ReadLineInfo`.
pub fn readLine(
    input: []const u8,
    index: usize,
    curr_ln: CurrLineNum,
) ReadLineInfo {
    if (index > input.len)
        return .{ .line = null, .index_pos = 0, .line_num = 0 };
    const line_start = indexOfLineStart(input, index);
    const line_end = indexOfLineEnd(input, index);
    const index_pos = index - line_start;
    return .{
        .line = input[line_start..line_end],
        .index_pos = index_pos,
        .line_num = if (curr_ln == .detect)
            countLineNumForward(input, 0, line_start)
        else
            curr_ln.set,
    };
}

test "+readLine" {
    const t = std.testing;

    const case = struct {
        fn run(
            input: []const u8,
            index: usize,
            curr_ln: CurrLineNum,
            expect_line: ?[]const u8,
            expect: struct {
                pos: usize,
                ln: usize,
            },
        ) !void {
            const actual_line = readLine(input, index, curr_ln);
            if (expect_line != null and actual_line.line != null)
                try t.expectEqualStrings(expect_line.?, actual_line.line.?)
            else
                try t.expectEqual(expect_line, actual_line.line);
            try t.expectEqual(expect.pos, actual_line.index_pos);
            try t.expectEqual(expect.ln, actual_line.line_num);
        }
    }.run;

    // format:
    // try case(|input|, |index|, |curr_ln|, |expect_line|, |expect items|)

    // automatic line number detection
    //
    try case("", 0, .detect, "", .{ .pos = 0, .ln = 1 });
    try case("\n", 0, .detect, "", .{ .pos = 0, .ln = 1 });
    //        ^
    try case("\n", 1, .detect, "", .{ .pos = 0, .ln = 2 });
    //          ^
    try case("\none", 4, .detect, "one", .{ .pos = 3, .ln = 2 });
    //             ^
    try case("\n", 100, .detect, null, .{ .pos = 0, .ln = 0 });
    //           ^+
    try case("one", 100, .detect, null, .{ .pos = 0, .ln = 0 });
    //            ^+
    try case("one", 0, .{ .set = 42 }, "one", .{ .pos = 0, .ln = 42 });
    //        ^
    try case("one", 2, .detect, "one", .{ .pos = 2, .ln = 1 });
    //          ^
    try case("one\n", 2, .detect, "one", .{ .pos = 2, .ln = 1 });
    //          ^
    try case("one\n", 3, .detect, "one", .{ .pos = 3, .ln = 1 });
    //           ^
    try case("one\n", 4, .detect, "", .{ .pos = 0, .ln = 2 });
    //             ^
    try case("one\ntwo", 3, .detect, "one", .{ .pos = 3, .ln = 1 });
    //           ^
    try case("one\ntwo", 4, .detect, "two", .{ .pos = 0, .ln = 2 });
    //             ^
    try case("one\ntwo", 6, .detect, "two", .{ .pos = 2, .ln = 2 });
    //               ^

    // manual line number assignment
    //
    try case("", 0, .{ .set = 42 }, "", .{ .pos = 0, .ln = 42 });
    try case("", 100, .{ .set = 42 }, null, .{ .pos = 0, .ln = 0 });
    try case("one\n", 1, .{ .set = 42 }, "one", .{ .pos = 1, .ln = 42 });
    //         ^
    try case("one\n", 4, .{ .set = 42 }, "", .{ .pos = 0, .ln = 42 });
    //             ^
}

/// Defines the basic direction for multi-line reading.
const ReadDirection = enum { forward, backward };

/// Specifies the amount and direction for multi-line reading.
pub const ReadRequest = union(enum) {
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

    /// Extends the requested amount by adding another request's value. Coerces
    /// the result into a bidirectional `ReadRequest`.
    pub fn extend(req: ReadRequest, extra: ReadRequest) ReadRequest {
        return ReadRequest{ .bi = .{
            .backward = req.amountBackward() + extra.amountBackward(),
            .forward = req.amountForward() + extra.amountForward(),
        } };
    }

    /// The total amount of lines requested, regardless of direction.
    pub fn amountTotal(req: ReadRequest) usize {
        return switch (req) {
            inline .backward, .forward, .range_soft, .range_hard => |amt| amt,
            .bi => |amt| amt.backward + amt.forward,
        };
    }

    /// The amount of lines requested in the backward direction.
    pub fn amountBackward(req: ReadRequest) usize {
        return switch (req) {
            .backward => |amt| amt,
            .forward => 0,
            .bi => |amt| amt.backward,
            else => 0,
        };
    }

    /// The amount of lines requested in the forward direction.
    pub fn amountForward(req: ReadRequest) usize {
        return switch (req) {
            .backward => 0,
            .forward => |amt| amt,
            .bi => |amt| amt.forward,
            else => 0,
        };
    }

    /// Creates a bidirectional `ReadRequest` with a specified range,
    /// distributing lines evenly between forward and backward directions.
    /// For even ranges, the range is shifted right by one line relative to
    /// the current one.
    pub inline fn range(len: usize) ReadRequest {
        const rshift_even = true; // hardcoded for now
        return ReadRequest{
            .bi = if (len & 1 == 0) .{ // even
                .backward = if (rshift_even) len / 2 else len / 2 + 1,
                .forward = if (rshift_even) len / 2 else len / 2 -| 1,
            } else .{ // odd
                .backward = len / 2 + 1, // backward includes current line
                .forward = len / 2,
            },
        };
    }
};

/// The result of multi-line reading.
pub const ReadLinesInfo = struct {
    /// Retrieved lines.
    lines: [][]const u8,
    /// The detected or specified line number of the first element in `lines`
    /// (starting from 1). If no lines were read, this value is `0`.
    first_line_num: usize,
    /// The position of the current line where the index was located.
    curr_line_pos: usize,
    /// The index position within the current line.
    index_pos: usize,

    /// Initializes an empty `ReadLinesInfo` structure with the provided buffer.
    pub inline fn initEmpty(buf: [][]const u8) ReadLinesInfo {
        return .{ .lines = buf[0..0], .first_line_num = 0, .curr_line_pos = 0, .index_pos = 0 };
    }

    /// Checks if no lines have been read.
    pub inline fn isEmpty(r: *const ReadLinesInfo) bool {
        return r.lines.len == 0;
    }

    /// The first line number of lines read.
    pub inline fn firstLineNum(info: *const ReadLinesInfo) usize {
        return info.first_line_num;
    }

    /// The first line number of lines read.
    pub inline fn lastLineNum(info: *const ReadLinesInfo) usize {
        return info.first_line_num +| info.linesTotal();
    }

    /// The current line number of lines read.
    pub inline fn currLineNum(info: *const ReadLinesInfo) usize {
        return info.first_line_num +| info.curr_line_pos;
    }

    /// The total number of lines read.
    pub inline fn linesTotal(info: *const ReadLinesInfo) usize {
        return info.lines.len;
    }

    /// The number of lines read before the current line.
    pub inline fn linesBeforeCurr(info: *const ReadLinesInfo) usize {
        return info.curr_line_pos;
    }

    /// The number of lines read after the current line.
    pub inline fn linesAfterCurr(info: *const ReadLinesInfo) usize {
        return info.lines.len -| info.curr_line_pos -| 1;
    }

    /// The number of lines read in the backward direction based on the
    /// specified request. Returns `0` if the request is forward-only.
    pub inline fn linesReadBackward(info: *const ReadLinesInfo, req: ReadRequest) usize {
        return switch (req) {
            .forward => 0,
            .backward => info.linesTotal(),
            else => info.linesBeforeCurr() + 1,
        };
    }

    /// The number of lines read in the forward direction based on the
    /// specified request. Returns `0` if the request is backward-only.
    pub inline fn linesReadForward(info: *const ReadLinesInfo, req: ReadRequest) usize {
        return switch (req) {
            .forward => info.linesTotal(),
            .backward => 0,
            else => info.linesAfterCurr(),
        };
    }

    /// Calculates the remaining number of lines to read based on the request’s total amount.
    pub inline fn leftTotal(info: *const ReadLinesInfo, req: ReadRequest) usize {
        return req.amountTotal() - info.linesTotal();
    }

    /// Calculates the remaining number of lines to read in the backward direction.
    pub inline fn leftBackward(info: *const ReadLinesInfo, req: ReadRequest) usize {
        return req.amountBackward() - info.linesReadBackward(req);
    }

    /// Calculates the remaining number of lines to read in the forward direction.
    pub inline fn leftForward(info: *const ReadLinesInfo, req: ReadRequest) usize {
        return req.amountForward() - info.linesReadForward(req);
    }

    /// Returns the current line being read.
    pub inline fn currLine(info: *const ReadLinesInfo) []const u8 {
        return info.lines[info.curr_line_pos];
    }

    /// Returns the first line in the collection of lines read.
    pub inline fn firstLine(info: *const ReadLinesInfo) []const u8 {
        return info.lines[0];
    }

    /// Returns the last line in the collection of lines read.
    pub inline fn lastLine(info: *const ReadLinesInfo) []const u8 {
        return info.lines[info.lines.len -| 1];
    }

    /// Finds the index position in `input` where the last read line ends. Add
    /// one to this index to start reading the next line in the forward direction.
    pub inline fn indexLastRead(info: *const ReadLinesInfo, input: []const u8) usize {
        return slice.indexOfEnd(input, info.lastLine());
    }

    /// Finds the index position in `input` where the first read line starts.
    /// Subtract one from this index to start reading the next line in the
    /// backward direction.
    pub inline fn indexFirstRead(info: *const ReadLinesInfo, input: []const u8) usize {
        return slice.indexOfStart(input, info.firstLine());
    }
};

/// Retrieves lines from the input starting at the specified index, based on the
/// requested direction and amount. Returns the retrieved lines, the line number
/// of the first line (starting from 1; detected if `curr_ln` is `.detect`,
/// otherwise set to the specified value), the index of the current line, and the
/// position within that line. If the position exceeds the current line's length,
/// the index will point to either a new line or the end of the stream (EOF).
/// For more details about the returned data, see `ReadLinesInfo`.
pub fn readLines(
    buf: [][]const u8,
    input: []const u8,
    index: usize,
    curr_ln: CurrLineNum,
    request: ReadRequest,
) ReadLinesInfo {
    switch (request) {
        .forward => |amt| return readLinesImpl(.forward, buf, input, index, curr_ln, amt),
        .backward => |amt| return readLinesImpl(.backward, buf, input, index, curr_ln, amt),
        .bi => |amt| {
            if (amt.forward == 0 and amt.backward == 0) return ReadLinesInfo.initEmpty(buf);
            // backward only
            if (amt.forward == 0)
                return readLinesImpl(.backward, buf, input, index, curr_ln, amt.backward);
            // forward only
            if (amt.backward == 0)
                return readLinesImpl(.forward, buf, input, index, curr_ln, amt.forward);
            // both direction
            var backward = readLinesImpl(.backward, buf, input, index, curr_ln, amt.backward);
            // if backward read failed, no reason to read forward
            if (backward.isEmpty())
                return backward;
            // if not, prepare reading forward
            const buf_left = buf[backward.linesTotal()..];
            if (buf_left.len == 0)
                return backward;
            const next_index = backward.indexLastRead(input) +| 1;
            const next_curr_ln: CurrLineNum = .{ .set = 0 }; // ignore
            const forward = readLinesImpl(.forward, buf_left, input, next_index, next_curr_ln, amt.forward);
            // merge both directions
            backward.lines = buf[0 .. backward.linesTotal() + forward.linesTotal()];
            return backward;
        },
        inline .range_soft, .range_hard => |amt, req| {
            const range = ReadRequest.range(amt);
            switch (req) {
                .range_hard => return readLines(buf, input, index, curr_ln, range),
                .range_soft => {
                    // read planned amount backward/forward
                    var planned = readLines(buf, input, index, curr_ln, range);
                    // nothing to read
                    if (planned.isEmpty()) return planned;
                    // no reading deficit
                    const amt_left = planned.leftTotal(range);
                    if (amt_left == 0) return planned;
                    // no space to compensate deficit
                    const buf_left = buf[planned.linesTotal()..];
                    if (buf_left.len == 0) return planned;
                    // calc deficit direction and boundaries
                    const comp_dir: ReadDirection =
                        if (planned.leftBackward(range) > 0) .forward else .backward;
                    const next_read_back = planned.indexFirstRead(input) -| 1;
                    const next_read_forw = planned.indexLastRead(input) +| 1;
                    // compensate deficit only if possible
                    if (comp_dir == .forward and next_read_forw >= input.len or
                        comp_dir == .backward and next_read_back == 0)
                        return planned;
                    // perform compensate read
                    const comp = if (comp_dir == .forward)
                        readLinesImpl(.forward, buf_left, input, next_read_forw, .{
                            .set = 0, // ignore
                        }, amt_left)
                    else
                        readLinesImpl(.backward, buf_left, input, next_read_back, .{
                            .set = 0, // ignore
                        }, amt_left);
                    // merge results
                    planned.lines = buf[0 .. planned.linesTotal() + comp.linesTotal()];
                    // fix lines order if deficit was backward
                    if (comp_dir == .backward) {
                        slice.moveSegLeft([]const u8, planned.lines, comp.lines) catch
                            return planned;
                        planned.first_line_num = planned.first_line_num -| comp.linesTotal();
                        planned.curr_line_pos = planned.curr_line_pos +| comp.linesTotal();
                    }
                    return planned;
                },
                else => unreachable,
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
            line_num: CurrLineNum,
            request: ReadRequest,
            expect_lns: anytype,
            expect: struct { pos: usize, clp: usize, fln: usize },
        ) !void {
            var buf: [32][]const u8 = undefined;
            const actual = readLines(&buf, input, index, line_num, request);
            const expect_lines: [std.meta.fields(@TypeOf(expect_lns)).len][]const u8 = expect_lns;
            t.expectEqual(expect_lines.len, actual.lines.len) catch |err| {
                for (actual.lines) |l| std.log.err("\"{s}\"", .{l});
                return err;
            };
            for (expect_lines, actual.lines) |e, a| {
                t.expectEqualStrings(e, a) catch |err| {
                    for (actual.lines) |l| std.log.err("\"{s}\"", .{l});
                    return err;
                };
            }
            try t.expectEqual(expect.clp, actual.curr_line_pos);
            try t.expectEqual(expect.pos, actual.index_pos);
            try t.expectEqual(expect.fln, actual.first_line_num);
        }
    }.run;

    // format:
    // try case(|input|, |index|, |curr_line_num|, |read_request|, |expected result items|)

    const input = "one\ntwo\nthree\nfour\n";
    //             ^0 ^3   ^7     ^13   ^18

    // .forward
    //
    // test reading with an empty buffer
    {
        const info = readLines(&[0][]const u8{}, input, 2, .{ .set = 42 }, .{ .forward = 2 });
        try t.expectEqual(0, info.lines.len);
        try t.expectEqual(0, info.curr_line_pos);
        try t.expectEqual(0, info.index_pos);
        try t.expectEqual(0, info.first_line_num);
    }
    // test reading out of bounds
    try case(input, 100, .detect, .{ .forward = 2 }, .{}, .{ .pos = 0, .clp = 0, .fln = 0 });
    // test reading zero amount
    try case(input, 0, .detect, .{ .forward = 0 }, .{}, .{ .pos = 0, .clp = 0, .fln = 0 });
    // test manual line number assignment
    try case(input, 0, .{ .set = 42 }, .{ .forward = 1 }, .{"one"}, .{ .pos = 0, .clp = 0, .fln = 42 });
    try case(input, 2, .{ .set = 42 }, .{ .forward = 1 }, .{"one"}, .{ .pos = 2, .clp = 0, .fln = 42 });
    try case(input, 4, .{ .set = 42 }, .{ .forward = 1 }, .{"two"}, .{ .pos = 0, .clp = 0, .fln = 42 });
    try case(input, 7, .{ .set = 42 }, .{ .forward = 1 }, .{"two"}, .{ .pos = 3, .clp = 0, .fln = 42 });
    try case(input, 10, .{ .set = 42 }, .{ .forward = 3 }, .{ "three", "four", "" }, .{ .pos = 2, .clp = 0, .fln = 42 });
    try case(input, 17, .{ .set = 42 }, .{ .forward = 2 }, .{ "four", "" }, .{ .pos = 3, .clp = 0, .fln = 42 });
    try case(input, 19, .{ .set = 42 }, .{ .forward = 2 }, .{""}, .{ .pos = 0, .clp = 0, .fln = 42 });
    // test automatic line number detection
    try case(input, 2, .detect, .{ .forward = 1 }, .{"one"}, .{ .pos = 2, .clp = 0, .fln = 1 });
    try case(input, 7, .detect, .{ .forward = 1 }, .{"two"}, .{ .pos = 3, .clp = 0, .fln = 2 });
    try case(input, 10, .detect, .{ .forward = 2 }, .{ "three", "four" }, .{ .pos = 2, .clp = 0, .fln = 3 });
    try case(input, 19, .detect, .{ .forward = 2 }, .{""}, .{ .pos = 0, .clp = 0, .fln = 5 });

    // .backward
    //
    // test reading with an empty buffer
    {
        const info = readLines(&[0][]const u8{}, input, 2, .{ .set = 42 }, .{ .backward = 2 });
        try t.expectEqual(0, info.lines.len);
        try t.expectEqual(0, info.curr_line_pos);
        try t.expectEqual(0, info.index_pos);
        try t.expectEqual(0, info.first_line_num);
    }
    // test reading out of bounds
    try case(input, 100, .detect, .{ .backward = 2 }, .{}, .{ .pos = 0, .clp = 0, .fln = 0 });
    try case(input, 100, .{ .set = 42 }, .{ .backward = 2 }, .{}, .{ .pos = 0, .clp = 0, .fln = 0 });
    // test reading zero amount
    try case(input, 0, .detect, .{ .backward = 0 }, .{}, .{ .pos = 0, .clp = 0, .fln = 0 });
    try case(input, 0, .{ .set = 42 }, .{ .backward = 0 }, .{}, .{ .pos = 0, .clp = 0, .fln = 0 });
    // test manual line number assignment
    try case(input, 0, .{ .set = 42 }, .{ .backward = 1 }, .{"one"}, .{ .pos = 0, .clp = 0, .fln = 42 });
    try case(input, 2, .{ .set = 42 }, .{ .backward = 1 }, .{"one"}, .{ .pos = 2, .clp = 0, .fln = 42 });
    try case(input, 4, .{ .set = 42 }, .{ .backward = 1 }, .{"two"}, .{ .pos = 0, .clp = 0, .fln = 42 });
    try case(input, 7, .{ .set = 42 }, .{ .backward = 1 }, .{"two"}, .{ .pos = 3, .clp = 0, .fln = 42 });
    try case(input, 10, .{ .set = 42 }, .{ .backward = 2 }, .{ "two", "three" }, .{ .pos = 2, .clp = 1, .fln = 41 });
    try case(input, 17, .{ .set = 42 }, .{ .backward = 3 }, .{ "two", "three", "four" }, .{ .pos = 3, .clp = 2, .fln = 40 });
    try case(input, 19, .{ .set = 42 }, .{ .backward = 2 }, .{ "four", "" }, .{ .pos = 0, .clp = 1, .fln = 41 });
    // test automatic line number detection
    try case(input, 2, .detect, .{ .backward = 1 }, .{"one"}, .{ .pos = 2, .clp = 0, .fln = 1 });
    try case(input, 7, .detect, .{ .backward = 1 }, .{"two"}, .{ .pos = 3, .clp = 0, .fln = 2 });
    try case(input, 17, .detect, .{ .backward = 3 }, .{ "two", "three", "four" }, .{ .pos = 3, .clp = 2, .fln = 2 });
    try case(input, 19, .detect, .{ .backward = 1 }, .{""}, .{ .pos = 0, .clp = 0, .fln = 5 });

    // .bi
    //
    // test reading with an empty buffer
    {
        const info = readLines(&[0][]const u8{}, input, 2, .{ .set = 42 }, .{ .bi = .{ .backward = 10, .forward = 10 } });
        try t.expectEqual(0, info.lines.len);
        try t.expectEqual(0, info.curr_line_pos);
        try t.expectEqual(0, info.index_pos);
        try t.expectEqual(0, info.first_line_num);
    }
    // test reading out of bounds
    try case(input, 100, .detect, .{ .bi = .{ .backward = 10, .forward = 10 } }, .{}, .{ .pos = 0, .clp = 0, .fln = 0 });
    // test reading zero amount
    try case(input, 0, .detect, .{ .bi = .{ .backward = 0, .forward = 0 } }, .{}, .{ .pos = 0, .clp = 0, .fln = 0 });
    // test manual line number assignment
    try case(input, 0, .{ .set = 42 }, .{ .bi = .{ .backward = 5, .forward = 5 } }, .{
        "one",
        "two",
        "three",
        "four",
        "",
    }, .{ .pos = 0, .clp = 0, .fln = 42 });
    try case(input, 7, .{ .set = 42 }, .{ .bi = .{ .backward = 1, .forward = 0 } }, .{"two"}, .{ .pos = 3, .clp = 0, .fln = 42 });
    try case(input, 7, .{ .set = 42 }, .{ .bi = .{ .backward = 0, .forward = 1 } }, .{"two"}, .{ .pos = 3, .clp = 0, .fln = 42 }); // !!!
    try case(input, 10, .{ .set = 42 }, .{ .bi = .{ .backward = 1, .forward = 0 } }, .{"three"}, .{ .pos = 2, .clp = 0, .fln = 42 });
    try case(input, 10, .{ .set = 42 }, .{ .bi = .{ .backward = 0, .forward = 1 } }, .{"three"}, .{ .pos = 2, .clp = 0, .fln = 42 });
    try case(input, 10, .{ .set = 42 }, .{ .bi = .{ .backward = 1, .forward = 1 } }, .{ "three", "four" }, .{ .pos = 2, .clp = 0, .fln = 42 });
    try case(input, 10, .{ .set = 42 }, .{ .bi = .{ .backward = 2, .forward = 2 } }, .{ "two", "three", "four", "" }, .{ .pos = 2, .clp = 1, .fln = 41 });
    try case(input, 19, .{ .set = 42 }, .{ .bi = .{ .backward = 5, .forward = 5 } }, .{
        "one",
        "two",
        "three",
        "four",
        "",
    }, .{ .pos = 0, .clp = 4, .fln = 38 });
    // test automatic line number detection
    try case(input, 0, .detect, .{ .bi = .{ .backward = 5, .forward = 5 } }, .{
        "one",
        "two",
        "three",
        "four",
        "",
    }, .{ .pos = 0, .clp = 0, .fln = 1 });
    try case(input, 7, .detect, .{ .bi = .{ .backward = 1, .forward = 0 } }, .{"two"}, .{ .pos = 3, .clp = 0, .fln = 2 });
    try case(input, 7, .detect, .{ .bi = .{ .backward = 0, .forward = 1 } }, .{"two"}, .{ .pos = 3, .clp = 0, .fln = 2 });
    try case(input, 10, .detect, .{ .bi = .{ .backward = 2, .forward = 0 } }, .{ "two", "three" }, .{ .pos = 2, .clp = 1, .fln = 2 });
    try case(input, 10, .detect, .{ .bi = .{ .backward = 0, .forward = 2 } }, .{ "three", "four" }, .{ .pos = 2, .clp = 0, .fln = 3 });
    try case(input, 10, .detect, .{ .bi = .{ .backward = 2, .forward = 2 } }, .{ "two", "three", "four", "" }, .{ .pos = 2, .clp = 1, .fln = 2 });
    try case(input, 19, .detect, .{ .bi = .{ .backward = 5, .forward = 5 } }, .{
        "one",
        "two",
        "three",
        "four",
        "",
    }, .{ .pos = 0, .clp = 4, .fln = 1 });

    // .range_hard
    //
    // test reading with an empty buffer
    {
        const info = readLines(&[0][]const u8{}, input, 2, .{ .set = 42 }, .{ .range_hard = 5 });
        try t.expectEqual(0, info.lines.len);
        try t.expectEqual(0, info.curr_line_pos);
        try t.expectEqual(0, info.index_pos);
        try t.expectEqual(0, info.first_line_num);
    }
    // test reading out of bounds
    try case(input, 100, .detect, .{ .range_hard = 5 }, .{}, .{ .pos = 0, .clp = 0, .fln = 0 });
    // test reading zero amount
    try case(input, 0, .detect, .{ .range_hard = 0 }, .{}, .{ .pos = 0, .clp = 0, .fln = 0 });
    // test manual line number assignment
    try case(input, 0, .{ .set = 42 }, .{ .range_hard = 1 }, .{"one"}, .{ .pos = 0, .clp = 0, .fln = 42 });
    try case(input, 19, .{ .set = 42 }, .{ .range_hard = 1 }, .{""}, .{ .pos = 0, .clp = 0, .fln = 42 });
    try case(input, 0, .{ .set = 42 }, .{ .range_hard = 2 }, .{ "one", "two" }, .{ .pos = 0, .clp = 0, .fln = 42 });
    try case(input, 19, .{ .set = 42 }, .{ .range_hard = 2 }, .{""}, .{ .pos = 0, .clp = 0, .fln = 42 });
    try case(input, 0, .{ .set = 42 }, .{ .range_hard = 3 }, .{ "one", "two" }, .{ .pos = 0, .clp = 0, .fln = 42 });
    try case(input, 19, .{ .set = 42 }, .{ .range_hard = 3 }, .{ "four", "" }, .{ .pos = 0, .clp = 1, .fln = 41 });
    try case(input, 10, .{ .set = 42 }, .{ .range_hard = 3 }, .{ "two", "three", "four" }, .{ .pos = 2, .clp = 1, .fln = 41 });
    try case(input, 6, .{ .set = 42 }, .{ .range_hard = 4 }, .{ "one", "two", "three", "four" }, .{ .pos = 2, .clp = 1, .fln = 41 });
    try case(input, 15, .{ .set = 42 }, .{ .range_hard = 4 }, .{ "three", "four", "" }, .{ .pos = 1, .clp = 1, .fln = 41 });
    // test automatic line number detection
    try case(input, 0, .detect, .{ .range_hard = 1 }, .{"one"}, .{ .pos = 0, .clp = 0, .fln = 1 });
    try case(input, 19, .detect, .{ .range_hard = 1 }, .{""}, .{ .pos = 0, .clp = 0, .fln = 5 });
    try case(input, 0, .detect, .{ .range_hard = 2 }, .{ "one", "two" }, .{ .pos = 0, .clp = 0, .fln = 1 });
    try case(input, 19, .detect, .{ .range_hard = 2 }, .{""}, .{ .pos = 0, .clp = 0, .fln = 5 });
    try case(input, 0, .detect, .{ .range_hard = 3 }, .{ "one", "two" }, .{ .pos = 0, .clp = 0, .fln = 1 });
    try case(input, 19, .detect, .{ .range_hard = 3 }, .{ "four", "" }, .{ .pos = 0, .clp = 1, .fln = 4 });
    try case(input, 10, .detect, .{ .range_hard = 3 }, .{ "two", "three", "four" }, .{ .pos = 2, .clp = 1, .fln = 2 });
    try case(input, 6, .detect, .{ .range_hard = 4 }, .{ "one", "two", "three", "four" }, .{ .pos = 2, .clp = 1, .fln = 1 });
    try case(input, 15, .detect, .{ .range_hard = 4 }, .{ "three", "four", "" }, .{ .pos = 1, .clp = 1, .fln = 3 });

    // .range_soft
    //
    // test reading with an empty buffer
    {
        const info = readLines(&[0][]const u8{}, input, 2, .{ .set = 42 }, .{ .range_soft = 1 });
        try t.expectEqual(0, info.lines.len);
        try t.expectEqual(0, info.curr_line_pos);
        try t.expectEqual(0, info.index_pos);
        try t.expectEqual(0, info.first_line_num);
    }
    // test reading out of bounds
    try case(input, 100, .detect, .{ .range_soft = 5 }, .{}, .{ .pos = 0, .clp = 0, .fln = 0 });
    // test reading zero amount
    try case(input, 0, .detect, .{ .range_soft = 0 }, .{}, .{ .pos = 0, .clp = 0, .fln = 0 });
    // test reading deficit compensation (right direction)
    try case(input, 0, .detect, .{ .range_soft = 1 }, .{"one"}, .{ .pos = 0, .clp = 0, .fln = 1 });
    try case(input, 0, .detect, .{ .range_soft = 3 }, .{ "one", "two", "three" }, .{ .pos = 0, .clp = 0, .fln = 1 });
    try case(input, 9, .detect, .{ .range_soft = 3 }, .{ "two", "three", "four" }, .{ .pos = 1, .clp = 1, .fln = 2 });
    try case(input, 0, .detect, .{ .range_soft = 4 }, .{ "one", "two", "three", "four" }, .{ .pos = 0, .clp = 0, .fln = 1 });

    // test reading deficit compensation (left direction)
    try case(input, 19, .detect, .{ .range_soft = 4 }, .{ "two", "three", "four", "" }, .{ .pos = 0, .clp = 3, .fln = 2 });
    try case(input, 18, .detect, .{ .range_soft = 4 }, .{ "two", "three", "four", "" }, .{ .pos = 4, .clp = 2, .fln = 2 });
    //                                                                         ^
    try case(input, 13, .detect, .{ .range_soft = 4 }, .{ "two", "three", "four", "" }, .{ .pos = 5, .clp = 1, .fln = 2 });
    //                                                                 ^
}

/// Implementation function. Reads lines in both directions.
fn readLinesImpl(
    comptime dir: ReadDirection,
    buf: [][]const u8,
    input: []const u8,
    index: usize,
    curr_ln: CurrLineNum,
    amount: usize,
) ReadLinesInfo {
    if (index > input.len or buf.len == 0 or amount == 0)
        return ReadLinesInfo.initEmpty(buf);

    var line_start = indexOfLineStart(input, index);
    var line_end = indexOfLineEnd(input, index);
    const index_pos = index - line_start;

    var s = stack.initFromSliceEmpty([]const u8, buf);
    s.push(input[line_start..line_end]) catch unreachable; // current line

    var i: usize = amount - 1;
    while (i != 0 and !s.full()) : (i -= 1) {
        switch (dir) {
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
    if (dir == .backward) slice.reverse(s.slice());
    const curr_line_pos = if (dir == .backward) s.slice().len -| 1 else 0;

    return .{
        .lines = s.slice(),
        .curr_line_pos = curr_line_pos,
        .index_pos = index_pos,
        .first_line_num = blk: {
            if (curr_ln == .detect) {
                const first_line = s.slice()[0];
                const first_line_start = slice.indexOfStart(input, first_line);
                break :blk countLineNumForward(input, 0, first_line_start);
            } else break :blk curr_ln.set -| curr_line_pos;
        },
    };
}
