// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

const std = @import("std");
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const Token = @import("tokenizer.zig").Token;
const print = std.debug.print;
const assert = std.debug.assert;

pub const List = std.ArrayListUnmanaged;
pub const Map = std.StringHashMapUnmanaged;

pub const Node = struct {
    tag: Tag,
    data: union(DataTag) {
        literal: []const u8,
        single: ?*Node,
        pair: struct { left: ?*Node, right: ?*Node },
        list: List(*Node),
        map: Map(*Node),
    },

    pub const DataTag = enum {
        literal,
        single,
        pair,
        list,
        map,
    };

    pub fn init(alloc: std.mem.Allocator, tag: Tag, data_tag: DataTag) !*Node {
        var node = try alloc.create(Node);
        node.tag = tag;
        node.data = switch (data_tag) {
            .literal => .{ .literal = &[_]u8{} },
            .single => .{ .single = null },
            .pair => .{ .pair = .{ .left = null, .right = null } },
            .list => .{ .list = List(*Node){} },
            .map => .{ .map = Map(*Node){} },
        };
        return node;
    }

    pub const Tag = enum(u5) {
        // operands
        literal_number,
        literal_identifier,
        node_list,
        node_map,

        // operators
        op_arith_add,
        op_arith_sub,
        op_arith_mul,
        op_arith_div,
        op_arith_exp,
        op_arith_neg,

        op_node,
        op_node_name,
        op_node_attr,
        op_node_type,
        op_node_value,

        op_list_and,
        op_list_or,

        op_scope,

        op_ctrl_for,
        op_ctrl_for_cnd,
        op_ctrl_for_body,

        op_ctrl_while,
        op_ctrl_if,

        /// If there are two identical operators in a sequence, right
        /// associativity means that the operator on the right is applied first.
        inline fn isRightAssociative(node_tag: Tag) bool {
            return if (node_tag.precedence() == 0 or node_tag == .op_arith_exp) true else false;
        }

        inline fn precedence(node_tag: Tag) std.meta.Tag(Tag) {
            return precedence_table[@intFromEnum(node_tag)];
        }

        const precedence_table = blk: {
            const Tags_size = std.meta.Tag(Tag); // u5
            const tags_len = std.meta.fields(Tag).len;
            var table = [1]Tags_size{0} ** tags_len; // 0 for all, except:
            table[@intFromEnum(Tag.op_arith_add)] = 1;
            table[@intFromEnum(Tag.op_arith_sub)] = 1;
            table[@intFromEnum(Tag.op_arith_mul)] = 2;
            table[@intFromEnum(Tag.op_arith_div)] = 2;
            table[@intFromEnum(Tag.op_arith_exp)] = 3;
            table[@intFromEnum(Tag.op_arith_neg)] = 7;
            // table[@intFromEnum(Tag.op_list_or)] = 1;
            break :blk table;
        };

        pub inline fn isOperator(node_tag: Tag) bool {
            return @intFromEnum(node_tag) >= @intFromEnum(Tag.op_arith_add) and
                @intFromEnum(node_tag) <= @intFromEnum(Tag.op_arith_exp);
        }

        pub inline fn isStatement(node_tag: Tag) bool {
            return @intFromEnum(node_tag) >= @intFromEnum(Tag.op_ctrl_for) and
                @intFromEnum(node_tag) <= @intFromEnum(Tag.op_ctrl_if);
        }
    };
};

const Token = @import("tokenizer.zig").Token;
const Tokenizer = @import("tokenizer.zig").Tokenizer(
    .{ .ignore_spaces = true },
);

pub const Parser = struct {
    alloc: std.mem.Allocator,
    tokenizer: Tokenizer,
    indent: Indent = .{},
    pending: Stack = .{},
    state: State = .expect_leading_space,
    err: ?union(enum) {
        token: Token,
    } = null,

    pub const Error = error{
        OutOfMemory,
        UnbalancedOperandStack,
        InvalidOperatorActiveTag,
        InvalidToken,
        UnexpectedToken,
        UnexpectedNullNode,
        UnexpectedState,
        UnsupportedOperator,
        UnbalancedClosingBracket,
    };

    const Indent = struct {
        lead_size: u16 = 0, // --code   (-- leading space before indentation)
        size: u16 = 0, //      --++code (++ indentation size)
    };

    pub const State = enum {
        expect_leading_space,
        expect_indentation,

        expect_literal_or_op_prefix,
        expect_op_postfix_or_infix,

        expect_past_for,
        expect_past_for_condition,

        expect_past_dot,
        expect_past_dot_id,
        expect_past_dot_id_attr,
    };

    pub fn init(alloc: std.mem.Allocator, input: [:0]const u8) Parser {
        return Parser{
            .alloc = alloc,
            .tokenizer = Tokenizer.init(input),
        };
    }

    pub fn parse(p: *Parser, from: State) Error!?*Node {
        var token: Token = p.tokenizer.nextFrom(.space);
        p.state = from;
        parse: while (true) {
            // try log_parse(p);
            // std.log.info("{}", .{p.state});
            // std.log.info("{}", .{token});
            switch (p.state) {
                // initialization state
                .expect_leading_space => {
                    while (true) {
                        switch (token.tag) {
                            .space => p.indent.lead_size = @intCast(token.len()),
                            .newline => p.indent.lead_size = 0,
                            else => {
                                p.state = .expect_literal_or_op_prefix;
                                continue :parse;
                            },
                        }
                        token = p.tokenizer.nextFrom(.space);
                    }
                },

                // main state
                .expect_literal_or_op_prefix => {
                    switch (token.tag) {
                        .eof => break,
                        .left_paren => {
                            try p.pending.operators.append(p.alloc, .op_scope);
                            try p.pending.scope.append(p.alloc, .{ .state = .expect_op_postfix_or_infix, .closing_token = .right_paren });
                        },
                        .identifier => {
                            var node = try Node.init(p.alloc, .literal_identifier, .literal);
                            node.data.literal = token.sliceFrom(p.tokenizer.input);
                            try p.pending.operands.append(p.alloc, node);
                            p.state = .expect_op_postfix_or_infix;
                        },
                        .number => {
                            var node = try Node.init(p.alloc, .literal_number, .literal);
                            node.data.literal = token.sliceFrom(p.tokenizer.input);
                            try p.pending.operands.append(p.alloc, node);
                            p.state = .expect_op_postfix_or_infix;
                        },

                        .keyword_for => {
                            p.state = .expect_past_for;
                        },
                        .dot => {
                            p.state = .expect_past_dot;
                        },
                        .minus => { // add jump to a state instead (to limit the space of next valid tokens)
                            try p.pending.operators.append(p.alloc, .op_arith_neg);
                        },

                        // invalid states:
                        .invalid => {
                            p.err = .{ .token = token };
                            return Error.InvalidToken;
                        },
                        else => {
                            p.err = .{ .token = token };
                            // Provide additional error context
                            // switch (token.tag) {
                            // .right_paren => {},
                            // }
                            return Error.UnexpectedToken;
                        },
                    }
                },

                .expect_op_postfix_or_infix => {
                    switch (token.tag) {
                        .eof => break,
                        // .newline => p.state = .end_parse_scope,
                        .plus,
                        .plus_plus,
                        .minus,
                        .asterisk,
                        .slash,
                        .caret,
                        .comma,
                        .pipe,
                        => {
                            const operator: Node.Tag = switch (token.tag) {
                                .plus => .op_arith_add,
                                // .plus_plus => .op_arith_add,
                                .minus => .op_arith_sub,
                                .asterisk => .op_arith_mul,
                                .slash => .op_arith_div,
                                .caret => .op_arith_exp,
                                .comma => .op_list_and,
                                .pipe => .op_list_or,
                                else => unreachable,
                            };
                            try p.pending.resolveAllIfPrecedenceIsHigher(p.alloc, operator);
                            try p.pending.operators.append(p.alloc, operator);
                            p.state = .expect_literal_or_op_prefix;
                        },

                        .right_square,
                        .right_paren,
                        .right_curly,
                        => |closing_bracket| {
                            if (p.pending.scope.popOrNull()) |pending| {
                                if (pending.closing_token != closing_bracket) {
                                    p.err = .{ .token = token };
                                    return Error.UnbalancedClosingBracket;
                                }
                                try p.pending.resolveAllUntil(p.alloc, .op_scope);
                                p.state = pending.state;
                            } else {
                                p.err = .{ .token = token };
                                return Error.UnexpectedToken;
                            }
                        },

                        else => {
                            p.err = .{ .token = token };
                            return Error.UnexpectedToken;
                        },
                    }
                },

                .expect_indentation => {
                    // token = p.tokenizer.nextFrom(.space);
                    if (token.tag == .space) {
                        if (p.indent.size == 0) {
                            p.indent.size = @intCast(token.len());
                        }
                        // check depth integrity
                    }
                    p.state = .expect_literal_or_op_prefix;
                    // continue;
                },

                // control structure states
                .expect_past_for => {
                    if (token.tag != .left_paren) {
                        p.err = .{ .token = token };
                        return Error.UnexpectedToken;
                    }

                    const node = try Node.init(p.alloc, .op_ctrl_for, .map);
                    try p.pending.operands.append(p.alloc, node);

                    try p.pending.operators.append(p.alloc, .op_scope);
                    try p.pending.scope.append(p.alloc, .{ .state = .expect_past_for_condition, .closing_token = .right_paren });
                    p.state = .expect_literal_or_op_prefix;
                },

                .expect_past_for_condition => {
                    // try p.pending.operators.append(p.alloc, .op_ctrl_for_body);
                    try p.pending.resolveAs(p.alloc, .op_ctrl_for_cnd);
                    try p.pending.operators.append(p.alloc, .op_ctrl_for_body);
                    p.state = .expect_literal_or_op_prefix;
                    continue;
                },

                // node processing states
                .expect_past_dot => {
                    const node = try Node.init(p.alloc, .op_node, .map);
                    try p.pending.operands.append(p.alloc, node);

                    switch (token.tag) {
                        .identifier => {
                            var literal = try Node.init(p.alloc, .literal_identifier, .literal);
                            literal.data.literal = token.sliceFrom(p.tokenizer.input);
                            try p.pending.operands.append(p.alloc, literal);

                            try p.pending.resolveAs(p.alloc, .op_node_name);
                            p.state = .expect_past_dot_id;
                        },
                        else => {
                            p.err = .{ .token = token };
                            return Error.UnexpectedToken;
                        },
                    }
                },
                .expect_past_dot_id => {
                    switch (token.tag) {
                        .left_square => {
                            try p.pending.operators.append(p.alloc, .op_scope);
                            try p.pending.scope.append(p.alloc, .{ .state = .expect_past_dot_id_attr, .closing_token = .right_square });

                            p.state = .expect_literal_or_op_prefix;
                        },
                        .equal => {
                            try p.pending.operators.append(p.alloc, .op_node_value);
                            p.state = .expect_literal_or_op_prefix;
                        },
                        else => {
                            p.state = .expect_op_postfix_or_infix;
                        },
                    }
                },
                .expect_past_dot_id_attr => {
                    try p.pending.resolveAs(p.alloc, .op_node_attr);
                    switch (token.tag) {
                        .equal => {
                            try p.pending.operators.append(p.alloc, .op_node_value);
                            p.state = .expect_literal_or_op_prefix;
                        },
                        else => {
                            p.state = .expect_op_postfix_or_infix;
                        },
                    }
                },

                // else => return error.UnexpectedState,
            }
            token = p.tokenizer.next();
            try dump_stack(p);
        }

        try p.pending.resolveAll(p.alloc);

        return p.pending.operands.popOrNull();
    }

    pub const Stack = struct {
        operands: List(*Node) = .{},
        operators: List(Node.Tag) = .{},
        scope: List(struct { state: Parser.State, closing_token: Token.Tag }) = .{},

        /// ```
        ///  2        [+]        [*]  < current
        ///  1         *          +   < pending
        /// ---       ---        ---
        ///           (case 1)   (case 2)
        /// operands  operators  operators
        ///           1 * 2 [+]  1 + 2 [*]
        /// ```
        pub inline fn resolveAllIfPrecedenceIsHigher(s: *Stack, alloc: std.mem.Allocator, current: Node.Tag) Error!void {
            while (s.operators.getLastOrNull()) |pending| {
                if (pending.precedence() > current.precedence() or
                    (pending.precedence() == current.precedence() and !current.isRightAssociative()))
                {
                    // std.log.err("{s}", .{@tagName(current)});
                    try s.resolveOnce(alloc); // (case 1)
                } else break; // (case 2)
            }
        }

        pub inline fn resolveAllUntil(s: *Stack, alloc: std.mem.Allocator, tag: Node.Tag) Error!void {
            while (s.operators.popOrNull()) |operator| {
                try s.resolveAs(alloc, operator);
                if (operator == tag) break;
            }
        }

        pub inline fn resolveAll(s: *Stack, alloc: std.mem.Allocator) Error!void {
            while (s.operators.popOrNull()) |operator| {
                try s.resolveAs(alloc, operator);
            }
        }

        pub fn resolveOnce(s: *Stack, alloc: std.mem.Allocator) Error!void {
            if (s.operators.popOrNull()) |operator| {
                try s.resolveAs(alloc, operator);
            }
        }

        pub fn resolveAs(s: *Stack, alloc: std.mem.Allocator, operator: Node.Tag) Error!void {
            switch (operator) {
                // discarding operators
                .op_scope => {},

                // single-operand operators
                .op_arith_neg => {
                    if (s.operands.items.len < 1) return Error.UnbalancedOperandStack;

                    const node = try Node.init(alloc, operator, .single);
                    node.data.single = s.operands.pop();
                    try s.operands.append(alloc, node);
                },

                // two-operands operators
                .op_arith_add,
                .op_arith_div,
                .op_arith_exp,
                .op_arith_mul,
                .op_arith_sub,
                => {
                    if (s.operands.items.len < 2) return Error.UnbalancedOperandStack;

                    const node = try Node.init(alloc, operator, .pair);
                    node.data.pair.right = s.operands.pop();
                    node.data.pair.left = s.operands.pop();
                    try s.operands.append(alloc, node);
                },

                // n-operands operators
                .op_list_and,
                .op_list_or,
                => {
                    if (s.operands.items.len < 2) return Error.UnbalancedOperandStack;

                    const second = s.operands.pop();
                    const first = s.operands.pop();
                    if (first.data == .list) {
                        try first.data.list.append(alloc, second);
                        try s.operands.append(alloc, first);
                    } else {
                        const node = try Node.init(alloc, operator, .list);
                        try node.data.list.append(alloc, first);
                        try node.data.list.append(alloc, second);
                        try s.operands.append(alloc, node);
                    }
                },

                // operands-mapping operators
                inline .op_ctrl_for_body,
                .op_ctrl_for_cnd,
                .op_node_value,
                .op_node_attr,
                .op_node_name,
                => |op| {
                    if (s.operands.items.len < 2) return Error.UnbalancedOperandStack;

                    const val = s.operands.pop();
                    const node = s.operands.getLast();
                    const key = comptime switch (op) {
                        .op_ctrl_for_body => "body",
                        .op_ctrl_for_cnd => "cnd",
                        .op_node_value => "val",
                        .op_node_attr => "attr",
                        .op_node_name => "name",
                        else => unreachable,
                    };
                    try node.data.map.put(alloc, key, val);
                },

                else => {
                    return Error.UnsupportedOperator;
                },
            }
        }
    };

    pub fn parseFromInput(alloc: std.mem.Allocator, input: [:0]const u8) !?*Node {
        var p = Parser.init(alloc, input);
        return p.parse(.expect_leading_space);
    }
};

fn dump_node(tree: ?*Node, alloc: std.mem.Allocator, lvl: usize) ![]u8 {
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
                const rhs = try dump_node(elm, alloc, (lvl + 1));
                try out.appendSlice(rhs);
            },
            .pair => |pair| {
                // `\n` + recursion
                try out.append('\n');
                const lhs = try dump_node(pair.left, alloc, (lvl + 1));
                try out.appendSlice(lhs);
                const rhs = try dump_node(pair.right, alloc, (lvl + 1));
                try out.appendSlice(rhs);
            },
            .list => |list| {
                // `\n` + recursion
                try out.append('\n');
                for (list.items) |item| {
                    const res = try dump_node(item, alloc, (lvl + 1));
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
                    const rhs = try dump_node(entry.value_ptr.*, alloc, (lvl + 2));
                    try out.appendSlice(rhs);
                }
            },
        }
        return out.toOwnedSlice();
    }
    return "";
}

fn dump_stack(p: *Parser) !void {
    var out = std.ArrayList(u8).init(p.alloc);
    const operators = p.pending.operators.items;
    const operands = p.pending.operands.items;
    const scopes = p.pending.scope.items;

    var i: usize = @max(scopes.len, @max(operands.len, operators.len)) -| 1;
    while (true) : (i -= 1) { // zip print
        const operand = if (i < operands.len) @tagName(operands[i].tag) else "";
        try out.writer().print("|{s: <24}| ", .{operand});

        const operator = if (i < operators.len) @tagName(operators[i]) else "";
        try out.writer().print("|{s: <24}| ", .{operator});

        const state = if (i < scopes.len) @tagName(scopes[i].state)[5..] else "";
        try out.writer().print("|{s: <20},", .{state});

        const bracket = if (i < scopes.len) @tagName(scopes[i].closing_token) else "";
        try out.writer().print(" {s: <20}| ", .{bracket});

        try out.append('\n');
        if (i == 0) break;
    }

    printStderr("\n{s} " ++ ("-" ** (24 * 4)) ++ "\n", .{out.items});
}

fn printStderr(comptime fmt: []const u8, args: anytype) void {
    const stderr = std.io.getStdErr().writer();
    var bw = std.io.bufferedWriter(stderr);
    const writer = bw.writer();

    std.debug.getStderrMutex().lock();
    defer std.debug.getStderrMutex().unlock();
    nosuspend {
        writer.print(fmt, args) catch return;
        bw.flush() catch return;
    }
}

test "parser" {
    const t = std.testing;

    const case = struct {
        fn run(input: [:0]const u8, expect: [:0]const u8) !void {
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();

            const node = try Parser.parseFromInput(arena.allocator(), input);
            const res = try dump_node(node, arena.allocator(), 0);
            try t.expectEqualStrings(expect, res[0..res.len -| 1]);
        }
    };

    try case.run("1",
        \\.literal_number -> "1"
    );

    try case.run("1 + 2",
        \\.op_arith_add
        \\  .literal_number -> "1"
        \\  .literal_number -> "2"
    );

    try case.run("1 + 2 * 3 ^ 4 - 5",
        \\.op_arith_sub
        \\  .op_arith_add
        \\    .literal_number -> "1"
        \\    .op_arith_mul
        \\      .literal_number -> "2"
        \\      .op_arith_exp
        \\        .literal_number -> "3"
        \\        .literal_number -> "4"
        \\  .literal_number -> "5"
    );

    try case.run("(1 + 2) * 3 ^ -(4 - 5)",
        \\.op_arith_mul
        \\  .op_arith_add
        \\    .literal_number -> "1"
        \\    .literal_number -> "2"
        \\  .op_arith_exp
        \\    .literal_number -> "3"
        \\    .op_arith_neg
        \\      .op_arith_sub
        \\        .literal_number -> "4"
        \\        .literal_number -> "5"
    );

    try case.run("for (x) 1 + 2 | 3",
        \\.op_ctrl_for
        \\  "cnd":
        \\    .literal_identifier -> "x"
        \\  "body":
        \\    .op_list_or
        \\      .op_arith_add
        \\        .literal_number -> "1"
        \\        .literal_number -> "2"
        \\      .literal_number -> "3"
    );

    try case.run(".name [attr1, attr2] = 5",
        \\.op_node
        \\  "name":
        \\    .literal_identifier -> "name"
        \\  "val":
        \\    .literal_number -> "5"
        \\  "attr":
        \\    .op_list_and
        \\      .literal_identifier -> "attr1"
        \\      .literal_identifier -> "attr2"
    );
}
