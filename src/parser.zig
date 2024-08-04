// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

const std = @import("std");
const ThisFile = @This();
pub const List = std.ArrayListUnmanaged;
pub const Map = std.StringHashMapUnmanaged;

pub const Node = struct {
    tag: Tag,
    data: Data,

    /// Underlying node representation.
    pub const Data = union(enum) {
        void: void,
        token: Token,
        single: *Node,
        pair: struct { left: *Node, right: *Node },
        list: List(*Node),
        map: Map(*Node),

        pub const Tag = std.meta.Tag(Data);
    };

    pub const Tag = enum(u5) {
        // primitives
        literal_number,
        literal_string,
        literal_identifier,

        // aggregation
        enum_and,
        enum_or,

        // arithmetics
        arith_add,
        arith_sub,
        arith_mul,
        arith_div,
        arith_exp,
        arith_neg,

        // abstraction
        dot,

        // control
        ctrl_for,
        ctrl_while,
        ctrl_if,

        // pseudo
        assign_equal,
        assign_indent,
        scope,
        scope_body,
        scope_cond,
        scope_attr,
        scope_name,

        pub fn dataTag(node_tag: Tag) Data.Tag {
            return switch (node_tag) {
                .literal_number,
                .literal_string,
                .literal_identifier,
                => .token,

                .arith_neg,
                => .single,

                .arith_add,
                .arith_sub,
                .arith_mul,
                .arith_div,
                .arith_exp,
                => .pair,

                .enum_and,
                .enum_or,
                => .list,

                .dot,
                .ctrl_for,
                .ctrl_while,
                .ctrl_if,
                => .map,

                // has no data representation
                .scope,
                .scope_body,
                .scope_cond,
                .assign_equal,
                .assign_indent,
                .scope_attr,
                .scope_name,
                => .void,
            };
        }

        pub fn keyName(node_tag: Tag) []const u8 {
            return switch (node_tag) {
                .scope_body => "body",
                .scope_cond => "cond",
                .assign_equal => "val",
                .assign_indent => "val",
                .scope_attr => "attr",
                .scope_name => "name",
                else => unreachable,
            };
        }

        /// If there are two identical operators in a sequence, right
        /// associativity means that the operator on the right is applied first.
        /// Right associative: `1 + 2 + 3` –› `(1 + (2 + 3))`.
        /// Left associative: `1 + 2 + 3` –› `((1 + 2) + 3)`.
        pub inline fn isRightAssociative(node_tag: Tag) bool {
            return if (node_tag.precedence() == 0 or node_tag == .arith_exp) true else false;
        }

        pub inline fn precedence(node_tag: Tag) std.meta.Tag(Tag) {
            return precedence_table[@intFromEnum(node_tag)];
        }

        /// The precedence of operators is defined here.
        const precedence_table = blk: {
            const Tags_size = std.meta.Tag(Tag); // u5
            const tags_len = std.meta.fields(Tag).len;
            var table = [1]Tags_size{0} ** tags_len; // 0 for all, except:
            table[@intFromEnum(Tag.arith_add)] = 1;
            table[@intFromEnum(Tag.arith_sub)] = 1;
            table[@intFromEnum(Tag.arith_mul)] = 2;
            table[@intFromEnum(Tag.arith_div)] = 2;
            table[@intFromEnum(Tag.arith_exp)] = 3;
            table[@intFromEnum(Tag.arith_neg)] = 7;
            break :blk table;
        };

        pub inline fn isOperator(node_tag: Tag) bool {
            return @intFromEnum(node_tag) >= @intFromEnum(Tag.arith_add) and
                @intFromEnum(node_tag) <= @intFromEnum(Tag.arith_exp);
        }
    };

    pub fn init(alloc: std.mem.Allocator, tag: Tag) !*Node {
        const node = try alloc.create(Node);
        node.tag = tag;
        node.data = switch (tag.dataTag()) {
            .void => .{ .void = {} },
            .token => .{ .token = undefined },
            .single => .{ .single = undefined },
            .pair => .{ .pair = .{ .left = undefined, .right = undefined } },
            .list => .{ .list = List(*Node){} },
            .map => .{ .map = Map(*Node){} },
        };
        return node;
    }
};

const Token = @import("tokenizer.zig").Token;
const Tokenizer = @import("tokenizer.zig").Tokenizer(
    .{
        .tokenize_spaces = false,
        .tokenize_indents = true,
    },
);

pub const Parser = struct {
    tokenizer: Tokenizer, // input
    token: Token = undefined, // cursor
    indent: Indent = .{},
    pending: Pending = .{},
    state: State = .parse_first_indent,

    pub const Indent = struct {
        trim_size: u16 = 0, // --code    (--  lead size before indentation = 2)
        size: u16 = 0, //      --+++code (+++ indentation size = 3)
        level: u16 = 0, //     --+++code (indent level = 1; starts from 0)

        pub fn isIncreased(indent: *Indent, indent_size: usize) !bool {
            // std.log.err("indent_size: {}", .{indent_size});
            // std.log.err("last_indent_level: {}", .{last_indent_level});
            // std.log.err("current p.indent.level: {}", .{p.indent.level});
            const last_indent_level = indent.level;
            const new_indent_size: u16 = @intCast(indent_size);

            if (new_indent_size > 0) {
                if (indent.size == 0) { // initialize indent size
                    indent.size = new_indent_size;
                    indent.level = 1;
                } else { // already initialized
                    if (new_indent_size % indent.size != 0) {
                        // assert proper alignment
                        return Error.UnalignedIndentSize;
                    } else if (new_indent_size > indent.size * (indent.level + 1)) {
                        // assert proper nesting (same or +1)
                        return Error.IndentationTooDeep;
                    } else {
                        // update current level
                        indent.level = new_indent_size / indent.size;
                    }
                }
            }

            return indent.level > last_indent_level;
        }
    };

    pub const State = enum {
        parse_first_indent,

        parser_prefix,
        parse_postfix,

        parse_past_for,
        parse_past_for_condition,

        parse_past_dot,
        parse_past_dot_id,
        parse_past_dot_id_attr,
    };

    pub const Error = error{
        SyntaxDoubleAssignment,
        OutOfMemory,
        InvalidToken,
        InvalidOperandStack1,
        InvalidOperandStack2,
        UnalignedIndentSize,
        IndentationTooDeep,
        UnexpectedToken,
        UnreachableCode, // TODO temporarily?
        UnbalancedClosingBracket,
    };

    const Pending = struct {
        operands: List(*Node) = .{},
        operators: List(Node.Tag) = .{},
        scopes: List(struct { next_state: Parser.State, closing_token: Token.Tag }) = .{},

        pub inline fn pushScope(s: *Pending, alloc: std.mem.Allocator, next_state: Parser.State, closing_token: Token.Tag) Error!void {
            try s.operators.append(alloc, .scope);
            try s.scopes.append(alloc, .{ .next_state = next_state, .closing_token = closing_token });
        }

        pub inline fn pushOperand(s: *Pending, alloc: std.mem.Allocator, comptime op_tag: Node.Tag, token: ?Token) !void {
            log.action(@src().fn_name, @tagName(op_tag));
            const node = try Node.init(alloc, op_tag);
            if (token) |t| node.data.token = t;
            try s.operands.append(alloc, node);
        }

        pub inline fn pushOperator(s: *Pending, alloc: std.mem.Allocator, op_tag: Node.Tag) !void {
            log.action(@src().fn_name, @tagName(op_tag));
            try s.operators.append(alloc, op_tag);
        }

        pub inline fn resolveAllIfPrecedenceHigher(s: *Pending, alloc: std.mem.Allocator, op_tag: Node.Tag) Error!void {
            log.action(@src().fn_name, @tagName(op_tag));
            const current = op_tag;
            while (s.operators.getLastOrNull()) |pending| {
                if (pending.precedence() > current.precedence() or
                    (pending.precedence() == current.precedence() and !current.isRightAssociative()))
                {
                    try s.resolveOnce(alloc);
                } else break;
            }
        }

        pub inline fn resolveAllUntilIncluding(s: *Pending, alloc: std.mem.Allocator, op_tag: Node.Tag) Error!void {
            log.action(@src().fn_name, @tagName(op_tag));
            while (s.operators.popOrNull()) |operator| {
                try s.resolveAs(alloc, operator);
                if (operator == op_tag) break;
            }
        }

        pub inline fn resolveAllUntilExcluding(s: *Pending, alloc: std.mem.Allocator, op_tag: Node.Tag) Error!void {
            log.action(@src().fn_name, @tagName(op_tag));
            while (s.operators.getLastOrNull()) |operator| {
                if (operator == op_tag) break;
                const op = s.operators.pop();
                try s.resolveAs(alloc, op);
            }
        }

        pub inline fn resolveAll(s: *Pending, alloc: std.mem.Allocator) Error!void {
            log.action(@src().fn_name, "");
            while (s.operators.popOrNull()) |operator| {
                try s.resolveAs(alloc, operator);
            }
        }

        pub fn resolveOnce(s: *Pending, alloc: std.mem.Allocator) Error!void {
            log.action(@src().fn_name, "");
            if (s.operators.popOrNull()) |op_tag| {
                try s.resolveAs(alloc, op_tag);
            }
        }

        // pub fn resolveImmediateAs(s: *Stack, alloc: std.mem.Allocator, node: *Node, op_tag: Node.Tag) Error!void { }

        pub fn resolveAs(s: *Pending, alloc: std.mem.Allocator, op_tag: Node.Tag) Error!void {
            log.action(@src().fn_name, @tagName(op_tag));
            switch (op_tag) {
                // discarding operators
                .scope => {},

                // single-operand operators
                .arith_neg => {
                    if (s.operands.items.len < 1) return Error.InvalidOperandStack1;

                    var node = try Node.init(alloc, op_tag);
                    node.data.single = s.operands.pop();
                    try s.operands.append(alloc, node);
                },

                // two-operands operators
                .arith_add,
                .arith_div,
                .arith_exp,
                .arith_mul,
                .arith_sub,
                => {
                    if (s.operands.items.len < 2) return Error.InvalidOperandStack2;

                    var node = try Node.init(alloc, op_tag);
                    node.data.pair.right = s.operands.pop();
                    node.data.pair.left = s.operands.pop();
                    try s.operands.append(alloc, node);
                },

                // n-operands operators
                .enum_and,
                .enum_or,
                => {
                    if (s.operands.items.len < 2) return Error.InvalidOperandStack2;

                    const right = s.operands.pop();
                    const left = s.operands.pop();
                    if (left.data == .list) {
                        try left.data.list.append(alloc, right);
                        try s.operands.append(alloc, left);
                    } else {
                        var node = try Node.init(alloc, op_tag);
                        try node.data.list.append(alloc, left);
                        try node.data.list.append(alloc, right);
                        try s.operands.append(alloc, node);
                    }
                },

                // operands-mapping operators
                inline .scope_body,
                .scope_cond,
                .assign_equal,
                .assign_indent,
                .scope_attr,
                .scope_name,
                => |key| {
                    if (s.operands.items.len < 2) return Error.InvalidOperandStack2;

                    const val = s.operands.pop();
                    const node = s.operands.getLast();
                    try node.data.map.put(alloc, key.keyName(), val);
                },

                else => return Error.UnreachableCode,
            }
        }
    };

    pub fn init(input: [:0]const u8) Parser {
        return Parser{ .tokenizer = Tokenizer.init(input) };
    }

    pub fn parse(p: *Parser, alloc: std.mem.Allocator, from: State) Error!?*Node {
        p.token = p.tokenizer.nextFrom(.space);
        p.state = from;
        while (true) {
            log.cursor(p);
            switch (p.state) {
                // initialization state
                .parse_first_indent => {
                    if (p.token.tag == .indent) {
                        p.indent.trim_size = @intCast(p.token.len());
                        p.state = .parser_prefix;
                    } else {
                        p.state = .parser_prefix;
                        continue;
                    }
                },

                // main state
                .parser_prefix => {
                    switch (p.token.tag) {
                        .eof => break,
                        .left_paren => {
                            try p.pending.pushScope(alloc, .parse_postfix, .right_paren);
                        },
                        inline .number,
                        .identifier,
                        .string,
                        => |tag| {
                            const node_tag = comptime switch (tag) {
                                .number => .literal_number,
                                .identifier => .literal_identifier,
                                .string => .literal_string,
                                else => unreachable,
                            };
                            try p.pending.pushOperand(alloc, node_tag, p.token);
                            p.state = .parse_postfix;
                        },
                        .keyword_for => {
                            p.state = .parse_past_for;
                        },
                        .dot => {
                            p.state = .parse_past_dot;
                        },
                        .minus => {
                            try p.pending.pushOperator(alloc, .arith_neg);
                        },
                        else => return Error.UnexpectedToken,
                    }
                },

                .parse_postfix => {
                    switch (p.token.tag) {
                        .eof => break,
                        .indent => {
                            // assign (if indentation level increased)
                            if (try p.indent.isIncreased(p.token.len())) {
                                try p.pending.resolveAllUntilExcluding(alloc, .assign_equal);
                                if (p.pending.operators.getLastOrNull() == .assign_equal) {
                                    return Error.SyntaxDoubleAssignment;
                                }
                                try p.pending.pushOperator(alloc, .assign_indent);
                            }
                            // enumerate (if indentation is the same)
                            else {
                                try p.pending.resolveAllUntilExcluding(alloc, .assign_indent);
                                if (p.pending.operators.getLastOrNull() == .enum_and) {
                                    try p.pending.resolveOnce(alloc);
                                }
                                try p.pending.pushOperator(alloc, .enum_and);
                            }
                            try p.pending.pushOperator(alloc, .scope);
                            p.state = .parser_prefix;
                        },

                        inline .plus,
                        .minus,
                        .asterisk,
                        .slash,
                        .caret,
                        => |tag| {
                            const operator = switch (tag) {
                                .plus => .arith_add,
                                .minus => .arith_sub,
                                .asterisk => .arith_mul,
                                .slash => .arith_div,
                                .caret => .arith_exp,
                                else => unreachable,
                            };
                            try p.pending.resolveAllIfPrecedenceHigher(alloc, operator);
                            try p.pending.pushOperator(alloc, operator);
                            p.state = .parser_prefix;
                        },

                        inline .comma,
                        .pipe,
                        => |tag| {
                            const operator = switch (tag) {
                                .comma => .enum_and,
                                .pipe => .enum_or,
                                else => unreachable,
                            };
                            try p.pending.resolveAllIfPrecedenceHigher(alloc, operator);
                            if (p.pending.operators.getLastOrNull() == operator) {
                                try p.pending.resolveOnce(alloc);
                            }
                            try p.pending.pushOperator(alloc, operator);
                            p.state = .parser_prefix;
                        },

                        .semicolon => {
                            try p.pending.resolveAllUntilExcluding(alloc, .scope);
                            if (p.pending.operators.getLastOrNull() == .enum_and) {
                                try p.pending.resolveOnce(alloc);
                            }
                            try p.pending.pushOperator(alloc, .enum_and);
                            p.state = .parser_prefix;
                        },

                        .right_square,
                        .right_paren,
                        .right_curly,
                        => |bracket| {
                            if (p.pending.scopes.popOrNull()) |scope| {
                                if (scope.closing_token != bracket) {
                                    return Error.UnbalancedClosingBracket;
                                }
                                try p.pending.resolveAllUntilIncluding(alloc, .scope);
                                p.state = scope.next_state;
                            } else {
                                return Error.UnexpectedToken;
                            }
                        },

                        else => return Error.UnexpectedToken,
                    }
                },

                // control structure
                .parse_past_for => {
                    if (p.token.tag != .left_paren) {
                        return Error.UnexpectedToken;
                    }
                    try p.pending.pushOperand(alloc, .ctrl_for, null);
                    try p.pending.pushScope(alloc, .parse_past_for_condition, .right_paren);
                    p.state = .parser_prefix;
                },
                .parse_past_for_condition => {
                    try p.pending.resolveAs(alloc, .scope_cond);
                    try p.pending.pushOperator(alloc, .scope_body);
                    p.state = .parser_prefix;
                    continue;
                },

                // node processing
                .parse_past_dot => {
                    try p.pending.pushOperand(alloc, .dot, null);

                    switch (p.token.tag) {
                        .identifier => {
                            try p.pending.pushOperand(alloc, .literal_identifier, p.token);
                            try p.pending.resolveAs(alloc, .scope_name);
                            p.state = .parse_past_dot_id;
                        },
                        else => {
                            return Error.UnexpectedToken;
                        },
                    }
                },
                .parse_past_dot_id => {
                    switch (p.token.tag) {
                        .left_square => {
                            try p.pending.pushScope(alloc, .parse_past_dot_id_attr, .right_square);
                            p.state = .parser_prefix;
                        },
                        .equal => {
                            try p.pending.pushOperator(alloc, .assign_equal);
                            p.state = .parser_prefix;
                        },
                        else => {
                            p.state = .parse_postfix;
                            continue;
                        },
                    }
                },
                .parse_past_dot_id_attr => {
                    try p.pending.resolveAs(alloc, .scope_attr);
                    switch (p.token.tag) {
                        .equal => {
                            try p.pending.pushOperator(alloc, .assign_equal);
                            p.state = .parser_prefix;
                        },
                        else => {
                            p.state = .parse_postfix;
                            continue;
                        },
                    }
                },

                // else => return error.UnexpectedState,
            }
            log.stacks(p);
            p.token = p.tokenizer.next();
        }

        try p.pending.resolveAll(alloc);
        log.end();

        if (p.pending.operands.popOrNull()) |node| {
            return node;
        } else {
            if (p.token.tag != .eof)
                return Error.UnreachableCode;
            return null;
        }
    }

    /// Deprecated.
    pub fn parseFromInput(alloc: std.mem.Allocator, input: [:0]const u8) Error!?*Node {
        var p = Parser.init(input);
        return p.parse(alloc, .parse_first_indent);
    }

    pub fn at(p: *Parser, alloc: std.mem.Allocator) ![]u8 {
        _ = p; // autofix
        _ = alloc; // autofix
        // given params context {before, after} prints
        // 1 | abc abc abc abc␃
        //    ~~~^ ('\x22') | (end of string)
    }

    pub fn errMessage(p: *Parser, alloc: std.mem.Allocator, err: Error) ![]u8 {
        switch (err) {
            Error.UnexpectedToken => {
                return std.fmt.allocPrint(alloc, "unexpected token '{s}' (.{s})\n", .{
                    p.token.sliceFrom(p.tokenizer.input),
                    @tagName(p.token.tag),
                });
            },
            inline Error.InvalidOperandStack1,
            Error.InvalidOperandStack2,
            => |code| {
                const expected = switch (code) {
                    Error.InvalidOperandStack1 => 1,
                    Error.InvalidOperandStack2 => 2,
                    else => unreachable,
                };
                if (p.pending.operators.items.len == 0) {
                    return error.OperatorStackIsEmpty;
                }
                const operator = p.pending.operators.items[p.pending.operators.items.len -| 1];
                return std.fmt.allocPrint(alloc, "unexpected number of operands for .{s} operation (expected {d}, got {d})\n", .{
                    @tagName(operator),
                    expected,
                    p.pending.operands.items.len,
                });
            },
            else => {
                return std.fmt.allocPrint(alloc, "{s}\n", .{@errorName(err)});
            },
        }
    }
};

const log = struct {
    const _log = @import("utils/log.zig");
    const color = @import("utils/ansi_colors.zig");
    var scope = _log.scope(.parser, .{}){};
    const scopeActive = if (@hasDecl(ThisFile, "log_in_tests")) true else _log.scopeActive(.parser);

    pub fn stacks(p: *Parser) void {
        if (!scopeActive) return;
        const operators = p.pending.operators.items;
        const operands = p.pending.operands.items;
        const scopes = p.pending.scopes.items;

        // stacks width
        const op_len = 16;
        const od_len = 16;
        const sc_len = 18;
        var i: usize = @max(scopes.len, @max(operands.len, operators.len)) -| 1;

        // border
        const border = "+" ++ ("-" ** (op_len + od_len + sc_len + 8)) ++ "+";

        scope.print("{s}\n", .{border}) catch return;
        while (true) : (i -= 1) { // zip print
            const operand = if (i >= operands.len) "" else blk: {
                const name = @tagName(operands[i].tag);
                break :blk if (name.len > op_len) name[0 .. op_len - 2] ++ ".." else name;
            };

            const operator = if (i >= operators.len) "" else blk: {
                const name = @tagName(operators[i]);
                break :blk if (name.len > od_len) name[0 .. od_len - 2] ++ ".." else name;
            };

            const st = if (i >= scopes.len) "" else blk: {
                const name = @tagName(scopes[i].next_state)[0..];
                break :blk if (name.len > sc_len) name[0 .. sc_len - 2] ++ ".." else name;
            };

            const bracket = if (i >= scopes.len) "" else blk: {
                break :blk switch (scopes[i].closing_token) {
                    .right_paren => ")",
                    .right_curly => "}",
                    .right_square => "]",
                    else => unreachable,
                };
            };

            scope.print("|{s: <16}| |{s: <16}| |{s: <18}{s: >2}|\n", .{ operand, operator, st, bracket }) catch return;

            if (i == 0) break;
        }
        scope.print("{s}\n", .{border}) catch return;
    }

    pub fn cursor(p: *Parser) void {
        if (!scopeActive) return;
        scope.print("[state:  " ++ color.ctEscape(.{.bold}, "{s}") ++ " at .{s}]\n", .{ @tagName(p.state), @tagName(p.token.tag) }) catch return;
    }

    pub fn action(name: []const u8, arg: []const u8) void {
        if (!scopeActive) return;
        if (arg.len == 0)
            scope.print("[action: {s}]\n", .{name}) catch return
        else
            scope.print("[action: {s} .{s}]\n", .{ name, arg }) catch return;
    }

    pub fn end() void {
        if (!scopeActive) return;
        scope.print("[end]\n", .{}) catch return;
    }
};

// const log_in_tests = true;

test "Parser" {
    const writer = @import("writer.zig");

    const case = struct {
        fn run(input: [:0]const u8, expect: [:0]const u8) !void {
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();

            const root = try Parser.parseFromInput(arena.allocator(), input);
            const res = try writer.writeDebugTree(arena.allocator(), input, root, 0);
            try std.testing.expectEqualStrings(expect, res[0..res.len -| 1]); // ignore trailing \n
        }
    };

    try case.run("1",
        \\.literal_number -> "1"
    );

    try case.run("1, 2",
        \\.enum_and
        \\  .literal_number -> "1"
        \\  .literal_number -> "2"
    );

    try case.run("1 + 2",
        \\.arith_add
        \\  .literal_number -> "1"
        \\  .literal_number -> "2"
    );

    try case.run("1 + 2 * 3 ^ 4 - 5",
        \\.arith_sub
        \\  .arith_add
        \\    .literal_number -> "1"
        \\    .arith_mul
        \\      .literal_number -> "2"
        \\      .arith_exp
        \\        .literal_number -> "3"
        \\        .literal_number -> "4"
        \\  .literal_number -> "5"
    );

    try case.run("(1 + 2) * 3 ^ -(4 - 5)",
        \\.arith_mul
        \\  .arith_add
        \\    .literal_number -> "1"
        \\    .literal_number -> "2"
        \\  .arith_exp
        \\    .literal_number -> "3"
        \\    .arith_neg
        \\      .arith_sub
        \\        .literal_number -> "4"
        \\        .literal_number -> "5"
    );

    try case.run("for (x) 1 + 2 | 3",
        \\.ctrl_for
        \\  "cond":
        \\    .literal_identifier -> "x"
        \\  "body":
        \\    .enum_or
        \\      .arith_add
        \\        .literal_number -> "1"
        \\        .literal_number -> "2"
        \\      .literal_number -> "3"
    );

    try case.run(".name [attr1, attr2] = 3",
        \\.dot
        \\  "name":
        \\    .literal_identifier -> "name"
        \\  "val":
        \\    .literal_number -> "3"
        \\  "attr":
        \\    .enum_and
        \\      .literal_identifier -> "attr1"
        \\      .literal_identifier -> "attr2"
    );

    try case.run(".name [.attr1 = 1; .attr2 = 2] = 3",
        \\.dot
        \\  "name":
        \\    .literal_identifier -> "name"
        \\  "val":
        \\    .literal_number -> "3"
        \\  "attr":
        \\    .enum_and
        \\      .dot
        \\        "name":
        \\          .literal_identifier -> "attr1"
        \\        "val":
        \\          .literal_number -> "1"
        \\      .dot
        \\        "name":
        \\          .literal_identifier -> "attr2"
        \\        "val":
        \\          .literal_number -> "2"
    );

    try case.run(
        \\.a
        \\  1
        \\  2
        \\  3
    ,
        \\.dot
        \\  "name":
        \\    .literal_identifier -> "a"
        \\  "val":
        \\    .enum_and
        \\      .literal_number -> "1"
        \\      .literal_number -> "2"
        \\      .literal_number -> "3"
    );

    try case.run(
        \\.div [.width = 100]
        \\  .h1 = 0o755
        \\  .p = .span = "hello world"
        \\  .h2 = 0x103.70p-5
    ,
        \\.dot
        \\  "name":
        \\    .literal_identifier -> "div"
        \\  "val":
        \\    .enum_and
        \\      .dot
        \\        "name":
        \\          .literal_identifier -> "h1"
        \\        "val":
        \\          .literal_number -> "0o755"
        \\      .dot
        \\        "name":
        \\          .literal_identifier -> "p"
        \\        "val":
        \\          .dot
        \\            "name":
        \\              .literal_identifier -> "span"
        \\            "val":
        \\              .literal_string -> ""hello world""
        \\      .dot
        \\        "name":
        \\          .literal_identifier -> "h2"
        \\        "val":
        \\          .literal_number -> "0x103.70p-5"
        \\  "attr":
        \\    .dot
        \\      "name":
        \\        .literal_identifier -> "width"
        \\      "val":
        \\        .literal_number -> "100"
    );
}
