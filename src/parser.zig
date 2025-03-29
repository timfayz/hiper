// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

//! Public API:
//! - Node
//! - Error
//! - ParserOptions
//! - Parser

const std = @import("std");
const ThisFile = @This();
const slice = @import("utils/slice.zig");
const line = @import("utils/line.zig");
const stack = @import("utils/stack.zig");
pub const List = std.ArrayListUnmanaged;
pub const Map = std.StringHashMapUnmanaged;
pub const Allocator = std.mem.Allocator;
pub const Token = @import("tokenizer.zig").Token;
pub const Tokenizer = @import("tokenizer.zig").Tokenizer(.{
    .tokenize_spaces = false,
    .tokenize_indents = true,
});
pub var logger = @import("utils/log.zig").Scope(.parser, .{}){};

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
        // primitives
        literal_number,
        literal_string,
        literal_identifier,

        // enumeration
        inline_enum_and,
        inline_enum_or,
        block_enum_and,
        block_enum_or,

        // grouping
        parens,
        square,

        // arithmetics
        op_arith_add,
        op_arith_sub,
        op_arith_mul,
        op_arith_div,
        op_arith_exp,
        op_arith_neg,

        // abstraction
        name_def,
        name_ref,

        block_assign,
        inline_assign,

        // control
        ctrl_for,
        ctrl_while,
        ctrl_if,

        pub fn dataTag(tag: Tag) Data.Tag {
            return switch (tag) {
                .parens,
                .square,
                .op_arith_neg,
                .block_assign,
                => .single,

                .op_arith_add,
                .op_arith_sub,
                .op_arith_mul,
                .op_arith_div,
                .op_arith_exp,
                => .pair,

                .block_enum_and,
                .block_enum_or,
                .inline_enum_and,
                .inline_enum_or,

                .name_def,
                .name_ref,
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
            table[@intFromEnum(Tag.block_enum_and)] = 1;
            table[@intFromEnum(Tag.block_enum_or)] = 2;
            table[@intFromEnum(Tag.inline_enum_and)] = 3;
            table[@intFromEnum(Tag.inline_enum_or)] = 4;
            table[@intFromEnum(Tag.op_arith_add)] = 5;
            table[@intFromEnum(Tag.op_arith_sub)] = 5;
            table[@intFromEnum(Tag.op_arith_mul)] = 6;
            table[@intFromEnum(Tag.op_arith_div)] = 6;
            table[@intFromEnum(Tag.op_arith_exp)] = 7;
            table[@intFromEnum(Tag.op_arith_neg)] = 7;
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

    pub fn init(alloc: Allocator, comptime tag: Tag, token: ?Token) !*Node {
        const node = try alloc.create(Node);
        node.tag = tag;
        node.token = token;
        node.data = @unionInit(Data, @tagName(tag.dataTag()), undefined);
        return node;
    }

    pub fn get(node: *const Node, comptime field: enum { val }) ?*Node {
        switch (node.tag) {
            .name_def => {
                const items = node.data.list.items;
                switch (field) {
                    .val => {
                        return switch (items.len) {
                            0 => null,
                            1 => items[0].data.single,
                            2 => items[1].data.single,
                            else => unreachable,
                        };
                    },
                }
            },
            else => unreachable,
        }
    }

    pub fn tokenString(node: *const Node, input: []const u8) []const u8 {
        if (node.token) |tok| {
            const str = tok.sliceFrom(input);
            return if (str.len > 10) str[0..10] else str;
        }
        return "?";
    }

    pub fn dump(node: *const Node, writer: anytype, input: []const u8) !void {
        try writer.print(".{s} '{s}'\n", .{ @tagName(node.tag), node.tokenString(input) });
    }

    pub fn dumpRec(node: *const Node, writer: anytype, input: []const u8, lvl: usize) !void {
        try writer.writeByteNTimes(' ', lvl * 2);
        try node.dump(writer, input);
        if (lvl > 16) return;
        switch (node.tag.dataTag()) {
            .void => {},
            .single => {
                try node.data.single.dumpRec(writer, input, lvl +| 1);
            },
            .pair => {
                try node.data.pair.left.dumpRec(writer, input, lvl +| 1);
                try node.data.pair.right.dumpRec(writer, input, lvl +| 1);
            },
            .list => {
                for (node.data.list.items) |item| {
                    try item.dumpRec(writer, input, lvl +| 1);
                }
            },
        }
    }

    pub fn dumpRecString(node: *const Node, alloc: Allocator, input: []const u8) ![]u8 {
        var str = std.ArrayListUnmanaged(u8){};
        try node.dumpRec(str.writer(alloc), input, 0);
        return try str.toOwnedSlice(alloc);
    }
};

pub const Error = error{
    OutOfMemory,
    UnalignedIndent,
    UnexpectedToken,
    UnmatchedBracket,
};

pub const ParserOptions = struct {
    log: bool = false,
};

pub fn Parser(opt: ParserOptions) type {
    return struct {
        alloc: Allocator,
        tokenizer: Tokenizer,
        token: Token = undefined,
        indent: Indent = .{},
        pending: Pending = .{},
        state: State = .expr,

        const Self = @This();

        pub const State = enum {
            expr,
            operator,

            paren_post_open,
            paren_end,
            paren_end_post_indent,

            name_post_dot,
            name_post_dot_id,
            name_post_square_open,
            name_end_square,
            name_end_assign,

            end,
        };

        pub const Indent = struct {
            trim_size: usize = 0,
            size: usize = 0,
            curr_level: usize = 0,

            fn levelOf(indent: *Indent, indent_size: usize) !usize {
                if (indent_size == indent.trim_size) return 0;
                if (indent_size < indent.trim_size) return error.UnalignedIndent;

                if (indent.size == 0 and indent_size > 0) { // init indent
                    indent.size = indent_size - indent.trim_size;
                    return 1;
                }

                const size = indent_size - indent.trim_size;
                if (size % indent.size != 0) return error.UnalignedIndent;
                return size / indent.size;
            }

            fn isEqual(indent: *Indent, indent_size: usize) !bool {
                return try indent.levelOf(indent_size) == indent.curr_level;
            }

            fn isIncreased(indent: *Indent, indent_size: usize) !bool {
                return try indent.levelOf(indent_size) == indent.curr_level + 1;
            }

            fn isDecreased(indent: *Indent, indent_size: usize) !bool {
                return try indent.levelOf(indent_size) < indent.curr_level;
            }
        };

        pub const Pending = struct {
            operators: List(*Node) = .{},
            operands: List(*Node) = .{},
            states: stack.Stack(State, 64) = .{},

            fn pushState(p: *Pending, state: State) !void {
                try p.states.push(state);
            }

            fn pushOperand(p: *Pending, alloc: Allocator, comptime node_tag: Node.Tag, token: ?Token) !void {
                try p.operands.append(alloc, try Node.init(alloc, node_tag, token));
            }

            fn pushOperator(p: *Pending, alloc: Allocator, comptime node_tag: Node.Tag, token: ?Token) !void {
                try p.operators.append(alloc, try Node.init(alloc, node_tag, token));
            }

            fn popOperandAppendToLast(p: *Pending, alloc: Allocator) !void {
                const operand = p.operands.pop().?;
                const last = p.operands.getLast();
                try last.data.list.append(alloc, operand);
            }

            fn reduceWhileHigherPre(p: *Pending, alloc: Allocator, tag: Node.Tag) !void {
                while (p.operators.getLastOrNull()) |last| {
                    if (last.tag.isHigherPrecedenceThan(tag)) {
                        try p.reduceOperator(alloc, last);
                        _ = p.operators.pop();
                    } else break;
                }
            }

            fn reduceUntilInc(p: *Pending, alloc: Allocator, tag: Node.Tag) !void {
                while (p.operators.pop()) |n| {
                    try p.reduceOperator(alloc, n);
                    if (n.tag == tag) break;
                }
            }

            fn reduceAll(p: *Pending, alloc: Allocator) !void {
                while (p.operators.pop()) |n|
                    try p.reduceOperator(alloc, n);
            }

            fn reduceOperator(p: *Pending, alloc: Allocator, op: *Node) !void {
                switch (op.tag.dataTag()) {
                    .pair => {
                        op.data.pair.right = p.operands.pop().?;
                        op.data.pair.left = p.operands.pop().?;
                        try p.operands.append(alloc, op);
                    },
                    .list => {
                        const tail = p.operands.pop().?;
                        const head = p.operands.getLast();
                        if (head.tag == op.tag) { // continue pushing to operand
                            try head.data.list.append(alloc, tail);
                        } else { // move operator to operand
                            try op.data.list.append(alloc, p.operands.pop().?); // head
                            try op.data.list.append(alloc, tail);
                            try p.operands.append(alloc, op);
                        }
                    },
                    .single => {
                        op.data.single = p.operands.pop().?;
                        try p.operands.append(alloc, op);
                    },
                    .void => unreachable,
                }
            }
        };

        pub fn init(alloc: Allocator, input: [:0]const u8) Self {
            return .{ .tokenizer = .init(input), .alloc = alloc };
        }

        pub fn initTrimSize(p: *Self) void {
            p.token = p.tokenizer.nextFrom(.space);
            switch (p.token.tag) {
                .space, .indent => {
                    p.indent.trim_size = p.token.len();
                    p.advance();
                },
                else => {},
            }
        }

        fn assert(p: *Self, token_tag: Token.Tag, err: Error) Error!void {
            if (p.token.tag != token_tag)
                return err;
        }

        fn assertIndentIncreased(p: *Self) Error!void {
            if (!try p.indent.isIncreased(p.token.len()))
                return error.UnalignedIndent;
        }

        fn updateIndent(p: *Self) Error!void {
            p.indent.curr_level = try p.indent.levelOf(p.token.len());
        }

        fn jump(p: *Self, state: State) void {
            p.state = state;
        }

        fn jumpPending(p: *Self) void {
            p.state = p.pending.states.pop();
        }

        fn advance(p: *Self) void {
            p.token = p.tokenizer.next();
        }

        fn advanceAndJump(p: *Self, state: State) void {
            p.token = p.tokenizer.next();
            p.state = state;
        }

        pub fn parse(p: *Self) Error!?*Node {
            p.initTrimSize();
            try p.pending.pushState(.end);
            while (true) {
                p.log(logger.writer(), .token, false);
                p.log(logger.writer(), .pending_operators, false);
                p.log(logger.writer(), .pending_operands, false);
                p.log(logger.writer(), .pending_states, false);
                p.log(logger.writer(), .state, true);
                switch (p.state) {
                    // ----------------
                    // .expr
                    // ----------------
                    .expr => {
                        switch (p.token.tag) {
                            .number => {
                                try p.pending.pushOperand(p.alloc, .literal_number, p.token);
                                p.advanceAndJump(.operator);
                            },
                            .identifier => {
                                try p.pending.pushOperand(p.alloc, .literal_identifier, p.token);
                                p.advanceAndJump(.operator);
                            },
                            .string => {
                                try p.pending.pushOperand(p.alloc, .literal_string, p.token);
                                p.advanceAndJump(.operator);
                            },
                            .paren_open => {
                                try p.pending.pushOperator(p.alloc, .parens, p.token);
                                p.advanceAndJump(.paren_post_open);
                            },
                            .dot => {
                                p.advanceAndJump(.name_post_dot);
                            },
                            else => {
                                return error.UnexpectedToken;
                                // p.jumpPending();
                            },
                        }
                    },

                    // ----------------
                    // .operator
                    // ----------------
                    .operator => {
                        switch (p.token.tag) {
                            inline .minus,
                            .plus,
                            .asterisk,
                            .slash,
                            .caret,
                            .comma,
                            .pipe,
                            => |tag| {
                                const node_tag = switch (tag) {
                                    .minus => .op_arith_sub,
                                    .plus => .op_arith_add,
                                    .asterisk => .op_arith_mul,
                                    .slash => .op_arith_div,
                                    .caret => .op_arith_exp,
                                    .comma => .inline_enum_and,
                                    .pipe => .inline_enum_or,
                                    else => unreachable,
                                };
                                try p.pending.reduceWhileHigherPre(p.alloc, node_tag);
                                try p.pending.pushOperator(p.alloc, node_tag, p.token);
                                p.advanceAndJump(.expr);
                            },
                            .indent => {
                                if (try p.indent.isEqual(p.token.len())) {
                                    try p.pending.reduceWhileHigherPre(p.alloc, .block_enum_and);
                                    try p.pending.pushOperator(p.alloc, .block_enum_and, p.token);
                                    p.advanceAndJump(.expr);
                                } else {
                                    p.jumpPending();
                                }
                            },
                            else => {
                                p.jumpPending();
                            },
                        }
                    },

                    // ----------------
                    // .name
                    // ----------------
                    .name_post_dot => {
                        try p.assert(.identifier, error.UnexpectedToken);
                        try p.pending.pushOperand(p.alloc, .name_def, p.token);
                        p.advanceAndJump(.name_post_dot_id);
                    },
                    .name_post_dot_id => {
                        switch (p.token.tag) {
                            .indent => {
                                // block assign
                                if (try p.indent.isIncreased(p.token.len())) {
                                    p.indent.curr_level += 1;
                                    try p.pending.pushOperator(p.alloc, .block_assign, p.token);
                                    try p.pending.pushState(.name_end_assign);
                                    p.advanceAndJump(.expr);
                                } else {
                                    p.jump(.operator);
                                }
                            },
                            .equal => { // inline assign

                            },
                            .square_open => { // attributes
                                try p.pending.pushOperator(p.alloc, .square, p.token);
                                p.advanceAndJump(.name_post_square_open);
                            },
                            .empty_square => { // empty attributes
                                p.advanceAndJump(.operator);
                            },
                            else => {
                                p.jump(.operator);
                            },
                        }
                    },

                    // .name [..]
                    .name_post_square_open => {
                        if (p.token.tag == .indent) {
                            if (try p.indent.isIncreased(p.token.len())) {
                                p.advance();
                            } // else jump below
                        } else {
                            // TODO inline
                        }
                        try p.pending.pushState(.name_end_square);
                        p.jump(.expr);
                    },
                    .name_end_square => {
                        try p.assert(.square_close, error.UnmatchedBracket);
                        try p.pending.reduceUntilInc(p.alloc, .square);
                        try p.pending.popOperandAppendToLast(p.alloc); // merge
                        p.advanceAndJump(.name_post_dot_id);
                    },

                    // .name = ..;
                    .name_end_assign => {
                        // TODO assert indent or ;
                        try p.pending.reduceUntilInc(p.alloc, .block_assign);
                        try p.pending.popOperandAppendToLast(p.alloc);
                        switch (p.token.tag) {
                            .indent => {
                                const indent_lvl = try p.indent.levelOf(p.token.len());
                                if (p.indent.curr_level - indent_lvl > 1) // exit
                                    return error.UnalignedIndent;
                                p.indent.curr_level -= 1;
                                // enumerate next element
                                try p.pending.pushOperator(p.alloc, .block_enum_and, p.token);
                                p.advanceAndJump(.expr);
                            },
                            else => {
                                p.jumpPending();
                            },
                        }
                    },

                    // ----------------
                    // .paren
                    // ----------------
                    .paren_post_open => {
                        if (p.token.tag == .indent) {
                            try p.updateIndent();
                            p.advance();
                        }
                        try p.pending.pushState(.paren_end);
                        p.jump(.expr);
                    },
                    .paren_end => {
                        if (p.token.tag == .indent) {
                            try p.updateIndent();
                            p.advanceAndJump(.paren_end);
                        } else {
                            try p.assert(.paren_close, error.UnmatchedBracket);
                            try p.pending.reduceUntilInc(p.alloc, .parens);
                            p.advanceAndJump(.operator);
                        }
                    },

                    .end => {
                        try p.assert(.eof, error.UnexpectedToken);
                        try p.pending.reduceAll(p.alloc);
                        break;
                    },

                    else => unreachable,
                }
            }
            p.log(logger.writer(), .all, true);

            return p.pending.operands.pop();
        }

        pub fn parseInput(alloc: Allocator, input: [:0]const u8) Error!?*Node {
            var p = Self.init(alloc, input);
            return p.parse();
        }

        pub fn log(
            p: *const Self,
            writer: anytype,
            comptime part: enum {
                all,
                indent,
                token,
                state,
                pending_states,
                pending_operators,
                pending_operands,
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
                    writer.print("indent.level: {d}\n", .{p.indent.curr_level}) catch {};
                    writer.print("indent.trim_size: {d}\n", .{p.indent.trim_size}) catch {};
                },
                .pending_operands,
                .pending_operators,
                => |tag| {
                    writer.print(@tagName(tag) ++ ":\n", .{}) catch {};
                    const src = switch (tag) {
                        .pending_operands => p.pending.operands,
                        .pending_operators => p.pending.operators,
                        else => unreachable,
                    };
                    var i: usize = src.items.len;
                    while (i > 0) {
                        i -= 1;
                        const node = src.items[i];
                        writer.writeByteNTimes(' ', 2) catch {};
                        node.dump(writer, p.tokenizer.input) catch {};
                    }
                },
                .pending_states => |tag| {
                    writer.print(@tagName(tag) ++ ":\n", .{}) catch {};
                    var i: usize = p.pending.states.constSlice().len;
                    while (i > 0) {
                        i -= 1;
                        const state = p.pending.states.arr[i];
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
                    log(p, writer, .pending_operators, false);
                    log(p, writer, .pending_operands, false);
                    log(p, writer, .pending_states, false);
                    log(p, writer, .state, false);
                    log(p, writer, .cursor, false);
                },
            }
            if (extra_nl) writer.print("---\n", .{}) catch {};
        }
    };
}
