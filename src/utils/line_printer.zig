// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

//! Public API:
//! - PrintOptions
//! - printLines()
//! - printLinesWithCursor()

const std = @import("std");
const stack = @import("stack.zig");
const slice = @import("slice.zig");
const range = @import("range.zig");
const num = @import("num.zig");
const meta = @import("meta.zig");
const lr = @import("line_reader.zig");

/// Line printing options.
pub const PrintOptions = struct {
    trunc_mode: range.TruncMode = .hard_flex,
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

/// A simple wrapper around `printLine` that forces `opt.show_cursor = true`.
fn printLinesWithCursor(
    writer: anytype,
    input: []const u8,
    index: anytype,
    comptime mode: range.Rel,
    comptime amount: range.Rel,
    line_num: ?usize,
    comptime opt: PrintOptions,
) !void {
    comptime var opt_ = opt;
    opt_.show_cursor = true; // force
    return printLines(writer, input, index, mode, amount, line_num, opt_);
}

/// Prints a specified number of lines from input to writer based on the given
/// view range. `line_num` specifies the current line number; if `null`, it's
/// automatically determined. If the index exceeds the input length, no lines are
/// written.
pub fn printLines(
    writer: anytype,
    input: []const u8,
    index: anytype,
    comptime view_range: range.Rel,
    comptime amount: range.Rel,
    line_num: ?usize,
    comptime opt: PrintOptions,
) !void {
    if (opt.buf_size == 0 or view_range.len() == 0) return;
    var lines_buf: [opt.buf_size][]const u8 = undefined;

    const start: usize, const end: usize = if (meta.isTuple(index)) num.orderPairAsc(index[0], index[1]) else .{ index, index };
    const index_range = end - start +| 1;

    const first = try lr.readLines(&lines_buf, input, start, amount, true);
    if (first.isEmpty()) return;

    var view_segs = stack.init(range.Range, 2);

    if (view_range.fits(index_range)) {
        const curr_line_num = if (line_num) |l| l else lr.countLineNum(input, 0, start);
        const curr_line_view = slice.truncIndices(first.curr(), .{
            first.index_pos,
            first.index_pos,
        }, view_range, opt.trunc_mode, .{});
        view_segs.push(curr_line_view) catch unreachable;
        return renderLines(
            writer,
            input,
            index,
            view_segs.slice(),
            first.lines,
            first.curr_line_pos,
            curr_line_num,
            opt,
        );
    } else {
        // range fits first read range
        if (first.containsIndex(end, input)) {
            // range fits current line range
            const end_pos = first.index_pos + index_range;
            if (end_pos <= first.curr().len) {
                //
            }
        } else {
            //
        }
    }
}

/// Implementation function.
fn renderLines(
    writer: anytype,
    input: []const u8,
    index: usize,
    line_view_segs: []range.Range,
    lines: []const []const u8,
    curr_line_pos: usize,
    curr_line_num: usize,
    comptime opt: PrintOptions,
) !void {
    const first_line_num = curr_line_num -| curr_line_pos;
    const last_line_num = first_line_num +| lines.len;
    const line_num_width = if (opt.show_line_num) num.countIntLen(last_line_num) else 0;

    for (lines, first_line_num.., 0..) |line, ln, i| {
        // render line number
        if (opt.show_line_num)
            try writer.print("{d: <[1]}" ++ opt.line_num_sep, .{ ln, line_num_width });

        // render line
        if (line_view_segs.len > 0) {
            for (line_view_segs) |line_seg| {
                // render line segments
                const seg = line_seg.sliceBounded([]const u8, line);
                if (line_seg.start > 0 and line.len != 0) {
                    try writer.writeAll(opt.trunc_sym);
                }
                try writer.writeAll(seg);
                if (line_seg.end < line.len) {
                    try writer.writeAll(opt.trunc_sym);
                } else if (opt.show_eof and slice.endIndex(input, seg) >= input.len) {
                    try writer.writeAll("␃");
                }
            }
        } else {
            try writer.writeAll(line);
            if (opt.show_eof and slice.endIndex(input, line) >= input.len) {
                try writer.writeAll("␃");
            }
        }
        try writer.writeByte('\n');

        // render cursor
        if (opt.show_cursor and i == curr_line_pos) {
            const curr_line_start = if (line_view_segs.len > 0) line_view_segs[0].start else 0;
            const index_pos = (index - slice.startIndex(input, line)) - curr_line_start;
            const trunc_width = if (curr_line_start > 0) opt.trunc_sym.len else 0;
            const sep_width = if (opt.show_line_num) opt.line_num_sep.len else 0;
            const pad = line_num_width +| sep_width +| trunc_width +| index_pos;

            // head
            try writer.writeByteNTimes(' ', pad);
            try writer.writeByte(opt.cursor_head_char);

            // tail
            // TODO

            // hint
            if (opt.show_cursor_hint) {
                const hint = getHint(input, index, opt);
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
            return str;
        }
    }.run;
    var buf = std.BoundedArray(u8, 1024){};
    const w = buf.writer();

    // out-of-bounds read
    try printLinesWithCursor(w, "hello", 100, .{ .around = 100 }, .{ .right = 1 }, 1, .{});
    try equal(
        \\
    , string(&buf));

    // [.show_cursor]
    try printLines(w, "hello", 1, .{ .around = 100 }, .{ .right = 1 }, 1, .{
        .show_cursor = false,
    });
    try equal(
        \\1| hello␃
        \\
    , string(&buf));

    // [.show_eof]
    try printLinesWithCursor(w, "hello", 1, .{ .around = 100 }, .{ .right = 1 }, 1, .{
        .show_eof = false,
    });
    try equal(
        \\1| hello
        \\    ^
        \\
    , string(&buf));

    // [.hint_printable_chars]
    try printLinesWithCursor(w, "hello\nworld", 7, .{ .around = 100 }, .{ .left = 2 }, 2, .{
        .hint_printable_chars = true,
    });
    try equal(
        \\1| hello
        \\2| world␃
        \\    ^ ('\x6f')
        \\
    , string(&buf));

    // end of string hint
    try printLinesWithCursor(w, "hello\nworld", 11, .{ .around = 100 }, .{ .left = 2 }, 2, .{});
    try equal(
        \\1| hello
        \\2| world␃
        \\        ^ (end of string)
        \\
    , string(&buf));

    // newline hint
    try printLinesWithCursor(w, "hello\n", 5, .{ .around = 100 }, .{ .right = 1 }, 1, .{});
    try equal(
        \\1| hello
        \\        ^ (newline)
        \\
    , string(&buf));

    // [.show_cursor_hint]
    try printLinesWithCursor(w, "hello\n", 5, .{ .around = 100 }, .{ .right = 1 }, 1, .{
        .show_cursor_hint = false,
    });
    try equal(
        \\1| hello
        \\        ^
        \\
    , string(&buf));

    // [.show_line_num]
    try printLinesWithCursor(w, "hello", 1, .{ .around = 100 }, .{ .right = 1 }, 1, .{
        .show_line_num = false,
    });
    try equal(
        \\hello␃
        \\ ^
        \\
    , string(&buf));

    // [.line_num_sep]
    try printLinesWithCursor(w, "hello", 1, .{ .around = 100 }, .{ .right = 1 }, 1, .{
        .line_num_sep = "__",
    });
    try equal(
        \\1__hello␃
        \\    ^
        \\
    , string(&buf));

    // [.trunc_sym]
    try printLinesWithCursor(w, "hello world", 5, .{ .around = 5 }, .{ .right = 1 }, 1, .{
        .trunc_sym = "--",
    });
    try equal(
        \\1| --lo wor--
        \\       ^ (space)
        \\
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

    // automatic line numbering (null)
    try printLinesWithCursor(w, input, 15, .{ .around = 100 }, .{ .right = 6 }, null, .{});
    try equal(
        \\2| This is the second.
        \\      ^
        \\3| A third line is a l..
        \\4| 
        \\5| Fifth line.
        \\6| Sixth one.
        \\7| ␃
        \\
    , string(&buf));

    // // [.backward] read, [.around] mode, trunc [.hard_flex]
    // try printLinesWithCursor(w, input, 85, .{ .around = 5 }, .{ .right = 6 }, null, .{
    //     .trunc_mode = .hard_flex,
    //     .show_cursor_hint = true,
    // });
    // try equal(
    //     \\1| ..line..
    //     \\2| ..s th..
    //     \\3| ..d li..
    //     \\4|
    //     \\5| ..line..
    //     \\6| ..one.
    //     \\         ^ (newline)
    // , string(&buf));
}
