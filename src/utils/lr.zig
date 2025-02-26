// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

//! Public API:
//! - LineReader
//! - ReadLines
//! - readLines
//! - readLinesWithin
//! - ReadLine
//! - readLineWithin
//! - readLineAround
//! - readLineAroundRange
//! - countLineNum

const std = @import("std");
const stack = @import("stack.zig");
const slice = @import("slice.zig");
const Range = @import("span.zig").Range;
const Dir = @import("span.zig").Dir;
const num = @import("num.zig");
const assert = std.debug.assert;
const t = std.testing;

/// A line retriever that can stack-allocate its own buffer (`buf_len != null`)
/// for retrieved lines or use an externally provided one (`buf_len == null`).
pub fn LineReader(buf_len: ?usize) type {
    return struct {
        lines: stack.Stack([]const u8, buf_len) = .{},
        input: []const u8,
        start: usize,
        end: usize,

        const Self = @This();

        pub usingnamespace if (buf_len == null) struct {
            pub fn init(slc: [][]const u8, input: []const u8, index: usize) Self {
                return .{
                    .lines = stack.Stack([]const u8, buf_len).initEmpty(slc),
                    .input = input,
                    .start = index,
                    .end = index,
                };
            }
        } else struct {
            pub fn init(input: []const u8, index: usize) Self {
                return .{
                    .lines = .{},
                    .input = input,
                    .start = index,
                    .end = index,
                };
            }
        };

        pub fn reset(l: *Self, input: []const u8, index: usize) void {
            l.lines.reset();
            l.input = input;
            l.start = index;
            l.end = index;
        }

        pub fn clearPushed(l: *Self) void {
            l.lines.reset();
        }

        pub fn setPos(l: *Self, index: usize) void {
            l.start = index;
            l.end = index;
        }

        pub fn setStartEndPos(l: *Self, start: usize, end: usize) void {
            l.start = start;
            l.end = end;
        }

        pub fn setPosFromRange(l: *Self, rng: Range) void {
            l.start = rng.start;
            l.end = rng.end;
        }

        pub fn movePosRight(l: *Self, amt: usize) void {
            l.end +|= amt;
            l.start = l.end;
        }

        pub fn movePosLeft(l: *Self, amt: usize) void {
            l.start -|= amt;
            l.end = l.start;
        }

        pub fn line(l: *const Self) []const u8 {
            return l.input[l.start..l.end];
        }

        pub fn endIsLineEnd(l: *const Self) bool {
            return l.end == l.input.len or l.input.len == 0 or l.input[l.end] == '\n';
        }

        pub fn startIsLineStart(l: *const Self) bool {
            return l.start == 0 or l.input.len == 0 or l.input[l.start - 1] == '\n';
        }

        pub fn pushLine(l: *Self) !void {
            try l.lines.push(l.input[l.start..l.end]);
        }

        pub fn totalPushed(l: *const Self) usize {
            return l.lines.len;
        }

        pub fn pushed(l: *Self) [][]const u8 {
            return l.lines.slice();
        }

        pub fn reversePushed(l: *Self) void {
            slice.reverse(l.pushed());
        }

        pub fn isEmpty(l: *const Self) bool {
            return l.lines.empty();
        }

        pub fn reachedEOF(l: *const Self) bool {
            return l.end >= l.input.len;
        }

        pub fn reachedZero(l: *const Self) bool {
            return l.start == 0;
        }

        pub fn seekLineStart(l: *Self) void {
            assert(l.start <= l.input.len);
            if (l.input.len == 0 or l.start == 0)
                return;
            if (l.start == l.input.len or l.input[l.start] == '\n') l.start -|= 1;
            while (true) : (l.start -= 1) {
                if (l.input[l.start] == '\n') {
                    l.start += 1;
                    break;
                }
                if (l.start == 0)
                    break;
            }
        }

        pub fn seekLineStartUntil(l: *Self, until: usize) void {
            assert(l.start <= l.input.len);
            assert(until <= l.start);
            if (l.input.len == 0 or l.start == 0)
                return;
            if (l.start == l.input.len or l.input[l.start] == '\n') l.start -|= 1;
            while (true) : (l.start -= 1) {
                if (l.input[l.start] == '\n') {
                    l.start += 1;
                    break;
                }
                if (l.start == 0 or l.start == until)
                    break;
            }
        }

        pub fn seekLineEnd(l: *Self) void {
            assert(l.end <= l.input.len);
            while (l.end < l.input.len and l.input[l.end] != '\n') l.end += 1;
        }

        pub fn seekLineEndUntil(l: *Self, until: usize) void {
            assert(l.end <= l.input.len);
            while (l.end < l.input.len and l.end != until and
                l.input[l.end] != '\n') l.end += 1;
        }

        pub fn seekLine(l: *Self) void {
            l.seekLineStart();
            l.seekLineEnd();
        }

        pub fn seekLineWithin(l: *Self, within: Range) void {
            assert(within.start <= l.start);
            assert(within.end >= l.end);
            l.seekLineStartUntil(within.start);
            l.seekLineEndUntil(within.end);
        }

        pub fn seekAndPushLine(l: *Self) !void {
            l.seekLine();
            try l.pushLine();
        }

        pub fn seekAndPushLineWithin(l: *Self, within: Range) !void {
            l.seekLineWithin(within);
            try l.pushLine();
        }

        pub fn seekAndPushLines(l: *Self, comptime dir: Dir, amt: ?usize) !void {
            var left = amt orelse std.math.maxInt(usize);
            if (left == 0)
                return;

            switch (dir) {
                .right => {
                    l.seekLineStart();
                    while (true) {
                        l.seekLineEnd();
                        try l.pushLine();
                        left -= 1;
                        if (l.reachedEOF() or left == 0) break;
                        l.movePosRight(1);
                    }
                },
                .left => {
                    l.seekLineEnd();
                    while (true) {
                        l.seekLineStart();
                        try l.pushLine();
                        left -= 1;
                        if (l.reachedZero() or left == 0) break;
                        l.movePosLeft(1);
                    }
                },
            }
        }

        pub fn seekAndPushLinesWithin(
            l: *Self,
            comptime dir: Dir,
            amt: ?usize,
            within: Range,
            hard_cut: bool,
        ) !void {
            assert(within.start <= l.start);
            assert(within.end >= l.end);
            var left = amt orelse std.math.maxInt(usize);
            if (left == 0)
                return;

            switch (dir) {
                .right => {
                    if (hard_cut) l.seekLineStartUntil(within.start) else l.seekLineStart();
                    while (true) {
                        if (hard_cut) l.seekLineEndUntil(within.end) else l.seekLineEnd();
                        try l.pushLine();
                        left -= 1;
                        if (l.reachedEOF() or l.end >= within.end or left == 0) break;
                        l.movePosRight(1);
                    }
                },
                .left => {
                    if (hard_cut) l.seekLineEndUntil(within.end) else l.seekLineEnd();
                    while (true) {
                        if (hard_cut) l.seekLineStartUntil(within.start) else l.seekLineStart();
                        try l.pushLine();
                        left -= 1;
                        if (l.reachedZero() or l.start == within.start or left == 0) break;
                        l.movePosLeft(1);
                    }
                },
            }
        }

        pub fn seekAndPushLineRange(l: *Self, comptime line_range: Range.View) !usize {
            if (line_range.len() == 0) return 0;
            const plan = line_range.toPair(.{ .around_rshift_odd = false });

            try l.seekAndPushLines(.left, plan.left);
            if (l.totalPushed() > 1) l.reversePushed();
            const curr_line_idx: usize = l.totalPushed() -| 1;
            if (l.topLineIndexOf(.end)) |next| l.setPos(next +| 1);
            if (l.reachedEOF()) return curr_line_idx;
            try l.seekAndPushLines(.right, plan.right);
            return curr_line_idx;
        }

        pub fn seekAndPushLineRangeWithin(
            l: *Self,
            comptime line_range: Range.View,
            within: Range,
            hard_cut: bool,
        ) !usize {
            if (line_range.len() == 0) return 0;
            const plan = line_range.toPair(.{ .around_rshift_odd = false });

            try l.seekAndPushLinesWithin(.left, plan.left, within, hard_cut);
            if (l.totalPushed() > 1) l.reversePushed();
            const curr_line_idx: usize = l.totalPushed() -| 1;
            if (l.end == within.end or l.reachedEOF()) return curr_line_idx;
            if (l.topLineIndexOf(.end)) |next| l.setPos(next +| 1);
            try l.seekAndPushLinesWithin(.right, plan.right, within, hard_cut);
            return curr_line_idx;
        }

        pub fn lineContainsIndex(l: *const Self, index: usize) bool {
            return index >= l.start and index <= l.end;
        }

        pub fn topLine(l: *const Self) ?[]const u8 {
            return l.lines.topOrNull();
        }

        pub fn bottomLine(l: *const Self) ?[]const u8 {
            return l.lines.bottomOrNull();
        }

        pub fn topLineIndexOf(l: *const Self, comptime edge: enum { start, end }) ?usize {
            if (l.topLine()) |top_line| {
                return switch (edge) {
                    .start => slice.startIndex(l.input, top_line),
                    .end => slice.endIndex(l.input, top_line),
                };
            } else return null;
        }

        pub fn bottomLineIndexOf(l: *const Self, comptime edge: enum { start, end }) ?usize {
            if (l.bottomLine()) |bottom_line| {
                return switch (edge) {
                    .start => slice.startIndex(l.input, bottom_line),
                    .end => slice.endIndex(l.input, bottom_line),
                };
            } else return null;
        }
    };
}

test LineReader {
    var lr = LineReader(512).init("", 0);

    // [endIsLineEnd()]
    {
        lr.reset("\nline\n", 3);
        //        0 12345 6
        try t.expectEqual(false, lr.endIsLineEnd());

        lr.end = 1;
        try t.expectEqual(false, lr.endIsLineEnd());

        lr.end = 5;
        try t.expectEqual(true, lr.endIsLineEnd());

        lr.end = 6;
        try t.expectEqual(true, lr.endIsLineEnd());
    }
    // [startIsLineStart()]
    {
        lr.reset("\nline\n", 3);
        //        0 12345 6
        try t.expectEqual(false, lr.startIsLineStart());

        lr.start = 0;
        try t.expectEqual(true, lr.startIsLineStart());

        lr.start = 1;
        try t.expectEqual(true, lr.startIsLineStart());

        lr.start = 5;
        try t.expectEqual(false, lr.startIsLineStart());

        lr.start = 6;
        try t.expectEqual(true, lr.startIsLineStart());
    }
    // [seekLineStart()]
    {
        lr.reset("line", 0);
        lr.seekLineStart();
        try t.expectEqual(0, lr.start);

        lr.reset("line", 4);
        lr.seekLineStart();
        try t.expectEqual(0, lr.start);

        lr.reset("\n\n", 0);
        lr.seekLineStart();
        try t.expectEqual(0, lr.start);

        lr.reset("\n\n", 1);
        lr.seekLineStart();
        try t.expectEqual(1, lr.start);

        lr.reset("\n\n", 2);
        lr.seekLineStart();
        try t.expectEqual(2, lr.start);

        lr.reset("\nline", 5);
        lr.seekLineStart();
        try t.expectEqual(1, lr.start);

        lr.reset("line\n", 4);
        lr.seekLineStart();
        try t.expectEqual(0, lr.start);
    }
    // [seekLineStartUntil()]
    {
        lr.reset("line\n", 4);
        //         ^  ^
        lr.seekLineStartUntil(1);
        try t.expectEqual(1, lr.start);

        lr.reset("\nline", 5);
        //        ^     ^
        lr.seekLineStartUntil(0);
        try t.expectEqual(1, lr.start);
    }
    // [seekLineEnd()]
    {
        lr.reset("", 0);
        lr.seekLineEnd();
        try t.expectEqual(0, lr.end);

        lr.reset("line", 0);
        lr.seekLineEnd();
        try t.expectEqual(4, lr.end);

        lr.reset("line", 4);
        lr.seekLineEnd();
        try t.expectEqual(4, lr.end);

        lr.reset("\n\n", 0);
        lr.seekLineEnd();
        try t.expectEqual(0, lr.end);

        lr.reset("\n\n", 1);
        lr.seekLineEnd();
        try t.expectEqual(1, lr.end);

        lr.reset("line\n", 1);
        lr.seekLineEnd();
        try t.expectEqual(4, lr.end);
    }
    // [seekLineEndUntil()]
    {
        lr.reset("line\n", 1);
        //         ^ ^
        lr.seekLineEndUntil(3);
        try t.expectEqual(3, lr.end);

        lr.reset("line\n", 1);
        //         ^  ^
        lr.seekLineEndUntil(4);
        try t.expectEqual(4, lr.end);

        lr.reset("line\n", 1);
        //         ^    ^
        lr.seekLineEndUntil(5);
        try t.expectEqual(4, lr.end);
    }
    // [seekAndPushLine()]
    {
        lr.reset("line1\nline2\nline3", 0);
        //        ^
        try lr.seekAndPushLine();
        try t.expectEqualStrings("line1", lr.line());

        lr.reset("line1\nline2\nline3", 8);
        //                 ^
        try lr.seekAndPushLine();
        try t.expectEqualStrings("line2", lr.line());

        lr.reset("line1\nline2\nline3", 12);
        //                      ^
        try lr.seekAndPushLine();
        try t.expectEqualStrings("line3", lr.line());
    }
    // [seekAndPushLineWithin()]
    {
        lr.reset("line1\nline2\nline3", 8);
        //                789
        try lr.seekAndPushLineWithin(.{ .start = 7, .end = 9 });
        try t.expectEqualStrings("in", lr.line());
    }
    // [seekAndPushLines()]
    {
        const input = "line1\nline2\nline3";
        //             ^0  ^4 ^6  ^10^11 ^15

        lr.reset(input, 1);
        try lr.seekAndPushLines(.right, 0);
        try t.expectEqual(0, lr.totalPushed());

        // [.right]

        lr.reset(input, 0);
        try lr.seekAndPushLines(.right, 2);
        try t.expectEqual(2, lr.totalPushed());
        for (&[_][]const u8{ "line1", "line2" }, lr.pushed()) |e, a| {
            try t.expectEqualStrings(e, a);
        }
        // pos is on the last read line
        try t.expectEqual(6, lr.start);
        try t.expectEqual(11, lr.end);

        lr.reset(input, 0);
        try lr.seekAndPushLines(.right, 4);
        try t.expectEqual(3, lr.totalPushed());
        for (&[_][]const u8{ "line1", "line2", "line3" }, lr.pushed()) |e, a| {
            try t.expectEqualStrings(e, a);
        }

        lr.reset(input, input.len);
        try lr.seekAndPushLines(.right, 4);
        try t.expectEqual(1, lr.totalPushed());
        for (&[_][]const u8{"line3"}, lr.pushed()) |e, a| {
            try t.expectEqualStrings(e, a);
        }

        // [.left]
        lr.reset(input, 0);
        try lr.seekAndPushLines(.left, 2);
        try t.expectEqual(1, lr.totalPushed());
        for (&[_][]const u8{"line1"}, lr.pushed()) |e, a| {
            try t.expectEqualStrings(e, a);
        }

        lr.reset(input, input.len);
        try lr.seekAndPushLines(.left, 2);
        try t.expectEqual(2, lr.totalPushed());
        for (&[_][]const u8{ "line3", "line2" }, lr.pushed()) |e, a| {
            try t.expectEqualStrings(e, a);
        }
        // pos is on the last read line
        try t.expectEqual(6, lr.start);
        try t.expectEqual(11, lr.end);

        lr.reset(input, input.len);
        try lr.seekAndPushLines(.left, 4);
        try t.expectEqual(3, lr.totalPushed());
        for (&[_][]const u8{ "line3", "line2", "line1" }, lr.pushed()) |e, a| {
            try t.expectEqualStrings(e, a);
        }
    }
    // [seekAndPushLinesWithin()]
    {
        const input = "line1\nline2\nline3";
        //             ^0  ^4 ^6  ^10^12 ^16

        lr.reset(input, 1);
        try lr.seekAndPushLinesWithin(.right, 0, .{ .start = 0, .end = 5 }, true);
        try t.expectEqual(0, lr.totalPushed());

        // [.right]

        lr.reset(input, 3);
        try lr.seekAndPushLinesWithin(.right, 2, .{ .start = 2, .end = 14 }, true);
        try t.expectEqual(2, lr.totalPushed());
        for (&[_][]const u8{ "ne1", "line2" }, lr.pushed()) |e, a| {
            try t.expectEqualStrings(e, a);
        }

        lr.reset(input, 3);
        try lr.seekAndPushLinesWithin(.right, 4, .{ .start = 2, .end = 14 }, true);
        try t.expectEqual(3, lr.totalPushed());
        for (&[_][]const u8{ "ne1", "line2", "li" }, lr.pushed()) |e, a| {
            try t.expectEqualStrings(e, a);
        }
        // pos is on the last read line
        try t.expectEqual(12, lr.start);
        try t.expectEqual(14, lr.end);

        lr.reset(input, 3); // edge: index == within.end
        try lr.seekAndPushLinesWithin(.right, 4, .{ .start = 2, .end = 3 }, true);
        try t.expectEqual(1, lr.totalPushed());
        for (&[_][]const u8{"n"}, lr.pushed()) |e, a| {
            try t.expectEqualStrings(e, a);
        }

        // [.left]

        lr.reset(input, 14);
        try lr.seekAndPushLinesWithin(.left, 2, .{ .start = 2, .end = 14 }, true);
        try t.expectEqual(2, lr.totalPushed());
        for (&[_][]const u8{ "li", "line2" }, lr.pushed()) |e, a| {
            try t.expectEqualStrings(e, a);
        }

        lr.reset(input, 14);
        try lr.seekAndPushLinesWithin(.left, 4, .{ .start = 2, .end = 14 }, true);
        try t.expectEqual(3, lr.totalPushed());
        for (&[_][]const u8{ "li", "line2", "ne1" }, lr.pushed()) |e, a| {
            try t.expectEqualStrings(e, a);
        }
        // pos is on the last read line
        try t.expectEqual(2, lr.start);
        try t.expectEqual(5, lr.end);

        lr.reset(input, 2); // edge: index == within.start
        try lr.seekAndPushLinesWithin(.left, 4, .{ .start = 2, .end = 3 }, true);
        try t.expectEqual(1, lr.totalPushed());
        for (&[_][]const u8{"n"}, lr.pushed()) |e, a| {
            try t.expectEqualStrings(e, a);
        }
    }
    // [seekAndPushLineRange()]
    {
        const input = "line1\nline2\nline3";
        //             ^0  ^4 ^6  ^10^12 ^16

        lr.reset(input, 17);
        try t.expectEqual(1, try lr.seekAndPushLineRange(.{ .around = 3 }));
        for (&[_][]const u8{ "line2", "line3" }, lr.pushed()) |e, a| {
            try t.expectEqualStrings(e, a);
        }

        lr.reset(input, 8);
        try t.expectEqual(1, try lr.seekAndPushLineRange(.{ .around = 3 }));
        for (&[_][]const u8{ "line1", "line2", "line3" }, lr.pushed()) |e, a| {
            try t.expectEqualStrings(e, a);
        }

        lr.reset(input, 0);
        try t.expectEqual(0, try lr.seekAndPushLineRange(.{ .around = 3 }));
        for (&[_][]const u8{ "line1", "line2" }, lr.pushed()) |e, a| {
            try t.expectEqualStrings(e, a);
        }
    }
    // [seekAndPushLineRangeWithin()]
    {
        const input = "line1\nline2\nline3";
        //             ^0  ^4 ^6  ^10^12 ^16

        lr.input = input;

        lr.reset(input, 8);
        try t.expectEqual(1, try lr.seekAndPushLineRangeWithin(.{ .around = 5 }, .{ .start = 2, .end = 14 }, true));
        for (&[_][]const u8{ "ne1", "line2", "li" }, lr.pushed()) |e, a| {
            try t.expectEqualStrings(e, a);
        }

        lr.reset(input, 8);
        try t.expectEqual(1, try lr.seekAndPushLineRangeWithin(.{ .around = 5 }, .{ .start = 2, .end = 14 }, false));
        for (&[_][]const u8{ "line1", "line2", "line3" }, lr.pushed()) |e, a| {
            try t.expectEqualStrings(e, a);
        }
    }
}

/// The result of a multiline read.
pub const ReadLines = struct {
    lines: []const []const u8,
    /// Position of the current line where the index was located.
    curr_line_pos: usize,
    /// Index position within the current line. If it exceeds the line's
    /// length, the position points to either the newline or EOF.
    index_pos: usize,

    pub fn empty(self: *const ReadLines) bool {
        return self.lines.len == 0;
    }

    pub fn total(self: *const ReadLines) usize {
        return self.lines.len;
    }

    pub fn curr(self: *const ReadLines) []const u8 {
        return self.lines[self.curr_line_pos];
    }

    pub fn beforeCurr(self: *const ReadLines) usize {
        return self.curr_line_pos;
    }

    pub fn afterCurr(self: *const ReadLines) usize {
        return self.lines.len -| self.curr_line_pos -| 1;
    }

    pub fn first(self: *const ReadLines) []const u8 {
        return self.lines[0];
    }

    pub fn last(self: *const ReadLines) []const u8 {
        return self.lines[self.lines.len -| 1];
    }
};

/// Retrieves a specified number of lines starting from the given index.
pub fn readLines(
    buf: [][]const u8,
    input: []const u8,
    index: usize,
    comptime line_range: Range.View,
) !ReadLines {
    var lr = LineReader(null).init(buf, input, index);
    const curr_line_pos = try lr.seekAndPushLineRange(line_range);
    const start_idx = if (!lr.isEmpty()) slice.startIndex(input, lr.pushed()[curr_line_pos]) else 0;
    return .{ .curr_line_pos = curr_line_pos, .index_pos = index - start_idx, .lines = lr.pushed() };
}

test readLines {
    var buf: [2][]const u8 = undefined;
    const res = try readLines(&buf, "hello\nworld", 7, .{ .around = 3 });
    //                                       ^
    try t.expectEqual(2, res.total());
    try t.expectEqualStrings("world", res.curr());
    try t.expectEqualStrings("hello", res.first());
    try t.expectEqual(1, res.curr_line_pos);
    try t.expectEqual(1, res.index_pos);
}

/// Retrieves the number of lines within the specified index range.
pub fn readLinesWithin(
    buf: [][]const u8,
    input: []const u8,
    index: usize,
    comptime line_range: Range.View,
    within: Range,
) !ReadLines {
    var lr = LineReader(null).init(buf, input, index);
    const curr_line_pos = try lr.seekAndPushLineRangeWithin(line_range, within);
    const start_idx = if (!lr.isEmpty()) slice.startIndex(input, lr.pushed()[curr_line_pos]) else 0;
    return .{ .curr_line_pos = curr_line_pos, .index_pos = index - start_idx, .lines = lr.pushed() };
}

/// The result of single line read: the line and its relative index position.
pub const ReadLine = struct { []const u8, usize };

pub fn readLineWithin(input: []const u8, index: usize, within: Range) ReadLine {
    var lr = LineReader(0).init(input, index);
    lr.seekLineWithin(within);
    return .{ lr.line(), index - lr.start };
}

test readLineWithin {
    const line, const index_pos = readLineWithin("hello world", 5, .{ .start = 3, .end = 8 });
    //                                                 ^
    try t.expectEqualStrings("lo wo", line);
    try t.expectEqual(2, index_pos);
}

pub const ReadLineOptions = struct {
    trunc_mode: Range.TruncMode = .hard,
    view_opt: Range.View.Options = .{},
    fit_pad: ?Dir.One = null,
    extra_dir: Dir = .right,
};

/// Retrieve a line span around the given index.
pub fn readLineAround(
    input: []const u8,
    index: usize,
    comptime view: Range.View,
    comptime opt: ReadLineOptions,
) ReadLine {
    const within = view
        .toPairAddExtra(1, .right, .{})
        .toRangeWithin(index, Range.initFromSlice(input), opt.trunc_mode);
    return readLineWithin(input, index, within);
}

test readLineAround {
    const line, const index_pos = readLineAround("hello world", 5, .{ .around = 4 }, .{});
    //                                                     ^
    try t.expectEqualStrings("lo wo", line);
    try t.expectEqual(2, index_pos);
}

/// Retrieve a line span around the given index with an additional extra range.
pub fn readLineAroundRange(
    input: []const u8,
    index: usize,
    extra: usize,
    comptime view: Range.View,
    comptime opt: ReadLineOptions,
) ReadLine {
    const pair = if (opt.fit_pad != null)
        view.toPairFitExtra(extra, opt.extra_dir, opt.fit_pad, .{})
    else
        view.toPairAddExtra(extra, opt.extra_dir, .{});
    const within = pair.toRangeWithin(index, Range.initFromSlice(input), opt.trunc_mode);
    return readLineWithin(input, index, within);
}

test readLineAroundRange {
    const line, const index_pos =
        readLineAroundRange("var x = 'string';", 8, 8, .{ .around = 10 }, .{ .fit_pad = .{ .left = 2 } });
    //                               ^
    try t.expectEqualStrings("= 'string'", line);
    try t.expectEqual(2, index_pos);
}

/// Checks if the line is truncated at the start.
pub fn truncatedStart(input: []const u8, line: []const u8) bool {
    const start = slice.startIndex(input, line);
    return start != 0 and input.len != 0 and input[start - 1] != '\n';
}

test truncatedStart {
    const input = "line\nline";
    //             01234 56789
    try t.expectEqual(false, truncatedStart(input, input[0..]));
    try t.expectEqual(true, truncatedStart(input, input[1..]));
    try t.expectEqual(false, truncatedStart(input, input[5..]));
    try t.expectEqual(true, truncatedStart(input, input[9..]));
}

/// Checks if the line is truncated at the end.
pub fn truncatedEnd(input: []const u8, line: []const u8) bool {
    const end = slice.endIndex(input, line);
    return end != input.len and input.len != 0 and input[end] != '\n';
}

test truncatedEnd {
    const input = "line\nline";
    //             01234 56789
    try t.expectEqual(true, truncatedEnd(input, input[0..3]));
    try t.expectEqual(false, truncatedEnd(input, input[0..4]));
    try t.expectEqual(true, truncatedEnd(input, input[0..5]));
    try t.expectEqual(false, truncatedEnd(input, input[0..9]));
}

/// Counts the number of lines in input between start and end indices.
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
    try t.expectEqual(1, countLineNum("", 0, 0));
    try t.expectEqual(1, countLineNum("", 100, 100));
    try t.expectEqual(2, countLineNum("\n", 0, 1));
    //                                 ^ ^
    try t.expectEqual(2, countLineNum("\n", 0, 100));
    //                                 ^   ^
    try t.expectEqual(2, countLineNum("\n", 100, 0));
    //                                 ^   ^
    try t.expectEqual(2, countLineNum("\n\n", 0, 1));
    //                                 ^ ^
    try t.expectEqual(3, countLineNum("\n\n", 0, 2));
    //                                 ^   ^
    try t.expectEqual(2, countLineNum("\n\n", 1, 2));
    //                                   ^ ^
    try t.expectEqual(2, countLineNum("\n\n", 2, 1));
    //                                   ^ ^
    try t.expectEqual(1, countLineNum("\n\n", 3, 4));
    //                                      ^^
    try t.expectEqual(1, countLineNum("l1\nl2\nl3", 0, 0));
    //                                 ^
    try t.expectEqual(2, countLineNum("l1\nl2\nl3", 0, 3));
    //                                 ^   ^
    try t.expectEqual(3, countLineNum("l1\nl2\nl3", 0, 6));
    //                                 ^       ^
    try t.expectEqual(3, countLineNum("l1\nl2\nl3", 0, 7));
    //                                 ^        ^
    try t.expectEqual(3, countLineNum("l1\nl2\nl3", 7, 0));
    //                                 ^        ^
    try t.expectEqual(3, countLineNum("l1\nl2\nl3", 2, 6));
    //                                   ^     ^
    try t.expectEqual(3, countLineNum("l1\nl2\nl3", 6, 2));
    //                                   ^     ^
}
