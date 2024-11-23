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
    view_at: enum { start, end, cursor } = .cursor,
    line_len: usize = 80,
    trunc_sym: []const u8 = "..",
    trunc_mode: slice.SegAroundMode = .hard_flex,
    show_line_num: bool = true,
    line_num_sep: []const u8 = "| ",
    show_eof: bool = true,
    /// The size of the stack-allocated buffer is the maximum amount of
    /// lines that can be read (upper bound).
    buf_size: usize = 256,

    // applies only when `.show_cursor = true`
    show_cursor: bool = false,
    show_cursor_hint: bool = true,
    hint_printable_chars: bool = false,
    cursor_head_char: u8 = '^',
};

/// Prints `amount` of lines from `input` starting at `index`, writes them to
/// the writer, and renders line numbers calculated relative to `curr_ln`. If
/// `index > input.len`, no line will be read or written. See `PrintLineOptions`
/// for additional details.
pub fn printLine(
    writer: anytype,
    input: []const u8,
    index: usize,
    amount: lr.ReadRequest,
    curr_ln: lr.CurrLineNum,
    comptime opt: PrintLineOptions,
) !void {
    try printLineImpl(writer, input, index, amount, curr_ln, opt);
}

/// Prints `amount` of lines from `input` starting at `index`, writes them to
/// the writer, and renders a cursor with the line number calculated relative to
/// `curr_ln`. If `index > input.len`, no line will be read or written. See
/// `PrintLineOptions` for additional details.
pub fn printLineWithCursor(
    writer: anytype,
    input: []const u8,
    index: usize,
    amount: lr.ReadRequest,
    curr_ln: lr.CurrLineNum,
    comptime opt: PrintLineOptions,
) !void {
    comptime var opt_ = opt;
    opt_.show_cursor = true; // force
    opt_.view_at = .cursor; // force
    try printLineImpl(writer, input, index, amount, curr_ln, opt_);
}

/// Implementation function.
fn printLineImpl(
    writer: anytype,
    input: []const u8,
    index: usize,
    amount: lr.ReadRequest,
    curr_ln: lr.CurrLineNum,
    comptime opt: PrintLineOptions,
) !void {
    // read lines
    var buf: [opt.buf_size][]const u8 = undefined;
    const info = lr.readLines(&buf, input, index, curr_ln, amount);
    if (info.isEmpty()) return;

    const num_col_len = if (opt.show_line_num) num.countIntLen(info.lastLineNum()) else 0;
    const num_col_sep_len = if (opt.show_line_num) opt.line_num_sep.len else 0;

    const cursor_line_len = if (opt.line_len == 0) std.math.maxInt(usize) else opt.line_len;
    const cursor_line_indices: slice.SegAroundIndices = switch (opt.view_at) {
        .cursor => slice.segAroundIndices(info.currLine(), info.index_pos, cursor_line_len, .{ .slicing_mode = opt.trunc_mode }),
        .end => blk: {
            const indices = slice.segEndIndices(info.currLine(), cursor_line_len);
            break :blk .{ .start = indices.start, .end = indices.end, .index_pos = 0 };
        },
        .start => blk: {
            const indices = slice.segStartIndices(info.currLine(), cursor_line_len);
            break :blk .{ .start = indices.start, .end = indices.end, .index_pos = 0 };
        },
    };

    // print lines
    for (info.lines, info.firstLineNum().., 0..) |line, line_num, i| {
        if (opt.show_line_num) try writeLineNum(writer, line_num, num_col_len, opt);
        const trim_len = try writeLine(writer, input, line, cursor_line_indices, opt);
        // cursor
        if (opt.show_cursor and info.curr_line_pos == i) {
            const index_pos = num_col_len + num_col_sep_len + trim_len + cursor_line_indices.index_pos;
            try writeCursor(writer, input, index, index_pos, opt);
        }
    }
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
    cursor_line_indices: slice.SegAroundIndices,
    comptime opt: PrintLineOptions,
) !usize {
    var trunc_len: usize = 0;
    // complete line
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
    else if (cursor_line_indices.start > line.len) {
        try writer.writeAll(opt.trunc_sym);
    }
    // sliced line
    else {
        const line_seg = slice.segRange([]const u8, line, cursor_line_indices.start, cursor_line_indices.end);
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
    index: usize,
    index_pos: usize,
    comptime opt: PrintLineOptions,
) !void {
    if (opt.view_at != .cursor) return;
    try writer.writeByteNTimes(' ', index_pos);
    try writer.writeByte(opt.cursor_head_char);
    if (opt.show_cursor_hint) {
        const hint = b: {
            if (index >= input.len)
                break :b " (end of string)";
            break :b switch (input[index]) {
                '\n' => " (newline)",
                ' ' => " (space)",
                inline '!'...'~',
                => |char| if (opt.hint_printable_chars)
                    std.fmt.comptimePrint(" ('\\x{x}')", .{char})
                else
                    "",
                else => "",
            };
        };
        if (hint.len > 0) try writer.writeAll(hint);
    }
    try writer.writeByte('\n');
}

test "+printLine, printLineWithCursor" {
    const t = std.testing;

    const case = struct {
        pub fn run(
            comptime expect: ?[]const u8,
            comptime expect_with_cursor: ?[]const u8,
            input: []const u8,
            index: usize,
            amount: lr.ReadRequest,
            curr_ln: lr.CurrLineNum,
            comptime opt: PrintLineOptions,
        ) !void {
            var out = std.BoundedArray(u8, 256){};
            if (expect) |exp| {
                try printLine(out.writer(), input, index, amount, curr_ln, opt);
                try t.expectEqualStrings(exp, out.slice());
            }
            if (expect_with_cursor) |exp_with_cursor| {
                out.len = 0; // reset
                try printLineWithCursor(out.writer(), input, index, amount, curr_ln, opt);
                try t.expectEqualStrings(if (exp_with_cursor.len == 0) "" else exp_with_cursor ++ "\n", out.slice());
            }
        }
    }.run;

    // format:
    // try case(
    // |expected printLine output|,
    // |expected printLineWithCursor output|,
    // |input|, |idx|, |amount|, |line_num|, |line_opts|, |cursor_opts|)

    // out of bounds read
    //
    try case(
        \\
    ,
        \\
    , "hello", 100, .{ .forward = 1 }, .detect, .{});

    // .show_line_num
    // --------------------
    try case(
        \\␃
        \\
    ,
        \\␃
        \\^ (end of string)
    , "", 0, .{ .forward = 1 }, .detect, .{ .show_line_num = false });

    try case(
        \\1| ␃
        \\
    ,
        \\1| ␃
        \\   ^ (end of string)
    , "", 0, .{ .forward = 1 }, .detect, .{ .show_line_num = true });

    // .show_eof
    // --------------------
    try case(
        \\1| 
        \\
    ,
        \\1| 
        \\   ^ (end of string)
    , "", 0, .{ .forward = 1 }, .detect, .{ .show_eof = false, .show_line_num = true });

    try case(
        \\
        \\
    ,
        \\
        \\^ (end of string)
    , "", 0, .{ .forward = 1 }, .detect, .{ .show_eof = false, .show_line_num = false });

    // .line_num_sep
    // --------------------
    try case(
        \\1__hello␃
        \\
    ,
        \\1__hello␃
        \\   ^
    , "hello", 0, .{ .forward = 1 }, .detect, .{ .line_len = 0, .line_num_sep = "__" });

    try case(
        \\1hello␃
        \\
    ,
        \\1hello␃
        \\ ^
    , "hello", 0, .{ .forward = 1 }, .detect, .{ .line_len = 0, .line_num_sep = "" });

    // .view_at and .line_len
    // --------------------
    try case(
        \\1| ..llo␃
        \\
    ,
        \\1| ..ell..
        \\      ^
    , "hello", 2, .{ .forward = 1 }, .detect, .{ .line_len = 3, .view_at = .end });

    try case(
        \\1| hel..
        \\
    ,
        \\1| ..ell..
        \\      ^
    , "hello", 2, .{ .forward = 1 }, .detect, .{ .line_len = 3, .view_at = .start });

    // `.view_at == .cursor` is a default for other cases

    // .trunc_mode
    // --------------------
    // .soft
    try case(
        \\1| hel..
        \\
    ,
        \\1| hel..
        \\   ^
    , "hello", 0, .{ .forward = 1 }, .detect, .{ .line_len = 3, .trunc_mode = .soft });

    try case(
        \\1| ..llo␃
        \\
    ,
        \\1| ..llo␃
        \\       ^
    , "hello", 4, .{ .forward = 1 }, .detect, .{ .line_len = 3, .trunc_mode = .soft });

    try case(
        \\1| ..ell..
        \\
    ,
        \\1| ..ell..
        \\      ^
    , "hello", 2, .{ .forward = 1 }, .detect, .{ .line_len = 3, .trunc_mode = .soft });

    // .hard
    try case(
        \\1| he..
        \\
    ,
        \\1| he..
        \\   ^
    , "hello", 0, .{ .forward = 1 }, .detect, .{ .line_len = 3, .trunc_mode = .hard });

    try case(
        \\1| ..lo␃
        \\
    ,
        \\1| ..lo␃
        \\      ^
    , "hello", 4, .{ .forward = 1 }, .detect, .{ .line_len = 3, .trunc_mode = .hard });

    // .hard_flex
    try case(
        \\1| hel..
        \\
    ,
        \\1| hel..
        \\   ^
    , "hello", 0, .{ .forward = 1 }, .detect, .{ .line_len = 3, .trunc_mode = .hard_flex });

    try case(
        \\1| ..llo␃
        \\
    ,
        \\1| ..llo␃
        \\       ^
    , "hello", 4, .{ .forward = 1 }, .detect, .{ .line_len = 3, .trunc_mode = .hard_flex });

    try case(
        \\1| ..ell..
        \\
    ,
        \\1| ..ell..
        \\      ^
    , "hello", 2, .{ .forward = 1 }, .detect, .{ .line_len = 3, .trunc_mode = .hard_flex });

    // manual line numbering
    // --------------------
    try case(
        \\42| hello␃
        \\
    ,
        \\42| hello␃
        \\    ^
    , "hello", 0, .{ .forward = 1 }, .{ .set = 42 }, .{ .line_len = 0 });

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
    , input1, 0, .{ .forward = 1 }, .detect, .{ .line_len = 0 });

    try case(
        \\1| first line
        \\
    ,
        \\1| first line
        \\        ^ (space)
    , input1, 5, .{ .forward = 1 }, .detect, .{ .line_len = 0 });

    try case(
        \\2| second line
        \\
    ,
        \\2| second line
        \\    ^
    , input1, 12, .{ .forward = 1 }, .detect, .{ .line_len = 0 });

    try case(
        \\2| second line
        \\
    ,
        \\2| second line
        \\              ^ (newline)
    , input1, 22, .{ .forward = 1 }, .detect, .{ .line_len = 0 });

    try case(
        \\3| ␃
        \\
    ,
        \\3| ␃
        \\   ^ (end of string)
    , input1, 23, .{ .forward = 1 }, .detect, .{ .line_len = 0 });

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
    , input2, 0, .{ .forward = 3 }, .{ .set = 10 }, .{ .line_len = 0 });

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
    , input2, 28, .{ .backward = 3 }, .{ .set = 10 }, .{ .line_len = 5 });

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
    , input2, 31, .{ .forward = 3 }, .{ .set = 10 }, .{ .line_len = 5 });

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
    , input2, 56, .{ .bi = .{ .backward = 2, .forward = 2 } }, .{ .set = 10 }, .{ .line_len = 5 });

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
    , input3, 40, .{ .forward = 3 }, .detect, .{ .line_len = 5 });
}
