// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

//! Public API:
//! - Token
//! - TokenizerOptions
//! - Tokenizer

const std = @import("std");
const t = std.testing;
const ThisFile = @This();
var log = @import("utils/log.zig").Scope(.tokenizer, .{}){};
const log_in_tests = false;

pub const Token = struct {
    tag: Tag,
    loc: Loc,

    pub const Loc = struct {
        start: usize,
        end: usize,
    };

    pub const Tag = enum {
        // pseudo tokens
        incomplete, // invalid but potentially recoverable (if stream continues on the current token's state)
        invalid, // non-recoverable (even if stream continues)
        eof, // end of stream

        // symbol tokens
        // whitespace
        space, //
        newline, // \n
        indent,

        // brackets
        left_paren, // (
        right_paren, // )
        empty_parens, // ()

        left_curly, // {
        right_curly, // }
        left_square, // [
        right_square, // ]

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
        plus_plus, // ++
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

        // literal tokens
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
                '(' => .left_paren,
                ')' => .right_paren,
                '{' => .left_curly,
                '}' => .right_curly,
                '[' => .left_square,
                ']' => .right_square,

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
                .left_paren => '(',
                .right_paren => ')',
                .left_curly => '{',
                .right_curly => '}',
                .left_square => '[',
                .right_square => ']',

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

    pub fn init(tag: Tag, start: usize, end: usize) Token {
        return Token{ .tag = tag, .loc = .{ .start = start, .end = end } };
    }

    pub fn len(self: *const Token) usize {
        return self.loc.end - self.loc.start;
    }

    pub fn sliceFrom(self: *const Token, input: []const u8) []const u8 {
        return input[self.loc.start..self.loc.end];
    }
};

/// Tokenizer options.
pub const TokenizerOptions = struct {
    /// Enable strict recognition of tokens:
    /// * `true` - Consume only valid tokens (this is useful if you want to
    ///    terminate tokenization as soon as the first invalid token is
    ///    encountered).
    /// * `false` - Consume any token that "looks" valid (this is useful if you
    ///    want to tokenize the complete input and report several invalid
    ///    occasions).
    strict_mode: bool = true,
    /// Recognize spaces as separate tokens.
    tokenize_spaces: bool = false,
    /// Recognize indents as separate tokens. An indent is a newline followed by
    /// optional leading spaces before the next printable character.
    /// * `true` - tokenizer produces .indent tokens, skipping empty lines,
    ///   including those with spaces. token.len() gives the size of the leading
    ///   spaces before the first printable character.
    /// * `false` - tokenizer produces .newline tokens instead, consuming as
    ///   many newlines as possible in one go until it encounters a space or
    ///   a printable character. token.len() gives the number of lines consumed.
    tokenize_indents: bool = false,
    /// Track line position of the cursor.
    /// ```txt
    /// 0 1  2 3 4  tokenizer.index = 4
    /// a \n b c d  tokenizer.loc.line_number = 2 (starts at 1)
    ///          ^  tokenizer.loc.line_start = 2 (starts at 0)
    ///             tokenizer.atCol() = 3 (starts at 1)
    /// ````
    track_location: bool = true,
};

/// Tokenizer splits input into a stream of tokens. To retrieve a token, use
/// the `next()` function. Several invariants apply on every `next()` call:
/// * An invalid token always contains the character that caused it, see
///   `token[token.len - 1]`.
/// * A returned token has 4 possible conditions:
/// ```
///   Tag          State
///  .[tag],      .complete    Completed and valid token (the next one will
///                            be of a different tag).
///  .[tag],      .[state]     Valid token but potentially extendable if
///                            stream continues.
///  .invalid,    .[state]     Invalid and unrecoverable token regardless of
///                            whether the stream continues.
///  .incomplete, .[state]     Invalid token (at this EOF-moment) but potentially
///                            completable if the stream continues.
/// ```
/// * Tokens with .number tag do not have specific states to represent their base.
///   Instead, check `token[1]` for `b`, `o`, or `x`, which represent binary, octal,
///   or hexadecimal, respectively. If `token.len < 2` or none match, it is decimal.
/// * Tokens with .number tag do not have specific states to represent separators
///   between digits. Instead, check if `current_token[token.len-1] == '_' and
///   next_token[0] != '_'`.
pub fn Tokenizer(opt: TokenizerOptions) type {
    return struct {
        input: [:0]const u8,
        index: usize,
        loc: if (opt.track_location) Loc else struct {} = .{},
        state: State,

        const Self = @This();

        pub const Loc = struct {
            line_start: usize = @as(usize, 0) -% 1,
            line_number: usize = 1,
        };

        /// Defines the state in which tokenizer starts and returns.
        pub const State = enum {
            // root state that leads to others
            complete,

            // [forced recognition states]

            space, // reachable only by using nextFrom()
            indent, // reachable only by using nextFrom()

            // [symbols recognition states]

            post_newline,
            left_paren,
            plus,

            // [literals recognition states]

            identifier_non_strict,
            // strict mode only {
            identifier_post_first_alpha,
            identifier_post_first_digit,
            identifier_end,
            // }

            number_non_strict,
            // strict mode only {
            number_post_first_nonzero,
            number_post_first_zero,

            number_post_base_bin,
            number_post_base_oct,
            number_post_base_hex,

            number_post_base_first_digit_bin,
            number_post_base_first_digit_oct,
            number_post_base_first_digit_hex,

            number_post_dot_decimal,
            number_post_dot_hex,

            number_post_dot_first_digit_decimal,
            number_post_dot_first_digit_hex,

            number_post_exp,
            number_post_exp_sign,
            number_post_exp_first_digit,
            // }

            char_non_strict,
            // strict mode only {
            char_post_single_quote,
            char_post_backslash,
            char_end,
            // }

            string_post_double_quote,

            /// Applicable only for .number_* states
            pub fn toBase(s: @This()) Base {
                return switch (s) {
                    .number_post_base_bin,
                    .number_post_base_first_digit_bin,
                    => Base.binary,

                    .number_post_base_oct,
                    .number_post_base_first_digit_oct,
                    => Base.octal,

                    .number_post_base_hex,
                    .number_post_base_first_digit_hex,
                    .number_post_dot_first_digit_hex,
                    .number_post_dot_hex,
                    => Base.hex,

                    .number_post_dot_decimal,
                    .number_post_dot_first_digit_decimal,
                    => Base.decimal,
                    else => unreachable,
                };
            }
        };

        /// Defines primitives for the number base recognition.
        pub const Base = enum(u8) {
            hex = 16,
            decimal = 10,
            octal = 8,
            binary = 2,

            const digit_value = blk: {
                var table = [1]u8{0xFF} ** 256;
                for ('0'..'9' + 1) |ch| { // maps to 0..9
                    table[ch] = ch - '0';
                }
                for ('a'..'f' + 1) |ch| { // maps to 10..15
                    table[ch] = (ch - 'a') + 10;
                }
                for ('A'..'F' + 1) |ch| { // maps to 10..15
                    table[ch] = (ch - 'A') + 10;
                }
                break :blk table;
            };

            /// Applicable only for digits within '0'..'9'
            pub fn hasDigit(base: @This(), digit: u8) bool {
                return digit_value[digit] < @intFromEnum(base);
            }

            pub fn fromChar(char: u8) @This() {
                return switch (char) {
                    'x' => .hex,
                    'o' => .octal,
                    'b' => .binary,
                    else => .decimal,
                };
            }
        };

        pub fn init(input: [:0]const u8) Self {
            std.debug.assert(input[input.len] == 0); // TODO test if zig already makes this check on call
            // Skip UTF-8 BOM if present
            const start: usize = if (std.mem.startsWith(u8, input, "\xEF\xBB\xBF")) 3 else 0;
            return Self{
                .input = input,
                .index = start,
                .state = .complete,
            };
        }

        /// Returns the current line number the tokenizer is at. Starts at 1.
        pub fn getLine(s: *const Self) usize {
            if (!opt.track_location) @compileError("enable opt.track_location to use this function");
            return s.loc.line_number;
        }

        /// Returns the column number at the current line the tokenizer is at.
        /// Starts at 1.
        pub fn getCol(s: *const Self) usize {
            if (!opt.track_location) @compileError("enable opt.track_location to use this function");
            return s.index -% s.loc.line_start;
        }

        /// Returns the next recognized token. Read the Tokenizer doc comment
        /// for more details.
        pub inline fn next(self: *Self) Token {
            return self.nextFrom(.complete);
        }

        /// Similar to `next()`, but starts with a specific state.
        /// Used to continue tokenization for streamed input.
        pub fn nextFrom(s: *Self, from: State) Token {
            var token = Token{
                .tag = .eof,
                .loc = .{
                    .start = s.index,
                    .end = s.index,
                },
            };
            s.state = from;
            s.logState();
            while (true) {
                const c = s.input[s.index];
                switch (s.state) {
                    // root state for others; equivalent to '.start' and '.end' states
                    .complete => {
                        switch (c) {
                            0 => {
                                if (s.index != s.input.len) {
                                    token.tag = .invalid;
                                    s.index += 1;
                                } // else tag == .eof
                                break;
                            },

                            // whitespace
                            ' ' => {
                                if (opt.tokenize_spaces) {
                                    token.tag = .space;
                                    s.index += 1;
                                    // shortcut {
                                    while (s.input[s.index] == ' ') : (s.index += 1) {}
                                    // }
                                    break;
                                } else {
                                    token.loc.start += 1;
                                }
                            },

                            // newline
                            '\n' => {
                                if (opt.tokenize_indents) {
                                    token.loc.start += 1;
                                    s.state = .post_newline;
                                } else {
                                    token.tag = .newline;
                                    s.index += 1;
                                    // shortcut {
                                    while (s.input[s.index] == '\n') : (s.index += 1) {}
                                    // }
                                    if (opt.track_location) {
                                        s.loc.line_start = s.index -| 1;
                                        s.loc.line_number += s.index - token.loc.start;
                                    }
                                    break;
                                }
                            },

                            // operator-looking tokens
                            '(' => s.state = .left_paren,
                            '+' => s.state = .plus,

                            inline
                            // brackets
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
                                s.index += 1;
                                break;
                            },

                            // identifier
                            '_', 'a'...'z', 'A'...'Z' => {
                                token.tag = .identifier;
                                s.state = comptime if (!opt.strict_mode) .identifier_non_strict else .identifier_post_first_alpha;
                            },

                            // number
                            '0' => {
                                token.tag = .number;
                                s.state = comptime if (!opt.strict_mode) .number_non_strict else .number_post_first_zero;
                            },
                            '1'...'9' => {
                                token.tag = .number;
                                s.state = comptime if (!opt.strict_mode) .number_non_strict else .number_post_first_nonzero;
                            },

                            // string literal
                            '"' => {
                                token.tag = .string;
                                s.state = .string_post_double_quote;
                            },

                            // char
                            '\'' => {
                                token.tag = .char;
                                s.state = comptime if (!opt.strict_mode) .char_non_strict else .char_post_single_quote;
                            },

                            else => {
                                token.tag = .invalid;
                                s.index += 1;
                                break;
                            },
                        }
                    },

                    // use nextFrom(.space) to recognize spaces even if
                    // .tokenize_spaces is false
                    .space => {
                        switch (c) {
                            ' ' => {
                                token.tag = .space;
                                s.index += 1;
                                // shortcut {
                                while (s.input[s.index] == ' ') : (s.index += 1) {}
                                // }
                                break;
                            },
                            else => {
                                s.state = .complete;
                                continue;
                            },
                        }
                    },

                    // use nextFrom(.indent) to recognize indents even if
                    // .tokenize_indents is false
                    .indent,
                    .post_newline,
                    => {
                        switch (c) {
                            ' ' => {}, // continue
                            '\n' => {
                                s.index += 1;
                                // shortcut {
                                while (s.input[s.index] == '\n') : (s.index += 1) {}
                                // }
                                if (opt.track_location) {
                                    s.loc.line_start = s.index -| 1;
                                    s.loc.line_number += s.index - token.loc.start;
                                }
                                token.loc.start = s.index;
                                continue;
                            },
                            0 => {
                                if (s.index != s.input.len) {
                                    token.tag = .invalid;
                                    s.index += 1;
                                } else {
                                    token.tag = .eof;
                                    s.state = .complete;
                                }
                                break;
                            },
                            else => {
                                token.tag = .indent;
                                s.state = .complete;
                                break;
                            },
                        }
                    },

                    // operators
                    .plus => {
                        switch (c) {
                            '+' => {
                                token.tag = .plus_plus;
                                s.index += 1;
                            },
                            else => token.tag = .plus,
                        }
                        s.state = .complete;
                        break;
                    },
                    .left_paren => {
                        switch (c) {
                            ')' => {
                                token.tag = .empty_parens;
                                s.state = .complete;
                                s.index += 1;
                                break;
                            },
                            else => {
                                token.tag = .left_paren;
                                s.state = .complete;
                                break;
                            },
                        }
                    },

                    // identifier
                    .identifier_non_strict => {
                        switch (c) {
                            '_', 'a'...'z', 'A'...'Z', '0'...'9' => {},
                            else => {
                                s.state = .complete;
                                if (Token.Tag.getKeyword(s.input[token.loc.start..s.index])) |tag|
                                    token.tag = tag;
                                break;
                            },
                        }
                    },
                    .identifier_post_first_alpha => {
                        switch (c) {
                            '_', 'a'...'z', 'A'...'Z' => {},
                            '0'...'9' => s.state = .identifier_post_first_digit,
                            else => {
                                s.state = .complete;
                                if (Token.Tag.getKeyword(s.input[token.loc.start..s.index])) |tag|
                                    token.tag = tag;
                                break;
                            },
                        }
                    },
                    .identifier_post_first_digit => {
                        switch (c) {
                            '0'...'9' => {},
                            '_', 'a'...'z', 'A'...'Z' => {
                                token.tag = .invalid;
                                s.index += 1;
                                break;
                            },
                            else => {
                                s.state = .complete;
                                if (Token.Tag.getKeyword(s.input[token.loc.start..s.index])) |tag|
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
                                s.state = .complete;
                                break;
                            },
                        }
                    },
                    .number_post_first_nonzero => { // <nonzero>[..] (decimal only)
                        switch (c) {
                            '0'...'9' => {}, // <nonzero><digit+>[..]
                            'e', 'E' => s.state = .number_post_exp, // <nonzero><exp>[..]
                            '.' => s.state = .number_post_dot_decimal, // <nonzero><dot>[..]
                            // TODO assert next is [0-9] or null otherwise invalid
                            '_' => if (s.input[s.index + 1] == '_') {
                                token.tag = .invalid;
                                s.index += 1;
                                break;
                            },
                            'a'...'d', 'f'...'z', 'A'...'D', 'F'...'Z' => { // any letter except [eE]
                                token.tag = .invalid;
                                s.index += 1;
                                break;
                            },
                            else => {
                                if (s.index == s.input.len) break;
                                // isn't token char and isn't the last char
                                s.state = .complete;
                                break;
                            },
                        }
                    },
                    .number_post_first_zero => { // 0[..]
                        switch (c) {
                            '.' => { // 0<dot>[..]
                                s.state = .number_post_dot_decimal;
                            },
                            'e', 'E' => { // 0<exp>[..]
                                s.state = .number_post_exp;
                            },
                            // 0<base>[..]
                            'b' => s.state = .number_post_base_bin,
                            'o' => s.state = .number_post_base_oct,
                            'x' => s.state = .number_post_base_hex,
                            // token char range except [boeEx]
                            '_', '0'...'9', 'a', 'c', 'd', 'f'...'n', 'p'...'w', 'y'...'z', 'A'...'D', 'F'...'Z' => {
                                token.tag = .invalid;
                                s.index += 1;
                                break;
                            },
                            else => {
                                if (s.index == s.input.len) break;
                                s.state = .complete;
                                break;
                            },
                        }
                    },
                    .number_post_base_bin,
                    .number_post_base_oct,
                    .number_post_base_hex,
                    => |state| { // 0<base>[..]
                        const base = state.toBase();
                        // assert next char is ..
                        if (base.hasDigit(c)) { // 0<base><digit>[..]
                            s.state = switch (base) {
                                .binary => .number_post_base_first_digit_bin,
                                .octal => .number_post_base_first_digit_oct,
                                .hex => .number_post_base_first_digit_hex,
                                else => unreachable,
                            };
                        } else {
                            if (s.index == s.input.len) {
                                token.tag = .incomplete;
                            } else {
                                token.tag = .invalid;
                                s.index += 1;
                            }
                            break;
                        }
                    },
                    .number_post_base_first_digit_bin,
                    .number_post_base_first_digit_oct,
                    .number_post_base_first_digit_hex,
                    => |state| { // 0<base><digit>[..]
                        const base = state.toBase();
                        switch (c) {
                            'p', 'P' => { // 0<base><digit+><exp>[..]
                                if (base != .hex) { // non-decimal float points available only for hex
                                    token.tag = .invalid;
                                    s.index += 1;
                                    break;
                                }
                                s.state = .number_post_exp;
                            },
                            '.' => { // 0<base><digit+><dot>[..]
                                if (base != .hex) { // non-decimal exponents available only for hex
                                    token.tag = .invalid;
                                    s.index += 1;
                                    break;
                                }
                                s.state = .number_post_dot_hex;
                            },
                            // token char range except [.pP]
                            '0'...'9', 'a'...'o', 'q'...'z', 'A'...'O', 'Q'...'Z' => |digit| { // 0<base><digit+>[..]
                                if (!base.hasDigit(digit)) {
                                    token.tag = .invalid;
                                    s.index += 1;
                                    break;
                                }
                            },
                            // TODO // '_' => ,
                            else => {
                                if (s.index == s.input.len) break;
                                s.state = .complete;
                                break;
                            },
                        }
                    },
                    .number_post_dot_decimal,
                    .number_post_dot_hex,
                    => |state| { // <num><dot>[..]
                        const base = state.toBase();
                        // assert next char is ..
                        if (base.hasDigit(c)) { // <num><dot><digit>[..]
                            s.state = switch (base) {
                                .decimal => .number_post_dot_first_digit_decimal,
                                .hex => .number_post_dot_first_digit_hex,
                                else => unreachable,
                            };
                        } else {
                            if (s.index == s.input.len) {
                                token.tag = .incomplete;
                            } else {
                                token.tag = .invalid;
                                s.index += 1;
                            }
                            break;
                        }
                    },
                    .number_post_dot_first_digit_decimal,
                    .number_post_dot_first_digit_hex,
                    => |state| { // <num><dot><digit>[..] (any base)
                        const base = state.toBase();
                        switch (c) {
                            '0'...'9', 'a'...'z', 'A'...'Z' => {
                                if (!base.hasDigit(c)) {
                                    if (base == .decimal and (c == 'e' or c == 'E') or // <num><dot><digit+><exp>[..]
                                        base == .hex and (c == 'p' or c == 'P'))
                                    {
                                        s.state = .number_post_exp;
                                    } else {
                                        token.tag = .invalid;
                                        s.index += 1;
                                        break;
                                    }
                                } // <num><dot><digit+>[..]
                            },
                            '.' => { // redundant dot
                                token.tag = .invalid;
                                s.index += 1;
                                break;
                            },
                            // TODO // '_' => ,
                            else => {
                                if (s.index == s.input.len) break;
                                s.state = .complete;
                                break;
                            },
                        }
                    },
                    .number_post_exp => { // <num><exp>[..]
                        // assert next char is ..
                        switch (c) {
                            '+', '-' => s.state = .number_post_exp_sign,
                            '0'...'9' => s.state = .number_post_exp_first_digit,
                            else => {
                                if (s.index == s.input.len) {
                                    token.tag = .incomplete;
                                } else {
                                    token.tag = .invalid;
                                    s.index += 1;
                                }
                                break;
                            },
                        }
                    },
                    .number_post_exp_sign => { // <num><exp><sign>[..]
                        // assert next char is ..
                        switch (c) {
                            '0'...'9' => {
                                s.state = .number_post_exp_first_digit;
                            },
                            else => {
                                if (s.index == s.input.len) {
                                    token.tag = .incomplete;
                                } else {
                                    token.tag = .invalid;
                                    s.index += 1;
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
                                s.index += 1;
                                break;
                            },
                            // TODO // '_' => ,
                            else => {
                                if (s.index == s.input.len) break;
                                s.state = .complete;
                                break;
                            },
                        }
                    },

                    // char
                    .char_non_strict => {
                        switch (c) {
                            '\'' => {
                                s.state = .complete;
                                s.index += 1;
                                break;
                            },
                            else => {}, // TODO exclude invalid chars
                        }
                    },
                    .char_post_single_quote => {
                        switch (c) {
                            0 => {
                                if (s.index != s.input.len) {
                                    token.tag = .invalid;
                                    s.index += 1;
                                }
                                break;
                            },
                            '\\' => {
                                s.state = .char_post_backslash;
                            },
                            '\'', '\n' => { // unexpected end
                                token.tag = .invalid;
                                s.index += 1;
                                break;
                            },
                            else => {
                                if (std.ascii.isPrint(c)) {
                                    s.state = .char_end;
                                } else {
                                    token.tag = .invalid;
                                    s.index += 1;
                                    break;
                                }
                            },
                        }
                    },
                    .char_post_backslash => {
                        switch (c) {
                            0 => {
                                if (s.index != s.input.len) {
                                    token.tag = .invalid;
                                    s.index += 1;
                                }
                                break;
                            },
                            '\n' => { // unexpected end
                                token.tag = .invalid;
                                s.index += 1;
                                break;
                            },
                            '\'', 'n', 'r', 't' => {
                                s.state = .char_end;
                            },
                            // TODO add \x, \u
                            else => {
                                token.tag = .invalid;
                                s.index += 1;
                                break;
                            },
                        }
                    },
                    .char_end => {
                        switch (c) {
                            '\'' => {
                                s.state = .complete;
                                s.index += 1;
                                break;
                            },
                            else => {
                                // if it isn't closing quote or eof
                                if (s.index != s.input.len) {
                                    token.tag = .invalid;
                                    s.index += 1;
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
                                s.index += 1;
                                break;
                            },
                            '"' => { // end of string
                                s.state = .complete;
                                s.index += 1;
                                break;
                            },
                            else => {
                                // TODO allow UTF-8 as well
                                if (!std.ascii.isPrint(c)) {
                                    if (s.index == s.input.len) {
                                        token.tag = .incomplete; // TODO why?
                                    } else {
                                        token.tag = .invalid;
                                        s.index += 1;
                                    }
                                    break;
                                }
                            },
                        }
                    },
                    else => break,
                }
                s.index +%= 1;
                s.logState();
            }
            token.loc.end = s.index;
            s.logState();
            Self.logToken(token);
            return token;
        }

        pub fn nextIs(s: *Self, tag: Token.Tag) bool {
            // TODO add support for strings, numbers, etc
            // TODO add invariant or comment that this would work only on a fresh start (after previous token is .complete)
            switch (tag) {
                .eof => return s.index >= s.input.len,
                inline else => |for_each| {
                    if (s.index >= s.input.len) return false;
                    return if (for_each.lexeme()) |l| s.input[s.index] == l else false;
                },
            }
            unreachable;
        }

        pub fn skip(self: *Self) void {
            _ = self.next();
        }

        pub fn rewind(s: *const Self, token: Token) void {
            s.index = token.loc.start;
        }

        pub fn rewindTo(s: *const Self, index: usize) void {
            s.index = index;
        }

        pub fn peek(s: *const Self) Token {
            const token = s.next();
            s.rewind(token);
            return token;
        }

        pub fn peekByte(s: *const Self) u8 {
            // TODO self.index < self.input.len is an invariant?
            return if (s.index < s.input.len) s.input[s.index] else 0;
        }

        fn logState(s: *const Self) void {
            if (comptime log.active() or log_in_tests) {
                log.print("[state .{s} ", .{@tagName(s.state)}) catch {};
                log.setAnsiColor(.dim) catch {};
                if (opt.track_location) {
                    log.print("{d}:{d}:", .{ s.getLine(), s.getCol() }) catch {};
                }
                log.print("{d}", .{s.index}) catch {};
                log.setAnsiColor(.reset) catch {};
                log.printAndFlush("]\n", .{}) catch {};
            }
        }

        fn logToken(token: Token) void {
            if (comptime log.active() or log_in_tests) {
                log.print("[token ", .{}) catch {};
                log.setAnsiColor(.bold) catch {};
                log.print(".{s}", .{@tagName(token.tag)}) catch {};
                log.setAnsiColor(.reset) catch {};
                log.printAndFlush(":{d}:{d}]\n", .{ token.loc.start, token.loc.end }) catch {};
            }
        }
    };
}

test Tokenizer {
    @setEvalBranchQuota(2000);

    // Test correct location tracking.
    {
        var scan = Tokenizer(.{ .track_location = true }).init("\nfoo!\n\n");
        // cold start
        try t.expectEqual(1, scan.getLine());
        try t.expectEqual(1, scan.getCol());

        // \n
        try t.expectEqual(Token.Tag.newline, scan.next().tag);
        try t.expectEqual(1, scan.index);
        try t.expectEqual(2, scan.getLine());
        try t.expectEqual(1, scan.getCol());

        // foo
        try t.expectEqual(Token.Tag.identifier, scan.next().tag);
        try t.expectEqual(4, scan.index);
        try t.expectEqual(2, scan.getLine());
        try t.expectEqual(4, scan.getCol());

        // !
        try t.expectEqual(Token.Tag.exclamation, scan.next().tag);
        try t.expectEqual(5, scan.index);
        try t.expectEqual(2, scan.getLine());
        try t.expectEqual(5, scan.getCol());

        // \n\n
        try t.expectEqual(Token.Tag.newline, scan.next().tag);
        try t.expectEqual(7, scan.index);
        try t.expectEqual(4, scan.getLine());
        try t.expectEqual(1, scan.getCol());

        // eof
        try t.expectEqual(Token.Tag.eof, scan.next().tag);
        try t.expectEqual(7, scan.index);
        try t.expectEqual(4, scan.getLine());
        try t.expectEqual(1, scan.getCol());
    }

    // Test correct token recognition.
    {
        // Note, in this test set, all complete valid tokens end with a space to
        // avoid tokenizing only the correct beginning and leaving the invalid end.

        const T = Tokenizer(.{
            .strict_mode = true,
            .track_location = true,
            .tokenize_spaces = true,
            .tokenize_indents = false,
        });

        const case = struct {
            pub fn run(input: [:0]const u8, expect_tag: Token.Tag, expect_state: T.State) !void {
                var scan = T.init(input);
                const token = scan.next();

                // states match
                try t.expectEqual(expect_state, scan.state);

                // a complete valid token ends with a space
                if (expect_tag != .space and expect_state == .complete)
                    try t.expectEqual(' ', input[token.len()]);

                // tags match
                try t.expectEqual(expect_tag, token.tag);

                // an invalid token includes the first invalid char
                if (expect_tag == .invalid)
                    try t.expectEqual(input[input.len - 1], input[token.loc.end - 1]);
            }
        }.run;

        // primes
        // -------------------------------
        // whitespace
        try case(" ", .space, .complete);
        try case("\n ", .newline, .complete);

        // brackets
        try case("( ", .left_paren, .complete);
        try case(") ", .right_paren, .complete);
        try case("() ", .empty_parens, .complete);
        try case("{ ", .left_curly, .complete);
        try case("} ", .right_curly, .complete);
        try case("[ ", .left_square, .complete);
        try case("] ", .right_square, .complete);

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
        try case("++ ", .plus_plus, .complete);
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
        // [integers]
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
        try case("0b1", .number, .number_post_base_first_digit_bin);
        try case("0b01", .number, .number_post_base_first_digit_bin);
        try case("0b09", .invalid, .number_post_base_first_digit_bin);
        try case("0b1z", .invalid, .number_post_base_first_digit_bin);
        try case("0b1Z", .invalid, .number_post_base_first_digit_bin);
        // failed base
        try case("0b ", .invalid, .number_post_base_bin);
        try case("0b", .incomplete, .number_post_base_bin);

        // base 8
        try case("0o1 ", .number, .complete);
        try case("0o1", .number, .number_post_base_first_digit_oct);
        try case("0o07", .number, .number_post_base_first_digit_oct);
        try case("0o08", .invalid, .number_post_base_first_digit_oct);
        try case("0o7z", .invalid, .number_post_base_first_digit_oct);
        try case("0o7Z", .invalid, .number_post_base_first_digit_oct);
        // failed base
        try case("0o ", .invalid, .number_post_base_oct);
        try case("0o", .incomplete, .number_post_base_oct);

        // base 16
        try case("0x1 ", .number, .complete);
        try case("0x1", .number, .number_post_base_first_digit_hex);
        try case("0x0f", .number, .number_post_base_first_digit_hex);
        try case("0x0F", .number, .number_post_base_first_digit_hex);
        try case("0x0g", .invalid, .number_post_base_first_digit_hex);
        try case("0x0G", .invalid, .number_post_base_first_digit_hex);
        try case("0xfz", .invalid, .number_post_base_first_digit_hex);
        try case("0xfZ", .invalid, .number_post_base_first_digit_hex);
        // failed base
        try case("0x ", .invalid, .number_post_base_hex);
        try case("0x", .incomplete, .number_post_base_hex);

        // [floats]
        // base 10
        try case("0.0 ", .number, .complete);
        try case("0.0", .number, .number_post_dot_first_digit_decimal);
        try case("0.09", .number, .number_post_dot_first_digit_decimal);
        try case("0.09.", .invalid, .number_post_dot_first_digit_decimal);
        try case("0.09a", .invalid, .number_post_dot_first_digit_decimal);
        // failed dot
        try case("0. ", .invalid, .number_post_dot_decimal);
        try case("0..", .invalid, .number_post_dot_decimal);
        try case("1. ", .invalid, .number_post_dot_decimal);
        try case("1..", .invalid, .number_post_dot_decimal);
        try case("0.", .incomplete, .number_post_dot_decimal);
        try case("1.", .incomplete, .number_post_dot_decimal);

        // base 16
        try case("0xf.0 ", .number, .complete);
        try case("0xf.0", .number, .number_post_dot_first_digit_hex);
        try case("0xf.09", .number, .number_post_dot_first_digit_hex);
        try case("0xf.09.", .invalid, .number_post_dot_first_digit_hex);
        try case("0xf.09z", .invalid, .number_post_dot_first_digit_hex);
        // failed dot
        try case("0x0. ", .invalid, .number_post_dot_hex);
        try case("0x0..", .invalid, .number_post_dot_hex);
        try case("0x0.", .incomplete, .number_post_dot_hex);
        try case("0x09.", .incomplete, .number_post_dot_hex);

        // [float exponents]
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

        // [float exponents sign]
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

        // [mixed]
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

        // chars
        // -------------------------------
        try case("\'", .char, .char_post_single_quote);

        // strings
        // -------------------------------
        try case("\"\" ", .string, .complete);
        try case("\"", .incomplete, .string_post_double_quote);
        try case("\"\n", .invalid, .string_post_double_quote);
        try case("\" !#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~\" ", .string, .complete);

        // [.tokenize_spaces]
        // -------------------------------
        {
            var scan = Tokenizer(.{ .tokenize_spaces = false }).init("  1");
            try t.expectEqual(.number, scan.next().tag);
            try t.expectEqual(.eof, scan.next().tag);
        }
        {
            var scan = Tokenizer(.{ .tokenize_spaces = true }).init("  1");
            const token = scan.next();
            try t.expectEqual(.space, token.tag);
            try t.expectEqual(2, token.len());
            try t.expectEqual(.number, scan.next().tag);
            try t.expectEqual(.eof, scan.next().tag);
        }

        // [.tokenize_indents]
        // -------------------------------
        {
            var scan = Tokenizer(.{ .tokenize_indents = false }).init("\n");
            try t.expectEqual(.newline, scan.next().tag);
        }
        {
            var scan = Tokenizer(.{ .tokenize_indents = true }).init("\n");
            const token = scan.next();
            try t.expectEqual(.eof, token.tag);
            try t.expectEqual(0, token.len());
            try t.expectEqual(0, scan.input[token.loc.start]);
            try t.expectEqual(0, scan.input[token.loc.end]);
        }
        {
            var scan = Tokenizer(.{ .tokenize_indents = true }).init("\n!");
            const token = scan.next();
            try t.expectEqual(.indent, token.tag);
            try t.expectEqual(0, token.len());
            try t.expectEqual('!', scan.input[token.loc.start]);
            try t.expectEqual('!', scan.input[token.loc.end]);
        }
        {
            var scan = Tokenizer(.{ .tokenize_indents = true }).init("\n  !");
            const token = scan.next();
            try t.expectEqual(.indent, token.tag);
            try t.expectEqual(2, token.len());
            try t.expectEqual(' ', scan.input[token.loc.start]);
            try t.expectEqual('!', scan.input[token.loc.end]);
        }
        {
            var scan = Tokenizer(.{ .tokenize_indents = true }).init(
                \\
                //^ the first newline is necessary to recognize the indent
                \\   hello
                \\  
                //^ '  \n' recognize indent with extra leading spaces
                \\   world
            );
            var token = scan.next();
            try t.expectEqual(.indent, token.tag);
            try t.expectEqual(3, token.len());
            try t.expectEqual(.identifier, scan.next().tag); // hello
            try t.expectEqual(.indent, scan.next().tag);
            try t.expectEqual(3, token.len());
            try t.expectEqual(.identifier, scan.next().tag); // world
        }

        // [nextFrom(.indent)]
        // -------------------------------
        {
            var scan = Tokenizer(.{ .tokenize_indents = false }).init("  !");
            const token = scan.nextFrom(.indent);
            try t.expectEqual(.indent, token.tag);
            try t.expectEqual(2, token.len());
            try t.expectEqual(' ', scan.input[token.loc.start]);
            try t.expectEqual('!', scan.input[token.loc.end]);
        }

        // mixed
        // -------------------------------
        {
            var scan = Tokenizer(.{
                .tokenize_indents = true,
                .tokenize_spaces = true,
            }).init(
                \\  hello!
                \\  {123,456}+
            );

            var token = scan.next();
            try t.expectEqual(.space, token.tag);
            try t.expectEqual(2, token.len());
            try t.expectEqual(.identifier, scan.next().tag);
            try t.expectEqual(true, scan.nextIs(.exclamation));
            try t.expectEqual(.exclamation, scan.next().tag);
            token = scan.next();
            try t.expectEqual(.indent, token.tag);
            try t.expectEqual(2, token.len());
            try t.expectEqual(.left_curly, scan.next().tag);
            try t.expectEqual(.number, scan.next().tag);
            try t.expectEqual(.comma, scan.next().tag);
            try t.expectEqual(.number, scan.next().tag);
            try t.expectEqual(.right_curly, scan.next().tag);
            try t.expectEqual(.plus, scan.next().tag);
            try t.expectEqual(.eof, scan.next().tag);
            try t.expectEqual(.eof, scan.next().tag); // make sure we stay the same
        }
    }
}
