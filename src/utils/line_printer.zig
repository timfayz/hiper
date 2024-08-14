const std = @import("std");
const lr = @import("line_reader.zig");

pub const LinePrinterOptions = struct {
    max_line_width: u8 = 80,
    trim_alignment: enum { left, right } = .right,
    show_line_numbers: bool = true,
    line_number_sep: []const u8 = " | ",
    show_eof: bool = true,
    show_cursor_hint: bool = true,
    hint_printable_chars: bool = false,
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
    if (opt.max_line_width < 1) @compileError("max_line_width cannot be less than one");
    const line, _ = lr.readLine(input, index); // get current line
    const number = if (line_number == 0) lr.lineNumAt(input, index) else line_number;
    _ = try printLineNumImpl(writer, number, opt);
    try printLineImpl(writer, input, line, opt);
}

test "+printLine" {
    const t = std.testing;

    // test line and cursor rendering
    const case = struct {
        pub fn run(
            input: [:0]const u8,
            at: struct { index: usize, line_number: usize = 0 },
            comptime opt: LinePrinterOptions,
            expect: []const u8,
        ) !void {
            var out = std.ArrayList(u8).init(t.allocator);
            defer out.deinit();
            try printLine(out.writer(), input, at.index, at.line_number, opt);
            try t.expectEqualStrings(expect, out.items);
        }
    };

    // .show_eof

    try case.run("", .{ .index = 0 }, .{ .show_eof = false },
        \\1 | 
        \\
    );

    try case.run("", .{ .index = 0 }, .{ .show_eof = true },
        \\1 | ␃
        \\
    );

    // .show_line_numbers

    try case.run("", .{ .index = 0 }, .{ .show_line_numbers = false },
        \\␃
        \\
    );

    try case.run("", .{ .index = 0 }, .{ .show_eof = false, .show_line_numbers = false },
        \\
        \\
    );

    try case.run("", .{ .index = 0 }, .{ .show_line_numbers = true },
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

/// Reads a line from the input at the specified index and writes it to the
/// writer. If `line_number` is 0, it is automatically detected; otherwise, the
/// specified number is used as is. In addition to printing the line, this
/// function also provides a cursor at the specified position with an optional
/// hint. See `LineReaderOptions` for additional options.
pub fn printLineWithCursor(
    writer: anytype,
    input: [:0]const u8,
    index: usize,
    line_number: usize,
    comptime opt: LinePrinterOptions,
) !void {
    if (opt.max_line_width < 1) @compileError("max_line_width cannot be less than one");
    const line, const index_rel_pos = lr.readLine(input, index); // get current line
    const number = if (line_number == 0) lr.lineNumAt(input, index) else line_number;
    const num_col_width = try printLineNumImpl(writer, number, opt);
    try printLineImpl(writer, input, line, opt);
    try printCursorImpl(writer, input, index, num_col_width + index_rel_pos, opt);
}

/// Implementation function. Should not be used directly.
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

/// Implementation function. Should not be used directly.
inline fn printLineImpl(
    writer: anytype,
    input: [:0]const u8,
    line: []const u8,
    comptime opt: LinePrinterOptions,
) !void {
    if (line.len > opt.max_line_width) { // trimming
        switch (opt.trim_alignment) {
            .right => {
                try writer.writeAll(line[0..opt.max_line_width]);
                try writer.writeAll("..");
            },
            .left => {
                try writer.writeAll("..");
                try writer.writeAll(line[line.len - opt.max_line_width ..]);
                if (opt.show_eof and lr.indexOfSliceEnd(input, line) >= input.len)
                    try writer.writeAll("␃");
            },
        }
    } else {
        try writer.writeAll(line);
        if (opt.show_eof and lr.indexOfSliceEnd(input, line) >= input.len)
            try writer.writeAll("␃");
    }
    try writer.writeByte('\n');
}

/// Implementation function. Should not be used directly.
fn printCursorImpl(
    writer: anytype,
    input: [:0]const u8,
    index: usize,
    index_rel_pos: usize,
    comptime opt: LinePrinterOptions,
) !void {
    try writer.writeByteNTimes(' ', index_rel_pos);
    try writer.writeByte(opt.cursor_head_char);
    if (opt.show_cursor_hint) {
        const hint = cursorHintImpl(input, index, opt);
        if (hint.len > 0) try writer.writeAll(hint);
    }
    try writer.writeByte('\n');
}

/// Implementation function. Should not be used directly.
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
            at: struct { index: usize, line_number: usize = 0 },
            expect: []const u8,
        ) !void {
            var out = std.ArrayList(u8).init(t.allocator);
            defer out.deinit();
            try printLineWithCursor(out.writer(), input, at.index, at.line_number, .{});
            try t.expectEqualStrings(expect, out.items);
        }
    };

    const input =
        \\line1
        \\line2
        \\
    ;
    try case.run(input, .{ .index = 0 },
        \\1 | line1
        \\    ^
        \\
    );
    try case.run(input, .{ .index = 5 },
        \\1 | line1
        \\         ^ (newline)
        \\
    );
    try case.run(input, .{ .index = 6 },
        \\2 | line2
        \\    ^
        \\
    );
    try case.run(input, .{ .index = 100 },
        \\3 | ␃
        \\    ^ (end of string)
        \\
    );
}
