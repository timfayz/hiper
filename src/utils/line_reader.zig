// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

//! Public API:
//! - indexOfLineStart()
//! - indexOfLineEnd()
//! - countLineNum()
//! - readLine()
//! - streamLinesForward()
//! - readLinesForward()
//! - streamLinesBackward()
//! - readLinesBackward()
//! - ReadLines
//! - readLines()

const std = @import("std");
const num = @import("num.zig");
const stack = @import("stack.zig");
const err = @import("err.zig");
const range = @import("range.zig");
const slice = @import("slice.zig");

/// Retrieves the starting position of a line.
pub fn indexOfLineStart(input: []const u8, index: usize) usize {
    if (input.len == 0 or index == 0) return 0;
    var start = @min(input.len, index);
    // step back from EOF or newline
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
    if (index >= input.len) return input.len;
    var end: usize = index;
    while (end < input.len and input[end] != '\n') : (end += 1) {}
    return end;
}

test indexOfLineStart {
    const equal = std.testing.expectEqual;
    try equal(0, indexOfLineStart("", 0));
    try equal(0, indexOfLineStart("", 100));
    try equal(0, indexOfLineStart("line", 0));
    try equal(0, indexOfLineStart("line", 4));
    try equal(0, indexOfLineStart("line", 8));
    try equal(0, indexOfLineStart("\n\n", 0));
    //                             ^
    try equal(1, indexOfLineStart("\n\n", 1));
    //                               ^
    try equal(2, indexOfLineStart("\n\n", 2));
    //                                 ^
    try equal(1, indexOfLineStart("\nline", 5));
    //                                   ^
    try equal(0, indexOfLineStart("line\n", 4));
    //                                 ^
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

/// Counts the number of lines in `input` between `start` and `end` indices.
/// If `start > end`, their values are automatically swapped. Returns 1 if
/// `start == end`. Line numbering starts from 1.
pub fn countLineNum(input: []const u8, start: usize, end: usize) usize {
    var from: usize, var until = num.orderPairAsc(start, end);
    if (until >= input.len) until = input.len; // normalize

    var line_num: usize = 1;
    while (from < until) : (from += 1) {
        if (input[from] == '\n') line_num += 1;
    }
    return line_num;
}

test countLineNum {
    const equal = std.testing.expectEqual;

    try equal(1, countLineNum("", 0, 0));
    try equal(1, countLineNum("", 0, 100));
    try equal(1, countLineNum("", 100, 0));
    try equal(1, countLineNum("", 100, 100));
    try equal(2, countLineNum("\n", 0, 1));
    //                         ^ ^
    try equal(2, countLineNum("\n", 0, 100));
    //                         ^   ^
    try equal(2, countLineNum("\n", 100, 0));
    //                         ^   ^
    try equal(2, countLineNum("\n\n", 0, 1));
    //                         ^ ^
    try equal(3, countLineNum("\n\n", 0, 2));
    //                         ^   ^
    try equal(2, countLineNum("\n\n", 1, 2));
    //                           ^ ^
    try equal(2, countLineNum("\n\n", 2, 1));
    //                           ^ ^
    try equal(1, countLineNum("\n\n", 3, 4));
    //                              ^^
    try equal(1, countLineNum("l1\nl2\nl3", 0, 0));
    //                         ^
    try equal(2, countLineNum("l1\nl2\nl3", 0, 3));
    //                         ^   ^
    try equal(3, countLineNum("l1\nl2\nl3", 0, 6));
    //                         ^       ^
    try equal(3, countLineNum("l1\nl2\nl3", 0, 7));
    //                         ^        ^
    try equal(3, countLineNum("l1\nl2\nl3", 7, 0));
    //                         ^        ^
    try equal(3, countLineNum("l1\nl2\nl3", 2, 6));
    //                           ^     ^
    try equal(3, countLineNum("l1\nl2\nl3", 6, 2));
    //                           ^     ^
}

/// Retrieves a line from `input` starting at index, returning the line and the
/// index's relative position within it. If the index exceeds the line length,
/// the position points to the newline or EOF.
pub fn readLine(input: []const u8, index: usize) ?struct { []const u8, usize } {
    if (index > input.len) return null;
    const line_start = indexOfLineStart(input, index);
    const line_end = indexOfLineEnd(input, index);
    return .{ input[line_start..line_end], index - line_start };
}

test readLine {
    const equal = std.testing.expectEqualDeep;

    try equal(null, readLine("", 100));
    try equal(.{ "", 0 }, readLine("", 0));
    try equal(.{ "", 0 }, readLine("\n", 0));
    try equal(.{ "one", 3 }, readLine("\none", 4));
    try equal(.{ "one", 2 }, readLine("one", 2));
    try equal(.{ "one", 2 }, readLine("one\n", 2));
    try equal(.{ "one", 3 }, readLine("one\n", 3));
    try equal(.{ "", 0 }, readLine("one\n", 4));
    try equal(.{ "one", 3 }, readLine("one\ntwo", 3));
    try equal(.{ "two", 0 }, readLine("one\ntwo", 4));
    try equal(.{ "two", 2 }, readLine("one\ntwo", 6));
}

/// Retrieves lines from `input` starting at `index`, reading forward. Returns
/// the number of lines written into `writer` and the index's relative position
/// on the first written line (current line).
pub fn streamLinesForward(
    writer: anytype,
    input: []const u8,
    index: usize,
    amount: usize,
) !struct { usize, usize } {
    if (index > input.len or amount == 0)
        return .{ 0, 0 };

    var line_start = indexOfLineStart(input, index);
    var line_end = line_start;
    const index_pos = index - line_start;

    var written: usize = 0;
    while (written < amount) {
        line_end = indexOfLineEnd(input, line_start);
        written += try writer.write(input[line_start..line_end]);
        if (line_end >= input.len) break;
        line_start = line_end + 1;
    }

    return .{ written, index_pos };
}

/// Retrieves lines from `input` starting at `index`, reading backward. Returns
/// the number of lines written into `writer` and the index's relative position
/// on the first written line (current line). Lines are written in traversal
/// order (reversed).
pub fn streamLinesBackward(
    writer: anytype,
    input: []const u8,
    index: usize,
    amount: usize,
) !struct { usize, usize } {
    if (index > input.len or amount == 0)
        return .{ 0, 0 };

    var line_start = indexOfLineStart(input, index);
    var line_end = indexOfLineEnd(input, index);
    const index_pos = index - line_start;

    // first line
    var written: usize = 0;
    written += try writer.write(input[line_start..line_end]);
    if (line_start == 0 or written == amount) return .{ written, index_pos };
    line_end = line_start - 1;

    // rest
    while (written < amount) {
        line_start = indexOfLineStart(input, line_end);
        written += try writer.write(input[line_start..line_end]);
        if (line_start == 0) break;
        line_end = line_start - 1;
    }

    return .{ written, index_pos };
}

/// Retrieves lines from `input` starting at `index`, reading forward.
/// See `ReadLines` for details.
pub fn readLinesForward(
    buf: [][]const u8,
    input: []const u8,
    index: usize,
    amount: usize,
) !ReadLines {
    var lines = stack.initFromSlice([]const u8, buf);
    _, const index_pos = try streamLinesForward(lines.writer(), input, index, amount);
    return .{
        .lines = lines.slice(),
        .curr_line_pos = 0,
        .index_pos = index_pos,
    };
}

test readLinesForward {
    const t = std.testing;

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
        //^19 (eof)
    ;
    var str = std.BoundedArray(u8, 512){};
    var line_buf: [16][]const u8 = undefined;

    // empty-buffer read
    {
        try t.expectEqual(error.OutOfSpace, readLinesForward(&[0][]const u8{}, input, 0, 3));
    }
    // out-of-input read
    {
        const res = try readLinesForward(&line_buf, input, 100, 3);
        try res.log(str.writer(), 1);
        try t.expectEqualStrings(
            \\1|  [0]
            \\   ^ [0]
            \\
        , str.slice());
        str.clear();
    }
    // zero-amount read
    {
        const res = try readLinesForward(&[0][]const u8{}, input, 0, 0);
        try res.log(str.writer(), 1);
        try t.expectEqualStrings(
            \\1|  [0]
            \\   ^ [0]
            \\
        , str.slice());
        str.clear();
    }
    // normal reads
    {
        const res = try readLinesForward(&line_buf, input, 3, 3);
        try res.log(str.writer(), 1);
        try t.expectEqualStrings(
            \\1| one [0]
            \\      ^ [3]
            \\2| two
            \\3| three
            \\
        , str.slice());
        str.clear();
    }
    {
        const res = try readLinesForward(&line_buf, input, 18, 3);
        try res.log(str.writer(), 4);
        try t.expectEqualStrings(
            \\4| four [0]
            \\       ^ [4]
            \\5| 
            \\
        , str.slice());
        str.clear();
    }

    {
        const res = try readLinesForward(&line_buf, input, 19, 3);
        try res.log(str.writer(), 5);
        try t.expectEqualStrings(
            \\5|  [0]
            \\   ^ [0]
            \\
        , str.slice());
        str.clear();
    }
}

/// Retrieves lines from `input` starting at `index`, reading backward.
/// See `ReadLines` for details.
pub fn readLinesBackward(
    buf: [][]const u8,
    input: []const u8,
    index: usize,
    amount: usize,
) !ReadLines {
    var lines = stack.initFromSlice([]const u8, buf);
    _, const index_pos = try streamLinesBackward(lines.writer(), input, index, amount);
    const reversed = slice.reversed(@TypeOf(buf), lines.slice());
    return .{
        .lines = reversed,
        .curr_line_pos = reversed.len -| 1,
        .index_pos = index_pos,
    };
}

test readLinesBackward {
    const t = std.testing;

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
        //^19 (eof)
    ;
    var str = std.BoundedArray(u8, 512){};
    var line_buf: [16][]const u8 = undefined;

    // empty-buffer read
    {
        try t.expectEqual(error.OutOfSpace, readLinesBackward(&[0][]const u8{}, input, 0, 3));
    }
    // out-of-input read
    {
        const res = try readLinesBackward(&line_buf, input, 100, 3);
        try res.log(str.writer(), 1);
        try t.expectEqualStrings(
            \\1|  [0]
            \\   ^ [0]
            \\
        , str.slice());
        str.clear();
    }
    // zero-amount read
    {
        const res = try readLinesBackward(&[0][]const u8{}, input, 0, 0);
        try res.log(str.writer(), 1);
        try t.expectEqualStrings(
            \\1|  [0]
            \\   ^ [0]
            \\
        , str.slice());
        str.clear();
    }
    // normal reads
    {
        const res = try readLinesBackward(&line_buf, input, 3, 3);
        try res.log(str.writer(), 1);
        try t.expectEqualStrings(
            \\1| one [0]
            \\      ^ [3]
            \\
        , str.slice());
        str.clear();
    }
    {
        const res = try readLinesBackward(&line_buf, input, 18, 3);
        try res.log(str.writer(), 2);
        try t.expectEqualStrings(
            \\2| two
            \\3| three
            \\4| four [2]
            \\       ^ [4]
            \\
        , str.slice());
        str.clear();
    }

    {
        const res = try readLinesBackward(&line_buf, input, 19, 3);
        try res.log(str.writer(), 3);
        try t.expectEqualStrings(
            \\3| three
            \\4| four
            \\5|  [2]
            \\   ^ [0]
            \\
        , str.slice());
        str.clear();
    }
}

pub const ReadLines = struct {
    /// Retrieved lines.
    lines: []const []const u8,
    /// Position of the current line where the index was located.
    curr_line_pos: usize,
    /// Index position within the current line. If it exceeds the line's
    /// length, the position points to either the newline or EOF.
    index_pos: usize,

    /// Checks if no lines have been read.
    pub fn isEmpty(self: *const ReadLines) bool {
        return self.lines.len == 0;
    }

    /// The total number of the read lines.
    pub fn total(self: *const ReadLines) usize {
        return self.lines.len;
    }

    /// The number of lines read before the current line.
    pub fn beforeCurr(self: *const ReadLines) usize {
        return self.curr_line_pos;
    }

    /// The number of lines read after the current line.
    pub fn afterCurr(self: *const ReadLines) usize {
        return self.lines.len -| self.curr_line_pos -| 1;
    }

    /// The current line being read.
    pub fn curr(self: *const ReadLines) []const u8 {
        return self.lines[self.curr_line_pos];
    }

    /// The first line of the read collection.
    pub fn first(self: *const ReadLines) []const u8 {
        return self.lines[0];
    }

    /// The last line of the read collection.
    pub fn last(self: *const ReadLines) []const u8 {
        return self.lines[self.lines.len -| 1];
    }

    /// Index where the last read line ends in `input` (for forward reading).
    /// Add 1 to start reading the next line forward.
    pub fn indexLastRead(self: *const ReadLines, input: []const u8) usize {
        return slice.endIndex(input, self.last());
    }

    /// Index where the first read line starts in `input` (for backward reading).
    /// Subtract 1 to start reading the next line backward.
    pub fn indexFirstRead(self: *const ReadLines, input: []const u8) usize {
        return slice.startIndex(input, self.first());
    }

    pub fn nextReadIndex(self: *const ReadLines, comptime dir: range.Dir, input: []const u8) ?usize {
        if (self.isEmpty()) return null;
        return if (dir == .right) self.indexLastRead(input) +| 1 else self.indexFirstRead(input) -| 1;
    }

    /// Checks if the provided index is within the already read range.
    pub fn containsIndex(self: *const ReadLines, index: usize, input: []const u8) bool {
        return index >= self.indexFirstRead(input) and index <= self.indexLastRead(input);
    }

    pub fn join(base: ReadLines, extension: ReadLines, comptime dir: range.Dir, buf: [][]const u8) !ReadLines {
        if (base.isEmpty()) return extension;
        if (extension.isEmpty()) return base;
        var new = base;
        new.lines = buf[0..base.total() +| extension.total()];
        if (dir == .left) {
            try slice.move(.left, 1024, []const u8, buf, extension.lines);
            new.curr_line_pos +|= extension.total();
        }
        return new;
    }

    pub fn log(self: ReadLines, writer: anytype, first_line_num: usize) !void {
        const line_num_len = num.countIntLen(first_line_num +| self.total()) +| 2;
        for (self.lines, first_line_num.., 0..) |line, line_num, i| {
            try writer.print("{d}| {s}", .{ line_num, line });
            if (self.curr_line_pos == i) {
                try writer.print(" [{d}]\n", .{self.curr_line_pos});
                try writer.print("{c: >[1]} [{2d}]", .{
                    '^',
                    line_num_len + self.index_pos + 1,
                    self.index_pos,
                });
            }
            try writer.writeByte('\n');
        }
        if (self.lines.len == 0) {
            try writer.print("{d}|  [{d}]\n", .{ first_line_num, self.curr_line_pos });
            try writer.print("{[0]c: >[1]} [{[2]d}]\n", .{ '^', line_num_len + self.index_pos + 1, self.index_pos });
        }
    }
};

/// Retrieves lines from input starting at the given index and view view mode.
/// Returns the lines, current line index, and position within that line. If the
/// position exceeds line's length, it points to the newline or EOF.
pub fn readLines(
    buf: [][]const u8,
    input: []const u8,
    index: usize,
    comptime amount: range.Rel,
    comptime compensate: bool,
) !ReadLines {
    const plan = amount.toPair(.{});
    const first = try readLinesBackward(buf, input, index, plan.left);
    const next_index = first.nextReadIndex(.right, input) orelse index;
    const second = try readLinesForward(buf[first.total()..], input, next_index, plan.right);
    const merged = try first.join(second, .right, buf);

    if (compensate) {
        const reminder = range.DirPair.init(
            plan.left - first.total(),
            plan.right - second.total(),
        );
        if (reminder.uniqueNonZeroDir()) |reminder_dir| {
            const buf_left = buf[merged.total()..];
            switch (reminder_dir) {
                .left => {
                    const next_idx = merged.nextReadIndex(.right, input) orelse index;
                    const third_read = try readLinesForward(buf_left, input, next_idx, reminder.left);
                    return try merged.join(third_read, .right, buf);
                },
                .right => {
                    const next_idx = merged.nextReadIndex(.left, input) orelse index;
                    const third_read = try readLinesBackward(buf_left, input, next_idx, reminder.right);
                    return try merged.join(third_read, .left, buf);
                },
            }
        }
    }
    return merged;
}

test readLines {
    const equal = std.testing.expectEqualStrings;
    var line_buf: [16][]const u8 = undefined;
    var str = std.BoundedArray(u8, 512){};

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
    {
        const read = try readLines(&line_buf, input, 2, .{ .custom = .{ .left = 3, .right = 1 } }, true);
        try read.log(str.writer(), 1);
        try equal(
            \\1| one [0]
            \\     ^ [2]
            \\2| two
            \\3| three
            \\4| four
            \\
        , str.slice());
        str.clear();
    }
    {
        const read = try readLines(&line_buf, input, 19, .{ .custom = .{ .left = 1, .right = 3 } }, true);
        try read.log(str.writer(), 2);
        try equal(
            \\2| two
            \\3| three
            \\4| four
            \\5|  [3]
            \\   ^ [0]
            \\
        , str.slice());
        str.clear();
    }
    {
        const read = try readLines(&line_buf, input, 10, .{ .custom = .{ .left = 10, .right = 10 } }, true);
        try read.log(str.writer(), 1);
        try equal(
            \\1| one
            \\2| two
            \\3| three [2]
            \\     ^ [2]
            \\4| four
            \\5| 
            \\
        , str.slice());
        str.clear();
    }
}
