// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

const std = @import("std");

/// Prints under the `.unscoped` scope using `defaults.log_fn`.
/// Use `defaults.logFn()` for raw, unconditional logging.
pub const print = scope(.{ .tag = .unscoped }).print;

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
    ) void {
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

/// Initializes print functions under the `.tag` scope.
/// Ensure the tag is present in `.log_scopes` for prints to function.
pub fn scope(
    s: struct {
        tag: @TypeOf(.Enum),
        prefix: []const u8 = "",
        log_fn: fn (comptime format: []const u8, args: anytype) void = defaults.log_fn,
    },
) type {
    return struct {
        /// Prints a formatted string using `.log_fn` within a given scope.
        pub fn print(comptime fmt: []const u8, args: anytype) void {
            if (!scopeActive(s.tag)) return;
            s.log_fn(s.prefix ++ fmt, args);
        }

        /// Formats a string, splits it by lines, and prints each line within
        /// a given scope.
        pub fn printPerLine(alloc: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
            if (!scopeActive(s.tag)) return;
            const res = try std.fmt.allocPrint(alloc, fmt, args);
            defer alloc.free(res);
            var iter = std.mem.splitScalar(u8, res, '\n');
            while (iter.next()) |line| {
                s.log_fn(s.prefix ++ "{s}\n", .{line});
            }
        }

        /// Prints a string using `.log_fn` within a given scope.
        pub fn printString(str: []const u8) void {
            if (!scopeActive(s.tag)) return;
            s.log_fn(s.prefix ++ "{s}", .{str});
        }

        /// Splits a string and prints each line within a given scope.
        pub fn printStringPerLine(str: []const u8) void {
            if (!scopeActive(s.tag)) return;
            var iter = std.mem.splitScalar(u8, str, '\n');
            while (iter.next()) |line| {
                defaults.log_fn(s.prefix ++ "{s}\n", .{line});
            }
        }
    };
}
