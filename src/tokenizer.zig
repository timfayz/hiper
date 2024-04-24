// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;

/// Invariants:
/// * An invalid token always contains the character that caused it, see token[token.len].
/// * Every token has 4 possible conditions:
///   Tag          State
///  .[tag],      .complete   -- Completed and valid token (next token will be of a different tag).
///  .[tag],      .[state]    -- Valid token but potentially extendable if stream continues.
///  .invalid,    .[state]    -- Invalid and unrecoverable token regardless of whether the stream continues.
///  .incomplete, .[state]    -- Invalid token at this EOF-moment but potentially completable if the stream continues.
/// * Number tokens have no specific states to represent different bases; instead, check token[1] if token.len > 2.
/// * Number tokens have no specific states to represent separators between digits; instead, check token[token.len] == '_' and next_token[0] != '_'.
pub const Token = struct {
    tag: Tag,
    state: State = .complete,
    loc: Loc,

    pub const Loc = struct {
        start: usize,
        end: usize,
    };

    /// The state in which tokenizer returned.
    pub const State = enum {
        complete,

        identifier_non_strict,
        // strict mode only
        identifier_post_first_alpha,
        identifier_post_first_digit,
        identifier_end,

        number_non_strict,
        // strict mode only
        number_post_first_nonzero,
        number_post_first_zero,
        number_post_base,
        number_post_base_first_digit,
        number_post_dot,
        number_post_dot_first_digit,
        number_post_exp,
        number_post_exp_sign,
        number_post_exp_first_digit,

        char_non_strict,
        // strict mode only
        char_post_single_quote,
        char_post_backslash,
        char_end,

        // strict mode only
        string_post_double_quote,
    };

    pub const Tag = enum {
        // pseudo tokens
        incomplete, // invalid but potentially recoverable (if stream continues on the current token's state)
        invalid, // non-recoverable (even if stream continues)
        eof, // end of stream

        // single-char tokens
        // whitespace
        space, //
        newline, // \n

        // brackets
        l_paren, // (
        r_paren, // )
        l_curly, // {
        r_curly, // }
        l_square, // [
        r_square, // ]

        // special
        single_quote, // ' (currently unused)
        double_quote, // " (currently unused)
        backtick, // `
        dot, // .
        comma, // ,
        colon, // :
        semicolon, // ;
        exclamation, // !
        ampersand, // &
        question, // ?
        dollar, // $
        caret, // ^
        pipe, // |
        hash, // #
        plus, // +
        minus, // -
        percent, // %
        asterisk, // *
        backslash, // \
        slash, // /
        tilde, // ~
        equal, // =
        lt, // <
        gt, // >
        at, // @

        // composite tokens
        number,
        identifier,
        string,
        char,
        keyword_if,
        keyword_elif,
        keyword_else,
        keyword_for,
        keyword_while,

        /// Applies only to tokens of .identifier tag.
        pub fn getKeyword(input: []const u8) ?Tag {
            switch (input.len) {
                // if
                2 => return if (std.mem.startsWith(u8, input, "if")) .keyword_if else null,
                // for
                3 => return if (std.mem.startsWith(u8, input, "for")) .keyword_for else null,
                // elif, else
                4 => {
                    if (input[0] != 'e') return null;
                    if (input[1] != 'l') return null;
                    switch (input[2]) {
                        'i' => if (input[3] == 'f') return .keyword_elif,
                        's' => if (input[3] == 'e') return .keyword_else,
                        else => return null,
                    }
                    return null;
                },
                // while
                5 => return if (std.mem.startsWith(u8, input, "while")) .keyword_while else null,
                else => return null,
            }
        }

        /// Applies only to single character tokens.
        pub fn getFrom(char: u8) Tag {
            return switch (char) {
                // whitespace
                ' ' => .space,
                '\n' => .newline,

                // brackets
                '(' => .l_paren,
                ')' => .r_paren,
                '{' => .l_curly,
                '}' => .r_curly,
                '[' => .l_square,
                ']' => .r_square,

                // special
                '\'' => .single_quote,
                '"' => .double_quote,
                '`' => .backtick,
                '.' => .dot,
                ',' => .comma,
                ':' => .colon,
                ';' => .semicolon,
                '!' => .exclamation,
                '&' => .ampersand,
                '?' => .question,
                '$' => .dollar,
                '^' => .caret,
                '|' => .pipe,
                '#' => .hash,
                '+' => .plus,
                '-' => .minus,
                '%' => .percent,
                '*' => .asterisk,
                '\\' => .backslash,
                '/' => .slash,
                '~' => .tilde,
                '=' => .equal,
                '<' => .lt,
                '>' => .gt,
                '@' => .at,

                else => unreachable,
            };
        }

        /// Applies only to non-pseudo single character tokens. For composite one, use token.slice() instead.
        /// TODO: can be unified for any token types (except pseudo) with ?[]const
        pub fn lexeme(tag: Tag) ?u8 {
            return switch (tag) {
                // pseudo
                .invalid => null,
                .eof => null,

                // composite
                .identifier => null,
                .number => null,
                .string => null,

                // whitespace
                .space => ' ',
                .newline => '\n',

                // brackets
                .l_paren => '(',
                .r_paren => ')',
                .l_curly => '{',
                .r_curly => '}',
                .l_square => '[',
                .r_square => ']',

                // special
                .single_quote => '\'',
                .double_quote => '"',
                .backtick => '`',
                .dot => '.',
                .comma => ',',
                .colon => ':',
                .semicolon => ';',
                .exclamation => '!',
                .ampersand => '&',
                .question => '?',
                .dollar => '$',
                .caret => '^',
                .pipe => '|',
                .hash => '#',
                .plus => '+',
                .minus => '-',
                .percent => '%',
                .asterisk => '*',
                .backslash => '\\',
                .slash => '/',
                .tilde => '~',
                .equal => '=',
                .lt => '<',
                .gt => '>',
                .at => '@',

                else => null,
            };
        }
    };

    pub fn init(tag: Tag, state: State, start: usize, end: usize) Token {
        return Token{ .tag = tag, .loc = .{ .start = start, .end = end }, .state = state };
    }

    pub inline fn len(self: *const Token) usize {
        return self.loc.end - self.loc.start;
    }

    pub inline fn slice(self: *const Token, input: []const u8) []const u8 {
        return input[self.loc.start..self.loc.end];
    }

    pub fn debug(self: *const Token) void {
        std.debug.print("tag: {s}, len: {any}, state: {s}\n", .{ @tagName(self.tag), self.len(), @tagName(self.state) });
    }
};

const TokenizerOptions = struct {
    trace_lines: bool = false,
    /// true - Consume only valid tokens (useful if we want to terminate parsing as soon as the first encountered token is invalid).
    /// false - Consume tokens that "look" valid (useful if we want to tokenize complete input and report several invalid occasions).
    tokenize_strict: bool = true,
};

pub fn Tokenizer(opt: TokenizerOptions) type {
    const Empty = struct {};

    const LineInfo = struct {
        line_start: usize = 0,
        line_number: usize = 0,
    };

    return struct {
        index: usize = 0,
        input: [:0]const u8,
        // pending_token: ?Token = null,
        trace: if (opt.trace_lines) LineInfo else Empty = .{},

        const Self = @This();

        pub fn init(input: [:0]const u8) Self {
            assert(input[input.len] == 0);
            // Skip UTF-8 BOM if present
            const start: usize = if (std.mem.startsWith(u8, input, "\xEF\xBB\xBF")) 3 else 0;
            return Self{
                .input = input,
                .index = start,
            };
        }

        pub fn validate(self: *Self, tag: Token.Tag) bool {
            const token = self.next().tag;
            self.rewind(token);
            return token == tag;
        }

        pub inline fn next(self: *Self) Token {
            return self.nextImpl(.complete, opt.tokenize_strict);
        }

        pub inline fn nextFromState(self: *Self, from: Token.State) Token {
            return self.nextImpl(from, opt.tokenize_strict);
        }

        pub inline fn nextFromInput(input: [:0]const u8) Token {
            var tokenizer = Self.init(input);
            return tokenizer.nextImpl(.complete, opt.tokenize_strict);
        }

        pub fn nextImpl(self: *Self, from: Token.State, comptime strict: bool) Token {
            var token = Token{
                .tag = .eof,
                .state = from,
                .loc = .{
                    .start = self.index,
                    .end = self.index,
                },
            };
            var base: Base = .decimal;
            while (true) : (self.index += 1) {
                const c = self.input[self.index];
                switch (token.state) {
                    .complete => { // equals to .start and .end
                        switch (c) {
                            0 => {
                                if (self.index != self.input.len) {
                                    token.tag = .invalid;
                                    self.index += 1;
                                } // else tag == .eof already
                                break;
                            },

                            // whitespace
                            ' ' => {
                                token.tag = .space;
                                self.index += 1;
                                while (self.input[self.index] == ' ') : (self.index += 1) {}
                                break;
                            },
                            '\n' => {
                                token.tag = .newline;
                                self.index += 1;
                                while (self.input[self.index] == '\n') : (self.index += 1) {}
                                break;
                            },

                            inline // "for each"
                            // brackets
                            '(',
                            ')',
                            '{',
                            '}',
                            '[',
                            ']',
                            // special
                            '`',
                            '.',
                            ',',
                            ':',
                            ';',
                            '!',
                            '&',
                            '?',
                            '$',
                            '^',
                            '|',
                            '#',
                            '+',
                            '-',
                            '%',
                            '*',
                            '\\',
                            '/',
                            '~',
                            '=',
                            '<',
                            '>',
                            '@',
                            => |char| {
                                token.tag = comptime Token.Tag.getFrom(char);
                                self.index += 1;
                                break;
                            },

                            // identifier
                            '_', 'a'...'z', 'A'...'Z' => {
                                token.tag = .identifier;
                                token.state = if (!strict) .identifier_non_strict else .identifier_post_first_alpha;
                            },

                            // number
                            '0' => {
                                token.tag = .number;
                                token.state = if (!strict) .number_non_strict else .number_post_first_zero;
                            },
                            '1'...'9' => {
                                token.tag = .number;
                                token.state = if (!strict) .number_non_strict else .number_post_first_nonzero;
                            },

                            // string literal
                            '"' => {
                                token.tag = .string;
                                token.state = .string_post_double_quote;
                            },

                            '\'' => {
                                token.tag = .char;
                                token.state = if (!strict) .char_non_strict else .char_post_single_quote;
                            },

                            else => {
                                token.tag = .invalid;
                                self.index += 1;
                                break;
                            },
                        }
                    },

                    // identifier
                    .identifier_non_strict => {
                        switch (c) {
                            '_', 'a'...'z', 'A'...'Z', '0'...'9' => {},
                            else => {
                                token.state = .complete;
                                if (Token.Tag.getKeyword(self.input[token.loc.start..self.index])) |tag|
                                    token.tag = tag;
                                break;
                            },
                        }
                    },
                    .identifier_post_first_alpha => {
                        switch (c) {
                            '_', 'a'...'z', 'A'...'Z' => {},
                            '0'...'9' => token.state = .identifier_post_first_digit,
                            else => {
                                token.state = .complete;
                                if (Token.Tag.getKeyword(self.input[token.loc.start..self.index])) |tag|
                                    token.tag = tag;
                                break;
                            },
                        }
                    },
                    .identifier_post_first_digit => {
                        switch (c) {
                            '0'...'9' => {},
                            else => {
                                token.state = .complete;
                                if (Token.Tag.getKeyword(self.input[token.loc.start..self.index])) |tag|
                                    token.tag = tag;
                                break;
                            },
                        }
                    },

                    // number
                    .number_non_strict => {
                        switch (c) {
                            '.', '_', '0'...'9', 'a'...'z', 'A'...'Z' => {},
                            else => {
                                token.state = .complete;
                                break;
                            },
                        }
                    },
                    .number_post_first_nonzero => { // <nonzero>[..] (decimal only)
                        switch (c) {
                            '0'...'9' => {}, // <nonzero><digit+>[..]
                            'e', 'E' => token.state = .number_post_exp, // <nonzero><exp>[..]
                            '.' => token.state = .number_post_dot, // <nonzero><dot>[..]
                            // TODO assert next is [0-9] or null otherwise invalid
                            '_' => if (self.input[self.index + 1] == '_') {
                                token.tag = .invalid;
                                self.index += 1;
                                break;
                            },
                            'a'...'d', 'f'...'z', 'A'...'D', 'F'...'Z' => { // letter except [eE]
                                token.tag = .invalid;
                                self.index += 1;
                                break;
                            },
                            else => {
                                if (self.index == self.input.len) break;
                                // isn't token char and isn't the last char
                                token.state = .complete;
                                break;
                            },
                        }
                    },
                    .number_post_first_zero => { // 0[..] (hex, octal, bin only)
                        switch (c) {
                            '.' => { // 0<dot>[..]
                                token.state = .number_post_dot;
                            },
                            'e', 'E' => { // 0<exp>[..]
                                token.state = .number_post_exp;
                            },
                            'b', 'o', 'x' => { // 0<base>[..]
                                base = Base.fromChar(c);
                                token.state = .number_post_base;
                            },
                            // token char range except [boeEx]
                            '_', '0'...'9', 'a', 'c', 'd', 'f'...'n', 'p'...'w', 'y'...'z', 'A'...'D', 'F'...'Z' => {
                                token.tag = .invalid;
                                self.index += 1;
                                break;
                            },
                            else => {
                                if (self.index == self.input.len) break;
                                token.state = .complete;
                                break;
                            },
                        }
                    },
                    .number_post_base => { // 0<base>[..] (hex, octal, bin only)
                        // assert next char is .. otherwise invalid
                        switch (base) {
                            .decimal => unreachable, // decimals cannot have base prefix
                            inline else => |in_base| {
                                if (in_base.isDigit(c)) { // 0<base><digit>[..]
                                    token.state = .number_post_base_first_digit;
                                } else {
                                    if (self.index == self.input.len) {
                                        token.tag = .incomplete;
                                    } else {
                                        token.tag = .invalid;
                                        self.index += 1;
                                    }
                                    break;
                                }
                            },
                        }
                    },
                    .number_post_base_first_digit => { // 0<base><digit>[..] (hex, octal, bin only)
                        switch (c) {
                            '.', 'p', 'P' => { // 0<base><digit+>(<dot>|<exp>)[..]
                                if (base != .hex) { // non-decimal floats available only for hex
                                    token.tag = .invalid;
                                    self.index += 1;
                                    break;
                                }
                                token.state = if (c == '.') .number_post_dot else .number_post_exp;
                            },
                            // token char range except [.pP]
                            '0'...'9', 'a'...'o', 'q'...'z', 'A'...'O', 'Q'...'Z' => |digit| { // 0<base><digit+>[..]
                                if (base.isDigit(digit)) continue;
                                token.tag = .invalid;
                                self.index += 1;
                                break;
                            },
                            // TODO // '_' => ,
                            else => {
                                if (self.index == self.input.len) break;
                                token.state = .complete;
                                break;
                            },
                        }
                    },
                    .number_post_dot => { // <num><dot>[..] (any base)
                        // assert next char is .. otherwise invalid
                        if (base.isDigit(c)) { // <num><dot><digit>[..]
                            token.state = .number_post_dot_first_digit;
                        } else {
                            if (self.index == self.input.len) {
                                token.tag = .incomplete;
                            } else {
                                token.tag = .invalid;
                                self.index += 1;
                            }
                            break;
                        }
                    },
                    .number_post_dot_first_digit => { // <num><dot><digit>[..] (any base)
                        switch (c) {
                            '0'...'9', 'a'...'z', 'A'...'Z' => {
                                if (base.isDigit(c)) continue; // <num><dot><digit+>[..]
                                if (base == .decimal and (c == 'e' or c == 'E') or
                                    base == .hex and (c == 'p' or c == 'P')) // <num><dot><digit+><exp>[..]
                                {
                                    token.state = .number_post_exp;
                                } else {
                                    token.tag = .invalid;
                                    self.index += 1;
                                    break;
                                }
                            },
                            '.' => { // redundant dot
                                token.tag = .invalid;
                                self.index += 1;
                                break;
                            },
                            // TODO // '_' => ,
                            else => {
                                if (self.index == self.input.len) break;
                                token.state = .complete;
                                break;
                            },
                        }
                    },
                    .number_post_exp => { // <num><exp>[..]
                        // assert next char is .. otherwise invalid
                        switch (c) {
                            '+', '-' => token.state = .number_post_exp_sign,
                            '0'...'9' => token.state = .number_post_exp_first_digit,
                            else => {
                                if (self.index == self.input.len) {
                                    token.tag = .incomplete;
                                } else {
                                    token.tag = .invalid;
                                    self.index += 1;
                                }
                                break;
                            },
                        }
                    },
                    .number_post_exp_sign => { // <num><exp><sign>[..]
                        // assert next char is .. otherwise invalid
                        switch (c) {
                            '0'...'9' => {
                                token.state = .number_post_exp_first_digit;
                            },
                            else => {
                                if (self.index == self.input.len) {
                                    token.tag = .incomplete;
                                } else {
                                    token.tag = .invalid;
                                    self.index += 1;
                                }
                                break;
                            },
                        }
                    },
                    .number_post_exp_first_digit => { // <num><exp>(<sign>)<digit>[..]
                        switch (c) {
                            '0'...'9' => {}, // <num><exp>(<sign>)<digit+>[..]
                            '.', 'a'...'z', 'A'...'Z' => { // any letter except [0-9_]
                                token.tag = .invalid;
                                self.index += 1;
                                break;
                            },
                            // TODO // '_' => ,
                            else => {
                                if (self.index == self.input.len) break;
                                token.state = .complete;
                                break;
                            },
                        }
                    },

                    // char
                    .char_non_strict => {
                        switch (c) {
                            '\'' => {
                                token.state = .complete;
                                self.index += 1;
                                break;
                            },
                            else => {}, // TODO exclude invalid chars
                        }
                    },
                    .char_post_single_quote => {
                        switch (c) {
                            0 => {
                                if (self.index != self.input.len) {
                                    token.tag = .invalid;
                                    self.index += 1;
                                }
                                break;
                            },
                            '\\' => {
                                token.state = .char_post_backslash;
                            },
                            '\'', '\n' => { // unexpected end
                                token.tag = .invalid;
                                self.index += 1;
                                break;
                            },
                            else => {
                                if (std.ascii.isPrint(c)) {
                                    token.state = .char_end;
                                } else {
                                    token.tag = .invalid;
                                    self.index += 1;
                                    break;
                                }
                            },
                        }
                    },
                    .char_post_backslash => {
                        switch (c) {
                            0 => {
                                if (self.index != self.input.len) {
                                    token.tag = .invalid;
                                    self.index += 1;
                                }
                                break;
                            },
                            '\n' => { // unexpected end
                                token.tag = .invalid;
                                self.index += 1;
                                break;
                            },
                            '\'', 'n', 'r', 't' => {
                                token.state = .char_end;
                            },
                            // TODO add \x, \u
                            else => {
                                token.tag = .invalid;
                                self.index += 1;
                                break;
                            },
                        }
                    },
                    .char_end => {
                        switch (c) {
                            '\'' => {
                                token.state = .complete;
                                self.index += 1;
                                break;
                            },
                            else => {
                                // if it isn't closing quote or eof
                                if (self.index != self.input.len) {
                                    token.tag = .invalid;
                                    self.index += 1;
                                }
                                break;
                            },
                        }
                    },

                    // string
                    .string_post_double_quote => {
                        switch (c) {
                            '\n' => {
                                token.tag = .invalid;
                                self.index += 1;
                                break;
                            },
                            '"' => { // end of string
                                token.state = .complete;
                                self.index += 1;
                                break;
                            },
                            else => {
                                // TODO allow UTF-8 as well
                                if (std.ascii.isPrint(c)) continue;
                                if (self.index == self.input.len) {
                                    token.tag = .incomplete;
                                } else {
                                    token.tag = .invalid;
                                    self.index += 1;
                                }
                                break;
                            },
                        }
                    },
                    else => break,
                }
            }
            token.loc.end = self.index;

            // trace
            if (opt.trace_lines) {
                if (token.tag == .newline)
                    self.traceLines(token.len())
                else
                    self.tracePos(token.len());
            }
            return token;
        }

        // TODO add support for strings, numbers, etc
        // TODO add invariant or comment that this would work only on a fresh start (after previous token is .complete)
        pub fn nextIs(self: *Self, tag: Token.Tag) bool {
            switch (tag) {
                .eof => return self.index >= self.input.len,
                inline else => |for_each| {
                    if (self.index >= self.input.len) return false;
                    return if (for_each.lexeme()) |l| self.input[self.index] == l else false;
                },
            }
            unreachable;
        }

        pub inline fn skip(self: *Self) void {
            _ = self.next();
        }

        pub inline fn rewind(self: *Self, token: Token) void {
            self.index = token.loc.start;
        }

        pub fn peekByte(self: *Self) u8 {
            // TODO is self.index < self.input.len an invariant? no need to check the overflow then?
            return if (self.index < self.input.len) self.input[self.index] else 0;
        }

        pub const Base = enum(u8) {
            hex = 16,
            decimal = 10,
            octal = 8,
            binary = 2,

            const digit_value = blk: {
                var table = [1]u8{0xFF} ** 256;
                for ('0'..'9' + 1) |ch| {
                    table[ch] = ch - '0';
                }
                for ('a'..'f' + 1) |ch| {
                    table[ch] = ch - 'a' + 10;
                }
                for ('A'..'F' + 1) |ch| {
                    table[ch] = ch - 'A' + 10;
                }
                break :blk table;
            };

            // digit must be '0'...'9'
            pub inline fn isDigit(base: @This(), digit: u8) bool {
                return digit_value[digit] < @intFromEnum(base);
            }

            pub fn fromChar(char: u8) @This() {
                return switch (char) {
                    'x' => .hex,
                    'o' => .octal,
                    'b' => .binary,
                    else => unreachable,
                };
            }
        };

        inline fn tracePos(self: *Self, len: usize) void {
            if (opt.trace_lines) self.trace.line_start += len;
        }

        inline fn traceLines(self: *Self, len: usize) void {
            if (opt.trace_lines) {
                self.trace.line_number += len;
                self.trace.line_start = 0;
            }
        }
    };
}

test "tokenizer" {
    const t = std.testing;
    const case = struct {
        pub fn run(input: [:0]const u8, expect_tag: Token.Tag, expect_state: Token.State) !void {
            const token = Tokenizer(.{}).nextFromInput(input);
            try t.expectEqual(expect_state, token.state);
            if (expect_tag != .space and expect_state == .complete)
                try t.expectEqual(' ', input[token.len()]);
            // invalid token always includes the first invalid char
            if (expect_tag == .invalid)
                try t.expectEqual(input.len, token.len());
            try t.expectEqual(expect_tag, token.tag);
        }
    }.run;

    // In this test set, all complete valid tokens end with a space to avoid tokenizing only the correct beginning and leaving rubbish afterward.
    {
        // primes
        // -------------------------------
        // whitespace
        try case(" ", .space, .complete);
        try case("\n ", .newline, .complete);

        // brackets
        try case("( ", .l_paren, .complete);
        try case(") ", .r_paren, .complete);
        try case("{ ", .l_curly, .complete);
        try case("} ", .r_curly, .complete);
        try case("[ ", .l_square, .complete);
        try case("] ", .r_square, .complete);

        // special
        // no single quotes (see strings)
        try case("` ", .backtick, .complete);
        try case(". ", .dot, .complete);
        try case(", ", .comma, .complete);
        try case(": ", .colon, .complete);
        try case("; ", .semicolon, .complete);
        try case("! ", .exclamation, .complete);
        try case("& ", .ampersand, .complete);
        try case("? ", .question, .complete);
        try case("$ ", .dollar, .complete);
        try case("^ ", .caret, .complete);
        try case("| ", .pipe, .complete);
        try case("# ", .hash, .complete);
        try case("+ ", .plus, .complete);
        try case("- ", .minus, .complete);
        try case("% ", .percent, .complete);
        try case("* ", .asterisk, .complete);
        try case("\\ ", .backslash, .complete);
        try case("/ ", .slash, .complete);
        try case("~ ", .tilde, .complete);
        try case("= ", .equal, .complete);
        try case("< ", .lt, .complete);
        try case("> ", .gt, .complete);
        try case("@ ", .at, .complete);

        // numbers
        // -------------------------------
        // ints:
        // base 10
        try case("1 ", .number, .complete);
        try case("1", .number, .number_post_first_nonzero);
        try case("12", .number, .number_post_first_nonzero);
        try case("1a", .invalid, .number_post_first_nonzero);
        try case("0 ", .number, .complete);
        try case("0", .number, .number_post_first_zero);
        try case("00", .invalid, .number_post_first_zero);
        try case("0a", .invalid, .number_post_first_zero);

        // base 2
        try case("0b1 ", .number, .complete);
        try case("0b1", .number, .number_post_base_first_digit);
        try case("0b01", .number, .number_post_base_first_digit);
        try case("0b09", .invalid, .number_post_base_first_digit);
        try case("0b1z", .invalid, .number_post_base_first_digit);
        try case("0b1Z", .invalid, .number_post_base_first_digit);
        // failed base
        try case("0b ", .invalid, .number_post_base);
        try case("0b", .incomplete, .number_post_base);

        // base 8
        try case("0o1 ", .number, .complete);
        try case("0o1", .number, .number_post_base_first_digit);
        try case("0o07", .number, .number_post_base_first_digit);
        try case("0o08", .invalid, .number_post_base_first_digit);
        try case("0o7z", .invalid, .number_post_base_first_digit);
        try case("0o7Z", .invalid, .number_post_base_first_digit);
        // failed base
        try case("0o ", .invalid, .number_post_base);
        try case("0o", .incomplete, .number_post_base);

        // base 16
        try case("0x1 ", .number, .complete);
        try case("0x1", .number, .number_post_base_first_digit);
        try case("0x0f", .number, .number_post_base_first_digit);
        try case("0x0F", .number, .number_post_base_first_digit);
        try case("0x0g", .invalid, .number_post_base_first_digit);
        try case("0x0G", .invalid, .number_post_base_first_digit);
        try case("0xfz", .invalid, .number_post_base_first_digit);
        try case("0xfZ", .invalid, .number_post_base_first_digit);
        // failed base
        try case("0x ", .invalid, .number_post_base);
        try case("0x", .incomplete, .number_post_base);

        // floats dot:
        // base 10
        try case("0.0 ", .number, .complete);
        try case("0.0", .number, .number_post_dot_first_digit);
        try case("0.09", .number, .number_post_dot_first_digit);
        try case("0.09.", .invalid, .number_post_dot_first_digit);
        try case("0.09a", .invalid, .number_post_dot_first_digit);
        // failed dot
        try case("0. ", .invalid, .number_post_dot);
        try case("0..", .invalid, .number_post_dot);
        try case("1. ", .invalid, .number_post_dot);
        try case("1..", .invalid, .number_post_dot);
        try case("0.", .incomplete, .number_post_dot);
        try case("1.", .incomplete, .number_post_dot);

        // base 16
        try case("0xf.0 ", .number, .complete);
        try case("0xf.0", .number, .number_post_dot_first_digit);
        try case("0xf.09", .number, .number_post_dot_first_digit);
        try case("0xf.09.", .invalid, .number_post_dot_first_digit);
        try case("0xf.09z", .invalid, .number_post_dot_first_digit);
        // failed dot
        try case("0x0. ", .invalid, .number_post_dot);
        try case("0x0..", .invalid, .number_post_dot);
        try case("0x0.", .incomplete, .number_post_dot);
        try case("0x09.", .incomplete, .number_post_dot);

        // floats exponent:
        // base 10
        try case("0e0 ", .number, .complete);
        try case("0e0", .number, .number_post_exp_first_digit);
        try case("0e09", .number, .number_post_exp_first_digit);
        try case("0e09a", .invalid, .number_post_exp_first_digit);
        try case("1e0 ", .number, .complete);
        try case("1e0", .number, .number_post_exp_first_digit);
        // failed exponent
        try case("0e ", .invalid, .number_post_exp);
        try case("0ee", .invalid, .number_post_exp);
        try case("0e", .incomplete, .number_post_exp);
        // exponent after dot
        try case("1.0e09 ", .number, .complete);
        try case("0.0e0", .number, .number_post_exp_first_digit);
        try case("1.0e0", .number, .number_post_exp_first_digit);
        try case("1.0e09", .number, .number_post_exp_first_digit);
        try case("1.0e09a", .invalid, .number_post_exp_first_digit);

        // base 16
        try case("0x0p0 ", .number, .complete); // valid
        try case("0x0p0", .number, .number_post_exp_first_digit); // valid, incomplete
        // failed exponent
        try case("0x0p ", .invalid, .number_post_exp); // invalid
        try case("0x0p", .incomplete, .number_post_exp); // incomplete
        // exponent after dot
        try case("0x0.0p0 ", .number, .complete); // valid
        try case("0x0.0p0", .number, .number_post_exp_first_digit); // valid, incomplete
        try case("0x0.0p0a", .invalid, .number_post_exp_first_digit); // invalid

        // floats exponent sign:
        // base 10
        try case("0e+0 ", .number, .complete); // valid
        try case("0e+09 ", .number, .complete); // valid
        try case("1e+0 ", .number, .complete); // valid
        try case("0e+0", .number, .number_post_exp_first_digit); // valid, incomplete
        try case("0e+09", .number, .number_post_exp_first_digit); // valid, incomplete
        try case("1e+0", .number, .number_post_exp_first_digit); // valid, incomplete
        try case("0e+", .incomplete, .number_post_exp_sign); // incomplete
        try case("1e+", .incomplete, .number_post_exp_sign); // incomplete
        try case("0e+ ", .invalid, .number_post_exp_sign); // invalid
        try case("1e+ ", .invalid, .number_post_exp_sign); // invalid
        // base 16
        try case("0x0p+0 ", .number, .complete); // valid
        try case("0x0p+0", .number, .number_post_exp_first_digit); // valid, incomplete
        try case("0x0p+09", .number, .number_post_exp_first_digit); // valid, incomplete
        try case("0x0p+ ", .invalid, .number_post_exp_sign); // invalid
        try case("0x0p+", .incomplete, .number_post_exp_sign); // incomplete

        // random:
        // TODO add _
        try case("98222 ", .number, .complete); // decimal_int
        try case("0xff ", .number, .complete); // hex_int
        try case("0xFF ", .number, .complete); // another_hex_int
        try case("0o755 ", .number, .complete); // octal_int
        try case("0b11110000 ", .number, .complete); // binary_int
        try case("1000000000 ", .number, .complete); // one_billion
        try case("0b111111111 ", .number, .complete); // binary_mask
        try case("0o755 ", .number, .complete); // permissions
        try case("0xFF80000000000000 ", .number, .complete); // big_address

        try case("123.0E+77 ", .number, .complete); // floating_point
        try case("123.0 ", .number, .complete); // another_float
        try case("123.0e+77 ", .number, .complete); // yet_another
        try case("0x103.70p-5 ", .number, .complete); // hex_floating_point
        try case("0x103.70 ", .number, .complete); // another_hex_float
        try case("0x103.70P-5 ", .number, .complete); // yet_another_hex_float
        try case("299792458.000000 ", .number, .complete); // lightspeed
        try case("0.000000001 ", .number, .complete); // nanosecond
        try case("0x12345678.9ABCCDEFp-10 ", .number, .complete); // more_hex

        // char
        // -------------------------------
        try case("\'", .char, .char_post_single_quote);

        // string
        // -------------------------------
        try case("\"\" ", .string, .complete);
        try case("\"", .incomplete, .string_post_double_quote);
        try case("\"\n", .invalid, .string_post_double_quote);
        try case("\" !#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~\" ", .string, .complete);

        // mixed
        // -------------------------------
        const input = "  hello!\n\n{123,456}+";
        var scan = Tokenizer(.{}).init(input);
        try t.expectEqual(.space, scan.next().tag);
        try t.expectEqual(.identifier, scan.next().tag);
        try t.expectEqual(true, scan.nextIs(.exclamation));
        try t.expectEqual(.exclamation, scan.next().tag);
        try t.expectEqual(.newline, scan.next().tag);
        try t.expectEqual(.l_curly, scan.next().tag);
        try t.expectEqual(.number, scan.next().tag);
        try t.expectEqual(.comma, scan.next().tag);
        try t.expectEqual(.number, scan.next().tag);
        try t.expectEqual(.r_curly, scan.next().tag);
        try t.expectEqual(.plus, scan.next().tag);
        try t.expectEqual(.eof, scan.next().tag);
        try t.expectEqual(.eof, scan.next().tag);
    }
}
