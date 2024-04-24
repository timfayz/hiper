// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

const std = @import("std");
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const Token = @import("tokenizer.zig").Token;
const List = std.ArrayListUnmanaged;
const Map = std.StringHashMapUnmanaged;
const print = std.debug.print;
const assert = std.debug.assert;

pub const Node = struct {
    tag: Tag,
    data: union(enum) {
        num: u64,
        flt: f64,
        str: []const u8,
        arr: List(*Node),
        map: Map(*Node),
    },

    pub fn init(alloc: std.mem.Allocator, tag: Tag) !*Node {
        var new = try alloc.create(Node);
        new.tag = tag;
        switch (tag) {
            .number => {
                new.data = .{ .str = undefined };
            },
            .op_add,
            .op_sub,
            .op_mul,
            .op_div,
            .op_exp,
            => {
                new.data = .{ .arr = List(*Node){} };
            },
            .keyword_for => {
                new.data = .{ .map = Map(*Node){} };
            },
            else => {},
        }
        return new;
    }

    pub const Tag = enum(u4) {
        // operands
        number,
        identifier,

        // operators
        // classic infix operators
        op_add,
        op_sub,
        op_mul,
        op_div,
        op_exp,
        // classic prefix keyword statements
        keyword_for,
        keyword_while,
        keyword_if,

        pub fn fromToken(token: Token) Tag {
            return switch (token.tag) {
                .plus => .op_add,
                .minus => .op_sub,
                .asterisk => .op_mul,
                .slash => .op_div,
                .caret => .op_exp,
                else => unreachable,
            };
        }

        pub inline fn isOperator(node_tag: Tag) bool {
            return @intFromEnum(node_tag) >= @intFromEnum(Tag.op_add) and
                @intFromEnum(node_tag) <= @intFromEnum(Tag.op_exp);
        }

        pub inline fn isStatement(node_tag: Tag) bool {
            return @intFromEnum(node_tag) >= @intFromEnum(Tag.keyword_for) and
                @intFromEnum(node_tag) <= @intFromEnum(Tag.keyword_if);
        }

        inline fn isLeftAssociate(node_tag: Tag) bool {
            return if (node_tag == .op_exp) false else true;
        }

        inline fn precedence(node_tag: Tag) std.meta.Tag(Tag) {
            return precedence_table[@intFromEnum(node_tag)];
        }

        const precedence_table = blk: {
            const enum_tag = std.meta.Tag(Tag);
            const enum_size = std.meta.fields(Tag).len;
            var table = [1]enum_tag{0} ** enum_size;
            table[@intFromEnum(Tag.op_add)] = 1;
            table[@intFromEnum(Tag.op_sub)] = 1;
            table[@intFromEnum(Tag.op_mul)] = 2;
            table[@intFromEnum(Tag.op_div)] = 2;
            table[@intFromEnum(Tag.op_exp)] = 3;
            table[@intFromEnum(Tag.keyword_for)] = 7;
            table[@intFromEnum(Tag.keyword_if)] = 7;
            break :blk table;
        };
    };

    pub fn dump(node: *Node, alloc: std.mem.Allocator, lvl: usize) ![]u8 {
        var out = std.ArrayList(u8).init(alloc);
        var ow = out.writer();
        const indent_size = 3;
        try out.appendNTimes(' ', indent_size * lvl);
        try ow.print("[{s}]", .{@tagName(node.tag)});
        switch (node.data) {
            .arr => |arr| {
                try out.append('\n');
                for (arr.items) |item| {
                    const res = try dump(item, alloc, (lvl + 1));
                    try out.appendSlice(res);
                }
            },
            .str => |str| {
                try ow.print(":\"{s}\"\n", .{str});
            },
            .map => |map| {
                try out.append('\n');
                var iter = map.iterator();
                while (iter.next()) |entry| {
                    try out.appendNTimes(' ', indent_size * (lvl + 1));
                    try ow.print("\"{s}\":[{s}]\n", .{ entry.key_ptr.*, @tagName(entry.value_ptr.*.tag) });
                }
            },
            else => {
                try out.append('\n');
            },
        }
        return out.toOwnedSlice();
    }
};

pub const Parser = struct {
    alloc: std.mem.Allocator,
    input: []const u8,
    scan: Tokenizer(.{}),
    token: Token,
    indent: IndentInfo = .{},

    pub const State = enum {
        expect_first_leading_space,
        expect_indentation,
        expect_operand,
        expect_operator,
    };

    pub const Error = error{
        InvalidOperandStack,
        InternalError,
        UnexpectedToken,
    };

    const IndentInfo = struct {
        //---code   (leading == 3)
        //---++code (indentation == 2)
        size: usize = 0, // indentation size
        lead_size: usize = 0, // leading space size before indentation (for trimming)
    };

    pub fn init(alloc: std.mem.Allocator, input: [:0]const u8) Parser {
        return Parser{
            .alloc = alloc,
            .input = input,
            .scan = Tokenizer(.{}).init(input),
            .token = undefined,
        };
    }

    pub const Pending = struct {
        operands: List(*Node) = .{},
        operators: List(*Node) = .{},

        pub fn resolveIfHigherPrecedence(p: *Pending, alloc: std.mem.Allocator, operator: Node.Tag) !void {
            while (p.operators.getLastOrNull()) |node| {
                const pending = node.tag;
                if (operator.precedence() < pending.precedence() // (1 * 2) + [..]
                or (operator.precedence() == pending.precedence() and operator.isLeftAssociate())) // (1 + 2) + [..]
                {
                    try p.resolveOperators(alloc);
                } else {
                    break;
                }
            }
        }

        pub fn resolveOperators(p: *Pending, alloc: std.mem.Allocator) !void {
            if (p.operators.popOrNull()) |node| {
                if (node.tag.isOperator()) {
                    if (p.operands.items.len < 2) return Parser.Error.InvalidOperandStack;
                    node.data.arr.items[1] = p.operands.pop(); // right
                    node.data.arr.items[0] = p.operands.pop(); // left
                    try p.operands.append(alloc, node);
                } else {
                    return Error.InternalError;
                }
            }
        }
    };

    pub fn parse(p: *Parser, from: State) !*Node {
        var pending = Pending{};
        p.token = p.scan.next();
        var state = from;
        while (true) {
            switch (state) {
                .expect_first_leading_space => {
                    switch (p.token.tag) {
                        .space => {
                            if (p.scan.peekByte() != '\n') {
                                p.indent.lead_size = p.token.len();
                                state = .expect_operand;
                                continue;
                            }
                        },
                        .newline => {},
                        else => {
                            state = .expect_operand;
                            continue; // lead_size == 0
                        },
                    }
                },
                .expect_indentation => {
                    if (p.token.tag == .space) {
                        if (p.indent.size == 0) {
                            p.indent.size = p.token.len();
                        }
                        // check depth integrity
                    }
                    state = .expect_operand;
                    continue;
                },
                .expect_operand => {
                    switch (p.token.tag) {
                        .eof => break,
                        .space => {},
                        .newline => {
                            state = .expect_indentation;
                        },
                        .number => {
                            const node = try Node.init(p.alloc, .number);
                            node.data.str = p.token.slice(p.input);
                            try pending.operands.append(p.alloc, node);
                            state = .expect_operator;
                        },
                        .keyword_for => {
                            p.token = p.scan.next(); // 'for'
                            if (p.token.tag == .space) p.token = p.scan.next(); // ' '
                            // retrieve condition
                            if (p.token.tag != .l_paren) return Error.UnexpectedToken; // '('
                            const condition_node = try p.parse(.expect_operand); // condition
                            if (p.token.tag != .r_paren) return Error.UnexpectedToken; // ')'
                            // retrieve body
                            const body = try p.parse(.expect_operand); // body
                            // populate node
                            const node = try Node.init(p.alloc, .keyword_for);
                            try node.data.map.put(p.alloc, "condition", condition_node);
                            try node.data.map.put(p.alloc, "body", body);
                            // push on stack
                            try pending.operands.append(p.alloc, node);
                            // continue
                        },
                        else => {
                            std.log.err("Expected operand, got: {any}\n", .{p.token});
                            return Error.UnexpectedToken;
                        },
                    }
                },
                .expect_operator => {
                    switch (p.token.tag) {
                        .eof => break,
                        .space => {},
                        .newline => {
                            state = .expect_indentation;
                        },
                        .plus,
                        .minus,
                        .asterisk,
                        .caret,
                        .comma,
                        => {
                            const operator = Node.Tag.fromToken(p.token);
                            try pending.resolveIfHigherPrecedence(p.alloc, operator);
                            const node = try Node.init(p.alloc, operator);
                            try node.data.arr.resize(p.alloc, 2);
                            try pending.operators.append(p.alloc, node);
                            state = .expect_operand;
                        },
                        else => break,
                    }
                },
                // else => break,
            }
            p.token = p.scan.next();
        }

        while (pending.operators.items.len > 0) {
            try pending.resolveOperators(p.alloc);
        }

        return pending.operands.pop();
    }

    pub fn parseFromInput(alloc: std.mem.Allocator, input: [:0]const u8) !*Node {
        var p = Parser.init(alloc, input);
        return p.parse(.expect_first_leading_space);
    }
};

test "parser" {
    const t = std.testing;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();
    const input = "1 + 2 * 3 ^ 4 - for (5) 6";
    const root = try Parser.parseFromInput(alloc, input);
    const res = try root.dump(alloc, 0);
    defer alloc.free(res);
    try t.expectEqualStrings(
        \\[op_sub]
        \\   [op_add]
        \\      [number]:"1"
        \\      [op_mul]
        \\         [number]:"2"
        \\         [op_exp]
        \\            [number]:"3"
        \\            [number]:"4"
        \\   [keyword_for]
        \\      "condition":[number]
        \\      "body":[number]
        \\
    , res);
}
