// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

const std = @import("std");

const PrinterOptions = struct {
    show_line_numbers: bool = true,
    show_cursor_hint: bool = true,
    visible_char_hints: bool = false,
    cursor_head_char: u8 = '^',
    cursor_body_char: u8 = '~',
    // cursor_tail_char: u8 = '~',
};

/// Initializes a line printer with the given printing options.
pub fn Printer(opt: PrinterOptions) type {
    return struct {
        /// Returns a single line of text from the given input, along with a
        /// cursor position and optional line number and hint. `at.line` specifies
        /// the current line number of the `at.index`.
        pub fn getLine(
            alloc: std.mem.Allocator,
            input: [:0]const u8,
            at: struct { index: usize, line: usize },
        ) ![]u8 {
            var out = std.ArrayListUnmanaged(u8){};
            const index = if (at.index > input.len) input.len else at.index;
            const line_start = getLineStartPosImpl(input, index);
            const line_end = getLineEndPosImpl(input, index);

            // line
            try out.writer(alloc).print("{d} | ", .{at.line});
            try out.writer(alloc).print("{s}", .{input[line_start..line_end]});
            if (input[index] == 0) try out.appendSlice(alloc, "␃"); // end of string marker
            try out.append(alloc, '\n');

            // cursor
            try out.appendNTimes(alloc, ' ', countIntLen(at.line) + 3 + (index - line_start));
            try out.append(alloc, opt.cursor_head_char);
            const hint = getCursorHint(input, index);
            if (hint.len > 0) {
                try out.append(alloc, ' ');
                try out.appendSlice(alloc, hint);
            }
            try out.append(alloc, '\n');

            return try out.toOwnedSlice(alloc);
        }

        /// Returns a hint about the character at the specified index.
        pub fn getCursorHint(input: [:0]const u8, index: usize) []const u8 {
            if (!opt.show_cursor_hint) return "";
            if (index >= input.len) return "(end of string)";
            switch (input[index]) {
                '\n' => return "(newline)",
                ' ' => return "(space)",
                inline '!'...'~' => |char| {
                    if (opt.visible_char_hints)
                        return std.fmt.comptimePrint("('\\x{x}')", .{char})
                    else
                        return "";
                },
                else => return "",
            }
        }
    };
}

test "test Printer" {
    const t = std.testing;
    {
        const p = Printer(.{
            .show_cursor_hint = true,
            .visible_char_hints = true,
        });
        try t.expectEqualStrings("(end of string)", p.getCursorHint("a", 5));
        try t.expectEqualStrings("(space)", p.getCursorHint(" ", 0));
        try t.expectEqualStrings("('\\x21')", p.getCursorHint("!", 0));
        try t.expectEqualStrings("('\\x7e')", p.getCursorHint("~", 0));
    }

    const case = struct {
        pub fn run(input: [:0]const u8, args: struct { index: usize, line: usize }, expect: []const u8) !void {
            const p = Printer(.{
                .show_cursor_hint = true,
                .visible_char_hints = false,
            });
            const res = try p.getLine(t.allocator, input, .{ .index = args.index, .line = args.line });
            defer t.allocator.free(res);
            try t.expectEqualStrings(expect, res[0 .. res.len - 1]);
        }
    };

    const input =
        \\line1
        \\line2
        \\
    ;
    try case.run(input, .{ .index = 0, .line = 42 },
        \\42 | line1
        \\     ^
    );
    try case.run(input, .{ .index = 5, .line = 42 },
        \\42 | line1
        \\          ^ (newline)
    );
    try case.run(input, .{ .index = 6, .line = 42 },
        \\42 | line2
        \\     ^
    );
    try case.run(input, .{ .index = 100, .line = 42 },
        \\42 | ␃
        \\     ^ (end of string)
    );
}

/// Retrieves the ending position of a line.
pub fn getLineEndPos(input: [:0]const u8, index: usize) usize {
    if (index >= input.len) return input.len;
    return getLineEndPosImpl(input, index);
}

/// Retrieves the starting position of a line.
pub fn getLineStartPos(input: [:0]const u8, index: usize) usize {
    if (index >= input.len)
        return getLineStartPosImpl(input, input.len);
    return getLineStartPosImpl(input, index);
}

/// Retrieves the ending position of a line without boundary checks.
inline fn getLineEndPosImpl(input: [:0]const u8, index: usize) usize {
    var i: usize = index;
    while (true) : (i += 1) {
        if (input[i] == '\n') break;
        if (i == input.len) break;
    }
    return i;
}

/// Retrieves the starting position of a line without boundary checks.
inline fn getLineStartPosImpl(input: [:0]const u8, index: usize) usize {
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

test "test getLineEnd/StartPos" {
    const t = std.testing;

    const case = struct {
        pub fn runStart(input: [:0]const u8, args: struct { at: usize, expect: usize }) !void {
            try t.expectEqual(args.expect, getLineStartPos(input, args.at));
        }

        pub fn runEnd__(input: [:0]const u8, args: struct { at: usize, expect: usize }) !void {
            try t.expectEqual(args.expect, getLineEndPos(input, args.at));
        }
    };

    try case.runStart("", .{ .at = 0, .expect = 0 });
    try case.runEnd__("", .{ .at = 0, .expect = 0 });

    try case.runStart("\n", .{ .at = 0, .expect = 0 });
    try case.runEnd__("\n", .{ .at = 0, .expect = 0 });

    try case.runStart("\n\n", .{ .at = 1, .expect = 1 });
    try case.runEnd__("\n\n", .{ .at = 0, .expect = 0 });

    try case.runStart("line", .{ .at = 2, .expect = 0 });
    try case.runEnd__("line", .{ .at = 2, .expect = 4 });

    try case.runStart("line\n", .{ .at = 10, .expect = 5 });
    try case.runEnd__("line\n", .{ .at = 10, .expect = 5 });
    // "line\n"[5..5] -> "" (correct behavior for 0-terminated strings)

    try case.runStart("\nline2\n", .{ .at = 3, .expect = 1 });
    try case.runEnd__("\nline2\n", .{ .at = 3, .expect = 6 });
    //                   ^ ^  ^
    //                   1 3  6
}

/// Computes the length of an integer.
fn countIntLen(int: usize) usize {
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

test "test countIntLen" {
    const t = std.testing;

    try t.expectEqual(1, countIntLen(0));
    try t.expectEqual(1, countIntLen(1));
    try t.expectEqual(1, countIntLen(9));
    try t.expectEqual(2, countIntLen(10));
    try t.expectEqual(2, countIntLen(11));
    try t.expectEqual(2, countIntLen(99));
    try t.expectEqual(3, countIntLen(100));
    try t.expectEqual(3, countIntLen(101));
    try t.expectEqual(10, countIntLen(std.math.maxInt(u32)));
}
