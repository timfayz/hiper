// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

const std = @import("std");
const stack = @import("stack.zig");
const slice = @import("slice.zig");
const range = @import("range.zig");
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

    pub fn movePosRight(l: *LineReader, amt: usize) void {
        l.end +|= amt;
        l.start = l.end;
    }

    pub fn movePosLeft(l: *LineReader, amt: usize) void {
        l.start -|= amt;
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

    pub fn reachedEOF(l: *const LineReader) bool {
        return l.end >= l.input.len;
    }

    pub fn reachedZero(l: *const LineReader) bool {
        return l.start == 0;
    }

    pub fn seekLineStart(l: *LineReader) void {
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

    pub fn seekLineStartUntil(l: *LineReader, until: usize) void {
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

    pub fn seekLineEnd(l: *LineReader) void {
        assert(l.end <= l.input.len);
        while (l.end < l.input.len and l.input[l.end] != '\n') l.end += 1;
    }

    pub fn seekLineEndUntil(l: *LineReader, until: usize) void {
        assert(l.end <= l.input.len);
        while (l.end < l.input.len and l.end != until and
            l.input[l.end] != '\n') l.end += 1;
    }

    pub fn seekLine(l: *LineReader) void {
        l.seekLineStart();
        l.seekLineEnd();
    }

    pub fn seekLineAndPush(l: *LineReader) !void {
        l.seekLine();
        try l.pushLine();
    }

    pub fn seekLineWithin(l: *LineReader, within: range.Range) void {
        assert(within.start <= l.start);
        assert(within.end >= l.end);
        l.seekLineStartUntil(within.start);
        l.seekLineEndUntil(within.end);
    }

    pub fn seekLineWithinAndPush(l: *LineReader, within: range.Range) !void {
        l.seekLineWithin(within);
        try l.pushLine();
    }

    pub fn seekLinesAndPush(l: *LineReader, comptime dir: range.Dir, amt: ?usize) !void {
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

    pub fn seekLinesWithinAndPush(
        l: *LineReader,
        comptime dir: range.Dir,
        within: range.Range,
        amt: ?usize,
    ) !void {
        assert(within.start <= l.start);
        assert(within.end >= l.end);
        var left = amt orelse std.math.maxInt(usize);
        if (left == 0)
            return;

        switch (dir) {
            .right => {
                l.seekLineStartUntil(within.start);
                while (true) {
                    l.seekLineEndUntil(within.end);
                    try l.pushLine();
                    left -= 1;
                    if (l.reachedEOF() or l.end == within.end or left == 0) break;
                    l.movePosRight(1);
                }
            },
            .left => {
                l.seekLineEndUntil(within.end);
                while (true) {
                    l.seekLineStartUntil(within.start);
                    try l.pushLine();
                    left -= 1;
                    if (l.reachedZero() or l.start == within.start or left == 0) break;
                    l.movePosLeft(1);
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

    // [seekLineStart()]
    {
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
    // [seekLineAndPush()]
    {
        lr.reset("line1\nline2\nline3", 0);
        //        ^
        try lr.seekLineAndPush();
        try t.expectEqualStrings("line1", lr.line());

        lr.reset("line1\nline2\nline3", 8);
        //                 ^
        try lr.seekLineAndPush();
        try t.expectEqualStrings("line2", lr.line());

        lr.reset("line1\nline2\nline3", 12);
        //                      ^
        try lr.seekLineAndPush();
        try t.expectEqualStrings("line3", lr.line());
    }
    // [seekLineWithinAndPush()]
    {
        lr.reset("line1\nline2\nline3", 8);
        //                789
        try lr.seekLineWithinAndPush(.{ .start = 7, .end = 9 });
        try t.expectEqualStrings("in", lr.line());
    }
    // [seekLinesAndPush()]
    {
        const input = "line1\nline2\nline3";
        //             ^0  ^4 ^6  ^10^11 ^15

        lr.reset(input, 1);
        try lr.seekLinesAndPush(.right, 0);
        try t.expectEqual(0, lr.len());

        // [.right]

        lr.reset(input, 0);
        try lr.seekLinesAndPush(.right, 2);
        try t.expectEqual(2, lr.len());
        for (&[_][]const u8{ "line1", "line2" }, lr.lines.slice()) |e, a| {
            try t.expectEqualStrings(e, a);
        }
        // pos is on the last read line
        try t.expectEqual(6, lr.start);
        try t.expectEqual(11, lr.end);

        lr.reset(input, 0);
        try lr.seekLinesAndPush(.right, 4);
        try t.expectEqual(3, lr.len());
        for (&[_][]const u8{ "line1", "line2", "line3" }, lr.lines.slice()) |e, a| {
            try t.expectEqualStrings(e, a);
        }

        lr.reset(input, input.len);
        try lr.seekLinesAndPush(.right, 4);
        try t.expectEqual(1, lr.len());
        for (&[_][]const u8{"line3"}, lr.lines.slice()) |e, a| {
            try t.expectEqualStrings(e, a);
        }

        // [.left]
        lr.reset(input, 0);
        try lr.seekLinesAndPush(.left, 2);
        try t.expectEqual(1, lr.len());
        for (&[_][]const u8{"line1"}, lr.lines.slice()) |e, a| {
            try t.expectEqualStrings(e, a);
        }

        lr.reset(input, input.len);
        try lr.seekLinesAndPush(.left, 2);
        try t.expectEqual(2, lr.len());
        for (&[_][]const u8{ "line3", "line2" }, lr.lines.slice()) |e, a| {
            try t.expectEqualStrings(e, a);
        }
        // pos is on the last read line
        try t.expectEqual(6, lr.start);
        try t.expectEqual(11, lr.end);

        lr.reset(input, input.len);
        try lr.seekLinesAndPush(.left, 4);
        try t.expectEqual(3, lr.len());
        for (&[_][]const u8{ "line3", "line2", "line1" }, lr.lines.slice()) |e, a| {
            try t.expectEqualStrings(e, a);
        }
    }
    // [seekLinesWithinAndPush()]
    {
        const input = "line1\nline2\nline3";
        //             ^0  ^4 ^6  ^10^12 ^16

        lr.reset(input, 1);
        try lr.seekLinesWithinAndPush(.right, .{ .start = 0, .end = 5 }, 0);
        try t.expectEqual(0, lr.len());

        // [.right]

        lr.reset(input, 3);
        try lr.seekLinesWithinAndPush(.right, .{ .start = 2, .end = 14 }, 2);
        try t.expectEqual(2, lr.len());
        for (&[_][]const u8{ "ne1", "line2" }, lr.lines.slice()) |e, a| {
            try t.expectEqualStrings(e, a);
        }

        lr.reset(input, 3);
        try lr.seekLinesWithinAndPush(.right, .{ .start = 2, .end = 14 }, 4);
        try t.expectEqual(3, lr.len());
        for (&[_][]const u8{ "ne1", "line2", "li" }, lr.lines.slice()) |e, a| {
            try t.expectEqualStrings(e, a);
        }
        // pos is on the last read line
        try t.expectEqual(12, lr.start);
        try t.expectEqual(14, lr.end);

        lr.reset(input, 3); // edge: index == within.end
        try lr.seekLinesWithinAndPush(.right, .{ .start = 2, .end = 3 }, 4);
        try t.expectEqual(1, lr.len());
        for (&[_][]const u8{"n"}, lr.lines.slice()) |e, a| {
            try t.expectEqualStrings(e, a);
        }

        // [.left]

        lr.reset(input, 14);
        try lr.seekLinesWithinAndPush(.left, .{ .start = 2, .end = 14 }, 2);
        try t.expectEqual(2, lr.len());
        for (&[_][]const u8{ "li", "line2" }, lr.lines.slice()) |e, a| {
            try t.expectEqualStrings(e, a);
        }

        lr.reset(input, 14);
        try lr.seekLinesWithinAndPush(.left, .{ .start = 2, .end = 14 }, 4);
        try t.expectEqual(3, lr.len());
        for (&[_][]const u8{ "li", "line2", "ne1" }, lr.lines.slice()) |e, a| {
            try t.expectEqualStrings(e, a);
        }
        // pos is on the last read line
        try t.expectEqual(2, lr.start);
        try t.expectEqual(5, lr.end);

        lr.reset(input, 2); // edge: index == within.start
        try lr.seekLinesWithinAndPush(.left, .{ .start = 2, .end = 3 }, 4);
        try t.expectEqual(1, lr.len());
        for (&[_][]const u8{"n"}, lr.lines.slice()) |e, a| {
            try t.expectEqualStrings(e, a);
        }
    }
}
