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

    pub fn child(node: *const Node, comptime tag: Node.Tag) ?*Node {
        switch (node.tag) {
            .name_def => {
                for (node.next.items) |item|
                    if (item.tag == tag) return item;
                return null;
            },
            else => unreachable,
        }
    }

    pub fn children(node: *const Node) []*Node {
        return node.next.items;
    }

    pub fn childDescendants(node: *const Node, comptime tag: Node.Tag) ?[]*Node {
        return if (node.child(tag)) |c| c.next.items else null;
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
            level: usize = 0,
        } = .{},
        operator_stack: List(*Node) = .{},
        scope_stack: List(*Node) = .{},
        scope: *Node = undefined,
        state_stack: stack.Stack(State, 64) = .{},
        state: State = .expr,
        inline_mode: bool = false,

        const Self = @This();

        pub const State = enum {
            expr,
            operator,
            operator__post_indent,

            parens__post_open,
            parens__end_block,
            parens__end_inline,

            name_def__post_dot,
            name_def__post_dot_id,
            name_attr,
            name_attr__post_square_open,
            name_attr__end_block,
            name_attr__end_inline,
            name_val,
            name_val__end_assign_block,
            name_val__end_assign_inline,

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

        fn tokenIs(p: *Self, token_tag: Token.Tag) bool {
            return p.token.tag == token_tag;
        }

        fn assertToken(p: *Self, comptime token_tag: Token.Tag) Error!void {
            if (p.token.tag != token_tag) {
                return switch (token_tag) {
                    .curly_open, .paren_open, .square_open => error.UnmatchedBracket,
                    else => error.UnexpectedToken,
                };
            }
        }

        fn jump(p: *Self, state: State) void {
            p.state = state;
        }

        fn jumpPending(p: *Self) void {
            p.state = p.state_stack.pop();
        }

        fn pushJump(p: *Self, state: State) !void {
            try p.state_stack.push(state);
        }

        fn advance(p: *Self) void {
            p.token = p.tokenizer.next();
        }

        fn advanceAndJump(p: *Self, state: State) void {
            p.token = p.tokenizer.next();
            p.state = state;
        }

        fn createNode(p: *Self, comptime node_tag: Node.Tag, token: ?Token) !*Node {
            return Node.init(p.alloc, node_tag, token);
        }

        fn createAndPushOperand(p: *Self, comptime node_tag: Node.Tag, token: ?Token) !void {
            const node = try Node.init(p.alloc, node_tag, token);
            try p.scope.next.append(p.alloc, node);
        }

        fn createAndPushOperator(p: *Self, comptime node_tag: Node.Tag, token: ?Token) !void {
            const scope = try p.createNode(node_tag, token);
            try p.operator_stack.append(p.alloc, scope);
        }

        fn createAndPushOperatorScope(p: *Self, comptime node_tag: Node.Tag, token: ?Token) !void {
            const scope = try p.createNode(node_tag, token);
            try p.operator_stack.append(p.alloc, scope);
            try p.pushAndSetScope(scope);
        }

        fn pushAndSetScope(p: *Self, node: *Node) !void {
            try p.scope_stack.append(p.alloc, node);
            p.scope = node;
        }

        fn popAndSetScope(p: *Self) !void {
            _ = p.scope_stack.pop().?;
            p.scope = p.scope_stack.getLast();
        }

        fn reduceWhileHigherPre(p: *Self, tag: Node.Tag) !void {
            while (p.operator_stack.getLastOrNull()) |last| {
                if (last.tag.isHigherPrecedenceThan(tag)) {
                    try p.reduce(last);
                    _ = p.operator_stack.pop();
                } else break;
            }
        }

        fn reduceUntilZeroPre(p: *Self) !void {
            while (p.operator_stack.getLastOrNull()) |n| {
                if (n.tag.precedence() == 0) break;
                try p.reduce(n);
                _ = p.operator_stack.pop();
            }
        }

        fn reduceTilZeroPre(p: *Self) !void {
            while (p.operator_stack.pop()) |n| {
                try p.reduce(n);
                if (n.tag.precedence() == 0) break;
            }
        }

        fn reduceAll(p: *Self) !void {
            while (p.operator_stack.pop()) |node|
                try p.reduce(node);
        }

        fn reduceOnce(p: *Self) !void {
            try p.reduce(p.operator_stack.pop().?);
        }

        fn reduce(p: *Self, operator: *Node) !void {
            switch (operator.tag) {
                // prefix
                .op_arith_neg,
                => {
                    const rhs = p.scope.next.pop().?;
                    try operator.next.append(p.alloc, rhs);
                    try p.scope.next.append(p.alloc, operator);
                },
                // infix
                .op_arith_add,
                .op_arith_div,
                .op_arith_exp,
                .op_arith_mul,
                .op_arith_sub,
                => {
                    const rhs = p.scope.next.pop().?;
                    const lhs = p.scope.next.pop().?;
                    try operator.next.append(p.alloc, lhs);
                    try operator.next.append(p.alloc, rhs);
                    try p.scope.next.append(p.alloc, operator);
                },
                // infix_flatten
                .inline_enum_and,
                .inline_enum_or,
                => {
                    const rhs = p.scope.next.pop().?;
                    const lhs = p.scope.next.getLast();
                    if (lhs.tag == operator.tag) { // continue pushing
                        try lhs.next.append(p.alloc, rhs);
                    } else { // create
                        try operator.next.append(p.alloc, lhs);
                        try operator.next.append(p.alloc, rhs);
                        p.scope.next.items.len -= 1; // pop lhs
                        try p.scope.next.append(p.alloc, operator);
                    }
                },
                else => {
                    try p.popAndSetScope();
                    try p.scope.next.append(p.alloc, operator);
                },
            }
        }

        fn updateIndentLevel(p: *Self) Error!void {
            p.indent.level = try p.indentLevel();
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
            return try p.indentLevel() == p.indent.level;
        }

        fn indentIncOnce(p: *Self) Error!bool {
            const new_lvl = try p.indentLevel();
            const expected_lvl = p.indent.level + 1;
            if (new_lvl > expected_lvl) return error.UnalignedIndent;
            return new_lvl == expected_lvl;
        }

        fn indentDecOnce(p: *Self) Error!bool {
            const new_lvl = try p.indentLevel();
            const expected_lvl = p.indent.level - 1;
            if (new_lvl < expected_lvl) return error.UnalignedIndent;
            return new_lvl == expected_lvl;
        }

        fn assertIndentEqual(p: *Self) Error!void {
            if (!try p.indentEqual()) return error.UnexpectedToken;
        }

        fn assertIndentIncAndUpdate(p: *Self) Error!void {
            if (!try p.indentIncOnce()) return error.UnexpectedToken;
            try p.updateIndentLevel();
        }

        fn assertIndentDecAndUpdate(p: *Self) Error!void {
            if (!try p.indentDecOnce()) return error.UnexpectedToken;
            try p.updateIndentLevel();
        }

        fn inlineIsActive(p: *Self) bool {
            return p.inline_mode;
        }

        pub fn parse(p: *Self) Error!?*Node {
            p.initTrimSize();
            const root = try p.createNode(.root, null);
            try p.pushAndSetScope(root);
            try p.pushJump(.end);
            while (true) {
                p.log(logger.writer(), .state, false);
                p.log(logger.writer(), .token, false);
                p.log(logger.writer(), .unparsed, false);
                p.log(logger.writer(), .scope, false);
                p.log(logger.writer(), .scopes, false);
                p.log(logger.writer(), .states, true);
                switch (p.state) {
                    // ----------------
                    // .expr
                    // ----------------
                    .expr => {
                        switch (p.token.tag) {
                            .number => {
                                try p.createAndPushOperand(.literal_number, p.token);
                                p.advanceAndJump(.operator);
                            },
                            .identifier => {
                                try p.createAndPushOperand(.literal_identifier, p.token);
                                p.advanceAndJump(.operator);
                            },
                            .string => {
                                try p.createAndPushOperand(.literal_string, p.token);
                                p.advanceAndJump(.operator);
                            },
                            .paren_open => {
                                try p.createAndPushOperatorScope(.parens, p.token);
                                p.advanceAndJump(.parens__post_open);
                            },
                            .dot => {
                                p.advanceAndJump(.name_def__post_dot);
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
                                try p.createAndPushOperator(node_tag, p.token);
                                p.advanceAndJump(.expr);
                            },
                            .indent => {
                                if (!p.inlineIsActive() and try p.indentEqual()) {
                                    try p.reduceUntilZeroPre();
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
                    // .parens_
                    // ----------------
                    .parens__post_open => {
                        if (p.tokenIs(.indent)) {
                            try p.assertIndentIncAndUpdate();
                            try p.pushJump(.parens__end_block);
                            p.advance();
                        } else {
                            try p.pushJump(.parens__end_inline);
                        }
                        p.jump(.expr);
                    },
                    .parens__end_block => {
                        try p.assertToken(.indent);
                        try p.assertIndentDecAndUpdate();
                        p.advanceAndJump(.parens__end_inline);
                    },
                    .parens__end_inline => {
                        try p.assertToken(.paren_close);
                        try p.reduceTilZeroPre();
                        p.advanceAndJump(.operator);
                    },

                    // ----------------
                    // .name_
                    // ----------------
                    // Name definition
                    // .a ..
                    .name_def__post_dot => {
                        try p.assertToken(.identifier);
                        try p.createAndPushOperatorScope(.name_def, p.token);
                        p.advanceAndJump(.name_def__post_dot_id);
                    },
                    .name_def__post_dot_id => {
                        // order: name -> arg (TODO) -> attr -> type (TODO) -> val
                        switch (p.token.tag) {
                            .square_open => p.jump(.name_attr),
                            .empty_square => p.advanceAndJump(.name_val),
                            .indent, .equal => p.jump(.name_val),
                            else => {
                                try p.reduceOnce();
                                p.jump(.operator);
                            },
                        }
                    },

                    // Name attribute
                    // .a [..]
                    .name_attr => {
                        // p.tokenIs(.square_open);
                        try p.createAndPushOperatorScope(.name_attr, p.token);
                        p.advanceAndJump(.name_attr__post_square_open);
                    },
                    .name_attr__post_square_open => {
                        if (p.tokenIs(.indent)) {
                            try p.assertIndentIncAndUpdate();
                            try p.pushJump(.name_attr__end_block);
                            p.advance();
                        } else {
                            try p.pushJump(.name_attr__end_inline);
                        }
                        p.jump(.expr);
                    },
                    .name_attr__end_block => {
                        try p.assertToken(.indent);
                        try p.assertIndentDecAndUpdate();
                        p.advanceAndJump(.name_attr__end_inline);
                    },
                    .name_attr__end_inline => {
                        try p.assertToken(.square_close);
                        try p.reduceTilZeroPre();
                        p.advanceAndJump(.name_val);
                    },

                    // Name value
                    // .a = ..
                    .name_val => {
                        switch (p.token.tag) {
                            .indent => {
                                if (try p.indentIncOnce()) {
                                    try p.updateIndentLevel();
                                    try p.createAndPushOperatorScope(.name_val, p.token);
                                    try p.pushJump(.name_val__end_assign_block);
                                    p.advanceAndJump(.expr);
                                } else {
                                    try p.reduceTilZeroPre();
                                    p.jump(.operator);
                                }
                            },
                            .equal => {
                                p.inline_mode = true;
                                try p.createAndPushOperatorScope(.name_val, p.token);
                                try p.pushJump(.name_val__end_assign_inline);
                                p.advanceAndJump(.expr);
                            },
                            else => {
                                try p.reduceTilZeroPre();
                                p.jump(.operator);
                            },
                        }
                    },
                    .name_val__end_assign_block => {
                        try p.reduceTilZeroPre();
                        try p.reduceOnce(); // exit .name_def
                        if (p.tokenIs(.eof)) {
                            p.jumpPending();
                            continue;
                        }
                        try p.assertToken(.indent);
                        try p.assertIndentDecAndUpdate();
                        p.advanceAndJump(.expr);
                    },
                    .name_val__end_assign_inline => {
                        p.inline_mode = false;
                        try p.reduceTilZeroPre();
                        try p.reduceOnce(); // exit .name_def
                        if (p.tokenIs(.eof)) {
                            p.jumpPending();
                            continue;
                        }
                        p.jump(.operator);
                    },

                    // ----------------
                    // end
                    // ----------------
                    .end => {
                        try p.assertToken(.eof);
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
                unparsed,
                scope,
                scopes,
                states,
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
                .scope,
                .scopes,
                .unparsed,
                => |tag| {
                    writer.print(@tagName(tag) ++ ": ", .{}) catch {};
                    const src = switch (tag) {
                        .scope => blk: {
                            switch (p.scope.tag) {
                                inline else => |t| {
                                    writer.print(".{s}", .{@tagName(t)}) catch {};
                                },
                            }
                            break :blk p.scope.next;
                        },
                        .scopes => p.scope_stack,
                        .unparsed => p.operator_stack,
                        else => unreachable,
                    };
                    writer.writeByte('\n') catch {};
                    var i: usize = src.items.len;
                    while (i > 0) {
                        i -= 1;
                        const node = src.items[i];
                        writer.writeByteNTimes(' ', 2) catch {};
                        node.dump(writer, p.tokenizer.input) catch {};
                    }
                },
                .states => |tag| {
                    writer.print(@tagName(tag) ++ ":\n", .{}) catch {};
                    var i: usize = p.state_stack.constSlice().len;
                    while (i > 0) {
                        i -= 1;
                        const state = p.state_stack.arr[i];
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
                    log(p, writer, .state, false);
                    log(p, writer, .token, false);
                    log(p, writer, .unparsed, false);
                    log(p, writer, .scope, false);
                    log(p, writer, .scopes, false);
                    log(p, writer, .states, false);
                    log(p, writer, .indent, false);
                    log(p, writer, .cursor, false);
                },
            }
            if (extra_nl) writer.print("---\n", .{}) catch {};
        }
    };
}
