// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

const std = @import("std");
const ThisFile = @This();
pub const List = std.ArrayListUnmanaged;
pub const Map = std.StringHashMapUnmanaged;
var log = @import("utils/log.zig").Scope(.parser, .{}){};
const t = std.testing;

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
        op_enum_and,
        op_enum_or,

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

                .op_enum_and,
                .op_enum_or,
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
            table[@intFromEnum(Tag.op_arith_add)] = 1;
            table[@intFromEnum(Tag.op_arith_sub)] = 1;
            table[@intFromEnum(Tag.op_arith_mul)] = 2;
            table[@intFromEnum(Tag.op_arith_div)] = 2;
            table[@intFromEnum(Tag.op_arith_exp)] = 3;
            table[@intFromEnum(Tag.op_arith_neg)] = 7;
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
    };

    pub fn init(alloc: std.mem.Allocator, tag: Tag, token: Token) !*Node {
        const node = try alloc.create(Node);
        node.tag = tag;
        node.token = token;
        return node;
    }

    pub fn debug(node: *const Node, writer: anytype, input: []const u8, lvl: usize) !void {
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
                try node.data.pair.left.debug(writer, input, lvl +| 1);
                try node.data.pair.right.debug(writer, input, lvl +| 1);
            },
            .list => {
                for (node.data.list.items) |item| {
                    try item.debug(writer, input, lvl +| 1);
                }
            },
            else => unreachable,
        }
    }

    pub fn debugString(node: *const Node, alloc: std.mem.Allocator, input: []const u8) ![]u8 {
        var str = std.ArrayListUnmanaged(u8){};
        try node.debug(str.writer(alloc), input, 0);
        return try str.toOwnedSlice(alloc);
    }
};

const Token = @import("tokenizer.zig").Token;
const Tokenizer = @import("tokenizer.zig").Tokenizer(.{
    .tokenize_spaces = false,
    .tokenize_indents = true,
});

pub const Error = error{
    OutOfMemory,
    InvalidToken,
    UnalignedIndentSize,
    IndentationTooDeep,
    UnexpectedToken,
};

pub const Parser = struct {
    alloc: std.mem.Allocator,
    tokenizer: Tokenizer,
    token: Token = undefined,
    indent: Indent = .{},
    pending_nodes: List(*Node) = .{},
    parsed_nodes: List(*Node) = .{},
    state: enum {
        parse_prime,
        parse_post_prime,
    } = .parse_prime,

    pub const Indent = struct {
        trim_size: usize = 0,
        size: usize = 0,
        level: usize = 0,
    };

    pub fn parse(p: *Parser) Error!?*Node {
        p.token = p.tokenizer.nextFrom(.space);
        while (true) {
            switch (p.state) {
                .parse_prime => {
                    switch (p.token.tag) {
                        .space => { // can run only once
                            p.indent.trim_size = 1;
                        },
                        .number => {
                            const n = try Node.init(p.alloc, .literal_number, p.token);
                            try p.parsed_nodes.append(p.alloc, n);
                            p.state = .parse_post_prime;
                        },
                        .eof => break,
                        else => return error.UnexpectedToken,
                    }
                },

                // operators
                .parse_post_prime => {
                    switch (p.token.tag) {
                        inline .minus, .plus, .asterisk, .slash => |tok_tag| {
                            const node_tag = Node.Tag.fromTokenTag(tok_tag);
                            // resolve
                            for (p.pending_nodes.items) |pending| {
                                if (pending.tag.precedence() >= node_tag.precedence() or
                                    pending.tag.isRightAssociative())
                                {
                                    // resolve
                                }
                            }
                            const node = try Node.init(p.alloc, node_tag, p.token);
                            try p.pending_nodes.append(p.alloc, node);
                            p.state = .parse_prime;
                        },
                        .eof => break,
                        else => unreachable,
                    }
                },
            }
            p.token = p.tokenizer.next();
        }
        while (p.pending_nodes.pop()) |pending| {
            switch (pending.tag) {
                .op_arith_add, .op_arith_mul => {
                    pending.data.pair.right = p.parsed_nodes.pop().?;
                    pending.data.pair.left = p.parsed_nodes.pop().?;
                    try p.parsed_nodes.append(p.alloc, pending);
                },
                else => unreachable,
            }
        }
        // p.logSelf(.pending_nodes, false);
        // p.logSelf(.parsed_nodes, false);
        return p.parsed_nodes.pop();
    }

    pub fn logSelf(
        p: *Parser,
        comptime lvl: enum { all, indent, pending_nodes, parsed_nodes, token },
        comptime extra_nl: bool,
    ) void {
        if (lvl == .all or lvl == .token) {
            log.print("token.tag: {s}\n", .{@tagName(p.token.tag)}) catch {};
        }
        if (lvl == .all or lvl == .indent) {
            log.print("indent.size: {d}\n", .{p.indent.size}) catch {};
            log.print("indent.level: {d}\n", .{p.indent.level}) catch {};
            log.print("indent.trim_size: {d}\n", .{p.indent.trim_size}) catch {};
        }
        if (lvl == .all or lvl == .pending_nodes) {
            log.print("pending_nodes:\n", .{}) catch {};
            var i: usize = p.pending_nodes.items.len;
            while (i > 0) {
                i -= 1;
                const token = p.pending_nodes.items[i];
                log.print("  .{s}\n", .{@tagName(token.tag)}) catch {};
            }
        }
        if (lvl == .all or lvl == .parsed_nodes) {
            log.print("parsed_nodes:\n", .{}) catch {};
            var i: usize = p.parsed_nodes.items.len;
            while (i > 0) {
                i -= 1;
                const node = p.parsed_nodes.items[i];
                log.print("  .{s}\n", .{@tagName(node.tag)}) catch {};
            }
        }
        if (extra_nl) log.print("\n", .{}) catch {};
        log.flush() catch {};
    }
};

test Parser {
    const input =
        \\ 1 + 2 * 3
    ;

    var p = Parser{
        .tokenizer = .init(input),
        .alloc = std.heap.c_allocator,
    };

    const node = try p.parse();

    if (node) |n| {
        try t.expectEqualStrings(
            \\.op_arith_add '+'
            \\  .literal_number '1'
            \\  .op_arith_mul '*'
            \\    .literal_number '2'
            \\    .literal_number '3'
            \\
        , try n.debugString(std.heap.c_allocator, input));
    }
}
