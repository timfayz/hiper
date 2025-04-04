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
        level: usize = 0,
        alloc: Allocator,
        input: [:0]const u8,
        const Self = @This();

        pub fn init(alloc: Allocator, input: [:0]const u8) Self {
            return .{ .alloc = alloc, .input = input };
        }

        pub fn renderFromInput(h: *Self, alloc: Allocator, writer: anytype, input: [:0]const u8) !void {
            h.input = input;
            var parser = Parser(.{}).init(alloc, input);
            const root = try parser.parse();
            // try root.?.dumpRec(std.io.getStdErr().writer(), input, 0);
            if (root) |node| {
                try h.render(writer, node);
            }
        }

        fn renderIndent(h: *Self, writer: anytype) !void {
            try writer.writeByteNTimes(' ', opt.indent_size * h.level);
        }

        fn renderStringUnquoted(h: *Self, writer: anytype, node: *Node) !void {
            const literal = h.getTagString(node);
            try writer.print("{s}", .{literal[1 .. literal.len - 1]});
        }

        fn renderLiteral(h: *Self, writer: anytype, node: *Node) !void {
            const literal = h.getTagString(node);
            try writer.print("{s}", .{literal});
        }

        fn renderNewline(writer: anytype) !void {
            try writer.writeByte('\n');
        }

        fn getTagString(h: *Self, node: *Node) []const u8 {
            return node.token.?.sliceFrom(h.input);
        }

        fn renderAttr(h: *Self, writer: anytype, node: ?*Node) !void {
            if (node) |n| {
                for (n.children()) |attr| {
                    // try attr.dumpRec(std.io.getStdErr().writer(), h.input, 0);
                    switch (attr.tag) {
                        .name_def => {
                            try writer.print(" {s}", .{h.getTagString(attr)});
                            if (attr.childDescendants(.name_val)) |attr_vals| {
                                try writer.writeByte('=');
                                try h.renderLiteral(writer, attr_vals[0]);
                            }
                        },
                        else => {}, // ignore
                    }
                }
            }
        }

        pub fn render(h: *Self, writer: anytype, node: *Node) !void {
            switch (node.tag) {
                .literal_number => {
                    try h.renderIndent(writer);
                    try h.renderLiteral(writer, node);
                    try renderNewline(writer);
                },
                .literal_string => {
                    try h.renderIndent(writer);
                    try h.renderStringUnquoted(writer, node);
                    try renderNewline(writer);
                },
                .name_def => {
                    try h.renderIndent(writer);
                    const tag_name = h.getTagString(node);
                    try writer.print("<{s}", .{tag_name});
                    try h.renderAttr(writer, node.child(.name_attr));
                    try writer.print(">\n", .{});
                    h.level += 1;
                    if (node.child(.name_val)) |val| {
                        try h.render(writer, val);
                    }
                    h.level -= 1;
                    try h.renderIndent(writer);
                    try writer.print("</{s}>\n", .{tag_name});
                },
                .literal_identifier => {
                    // resolve in scope, error or ignore otherwise
                },
                .ctrl_for => {
                    // evaluate
                },
                .root, .name_val => {
                    for (node.next.items) |child| {
                        try h.render(writer, child);
                    }
                },
                else => {
                    std.log.err("UnsupportedNode: {any}", .{node.tag});
                    return error.UnsupportedNode;
                },
            }
        }
    };
}

test Html {
    const alloc = std.heap.c_allocator;
    var str = std.BoundedArray(u8, 1024){};

    var html = Html(.{}).init(alloc, "");
    try html.renderFromInput(alloc, str.writer(),
        \\ .html
        \\   .div [
        \\     .id = "name"
        \\     .class
        \\   ]
        \\     "hello world"
    );
    try t.expectEqualStrings(
        \\<html>
        \\  <div id="name" class>
        \\    hello world
        \\  </div>
        \\</html>
        \\
    , str.slice());
}
