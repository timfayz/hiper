// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

//! Public API:
//! - Node
//! - Error
//! - ParserOptions
//! - Parser

const std = @import("std");
const t = std.testing;
const ThisFile = @This();
const slice = @import("utils/slice.zig");
const line = @import("utils/line.zig");
pub const List = std.ArrayListUnmanaged;
pub const Map = std.StringHashMapUnmanaged;
pub const Token = @import("tokenizer.zig").Token;
pub const Tokenizer = @import("tokenizer.zig").Tokenizer(.{
    .tokenize_spaces = false,
    .tokenize_indents = true,
});
var logger = @import("utils/log.zig").Scope(.parser, .{}){};

pub const Node = struct {
    tag: Tag,
    token: Token,
    data: Data,

    pub const Data = union {
        void: void,
        single: *Node,
        pair: struct { left: *Node, right: *Node },
        list: List(*Node),

        pub const Tag = enum { void, single, pair, list };
    };

    pub const Tag = enum {
        // primitives
        literal_number,
        literal_string,
        literal_identifier,

        // aggregation
        list_and,
        list_or,

        // arithmetics
        op_arith_add,
        op_arith_sub,
        op_arith_mul,
        op_arith_div,
        op_arith_exp,
        op_arith_neg,

        // abstraction
        node_def,
        node_ref,

        // control
        ctrl_for,
        ctrl_while,
        ctrl_if,

        pub fn dataTag(tag: Tag) Data.Tag {
            return switch (tag) {
                .op_arith_neg,
                => .single,

                .op_arith_add,
                .op_arith_sub,
                .op_arith_mul,
                .op_arith_div,
                .op_arith_exp,
                => .pair,

                .list_and,
                .list_or,
                => .list,

                .node_def,
                .node_ref,
                .ctrl_for,
                .ctrl_while,
                .ctrl_if,
                => .list,

                else => .void,
            };
        }

        const precedence_table = blk: {
            const tags_len = std.meta.fields(Tag).len;
            var table = [1]std.meta.Tag(Tag){0} ** tags_len; // 0 for all, except:
            table[@intFromEnum(Tag.list_and)] = 1;
            table[@intFromEnum(Tag.list_or)] = 2;
            table[@intFromEnum(Tag.op_arith_add)] = 3;
            table[@intFromEnum(Tag.op_arith_sub)] = 3;
            table[@intFromEnum(Tag.op_arith_mul)] = 4;
            table[@intFromEnum(Tag.op_arith_div)] = 4;
            table[@intFromEnum(Tag.op_arith_exp)] = 5;
            table[@intFromEnum(Tag.op_arith_neg)] = 5;
            break :blk table;
        };

        pub fn fromTokenTag(comptime tok_tag: Token.Tag) Tag {
            return switch (tok_tag) {
                .minus => .op_arith_sub,
                .plus => .op_arith_add,
                .asterisk => .op_arith_mul,
                .slash => .op_arith_div,
                .caret => .op_arith_exp,
                else => unreachable,
            };
        }

        pub fn precedence(tag: Tag) std.meta.Tag(Tag) {
            return precedence_table[@intFromEnum(tag)];
        }

        /// Right associative: `1 + 2 + 3` –› `(1 + (2 + 3))`.
        /// Left associative: `1 + 2 + 3` –› `((1 + 2) + 3)`.
        pub fn isRightAssociative(tag: Tag) bool {
            return tag.precedence() == 0 or tag == .op_arith_exp;
        }

        pub fn isHigherPrecedenceThan(left: Tag, right: Tag) bool {
            return left.precedence() > right.precedence() or
                (left.precedence() == right.precedence() and left.isRightAssociative());
        }
    };

    pub fn init(alloc: std.mem.Allocator, comptime tag: Tag, token: Token) !*Node {
        const node = try alloc.create(Node);
        node.tag = tag;
        node.token = token;
        node.data = @unionInit(Data, @tagName(tag.dataTag()), undefined);
        return node;
    }

    pub fn dumpTree(node: *const Node, writer: anytype, input: []const u8, lvl: usize) !void {
        const tok = node.token.sliceFrom(input);
        try writer.writeByteNTimes(' ', lvl * 2);
        try writer.print(".{s} '{s}'\n", .{
            @tagName(node.tag),
            if (tok.len > 10) tok[0..10] ++ ".." else tok,
        });
        if (lvl > 16) return;
        switch (node.tag.dataTag()) {
            .void => {},
            .pair => {
                try node.data.pair.left.dumpTree(writer, input, lvl +| 1);
                try node.data.pair.right.dumpTree(writer, input, lvl +| 1);
            },
            .list => {
                for (node.data.list.items) |item| {
                    try item.dumpTree(writer, input, lvl +| 1);
                }
            },
            else => unreachable,
        }
    }

    pub fn dumpTreeString(node: *const Node, alloc: std.mem.Allocator, input: []const u8) ![]u8 {
        var str = std.ArrayListUnmanaged(u8){};
        try node.dumpTree(str.writer(alloc), input, 0);
        return try str.toOwnedSlice(alloc);
    }
};

pub const Error = error{
    OutOfMemory,
    InvalidToken,
    UnalignedIndentSize,
    IndentationTooDeep,
    UnexpectedToken,
};

pub const ParserOptions = struct {
    log: bool = false,
};

pub fn Parser(opt: ParserOptions) type {
    return struct {
        alloc: std.mem.Allocator,
        tokenizer: Tokenizer,
        token: Token = undefined,
        indent: Indent = .{},
        pending_nodes: List(*Node) = .{},
        parsed_nodes: List(*Node) = .{},
        scope: List(*Node) = .{},
        pending_states: std.BoundedArray(State, 32) = .{},
        state: State = .exp_prime,

        const Self = @This();

        pub const State = enum {
            exp_prime,
            exp_post_prime,
            exp_right_paren,
            //
            end,
        };

        pub const Indent = struct {
            trim_size: usize = 0,
            size: usize = 0,
            level: usize = 0,
        };

        pub fn init(alloc: std.mem.Allocator, input: [:0]const u8) Self {
            return .{ .tokenizer = .init(input), .alloc = alloc };
        }

        pub fn parseInput(alloc: std.mem.Allocator, input: [:0]const u8) Error!?*Node {
            var p = Self.init(alloc, input);
            return p.parse();
        }

        pub fn firstRun(p: *Self) void {
            p.token = p.tokenizer.nextFrom(.space);
            switch (p.token.tag) {
                .space => p.indent.trim_size = p.token.len(),
                else => {},
            }
        }

        pub fn parse(p: *Self) Error!?*Node {
            p.firstRun();
            p.pending_states.append(.end) catch return error.OutOfMemory;
            while (true) {
                p.token = p.tokenizer.next();
                p.log(logger.writer(), .token, false);
                p.log(logger.writer(), .pending_nodes, false);
                p.log(logger.writer(), .parsed_nodes, false);
                p.log(logger.writer(), .state, true);
                switch (p.state) {
                    // empty | a.. | if.. | true.. | ..
                    .exp_prime => {
                        switch (p.token.tag) {
                            .number => {
                                const n = try Node.init(p.alloc, .literal_number, p.token);
                                try p.parsed_nodes.append(p.alloc, n);
                                p.state = .exp_post_prime;
                            },
                            // .left_paren => {
                            //     p.pending_states = .exp_right_paren;
                            // },
                            else => {
                                p.state = p.pending_states.pop().?;
                            },
                        }
                    },

                    // a+.. | a,..
                    .exp_post_prime => {
                        switch (p.token.tag) {
                            inline .minus, .plus, .asterisk, .slash => |tag| {
                                const node_tag = comptime Node.Tag.fromTokenTag(tag);
                                while (p.pending_nodes.getLastOrNull()) |last| {
                                    if (last.tag.isHigherPrecedenceThan(node_tag)) {
                                        try p.resolveNode(last);
                                        _ = p.pending_nodes.pop();
                                    } else break;
                                }
                                const node = try Node.init(p.alloc, node_tag, p.token);
                                try p.pending_nodes.append(p.alloc, node);
                                p.state = .exp_prime;
                            },
                            .comma => {
                                while (p.pending_nodes.pop()) |n| try p.resolveNode(n);
                                const node = try Node.init(p.alloc, .list_and, p.token);
                                try p.pending_nodes.append(p.alloc, node);
                                p.state = .exp_prime;
                            },
                            else => {
                                p.state = p.pending_states.pop().?;
                            },
                        }
                    },

                    .end => {
                        switch (p.token.tag) {
                            .eof => {
                                while (p.pending_nodes.pop()) |n| try p.resolveNode(n);
                                break;
                            },
                            else => return error.UnexpectedToken,
                        }
                    },

                    else => unreachable,
                }
            }
            p.log(logger.writer(), .all, true);

            return p.parsed_nodes.pop();
        }

        pub fn resolveNode(p: *Self, node: *Node) !void {
            switch (node.tag) {
                .op_arith_add,
                .op_arith_mul,
                => {
                    node.data.pair.right = p.parsed_nodes.pop().?;
                    node.data.pair.left = p.parsed_nodes.pop().?;
                    try p.parsed_nodes.append(p.alloc, node);
                },
                .list_and,
                => {
                    const tail = p.parsed_nodes.pop().?;
                    const head = p.parsed_nodes.getLast();
                    if (head.tag == .list_and) {
                        try head.data.list.append(p.alloc, tail);
                    } else {
                        const list = try Node.init(p.alloc, .list_and, p.token);
                        try list.data.list.append(p.alloc, p.parsed_nodes.pop().?); // head
                        try list.data.list.append(p.alloc, tail);
                        try p.parsed_nodes.append(p.alloc, list);
                    }
                },
                else => unreachable,
            }
        }

        pub fn log(
            p: *const Self,
            writer: anytype,
            comptime part: enum {
                all,
                indent,
                pending_nodes,
                parsed_nodes,
                token,
                state,
                cursor,
            },
            comptime extra_nl: bool,
        ) void {
            if (!opt.log) return;
            switch (part) {
                .token => {
                    writer.print("token: .{s} '{s}'\n", .{ @tagName(p.token.tag), slice.first([]const u8, p.token.sliceFrom(p.tokenizer.input), 10) }) catch {};
                },
                .state => {
                    writer.print("state: .{s}\n", .{@tagName(p.state)}) catch {};
                },
                .indent => {
                    writer.print("indent.size: {d}\n", .{p.indent.size}) catch {};
                    writer.print("indent.level: {d}\n", .{p.indent.level}) catch {};
                    writer.print("indent.trim_size: {d}\n", .{p.indent.trim_size}) catch {};
                },
                .pending_nodes => {
                    writer.print("pending_nodes:\n", .{}) catch {};
                    var i: usize = p.pending_nodes.items.len;
                    while (i > 0) {
                        i -= 1;
                        const node = p.pending_nodes.items[i];
                        writer.print("  .{s} '{s}'\n", .{
                            @tagName(node.tag),
                            slice.first([]const u8, node.token.sliceFrom(p.tokenizer.input), 10),
                        }) catch {};
                    }
                },
                .parsed_nodes => {
                    writer.print("parsed_nodes:\n", .{}) catch {};
                    var i: usize = p.parsed_nodes.items.len;
                    while (i > 0) {
                        i -= 1;
                        const node = p.parsed_nodes.items[i];
                        writer.print("  .{s} '{s}'\n", .{
                            @tagName(node.tag),
                            slice.first([]const u8, node.token.sliceFrom(p.tokenizer.input), 10),
                        }) catch {};
                    }
                },
                .cursor => {
                    line.printWithCursor(writer, p.tokenizer.input, .{
                        .index = p.token.loc.start,
                        .range = @max(p.token.len(), 1),
                        .line_num = p.tokenizer.loc.line_number,
                    }, .{ .around = 15 }, .{}) catch {};
                },
                .all => {
                    log(p, writer, .token, false);
                    log(p, writer, .state, false);
                    log(p, writer, .indent, false);
                    log(p, writer, .pending_nodes, false);
                    log(p, writer, .parsed_nodes, false);
                    log(p, writer, .cursor, false);
                },
            }
            if (extra_nl) writer.print("\n", .{}) catch {};
        }
    };
}

test Parser {
    const alloc = std.heap.c_allocator;
    defer logger.flush() catch {};
    {
        const input =
            \\ 1 + 2 * 3
        ;
        var p = Parser(.{}).init(alloc, input);
        const node = try p.parse();
        if (node) |n| {
            try t.expectEqualStrings(
                \\.op_arith_add '+'
                \\  .literal_number '1'
                \\  .op_arith_mul '*'
                \\    .literal_number '2'
                \\    .literal_number '3'
                \\
            , try n.dumpTreeString(alloc, input));
        } else return error.UnexpectedNull;
    }
    {
        const input =
            \\ 1, 2, 3
        ;
        var p = Parser(.{ .log = true }).init(alloc, input);
        errdefer p.log(logger.writer(), .cursor, true);
        const node = try p.parse();
        if (node) |n| {
            try t.expectEqualStrings(
                \\.list_and ','
                \\  .literal_number '1'
                \\  .literal_number '2'
                \\  .literal_number '3'
                \\
            , try n.dumpTreeString(alloc, input));
        } else return error.UnexpectedNull;
    }
}
