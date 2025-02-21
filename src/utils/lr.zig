// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

//! Public API:
//! - LineReader

const std = @import("std");
const stack = @import("stack.zig");
const slice = @import("slice.zig");
const range = @import("range.zig");
const assert = std.debug.assert;

pub const LineReader = struct {
    lines: stack.Stack([]const u8, 512) = .{},
    input: []const u8,
    start: usize,
    end: usize,

    pub fn init(input: []const u8, index: usize) LineReader {
        return .{
            .lines = .{},
            .input = input,
            .start = index,
            .end = index,
        };
    }

    pub fn reset(l: *LineReader, input: []const u8, index: usize) void {
        l.* = LineReader{
            .lines = .{},
            .input = input,
            .start = index,
            .end = index,
        };
    }

    pub fn clearPushed(l: *LineReader) void {
        l.lines.reset();
    }

    pub fn setPos(l: *LineReader, index: usize) void {
        l.start = index;
        l.end = index;
    }

    pub fn setRange(l: *LineReader, start: usize, end: usize) void {
        l.start = start;
        l.end = end;
    }

    pub fn movePosRight(l: *LineReader, amt: usize) void {
        l.end +|= amt;
        l.start = l.end;
    }

    pub fn movePosLeft(l: *LineReader, amt: usize) void {
        l.start -|= amt;
        l.end = l.start;
    }

    pub fn line(l: *const LineReader) []const u8 {
        return l.input[l.start..l.end];
    }

    pub fn endIsLineEnd(l: *const LineReader) bool {
        return l.end == l.input.len or l.input.len == 0 or l.input[l.end] == '\n';
    }

    pub fn startIsLineStart(l: *const LineReader) bool {
        return l.start == 0 or l.input.len == 0 or l.input[l.start - 1] == '\n';
    }

    pub fn truncatedLineSide(l: *const LineReader) range.Side {
        return if (l.startIsLineStart() and l.endIsLineEnd())
            .none
        else if (l.startIsLineStart())
            .right
        else if (l.endIsLineEnd())
            .left
        else
            .both;
    }

    pub fn pushLine(l: *LineReader) !void {
        try l.lines.push(l.input[l.start..l.end]);
    }

    pub fn totalPushed(l: *const LineReader) usize {
        return l.lines.len;
    }

    pub fn pushed(l: *LineReader) [][]const u8 {
        return l.lines.slice();
    }

    pub fn reversePushed(l: *LineReader) void {
        slice.reverse(l.pushed());
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

    pub fn seekLineWithin(l: *LineReader, within: range.Range) void {
        assert(within.start <= l.start);
        assert(within.end >= l.end);
        l.seekLineStartUntil(within.start);
        l.seekLineEndUntil(within.end);
    }

    pub fn seekAndPushLine(l: *LineReader) !void {
        l.seekLine();
        try l.pushLine();
    }

    pub fn seekAndPushLineWithin(l: *LineReader, within: range.Range) !void {
        l.seekLineWithin(within);
        try l.pushLine();
    }

    pub fn seekAndPushLines(l: *LineReader, comptime dir: range.Dir, amt: ?usize) !void {
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
        l: *LineReader,
        comptime dir: range.Dir,
        within: range.Range,
        amt: ?usize,
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

    pub fn seekAndPushLineRange(l: *LineReader, comptime line_range: range.View) !usize {
        if (line_range.len() == 0) return 0;
        const plan = line_range.toPair(.{ .rshift_uneven = false });

        try l.seekAndPushLines(.left, plan.left);
        if (l.totalPushed() > 1) l.reversePushed();
        const curr_line_idx: usize = l.totalPushed() -| 1;
        if (l.topLineIndexOf(.end)) |next| l.setPos(next +| 1);
        if (l.reachedEOF()) return curr_line_idx;
        try l.seekAndPushLines(.right, plan.right);
        return curr_line_idx;
    }

    pub fn lineContainsIndex(l: *const LineReader, index: usize) bool {
        return index >= l.start and index <= l.end;
    }

    pub fn topLine(l: *const LineReader) ?[]const u8 {
        return l.lines.topOrNull();
    }

    pub fn bottomLine(l: *const LineReader) ?[]const u8 {
        return l.lines.bottomOrNull();
    }

    pub fn topLineIndexOf(l: *const LineReader, comptime edge: enum { start, end }) ?usize {
        if (l.topLine()) |top_line| {
            return switch (edge) {
                .start => slice.startIndex(l.input, top_line),
                .end => slice.endIndex(l.input, top_line),
            };
        } else return null;
    }

    pub fn bottomLineIndexOf(l: *const LineReader, comptime edge: enum { start, end }) ?usize {
        if (l.bottomLine()) |bottom_line| {
            return switch (edge) {
                .start => slice.startIndex(l.input, bottom_line),
                .end => slice.endIndex(l.input, bottom_line),
            };
        } else return null;
    }
};

test LineReader {
    const t = std.testing;
    var lr = LineReader.init("", 0);

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
    // [truncatedLineSide()]
    {
        lr.reset("\nline\n", 3);
        //        0 12345 6
        lr.setRange(2, 3);
        try t.expectEqual(.both, lr.truncatedLineSide());

        lr.setRange(1, 5);
        try t.expectEqual(.none, lr.truncatedLineSide());

        lr.setRange(1, 3);
        try t.expectEqual(.right, lr.truncatedLineSide());

        lr.setRange(3, 5);
        try t.expectEqual(.left, lr.truncatedLineSide());
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
        try lr.seekAndPushLinesWithin(.right, .{ .start = 0, .end = 5 }, 0, true);
        try t.expectEqual(0, lr.totalPushed());

        // [.right]

        lr.reset(input, 3);
        try lr.seekAndPushLinesWithin(.right, .{ .start = 2, .end = 14 }, 2, true);
        try t.expectEqual(2, lr.totalPushed());
        for (&[_][]const u8{ "ne1", "line2" }, lr.pushed()) |e, a| {
            try t.expectEqualStrings(e, a);
        }

        lr.reset(input, 3);
        try lr.seekAndPushLinesWithin(.right, .{ .start = 2, .end = 14 }, 4, true);
        try t.expectEqual(3, lr.totalPushed());
        for (&[_][]const u8{ "ne1", "line2", "li" }, lr.pushed()) |e, a| {
            try t.expectEqualStrings(e, a);
        }
        // pos is on the last read line
        try t.expectEqual(12, lr.start);
        try t.expectEqual(14, lr.end);

        lr.reset(input, 3); // edge: index == within.end
        try lr.seekAndPushLinesWithin(.right, .{ .start = 2, .end = 3 }, 4, true);
        try t.expectEqual(1, lr.totalPushed());
        for (&[_][]const u8{"n"}, lr.pushed()) |e, a| {
            try t.expectEqualStrings(e, a);
        }

        // [.left]

        lr.reset(input, 14);
        try lr.seekAndPushLinesWithin(.left, .{ .start = 2, .end = 14 }, 2, true);
        try t.expectEqual(2, lr.totalPushed());
        for (&[_][]const u8{ "li", "line2" }, lr.pushed()) |e, a| {
            try t.expectEqualStrings(e, a);
        }

        lr.reset(input, 14);
        try lr.seekAndPushLinesWithin(.left, .{ .start = 2, .end = 14 }, 4, true);
        try t.expectEqual(3, lr.totalPushed());
        for (&[_][]const u8{ "li", "line2", "ne1" }, lr.pushed()) |e, a| {
            try t.expectEqualStrings(e, a);
        }
        // pos is on the last read line
        try t.expectEqual(2, lr.start);
        try t.expectEqual(5, lr.end);

        lr.reset(input, 2); // edge: index == within.start
        try lr.seekAndPushLinesWithin(.left, .{ .start = 2, .end = 3 }, 4, true);
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
}
