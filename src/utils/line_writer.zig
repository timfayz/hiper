// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

//! Public API:
//! - BufferedLineWriterOptions
//! - bufferedLineWriter()
//! - writeByLine()
//! - BufferedLineWriter()

const std = @import("std");

pub const BufferedLineWriterOptions = struct {
    /// Prefix added to each line.
    prefix: []const u8 = "",
    /// Postfix added before '\n' on each line.
    postfix: []const u8 = "",
    /// Skip last empty line when `flush()` is called.
    skip_last_empty_line: bool = true,
    /// Use `std.debug.lockStdErr()` while writing to the underlying writer.
    lock_stderr_on_flush: bool = false,
};

/// Shortcut for `BufferedLineWriter(@TypeOf(writer), 4096, opt).init(writer)`.
pub fn bufferedLineWriter(
    underlying_writer: anytype,
    comptime opt: BufferedLineWriterOptions,
) BufferedLineWriter(@TypeOf(underlying_writer), 4096, opt) {
    return .{ .underlying_writer = underlying_writer };
}

/// Shortcut for creating `BufferedLineWriter`, writing bytes to it, and flushing.
pub fn writeByLine(
    underlying_writer: anytype,
    bytes: []const u8,
    comptime buffer_size: usize,
    comptime opt: BufferedLineWriterOptions,
) @TypeOf(underlying_writer).Error!void {
    var blw = BufferedLineWriter(@TypeOf(underlying_writer), buffer_size, opt).init(underlying_writer);
    try blw.writer().writeAll(bytes);
    try blw.flush();
}

/// A writer that streams the buffer line by line. If a line exceeds the buffer,
/// it splits it by the buffer size. To render lines correctly, lines should not
/// exceed `buffer_size - 1`. After writing is complete, use `flush()` to write
/// out the remaining buffered data.
pub fn BufferedLineWriter(WriterType: type, buffer_size: usize, opt: BufferedLineWriterOptions) type {
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

test BufferedLineWriter {
    const t = std.testing;
    var out = std.BoundedArray(u8, 512){};
    const OutWriter = @TypeOf(out.writer());

    // normal usage
    {
        // shortcuts
        try writeByLine(out.writer(), "hello world", 6, .{ .prefix = "pre: " });
        try t.expectEqualStrings(
            \\pre: hello 
            \\pre: world
            \\
        , out.slice());
        out.clear();

        var blw0 = bufferedLineWriter(out.writer(), .{ .prefix = "pre: " });
        try blw0.print("hello world", .{});
        try t.expectEqualStrings(
            \\pre: hello world
            \\
        , out.slice());
        out.clear();

        // [.prefix]
        var blw1 = BufferedLineWriter(OutWriter, 4, .{
            .prefix = "pre: ",
        }).init(out.writer());

        // write empty string
        try blw1.writer().print("", .{});
        try blw1.flush();

        try t.expectEqualStrings( // nothing to flush out
            \\
        , out.slice());
        out.clear();

        // write empty newline
        try blw1.writer().print("\n", .{});
        try blw1.flush();

        try t.expectEqualStrings(
            \\pre: 
            \\
        , out.slice());
        out.clear();

        // normal write
        try blw1.writer().print("111\n222\n333\n", .{});
        try blw1.flush();

        try t.expectEqualStrings(
            \\pre: 111
            \\pre: 222
            \\pre: 333
            \\
        , out.slice());
        out.clear();

        // write lines that exceeds the internal buffer
        try blw1.writer().print("1111x\n2222y\n3333z\n", .{});
        try blw1.flush();

        try t.expectEqualStrings(
            \\pre: 1111
            \\pre: x
            \\pre: 2222
            \\pre: y
            \\pre: 3333
            \\pre: z
            \\
        , out.slice());
        out.clear();

        // [.skip_last_empty_line]
        var blw2 = BufferedLineWriter(OutWriter, 4, .{
            .prefix = "pre: ",
            .skip_last_empty_line = false,
        }).init(out.writer());

        // check if the trailing empty line is written
        try blw2.writer().print("111\n222\n333\n", .{});
        try blw2.flush();

        try t.expectEqualStrings(
            \\pre: 111
            \\pre: 222
            \\pre: 333
            \\pre: 
            \\
        , out.slice());
        out.clear();

        // [.postfix]
        var blw3 = BufferedLineWriter(OutWriter, 4, .{
            .postfix = " :post",
        }).init(out.writer());

        try blw3.writer().print("11112222", .{});
        try blw3.flush();

        try t.expectEqualStrings(
            \\1111 :post
            \\2222 :post
            \\
        , out.slice());
        out.clear();
    }

    // test internals
    {
        var blw = BufferedLineWriter(OutWriter, 4, .{
            .prefix = "pre: ",
            .skip_last_empty_line = false,
        }).init(out.writer());

        try t.expectEqual(blw.slice().len, 0); // (!) assert the slice is empty by default

        const written = try blw.write("1\n2\n3\n4");
        //                             ^^^^^^ write 4 bytes, 3 lines, the last one will be empty

        try t.expectEqual(4, written); // (!) assert a larger input is written to a smaller buffer
        try t.expectEqual(blw.slice().len, 4); // and the slice grows
        try t.expectEqualStrings( // (!) assert the pending output
            \\1
            \\2
            \\
        , blw.slice());
        try t.expectEqualStrings( // (!) assert nothing was yet written to the output
            \\
        , out.slice());

        try blw.flush();
        try t.expectEqual(0, blw.index); // (!) assert the flush resets the index
        try t.expectEqual(blw.slice().len, 0); // and the slice gets empty again
        try t.expectEqualStrings( // (!) assert the flush writes out the buffer
            \\pre: 1
            \\pre: 2
            \\pre: 
            \\
        , out.slice());

        try blw.flush();
        try t.expectEqualStrings( // (!) assert flushing an empty buffer doesn't write multiple times
            \\pre: 1
            \\pre: 2
            \\pre: 
            \\
        , out.slice());

        out.clear();
    }
    {
        var blw = BufferedLineWriter(OutWriter, 4, .{ .prefix = "pre: " }).init(out.writer());

        try blw.writer().writeAll("11\n22");
        //                         ^^^-^ (first pass)
        //                              ^ (second pass)
        try t.expectEqual(2, blw.slice().len); // (!) assert the merge of last incomplete line was successful
        try t.expectEqualStrings("22", blw.slice());
        try t.expectEqualStrings( // (!) assert the first line was already written
            \\pre: 11
            \\
        , out.slice());

        // (!) assert the flushExceptLastLine doesn't write the last line
        out.clear();
        try blw.flushExceptLastLine();
        try t.expectEqualStrings("", out.slice()); // nothing was written
        try t.expectEqualStrings("22", blw.slice()); // the last line stays

        out.clear();
        try blw.flushExceptLastLine();
        try t.expectEqualStrings("", out.slice()); // nothing was written
        try t.expectEqualStrings("22", blw.slice()); // the last line stays

        // (!) assert the flush writes the remaining lines
        try blw.flush();
        try t.expectEqualStrings(
            \\pre: 22
            \\
        , out.slice());

        // (!) assert the flush doesn't write twice
        try blw.flush();
        try t.expectEqualStrings(
            \\pre: 22
            \\
        , out.slice());

        out.clear();
    }
}
