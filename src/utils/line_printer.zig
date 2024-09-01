// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

//! Public API:
//! - LineOptions
//! - CursorOptions
//! - printLine()
//! - printLineWithCursor()

const std = @import("std");
const lr = @import("line_reader.zig");
const slice = @import("slice.zig");
const num = @import("num.zig");

/// Line printing options.
pub const LineOptions = struct {
    view_at: enum { start, end, cursor } = .cursor,
    line_len: usize = 80,
    trunc_sym: []const u8 = "..",
    trunc_mode: slice.SliceAroundMode = .hard_flex,
    show_line_num: bool = true,
    line_num_sep: []const u8 = "| ",
    show_eof: bool = true,
    /// The size of the stack-allocated buffer is the maximum amount of
    /// lines that can be read (upper bound).
    buf_size: usize = 256,
};

/// Cursor printing options.
pub const CursorOptions = struct {
    show_cursor_hint: bool = true,
    hint_printable_chars: bool = false,
    cursor_head_char: u8 = '^',
};

/// Line with cursor printing options.
pub const LineWithCursorOptions = struct {
    line_opt: LineOptions = .{},
    cursor_opt: CursorOptions = .{},
};

/// Reads an `amount` of lines from the input at the specified index and writes
/// it to the writer. If `line_number` is 0, it is automatically detected;
/// otherwise, the specified number is used as is. If `index > input.len`, no
/// line will be read or written. See `LineOptions` for additional details.
pub fn printLine(
    writer: anytype,
    input: []const u8,
    index: usize,
    amount: lr.ReadMode,
    line_number: usize,
    comptime opt: LineOptions,
) !void {
    try printLineImpl(writer, input, index, amount, line_number, false, opt);
}

/// Prints an `amount` of lines from the input at the specified index, writes it
/// to the writer, and renders a cursor at the specified position with an
/// optional hint. If `line_number` is 0, it is automatically detected;
/// otherwise, the specified number is used as is. If `index > input.len`, no
/// line will be read or written. See `CursorOptions` for additional details.
pub fn printLineWithCursor(
    writer: anytype,
    input: []const u8,
    index: usize,
    amount: lr.ReadMode,
    line_number: usize,
    comptime opt: LineWithCursorOptions,
) !void {
    try printLineImpl(writer, input, index, amount, line_number, true, opt);
}

/// Implementation function.
fn printLineImpl(
    writer: anytype,
    input: []const u8,
    index: usize,
    amount: lr.ReadMode,
    line_number: usize,
    comptime cursor: bool,
    comptime opt: if (cursor) LineWithCursorOptions else LineOptions,
) !void {
    comptime var line_opt = if (cursor) opt.line_opt else opt;
    if (cursor) line_opt.view_at = .cursor; // force

    // read lines
    var buf: [line_opt.buf_size][]const u8 = undefined;
    const detect_line_num = if (line_number == 0) true else false;
    const info = lr.readLines(&buf, input, index, detect_line_num, amount);

    if (info.lines.len > 0) {
        const first_line_num = if (detect_line_num) info.first_line_num else line_number - info.curr_line_pos;
        const last_line_num = first_line_num + info.lines.len -| 1;
        const num_col_len = if (line_opt.show_line_num) num.countIntLen(last_line_num) else 0;
        const line_num_sep_len = if (line_opt.show_line_num) line_opt.line_num_sep.len else 0;

        const curr_line = info.lines[info.curr_line_pos];
        const curr_line_len = if (line_opt.line_len == 0) std.math.maxInt(usize) else line_opt.line_len;
        const curr_line_slice = switch (line_opt.view_at) {
            .cursor => slice.sliceAroundIndices(curr_line, info.index_pos, curr_line_len, .{ .slicing_mode = line_opt.trunc_mode }),
            .end => slice.sliceEndIndices(curr_line, curr_line_len),
            .start => slice.sliceStartIndices(curr_line, curr_line_len),
        };

        // print lines
        for (info.lines, 0.., first_line_num..) |line, i, line_num| {
            try writeLineNumImpl(writer, line_num, num_col_len, line_opt);

            // project current line on others
            const sliced_line = slice.sliceRange([]const u8, line, curr_line_slice.start, curr_line_slice.end);
            try writeLineImpl(writer, input, line, sliced_line, curr_line_slice.start > line.len, line_opt);

            // print cursor
            if (cursor and info.curr_line_pos == i) {
                const trunc_sym_len = if (slice.indexOfSliceStart(line, sliced_line) > 0) line_opt.trunc_sym.len else 0;
                const cursor_pos = num_col_len + line_num_sep_len + trunc_sym_len + curr_line_slice.index_pos;
                try writeCursorImpl(writer, input, index, cursor_pos, opt.cursor_opt);
            }
        }
    }
}

/// Implementation function.
inline fn writeLineNumImpl(
    writer: anytype,
    line_num: usize,
    pad_size: usize,
    comptime opt: LineOptions,
) !void {
    if (!opt.show_line_num) return;
    try writer.print("{d: <[1]}" ++ opt.line_num_sep, .{ line_num, pad_size });
}

/// Implementation function.
fn writeLineImpl(
    writer: anytype,
    input: []const u8,
    full: []const u8,
    sliced: []const u8,
    skip_status: bool,
    comptime opt: LineOptions,
) !void {
    // full line
    if (opt.line_len == 0) {
        try writer.writeAll(full);
        if (slice.indexOfSliceEnd(input, full) >= input.len)
            try writer.writeAll("␃");
    } else
    // empty line
    if (opt.show_eof and full.len == 0) {
        if (slice.indexOfSliceEnd(input, full) >= input.len)
            try writer.writeAll("␃");
    }
    // skipped line
    else if (skip_status) {
        try writer.writeAll(opt.trunc_sym);
    }
    // sliced line
    else {
        if (slice.indexOfSliceStart(full, sliced) > 0) {
            try writer.writeAll(opt.trunc_sym);
        }
        try writer.writeAll(sliced);
        if (slice.indexOfSliceEnd(full, sliced) < full.len) {
            try writer.writeAll(opt.trunc_sym);
        } else if (opt.show_eof and
            slice.indexOfSliceEnd(input, sliced) >= input.len)
        {
            try writer.writeAll("␃");
        }
    }
    try writer.writeByte('\n');
}

/// Implementation function.
fn writeCursorImpl(
    writer: anytype,
    input: []const u8,
    index: usize,
    index_pos: usize,
    comptime opt: CursorOptions,
) !void {
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
            amount: lr.ReadMode,
            line_number: usize,
            comptime line_opt: LineOptions,
            comptime cursor_opt: CursorOptions,
        ) !void {
            var out = std.BoundedArray(u8, 256){};
            if (expect) |exp| {
                try printLine(out.writer(), input, index, amount, line_number, line_opt);
                try t.expectEqualStrings(exp, out.slice());
            }
            if (expect_with_cursor) |exp_with_cursor| {
                out.len = 0; // reset
                try printLineWithCursor(out.writer(), input, index, amount, line_number, .{ .cursor_opt = cursor_opt, .line_opt = line_opt });
                try t.expectEqualStrings(if (exp_with_cursor.len == 0) "" else exp_with_cursor ++ "\n", out.slice());
            }
        }
    }.run;

    // format:
    // try case(
    // |expected printLine output|,
    // |expected printLineWithCursor output|,
    // |input|, |idx|, |amount|, |line_num|, |line_ops|, |cursor_ops|)

    // out of bounds read
    //
    try case(
        \\
    ,
        \\
    , "hello", 100, .{ .forward = 1 }, 0, .{}, .{});

    // .show_line_num
    // --------------------
    try case(
        \\␃
        \\
    ,
        \\␃
        \\^ (end of string)
    , "", 0, .{ .forward = 1 }, 0, .{ .show_line_num = false }, .{});

    try case(
        \\1| ␃
        \\
    ,
        \\1| ␃
        \\   ^ (end of string)
    , "", 0, .{ .forward = 1 }, 0, .{ .show_line_num = true }, .{});

    // .show_eof
    // --------------------
    try case(
        \\1| 
        \\
    ,
        \\1| 
        \\   ^ (end of string)
    , "", 0, .{ .forward = 1 }, 0, .{ .show_eof = false, .show_line_num = true }, .{});

    try case(
        \\
        \\
    ,
        \\
        \\^ (end of string)
    , "", 0, .{ .forward = 1 }, 0, .{ .show_eof = false, .show_line_num = false }, .{});

    // .line_num_sep
    // --------------------
    try case(
        \\1__hello␃
        \\
    ,
        \\1__hello␃
        \\   ^
    , "hello", 0, .{ .forward = 1 }, 0, .{ .line_len = 0, .line_num_sep = "__" }, .{});

    try case(
        \\1hello␃
        \\
    ,
        \\1hello␃
        \\ ^
    , "hello", 0, .{ .forward = 1 }, 0, .{ .line_len = 0, .line_num_sep = "" }, .{});

    // .view_at and .line_len
    // --------------------
    try case(
        \\1| ..llo␃
        \\
    ,
        \\1| ..ell..
        \\      ^
    , "hello", 2, .{ .forward = 1 }, 0, .{ .line_len = 3, .view_at = .end }, .{});

    try case(
        \\1| hel..
        \\
    ,
        \\1| ..ell..
        \\      ^
    , "hello", 2, .{ .forward = 1 }, 0, .{ .line_len = 3, .view_at = .start }, .{});

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
    , "hello", 0, .{ .forward = 1 }, 0, .{ .line_len = 3, .trunc_mode = .soft }, .{});

    try case(
        \\1| ..llo␃
        \\
    ,
        \\1| ..llo␃
        \\       ^
    , "hello", 4, .{ .forward = 1 }, 0, .{ .line_len = 3, .trunc_mode = .soft }, .{});

    try case(
        \\1| ..ell..
        \\
    ,
        \\1| ..ell..
        \\      ^
    , "hello", 2, .{ .forward = 1 }, 0, .{ .line_len = 3, .trunc_mode = .soft }, .{});

    // .hard
    try case(
        \\1| he..
        \\
    ,
        \\1| he..
        \\   ^
    , "hello", 0, .{ .forward = 1 }, 0, .{ .line_len = 3, .trunc_mode = .hard }, .{});

    try case(
        \\1| ..lo␃
        \\
    ,
        \\1| ..lo␃
        \\      ^
    , "hello", 4, .{ .forward = 1 }, 0, .{ .line_len = 3, .trunc_mode = .hard }, .{});

    // .hard_flex
    try case(
        \\1| hel..
        \\
    ,
        \\1| hel..
        \\   ^
    , "hello", 0, .{ .forward = 1 }, 0, .{ .line_len = 3, .trunc_mode = .hard_flex }, .{});

    try case(
        \\1| ..llo␃
        \\
    ,
        \\1| ..llo␃
        \\       ^
    , "hello", 4, .{ .forward = 1 }, 0, .{ .line_len = 3, .trunc_mode = .hard_flex }, .{});

    try case(
        \\1| ..ell..
        \\
    ,
        \\1| ..ell..
        \\      ^
    , "hello", 2, .{ .forward = 1 }, 0, .{ .line_len = 3, .trunc_mode = .hard_flex }, .{});

    // manual line numbering
    // --------------------
    try case(
        \\42| hello␃
        \\
    ,
        \\42| hello␃
        \\    ^
    , "hello", 0, .{ .forward = 1 }, 42, .{ .line_len = 0 }, .{});

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
    , input1, 0, .{ .forward = 1 }, 0, .{ .line_len = 0 }, .{});

    try case(
        \\1| first line
        \\
    ,
        \\1| first line
        \\        ^ (space)
    , input1, 5, .{ .forward = 1 }, 0, .{ .line_len = 0 }, .{});

    try case(
        \\2| second line
        \\
    ,
        \\2| second line
        \\    ^
    , input1, 12, .{ .forward = 1 }, 0, .{ .line_len = 0 }, .{});

    try case(
        \\2| second line
        \\
    ,
        \\2| second line
        \\              ^ (newline)
    , input1, 22, .{ .forward = 1 }, 0, .{ .line_len = 0 }, .{});

    try case(
        \\3| ␃
        \\
    ,
        \\3| ␃
        \\   ^ (end of string)
    , input1, 23, .{ .forward = 1 }, 0, .{ .line_len = 0 }, .{});

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
    , input2, 0, .{ .forward = 3 }, 10, .{ .line_len = 0 }, .{});

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
    , input2, 28, .{ .backward = 3 }, 10, .{ .line_len = 5 }, .{});

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
    , input2, 31, .{ .forward = 3 }, 10, .{ .line_len = 5 }, .{});

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
    , input2, 56, .{ .bi = .{ .backward = 2, .forward = 2 } }, 10, .{ .line_len = 5 }, .{});

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
    , input3, 40, .{ .forward = 3 }, 0, .{ .line_len = 5 }, .{});
}
