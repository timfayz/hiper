// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

const std = @import("std");
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
        literal_string,
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

        op_enum_and,
        op_enum_or,

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
            // table[@intFromEnum(Tag.op_enum_or)] = 1;
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
    tokenizer: Tokenizer,
    indent: struct {
        lead_size: u16 = 0, // --code   (-- space before indentation)
        size: u16 = 0, //      --++code (++ indentation size)
    } = .{},
    pending: struct {
        operands: List(*Node) = .{},
        operators: List(Node.Tag) = .{},
        scope: List(struct { state: Parser.State, closing_token: Token.Tag }) = .{},

        const Stack = @This();

        pub inline fn resolveAllIfPrecedenceIsHigher(s: *Stack, alloc: std.mem.Allocator, current: Node.Tag) Error!void {
            while (s.operators.getLastOrNull()) |pending| {
                if (pending.precedence() > current.precedence() or
                    (pending.precedence() == current.precedence() and !current.isRightAssociative()))
                {
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
                    if (s.operands.items.len < 1) return Error.UnbalancedOperandsStack;

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
                    if (s.operands.items.len < 2) return Error.UnbalancedOperandsStack;

                    const node = try Node.init(alloc, operator, .pair);
                    node.data.pair.right = s.operands.pop();
                    node.data.pair.left = s.operands.pop();
                    try s.operands.append(alloc, node);
                },

                // n-operands operators
                .op_enum_and,
                .op_enum_or,
                => {
                    if (s.operands.items.len < 2) return Error.UnbalancedOperandsStack;

                    const right = s.operands.pop();
                    const left = s.operands.pop();
                    if (left.data == .list) {
                        try left.data.list.append(alloc, right);
                        try s.operands.append(alloc, left);
                    } else {
                        const node = try Node.init(alloc, operator, .list);
                        try node.data.list.append(alloc, left);
                        try node.data.list.append(alloc, right);
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
                    if (s.operands.items.len < 2) return Error.UnbalancedOperandsStack;

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
    } = .{},
    state: State = .expect_leading_space,
    token: Token = undefined,

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

    pub const Error = error{
        OutOfMemory,
        UnbalancedOperandsStack,
        InvalidToken, // TODO utilize
        UnexpectedToken,
        UnexpectedState, // TODO remove
        UnsupportedOperator, // TODO temporarily?
        UnbalancedClosingBracket,
    };

    pub fn init(input: [:0]const u8) Parser {
        return Parser{ .tokenizer = Tokenizer.init(input) };
    }

    pub fn parse(p: *Parser, alloc: std.mem.Allocator, from: State) Error!?*Node {
        p.token = p.tokenizer.nextFrom(.space);
        p.state = from;
        parse: while (true) {
            try p.printStacks(alloc);
            switch (p.state) {
                // initialization state
                .expect_leading_space => {
                    while (true) {
                        switch (p.token.tag) {
                            .space => p.indent.lead_size = @intCast(p.token.len()),
                            .newline => p.indent.lead_size = 0,
                            else => {
                                p.state = .expect_literal_or_op_prefix;
                                continue :parse;
                            },
                        }
                        p.token = p.tokenizer.nextFrom(.space);
                    }
                },

                // main state
                .expect_literal_or_op_prefix => {
                    switch (p.token.tag) {
                        .eof => break,
                        .left_paren => {
                            try p.pending.operators.append(alloc, .op_scope);
                            try p.pending.scope.append(alloc, .{ .state = .expect_op_postfix_or_infix, .closing_token = .right_paren });
                        },
                        .identifier => {
                            var node = try Node.init(alloc, .literal_identifier, .literal);
                            node.data.literal = p.token.sliceFrom(p.tokenizer.input);
                            try p.pending.operands.append(alloc, node);
                            p.state = .expect_op_postfix_or_infix;
                        },
                        .number => {
                            var node = try Node.init(alloc, .literal_number, .literal);
                            node.data.literal = p.token.sliceFrom(p.tokenizer.input);
                            try p.pending.operands.append(alloc, node);
                            p.state = .expect_op_postfix_or_infix;
                        },

                        .keyword_for => {
                            p.state = .expect_past_for;
                        },
                        .dot => {
                            p.state = .expect_past_dot;
                        },
                        .minus => { // add jump to a state instead (to limit the space of next valid tokens)
                            try p.pending.operators.append(alloc, .op_arith_neg);
                        },

                        // invalid states:
                        .invalid => {
                            return Error.InvalidToken;
                        }, // TODO utilize
                        else => {
                            // Provide additional error context
                            // switch (token.tag) {
                            // .right_paren => {},
                            // }
                            return Error.UnexpectedToken;
                        },
                    }
                },

                .expect_op_postfix_or_infix => {
                    switch (p.token.tag) {
                        .eof => break,
                        // .newline => p.state = .end_parse_scope,

                        inline .plus,
                        .minus,
                        .asterisk,
                        .slash,
                        .caret,
                        => |tag| {
                            const operator = switch (tag) {
                                .plus => .op_arith_add,
                                .minus => .op_arith_sub,
                                .asterisk => .op_arith_mul,
                                .slash => .op_arith_div,
                                .caret => .op_arith_exp,
                                else => unreachable,
                            };
                            try p.pending.resolveAllIfPrecedenceIsHigher(alloc, operator);
                            try p.pending.operators.append(alloc, operator);
                            p.state = .expect_literal_or_op_prefix;
                        },

                        inline .comma,
                        .pipe,
                        => |tag| {
                            const operator = switch (tag) {
                                .comma => .op_enum_and,
                                .pipe => .op_enum_or,
                                else => unreachable,
                            };
                            try p.pending.resolveAllIfPrecedenceIsHigher(alloc, operator);
                            if (p.pending.operators.getLastOrNull() == operator) {
                                try p.pending.resolveOnce(alloc);
                            }
                            try p.pending.operators.append(alloc, operator);
                            p.state = .expect_literal_or_op_prefix;
                        },

                        .right_square,
                        .right_paren,
                        .right_curly,
                        => |bracket| {
                            if (p.pending.scope.popOrNull()) |pending| {
                                if (pending.closing_token != bracket) {
                                    return Error.UnbalancedClosingBracket;
                                }
                                try p.pending.resolveAllUntil(alloc, .op_scope);
                                p.state = pending.state;
                            } else {
                                return Error.UnexpectedToken;
                            }
                        },

                        else => {
                            return Error.UnexpectedToken;
                        },
                    }
                },

                .expect_indentation => {
                    // token = p.tokenizer.nextFrom(.space);
                    if (p.token.tag == .space) {
                        if (p.indent.size == 0) {
                            p.indent.size = @intCast(p.token.len());
                        }
                        // check depth integrity
                    }
                    p.state = .expect_literal_or_op_prefix;
                    // continue;
                },

                // control structure states
                .expect_past_for => {
                    if (p.token.tag != .left_paren) {
                        return Error.UnexpectedToken;
                    }

                    const node = try Node.init(alloc, .op_ctrl_for, .map);
                    try p.pending.operands.append(alloc, node);

                    try p.pending.operators.append(alloc, .op_scope);
                    try p.pending.scope.append(alloc, .{ .state = .expect_past_for_condition, .closing_token = .right_paren });
                    p.state = .expect_literal_or_op_prefix;
                },

                .expect_past_for_condition => {
                    // try p.pending.operators.append(alloc, .op_ctrl_for_body);
                    try p.pending.resolveAs(alloc, .op_ctrl_for_cnd);
                    try p.pending.operators.append(alloc, .op_ctrl_for_body);
                    p.state = .expect_literal_or_op_prefix;
                    continue;
                },

                // node processing states
                .expect_past_dot => {
                    const node = try Node.init(alloc, .op_node, .map);
                    try p.pending.operands.append(alloc, node);

                    switch (p.token.tag) {
                        .identifier => {
                            var literal = try Node.init(alloc, .literal_identifier, .literal);
                            literal.data.literal = p.token.sliceFrom(p.tokenizer.input);
                            try p.pending.operands.append(alloc, literal);

                            try p.pending.resolveAs(alloc, .op_node_name);
                            p.state = .expect_past_dot_id;
                        },
                        else => {
                            return Error.UnexpectedToken;
                        },
                    }
                },
                .expect_past_dot_id => {
                    switch (p.token.tag) {
                        .left_square => {
                            try p.pending.operators.append(alloc, .op_scope);
                            try p.pending.scope.append(alloc, .{ .state = .expect_past_dot_id_attr, .closing_token = .right_square });

                            p.state = .expect_literal_or_op_prefix;
                        },
                        .equal => {
                            try p.pending.operators.append(alloc, .op_node_value);
                            p.state = .expect_literal_or_op_prefix;
                        },
                        else => {
                            p.state = .expect_op_postfix_or_infix;
                            continue;
                        },
                    }
                },
                .expect_past_dot_id_attr => {
                    try p.pending.resolveAs(alloc, .op_node_attr);
                    switch (p.token.tag) {
                        .equal => {
                            try p.pending.operators.append(alloc, .op_node_value);
                            p.state = .expect_literal_or_op_prefix;
                        },
                        else => {
                            p.state = .expect_op_postfix_or_infix;
                            continue;
                        },
                    }
                },

                // else => return error.UnexpectedState,
            }
            p.token = p.tokenizer.next();
        }

        try p.pending.resolveAll(alloc);

        return p.pending.operands.popOrNull();
    }

    pub fn parseFromInput(alloc: std.mem.Allocator, input: [:0]const u8) !?*Node {
        var p = Parser.init(input);
        return p.parse(alloc, .expect_leading_space);
    }

    pub fn errMessage(p: *Parser, alloc: std.mem.Allocator) ![]u8 {
        if (p.err) |err| {
            return switch (err) {
                .UnbalancedOperandStack => {
                    std.fmt.allocPrint(alloc, "Invalid token {s}: {}", .{ err.token.sliceFrom(p.tokenizer.input), err.token.loc });
                },
            };
        }
    }

    fn printStacks(p: *Parser, alloc: std.mem.Allocator) !void {
        var out = std.ArrayList(u8).init(alloc);
        const operators = p.pending.operators.items;
        const operands = p.pending.operands.items;
        const scopes = p.pending.scope.items;

        var i: usize = @max(scopes.len, @max(operands.len, operators.len)) -| 1;
        const l1 = 16;
        const l2 = 16;
        const l3 = 18;
        while (true) : (i -= 1) { // zip print
            const operand = if (i >= operands.len) "" else blk: {
                const name = @tagName(operands[i].tag);
                break :blk if (name.len > l1) name[0 .. l1 - 2] ++ ".." else name;
            };

            const operator = if (i >= operators.len) "" else blk: {
                const name = @tagName(operators[i]);
                break :blk if (name.len > l2) name[0 .. l2 - 2] ++ ".." else name;
            };

            const state = if (i >= scopes.len) "" else blk: {
                const name = @tagName(scopes[i].state)[7..];
                break :blk if (name.len > l3) name[0 .. l3 - 2] ++ ".." else name;
            };

            const bracket = if (i >= scopes.len) "   " else blk: {
                break :blk switch (scopes[i].closing_token) {
                    .right_paren => "')'",
                    .right_curly => "'}'",
                    .right_square => "']'",
                    else => unreachable,
                };
            };

            try out.writer().print("|{s: <16}| |{s: <16}| |{s: <18} {s}|\n", .{ operand, operator, state, bracket });

            if (i == 0) break;
        }
        const sep = ("-" ** (l1 + l2 + l3 + 11)) ++ "\n";

        const stderr = std.io.getStdErr().writer();
        var bw = std.io.bufferedWriter(stderr);
        bw.writer().print("\n{s}", .{@tagName(p.state)}) catch return;
        bw.writer().print("\n{s}" ++ sep, .{out.items}) catch return;
        bw.flush() catch return;
    }
};

pub fn renderDebugTree(alloc: std.mem.Allocator, tree: ?*Node, lvl: usize) ![]u8 {
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
                const rhs = try renderDebugTree(alloc, elm, (lvl + 1));
                try out.appendSlice(rhs);
            },
            .pair => |pair| {
                // `\n` + recursion
                try out.append('\n');
                const lhs = try renderDebugTree(alloc, pair.left, (lvl + 1));
                try out.appendSlice(lhs);
                const rhs = try renderDebugTree(alloc, pair.right, (lvl + 1));
                try out.appendSlice(rhs);
            },
            .list => |list| {
                // `\n` + recursion
                try out.append('\n');
                for (list.items) |item| {
                    const res = try renderDebugTree(alloc, item, (lvl + 1));
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
                    const rhs = try renderDebugTree(alloc, entry.value_ptr.*, (lvl + 2));
                    try out.appendSlice(rhs);
                }
            },
        }
        return out.toOwnedSlice();
    }
    return "";
}

test "Parser" {
    const t = std.testing;

    const case = struct {
        fn run(input: [:0]const u8, expect: [:0]const u8) !void {
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();

            const node = try Parser.parseFromInput(arena.allocator(), input);
            const res = try renderDebugTree(arena.allocator(), node, 0);
            try t.expectEqualStrings(expect, res[0..res.len -| 1]); // ignore trailing \n
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
        \\    .op_enum_or
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
        \\    .op_enum_and
        \\      .literal_identifier -> "attr1"
        \\      .literal_identifier -> "attr2"
    );
}
