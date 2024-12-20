// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

//! Public API:
//! - PrintOptions
//! - printLine()
//! - printLineWithCursor()

const std = @import("std");
const lr = @import("line_reader.zig");
const slice = @import("slice.zig");
const num = @import("num.zig");
const CurrLineScope = slice.View(.range);

/// Line printing options.
pub const PrintOptions = struct {
    trunc_mode: slice.ViewOptions.TruncMode = .hard_flex,
    trunc_sym: []const u8 = "..",
    show_line_num: bool = true,
    line_num_sep: []const u8 = "| ",
    show_eof: bool = true,
    /// The maximum (stack-allocated) amount of lines that can be read.
    buf_size: usize = 256,

    // Cursor related options.
    show_cursor: bool = false,
    show_cursor_hint: bool = true,
    hint_printable_chars: bool = false,
    cursor_head_char: u8 = '^',
    cursor_body_char: u8 = '~',
};

/// Prints the specified `amount` of lines from `input` based on the given
/// `mode`, writes them to the `writer`, and calculates line numbers relative
/// to the current line number (`curr_ln`) determined by `mode`. If the `mode`
/// specifies indices beyond `input.len`, no lines will be read or written.
/// Refer to `PrintLineOptions` for output formatting details.
pub fn printLine(
    writer: anytype,
    input: []const u8,
    index: anytype,
    comptime mode: slice.ViewMode,
    comptime amount: lr.ReadAmount,
    line_num: lr.LineNumMode,
    comptime opt: PrintOptions,
) !void {
    if (mode.len() == 0) return;

    const index_start, const index_end =
        if (num.isNum(index)) .{ index, index } else num.orderPair(index[0], index[1]);
    const range_len = index_end - index_start;

    // read first index
    var buf: [opt.buf_size][]const u8 = undefined;
    const ret = lr.readLines(&buf, input, index_start, amount, line_num);
    if (ret.isEmpty()) return;

    // determine the scope of current line to constrain others
    const scope: ?CurrLineScope = slice.viewRelRange(ret.currLine(), .{
        ret.index_pos,
        ret.index_pos + range_len,
    }, mode, .{ .trunc_mode = opt.trunc_mode });

    // TODO
    // if (index_start != index_end), it means we are handling a range
    // if scope is null but scope.rangeLen() fits mode.len(), it may mean
    // we need to split the view at each index separately

    // render lines
    const line_num_len = if (opt.show_line_num) num.countIntLen(ret.lastLineNum()) else 0;
    for (ret.lines, ret.firstLineNum().., 0..) |line, line_number, i| {
        try writeLine(
            writer,
            input,
            line,
            line_number,
            line_num_len,
            ret.curr_line_pos == i,
            mode,
            scope.?,
            opt,
        );
    }
}

/// A simple wrapper around `printLine` that forces cursor rendering by
/// setting `PrintLineOptions.show_cursor` to `true`. See `printLine`
/// for more details.
fn printLineWithCursor(
    writer: anytype,
    input: []const u8,
    index: anytype,
    comptime mode: slice.ViewMode,
    comptime amount: lr.ReadAmount,
    line_num: lr.LineNumMode,
    comptime opt: PrintOptions,
) !void {
    comptime var opt_ = opt;
    opt_.show_cursor = true; // force
    return printLine(writer, input, index, mode, amount, line_num, opt_);
}

/// Implementation function.
fn writeLine(
    writer: anytype,
    input: []const u8,
    line: []const u8,
    line_num: usize,
    line_num_len: usize,
    line_is_curr: bool,
    mode: slice.ViewMode,
    scope: CurrLineScope,
    comptime opt: PrintOptions,
) !void {
    // render line number
    if (opt.show_line_num)
        try writer.print("{d: <[1]}" ++ opt.line_num_sep, .{ line_num, line_num_len });

    // render line
    var trunc_len: usize = 0;
    if (mode == .full) { // full line
        try writer.writeAll(line);
        if (opt.show_eof and slice.indexOfEnd(input, line) >= input.len)
            try writer.writeAll("␃");
    } else if (line.len == 0) { // empty line
        if (opt.show_eof and slice.indexOfEnd(input, line) >= input.len)
            try writer.writeAll("␃");
    } else if (scope.start > line.len) { // skipped line
        try writer.writeAll(opt.trunc_sym);
    } else { // trimmed line
        const seg = scope.sliceBounded([]const u8, line);
        if (slice.indexOfStart(line, seg) > 0) {
            try writer.writeAll(opt.trunc_sym);
            trunc_len = opt.trunc_sym.len;
        }
        try writer.writeAll(seg);
        if (slice.indexOfEnd(line, seg) < line.len) {
            try writer.writeAll(opt.trunc_sym);
        } else if (opt.show_eof and slice.indexOfEnd(input, seg) >= input.len) {
            try writer.writeAll("␃");
        }
    }
    try writer.writeByte('\n');

    // render cursor
    if (opt.show_cursor and line_is_curr) {
        const extra_pad = line_num_len + (if (opt.show_line_num) opt.line_num_sep.len else 0) + trunc_len;
        try writeCursor(writer, input, scope, extra_pad, opt);
    }
}

/// Implementation function.
fn writeCursor(
    writer: anytype,
    input: []const u8,
    scope: CurrLineScope,
    extra_pad: usize,
    comptime opt: PrintOptions,
) !void {
    try writer.writeByteNTimes(' ', scope.pos.start +| extra_pad);
    try writer.writeByte(opt.cursor_head_char);
    const body_len = scope.rangeLen() -| 1; // 1 excludes head
    if (body_len > 0) { // range
        if (scope.endPosExceeds() and body_len > 0) { // `^~~`
            try writer.writeByteNTimes(opt.cursor_body_char, body_len -| 1); // 1 excludes newline
        } else if (body_len == 1) { // `^^`
            try writer.writeByte(opt.cursor_head_char);
        } else if (body_len > 1) { // `^~~^`
            try writer.writeByteNTimes(opt.cursor_body_char, body_len -| 1); // 1 excludes tail
            try writer.writeByte(opt.cursor_head_char);
        }
    }
    if (opt.show_cursor_hint) {
        const hint = getHint(input, scope.start + scope.pos.start, opt);
        if (hint.len > 0) {
            try writer.writeAll(" (");
            try writer.writeAll(hint);
            try writer.writeAll(")");
        }
    }
    try writer.writeByte('\n');
}

fn getHint(input: []const u8, index: usize, comptime opt: PrintOptions) []const u8 {
    return if (index >= input.len)
        "end of string"
    else switch (input[index]) {
        '\n' => "newline",
        ' ' => "space",
        inline '!'...'~',
        => |char| if (opt.hint_printable_chars)
            std.fmt.comptimePrint("'\\x{x}'", .{char})
        else
            "",
        else => "",
    };
}

test printLine {
    const equal = std.testing.expectEqualStrings;
    const string = struct {
        pub fn run(buffer: anytype) []const u8 {
            const str = buffer.slice();
            buffer.clear();
            return if (str.len != 0 and str[str.len -| 1] == '\n')
                str[0..str.len -| 1]
            else
                str;
        }
    }.run;
    var buf = std.BoundedArray(u8, 1024){};
    const w = buf.writer();

    // out-of-bounds read
    try printLine(w, "hello", 100, .{ .full = {} }, .{ .forward = 1 }, .detect, .{});
    try equal(
        \\
    , string(&buf));

    // normal read
    try printLine(w, "hello", 1, .{ .full = {} }, .{ .forward = 1 }, .detect, .{});
    try equal(
        \\1| hello␃
    , string(&buf));

    // [.show_cursor]
    try printLine(w, "hello", 1, .{ .full = {} }, .{ .forward = 1 }, .detect, .{
        .show_cursor = true,
    });
    try equal(
        \\1| hello␃
        \\    ^
    , string(&buf));

    // [.show_eof]
    try printLineWithCursor(w, "hello", 1, .{ .full = {} }, .{ .forward = 1 }, .detect, .{
        .show_eof = false,
    });
    try equal(
        \\1| hello
        \\    ^
    , string(&buf));

    // [.hint_printable_chars]
    try printLineWithCursor(w, "hello", 1, .{ .full = {} }, .{ .forward = 1 }, .detect, .{
        .hint_printable_chars = true,
    });
    try equal(
        \\1| hello␃
        \\    ^ ('\x65')
    , string(&buf));

    // end of string hint
    try printLineWithCursor(w, "hello", 5, .{ .full = {} }, .{ .forward = 1 }, .detect, .{});
    try equal(
        \\1| hello␃
        \\        ^ (end of string)
    , string(&buf));

    // newline hint
    try printLineWithCursor(w, "hello\n", 5, .{ .full = {} }, .{ .forward = 1 }, .detect, .{});
    try equal(
        \\1| hello
        \\        ^ (newline)
    , string(&buf));

    // [.show_cursor_hint]
    try printLineWithCursor(w, "hello", 5, .{ .full = {} }, .{ .forward = 1 }, .detect, .{
        .show_cursor_hint = false,
    });
    try equal(
        \\1| hello␃
        \\        ^
    , string(&buf));

    // [.show_line_num]
    try printLine(w, "hello", 1, .{ .full = {} }, .{ .forward = 1 }, .detect, .{
        .show_line_num = false,
    });
    try equal(
        \\hello␃
    , string(&buf));

    // [.line_num_sep]
    try printLine(w, "hello", 1, .{ .full = {} }, .{ .forward = 1 }, .detect, .{
        .line_num_sep = "__",
    });
    try equal(
        \\1__hello␃
    , string(&buf));

    const input =
        \\First line.
        //           ^11
        \\This is the second.
        //^12                ^31
        \\A third line is a longer one.
        //^32                          ^61
        \\
        //^62
        \\Fifth line.
        //^63        ^74
        \\Sixth one.
        //^75       ^85
        \\
    ;

    // [.detect] automatic line numbering
    try printLine(w, input, 15, .{ .full = {} }, .{ .forward = 6 }, .detect, .{});
    try equal(
        \\2| This is the second.
        \\3| A third line is a longer one.
        \\4| 
        \\5| Fifth line.
        \\6| Sixth one.
        \\7| ␃
    , string(&buf));

    // [.set = *] manual line numbering
    try printLine(w, input, 1, .{ .full = {} }, .{ .forward = 6 }, .{ .set = 7 }, .{});
    try equal(
        \\7 | First line.
        \\8 | This is the second.
        \\9 | A third line is a longer one.
        \\10| 
        \\11| Fifth line.
        \\12| Sixth one.
    , string(&buf));

    // [.backward] read, [.around] mode, trunc [.hard_flex]
    try printLineWithCursor(w, input, 85, .{ .around = .{ .len = 5 } }, .{ .backward = 6 }, .detect, .{
        .trunc_mode = .hard_flex,
        .show_cursor_hint = true,
    });
    try equal(
        \\1| ..line..
        \\2| ..s th..
        \\3| ..d li..
        \\4| 
        \\5| ..line..
        \\6| ..one.
        \\         ^
    , string(&buf));

    // [.trunc_sym]
    try printLineWithCursor(w, input, 85, .{ .around = .{ .len = 5 } }, .{ .backward = 1 }, .detect, .{
        .trunc_sym = "__",
    });
    try equal(
        \\6| __one.
        \\         ^
    , string(&buf));
}
