// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

//! Public API:
//! - PrintOptions
//! - printLines()
//! - printLinesWithCursor()

const std = @import("std");
const lr = @import("line_reader.zig");
const slice = @import("slice.zig");
const num = @import("num.zig");
const meta = @import("meta.zig");
const LineScope = slice.View(.range);

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
pub fn printLines(
    writer: anytype,
    input: []const u8,
    index: anytype,
    comptime mode: slice.ViewMode,
    comptime amount: lr.ReadAmount,
    line_num: lr.LineNumMode,
    comptime opt: PrintOptions,
) !void {
    if (opt.buf_size == 0) return;
    if (!mode.isExt() and mode.len() == 0) return;
    const index_start, const index_end = blk: {
        break :blk if (meta.isNum(index))
            .{ index, index }
        else if (meta.isTuple(index) and index.len == 1)
            .{ index[0], index[0] }
        else
            num.orderPair(index[0], index[1]);
    };
    if (index_start > input.len or index_end > input.len) return;
    const range_len = index_end - index_start;

    var lines_buf: [opt.buf_size][]const u8 = undefined;

    // invariants:
    // mode.len >= 1
    // index_start <= index_end
    // index_start, index_end <= input.len
    // opt.buf_size > 0
    // input.len > 0 TODO?

    const first: ?lr.ReadLines = blk: {
        // non-range or range that fits the view
        if (range_len == 0 or mode.fits(range_len)) {
            const read = lr.readLines(&lines_buf, input, index_start, amount, line_num);
            if (read.isEmpty()) return;
            break :blk read;
        }
        break :blk null; // TODO
    };
    if (first) |read| {
        try printLinesImpl(writer, input, range_len, read, mode, opt);
    }
}

/// A simple wrapper around `printLine` that forces cursor rendering by
/// setting `PrintLineOptions.show_cursor` to `true`. See `printLine`
/// for more details.
fn printLinesWithCursor(
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
    return printLines(writer, input, index, mode, amount, line_num, opt_);
}

/// Implementation function.
fn printLinesImpl(
    writer: anytype,
    input: []const u8,
    range_len: usize,
    read: lr.ReadLines,
    comptime mode: slice.ViewMode,
    comptime opt: PrintOptions,
) !void {
    const scope = slice.viewRelRange(read.currLine(), .{
        read.index_pos,
        read.index_pos + range_len,
    }, mode, .{ .trunc_mode = opt.trunc_mode }) orelse return;

    const ln_len = if (opt.show_line_num) num.countIntLen(read.lastLineNum()) else 0;

    for (read.lines, read.firstLineNum().., 0..) |line, ln, i| {
        // render line number
        if (opt.show_line_num)
            try writer.print("{d: <[1]}" ++ opt.line_num_sep, .{ ln, ln_len });

        // render line
        var trunc_len: usize = 0;
        if (line.len != 0 and scope.start > line.len) { // skip
            try writer.writeAll(opt.trunc_sym);
        } else { // trim
            const seg = if (mode == .full) line else scope.sliceBounded([]const u8, line);
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
        if (opt.show_cursor and read.curr_line_pos == i) {
            const ln_sep_len = if (opt.show_line_num) opt.line_num_sep.len else 0;
            const pad = ln_len +| ln_sep_len +| trunc_len +| scope.pos.start;
            // head
            try writer.writeByteNTimes(' ', pad);
            try writer.writeByte(opt.cursor_head_char);
            // tail
            if (range_len > 0) {
                if (range_len == 1) { // `^^`
                    try writer.writeByte(opt.cursor_head_char);
                } else if (range_len > 1 and !scope.endPosExceeds()) { // `^~~^`
                    try writer.writeByteNTimes(opt.cursor_body_char, range_len -| 1); // 1 excludes tail
                    try writer.writeByte(opt.cursor_head_char);
                } else { // `^~~`
                    try writer.writeByteNTimes(opt.cursor_body_char, range_len -| 1); // 1 excludes newline
                }
            }
            // hint
            if (opt.show_cursor_hint) {
                const cursor_index = slice.indexOfStart(input, line) +| read.index_pos;
                const hint = getHint(input, cursor_index, opt);
                if (hint.len > 0) {
                    try writer.writeAll(" (");
                    try writer.writeAll(hint);
                    try writer.writeAll(")");
                }
            }
            try writer.writeByte('\n');
        }
    }
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

test printLines {
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
    try printLines(w, "hello", 100, .{ .full = {} }, .{ .forward = 1 }, .detect, .{});
    try equal(
        \\
    , string(&buf));

    // normal read
    try printLines(w, "hello", 1, .{ .full = {} }, .{ .forward = 1 }, .detect, .{});
    try equal(
        \\1| hello␃
    , string(&buf));

    // [.show_cursor]
    try printLines(w, "hello", 1, .{ .full = {} }, .{ .forward = 1 }, .detect, .{
        .show_cursor = true,
    });
    try equal(
        \\1| hello␃
        \\    ^
    , string(&buf));

    // [.show_eof]
    try printLinesWithCursor(w, "hello", 1, .{ .full = {} }, .{ .forward = 1 }, .detect, .{
        .show_eof = false,
    });
    try equal(
        \\1| hello
        \\    ^
    , string(&buf));

    // [.hint_printable_chars]
    try printLinesWithCursor(w, "hello\nworld", 7, .{ .full = {} }, .{ .backward = 2 }, .detect, .{
        .hint_printable_chars = true,
    });
    try equal(
        \\1| hello
        \\2| world␃
        \\    ^ ('\x6f')
    , string(&buf));

    // end of string hint
    try printLinesWithCursor(w, "hello\nworld", 11, .{ .full = {} }, .{ .backward = 2 }, .detect, .{});
    try equal(
        \\1| hello
        \\2| world␃
        \\        ^ (end of string)
    , string(&buf));

    // newline hint
    try printLinesWithCursor(w, "hello\n", 5, .{ .full = {} }, .{ .forward = 1 }, .detect, .{});
    try equal(
        \\1| hello
        \\        ^ (newline)
    , string(&buf));

    // [.show_cursor_hint]
    try printLinesWithCursor(w, "hello\n", 5, .{ .full = {} }, .{ .forward = 1 }, .detect, .{
        .show_cursor_hint = false,
    });
    try equal(
        \\1| hello
        \\        ^
    , string(&buf));

    // [.show_line_num]
    try printLines(w, "hello", 1, .{ .full = {} }, .{ .forward = 1 }, .detect, .{
        .show_line_num = false,
    });
    try equal(
        \\hello␃
    , string(&buf));

    // [.line_num_sep]
    try printLines(w, "hello", 1, .{ .full = {} }, .{ .forward = 1 }, .detect, .{
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
    try printLines(w, input, 15, .{ .full = {} }, .{ .forward = 6 }, .detect, .{});
    try equal(
        \\2| This is the second.
        \\3| A third line is a longer one.
        \\4| 
        \\5| Fifth line.
        \\6| Sixth one.
        \\7| ␃
    , string(&buf));

    // [.set = *] manual line numbering
    try printLines(w, input, 1, .{ .full = {} }, .{ .forward = 6 }, .{ .set = 7 }, .{});
    try equal(
        \\7 | First line.
        \\8 | This is the second.
        \\9 | A third line is a longer one.
        \\10| 
        \\11| Fifth line.
        \\12| Sixth one.
    , string(&buf));

    // [.backward] read, [.around] mode, trunc [.hard_flex]
    try printLinesWithCursor(w, input, 85, .{ .around = .{ .len = 5 } }, .{ .backward = 6 }, .detect, .{
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
        \\         ^ (newline)
    , string(&buf));

    // [.trunc_sym]
    try printLinesWithCursor(w, input, 85, .{ .around = .{ .len = 5 } }, .{ .backward = 1 }, .detect, .{
        .trunc_sym = "__",
    });
    try equal(
        \\6| __one.
        \\         ^ (newline)
    , string(&buf));
}
