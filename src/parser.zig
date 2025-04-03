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
        root,

        // primitives
        literal_number,
        literal_string,
        literal_identifier,

        // enumeration
        inline_enum_and,
        inline_enum_or,

        // grouping
        parens,

        // arithmetics
        op_arith_add,
        op_arith_sub,
        op_arith_mul,
        op_arith_div,
        op_arith_exp,
        op_arith_neg,

        // abstraction
        name_ref,
        name_def,
        name_args,
        name_attr,
        name_type,
        name_val,

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
        current_node: *Node = undefined,
        pending_nodes: List(*Node) = .{},
        pending_states: stack.Stack(State, 64) = .{},
        state: State = .expr,

        const Self = @This();

        pub const State = enum {
            expr,
            operator,
            operator_post_indent,

            parens_post_open,
            parens_end_block,
            parens_end_inline,

            name_def_post_dot,
            name_def_post_dot_id,
            name_attr_post_square_open,
            name_attr_end_block,
            name_attr_end_inline,
            name_val_end_assign_block,
            name_val_end_assign_inline,

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

        fn jump(p: *Self, state: State) void {
            p.state = state;
        }

        fn jumpPending(p: *Self) void {
            p.state = p.pending_states.pop();
        }

        fn pushJump(p: *Self, state: State) !void {
            try p.pending_states.push(state);
        }

        fn advance(p: *Self) void {
            p.token = p.tokenizer.next();
        }

        fn advanceAndJump(p: *Self, state: State) void {
            p.token = p.tokenizer.next();
            p.state = state;
        }

        fn setScope(p: *Self, scope: *Node) void {
            p.current_node = scope;
        }

        fn makeNode(p: *Self, comptime node_tag: Node.Tag, token: ?Token) !*Node {
            return Node.init(p.alloc, node_tag, token);
        }

        fn pushChild(p: *Self, node: *Node) !void {
            try p.current_node.next.append(p.alloc, node);
        }

        fn pushToLastChild(p: *Self, node: *Node) !void {
            const last = p.current_node.next.getLast();
            try last.next.append(p.alloc, node);
        }

        fn pushPending(p: *Self, node: *Node) !void {
            try p.pending_nodes.append(p.alloc, node);
        }

        fn pushPendingAndSetScope(p: *Self, node: *Node) !void {
            try p.pending_nodes.append(p.alloc, node);
            p.current_node = node;
        }

        fn reduceWhileHigherPre(p: *Self, tag: Node.Tag) !void {
            while (p.pending_nodes.getLastOrNull()) |last| {
                if (last.tag.isHigherPrecedenceThan(tag)) {
                    try p.reduce(last);
                    _ = p.pending_nodes.pop();
                } else break;
            }
        }

        fn reduceAllNonZeroPre(p: *Self) !void {
            while (p.pending_nodes.getLastOrNull()) |n| {
                if (n.tag.precedence() == 0) break;
                try p.reduce(n);
                _ = p.pending_nodes.pop();
            }
        }

        fn reduceUntilFirstZeroPreInc(p: *Self) !void {
            while (p.pending_nodes.pop()) |n| {
                try p.reduce(n);
                if (n.tag.precedence() == 0) break;
            }
        }

        fn reduceAll(p: *Self) !void {
            while (p.pending_nodes.pop()) |node|
                try p.reduce(node);
        }

        fn reduce(p: *Self, pending: *Node) !void {
            switch (pending.tag) {
                // prefix
                .op_arith_neg,
                => {
                    const rhs = p.current_node.next.pop().?;
                    try pending.next.append(p.alloc, rhs);
                    try p.current_node.next.append(p.alloc, pending);
                },
                // infix
                .op_arith_add,
                .op_arith_div,
                .op_arith_exp,
                .op_arith_mul,
                .op_arith_sub,
                => {
                    const rhs = p.current_node.next.pop().?;
                    const lhs = p.current_node.next.pop().?;
                    try pending.next.append(p.alloc, lhs);
                    try pending.next.append(p.alloc, rhs);
                    try p.current_node.next.append(p.alloc, pending);
                },
                // infix_flatten
                .inline_enum_and,
                .inline_enum_or,
                => {
                    const rhs = p.current_node.next.pop().?;
                    const lhs = p.current_node.next.getLast();
                    if (lhs.tag == pending.tag) { // continue pushing
                        try lhs.next.append(p.alloc, rhs);
                    } else { // create
                        try pending.next.append(p.alloc, lhs);
                        try pending.next.append(p.alloc, rhs);
                        p.current_node.next.items.len -= 1; // pop lhs
                        try p.current_node.next.append(p.alloc, pending);
                    }
                },
                .root => {}, // ignore root scope
                else => { // exit scope
                    const parent = p.pending_nodes.getLast();
                    p.current_node = parent;
                },
            }
        }

        fn updateIndentLevel(p: *Self) Error!void {
            p.indent.curr_level = try p.indentLevel();
        }

        fn indentLevel(p: *Self) Error!usize {
            const indent_size = p.token.len();
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

        fn indentEqual(p: *Self) Error!bool {
            return try p.indentLevel() == p.indent.curr_level;
        }

        fn indentIncreasedOnce(p: *Self) Error!bool {
            const new_lvl = try p.indentLevel();
            const expected_lvl = p.indent.curr_level + 1;
            if (new_lvl > expected_lvl) return error.UnalignedIndent;
            return new_lvl == expected_lvl;
        }

        fn indentDecreasedOnce(p: *Self) Error!bool {
            const new_lvl = try p.indentLevel();
            const expected_lvl = p.indent.curr_level - 1;
            if (new_lvl < expected_lvl) return error.UnalignedIndent;
            return new_lvl == expected_lvl;
        }

        fn assertIndentIncreasedAndUpdate(p: *Self) Error!void {
            if (!try p.indentIncreasedOnce()) return error.UnexpectedToken;
            try p.updateIndentLevel();
        }

        fn assertIndentDecreasedAndUpdate(p: *Self) Error!void {
            if (!try p.indentDecreasedOnce()) return error.UnexpectedToken;
            try p.updateIndentLevel();
        }

        pub fn parse(p: *Self) Error!?*Node {
            p.initTrimSize();
            const root = try p.makeNode(.root, null);
            try p.pushPendingAndSetScope(root);
            try p.pushJump(.end);
            while (true) {
                p.log(logger.writer(), .token, false);
                p.log(logger.writer(), .current_children, false);
                p.log(logger.writer(), .pending_nodes, false);
                p.log(logger.writer(), .pending_states, false);
                p.log(logger.writer(), .state, true);
                switch (p.state) {
                    // ----------------
                    // .expr
                    // ----------------
                    .expr => {
                        switch (p.token.tag) {
                            .number => {
                                const literal = try p.makeNode(.literal_number, p.token);
                                try p.pushChild(literal);
                                p.advanceAndJump(.operator);
                            },
                            .identifier => {
                                const literal = try p.makeNode(.literal_identifier, p.token);
                                try p.pushChild(literal);
                                p.advanceAndJump(.operator);
                            },
                            .string => {
                                const literal = try p.makeNode(.literal_string, p.token);
                                try p.pushChild(literal);
                                p.advanceAndJump(.operator);
                            },
                            .paren_open => {
                                const parens = try p.makeNode(.parens, p.token);
                                try p.pushChild(parens);
                                try p.pushPendingAndSetScope(parens);
                                p.advanceAndJump(.parens_post_open);
                            },
                            .dot => {
                                p.advanceAndJump(.name_def_post_dot);
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
                            => |token_tag| {
                                const node_tag = switch (token_tag) {
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
                                const bin_op = try p.makeNode(node_tag, p.token);
                                try p.pushPending(bin_op);
                                p.advanceAndJump(.expr);
                            },
                            .indent => {
                                if (try p.indentEqual()) {
                                    try p.reduceAllNonZeroPre();
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
                    // .paren
                    // ----------------
                    .parens_post_open => {
                        if (p.token.tag == .indent) {
                            try p.assertIndentIncreasedAndUpdate();
                            try p.pushJump(.parens_end_block);
                            p.advance();
                        } else {
                            try p.pushJump(.parens_end_inline);
                        }
                        p.jump(.expr);
                    },
                    .parens_end_block => {
                        try p.assert(.indent, error.UnexpectedToken);
                        try p.assertIndentDecreasedAndUpdate();
                        p.advanceAndJump(.parens_end_inline);
                    },
                    .parens_end_inline => {
                        try p.assert(.paren_close, error.UnmatchedBracket);
                        try p.reduceUntilFirstZeroPreInc();
                        p.advanceAndJump(.operator);
                    },

                    // ----------------
                    // .name
                    // ----------------
                    // .a ..
                    .name_def_post_dot => {
                        try p.assert(.identifier, error.UnexpectedToken);
                        const name_def = try p.makeNode(.name_def, p.token);
                        try p.pushChild(name_def);
                        p.advanceAndJump(.name_def_post_dot_id);
                    },
                    .name_def_post_dot_id => {
                        switch (p.token.tag) {
                            .indent => { // block assign
                                if (try p.indentIncreasedOnce()) {
                                    try p.updateIndentLevel();

                                    const name_val = try p.makeNode(.name_val, p.token);
                                    try p.pushToLastChild(name_val);

                                    try p.pushPendingAndSetScope(name_val);
                                    try p.pushJump(.name_val_end_assign_block);
                                    p.advanceAndJump(.expr);
                                } else {
                                    p.jump(.operator);
                                }
                            },
                            .equal => { // inline assign
                                try p.pushJump(.name_val_end_assign_inline);
                            },
                            .square_open => { // attributes
                                const name_attr = try p.makeNode(.name_attr, p.token);
                                try p.pushToLastChild(name_attr);

                                try p.pushPendingAndSetScope(name_attr);
                                p.advanceAndJump(.name_attr_post_square_open);
                            },
                            .empty_square => { // empty attributes
                                p.advanceAndJump(.name_def_post_dot_id);
                            },
                            else => {
                                p.jump(.operator);
                            },
                        }
                    },

                    // .name [..]
                    .name_attr_post_square_open => {
                        if (p.token.tag == .indent) {
                            try p.assertIndentIncreasedAndUpdate();
                            try p.pushJump(.name_attr_end_block);
                            p.advance();
                        } else {
                            try p.pushJump(.name_attr_end_inline);
                        }
                        p.jump(.expr);
                    },
                    .name_attr_end_block => {
                        try p.assert(.indent, error.UnexpectedToken);
                        try p.assertIndentDecreasedAndUpdate();
                        p.advanceAndJump(.name_attr_end_inline);
                    },
                    .name_attr_end_inline => {
                        try p.assert(.square_close, error.UnmatchedBracket);
                        try p.reduceUntilFirstZeroPreInc();
                        p.advanceAndJump(.name_def_post_dot_id);
                    },

                    // .name = ..
                    .name_val_end_assign_block => {
                        try p.assert(.indent, error.UnexpectedToken);
                        try p.assertIndentDecreasedAndUpdate();
                        try p.reduceUntilFirstZeroPreInc();
                        p.advanceAndJump(.expr);
                    },
                    .name_val_end_assign_inline => {},

                    // ----------------
                    // end
                    // ----------------
                    .end => {
                        try p.assert(.eof, error.UnexpectedToken);
                        try p.reduceAll();
                        break;
                    },

                    else => unreachable,
                }
            }
            p.log(logger.writer(), .all, true);

            return root;
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
                pending_nodes,
                current_children,
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
                .current_children,
                .pending_nodes,
                .pending_scopes,
                => |tag| {
                    writer.print(@tagName(tag) ++ ":\n", .{}) catch {};
                    const src = switch (tag) {
                        .pending_nodes => p.pending_nodes,
                        .current_children => p.current_node.next,
                        // .pending_scopes => p.pending_scopes,
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
                    var i: usize = p.pending_states.constSlice().len;
                    while (i > 0) {
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
                    log(p, writer, .current_children, false);
                    log(p, writer, .pending_nodes, false);
                    log(p, writer, .pending_states, false);
                    log(p, writer, .state, false);
                    log(p, writer, .cursor, false);
                },
            }
            if (extra_nl) writer.print("---\n", .{}) catch {};
        }
    };
}
