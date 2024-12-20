// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

//! Public API:
//! - indexOfLineStart()
//! - indexOfLineEnd()
//! - countLineNumForw()
//! - countLineNumBack()
//! - LineNumMode
//! - ReadLine
//! - readLine()
//! - ReadMode
//! - ReadLines
//! - readLines()

const std = @import("std");
const num = @import("num.zig");
const stack = @import("stack.zig");
const slice = @import("slice.zig");

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

/// Retrieves the ending position of a line.
pub fn indexOfLineEnd(input: []const u8, index: usize) usize {
    if (index >= input.len or input.len == 0) return input.len;
    var end: usize = index;
    while (end < input.len) : (end += 1) {
        if (input[end] == '\n') break;
    }
    return end;
}

test indexOfLineStart {
    const equal = std.testing.expectEqual;
    try equal(0, indexOfLineStart("", 0));
    try equal(0, indexOfLineStart("", 100));
    try equal(0, indexOfLineStart("line", 0));
    try equal(0, indexOfLineStart("line", 4));
    try equal(0, indexOfLineStart("line", 8));
    try equal(0, indexOfLineStart("\n", 0));
    try equal(1, indexOfLineStart("\n\n", 1));
    try equal(0, indexOfLineStart("line\n", 4));
    try equal(1, indexOfLineStart("\nline", 2));
    try equal(1, indexOfLineStart("\nline", 3));
}

test indexOfLineEnd {
    const equal = std.testing.expectEqual;
    try equal(0, indexOfLineEnd("", 0));
    try equal(0, indexOfLineEnd("", 100));
    try equal(4, indexOfLineEnd("line", 0));
    try equal(4, indexOfLineEnd("line", 4));
    try equal(4, indexOfLineEnd("line", 8));
    try equal(0, indexOfLineEnd("\n", 0));
    try equal(0, indexOfLineEnd("\n\n", 0));
    try equal(0, indexOfLineEnd("\nline", 0));
    try equal(4, indexOfLineEnd("line\n", 1));
    try equal(4, indexOfLineEnd("line\n", 2));
}

/// Counts the line number in `input` up to the specified `end` index, starting
/// from `start` and reading forward. If `start > end`, they are reversed
/// automatically. Returns 1 if `start == end`. Line numbering begins at 1.
pub fn countLineNumForw(input: []const u8, start: usize, end: usize) usize {
    if (input.len == 0) return 1;

    var from: usize, var until = if (start < end) .{ start, end } else .{ end, start };
    if (until >= input.len) until = input.len; // normalize

    var line_num: usize = 1;
    while (from < until) : (from += 1) {
        if (input[from] == '\n') line_num += 1;
    }
    return line_num;
}

/// Counts the line number in `input` up to the specified `end` index, starting
// from `start` and reading backward. If `end > start`, they are reversed
// automatically. Returns 1 if `start == end`. Line numbering begins at 1.
pub fn countLineNumBack(input: []const u8, start: usize, end: usize) usize {
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

test countLineNumForw {
    const equal = std.testing.expectEqual;

    try equal(1, countLineNumForw("", 0, 0));
    try equal(1, countLineNumForw("", 0, 100));
    try equal(1, countLineNumForw("", 100, 0));
    try equal(1, countLineNumForw("", 100, 100));
    try equal(2, countLineNumForw("\n", 0, 1));
    //                             ^ ^
    try equal(2, countLineNumForw("\n", 0, 100));
    //                             ^   ^
    try equal(2, countLineNumForw("\n", 100, 0)); // reversed
    //                             ^   ^
    try equal(2, countLineNumForw("\n\n", 0, 1));
    //                             ^ ^
    try equal(3, countLineNumForw("\n\n", 0, 2));
    //                             ^   ^
    try equal(2, countLineNumForw("\n\n", 1, 2)); // partial range
    //                               ^ ^
    try equal(2, countLineNumForw("\n\n", 2, 1)); // reversed
    //                               ^ ^
    try equal(1, countLineNumForw("l1\nl2\nl3", 0, 0));
    //                             ^
    try equal(2, countLineNumForw("l1\nl2\nl3", 0, 3));
    //                             ^   ^
    try equal(3, countLineNumForw("l1\nl2\nl3", 0, 6));
    //                             ^       ^
    try equal(3, countLineNumForw("l1\nl2\nl3", 2, 6)); // partial range
    //                               ^     ^
    try equal(3, countLineNumForw("l1\nl2\nl3", 6, 2)); // reversed
    //                               ^     ^
    try equal(3, countLineNumForw("l1\nl2\nl3", 0, 7)); // full range
    //                             ^        ^
    try equal(3, countLineNumForw("l1\nl2\nl3", 7, 0)); // reversed
    //                             ^        ^
}

test countLineNumBack {
    const equal = std.testing.expectEqual;

    try equal(1, countLineNumBack("", 0, 0));
    try equal(1, countLineNumBack("", 0, 100));
    try equal(1, countLineNumBack("", 100, 0));
    try equal(1, countLineNumBack("", 100, 100));
    try equal(2, countLineNumBack("\n", 0, 1));
    //                             ^ ^
    try equal(2, countLineNumBack("\n", 0, 100));
    //                             ^   ^
    try equal(2, countLineNumBack("\n", 100, 0)); // reversed
    //                             ^   ^
    try equal(2, countLineNumBack("\n\n", 0, 1));
    //                             ^ ^
    try equal(3, countLineNumBack("\n\n", 0, 2));
    //                             ^   ^
    try equal(2, countLineNumBack("\n\n", 1, 2)); // partial range
    //                               ^ ^
    try equal(2, countLineNumBack("\n\n", 2, 1)); // reversed
    //                               ^ ^
    try equal(1, countLineNumBack("l1\nl2\nl3", 0, 0));
    //                             ^
    try equal(2, countLineNumBack("l1\nl2\nl3", 0, 3));
    //                             ^   ^
    try equal(3, countLineNumBack("l1\nl2\nl3", 0, 6));
    //                             ^       ^
    try equal(3, countLineNumBack("l1\nl2\nl3", 2, 6)); // partial range
    //                               ^     ^
    try equal(3, countLineNumBack("l1\nl2\nl3", 6, 2)); // reversed
    //                               ^     ^
    try equal(3, countLineNumBack("l1\nl2\nl3", 0, 7)); // full range
    //                             ^        ^
    try equal(3, countLineNumBack("l1\nl2\nl3", 7, 0)); // reversed
    //                             ^        ^
}

/// Specifies how the current line number is determined during reading.
pub const LineNumMode = union(enum) {
    /// Sets a specific line number.
    set: usize,
    /// Detects the line number automatically.
    detect,
};

/// The result of a single-line reading.
pub const ReadLine = struct {
    /// The retrieved line, or `null` if no line was read.
    line: ?[]const u8,
    /// The detected or specified line number (starting from 1).
    /// If no line was read, this value is `0`.
    line_num: usize,
    /// The index position within the current line.
    index_pos: usize,
};

/// Retrieves a line from input starting at the given index. Returns the line,
/// line number (1-based, detected or set), and index position within the line.
/// If the position exceeds the line's length, it points to the next line or EOF.
pub fn readLine(
    input: []const u8,
    index: usize,
    curr_ln: LineNumMode,
) ReadLine {
    if (index > input.len)
        return .{ .line = null, .index_pos = 0, .line_num = 0 };
    const line_start = indexOfLineStart(input, index);
    const line_end = indexOfLineEnd(input, index);
    const index_pos = index - line_start;
    return .{
        .line = input[line_start..line_end],
        .index_pos = index_pos,
        .line_num = if (curr_ln == .detect)
            countLineNumForw(input, 0, line_start)
        else
            curr_ln.set,
    };
}

test readLine {
    const equal = std.testing.expectEqualDeep;
    const Info = ReadLine;

    // [.detect]
    try equal(Info{ .line = "", .line_num = 1, .index_pos = 0 }, readLine("", 0, .detect));
    try equal(Info{ .line = null, .line_num = 0, .index_pos = 0 }, readLine("", 100, .detect));
    try equal(Info{ .line = "", .line_num = 1, .index_pos = 0 }, readLine("\n", 0, .detect));
    try equal(Info{ .line = "", .line_num = 2, .index_pos = 0 }, readLine("\n", 1, .detect));
    try equal(Info{ .line = "one", .line_num = 2, .index_pos = 3 }, readLine("\none", 4, .detect));
    try equal(Info{ .line = "one", .line_num = 1, .index_pos = 2 }, readLine("one", 2, .detect));
    try equal(Info{ .line = "one", .line_num = 1, .index_pos = 2 }, readLine("one\n", 2, .detect));
    try equal(Info{ .line = "one", .line_num = 1, .index_pos = 3 }, readLine("one\n", 3, .detect));
    try equal(Info{ .line = "", .line_num = 2, .index_pos = 0 }, readLine("one\n", 4, .detect));
    try equal(Info{ .line = "one", .line_num = 1, .index_pos = 3 }, readLine("one\ntwo", 3, .detect));
    try equal(Info{ .line = "two", .line_num = 2, .index_pos = 0 }, readLine("one\ntwo", 4, .detect));
    try equal(Info{ .line = "two", .line_num = 2, .index_pos = 2 }, readLine("one\ntwo", 6, .detect));

    // [.set = *]
    try equal(Info{ .line = "", .line_num = 42, .index_pos = 0 }, readLine("", 0, .{ .set = 42 }));
    try equal(Info{ .line = null, .line_num = 0, .index_pos = 0 }, readLine("", 100, .{ .set = 42 }));
    try equal(Info{ .line = "one", .line_num = 42, .index_pos = 1 }, readLine("one", 1, .{ .set = 42 }));
    try equal(Info{ .line = "one", .line_num = 42, .index_pos = 1 }, readLine("one\n", 1, .{ .set = 42 }));
    try equal(Info{ .line = "", .line_num = 42, .index_pos = 0 }, readLine("one\n", 4, .{ .set = 42 }));
}

/// Defines the basic direction for multi-line reading.
const ReadDirection = enum { forward, backward };

/// Specifies the amount and direction for multi-line reading.
pub const ReadAmount = union(enum) {
    /// Read lines backward.
    backward: usize,
    /// Read lines forward.
    forward: usize,
    /// Read lines backward first, then forward.
    bi: struct { backward: usize, forward: usize },
    /// Read a range of lines around the cursor within input boundaries.
    range_soft: usize,
    /// Read a range of lines around the cursor, cutting off out-of-bound lines.
    range_hard: usize,

    /// Creates a `.bi`-directional amount with an even line distribution.
    /// Shifts the range right by one line for even lengths.
    pub fn init(len: usize) ReadAmount {
        const rshift_even = true; // hardcoded for now
        return ReadAmount{
            .bi = if (len & 1 == 0) .{ // even
                .backward = if (rshift_even) len / 2 else len / 2 + 1,
                .forward = if (rshift_even) len / 2 else len / 2 -| 1,
            } else .{ // odd
                .backward = len / 2 + 1, // backward includes current line
                .forward = len / 2,
            },
        };
    }

    /// Extends the amount by adding another `ReadAmount` value.
    pub fn extend(self: ReadAmount, extra: ReadAmount) ReadAmount {
        return ReadAmount{ .bi = .{
            .backward = self.amountBackward() + extra.amountBackward(),
            .forward = self.amountForward() + extra.amountForward(),
        } };
    }

    /// The total amount of lines requested, regardless of direction.
    pub fn amountTotal(self: ReadAmount) usize {
        return switch (self) {
            inline .backward, .forward, .range_soft, .range_hard => |amt| amt,
            .bi => |amt| amt.backward + amt.forward,
        };
    }

    /// The amount of lines requested in the backward direction.
    pub fn amountBackward(self: ReadAmount) usize {
        return switch (self) {
            .backward => |amt| amt,
            .forward => 0,
            .bi => |amt| amt.backward,
            else => 0,
        };
    }

    /// The amount of lines requested in the forward direction.
    pub fn amountForward(self: ReadAmount) usize {
        return switch (self) {
            .backward => 0,
            .forward => |amt| amt,
            .bi => |amt| amt.forward,
            else => 0,
        };
    }
};

/// The result of multi-line reading.
pub const ReadLines = struct {
    /// Retrieved lines.
    lines: []const []const u8,
    /// Line number of the first element in `lines` (1-based, 0 if empty).
    first_line_num: usize,
    /// Position of the current line where the index was located.
    curr_line_pos: usize,
    /// Index position within the current line.
    index_pos: usize,

    /// Initializes an empty `ReadLinesInfo` structure with the provided buffer.
    pub fn initEmpty(buf: [][]const u8) ReadLines {
        return .{ .lines = buf[0..0], .first_line_num = 0, .curr_line_pos = 0, .index_pos = 0 };
    }

    /// Checks if no lines have been read.
    pub fn isEmpty(self: *const ReadLines) bool {
        return self.lines.len == 0;
    }

    /// The first line number of the read lines.
    pub fn firstLineNum(self: *const ReadLines) usize {
        return self.first_line_num;
    }

    /// The last line number of the read lines.
    pub fn lastLineNum(self: *const ReadLines) usize {
        return self.first_line_num +| self.linesTotal();
    }

    /// The current line number of the read lines.
    pub fn currLineNum(self: *const ReadLines) usize {
        return self.first_line_num +| self.curr_line_pos;
    }

    /// The total number of the read lines.
    pub fn linesTotal(self: *const ReadLines) usize {
        return self.lines.len;
    }

    /// The number of lines read before the current line.
    pub fn linesBeforeCurr(self: *const ReadLines) usize {
        return self.curr_line_pos;
    }

    /// The number of lines read after the current line.
    pub fn linesAfterCurr(self: *const ReadLines) usize {
        return self.lines.len -| self.curr_line_pos -| 1;
    }

    /// The number of lines read backward (0 if forward-only).
    pub fn linesReadBackward(self: *const ReadLines, amount: ReadAmount) usize {
        return switch (amount) {
            .forward => 0,
            .backward => self.linesTotal(),
            else => self.linesBeforeCurr() + 1,
        };
    }

    /// The number of lines read forward (0 if backward-only).
    pub fn linesReadForward(self: *const ReadLines, amount: ReadAmount) usize {
        return switch (amount) {
            .forward => self.linesTotal(),
            .backward => 0,
            else => self.linesAfterCurr(),
        };
    }

    /// The remaining lines to read based on the total amount.
    pub fn leftTotal(self: *const ReadLines, amount: ReadAmount) usize {
        return amount.amountTotal() - self.linesTotal();
    }

    /// The remaining number of lines to read in the backward direction.
    pub fn leftBackward(self: *const ReadLines, amount: ReadAmount) usize {
        return amount.amountBackward() - self.linesReadBackward(amount);
    }

    /// The remaining number of lines to read in the forward direction.
    pub fn leftForward(self: *const ReadLines, amount: ReadAmount) usize {
        return amount.amountForward() - self.linesReadForward(amount);
    }
    /// The current line being read.
    pub fn currLine(self: *const ReadLines) []const u8 {
        return self.lines[self.curr_line_pos];
    }

    /// The first line of the read collection.
    pub fn firstLine(self: *const ReadLines) []const u8 {
        return self.lines[0];
    }

    /// The last line of the read collection.
    pub fn lastLine(self: *const ReadLines) []const u8 {
        return self.lines[self.lines.len -| 1];
    }

    /// Index where the last read line ends in `input` (for forward reading).
    /// Add 1 to start reading the next line forward.
    pub fn indexLastRead(self: *const ReadLines, input: []const u8) usize {
        return slice.indexOfEnd(input, self.lastLine());
    }

    /// Index where the first read line starts in `input` (for backward reading).
    /// Subtract 1 to start reading the next line backward.
    pub fn indexFirstRead(self: *const ReadLines, input: []const u8) usize {
        return slice.indexOfStart(input, self.firstLine());
    }

    pub fn debugWrite(self: *const ReadLines, writer: anytype) !void {
        for (self.lines, self.first_line_num.., 0..) |line, line_num, i| {
            try writer.print("{d}| {s}", .{ line_num, line });
            if (self.curr_line_pos == i) {
                try writer.print(" [{d}]\n", .{i});
                const line_num_len = num.countIntLen(line_num) + 2;
                try writer.print("{c: >[1]}", .{ '^', line_num_len + self.index_pos + 1 });
            }
            try writer.writeByte('\n');
        }
        if (self.lines.len == 0) {
            try writer.print("{d}|  [{d}]\n", .{ self.first_line_num, self.curr_line_pos });
            const line_num_len = num.countIntLen(self.first_line_num) + 2;
            try writer.print("{[0]c: >[1]} [{[2]d}]\n", .{ '^', line_num_len + self.index_pos + 1, self.index_pos });
        }
    }

    pub fn debugString(self: *const ReadLines, buf: []u8) ![]u8 {
        var fbs = std.io.fixedBufferStream(buf);
        try self.debugWrite(fbs.writer());
        const str = fbs.getWritten();
        return str[0..str.len -| 1]; // remove trailing \n
    }
};

/// Retrieves lines from input starting at the given index based on direction
/// and amount. Returns the lines, first line number (1-based, detected or set),
/// current line index, and position within that line. If the position exceeds
/// the line's length, it points to the next line or EOF.
pub fn readLines(
    buf: [][]const u8,
    input: []const u8,
    index: usize,
    comptime amount: ReadAmount,
    curr_ln: LineNumMode,
) ReadLines {
    switch (amount) {
        .forward => |amt| return readLinesImpl(.forward, buf, input, index, amt, curr_ln),
        .backward => |amt| return readLinesImpl(.backward, buf, input, index, amt, curr_ln),
        .bi => |amt| {
            // backward only
            if (amt.forward == 0)
                return readLinesImpl(.backward, buf, input, index, amt.backward, curr_ln);
            // forward only
            if (amt.backward == 0)
                return readLinesImpl(.forward, buf, input, index, amt.forward, curr_ln);
            // both direction
            var backward = readLinesImpl(.backward, buf, input, index, amt.backward, curr_ln);
            // if backward read failed, no reason to read forward
            if (backward.isEmpty()) return backward;
            // prepare reading forward
            const buf_left = buf[backward.linesTotal()..];
            // no space left
            if (buf_left.len == 0) return backward;
            const next_index = backward.indexLastRead(input) +| 1;
            const next_curr_ln: LineNumMode = .{ .set = 0 }; // ignore
            const forward = readLinesImpl(.forward, buf_left, input, next_index, amt.forward, next_curr_ln);
            // merge both directions
            backward.lines = buf[0 .. backward.linesTotal() + forward.linesTotal()];
            return backward;
        },
        inline .range_soft, .range_hard => |amt, req| {
            const range = comptime ReadAmount.init(amt); // converts into .bi
            switch (req) {
                .range_hard => return readLines(buf, input, index, range, curr_ln),
                .range_soft => {
                    // read planned amount backward/forward
                    var planned = readLines(buf, input, index, range, curr_ln);
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
                        readLinesImpl(.forward, buf_left, input, next_read_forw, amt_left, .{
                            .set = 0, // ignore
                        })
                    else
                        readLinesImpl(.backward, buf_left, input, next_read_back, amt_left, .{
                            .set = 0, // ignore
                        });
                    // merge results
                    const merged = buf[0 .. planned.linesTotal() + comp.linesTotal()];
                    planned.lines = merged;
                    // fix lines order if deficit was backward
                    if (comp_dir == .backward) {
                        slice.moveLeft([]const u8, merged, comp.lines) catch
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

test readLines {
    const equal = std.testing.expectEqualStrings;
    var line_buf: [16][]const u8 = undefined;
    var str_buf: [512]u8 = undefined;
    var empty_buf: [0][]const u8 = undefined;

    const input =
        \\one
        //   ^3
        \\two
        //   ^7
        \\three
        //     ^13
        \\four
        //    ^18
        \\
    ;

    // [.forward] read mode
    {
        // reading with an empty buffer
        try equal(
            \\0|  [0]
            \\   ^ [0]
        , try readLines(&empty_buf, input, 2, .{ .forward = 2 }, .detect).debugString(&str_buf));
        // reading out of bounds
        try equal(
            \\0|  [0]
            \\   ^ [0]
        , try readLines(&line_buf, input, 100, .{ .forward = 2 }, .detect).debugString(&str_buf));
        // reading zero amount
        try equal(
            \\0|  [0]
            \\   ^ [0]
        , try readLines(&line_buf, input, 0, .{ .forward = 0 }, .detect).debugString(&str_buf));
        // manual line numbering
        try equal(
            \\10| one [0]
            \\      ^
        , try readLines(&line_buf, input, 2, .{ .forward = 1 }, .{ .set = 10 }).debugString(&str_buf));
        try equal(
            \\10| two [0]
            \\       ^
        , try readLines(&line_buf, input, 7, .{ .forward = 1 }, .{ .set = 10 }).debugString(&str_buf));
        try equal(
            \\10| three [0]
            \\      ^
            \\11| four
            \\12| 
        , try readLines(&line_buf, input, 10, .{ .forward = 3 }, .{ .set = 10 }).debugString(&str_buf));
        try equal(
            \\10|  [0]
            \\    ^
        , try readLines(&line_buf, input, 19, .{ .forward = 2 }, .{ .set = 10 }).debugString(&str_buf));

        // automatic line numbering
        try equal(
            \\2| two [0]
            \\      ^
        , try readLines(&line_buf, input, 7, .{ .forward = 1 }, .detect).debugString(&str_buf));
        try equal(
            \\5|  [0]
            \\   ^
        , try readLines(&line_buf, input, 19, .{ .forward = 2 }, .detect).debugString(&str_buf));
    }

    // [.backward] read mode
    {
        // reading with an empty buffer
        try equal(
            \\0|  [0]
            \\   ^ [0]
        , try readLines(&empty_buf, input, 2, .{ .backward = 2 }, .{ .set = 10 }).debugString(&str_buf));
        // reading out of bounds
        try equal(
            \\0|  [0]
            \\   ^ [0]
        , try readLines(&line_buf, input, 100, .{ .backward = 2 }, .detect).debugString(&str_buf));
        // reading zero amount
        try equal(
            \\0|  [0]
            \\   ^ [0]
        , try readLines(&line_buf, input, 0, .{ .backward = 0 }, .detect).debugString(&str_buf));
        // manual line numbering
        try equal(
            \\10| one [0]
            \\      ^
        , try readLines(&line_buf, input, 2, .{ .backward = 1 }, .{ .set = 10 }).debugString(&str_buf));
        try equal(
            \\10| two [0]
            \\       ^
        , try readLines(&line_buf, input, 7, .{ .backward = 1 }, .{ .set = 10 }).debugString(&str_buf));
        try equal(
            \\8| one
            \\9| two
            \\10| three [2]
            \\      ^
        , try readLines(&line_buf, input, 10, .{ .backward = 3 }, .{ .set = 10 }).debugString(&str_buf));
        try equal(
            \\9| four
            \\10|  [1]
            \\    ^
        , try readLines(&line_buf, input, 19, .{ .backward = 2 }, .{ .set = 10 }).debugString(&str_buf));

        // automatic line numbering
        try equal(
            \\2| two [0]
            \\      ^
        , try readLines(&line_buf, input, 7, .{ .backward = 1 }, .detect).debugString(&str_buf));
        try equal(
            \\4| four
            \\5|  [1]
            \\   ^
        , try readLines(&line_buf, input, 19, .{ .backward = 2 }, .detect).debugString(&str_buf));
    }

    // [.bi] read mode
    {
        // reading with an empty buffer
        try equal(
            \\0|  [0]
            \\   ^ [0]
        , try readLines(&empty_buf, input, 2, .{ .bi = .{ .backward = 2, .forward = 2 } }, .detect).debugString(&str_buf));
        // reading out of bounds
        try equal(
            \\0|  [0]
            \\   ^ [0]
        , try readLines(&empty_buf, input, 100, .{ .bi = .{ .backward = 2, .forward = 2 } }, .detect).debugString(&str_buf));
        // reading zero amount
        try equal(
            \\0|  [0]
            \\   ^ [0]
        , try readLines(&empty_buf, input, 0, .{ .bi = .{ .backward = 0, .forward = 0 } }, .detect).debugString(&str_buf));
        // manual line numbering
        try equal(
            \\10| one [0]
            \\     ^
            \\11| two
            \\12| three
            \\13| four
            \\14| 
        , try readLines(&line_buf, input, 1, .{ .bi = .{ .backward = 5, .forward = 5 } }, .{ .set = 10 }).debugString(&str_buf));
        try equal(
            \\9| two
            \\10| three [1]
            \\      ^
        , try readLines(&line_buf, input, 10, .{ .bi = .{ .backward = 2, .forward = 0 } }, .{ .set = 10 }).debugString(&str_buf));
        try equal(
            \\10| three [0]
            \\      ^
            \\11| four
        , try readLines(&line_buf, input, 10, .{ .bi = .{ .backward = 0, .forward = 2 } }, .{ .set = 10 }).debugString(&str_buf));
        try equal(
            \\9| two
            \\10| three [1]
            \\      ^
            \\11| four
            \\12| 
        , try readLines(&line_buf, input, 10, .{ .bi = .{ .backward = 2, .forward = 2 } }, .{ .set = 10 }).debugString(&str_buf));
        try equal(
            \\6| one
            \\7| two
            \\8| three
            \\9| four
            \\10|  [4]
            \\    ^
        , try readLines(&line_buf, input, 19, .{ .bi = .{ .backward = 5, .forward = 5 } }, .{ .set = 10 }).debugString(&str_buf));
        // automatic line numbering
        try equal(
            \\1| one [0]
            \\    ^
            \\2| two
        , try readLines(&line_buf, input, 1, .{ .bi = .{ .backward = 1, .forward = 1 } }, .detect).debugString(&str_buf));
        try equal(
            \\5|  [0]
            \\   ^
        , try readLines(&line_buf, input, 19, .{ .bi = .{ .backward = 1, .forward = 1 } }, .detect).debugString(&str_buf));
    }

    // [.range_hard] read mode
    {
        // reading with an empty buffer
        try equal(
            \\0|  [0]
            \\   ^ [0]
        , try readLines(&empty_buf, input, 2, .{ .range_hard = 5 }, .detect).debugString(&str_buf));
        // reading out of bounds
        try equal(
            \\0|  [0]
            \\   ^ [0]
        , try readLines(&empty_buf, input, 100, .{ .range_hard = 5 }, .detect).debugString(&str_buf));
        // reading zero amount
        try equal(
            \\0|  [0]
            \\   ^ [0]
        , try readLines(&empty_buf, input, 0, .{ .range_hard = 0 }, .detect).debugString(&str_buf));
        // manual line numbering
        try equal(
            \\10| one [0]
            \\    ^
        , try readLines(&line_buf, input, 0, .{ .range_hard = 1 }, .{ .set = 10 }).debugString(&str_buf));
        try equal(
            \\10|  [0]
            \\    ^
        , try readLines(&line_buf, input, 19, .{ .range_hard = 1 }, .{ .set = 10 }).debugString(&str_buf));
        try equal(
            \\10| one [0]
            \\    ^
            \\11| two
        , try readLines(&line_buf, input, 0, .{ .range_hard = 3 }, .{ .set = 10 }).debugString(&str_buf));
        try equal(
            \\9| four
            \\10|  [1]
            \\    ^
        , try readLines(&line_buf, input, 19, .{ .range_hard = 3 }, .{ .set = 10 }).debugString(&str_buf));
        try equal(
            \\9| two
            \\10| three [1]
            \\      ^
            \\11| four
        , try readLines(&line_buf, input, 10, .{ .range_hard = 3 }, .{ .set = 10 }).debugString(&str_buf));
        // automatic line numbering
        try equal(
            \\2| two
            \\3| three [1]
            \\     ^
            \\4| four
        , try readLines(&line_buf, input, 10, .{ .range_hard = 3 }, .detect).debugString(&str_buf));
    }

    // [.range_soft] read mode
    {
        // reading with an empty buffer
        try equal(
            \\0|  [0]
            \\   ^ [0]
        , try readLines(&empty_buf, input, 2, .{ .range_hard = 5 }, .detect).debugString(&str_buf));
        // reading out of bounds
        try equal(
            \\0|  [0]
            \\   ^ [0]
        , try readLines(&empty_buf, input, 100, .{ .range_soft = 5 }, .detect).debugString(&str_buf));
        // reading zero amount
        try equal(
            \\0|  [0]
            \\   ^ [0]
        , try readLines(&empty_buf, input, 0, .{ .range_soft = 0 }, .detect).debugString(&str_buf));
        // manual line numbering
        try equal(
            \\10| one [0]
            \\    ^
        , try readLines(&line_buf, input, 0, .{ .range_soft = 1 }, .{ .set = 10 }).debugString(&str_buf));
        try equal(
            \\10|  [0]
            \\    ^
        , try readLines(&line_buf, input, 19, .{ .range_soft = 1 }, .{ .set = 10 }).debugString(&str_buf));
        try equal(
            \\10| one [0]
            \\    ^
            \\11| two
            \\12| three
        , try readLines(&line_buf, input, 0, .{ .range_soft = 3 }, .{ .set = 10 }).debugString(&str_buf));
        try equal(
            \\8| three
            \\9| four
            \\10|  [2]
            \\    ^
        , try readLines(&line_buf, input, 19, .{ .range_soft = 3 }, .{ .set = 10 }).debugString(&str_buf));
        try equal(
            \\9| two
            \\10| three [1]
            \\      ^
            \\11| four
        , try readLines(&line_buf, input, 10, .{ .range_soft = 3 }, .{ .set = 10 }).debugString(&str_buf));
        // automatic line numbering
        try equal(
            \\2| two
            \\3| three [1]
            \\     ^
            \\4| four
        , try readLines(&line_buf, input, 10, .{ .range_soft = 3 }, .detect).debugString(&str_buf));
    }
}

/// Implementation function. Reads lines in both directions.
fn readLinesImpl(
    comptime dir: ReadDirection,
    buf: [][]const u8,
    input: []const u8,
    index: usize,
    amount: usize,
    curr_ln: LineNumMode,
) ReadLines {
    if (index > input.len or buf.len == 0 or amount == 0)
        return ReadLines.initEmpty(buf);

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
                break :blk countLineNumForw(input, 0, first_line_start);
            } else break :blk curr_ln.set -| curr_line_pos;
        },
    };
}
