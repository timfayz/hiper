// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

const std = @import("std");
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const Token = @import("tokenizer.zig").Token;
const print = std.debug.print;
const assert = std.debug.assert;

// Node representation structures
pub const Literal = []const u8;
pub const Pair = struct { left: *Node, right: *Node };
pub const List = std.ArrayListUnmanaged;
pub const Map = std.StringHashMapUnmanaged;

pub const Node = struct {
    tag: Tag,
    repr: union(RTag) {
        literal: []const u8,
        pair: struct { left: ?*Node, right: ?*Node },
        list: List(*Node),
        map: Map(*Node),
    },

    pub const RTag = enum { literal, pair, list, map };

    pub fn init(alloc: std.mem.Allocator, tag: Tag, repr: RTag) !*Node {
        var node = try alloc.create(Node);
        node.tag = tag;
        switch (repr) {
            .literal => node.repr = .{ .literal = &[_]u8{} },
            .pair => node.repr = .{ .pair = .{ .left = null, .right = null } },
            .list => node.repr = .{ .list = List(*Node){} },
            .map => node.repr = .{ .map = Map(*Node){} },
        }
        return node;
    }

    pub const Tag = enum(u4) {
        // operands
        number,
        identifier,
        list,
        map,

        // operators
        // classic infix operators
        bin_add,
        bin_sub,
        bin_mul,
        bin_div,
        bin_exp,
        // classic prefix keyword statements
        ctrl_for,
        ctrl_while,
        ctrl_if,

        pub fn fromToken(token: Token) Tag {
            return switch (token.tag) {
                .plus => .bin_add,
                .minus => .bin_sub,
                .asterisk => .bin_mul,
                .slash => .bin_div,
                .caret => .bin_exp,
                else => unreachable,
            };
        }

        pub inline fn isOperator(node_tag: Tag) bool {
            return @intFromEnum(node_tag) >= @intFromEnum(Tag.bin_add) and
                @intFromEnum(node_tag) <= @intFromEnum(Tag.bin_exp);
        }

        pub inline fn isStatement(node_tag: Tag) bool {
            return @intFromEnum(node_tag) >= @intFromEnum(Tag.ctrl_for) and
                @intFromEnum(node_tag) <= @intFromEnum(Tag.ctrl_if);
        }

        inline fn isLeftAssociate(node_tag: Tag) bool {
            return if (node_tag == .bin_exp) false else true;
        }

        inline fn precedence(node_tag: Tag) std.meta.Tag(Tag) {
            return precedence_table[@intFromEnum(node_tag)];
        }

        const precedence_table = blk: {
            const enum_tag = std.meta.Tag(Tag);
            const enum_size = std.meta.fields(Tag).len;
            var table = [1]enum_tag{0} ** enum_size;
            table[@intFromEnum(Tag.bin_add)] = 1;
            table[@intFromEnum(Tag.bin_sub)] = 1;
            table[@intFromEnum(Tag.bin_mul)] = 2;
            table[@intFromEnum(Tag.bin_div)] = 2;
            table[@intFromEnum(Tag.bin_exp)] = 3;
            table[@intFromEnum(Tag.ctrl_for)] = 7;
            table[@intFromEnum(Tag.ctrl_if)] = 7;
            table[@intFromEnum(Tag.ctrl_while)] = 7;
            break :blk table;
        };
    };

    pub fn dump(node: *Node, alloc: std.mem.Allocator, lvl: usize) ![]u8 {
        var out = std.ArrayList(u8).init(alloc);
        var ow = out.writer();
        const indent_size = 3;
        try out.appendNTimes(' ', indent_size * lvl);
        try ow.print("[{s}]", .{@tagName(node.tag)});
        switch (node.repr) {
            .literal => |token| {
                try ow.print(":\"{s}\"\n", .{token});
            },
            .pair => |pair| {
                try out.append('\n');
                const lhs = try dump(pair.left.?, alloc, (lvl + 1));
                try out.appendSlice(lhs);
                const rhs = try dump(pair.right.?, alloc, (lvl + 1));
                try out.appendSlice(rhs);
            },
            .list => |list| {
                try out.append('\n');
                for (list.items) |item| {
                    const res = try dump(item, alloc, (lvl + 1));
                    try out.appendSlice(res);
                }
            },
            .map => |map| {
                try out.append('\n');
                var iter = map.iterator();
                while (iter.next()) |entry| {
                    try out.appendNTimes(' ', indent_size * (lvl + 1));
                    try ow.print("\"{s}\":[{s}]\n", .{ entry.key_ptr.*, @tagName(entry.value_ptr.*.tag) });
                }
            },
            // else => try out.append('\n'),
        }
        return out.toOwnedSlice();
    }
};

pub fn log(state: Parser.State) @TypeOf(state) {
    // printStderr("state: .{s}\n", .{@tagName(state)});
    return state;
}

pub const Parser = struct {
    alloc: std.mem.Allocator,
    input: []const u8,
    scan: Tokenizer(.{}),
    token: Token,
    indent: IndentInfo = .{},

    pub const State = enum {
        expect_first_leading_space,
        expect_indentation,
        expect_primary,
        expect_sub,
        expect_new_scope,
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

    pub const StackPair = struct {
        operators: List(*Node) = .{},
        operands: List(*Node) = .{},

        // Invariant:
        // The operator stack is empty iff the operand stack is empty.
        pub fn empty(stack: *StackPair) bool {
            return stack.operands.items.len == 0;
        }

        pub fn resolveIfHigherPrecedence(stack: *StackPair, alloc: std.mem.Allocator, operator: Node.Tag) !void {
            while (stack.operators.getLastOrNull()) |node| {
                const pending = node.tag;
                if (operator.precedence() < pending.precedence() // (1 * 2) + [..]
                or (operator.precedence() == pending.precedence() and operator.isLeftAssociate())) // (1 + 2) + [..]
                {
                    try stack.resolveOperators(alloc);
                } else {
                    break;
                }
            }
        }

        pub fn resolveOperators(stack: *StackPair, alloc: std.mem.Allocator) !void {
            if (stack.operators.popOrNull()) |node| {
                if (node.tag.isOperator()) {
                    if (stack.operands.items.len < 2) return Parser.Error.InvalidOperandStack;
                    if (std.meta.activeTag(node.repr) != .pair) return Parser.Error.InternalError;
                    node.repr.pair.right = stack.operands.pop();
                    node.repr.pair.left = stack.operands.pop();
                    try stack.operands.append(alloc, node);
                } else {
                    return Error.InternalError;
                }
            }
        }
    };

    pub fn parse(p: *Parser, from: State) !*Node {
        var stack = StackPair{};
        p.token = p.scan.next();
        var state = log(from);
        while (true) {
            switch (state) {
                .expect_first_leading_space => {
                    switch (p.token.tag) {
                        .space => {
                            if (p.scan.peekByte() != '\n') {
                                p.indent.lead_size = p.token.len();
                                state = log(.expect_primary);
                                continue;
                            }
                        },
                        .newline => {},
                        else => {
                            state = log(.expect_primary);
                            continue; // lead_size == 0
                        },
                    }
                },
                .expect_indentation => { // post .newline token
                    if (p.token.tag == .space) {
                        if (p.indent.size == 0) {
                            p.indent.size = p.token.len();
                        }
                        // check depth integrity
                    }
                    state = log(.expect_primary);
                },
                .expect_new_scope => { // post .l_paren token
                    const parsed = try p.parse(.expect_primary);
                    if (p.token.tag != .r_paren) return Error.UnexpectedToken; // ')'
                    try stack.operands.append(p.alloc, parsed);
                    state = log(.expect_sub);
                },
                .expect_primary => {
                    switch (p.token.tag) {
                        .eof => break,
                        .space => {},
                        .l_paren => {
                            state = log(.expect_new_scope);
                            continue;
                        },
                        .newline => {
                            state = log(.expect_indentation);
                        },
                        .number => {
                            var node = try Node.init(p.alloc, .number, .literal);
                            node.repr.literal = p.token.slice(p.input);
                            try stack.operands.append(p.alloc, node);
                            state = log(.expect_sub);
                        },
                        .keyword_for => {
                            p.token = p.scan.next(); // 'for'
                            if (p.token.tag == .space) p.token = p.scan.next(); // ' '
                            // retrieve condition
                            if (p.token.tag != .l_paren) return Error.UnexpectedToken; // '('
                            const condition_node = try p.parse(.expect_primary); // condition
                            if (p.token.tag != .r_paren) return Error.UnexpectedToken; // ')'
                            // retrieve body
                            const body = try p.parse(.expect_primary); // body
                            // populate node
                            var node = try Node.init(p.alloc, .ctrl_for, .map);
                            try node.repr.map.put(p.alloc, "condition", condition_node);
                            try node.repr.map.put(p.alloc, "body", body);
                            // push on stack
                            try stack.operands.append(p.alloc, node);
                            // continue
                        },
                        else => {
                            std.log.err("Expected primary, got: {any}\n", .{p.token});
                            return Error.UnexpectedToken;
                        },
                    }
                },
                .expect_sub => {
                    switch (p.token.tag) {
                        .eof => break,
                        .space => {},
                        .newline => {
                            state = log(.expect_indentation);
                        },
                        .plus,
                        .minus,
                        .asterisk,
                        .caret,
                        .slash,
                        .comma,
                        => {
                            const operator = Node.Tag.fromToken(p.token);
                            try stack.resolveIfHigherPrecedence(p.alloc, operator);
                            const node = try Node.init(p.alloc, operator, .pair);
                            try stack.operators.append(p.alloc, node);
                            state = log(.expect_primary);
                        },
                        else => break,
                    }
                },
                // else => break,
            }
            p.token = p.scan.next();
        }

        while (stack.operators.items.len > 0) {
            try stack.resolveOperators(p.alloc);
        }

        return stack.operands.pop();
    }

    pub fn parseFromInput(alloc: std.mem.Allocator, input: [:0]const u8) !*Node {
        var p = Parser.init(alloc, input);
        return p.parse(.expect_first_leading_space);
    }
};

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
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();
    const input = "1 + 2 * 3 ^ 4 - for (5) 6";
    const root = try Parser.parseFromInput(alloc, input);
    const res = try root.dump(alloc, 0);
    defer alloc.free(res);
    try t.expectEqualStrings(
        \\[bin_sub]
        \\   [bin_add]
        \\      [number]:"1"
        \\      [bin_mul]
        \\         [number]:"2"
        \\         [bin_exp]
        \\            [number]:"3"
        \\            [number]:"4"
        \\   [ctrl_for]
        \\      "condition":[number]
        \\      "body":[number]
        \\
    , res);
}
