// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

const std = @import("std");
const root = @import("root");

pub const print = defaults.logFn;
pub const err = scope(.unscoped).err;
pub const debug = scope(.unscoped).debug;

pub const Level = struct {
    pub const debug = 0b100;
    pub const err = 0b010;
};

pub const defaults = struct {
    pub const root_options_identifier = "hi_options";
    pub const log_scopes = if (rootHas("log_scopes")) rootGet("log_scopes") else .{.unscoped};
    pub const log_levels = if (rootHas("log_levels")) rootGet("log_levels") else Level.err | Level.debug;
    pub const log_err_prefix = if (rootHas("log_err_prefix")) rootGet("log_err_prefix") else "";
    pub const log_debug_prefix = if (rootHas("log_debug_prefix")) rootGet("log_debug_prefix") else "";

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

    fn rootHas(comptime name: []const u8) bool {
        return @hasDecl(root, root_options_identifier) and
            @hasField(@TypeOf(@field(root, root_options_identifier)), name);
    }

    fn rootGet(comptime name: []const u8) blk: {
        if (!rootHas(name))
            @compileError(root_options_identifier ++ " does not have this option.");
        break :blk @TypeOf(@field(@field(root, root_options_identifier), name));
    } {
        return @field(@field(root, root_options_identifier), name);
    }
};

pub fn scopeActive(scope_tag: @TypeOf(.Enum)) bool {
    const fields = std.meta.fields(@TypeOf(defaults.log_scopes));
    inline for (fields) |field| {
        if (@field(defaults.log_scopes, field.name) == scope_tag) return true;
    }
    return false;
}

pub fn scope(scope_tag: @TypeOf(.Enum)) type {
    const tag = struct {
        pub fn within(tuple: anytype, tag: @TypeOf(.Enum)) bool {
            const info = @typeInfo(@TypeOf(tuple));
            if (info != .Struct) @compileError("provide a literal tuple");
            inline for (info.Struct.fields) |field| {
                if (@field(tuple, field.name) == tag) return true;
            }
            return false;
        }
    };

    return struct {
        pub fn err(comptime fmt: []const u8, args: anytype) void {
            if (defaults.log_levels & Level.err == 0) return;
            if (!tag.within(defaults.log_scopes, scope_tag)) return;
            defaults.logFn(defaults.log_err_prefix ++ fmt, args);
        }

        pub fn debug(comptime fmt: []const u8, args: anytype) void {
            if (defaults.log_levels & Level.debug == 0) return;
            if (!tag.within(defaults.log_scopes, scope_tag)) return;
            defaults.logFn(defaults.log_debug_prefix ++ fmt, args);
        }
    };
}
