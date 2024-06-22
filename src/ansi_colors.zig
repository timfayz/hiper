const std = @import("std");

fn collateCodes(comptime codes: anytype) []const u8 {
    comptime var esc_code: []const u8 = "";
    inline for (@as([codes.len]Color, codes)) |color|
        esc_code = esc_code ++ color.toInt() ++ ";"; // code;code;
    esc_code = "\x1b[" ++ esc_code[0..esc_code.len -| 1] ++ "m";
    return esc_code;
}

pub fn escape(alloc: std.mem.Allocator, comptime colors: anytype, text: []const u8) ![]const u8 {
    const esc_code = collateCodes(colors);
    var escaped = try std.ArrayList(u8).initCapacity(alloc, text.len + esc_code.len + Color.reset_code.len);
    escaped.appendSliceAssumeCapacity(esc_code);
    escaped.appendSliceAssumeCapacity(text);
    escaped.appendSliceAssumeCapacity(Color.reset_code);
    return escaped.toOwnedSlice();
}

pub fn ctEscape(comptime colors: anytype, comptime text: []const u8) []const u8 {
    return collateCodes(colors) ++ text ++ Color.reset_code;
}

pub const Color = enum(u8) {
    // formatting
    bold = 1,
    faint = 2,
    italic = 3,
    underline = 4,
    blink = 5,
    strike = 9,

    // foreground color
    black = 30,
    red = 31,
    green = 32,
    yellow = 33,
    blue = 34,
    magenta = 35,
    cyan = 36,
    white = 37,
    default = 39,

    // background color
    black_bg = 40,
    red_bg = 41,
    green_bg = 42,
    yellow_bg = 43,
    blue_bg = 44,
    magenta_bg = 45,
    cyan_bg = 46,
    white_bg = 47,
    default_bg = 49,

    // brights
    bright_black = 90,
    bright_black_bg = 100,
    bright_white = 97,
    bright_white_bg = 107,

    const reset_code = "\x1b[m";

    inline fn toInt(self: Color) []const u8 {
        return std.fmt.comptimePrint("{d}", .{@intFromEnum(self)});
    }

    inline fn toEscapeCode(self: Color) []const u8 {
        return "\x1b[" ++ std.fmt.comptimePrint("{d}", .{@intFromEnum(self)}) ++ "m";
    }
};
