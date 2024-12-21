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

const std = @import("std");
const builtin = @import("builtin");

/// Default log options.
pub const defaults = struct {
    pub const options_identifier = "hi_options";
    /// Default's log_writer. If not set, it will default to `std.io.getStdErr().writer()`.
    pub const log_writer = if (rootHas("log_writer")) rootGet("log_writer") else std.io.getStdErr().writer();
    /// Buffer size for the log writer. If the buffer is full, it will be
    /// flushed, meaning that the max line size is `log_buffer_size - 1`.
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
        if (@typeInfo(@TypeOf(scopes)) != .Struct)
            @compileError("log_scopes must be a tuple");
        break :blk scopes;
    } else .{.log}; // default scope

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

/// Initializes print and writer interface functions under the `tag` scope. Thin
/// wrapper around PerLineWriter, meaning it writes line by line adding pre/postfix
/// around. If `opt.Writer` type is not specified, the `defaults.log_writer` is used.
/// Ensure the tag is present in `.log_scopes` for the scope to function.
///
/// Use cases:
/// ```
/// // New scope with `defaults.log_writer`
/// var my_scope = scope(.scope_name, .{}){}; // no need to use .init()
/// try my_scope.print("hello world!", .{}); // `scope_name: hello world!`
///
/// // New scope with custom prefix
/// var my_scope = scope(.scope_name, .{.prefix = "p -> "}){};
/// try my_scope.print("hello world!", .{}); // `p -> hello world!`
///
/// // New scope with custom writer
/// const my_writer = std.io.getStdOut().writer();
/// var my_scope = scope(.scope_name, .{.Writer = @TypeOf(my_writer)}).init(my_writer);
/// try my_scope.print("hello world!", .{});
/// ```
pub fn scope(
    tag: @TypeOf(.Enum),
    opt: struct {
        prefix: []const u8 = @tagName(tag) ++ ": ",
        postfix: []const u8 = "",
        buffer_size: usize = defaults.log_buffer_size,
        lock_stderr_on_flush: bool = defaults.log_lock_stderr_on_flush,
        WriterType: ?type = null,
    },
) type {
    const UnderlyingWriter = if (opt.WriterType) |T| T else @TypeOf(defaults.log_writer);
    const WrappingWriter = @import("line_writer.zig").BufferedLineWriter(UnderlyingWriter, opt.buffer_size, .{
        .prefix = defaults.log_prefix_all_scopes ++ opt.prefix,
        .postfix = opt.postfix,
        .lock_stderr_on_flush = opt.lock_stderr_on_flush,
    });

    return struct {
        underlying_writer: WrappingWriter =
            WrappingWriter.init(if (opt.WriterType) |_| undefined else defaults.log_writer),

        const Self = @This();
        const Error = WrappingWriter.Error;
        const Writer = std.io.Writer(*Self, Error, write);

        pub fn init(underlying_writer: anytype) Self {
            if (opt.WriterType == null) @compileError("provide opt.WriterType when initializing scope(...){}");
            return Self{ .underlying_writer = WrappingWriter.init(underlying_writer) };
        }

        /// Prints a formatted string within the specified `tag` scope using
        /// `defaults.log_writer` and flushes automatically.
        pub fn print(s: *Self, comptime format: []const u8, args: anytype) Error!void {
            if (!builtin.is_test and !scopeActive(tag)) return;
            try s.underlying_writer.writer().print(format, args);
            try s.underlying_writer.flush();
        }

        /// Write primitive within the specified `tag` scope.
        pub fn write(s: *Self, bytes: []const u8) Error!usize {
            if (!builtin.is_test and !scopeActive(tag)) return bytes.len;
            return s.underlying_writer.write(bytes);
        }

        /// Flushes the entire buffer to the writer. Use this to ensure the
        /// buffer is written out after multiple writes via the `writer`
        /// interface or `write` function directly.
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
var defaultScope = scope(.log, .{ .prefix = defaults.log_prefix_default_scope }){};

/// Prints a formatted string within the default `.log` scope using
/// `defaults.log_writer`. Use `scope(..)` to initialize your own scope.
pub const print = defaultScope.print;

/// Returns writer interface within the default `.log` scope. If the scope is
/// inactive, it becomes a "null writer".
pub const writer = defaultScope.writer;

/// Write primitive within the default `.log` scope.
pub const writeFn = defaultScope.write;

/// Flushes the entire buffer within the default `.log` scope. Use this to
/// ensure the buffer is written out after multiple writes via the `writer`
/// interface or `writeFn` directly.
pub const flush = defaultScope.flush;

test scope {
    const t = std.testing;
    var out = std.BoundedArray(u8, 512){};
    const out_writer = out.writer();

    var phony_scope = scope(.not_exist, .{
        .WriterType = @TypeOf(out_writer),
    }).init(out_writer);

    if (scopeActive(.not_exist))
        try phony_scope.print("hello", .{});

    if (scopeActive(.log))
        try phony_scope.print("world", .{});

    try t.expectEqualStrings(
        \\not_exist: world
        \\
    , out.slice());
    out.clear();

    var sc = scope(.tag, .{
        .buffer_size = 10,
        .WriterType = @TypeOf(out_writer),
    }).init(out_writer);

    try sc.print("long print", .{});
    try sc.print("very long print", .{});

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
