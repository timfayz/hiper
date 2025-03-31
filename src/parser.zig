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
    next: List(*Node) = .{},

    pub const Tag = enum {
        // primitives
        literal_number,
        literal_string,
        literal_identifier,

        // enumeration
        inline_enum_and,
        inline_enum_or,

        // grouping
        scope,

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
        name_attr,

        name_val,
        inline_assign,

        // control
        ctrl_for,
        ctrl_while,
        ctrl_if,

        const precedence_table = blk: {
            const tags_len = std.meta.fields(Tag).len;
            var table = [1]std.meta.Tag(Tag){0} ** tags_len; // 0 for all, except:
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
        node.next = .{};
        return node;
    }

    pub fn get(node: *const Node, comptime field: enum { val }) ?*Node {
        const children = node.list.items;
        switch (field) {
            .val => return switch (node.tag) {
                .name_def => switch (children.len) {
                    0 => null,
                    1 => children[0],
                    2 => children[1],
                    else => unreachable,
                },
                else => unreachable,
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
        if (lvl >= 16) return;
        try writer.writeByteNTimes(' ', lvl * 2);
        try node.dump(writer, input);
        for (node.next.items) |item|
            try item.dumpRec(writer, input, lvl +| 1);
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
        indent: struct {
            trim_size: usize = 0,
            size: usize = 0,
            curr_level: usize = 0,
        } = .{},
        pending: struct {
            operators: List(*Node) = .{},
            operands: *List(*Node) = undefined,
            scopes: List(*Node) = .{},
            states: stack.Stack(State, 64) = .{},
        } = .{},
        state: State = .expr,

        const Self = @This();

        pub const State = enum {
            expr,
            operator,

            paren_post_open,
            paren_end,

            name_post_dot,
            name_post_dot_id,
            name_post_square_open,
            name_end_square,
            name_end_assign,

            end,
            phony,
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
            if (!try p.indentIsIncreasedOnce(p.token.len()))
                return error.UnalignedIndent;
        }

        fn updateIndent(p: *Self) Error!void {
            p.indent.curr_level = try p.indentLevelOf(p.token.len());
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

        fn pushPendingState(p: *Self, state: State) !void {
            try p.pending.states.push(state);
        }

        fn pushScopeAndEnter(p: *Self, node: *Node) !void {
            try p.pending.scopes.append(p.alloc, node);
            p.pending.operands = &(node.next);
        }

        fn popScopeAndExit(p: *Self) !void {
            const curr_scope = p.pending.scopes.pop().?;
            const prev_scope = p.pending.scopes.getLast();
            try prev_scope.next.append(p.alloc, curr_scope);
            p.pending.operands = &(prev_scope.next);
        }

        fn makeNode(p: *Self, comptime node_tag: Node.Tag, token: ?Token) !*Node {
            return Node.init(p.alloc, node_tag, token);
        }

        fn pushChild(p: *Self, comptime node_tag: Node.Tag, token: ?Token) !void {
            const node = try Node.init(p.alloc, node_tag, token);
            try p.pending.operands.append(p.alloc, node);
        }

        fn pushPendingNode(p: *Self, comptime node_tag: Node.Tag, token: ?Token) !void {
            const node = try Node.init(p.alloc, node_tag, token);
            try p.pending.operators.append(p.alloc, node);
        }

        fn reduceWhileHigherPre(p: *Self, tag: Node.Tag) !void {
            while (p.pending.operators.getLastOrNull()) |last| {
                if (last.tag.isHigherPrecedenceThan(tag)) {
                    try p.reduce(last);
                    _ = p.pending.operators.pop();
                } else break;
            }
        }

        fn reduceUntilFirstZeroPre(p: *Self) !void {
            while (p.pending.operators.pop()) |n| {
                if (n.tag.precedence() == 0) break;
                try p.reduce(n);
            }
        }

        fn reduceAll(p: *Self) !void {
            while (p.pending.operators.pop()) |node|
                try p.reduce(node);
        }

        fn reduce(p: *Self, node: *Node) !void {
            switch (node.tag) {
                // prefix
                .op_arith_neg => {
                    const rhs = p.pending.operands.pop().?;
                    try node.next.append(p.alloc, rhs);
                    try p.pending.operands.append(p.alloc, node);
                },
                // infix
                .op_arith_add,
                .op_arith_div,
                .op_arith_exp,
                .op_arith_mul,
                .op_arith_sub,
                => {
                    const rhs = p.pending.operands.pop().?;
                    const lhs = p.pending.operands.pop().?;
                    try node.next.append(p.alloc, lhs);
                    try node.next.append(p.alloc, rhs);
                    try p.pending.operands.append(p.alloc, node);
                },
                // infix_flatten
                .inline_enum_and,
                .inline_enum_or,
                => {
                    const rhs = p.pending.operands.pop().?;
                    const lhs = p.pending.operands.getLast();
                    if (lhs.tag == node.tag) { // continue pushing
                        try lhs.next.append(p.alloc, rhs);
                    } else { // create
                        try node.next.append(p.alloc, lhs);
                        try node.next.append(p.alloc, rhs);
                        p.pending.operands.items.len -= 1; // pop lhs
                        try p.pending.operands.append(p.alloc, node);
                    }
                },
                else => unreachable,
            }
        }

        fn indentLevelOf(p: *Self, indent_size: usize) Error!usize {
            if (indent_size == p.indent.trim_size) return 0;
            if (indent_size < p.indent.trim_size) return error.UnalignedIndent;

            if (p.indent.size == 0 and indent_size > 0) { // init indent
                p.indent.size = indent_size - p.indent.trim_size;
                return 1;
            }

            const size = indent_size - p.indent.trim_size;
            if (size % p.indent.size != 0) return error.UnalignedIndent;
            return size / p.indent.size;
        }

        fn indentIsEqual(p: *Self, indent_size: usize) Error!bool {
            return try p.indentLevelOf(indent_size) == p.indent.curr_level;
        }

        fn indentIsIncreasedOnce(p: *Self, indent_size: usize) Error!bool {
            const new_lvl = try p.indentLevelOf(indent_size);
            const expected_lvl = p.indent.curr_level + 1;
            if (new_lvl > expected_lvl) return error.UnalignedIndent;
            return new_lvl == expected_lvl;
        }

        fn indentIsDecreasedOnce(p: *Self, indent_size: usize) Error!bool {
            const new_lvl = try p.indentLevelOf(indent_size);
            const expected_lvl = p.indent.curr_level - 1;
            if (new_lvl < expected_lvl) return error.UnalignedIndent;
            return new_lvl == expected_lvl;
        }

        pub fn parse(p: *Self) Error!?*Node {
            p.initTrimSize();
            const root = try p.makeNode(.scope, null);
            try p.pushScopeAndEnter(root);
            try p.pushPendingState(.end);
            while (true) {
                p.log(logger.writer(), .token, false);
                p.log(logger.writer(), .pending_operators, false);
                p.log(logger.writer(), .pending_operands, false);
                p.log(logger.writer(), .pending_scopes, false);
                p.log(logger.writer(), .pending_states, false);
                p.log(logger.writer(), .state, true);
                switch (p.state) {
                    // ----------------
                    // .expr
                    // ----------------
                    .expr => {
                        switch (p.token.tag) {
                            .number => {
                                try p.pushChild(.literal_number, p.token);
                                p.advanceAndJump(.operator);
                            },
                            .identifier => {
                                try p.pushChild(.literal_identifier, p.token);
                                p.advanceAndJump(.operator);
                            },
                            .string => {
                                try p.pushChild(.literal_string, p.token);
                                p.advanceAndJump(.operator);
                            },
                            .paren_open => {
                                try p.pushPendingNode(.scope, p.token);
                                const parens = try p.makeNode(.scope, p.token);
                                try p.pushScopeAndEnter(parens);
                                p.advanceAndJump(.paren_post_open);
                            },
                            .dot => {
                                p.advanceAndJump(.name_post_dot);
                            },
                            else => {
                                return error.UnexpectedToken;
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
                                try p.reduceWhileHigherPre(node_tag);
                                try p.pushPendingNode(node_tag, p.token);
                                p.advanceAndJump(.expr);
                            },
                            .indent => {
                                if (try p.indentIsEqual(p.token.len())) {
                                    try p.reduceWhileHigherPre(.scope);
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
                        try p.pushChild(.name_def, p.token);
                        p.advanceAndJump(.name_post_dot_id);
                    },
                    .name_post_dot_id => {
                        switch (p.token.tag) {
                            .indent => { // block assign
                                if (try p.indentIsIncreasedOnce(p.token.len())) {
                                    p.indent.curr_level += 1;
                                    try p.pushPendingNode(.name_val, p.token);
                                    // const name_def = p.pending.operands.getLast();
                                    // try name_def.next.append(p.alloc, name_val);
                                    const name_val = try p.makeNode(.name_val, p.token);
                                    try p.pushScopeAndEnter(name_val);
                                    try p.pushPendingState(.name_end_assign);
                                    p.advanceAndJump(.expr);
                                } else {
                                    p.jump(.operator);
                                }
                            },
                            .equal => { // inline assign

                            },
                            .square_open => { // attributes
                                const name_attr = try p.makeNode(.name_attr, p.token);
                                const name_def = p.pending.operands.getLast();
                                try name_def.next.append(p.alloc, name_attr);
                                try p.pushScopeAndEnter(name_attr);
                                try p.pushPendingNode(.scope, p.token);
                                p.advanceAndJump(.name_post_square_open);
                            },
                            .empty_square => { // empty attributes
                                p.advanceAndJump(.operator);
                                // TODO p.advanceAndJump(.name_post_square_closed);
                            },
                            else => {
                                p.jump(.operator);
                            },
                        }
                    },

                    // .name [..]
                    .name_post_square_open => {
                        if (p.token.tag == .indent) {
                            if (try p.indentIsIncreasedOnce(p.token.len())) {
                                p.advance();
                            } // else jump below
                        } else {
                            // TODO inline
                        }
                        try p.pushPendingState(.name_end_square);
                        p.jump(.expr);
                    },
                    .name_end_square => {
                        try p.assert(.square_close, error.UnmatchedBracket);
                        try p.reduceUntilFirstZeroPre();
                        try p.popScopeAndExit();
                        p.advanceAndJump(.name_post_dot_id);
                    },

                    // .name = ..;
                    .name_end_assign => {
                        try p.reduceUntilFirstZeroPre();
                        try p.popScopeAndExit();
                        // TODO assert indent or ;
                        switch (p.token.tag) {
                            .indent => {
                                const indent_lvl = try p.indentLevelOf(p.token.len());
                                if (p.indent.curr_level - indent_lvl > 1) // exit
                                    return error.UnalignedIndent;
                                p.indent.curr_level -= 1;
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
                        try p.pushPendingState(.paren_end);
                        p.jump(.expr);
                    },
                    // TODO split into block/inline version with token assertions
                    .paren_end => {
                        if (p.token.tag == .indent) {
                            try p.updateIndent();
                            p.advanceAndJump(.paren_end);
                        } else {
                            try p.assert(.paren_close, error.UnmatchedBracket);
                            try p.reduceUntilFirstZeroPre();
                            try p.popScopeAndExit();
                            p.advanceAndJump(.operator);
                        }
                    },

                    .end => {
                        try p.assert(.eof, error.UnexpectedToken);
                        try p.reduceAll();
                        break;
                    },

                    else => unreachable,
                }
            }
            p.log(logger.writer(), .all, true);

            return p.pending.scopes.pop();
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
                pending_operators,
                pending_operands,
                pending_scopes,
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
                    writer.print("indent.level: {d}\n", .{p.indent.curr_level}) catch {};
                    writer.print("indent.trim_size: {d}\n", .{p.indent.trim_size}) catch {};
                },
                .pending_operands,
                .pending_operators,
                .pending_scopes,
                => |tag| {
                    writer.print(@tagName(tag) ++ ":\n", .{}) catch {};
                    const src = switch (tag) {
                        .pending_operators => p.pending.operators,
                        .pending_operands => p.pending.operands,
                        .pending_scopes => p.pending.scopes,
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
                    log(p, writer, .pending_scopes, false);
                    log(p, writer, .pending_states, false);
                    log(p, writer, .state, false);
                    log(p, writer, .cursor, false);
                },
            }
            if (extra_nl) writer.print("---\n", .{}) catch {};
        }
    };
}
