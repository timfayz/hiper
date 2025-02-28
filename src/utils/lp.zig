// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

//! Public API:
//! - PrinterOptions
//! - Printer

const std = @import("std");
const Range = @import("span.zig").Range;
const Dir = @import("span.zig").Dir;
const lr = @import("lr.zig");
const num = @import("num.zig");
const slice = @import("slice.zig");
const t = std.testing;

/// Line printing options.
pub const PrinterOptions = struct {
    trunc_sym: []const u8 = "..",
    show_line_num: bool = true,
    line_num_sep: []const u8 = "| ",
    show_eof: bool = true,

    // Cursor related options.
    show_cursor: bool = false,
    show_cursor_hint: bool = true,
    hint_printable_chars: bool = false,
    cursor_head_char: u8 = '^',
    cursor_body_char: u8 = '~',
};

pub fn Printer(WriterType: type, opt: PrinterOptions) type {
    return struct {
        input: []const u8,
        writer: WriterType,
        num_col_width: usize,
        trunc_start: bool = false,

        const Self = @This();

        pub fn init(writer: WriterType, input: []const u8, num_col_width: usize) Self {
            return .{ .input = input, .writer = writer, .num_col_width = num_col_width };
        }

        pub fn printRaw(p: *const Self, comptime format: []const u8, args: anytype) !void {
            try p.writer.print(format, args);
        }

        pub fn printLineNum(p: *const Self, n: usize) !void {
            if (opt.show_line_num)
                try p.writer.print("{d: <[1]}" ++ opt.line_num_sep, .{ n, p.num_col_width });
        }

        pub fn printLineSeg(p: *Self, trunc_side: Dir.Side, line: []const u8) !void {
            if (trunc_side == .both or trunc_side == .left) p.printTruncPre();
            try p.writer.writeAll(line);
            if (trunc_side == .both or trunc_side == .right) p.printTruncPost();
            try p.printEOL(line);
        }

        pub fn printLineSegAuto(p: *Self, line: []const u8) !void {
            if (lr.truncatedStart(p.input, line)) try p.printTruncPre();
            try p.writer.writeAll(line);
            if (lr.truncatedEnd(p.input, line)) try p.printTruncPost();
            try p.printEOL(line);
        }

        pub fn printLine(p: *const Self, line: []const u8) !void {
            try p.writer.writeAll(line);
            try p.printEOL(line);
        }

        pub fn printNL(p: *Self) !void {
            try p.writer.writeByte('\n');
        }

        pub fn printNLAndReset(p: *Self) !void {
            try p.writer.writeByte('\n');
            p.trunc_start = false;
        }

        pub fn printTruncPre(p: *Self) !void {
            try p.writer.writeAll(opt.trunc_sym);
            p.trunc_start = true;
        }

        pub fn printTruncPost(p: *Self) !void {
            try p.writer.writeAll(opt.trunc_sym);
        }

        pub fn printEOL(p: *const Self, line: []const u8) !void {
            if (opt.show_eof and slice.endIndex(p.input, line) >= p.input.len)
                try p.writer.writeAll("␃");
        }

        pub fn printSpace(p: *const Self, size: usize) !void {
            try p.writer.writeByteNTimes(' ', size);
        }

        pub fn printCursorPad(p: *const Self, size: usize) !void {
            if (opt.show_cursor) {
                const trunc_pad = if (p.trunc_start) opt.trunc_sym.len else 0;
                try p.writer.writeByteNTimes(' ', opt.line_num_sep.len +| p.num_col_width +| trunc_pad +| size);
            }
        }

        pub fn printCursorHead(p: *const Self, size: usize) !void {
            if (opt.show_cursor)
                try p.writer.writeByteNTimes(opt.cursor_head_char, size);
        }

        pub fn printCursorBody(p: *const Self, size: usize) !void {
            if (opt.show_cursor)
                try p.writer.writeByteNTimes(opt.cursor_body_char, size);
        }

        pub fn printCursorHint(p: *const Self, index: usize) !void {
            if (opt.show_cursor_hint) {
                const hint = p.getCursorHint(index);
                if (hint.len > 0) {
                    try p.writer.writeAll("(");
                    try p.writer.writeAll(hint);
                    try p.writer.writeAll(")");
                }
            }
        }

        fn getCursorHint(p: *const Self, index: usize) []const u8 {
            return if (index >= p.input.len)
                "end of string"
            else switch (p.input[index]) {
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
    };
}

test Printer {
    const input = "hello\nworld";
    //             0123456789ABCDE

    const line, const index_pos = lr.readLineAroundRange(input, 5, 1, .{ .left = 3 }, .{});

    var str = std.BoundedArray(u8, 512){};
    var lp = Printer(@TypeOf(str.writer()), .{ .show_cursor = true }).init(str.writer(), input, 1);
    try lp.printLineNum(2);
    try lp.printLineSegAuto(line);
    try lp.printNL();
    try lp.printCursorPad(index_pos);
    try lp.printCursorHead(1); // rest = line.len -| index_pos -| range_len
    try lp.printSpace(1);
    try lp.printCursorHint(5);
    try lp.printNLAndReset();

    try t.expectEqualStrings(
        \\2| ..llo
        \\        ^ (newline)
        \\
    , str.slice());
}
