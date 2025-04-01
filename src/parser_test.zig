// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

const std = @import("std");
const t = std.testing;
const Allocator = std.mem.Allocator;
const parser = @import("parser.zig");
const Parser = @import("parser.zig").Parser;
const Node = @import("parser.zig").Node;

test Parser {
    const alloc = std.heap.c_allocator;
    // defer parser.logger.flush() catch {};
    const case = struct {
        pub fn run(alc: Allocator, node: ?*Node, expect: []const u8, input: []const u8) !void {
            if (node) |n| {
                try t.expectEqualStrings(expect, try n.dumpRecString(alc, input));
            } else return error.UnexpectedNull;
        }
    }.run;
    {
        const input =
            \\()
        ;
        var p = Parser(.{}).init(alloc, input);
        try t.expectError(error.UnexpectedToken, p.parse());
    }
    {
        const input =
            \\ 1 + 2 * 3
        ;
        var p = Parser(.{}).init(alloc, input);
        try case(alloc, try p.parse(),
            \\.root '?'
            \\  .op_arith_add '+'
            \\    .literal_number '1'
            \\    .op_arith_mul '*'
            \\      .literal_number '2'
            \\      .literal_number '3'
            \\
        , input);
    }
    {
        const input =
            \\ 1, 2, 3
            \\ ((1 + 2) * 3)
            \\ 4
        ;
        var p = Parser(.{}).init(alloc, input);
        try case(alloc, try p.parse(),
            \\.root '?'
            \\  .inline_enum_and ','
            \\    .literal_number '1'
            \\    .literal_number '2'
            \\    .literal_number '3'
            \\  .parens '('
            \\    .op_arith_mul '*'
            \\      .parens '('
            \\        .op_arith_add '+'
            \\          .literal_number '1'
            \\          .literal_number '2'
            \\      .literal_number '3'
            \\  .literal_number '4'
            \\
        , input);
    }
    // {
    //     const input =
    //         \\ .a [.x, .z]
    //         \\   1, 2, 3
    //         \\   4
    //         \\ .b
    //     ;
    //     var p = Parser(.{}).init(alloc, input);
    //     try case(alloc, try p.parse(),
    //         \\.block_enum_and ' '
    //         \\  .name_def 'a'
    //         \\    .square '['
    //         \\      .inline_enum_and ','
    //         \\        .name_def 'x'
    //         \\        .name_def 'z'
    //         \\    .block_assign '   '
    //         \\      .block_enum_and '   '
    //         \\        .inline_enum_and ','
    //         \\          .literal_number '1'
    //         \\          .literal_number '2'
    //         \\          .literal_number '3'
    //         \\        .literal_number '4'
    //         \\  .name_def 'b'
    //         \\
    //     , input);
    // }
}
