const std = @import("std");
const Parser = @import("parser.zig").Parser;
const Node = @import("parser.zig").Node;

pub fn writeDebugTree(alloc: std.mem.Allocator, tree: ?*Node, lvl: usize) ![]u8 {
    if (tree) |node| {
        var out = std.ArrayList(u8).init(alloc);
        const indent_size = 2;
        // `  [node_tag]`
        try out.appendNTimes(' ', indent_size * lvl);
        try out.writer().print(".{s}", .{@tagName(node.tag)});
        switch (node.data) {
            .literal => |token| {
                // ` -> "literal"`
                try out.writer().print(" -> \"{s}\"\n", .{token});
            },
            .single => |elm| {
                // `\n` + recursion
                try out.append('\n');
                const rhs = try writeDebugTree(alloc, elm, (lvl + 1));
                try out.appendSlice(rhs);
            },
            .pair => |pair| {
                // `\n` + recursion
                try out.append('\n');
                const lhs = try writeDebugTree(alloc, pair.left, (lvl + 1));
                try out.appendSlice(lhs);
                const rhs = try writeDebugTree(alloc, pair.right, (lvl + 1));
                try out.appendSlice(rhs);
            },
            .list => |list| {
                // `\n` + recursion
                try out.append('\n');
                for (list.items) |item| {
                    const res = try writeDebugTree(alloc, item, (lvl + 1));
                    try out.appendSlice(res);
                }
            },
            .map => |map| {
                // `\n`
                try out.append('\n');
                var iter = map.iterator();
                while (iter.next()) |entry| {
                    // `  "key" -> .node_tag`
                    try out.appendNTimes(' ', indent_size * (lvl + 1));
                    try out.writer().print("\"{s}\":\n", .{entry.key_ptr.*});
                    const rhs = try writeDebugTree(alloc, entry.value_ptr.*, (lvl + 2));
                    try out.appendSlice(rhs);
                }
            },
        }
        return out.toOwnedSlice();
    }
    return "";
}

