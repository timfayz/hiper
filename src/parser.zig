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
const stack = @import("utils/stack.zig");
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
    token: ?Token,
    data: Data,

    pub const Data = union {
        void: void,
        single: *Node,
        pair: struct { left: *Node, right: *Node },
        list: List(*Node),

        pub const Tag = enum { void, single, pair, list };
    };

    pub const Tag = enum {
        root,

        // primitives
        literal_number,
        literal_string,
        literal_identifier,

        // aggregation
        list_and,
        list_or,
        parens,

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
                .parens,
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

                .root,
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
            table[@intFromEnum(Tag.parens)] = 0;
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
                (left.precedence() == right.precedence() and !left.isRightAssociative());
        }
    };

    pub fn init(alloc: std.mem.Allocator, comptime tag: Tag, token: ?Token) !*Node {
        const node = try alloc.create(Node);
        node.tag = tag;
        node.token = token;
        node.data = @unionInit(Data, @tagName(tag.dataTag()), undefined);
        return node;
    }

    pub fn tokenString(node: *const Node, input: []const u8) []const u8 {
        if (node.token) |tok| {
            const str = tok.sliceFrom(input);
            return if (str.len > 10) str[0..10] else str;
        }
        return "?";
    }

    pub fn dumpTree(node: *const Node, writer: anytype, input: []const u8, lvl: usize) !void {
        try writer.writeByteNTimes(' ', lvl * 2);
        try writer.print(".{s} '{s}'\n", .{ @tagName(node.tag), node.tokenString(input) });
        if (lvl > 16) return;
        switch (node.tag.dataTag()) {
            .void => {},
            .single => {
                try node.data.single.dumpTree(writer, input, lvl +| 1);
            },
            .pair => {
                try node.data.pair.left.dumpTree(writer, input, lvl +| 1);
                try node.data.pair.right.dumpTree(writer, input, lvl +| 1);
            },
            .list => {
                for (node.data.list.items) |item| {
                    try item.dumpTree(writer, input, lvl +| 1);
                }
            },
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
    UnalignedIndent,
    IndentationTooDeep,
    UnexpectedToken,
    UnmatchedBracket,
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
        unparsed: List(*Node) = .{},
        parsed: List(*Node) = .{},
        inline_scope: bool = false,
        pending_states: stack.Stack(State, 32) = .{},
        state: State = .parse_prime,

        const Self = @This();

        pub const State = enum {
            parse_prime,
            parse_post_prime,

            parse_post_left_paren,
            parse_end_right_paren,

            phony,
            parse_end,
        };

        pub const Indent = struct {
            trim_size: usize = 0,
            size: usize = 0,
            level: usize = 0,

            fn getLevel(self: *Indent, curr_size: usize) !usize {
                if (curr_size == self.trim_size) return 0;
                if (curr_size < self.trim_size) return error.UnalignedIndent;

                if (self.size == 0 and curr_size > 0) { // init indent
                    self.size = curr_size;
                    return 1;
                }

                const size = curr_size - self.trim_size;
                if (size % self.size != 0) return error.UnalignedIndent;
                return size / self.size;
            }
        };

        pub fn init(alloc: std.mem.Allocator, input: [:0]const u8) Self {
            return .{ .tokenizer = .init(input), .alloc = alloc };
        }

        pub fn initTrimSize(p: *Self) void {
            p.token = p.tokenizer.nextFrom(.space);
            switch (p.token.tag) {
                .space => {
                    p.indent.trim_size = p.token.len();
                    p.token = p.tokenizer.next();
                },
                else => {},
            }
        }

        pub fn parse(p: *Self) Error!?*Node {
            p.initTrimSize();
            try p.pending_states.push(.parse_end);
            while (true) {
                p.log(logger.writer(), .token, false);
                p.log(logger.writer(), .unparsed, false);
                p.log(logger.writer(), .parsed, false);
                p.log(logger.writer(), .pending_states, false);
                p.log(logger.writer(), .state, true);
                switch (p.state) {
                    // empty | a.. | if.. | true.. | (..
                    .parse_prime => {
                        switch (p.token.tag) {
                            .number => {
                                try p.parsed.append(p.alloc, try Node.init(p.alloc, .literal_number, p.token));
                                p.token = p.tokenizer.next();
                                p.state = .parse_post_prime;
                            },
                            .left_paren => {
                                try p.unparsed.append(p.alloc, try Node.init(p.alloc, .parens, p.token));
                                p.token = p.tokenizer.next();
                                p.state = .parse_post_left_paren;
                            },
                            else => {
                                p.state = p.pending_states.pop();
                            },
                        }
                    },

                    .parse_post_left_paren => {
                        if (p.token.tag == .indent) {
                            const curr_lvl = try p.indent.getLevel(p.token.len());
                            if (curr_lvl != p.indent.level + 1) {
                                return error.UnalignedIndent;
                            }
                            p.token = p.tokenizer.next();
                            // inline = false
                        }
                        try p.pending_states.push(.parse_end_right_paren);
                        p.state = .parse_prime;
                    },
                    .parse_end_right_paren => {
                        if (p.token.tag != .right_paren) {
                            return error.UnmatchedBracket;
                        }
                        try p.resolveAllUnparsedUntilInc(.parens);
                        p.token = p.tokenizer.next();
                        p.state = .parse_post_prime;
                    },

                    // a+.. | a,..
                    .parse_post_prime => {
                        switch (p.token.tag) {
                            inline .minus,
                            .plus,
                            .asterisk,
                            .slash,
                            .comma,
                            .pipe,
                            => |tag| {
                                const node_tag = switch (tag) {
                                    .minus => .op_arith_sub,
                                    .plus => .op_arith_add,
                                    .asterisk => .op_arith_mul,
                                    .slash => .op_arith_div,
                                    .caret => .op_arith_exp,
                                    .comma => .list_and,
                                    .pipe => .list_or,
                                    else => unreachable,
                                };
                                try p.resolveAllUnparsedWhileHigherPre(node_tag);
                                try p.unparsed.append(p.alloc, try Node.init(p.alloc, node_tag, p.token));
                                p.token = p.tokenizer.next();
                                p.state = .parse_prime;
                            },
                            .indent => {
                                if (try p.indent.getLevel(p.token.len()) == 0) {
                                    try p.resolveAllUnparsed();
                                    p.token = p.tokenizer.next();
                                    p.state = .parse_prime;
                                } else {
                                    p.state = p.pending_states.pop();
                                }
                            },
                            else => {
                                p.state = p.pending_states.pop();
                            },
                        }
                    },

                    .parse_end => {
                        switch (p.token.tag) {
                            .eof => {
                                try p.resolveAllUnparsed();
                                break;
                            },
                            else => return error.UnexpectedToken,
                        }
                    },

                    else => unreachable,
                }
            }
            p.log(logger.writer(), .all, true);

            return p.root();
        }

        pub fn root(p: *Self) !*Node {
            const node = try Node.init(p.alloc, .root, null);
            node.data.list = p.parsed;
            return node;
        }

        pub fn resolveAllUnparsedWhileHigherPre(p: *Self, tag: Node.Tag) !void {
            while (p.unparsed.getLastOrNull()) |last| {
                if (last.tag.isHigherPrecedenceThan(tag)) {
                    try p.resolveUnparsed(last);
                    _ = p.unparsed.pop();
                } else break;
            }
        }

        pub fn resolveAllUnparsedUntilInc(p: *Self, tag: Node.Tag) !void {
            while (p.unparsed.pop()) |n| {
                try p.resolveUnparsed(n);
                if (n.tag == tag) break;
            }
        }

        pub fn resolveAllUnparsed(p: *Self) !void {
            while (p.unparsed.pop()) |n|
                try p.resolveUnparsed(n);
        }

        pub fn resolveUnparsed(p: *Self, node: *Node) !void {
            switch (node.tag) {
                .op_arith_add,
                .op_arith_mul,
                => {
                    node.data.pair.right = p.parsed.pop().?;
                    node.data.pair.left = p.parsed.pop().?;
                    try p.parsed.append(p.alloc, node);
                },
                inline .list_and,
                .list_or,
                => |tag| {
                    const tail = p.parsed.pop().?;
                    const head = p.parsed.getLast();
                    if (head.tag == tag) { // continue pushing
                        try head.data.list.append(p.alloc, tail);
                    } else {
                        try node.data.list.append(p.alloc, p.parsed.pop().?); // head
                        try node.data.list.append(p.alloc, tail);
                        try p.parsed.append(p.alloc, node);
                    }
                },
                .parens => {
                    node.data.single = p.parsed.pop().?;
                    try p.parsed.append(p.alloc, node);
                },
                else => unreachable,
            }
        }

        pub fn parseInput(alloc: std.mem.Allocator, input: [:0]const u8) Error!?*Node {
            var p = Self.init(alloc, input);
            return p.parse();
        }

        pub fn log(
            p: *const Self,
            writer: anytype,
            comptime part: enum {
                all,
                indent,
                unparsed,
                parsed,
                token,
                state,
                pending_states,
                cursor,
            },
            comptime extra_nl: bool,
        ) void {
            if (!opt.log) return;
            switch (part) {
                .token => {
                    writer.print("token: .{s} '{s}'\n", .{
                        @tagName(p.token.tag),
                        slice.first([]const u8, p.token.sliceFrom(p.tokenizer.input), 10),
                    }) catch {};
                },
                .state => {
                    writer.print("state: .{s}\n", .{@tagName(p.state)}) catch {};
                },
                .indent => {
                    writer.print("indent.size: {d}\n", .{p.indent.size}) catch {};
                    writer.print("indent.level: {d}\n", .{p.indent.level}) catch {};
                    writer.print("indent.trim_size: {d}\n", .{p.indent.trim_size}) catch {};
                },
                .unparsed => {
                    writer.print("unparsed:\n", .{}) catch {};
                    var i: usize = p.unparsed.items.len;
                    while (i > 0) {
                        i -= 1;
                        const node = p.unparsed.items[i];
                        writer.print("  .{s} '{s}'\n", .{
                            @tagName(node.tag),
                            node.tokenString(p.tokenizer.input),
                        }) catch {};
                    }
                },
                .parsed => {
                    writer.print("parsed:\n", .{}) catch {};
                    var i: usize = p.parsed.items.len;
                    while (i > 0) {
                        i -= 1;
                        const node = p.parsed.items[i];
                        writer.print("  .{s} '{s}'\n", .{
                            @tagName(node.tag),
                            node.tokenString(p.tokenizer.input),
                        }) catch {};
                    }
                },
                .pending_states => {
                    writer.print("pending_states:\n", .{}) catch {};
                    var i: usize = p.pending_states.constSlice().len;
                    if (i == 0) {
                        writer.print("  (empty)\n", .{}) catch {};
                    } else while (i > 0) {
                        i -= 1;
                        const state = p.pending_states.arr[i];
                        writer.print("  .{s}\n", .{@tagName(state)}) catch {};
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
                    log(p, writer, .indent, false);
                    log(p, writer, .unparsed, false);
                    log(p, writer, .parsed, false);
                    log(p, writer, .pending_states, false);
                    log(p, writer, .state, false);
                    log(p, writer, .cursor, false);
                },
            }
            if (extra_nl) writer.print("---\n", .{}) catch {};
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
                \\.root '?'
                \\  .op_arith_add '+'
                \\    .literal_number '1'
                \\    .op_arith_mul '*'
                \\      .literal_number '2'
                \\      .literal_number '3'
                \\
            , try n.dumpTreeString(alloc, input));
        } else return error.UnexpectedNull;
    }
    {
        const input =
            \\ 1, 2, 3
            \\ 4
            \\ 5
        ;
        var p = Parser(.{}).init(alloc, input);
        const node = try p.parse();
        if (node) |n| {
            try t.expectEqualStrings(
                \\.root '?'
                \\  .list_and ','
                \\    .literal_number '1'
                \\    .literal_number '2'
                \\    .literal_number '3'
                \\  .literal_number '4'
                \\  .literal_number '5'
                \\
            , try n.dumpTreeString(alloc, input));
        } else return error.UnexpectedNull;
    }
    {
        const input =
            \\ ((1 + 2) * 3)
            \\ 4
        ;
        var p = Parser(.{ .log = true }).init(alloc, input);
        const node = try p.parse();
        if (node) |n| {
            try t.expectEqualStrings(
                \\.root '?'
                \\
            , try n.dumpTreeString(alloc, input));
        } else return error.UnexpectedNull;
    }
}
