// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

//! Public API:
//! - defaults
//! - scopeActive()
//! - scope()
//! - print()
//! - writer()
//! - writeFn()
//! - flush()
//! - LineStreamer
//! - lineStreamer()
//! - streamByLines()

const std = @import("std");
const builtin = @import("builtin");
const tty = std.io.tty;
const t = std.testing;

/// Default log options.
pub const defaults = struct {
    pub const options_identifier = "hiper_options";
    /// Default's log_writer. If not set, it will default to `std.io.getStdErr().writer()`.
    pub const log_writer = if (rootHas("log_writer")) rootGet("log_writer") else std.io.getStdErr().writer();
    /// Buffer size for the log writer. If buffer is flushed when full,
    /// limiting the max line size to `log_buffer_size - 1`.
    pub const log_buffer_size = if (rootHas("log_buffer_size")) rootGet("log_buffer_size") else 4096;
    /// Does `std.debug.un/lockStdErr()` on buffer flushes.
    pub const log_lock_stderr_on_flush = if (rootHas("log_lock_stderr_on_flush")) rootGet("log_lock_stderr_on_flush") else true;
    /// Prefix for the default scope.
    pub const log_prefix_default_scope = if (rootHas("log_prefix_default_scope")) rootGet("log_prefix_default_scope") else "log: ";
    /// Forced prefix for all scopes.
    pub const log_prefix_all_scopes = if (rootHas("log_prefix_all_scopes")) rootGet("log_prefix_all_scopes") else "";
    /// Active log scopes. If not set, it will default to `.log`.
    pub const log_scopes = if (rootHas("log_scopes")) blk: {
        const scopes = rootGet("log_scopes");
        if (@typeInfo(@TypeOf(scopes)) != .Struct) @compileError("log_scopes must be a tuple");
        break :blk scopes;
    } else .{.log};

    const root = @import("root");

    fn rootHas(comptime name: []const u8) bool {
        return @hasDecl(root, options_identifier) and
            @hasField(@TypeOf(@field(root, options_identifier)), name);
    }

    fn rootGet(comptime name: []const u8) blk: {
        if (!rootHas(name))
            @compileError(options_identifier ++ " does not have this option.");
        break :blk @TypeOf(@field(@field(root, options_identifier), name));
    } {
        return @field(@field(root, options_identifier), name);
    }
};

/// Checks if the `.log_scopes` option contains the specified `.tag`.
pub fn scopeActive(tag: @TypeOf(.Enum)) bool {
    const fields = std.meta.fields(@TypeOf(defaults.log_scopes));
    inline for (fields) |field| {
        if (@field(defaults.log_scopes, field.name) == tag) return true;
    }
    return false;
}

/// Initializes a print and writer interface under the specified `tag` scope.
/// Thin wrapper around LineStreamer.
///
/// ```
/// // new scope with custom prefix
/// var my_scope = scope(.scope_name, .{.prefix = "sn: "}){};
/// try my_scope.print("hello world!", .{}); // `sn: hello world!`
///
/// // new scope with custom writer
/// const my_writer = std.io.getStdOut().writer();
/// var my_scope = scope(.scope_name, .{.Writer = @TypeOf(my_writer)}).init(my_writer);
/// try my_scope.print("hello world!", .{});
/// ```
pub fn Scope(
    tag: @TypeOf(.Enum),
    opt: struct {
        WriterType: ?type = null,
        buffer_size: usize = defaults.log_buffer_size,
        prefix: []const u8 = @tagName(tag) ++ ": ",
        postfix: []const u8 = "",
        allow_colors: bool = true,
        lock_stderr_on_flush: bool = defaults.log_lock_stderr_on_flush,
    },
) type {
    const UnderlyingWriter = if (opt.WriterType) |T| T else @TypeOf(defaults.log_writer);
    const WrappingWriter = LineStreamer(UnderlyingWriter, opt.buffer_size, .{
        .prefix = defaults.log_prefix_all_scopes ++ opt.prefix,
        .postfix = opt.postfix,
        .lock_stderr_on_flush = opt.lock_stderr_on_flush,
    });

    return struct {
        underlying_writer: WrappingWriter = if (opt.WriterType == null) WrappingWriter.init(defaults.log_writer) else undefined,

        const Self = @This();
        const Error = WrappingWriter.Error;
        const Writer = std.io.Writer(*Self, Error, write);

        pub fn init(underlying_writer: anytype) Self {
            return .{ .underlying_writer = WrappingWriter.init(underlying_writer) };
        }

        /// Checks if the current scope is active.
        pub fn active(s: *const Self) bool {
            _ = s; // autofix
            return scopeActive(tag);
        }

        /// Writes an ANSI color code to the writer.
        pub fn setAnsiColor(s: *Self, color: tty.Color) Error!void {
            if (!opt.allow_colors) return;
            const ansi_tty = tty.Config{ .escape_codes = {} };
            try ansi_tty.setColor(s.writer(), color);
        }

        /// Writes a color code to the writer using the provided tty configuration.
        pub fn setColor(s: *Self, config: tty.Config, color: tty.Color) Error!void {
            if (!opt.allow_colors) return;
            try config.setColor(s.writer(), color);
        }

        /// Prints a formatted string within the specified `tag` scope.
        pub fn print(s: *Self, comptime format: []const u8, args: anytype) Error!void {
            if (!builtin.is_test and !scopeActive(tag)) return;
            try s.underlying_writer.writer().print(format, args);
        }

        /// Prints a formatted string within the specified `tag` scope using
        /// `defaults.log_writer` and flushes automatically.
        pub fn printAndFlush(s: *Self, comptime format: []const u8, args: anytype) Error!void {
            if (!builtin.is_test and !scopeActive(tag)) return;
            try s.underlying_writer.writer().print(format, args);
            try s.underlying_writer.flush();
        }

        /// Write primitive within the specified `tag` scope.
        pub fn write(s: *Self, bytes: []const u8) Error!usize {
            if (!builtin.is_test and !scopeActive(tag)) return bytes.len;
            return s.underlying_writer.write(bytes);
        }

        /// Flushes the entire buffer to the writer. Use this to
        /// ensure all writes are committed.
        pub fn flush(s: *Self) Error!void {
            if (!builtin.is_test and !scopeActive(tag)) return;
            return s.underlying_writer.flush();
        }

        pub fn writer(s: *Self) Writer {
            return .{ .context = s };
        }
    };
}

/// Default scope.
var defaultScope = Scope(.log, .{ .prefix = defaults.log_prefix_default_scope }){};

/// Prints a formatted string within the default `.log` scope; use `scope(..)`
/// for defining custom scopes.
pub const print = defaultScope.printAndFlush;

/// Returns writer interface within the default `.log` scope, falling back to
/// a "null writer" if the scope is inactive.
pub const writer = defaultScope.writer;

/// Write primitive within the default `.log` scope.
pub const writeFn = defaultScope.write;

/// Flushes the entire buffer within the default `.log` scope. Use this to
/// ensure all writes are committed.
pub const flush = defaultScope.flush;

test Scope {
    var out = std.BoundedArray(u8, 512){};
    const out_writer = out.writer();

    if (scopeActive(.non_active)) // `.non_active` tag isn't in `defaults.log_scopes`
        return error.UnexpectedScopeIsActive;

    // normal usage
    var sc = Scope(.tag, .{
        .buffer_size = 10,
        .WriterType = @TypeOf(out_writer),
    }).init(out_writer);

    try sc.print("long print", .{});
    try t.expectEqualStrings("", out.slice());
    try sc.printAndFlush("very long print", .{});
    try t.expectEqualStrings(
        \\tag: long print
        \\tag: very long 
        \\tag: print
        \\
    , out.slice());
    out.clear();

    try std.fmt.format(sc.writer(), "{s}", .{"very long print"});
    try t.expectEqualStrings(
        \\tag: very long 
        \\
    , out.slice());

    try sc.flush();
    try t.expectEqualStrings(
        \\tag: very long 
        \\tag: print
        \\
    , out.slice());
}

pub const LineStreamerOptions = struct {
    /// Prefix added to each line.
    prefix: []const u8 = "",
    /// Postfix added before '\n' on each line.
    postfix: []const u8 = "",
    /// Skip last empty line when `flush()` is called.
    skip_last_empty_line: bool = true,
    /// Use `std.debug.lockStdErr()` while writing to the underlying writer.
    lock_stderr_on_flush: bool = false,
};

/// A writer that streams the buffer line by line. For correct rendering, lines
/// should not exceed `buffer_size - 1`. After writing is complete, use `flush()`
/// to write out the remaining data.
pub fn LineStreamer(WriterType: type, buffer_size: usize, opt: LineStreamerOptions) type {
    if (buffer_size < 1) @compileError("buffer_size cannot be less than 1");
    return struct {
        underlying_writer: WriterType,
        buf: [buffer_size]u8 = undefined,
        index: usize = 0,

        const Self = @This();
        pub const Error = WriterType.Error;
        pub const Writer = std.io.Writer(*Self, Error, write);

        pub fn init(underlying_writer: WriterType) Self {
            return Self{ .underlying_writer = underlying_writer };
        }

        /// Returns the filled portion of the buffer as a slice.
        pub fn slice(s: *Self) []u8 {
            return s.buf[0..s.index];
        }

        /// Writes bytes to the internal buffer, flushing stored bytes first
        /// except the last line.
        pub fn write(s: *Self, bytes: []const u8) Error!usize {
            // bytes do not fit, flush stored bytes first
            if (s.index + bytes.len > s.buf.len) {
                try s.flushExceptLastLine();
            }

            // store bytes into the remaining buffer space
            const n = @min(s.buf.len - s.index, bytes.len);
            @memcpy(s.buf[s.index..][0..n], bytes[0..n]);
            s.index += n;

            return n;
        }

        pub fn writer(s: *Self) Writer {
            return .{ .context = s };
        }

        /// A shortcut for printing with `.writer().print(format, args)`
        /// followed by a `.flush()`.
        pub fn print(s: *Self, comptime format: []const u8, args: anytype) Error!void {
            try s.writer().print(format, args);
            try s.flush();
        }

        /// Flushes the entire buffer line by line, regardless of line
        /// completeness. Should be called after the writing process is complete.
        pub fn flush(s: *Self) Error!void {
            if (s.index == 0) return;

            if (opt.lock_stderr_on_flush) std.debug.lockStdErr();
            defer if (opt.lock_stderr_on_flush) std.debug.unlockStdErr();

            var iter = std.mem.splitScalar(u8, s.slice(), '\n');
            while (iter.next()) |line| {
                if (opt.skip_last_empty_line and iter.index == null and line.len == 0)
                    break;
                try s.writeLine(line);
            }
            s.index = 0;
        }

        /// Flushes the entire stream buffer line by line up to the last
        /// complete line. The last line is always assumed incomplete and
        /// is moved to the beginning of the buffer to allow continuation.
        fn flushExceptLastLine(s: *Self) Error!void {
            if (s.index == 0) return;

            if (opt.lock_stderr_on_flush) std.debug.lockStdErr();
            defer if (opt.lock_stderr_on_flush) std.debug.unlockStdErr();

            var iter = std.mem.splitScalar(u8, s.slice(), '\n');
            while (iter.next()) |line| {
                if (iter.index == null) { // reached the end
                    if (line.len == s.buf.len) { // the entire buffer was a single line (no '\n's)
                        s.index = 0; // reset buffer and write the line "as is", without splitting
                    } else { // otherwise, move the line to the buffer start
                        for (line, 0..) |byte, i| s.buf[i] = byte;
                        s.index = line.len;
                        break;
                    }
                }
                try s.writeLine(line);
            }
        }

        /// A direct write of a line with a configured prefix and postfix.
        pub fn writeLine(s: *Self, line: []const u8) Error!void {
            try s.underlying_writer.writeAll(opt.prefix);
            try s.underlying_writer.writeAll(line);
            try s.underlying_writer.writeAll(opt.postfix ++ "\n");
        }
    };
}

test LineStreamer {
    var out = std.BoundedArray(u8, 512){};
    const OutWriter = @TypeOf(out.writer());

    // shortcuts
    try streamByLine(out.writer(), "hello world", 6, .{ .prefix = "pre: " });
    try t.expectEqualStrings(
        \\pre: hello 
        \\pre: world
        \\
    , out.slice());
    out.clear();

    var s0 = lineStreamer(out.writer(), .{ .prefix = "pre: " });
    try s0.print("hello world", .{});
    try t.expectEqualStrings(
        \\pre: hello world
        \\
    , out.slice());
    out.clear();

    // stream empty string
    var s1 = LineStreamer(OutWriter, 4, .{ .prefix = "pre: " }).init(out.writer());
    try s1.print("", .{});
    try t.expectEqualStrings(
        \\
    , out.slice());
    out.clear();

    // stream empty newline
    try s1.print("\n", .{});
    try t.expectEqualStrings(
        \\pre: 
        \\
    , out.slice());
    out.clear();

    // stream lines that do not exceed internal buffer
    try s1.print("111\n222\n", .{});
    try t.expectEqualStrings(
        \\pre: 111
        \\pre: 222
        \\
    , out.slice());
    out.clear();

    // stream lines that exceed internal buffer
    try s1.print("1111x\n2222y\n", .{});
    try t.expectEqualStrings(
        \\pre: 1111
        \\pre: x
        \\pre: 2222
        \\pre: y
        \\
    , out.slice());
    out.clear();

    // [.skip_last_empty_line]
    var s2 = LineStreamer(OutWriter, 4, .{
        .prefix = "pre: ",
        .skip_last_empty_line = false,
    }).init(out.writer());

    try s2.print("111\n222\n", .{});
    try t.expectEqualStrings(
        \\pre: 111
        \\pre: 222
        \\pre: 
        \\
    , out.slice());
    out.clear();

    // [.postfix]
    var s3 = LineStreamer(OutWriter, 4, .{
        .postfix = " :post",
    }).init(out.writer());

    try s3.print("11112222", .{});
    try t.expectEqualStrings(
        \\1111 :post
        \\2222 :post
        \\
    , out.slice());
    out.clear();

    // test internals
    {
        var ls = LineStreamer(OutWriter, 4, .{ .prefix = "pre: " }).init(out.writer());

        try ls.writer().writeAll("11\n22");
        //                         ^^^-^ (first pass)
        //                              ^ (second pass)
        try t.expectEqual(2, ls.slice().len); // (!) assert the merge of last incomplete line was successful
        try t.expectEqualStrings("22", ls.slice());
        try t.expectEqualStrings( // (!) assert the first line was already written
            \\pre: 11
            \\
        , out.slice());

        // (!) assert the flushExceptLastLine doesn't write the last line
        out.clear();
        try ls.flushExceptLastLine();
        try t.expectEqualStrings("", out.slice()); // nothing was written
        try t.expectEqualStrings("22", ls.slice()); // the last line stays

        out.clear();
        try ls.flushExceptLastLine();
        try t.expectEqualStrings("", out.slice()); // nothing was written
        try t.expectEqualStrings("22", ls.slice()); // the last line stays

        // (!) assert the flush writes the remaining lines
        try ls.flush();
        try t.expectEqualStrings(
            \\pre: 22
            \\
        , out.slice());

        // (!) assert the flush doesn't write twice
        try ls.flush();
        try t.expectEqualStrings(
            \\pre: 22
            \\
        , out.slice());

        out.clear();
    }
}

/// Shortcut for `LineStreamer(@TypeOf(writer), 4096, opt).init(writer)`.
pub fn lineStreamer(
    underlying_writer: anytype,
    comptime opt: LineStreamerOptions,
) LineStreamer(@TypeOf(underlying_writer), 4096, opt) {
    return .{ .underlying_writer = underlying_writer };
}

/// Shortcut for creating `LineStreamer`, writing bytes to it, and flushing.
pub fn streamByLine(
    underlying_writer: anytype,
    bytes: []const u8,
    comptime buffer_size: usize,
    comptime opt: LineStreamerOptions,
) @TypeOf(underlying_writer).Error!void {
    var ls = LineStreamer(@TypeOf(underlying_writer), buffer_size, opt).init(underlying_writer);
    try ls.writer().writeAll(bytes);
    try ls.flush();
}
