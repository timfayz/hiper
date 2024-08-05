// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

const std = @import("std");

/// Retrieves the ending position of a line.
pub fn indexOfLineEnd(input: [:0]const u8, index: usize) usize {
    if (index >= input.len) return input.len;
    return indexOfLineEndImpl(input, index);
}

/// Retrieves the starting position of a line.
pub fn indexOfLineStart(input: [:0]const u8, index: usize) usize {
    if (index >= input.len)
        return indexOfLineStartImpl(input, input.len);
    return indexOfLineStartImpl(input, index);
}

/// Retrieves the ending position of a line without boundary checks.
inline fn indexOfLineEndImpl(input: [:0]const u8, index: usize) usize {
    var i: usize = index;
    while (true) : (i += 1) {
        if (input[i] == '\n') break;
        if (i == input.len) break;
    }
    return i;
}

/// Retrieves the starting position of a line without boundary checks.
inline fn indexOfLineStartImpl(input: [:0]const u8, index: usize) usize {
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

test "test indexOfLineEnd/Start" {
    const t = std.testing;

    const case = struct {
        pub fn runStart(input: [:0]const u8, args: struct { at: usize, expect: usize }) !void {
            try t.expectEqual(args.expect, indexOfLineStart(input, args.at));
        }

        pub fn runEnd__(input: [:0]const u8, args: struct { at: usize, expect: usize }) !void {
            try t.expectEqual(args.expect, indexOfLineEnd(input, args.at));
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
    try t.expectEqual(3, countIntLen(999));
    try t.expectEqual(
        std.fmt.comptimePrint("{d}", .{std.math.maxInt(u32)}).len,
        countIntLen(std.math.maxInt(u32)),
    );
}

/// Computes the number of lines in the input.
pub fn countLineNumber(input: [:0]const u8, index: usize) usize {
    const idx = if (index > input.len) input.len else index; // normalize

    // spacial case: index at the first empty line
    if (idx == 0 and input[0] == '\n') return 1;

    // general case
    var line_number: usize = 1;
    var i: usize = 0;
    while (i < idx) : (i += 1) {
        if (input[i] == '\n') line_number += 1;
    }
    return line_number;
}

test "test countLineNumber" {
    const t = std.testing;

    try t.expectEqual(1, countLineNumber("", 0));
    try t.expectEqual(1, countLineNumber("", 100));

    try t.expectEqual(1, countLineNumber("\n", 0));
    //                                    ^ (1 line)
    try t.expectEqual(2, countLineNumber("\n", 1));
    //                                      ^ (2 line)
    try t.expectEqual(2, countLineNumber("\n", 100));
    //                                      ^ (2 line)
    try t.expectEqual(2, countLineNumber("\n\n", 1));
    //                                       ^ (2 line)
    try t.expectEqual(3, countLineNumber("\n\n", 2));
    //                                        ^ (3 line)

    try t.expectEqual(1, countLineNumber("l1\nl2\nl3", 0));
    //                                    ^ (1 line)
    try t.expectEqual(2, countLineNumber("l1\nl2\nl3", 3));
    //                                        ^ (2 line)
    try t.expectEqual(3, countLineNumber("l1\nl2\nl3", 6));
    //                                            ^ (3 line)
}

/// Implementation function. Should not be used directly.
inline fn readLineTrimmedImpl(
    writer: anytype,
    input: [:0]const u8,
    line_start: usize,
    line_end: usize,
    comptime opt: LineReaderOptions,
) !void {
    const line_len = line_end - line_start;
    if (line_len <= opt.max_line_width) {
        try writer.writeAll(input[line_start..line_end]);
        if (opt.show_eof and input[line_end] == 0) try writer.writeAll("␃");
    } else {
        switch (opt.trim_alignment) {
            .right => {
                try writer.writeAll(input[line_start .. line_start + opt.max_line_width]);
                try writer.writeAll("..");
            },
            .left => {
                try writer.writeAll("..");
                try writer.writeAll(input[line_end - opt.max_line_width .. line_end]);
                if (opt.show_eof and input[line_end] == 0) try writer.writeAll("␃");
            },
        }
    }

    try writer.writeAll("\n");
}

const TrimAlignment = enum { left, right };
const ReadAt = struct { index: usize, line_number: usize = 0 };

pub const LineReaderOptions = struct {
    show_line_numbers: bool = true,
    line_number_sep: []const u8 = " | ",
    max_line_width: u8 = 80,
    trim_alignment: TrimAlignment = .right,
    show_eof: bool = true,
};

/// Reads a line from the input at the specified index and writes it to the
/// writer. If `line_number` is 0, it is automatically detected. Otherwise, the
/// specified number is used as is. See `LineReaderOptions` for additional
/// options.
pub fn readLine(
    writer: anytype,
    input: [:0]const u8,
    at: ReadAt,
    comptime opt: LineReaderOptions,
) !void {
    if (opt.max_line_width < 1) @compileError("max_line_width cannot be less than one");

    const idx = if (at.index > input.len) input.len else at.index; // normalize
    const line_start = indexOfLineStartImpl(input, idx);
    const line_end = indexOfLineEndImpl(input, idx);

    // line index
    if (opt.show_line_numbers) {
        const line_number = if (at.line_number == 0) countLineNumber(input, idx) else at.line_number;
        try writer.print("{d}" ++ opt.line_number_sep, .{line_number});
    }

    // line
    try readLineTrimmedImpl(writer, input, line_start, line_end, opt);
}

test "test readLine" {
    const t = std.testing;

    // test line and cursor rendering
    const case = struct {
        pub fn run(input: [:0]const u8, at: ReadAt, comptime opt: LineReaderOptions, expect: []const u8) !void {
            var out = std.ArrayList(u8).init(t.allocator);
            defer out.deinit();
            try readLine(out.writer(), input, .{
                .index = at.index,
                .line_number = at.line_number,
            }, opt);
            try t.expectEqualStrings(expect, out.items);
        }
    };

    // .show_eof

    try case.run("", .{ .index = 0 }, .{ .show_eof = false },
        \\1 | 
        \\
    );

    // .show_line_numbers

    try case.run("", .{ .index = 0 }, .{ .show_eof = false, .show_line_numbers = false },
        \\
        \\
    );

    try case.run("", .{ .index = 0 }, .{ .show_line_numbers = false },
        \\␃
        \\
    );

    try case.run("", .{ .index = 0 }, .{},
        \\1 | ␃
        \\
    );

    // manual and automatic line detection

    try case.run("hello", .{ .index = 0, .line_number = 2 }, .{},
        \\2 | hello␃
        \\
    );

    try case.run("hello", .{ .index = 0, .line_number = 0 }, .{},
        \\1 | hello␃
        \\
    );

    // .line_number_sep

    try case.run("hello", .{ .index = 0 }, .{ .line_number_sep = "__" },
        \\1__hello␃
        \\
    );

    try case.run("hello", .{ .index = 0 }, .{ .line_number_sep = "" },
        \\1hello␃
        \\
    );

    // .max_line_width and .trim_alignment

    try case.run("hello", .{ .index = 0 }, .{
        .max_line_width = 3,
        .trim_alignment = .right,
    },
        \\1 | hel..
        \\
    );

    try case.run("hello", .{ .index = 0 }, .{
        .max_line_width = 3,
        .trim_alignment = .left,
    },
        \\1 | ..llo␃
        \\
    );

    const input =
        \\first line
        //^0        ^10
        \\second line
        //^11        ^22
        \\
        //^23
    ;

    try case.run(input, .{ .index = 0 }, .{},
        \\1 | first line
        \\
    );

    try case.run(input, .{ .index = 5 }, .{},
        \\1 | first line
        \\
    );

    try case.run(input, .{ .index = 12 }, .{},
        \\2 | second line
        \\
    );

    try case.run(input, .{ .index = 22 }, .{},
        \\2 | second line
        \\
    );

    try case.run(input, .{ .index = 100 }, .{},
        \\3 | ␃
        \\
    );
}
