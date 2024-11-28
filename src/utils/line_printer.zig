// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

//! Public API:
//! - PrintLineOptions
//! - printLine()
//! - printLineWithCursor()

const std = @import("std");
const lr = @import("line_reader.zig");
const slice = @import("slice.zig");
const num = @import("num.zig");

/// Line printing options.
pub const PrintLineOptions = struct {
    line_len: usize = 80,
    trunc_sym: []const u8 = "..",
    /// Applies only when printing mode is `.cursor`.
    trunc_mode: slice.SegAroundMode = .hard_flex,
    show_line_num: bool = true,
    line_num_sep: []const u8 = "| ",
    show_eof: bool = true,
    /// The size of stack-allocated buffer, representing the maximum amount
    /// of lines that can be read (upper bound).
    buf_size: usize = 256,

    // applies only when `.show_cursor = true`
    show_cursor: bool = false,
    show_cursor_hint: bool = true,
    hint_printable_chars: bool = false,
    cursor_head_char: u8 = '^',
    cursor_body_char: u8 = '~',
};

/// Specifies which part of the line(s) should be rendered. Each mode optionally
/// allows specifying `curr_ln` to adjust relative line numbering (either
/// auto-detected or explicitly set).
pub const PrintLineMode = union(enum) {
    start: struct { index: usize, curr_ln: lr.CurrLineNum = .detect },
    end: struct { index: usize, curr_ln: lr.CurrLineNum = .detect },
    cursor: struct { index: usize, curr_ln: lr.CurrLineNum = .detect },
    range: struct { index_start: usize, index_end: usize, curr_ln: lr.CurrLineNum = .detect },

    pub inline fn curr_ln(self: *const PrintLineMode) lr.CurrLineNum {
        return switch (self.*) {
            inline else => |any| any.curr_ln,
        };
    }

    pub inline fn index(self: *const PrintLineMode) usize {
        return switch (self.*) {
            .range => |r| r.index_start,
            inline else => |any| any.index,
        };
    }
};

/// Prints the specified `amount` of lines from `input` based on the given
/// `mode`, writes them to the `writer`, and calculates line numbers relative
/// to the current line number (`curr_ln`) determined by `mode`. If the `mode`
/// specifies indices beyond `input.len`, no lines will be read or written.
/// Refer to `PrintLineOptions` for output formatting details.
fn printLine(
    writer: anytype,
    input: []const u8,
    mode: PrintLineMode,
    amount: lr.ReadRequest,
    comptime opt: PrintLineOptions,
) !void {
    var buf: [opt.buf_size][]const u8 = undefined;

    // ensure index <= index_end when reading mode is .range
    const index_start, const index_end: ?usize = switch (mode) {
        .range => |r| if (r.index_start <= r.index_end) .{ r.index_start, r.index_end } else .{ r.index_end, r.index_start },
        inline else => |any| .{ any.index, null },
    };

    // read first index
    const info = lr.readLines(&buf, input, index_start, mode.curr_ln(), amount);
    if (info.isEmpty()) return;

    // calc cursor line indices
    const cursor_len = if (opt.line_len == 0) std.math.maxInt(usize) else opt.line_len;
    const cursor_indices: slice.SegAroundRangeIndices = switch (mode) {
        .start => blk: {
            const indices = slice.segStartIndices(info.currLine(), cursor_len);
            break :blk .{ .start = indices.start, .end = indices.end, .start_pos = 0, .end_pos = 0 };
        },
        .end => blk: {
            const indices = slice.segEndIndices(info.currLine(), cursor_len);
            break :blk .{ .start = indices.start, .end = indices.end, .start_pos = 0, .end_pos = 0 };
        },
        .cursor => blk: {
            const indices = slice.segAroundIndices(info.currLine(), info.index_pos, cursor_len, .{ .slicing_mode = opt.trunc_mode });
            break :blk .{ .start = indices.start, .end = indices.end, .start_pos = indices.index_pos, .end_pos = 0 };
        },
        .range => blk: {
            const range_len = index_end.? - index_start;
            break :blk slice.segAroundRangeIndices(info.currLine(), info.index_pos, info.index_pos + range_len, cursor_len);
        },
    };

    const num_col_len = if (opt.show_line_num) num.countIntLen(info.lastLineNum()) else 0;
    const num_col_sep_len = if (opt.show_line_num) opt.line_num_sep.len else 0;

    // render lines
    for (info.lines, info.firstLineNum().., 0..) |line, line_num, i| {
        if (opt.show_line_num) try writeLineNum(writer, line_num, num_col_len, opt);
        const trim_len = try writeLine(writer, input, line, cursor_indices, opt);
        // cursor
        if (opt.show_cursor and info.curr_line_pos == i) {
            const extra_pad = num_col_len + num_col_sep_len + trim_len;
            try writeCursor(writer, input, mode, cursor_indices, extra_pad, opt);
        }
    }
}

/// A simple wrapper around `printLine` that enables cursor rendering by
/// setting `PrintLineOptions.show_cursor` to `true`. See `printLine` for
/// more details.
fn printLineWithCursor(
    writer: anytype,
    input: []const u8,
    mode: PrintLineMode,
    amount: lr.ReadRequest,
    comptime opt: PrintLineOptions,
) !void {
    comptime var opt_ = opt;
    opt_.show_cursor = true;
    return printLine(writer, input, mode, amount, opt_);
}

/// Implementation function.
inline fn writeLineNum(
    writer: anytype,
    line_num: usize,
    pad_size: usize,
    comptime opt: PrintLineOptions,
) !void {
    try writer.print("{d: <[1]}" ++ opt.line_num_sep, .{ line_num, pad_size });
}

/// Implementation function.
fn writeLine(
    writer: anytype,
    input: []const u8,
    line: []const u8,
    cursor: slice.SegAroundRangeIndices,
    comptime opt: PrintLineOptions,
) !usize {
    var trunc_len: usize = 0;
    // full line
    if (opt.line_len == 0) {
        try writer.writeAll(line);
        if (opt.show_eof and slice.indexOfEnd(input, line) >= input.len)
            try writer.writeAll("␃");
    }
    // empty line
    else if (line.len == 0) {
        if (opt.show_eof and slice.indexOfEnd(input, line) >= input.len)
            try writer.writeAll("␃");
    }
    // skipped line
    else if (cursor.start > line.len) {
        try writer.writeAll(opt.trunc_sym);
    }
    // sliced line
    else {
        const line_seg = slice.segRange([]const u8, line, cursor.start, cursor.end);
        if (slice.indexOfStart(line, line_seg) > 0) {
            try writer.writeAll(opt.trunc_sym);
            trunc_len = opt.trunc_sym.len;
        }
        try writer.writeAll(line_seg);
        if (slice.indexOfEnd(line, line_seg) < line.len) {
            try writer.writeAll(opt.trunc_sym);
        } else if (opt.show_eof and slice.indexOfEnd(input, line_seg) >= input.len) {
            try writer.writeAll("␃");
        }
    }
    try writer.writeByte('\n');
    return trunc_len;
}

/// Implementation function.
fn writeCursor(
    writer: anytype,
    input: []const u8,
    mode: PrintLineMode,
    cursor: slice.SegAroundRangeIndices,
    extra_pad: usize,
    comptime opt: PrintLineOptions,
) !void {
    // render cursor head
    try writer.writeByteNTimes(' ', cursor.start_pos +| extra_pad);
    try writer.writeByte(opt.cursor_head_char);

    if (mode == .range) {
        const body_len = cursor.rangeLen() -| 1; // 1 excludes head
        if (cursor.endPosExceeds() and body_len > 0) { // `^~~`
            try writer.writeByteNTimes(opt.cursor_body_char, body_len -| 1); // 1 excludes newline
        } else if (body_len == 1) { // `^^`
            try writer.writeByte(opt.cursor_head_char);
        } else if (body_len > 1) { // `^~~^`
            try writer.writeByteNTimes(opt.cursor_body_char, body_len -| 1); // 1 excludes tail
            try writer.writeByte(opt.cursor_head_char);
        }
    }
    if (opt.show_cursor_hint) {
        const hint = if (mode.index() >= input.len)
            " (end of string)"
        else switch (input[mode.index()]) {
            '\n' => " (newline)",
            ' ' => " (space)",
            inline '!'...'~',
            => |char| if (opt.hint_printable_chars)
                std.fmt.comptimePrint(" ('\\x{x}')", .{char})
            else
                "",
            else => "",
        };
        if (hint.len > 0) try writer.writeAll(hint);
    }
    try writer.writeByte('\n');
}

test ":printLine, printLineWithCursor" {
    const t = std.testing;

    const case = struct {
        pub fn run(
            comptime expect: ?[]const u8,
            comptime expect_with_cursor: ?[]const u8,
            input: []const u8,
            mode: PrintLineMode,
            amount: lr.ReadRequest,
            comptime opt: PrintLineOptions,
        ) !void {
            var res = std.BoundedArray(u8, 256){};
            if (expect) |str| {
                try printLine(res.writer(), input, mode, amount, opt);
                try t.expectEqualStrings(str, res.slice());
            }
            if (expect_with_cursor) |str| {
                res.len = 0; // reset
                try printLineWithCursor(res.writer(), input, mode, amount, opt);
                try t.expectEqualStrings(if (str.len == 0) "" else str ++ "\n", res.slice());
            }
        }
    }.run;

    // format:
    // try case(
    // |expected printLine output|,
    // |expected printLineWithCursor output|,
    // |input|, |idx|, |amount|, |line_num|, |line_opts|, |cursor_opts|)

    // out of bounds read
    // --------------------
    try case(
        \\
    ,
        \\
    , "hello", .{ .cursor = .{ .index = 100 } }, .{ .forward = 1 }, .{});

    // .show_line_num
    // --------------------
    try case(
        \\␃
        \\
    ,
        \\␃
        \\^ (end of string)
    , "", .{ .cursor = .{ .index = 0 } }, .{ .forward = 1 }, .{ .show_line_num = false });

    try case(
        \\1| ␃
        \\
    ,
        \\1| ␃
        \\   ^ (end of string)
    , "", .{ .cursor = .{ .index = 0 } }, .{ .forward = 1 }, .{ .show_line_num = true });

    // .show_eof
    // --------------------
    try case(
        \\1| 
        \\
    ,
        \\1| 
        \\   ^ (end of string)
    , "", .{ .cursor = .{ .index = 0 } }, .{ .forward = 1 }, .{ .show_eof = false, .show_line_num = true });

    try case(
        \\
        \\
    ,
        \\
        \\^ (end of string)
    , "", .{ .cursor = .{ .index = 0 } }, .{ .forward = 1 }, .{ .show_eof = false, .show_line_num = false });

    // .line_num_sep
    // --------------------
    try case(
        \\1__hello␃
        \\
    ,
        \\1__hello␃
        \\   ^
    , "hello", .{ .cursor = .{ .index = 0 } }, .{ .forward = 1 }, .{ .line_len = 0, .line_num_sep = "__" });

    try case(
        \\1hello␃
        \\
    ,
        \\1hello␃
        \\ ^
    , "hello", .{ .cursor = .{ .index = 0 } }, .{ .forward = 1 }, .{ .line_len = 0, .line_num_sep = "" });

    // .trunc_mode and .line_len
    // --------------------
    // .soft
    try case(
        \\1| hel..
        \\
    ,
        \\1| hel..
        \\   ^
    , "hello", .{ .cursor = .{ .index = 0 } }, .{ .forward = 1 }, .{ .line_len = 3, .trunc_mode = .soft });

    try case(
        \\1| ..llo␃
        \\
    ,
        \\1| ..llo␃
        \\       ^
    , "hello", .{ .cursor = .{ .index = 4 } }, .{ .forward = 1 }, .{ .line_len = 3, .trunc_mode = .soft });

    try case(
        \\1| ..ell..
        \\
    ,
        \\1| ..ell..
        \\      ^
    , "hello", .{ .cursor = .{ .index = 2 } }, .{ .forward = 1 }, .{ .line_len = 3, .trunc_mode = .soft });

    // .hard
    try case(
        \\1| he..
        \\
    ,
        \\1| he..
        \\   ^
    , "hello", .{ .cursor = .{ .index = 0 } }, .{ .forward = 1 }, .{ .line_len = 3, .trunc_mode = .hard });

    try case(
        \\1| ..lo␃
        \\
    ,
        \\1| ..lo␃
        \\      ^
    , "hello", .{ .cursor = .{ .index = 4 } }, .{ .forward = 1 }, .{ .line_len = 3, .trunc_mode = .hard });

    // .hard_flex (default)
    try case(
        \\1| hel..
        \\
    ,
        \\1| hel..
        \\   ^
    , "hello", .{ .cursor = .{ .index = 0 } }, .{ .forward = 1 }, .{ .line_len = 3, .trunc_mode = .hard_flex });

    try case(
        \\1| ..llo␃
        \\
    ,
        \\1| ..llo␃
        \\       ^
    , "hello", .{ .cursor = .{ .index = 4 } }, .{ .forward = 1 }, .{ .line_len = 3, .trunc_mode = .hard_flex });

    try case(
        \\1| ..ell..
        \\
    ,
        \\1| ..ell..
        \\      ^
    , "hello", .{ .cursor = .{ .index = 2 } }, .{ .forward = 1 }, .{ .line_len = 3, .trunc_mode = .hard_flex });

    // manual line numbering
    // --------------------
    try case(
        \\42| hello␃
        \\
    ,
        \\42| hello␃
        \\    ^
    , "hello", .{ .cursor = .{ .index = 0, .curr_ln = .{ .set = 42 } } }, .{ .forward = 1 }, .{ .line_len = 0 });

    // automatic line number detection
    // --------------------
    const input1 =
        \\first line
        \\second line
        \\
    ;

    try case(
        \\1| first line
        \\
    ,
        \\1| first line
        \\   ^
    , input1, .{ .cursor = .{ .index = 0 } }, .{ .forward = 1 }, .{ .line_len = 0 });

    try case(
        \\1| first line
        \\
    ,
        \\1| first line
        \\        ^ (space)
    , input1, .{ .cursor = .{ .index = 5 } }, .{ .forward = 1 }, .{ .line_len = 0 });

    try case(
        \\2| second line
        \\
    ,
        \\2| second line
        \\    ^
    , input1, .{ .cursor = .{ .index = 12 } }, .{ .forward = 1 }, .{ .line_len = 0 });

    try case(
        \\2| second line
        \\
    ,
        \\2| second line
        \\              ^ (newline)
    , input1, .{ .cursor = .{ .index = 22 } }, .{ .forward = 1 }, .{ .line_len = 0 });

    try case(
        \\3| ␃
        \\
    ,
        \\3| ␃
        \\   ^ (end of string)
    , input1, .{ .cursor = .{ .index = 23 } }, .{ .forward = 1 }, .{ .line_len = 0 });

    // multi-line read
    //
    const input2 =
        \\First.
        //^0    ^6
        \\This is the second.
        //^7                 ^26
        \\A third line is a longer one.
        //^27 ^31                      ^56
        \\Goes fourth.
        //^57         ^69
        \\Last.
        //^70  ^75
    ;

    try case(
        \\10| First.
        \\11| This is the second.
        \\12| A third line is a longer one.
        \\
    ,
        \\10| First.
        \\    ^
        \\11| This is the second.
        \\12| A third line is a longer one.
    , input2, .{ .cursor = .{ .index = 0, .curr_ln = .{ .set = 10 } } }, .{ .forward = 3 }, .{ .line_len = 0 });

    try case(
        \\8 | First..
        \\9 | This ..
        \\10| A thi..
        \\
    ,
        \\8 | First..
        \\9 | This ..
        \\10| A thi..
        \\     ^ (space)
    , input2, .{ .cursor = .{ .index = 28, .curr_ln = .{ .set = 10 } } }, .{ .backward = 3 }, .{ .line_len = 5 });

    try case(
        \\10| ..third..
        \\11| ..es fo..
        \\12| ..st.␃
        \\
    ,
        \\10| ..third..
        \\        ^
        \\11| ..es fo..
        \\12| ..st.␃
    , input2, .{ .cursor = .{ .index = 31, .curr_ln = .{ .set = 10 } } }, .{ .forward = 3 }, .{ .line_len = 5 });

    try case(
        \\9 | ..
        \\10| ..one.
        \\11| ..
        \\12| ..
        \\
    ,
        \\9 | ..
        \\10| ..one.
        \\          ^ (newline)
        \\11| ..
        \\12| ..
    , input2, .{ .cursor = .{ .index = 56, .curr_ln = .{ .set = 10 } } }, .{ .bi = .{ .backward = 2, .forward = 2 } }, .{ .line_len = 5 });

    // empty and last empty lines
    //
    const input3 =
        \\Test empty lines with one that shows EOF.
        //^0                                       ^41
        \\
        //^42
        \\
        //^43
    ;

    try case(
        \\1| .. EOF.
        \\2| 
        \\3| ␃
        \\
    ,
        \\1| .. EOF.
        \\         ^
        \\2| 
        \\3| ␃
    , input3, .{ .cursor = .{ .index = 40 } }, .{ .forward = 3 }, .{ .line_len = 5 });

    // mode .end
    // --------------------
    try case(
        \\1| ..llo␃
        \\
    ,
        \\1| ..llo␃
        \\     ^
    , "hello", .{ .end = .{ .index = 2 } }, .{ .forward = 1 }, .{ .line_len = 3 });

    // mode .start
    // --------------------
    try case(
        \\1| hel..
        \\
    ,
        \\1| hel..
        \\   ^
    , "hello", .{ .start = .{ .index = 2 } }, .{ .forward = 1 }, .{ .line_len = 3 });

    // mode .range
    // --------------------
    try case(
        \\1| ..234..
        \\
    ,
        \\1| ..234..
        \\     ^~^
    , "012345678", .{ .range = .{ .index_start = 2, .index_end = 4 } }, .{ .forward = 1 }, .{ .line_len = 1 });
}
