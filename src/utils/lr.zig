// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

const std = @import("std");
const stack = @import("stack.zig");
const slice = @import("slice.zig");
const assert = std.debug.assert;

pub const LineReader = struct {
    lines: stack.Stack([]const u8, 4096),
    input: []const u8,
    start: usize,
    end: usize,

    pub fn init(input: []const u8, index: usize) LineReader {
        return .{
            .lines = stack.init([]const u8, 4096),
            .input = input,
            .start = index,
            .end = index,
        };
    }

    pub fn reset(l: *LineReader, input: []const u8, index: usize) void {
        l.* = LineReader{
            .lines = stack.init([]const u8, 4096),
            .input = input,
            .start = index,
            .end = index,
        };
    }

    pub fn setPos(l: *LineReader, index: usize) void {
        l.start = index;
        l.end = index;
    }

    pub fn movePosNext(l: *LineReader) void {
        l.end +|= 1;
        l.start = l.end;
    }

    pub fn movePosPrev(l: *LineReader) void {
        l.start -|= 1;
        l.end = l.start;
    }

    pub fn pushLine(l: *LineReader) !void {
        try l.lines.push(l.input[l.start..l.end]);
    }

    pub fn len(l: *const LineReader) usize {
        return l.lines.len;
    }

    pub fn line(l: *const LineReader) []const u8 {
        return l.input[l.start..l.end];
    }

    pub fn isEmpty(l: *const LineReader) bool {
        return l.lines.empty();
    }

    pub fn reachedEnd(l: *const LineReader) bool {
        return l.end >= l.input.len;
    }

    pub fn reachedZero(l: *const LineReader) bool {
        return l.start == 0;
    }

    pub fn seekToLineStart(l: *LineReader) void {
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

    pub fn seekToLineStartUntil(l: *LineReader, until: usize) void {
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

    pub fn seekToLineEnd(l: *LineReader) void {
        assert(l.end <= l.input.len);
        while (l.end < l.input.len and l.input[l.end] != '\n') l.end += 1;
    }

    pub fn seekToLineEndUntil(l: *LineReader, until: usize) void {
        assert(l.end <= l.input.len);
        while (l.end < l.input.len and l.end != until and
            l.input[l.end] != '\n') l.end += 1;
    }

    pub fn readLine(l: *LineReader) !void {
        l.seekToLineStart();
        l.seekToLineEnd();
        try l.pushLine();
    }

    pub fn readLineWithin(l: *LineReader, start: usize, end: usize) !void {
        l.seekToLineStartUntil(start);
        l.seekToLineEndUntil(end);
        try l.pushLine();
    }

    pub fn readLinesAmt(l: *LineReader, comptime dir: enum { left, right }, amt: ?usize) !void {
        var left = amt orelse std.math.maxInt(usize);
        if (left == 0)
            return;

        switch (dir) {
            .right => {
                l.seekToLineStart();
                while (left != 0) : (left -= 1) {
                    l.seekToLineEnd();
                    try l.pushLine();
                    if (l.reachedEnd()) break;
                    l.movePosNext();
                }
            },
            .left => {
                l.seekToLineEnd();
                while (left != 0) : (left -= 1) {
                    l.seekToLineStart();
                    try l.pushLine();
                    if (l.reachedZero()) break;
                    l.movePosPrev();
                }
            },
        }
    }

    pub fn containsIndex(l: *const LineReader, index: usize) bool {
        return index >= l.start and index <= l.end;
    }
};

test LineReader {
    const t = std.testing;
    var lr = LineReader.init("line", 0);

    // [seekToLineStart()]
    {
        lr.seekToLineStart();
        try t.expectEqual(0, lr.start);

        lr.reset("line", 4);
        lr.seekToLineStart();
        try t.expectEqual(0, lr.start);

        lr.reset("\n\n", 0);
        lr.seekToLineStart();
        try t.expectEqual(0, lr.start);

        lr.reset("\n\n", 1);
        lr.seekToLineStart();
        try t.expectEqual(1, lr.start);

        lr.reset("\n\n", 2);
        lr.seekToLineStart();
        try t.expectEqual(2, lr.start);

        lr.reset("\nline", 5);
        lr.seekToLineStart();
        try t.expectEqual(1, lr.start);

        lr.reset("line\n", 4);
        lr.seekToLineStart();
        try t.expectEqual(0, lr.start);
    }
    // [seekToLineStartUntil()]
    {
        lr.reset("line\n", 4);
        //         ^  ^
        lr.seekToLineStartUntil(1);
        try t.expectEqual(1, lr.start);

        lr.reset("\nline", 5);
        //        ^     ^
        lr.seekToLineStartUntil(0);
        try t.expectEqual(1, lr.start);
    }
    // [seekToLineEnd()]
    {
        lr.reset("", 0);
        lr.seekToLineEnd();
        try t.expectEqual(0, lr.end);

        lr.reset("line", 0);
        lr.seekToLineEnd();
        try t.expectEqual(4, lr.end);

        lr.reset("line", 4);
        lr.seekToLineEnd();
        try t.expectEqual(4, lr.end);

        lr.reset("\n\n", 0);
        lr.seekToLineEnd();
        try t.expectEqual(0, lr.end);

        lr.reset("\n\n", 1);
        lr.seekToLineEnd();
        try t.expectEqual(1, lr.end);

        lr.reset("line\n", 1);
        lr.seekToLineEnd();
        try t.expectEqual(4, lr.end);
    }
    // [seekToLineEndUntil()]
    {
        lr.reset("line\n", 1);
        //         ^ ^
        lr.seekToLineEndUntil(3);
        try t.expectEqual(3, lr.end);

        lr.reset("line\n", 1);
        //         ^  ^
        lr.seekToLineEndUntil(4);
        try t.expectEqual(4, lr.end);

        lr.reset("line\n", 1);
        //         ^    ^
        lr.seekToLineEndUntil(5);
        try t.expectEqual(4, lr.end);
    }
    // [readLine()]
    {
        lr.reset("line1\nline2\nline3", 0);
        //        ^
        try lr.readLine();
        try t.expectEqualStrings("line1", lr.line());

        lr.reset("line1\nline2\nline3", 8);
        //                 ^
        try lr.readLine();
        try t.expectEqualStrings("line2", lr.line());

        lr.reset("line1\nline2\nline3", 12);
        //                      ^
        try lr.readLine();
        try t.expectEqualStrings("line3", lr.line());
    }
    // [readLineWithin()]
    {
        lr.reset("line1\nline2\nline3", 8);
        //                789
        try lr.readLineWithin(7, 9);
        try t.expectEqualStrings("in", lr.line());
    }
    // [readLinesAmt()]
    {
        const input = "line1\nline2\nline3";

        lr.reset(input, 1);
        try lr.readLinesAmt(.right, 0);
        try t.expectEqual(0, lr.len());

        // [.right]

        lr.reset(input, 0);
        try lr.readLinesAmt(.right, 2);
        try t.expectEqual(2, lr.len());
        for (&[_][]const u8{ "line1", "line2" }, lr.lines.slice()) |e, a| {
            try t.expectEqualStrings(e, a);
        }

        lr.reset(input, 0);
        try lr.readLinesAmt(.right, 4);
        try t.expectEqual(3, lr.len());
        for (&[_][]const u8{ "line1", "line2", "line3" }, lr.lines.slice()) |e, a| {
            try t.expectEqualStrings(e, a);
        }

        lr.reset(input, input.len);
        try lr.readLinesAmt(.right, 4);
        try t.expectEqual(1, lr.len());
        for (&[_][]const u8{"line3"}, lr.lines.slice()) |e, a| {
            try t.expectEqualStrings(e, a);
        }

        // [.left]
        lr.reset(input, 0);
        try lr.readLinesAmt(.left, 2);
        try t.expectEqual(1, lr.len());
        for (&[_][]const u8{"line1"}, lr.lines.slice()) |e, a| {
            try t.expectEqualStrings(e, a);
        }

        lr.reset(input, input.len);
        try lr.readLinesAmt(.left, 2);
        try t.expectEqual(2, lr.len());
        for (&[_][]const u8{ "line3", "line2" }, lr.lines.slice()) |e, a| {
            try t.expectEqualStrings(e, a);
        }

        lr.reset(input, input.len);
        try lr.readLinesAmt(.left, 4);
        try t.expectEqual(3, lr.len());
        for (&[_][]const u8{ "line3", "line2", "line1" }, lr.lines.slice()) |e, a| {
            try t.expectEqualStrings(e, a);
        }
    }
}
