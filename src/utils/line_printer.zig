const std = @import("std");
const lr = @import("line_reader.zig");

pub const LinePrinterOptions = struct {
    view_len: u8 = 80,
    view_line_at: enum { start, end, cursor } = .cursor,
    show_line_numbers: bool = true,
    show_eof: bool = true,
    show_cursor_hint: bool = true,
    hint_printable_chars: bool = false,
    line_number_sep: []const u8 = " | ",
    skip_symbol: []const u8 = "..",
    cursor_head_char: u8 = '^',
};

/// Reads a line from the input at the specified index and writes it to the
/// writer. If `line_number` is 0, it is automatically detected; otherwise, the
/// specified number is used as is. See `LineReaderOptions` for additional
/// options.
pub fn printLine(
    writer: anytype,
    input: [:0]const u8,
    index: usize,
    line_number: usize,
    comptime opt: LinePrinterOptions,
) !void {
    if (opt.view_len < 1) @compileError("view_length cannot be less than one");
    const line, const line_index_pos = lr.readLine(input, index); // get current line
    const number = if (line_number == 0) lr.lineNumAt(input, index) else line_number;
    _ = try printLineNumImpl(writer, number, opt);
    _ = try printLineImpl(writer, input, line, line_index_pos, opt);
}

test "+printLine" {
    const t = std.testing;

    const case = struct {
        pub fn run(
            input: [:0]const u8,
            index: usize,
            line_number: usize,
            comptime opt: LinePrinterOptions,
            expect: []const u8,
        ) !void {
            var out = std.BoundedArray(u8, 256){};
            try printLine(out.writer(), input, index, line_number, opt);
            try t.expectEqualStrings(expect, out.slice());
        }
    };

    // .show_eof
    //            |idx| |line_num|
    try case.run("", 0, 0, .{ .show_eof = false },
        \\1 | 
        \\
    );
    try case.run("", 0, 0, .{ .show_eof = true },
        \\1 | ␃
        \\
    );

    // .show_line_numbers
    //
    try case.run("", 0, 0, .{ .show_line_numbers = false },
        \\␃
        \\
    );
    try case.run("", 0, 0, .{ .show_eof = false, .show_line_numbers = false },
        \\
        \\
    );
    try case.run("", 0, 0, .{ .show_line_numbers = true },
        \\1 | ␃
        \\
    );

    // .line_number_sep
    //
    try case.run("hello", 0, 0, .{ .line_number_sep = "__" },
        \\1__hello␃
        \\
    );
    try case.run("hello", 0, 0, .{ .line_number_sep = "" },
        \\1hello␃
        \\
    );

    // .view_line_at
    //
    try case.run("hello", 0, 0, .{ .view_len = 3, .view_line_at = .end },
        \\1 | ..llo␃
        \\
    );
    try case.run("hello", 0, 0, .{ .view_len = 3, .view_line_at = .start },
        \\1 | hel..
        \\
    );
    try case.run("hello", 2, 0, .{ .view_len = 3, .view_line_at = .cursor },
        \\1 | ..ell..
        \\
    );

    // manual line number specification
    //
    try case.run("hello", 0, 2, .{},
        \\2 | hello␃
        \\
    );

    // automatic line number detection
    //
    const input =
        \\first line
        //^0        ^10
        \\second line
        //^11        ^22
        \\
        //^23
    ;
    try case.run(input, 0, 0, .{},
        \\1 | first line
        \\
    );
    try case.run(input, 5, 0, .{},
        \\1 | first line
        \\
    );
    try case.run(input, 12, 0, .{},
        \\2 | second line
        \\
    );
    try case.run(input, 22, 0, .{},
        \\2 | second line
        \\
    );
    try case.run(input, 100, 0, .{},
        \\3 | ␃
        \\
    );
}

/// Reads a line from the input at the specified index and writes it to the
/// writer. If `line_number` is 0, it is automatically detected; otherwise, the
/// specified number is used as is. In addition to printing the line, this
/// function provides a cursor at the specified position with an optional
/// hint. See `LineReaderOptions` for additional options.
pub fn printLineWithCursor(
    writer: anytype,
    input: [:0]const u8,
    index: usize,
    line_number: usize,
    comptime opt: LinePrinterOptions,
) !void {
    if (opt.view_len < 1) @compileError("view_length cannot be less than one");
    const line, const line_index_pos = lr.readLine(input, index); // get current line
    const number = if (line_number == 0) lr.lineNumAt(input, index) else line_number;
    const number_col_width = try printLineNumImpl(writer, number, opt);
    const new_index_pos = try printLineImpl(writer, input, line, line_index_pos, opt);
    // force line view at cursor position
    comptime var opt_forced = opt;
    opt_forced.view_line_at = .cursor;
    try printCursorImpl(writer, input, index, number_col_width + new_index_pos, opt_forced);
}

/// Implementation function. Prints `line_number`.
inline fn printLineNumImpl(
    writer: anytype,
    line_number: usize,
    comptime opt: LinePrinterOptions,
) !usize {
    if (opt.show_line_numbers) {
        try writer.print("{d}" ++ opt.line_number_sep, .{line_number});
        return lr.intLen(line_number) + opt.line_number_sep.len;
    }
    return 0;
}

/// Implementation function. Prints `line` and recalculate `line_index_pos`.
inline fn printLineImpl(
    writer: anytype,
    input: [:0]const u8,
    line: []const u8,
    line_index_pos: usize,
    comptime opt: LinePrinterOptions,
) !usize {
    var new_index_pos = line_index_pos;
    // line exceeds the view length
    if (line.len > opt.view_len) {
        switch (opt.view_line_at) {
            .cursor => {
                const extra_rshift = if (opt.view_len & 1 == 0) 1 else 0; // if view_len is even
                const view_start = @min(line_index_pos -| opt.view_len / 2 + extra_rshift, line.len - opt.view_len);
                const view_end = @min(view_start + opt.view_len, line.len);
                new_index_pos = line_index_pos - view_start;
                if (view_start > 0) {
                    try writer.writeAll(opt.skip_symbol);
                    new_index_pos += opt.skip_symbol.len;
                }
                try writer.writeAll(line[view_start..view_end]);
                if (view_end < line.len) {
                    try writer.writeAll(opt.skip_symbol);
                } else if (opt.show_eof and lr.indexOfSliceEnd(input, line) >= input.len) {
                    try writer.writeAll("␃");
                }
            },
            .end => {
                try writer.writeAll(opt.skip_symbol);
                try writer.writeAll(line[line.len - opt.view_len ..]);
                if (opt.show_eof and lr.indexOfSliceEnd(input, line) >= input.len)
                    try writer.writeAll("␃");
            },
            .start => {
                try writer.writeAll(line[0..opt.view_len]);
                try writer.writeAll(opt.skip_symbol);
            },
        }
    }
    // line fits the entire view length
    else {
        try writer.writeAll(line);
        if (opt.show_eof and lr.indexOfSliceEnd(input, line) >= input.len)
            try writer.writeAll("␃");
    }
    try writer.writeByte('\n');
    return new_index_pos;
}

test "+printLineImpl" {
    const t = std.testing;

    const run = struct {
        fn case(
            line: [:0]const u8,
            line_index_pos: usize,
            expect: []const u8,
            expect_index_pos: usize,
            comptime opt: LinePrinterOptions,
        ) !void {
            var out = std.BoundedArray(u8, 256){};
            const actual_index_pos = try printLineImpl(out.writer(), line, line, line_index_pos, opt);
            try t.expectEqualStrings(expect, out.slice());
            try t.expectEqual(expect_index_pos, actual_index_pos);
        }
    };

    // view_line_at = .cursor (default)

    try run.case("", 0, "␃\n", 0, .{ .view_len = 100 });
    //
    try run.case("01234", 0, "0..\n", 0, .{ .view_len = 1 });
    //            ^
    try run.case("01234", 0, "01234␃\n", 0, .{ .view_len = 5 });
    //            ^
    try run.case("01234", 0, "01234␃\n", 0, .{ .view_len = 10 });
    //            ^
    try run.case("01234", 0, "012..\n", 0, .{ .view_len = 3 });
    //            ^           ^
    try run.case("01234", 1, "012..\n", 1, .{ .view_len = 3 });
    //             ^           ^

    try run.case("01234", 2, "..123..\n", 3, .{ .view_len = 3 });
    //              ^            ^
    try run.case("01234", 2, "..23..\n", 2, .{ .view_len = 2 });
    //              ^           ^
    try run.case("01234", 2, "..2..\n", 2, .{ .view_len = 1 });
    //              ^           ^
    try run.case("01234", 2, "..1234␃\n", 3, .{ .view_len = 4 });
    //              ^            ^
    try run.case("01234", 2, "01234␃\n", 2, .{ .view_len = 10 });
    //              ^           ^

    try run.case("01234", 4, "..234␃\n", 4, .{ .view_len = 3 });
    //                ^           ^
    try run.case("01234", 5, "..234␃\n", 5, .{ .view_len = 3 });
    //                 ^           ^
    try run.case("01234", 5, "..34␃\n", 4, .{ .view_len = 2 });
    //                 ^          ^
    try run.case("01234", 5, "..4␃\n", 3, .{ .view_len = 1 });
    //                 ^         ^
}

/// Implementation function. Prints a cursor.
fn printCursorImpl(
    writer: anytype,
    input: [:0]const u8,
    index: usize,
    line_index_pos: usize,
    comptime opt: LinePrinterOptions,
) !void {
    try writer.writeByteNTimes(' ', line_index_pos);
    try writer.writeByte(opt.cursor_head_char);
    if (opt.show_cursor_hint) {
        const hint = cursorHintImpl(input, index, opt);
        if (hint.len > 0) try writer.writeAll(hint);
    }
    try writer.writeByte('\n');
}

/// Implementation function. Prints a cursor hint.
fn cursorHintImpl(
    input: [:0]const u8,
    index: usize,
    comptime opt: LinePrinterOptions,
) []const u8 {
    if (index >= input.len) return " (end of string)";
    return switch (input[index]) {
        '\n' => " (newline)",
        ' ' => " (space)",
        inline '!'...'~',
        => |char| if (opt.hint_printable_chars)
            std.fmt.comptimePrint(" ('\\x{x}')", .{char})
        else
            "",
        else => "",
    };
}

test "+printLineWithCursor" {
    const t = std.testing;

    const case = struct {
        pub fn run(
            input: [:0]const u8,
            index: usize,
            comptime opt: LinePrinterOptions,
            expect: []const u8,
        ) !void {
            var out = std.BoundedArray(u8, 256){};
            try printLineWithCursor(out.writer(), input, index, 0, opt); // auto line number detection
            try t.expectEqualStrings(expect, out.slice());
        }
    };

    const input =
        \\line1
        \\line2
        \\
    ;

    try case.run(input, 0, .{},
        \\1 | line1
        \\    ^
        \\
    );
    try case.run(input, 0, .{ .view_len = 3 },
        \\1 | lin..
        \\    ^
        \\
    );
    try case.run(input, 4, .{},
        \\1 | line1
        \\        ^
        \\
    );
    try case.run(input, 5, .{},
        \\1 | line1
        \\         ^ (newline)
        \\
    );
    try case.run(input, 5, .{ .view_len = 3 },
        \\1 | ..ne1
        \\         ^ (newline)
        \\
    );

    try case.run(input, 6, .{},
        \\2 | line2
        \\    ^
        \\
    );

    try case.run(input, 100, .{},
        \\3 | ␃
        \\    ^ (end of string)
        \\
    );
}
