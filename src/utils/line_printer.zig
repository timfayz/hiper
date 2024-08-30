// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

//! Public API:
//! - LineOptions
//! - CursorOptions
//! - printLine
//! - printLineWithCursor

const std = @import("std");
const lr = @import("line_reader.zig");
const slice = @import("slice.zig");
const num = @import("num.zig");

/// Line printing options.
pub const LineOptions = struct {
    view_at: enum { start, end, cursor } = .cursor,
    line_len: u8 = 3,
    trunc_sym: []const u8 = "..",
    trunc_hard: bool = true,
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

/// Reads an `amount` of lines from the input at the specified index and writes
/// it to the writer. If `line_number` is 0, it is automatically detected;
/// otherwise, the specified number is used as is. If `index > input.len`, no
/// line will be read and written. See `LineOptions` for additional details.
pub fn printLine(
    writer: anytype,
    input: []const u8,
    index: usize,
    amount: lr.ReadMode,
    line_number: usize,
    comptime opt: LineOptions,
) !void {
    const detect_line_num = if (line_number == 0) true else false;
    var buf: [opt.buf_size][]const u8 = undefined;
    const info = lr.readLines(&buf, input, index, detect_line_num, amount);
    if (info.lines.len > 0) {
        const first_line_num = if (detect_line_num) info.first_line_num else line_number - info.curr_line_pos;
        const last_line_num = first_line_num + info.lines.len -| 1;
        const num_col_len = num.countIntLen(last_line_num);

        for (info.lines, first_line_num..) |line, line_num| {
            var curr_index_pos = info.index_pos;
            try writeLineNumImpl(writer, line_num, num_col_len, opt);
            try writeLineImpl(writer, input, line, &curr_index_pos, opt.trunc_hard, opt);
        }
    }
}

/// Prints an `amount` of lines from the input at the specified index, writes it
/// to the writer, and additionally renders a cursor at the specified position
/// with an optional hint. See `printLine` and `CursorOptions` for additional
/// details.
pub fn printLineWithCursor(
    writer: anytype,
    input: []const u8,
    index: usize,
    amount: lr.ReadMode,
    line_number: usize,
    comptime opt: struct {
        line_opt: LineOptions,
        cursor_opt: CursorOptions,
    },
) !void {
    comptime var line_opt = opt.line_opt;
    line_opt.view_at = .cursor; // force
    const cursor_opt = opt.cursor_opt;

    const detect_line_num = if (line_number == 0) true else false;
    var buf: [line_opt.buf_size][]const u8 = undefined;
    const info = lr.readLines(&buf, input, index, detect_line_num, amount);
    if (info.lines.len > 0) {
        const first_line_num = if (detect_line_num) info.first_line_num else line_number - info.curr_line_pos;
        const last_line_num = first_line_num + info.lines.len -| 1;
        const num_col_len = if (line_opt.show_line_num) num.countIntLen(last_line_num) else 0;
        const line_num_sep_len = if (line_opt.show_line_num) line_opt.line_num_sep.len else 0;

        for (info.lines, 0.., first_line_num..) |line, i, line_num| {
            var index_pos = info.index_pos; // index relative position per line
            try writeLineNumImpl(writer, line_num, num_col_len, line_opt);
            try writeLineImpl(writer, input, line, &index_pos, line_opt.trunc_hard, line_opt);
            if (info.curr_line_pos == i) {
                const cursor_pos = num_col_len + line_num_sep_len + index_pos;
                try writeCursorImpl(writer, input, index, cursor_pos, cursor_opt);
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
    line: []const u8,
    index_pos: *usize,
    trunc_hard: bool,
    comptime opt: LineOptions,
) !void {
    truncate: {
        switch (opt.view_at) {
            .cursor => {
                if (opt.line_len == 0) break :truncate;
                const seg = slice.sliceSeg([]const u8, line, index_pos.*, opt.line_len, trunc_hard, .{});
                index_pos.* = seg.index_pos;
                if (slice.indexOfSliceStart(line, seg.slice) > 0) {
                    try writer.writeAll(opt.trunc_sym);
                    index_pos.* += opt.trunc_sym.len;
                }
                try writer.writeAll(seg.slice);
                if (slice.indexOfSliceEnd(line, seg.slice) < line.len) {
                    try writer.writeAll(opt.trunc_sym);
                }
                if (opt.show_eof and slice.indexOfSliceEnd(input, seg.slice) >= input.len and
                    seg.index_pos <= seg.slice.len)
                    try writer.writeAll("␃");
            },
            .end => {
                if (opt.line_len == 0 or opt.line_len >= line.len) break :truncate;
                try writer.writeAll(opt.trunc_sym);
                try writer.writeAll(line[line.len - opt.line_len ..]);
                if (opt.show_eof and slice.indexOfSliceEnd(input, line) >= input.len)
                    try writer.writeAll("␃");
            },
            .start => {
                if (opt.line_len == 0 or opt.line_len >= line.len) break :truncate;
                try writer.writeAll(line[0..opt.line_len]);
                try writer.writeAll(opt.trunc_sym);
            },
        }
        try writer.writeByte('\n');
        return;
    }
    // no truncation required
    try writer.writeAll(line);
    if (opt.show_eof and slice.indexOfSliceEnd(input, line) >= input.len)
        try writer.writeAll("␃");
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

test "+printLine[any]" {
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

    // params passing format:
    // |expected printLine output|
    // |expected printLineWithCursor output|
    // |input| |idx| |amount| |line_num| |line_ops| |cursor_ops|

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

    // .view_at
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

    // for other cases `.view_at == .cursor` by default

    // .trunc_hard
    // --------------------
    // == false
    try case(
        \\1| hel..
        \\
    ,
        \\1| hel..
        \\   ^
    , "hello", 0, .{ .forward = 1 }, 0, .{ .line_len = 3, .trunc_hard = false }, .{});

    try case(
        \\1| ..llo␃
        \\
    ,
        \\1| ..llo␃
        \\       ^
    , "hello", 4, .{ .forward = 1 }, 0, .{ .line_len = 3, .trunc_hard = false }, .{});

    try case(
        \\1| ..ell..
        \\
    ,
        \\1| ..ell..
        \\      ^
    , "hello", 2, .{ .forward = 1 }, 0, .{ .line_len = 3, .trunc_hard = false }, .{});

    // == true
    try case(
        \\1| he..
        \\
    ,
        \\1| he..
        \\   ^
    , "hello", 0, .{ .forward = 1 }, 0, .{ .line_len = 3, .trunc_hard = true }, .{});

    try case(
        \\1| ..lo␃
        \\
    ,
        \\1| ..lo␃
        \\      ^
    , "hello", 4, .{ .forward = 1 }, 0, .{ .line_len = 3, .trunc_hard = true }, .{});

    try case(
        \\1| ..ell..
        \\
    ,
        \\1| ..ell..
        \\      ^
    , "hello", 2, .{ .forward = 1 }, 0, .{ .line_len = 3, .trunc_hard = true }, .{});

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
        \\8 | Firs..
        \\9 | This..
        \\10| A th..
        \\
    ,
        \\8 | Firs..
        \\9 | This..
        \\10| A th..
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

    try case(null,
        \\9 | ..
        \\10| ..e.
        \\        ^ (newline)
        \\11| ..
        \\12| ..
    , input2, 56, .{ .bi = .{ .backward = 2, .forward = 2 } }, 10, .{ .line_len = 5 }, .{});
}
