// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

const std = @import("std");
const t = std.testing;
const Allocator = std.mem.Allocator;
const Node = @import("parser.zig").Node;
const Parser = @import("parser.zig").Parser;

pub const HtmlOptions = struct {
    indent_size: usize = 2,
};

pub fn Html(opt: HtmlOptions) type {
    return struct {
        lvl: usize = 0,
        const Self = @This();

        pub fn renderFromInput(s: *Self, arena: Allocator, writer: anytype, input: [:0]const u8) !void {
            var parser = Parser(.{}).init(arena, input);
            const root = try parser.parse();
            // try root.?.dumpRec(std.io.getStdErr().writer(), input, 0);
            try s.render(arena, writer, input, root);
        }

        pub fn render(s: *Self, arena: Allocator, writer: anytype, input: [:0]const u8, root: ?*Node) !void {
            if (root) |node| {
                switch (node.tag) {
                    .literal_number => {
                        const literal = node.token.?.sliceFrom(input);
                        try writer.writeByteNTimes(' ', opt.indent_size * s.lvl);
                        try writer.print("{s}\n", .{literal});
                    },
                    .literal_string => {
                        const literal = node.token.?.sliceFrom(input);
                        try writer.writeByteNTimes(' ', opt.indent_size * s.lvl);
                        try writer.print("{s}\n", .{literal[1 .. literal.len - 1]});
                    },
                    .block_enum_and => {
                        for (node.data.list.items) |item| {
                            try s.render(arena, writer, input, item);
                        }
                    },
                    .name_def => {
                        const tag_name = node.token.?.sliceFrom(input);
                        try writer.writeByteNTimes(' ', opt.indent_size * s.lvl);
                        try writer.print("<{0s}>\n", .{tag_name});
                        s.lvl += 1;
                        if (node.get(.val)) |val| {
                            try s.render(arena, writer, input, val);
                        }
                        s.lvl -= 1;
                        try writer.writeByteNTimes(' ', opt.indent_size * s.lvl);
                        try writer.print("</{0s}>\n", .{tag_name});
                    },
                    .literal_identifier => {
                        // resolve in scope, error or ignore otherwise
                    },
                    .ctrl_for => {
                        // evaluate
                    },
                    else => return error.UnsupportedNode,
                }
            }
        }
    };
}

test Html {
    const alloc = std.heap.c_allocator;
    var str = std.BoundedArray(u8, 1024){};

    var html = Html(.{}){};
    try html.renderFromInput(alloc, str.writer(),
        \\ .html
        \\   .div 
        \\     "hello world"
    );
    try t.expectEqualStrings(
        \\<html>
        \\  <div>
        \\    hello world
        \\  </div>
        \\</html>
        \\
    , str.slice());
}
