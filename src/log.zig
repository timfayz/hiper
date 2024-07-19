// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

const std = @import("std");

/// Default log options.
pub const defaults = struct {
    pub const options_identifier = "hi_options";
    pub const log_fn = if (rootHas("log_fn")) rootGet("log_fn") else logFn;
    pub const log_scopes = blk: {
        if (rootHas("log_scopes")) {
            const scopes = rootGet("log_scopes");
            if (@typeInfo(@TypeOf(scopes)) != .Struct)
                @compileError("log_scopes must be a tuple");
            break :blk scopes;
        } else break :blk .{.unscoped}; // default value
    };

    pub fn logFn(
        comptime format: []const u8,
        args: anytype,
    ) !void {
        std.debug.lockStdErr();
        defer std.debug.unlockStdErr();
        const stderr = std.io.getStdErr().writer();
        var bw = std.io.bufferedWriter(stderr);
        nosuspend {
            bw.writer().print(format, args) catch return;
            bw.flush() catch return;
        }
    }

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

/// Initializes print functions under the `.tag` scope using `.log_fn`.
/// Ensure the tag is present in `.log_scopes` for prints to function.
pub fn scope(
    s: struct {
        tag: @TypeOf(.Enum),
        prefix: []const u8 = "",
        log_fn: fn (comptime format: []const u8, args: anytype) anyerror!void = defaults.log_fn,
    },
) type {
    return struct {
        /// Prints a formatted string with a scope prefix.
        pub fn print(comptime fmt: []const u8, args: anytype) !void {
            if (!scopeActive(s.tag)) return;
            try s.log_fn(s.prefix ++ fmt, args);
        }

        /// Formats a string, splits it by lines, and prints each line with a
        /// scope prefix. If prefix is empty, uses `print()` directly instead.
        pub fn printPerLine(alloc: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
            if (!scopeActive(s.tag)) return;
            if (s.prefix.len == 0) return @This().print(fmt, args);

            const res = try std.fmt.allocPrint(alloc, fmt, args);
            defer alloc.free(res);
            var iter = std.mem.splitScalar(u8, res, '\n');
            while (iter.next()) |line| {
                try s.log_fn(s.prefix ++ "{s}\n", .{line});
            }
        }

        /// Prints a string with a scope prefix adding a newline at the end.
        pub fn printString(str: []const u8) !void {
            if (!scopeActive(s.tag)) return;
            try s.log_fn(s.prefix ++ "{s}\n", .{str});
        }

        /// Splits a string and prints each line with a scope prefix. If prefix
        /// is empty, uses `printString()` directly instead.
        pub fn printStringPerLine(str: []const u8) !void {
            if (!scopeActive(s.tag)) return;
            if (s.prefix.len == 0) return @This().printString(str);

            var iter = std.mem.splitScalar(u8, str, '\n');
            while (iter.next()) |line| {
                try s.log_fn(s.prefix ++ "{s}\n", .{line});
            }
        }
    };
}

/// Default scope for immediate use.
const unscoped = scope(.{ .tag = .unscoped });

/// Prints a formatted string within `.unscoped` scope using
/// `defaults.log_fn`. Use `scope(...).print` to initialize your own scope.
/// Or use `defaults.logFn()` for raw, unconditional logging.
pub const print = unscoped.print;

/// Formats a string, splits it by lines, and prints each line within
/// `.unscoped` scope using `defaults.log_fn`.
pub const printPerLine = unscoped.printPerLine;

/// Prints a string within `.unscoped` scope using `defaults.log_fn`.
pub const printString = unscoped.printString;

/// Splits a string and prints each line within `.unscoped` scope using
/// `defaults.log_fn`.
pub const printStringPerLine = unscoped.printStringPerLine;
