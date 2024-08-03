// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

const std = @import("std");

pub const BufferedPerLineWriterOptions = struct {
    Writer: type,
    prefix: []const u8 = "",
    postfix: []const u8 = "",
    buffer_size: usize = 4096,
    skip_last_empty_line: bool = true,
    lock_stderr_on_flush: bool = false,
};

/// A writer that streams the buffer line by line. If a line exceeds the buffer,
/// it splits it by the buffer size. To render lines correctly, lines should not
/// exceed `buffer_size - 1`. After writing is complete, use `flush()` to write
/// out the remaining buffered data to the underlying writer.
pub fn BufferedPerLineWriter(opt: BufferedPerLineWriterOptions) type {
    if (opt.buffer_size < 1) @compileError("buffer_size cannot be less than 1");
    return struct {
        underlying_writer: opt.Writer,
        buf: [opt.buffer_size]u8 = undefined,
        idx: usize = 0,

        const Self = @This();
        pub const Error = opt.Writer.Error;
        pub const Writer = std.io.Writer(*Self, Error, write);

        pub fn init(underlying_writer: opt.Writer) Self {
            return Self{ .underlying_writer = underlying_writer };
        }

        /// Returns the portion of the buffer that has been filled with data.
        pub inline fn slice(s: *Self) []u8 {
            return s.buf[0..s.idx];
        }

        /// Writes bytes to the internal buffer. If bytes do not fit, flushes
        /// the stored bytes except the last line before writing to the remaining
        /// buffer space.
        pub fn write(s: *Self, bytes: []const u8) Error!usize {
            // if bytes do not fit, parse and flush stored bytes first
            if (s.idx + bytes.len > s.buf.len) {
                try s.flushExceptLastLine();
            }

            // store bytes into the remaining buffer space
            const buf_left = s.buf.len - s.idx;
            const write_amt = @min(buf_left, bytes.len);
            @memcpy(s.buf[s.idx .. s.idx + write_amt], bytes[0..write_amt]);
            s.idx += write_amt;

            return write_amt;
        }

        pub fn writer(s: *Self) Writer {
            return .{ .context = s };
        }

        /// Flushes the entire stream buffer line by line. Does not consider
        /// whether the last line is complete. Use it once after writing
        /// process is completed.
        pub fn flush(s: *Self) Error!void {
            if (opt.lock_stderr_on_flush) std.debug.lockStdErr();
            defer if (opt.lock_stderr_on_flush) std.debug.unlockStdErr();

            const buf = s.slice();

            // print empty buffer as an empty line (s.idx = 0 already)
            if (buf.len == 0) return s.writeLineImpl("");

            var iter = std.mem.splitScalar(u8, buf, '\n');
            while (iter.next()) |line| {
                if (opt.skip_last_empty_line and
                    iter.index == null and line.len == 0)
                    break;
                try s.writeLineImpl(line);
            }
            s.idx = 0;
        }

        /// Flushes the entire stream buffer line by line up to the last
        /// complete line. The last line is always assumed incomplete and
        /// is moved to the beginning of the buffer to allow continuation.
        fn flushExceptLastLine(s: *Self) Error!void {
            if (opt.lock_stderr_on_flush) std.debug.lockStdErr();
            defer if (opt.lock_stderr_on_flush) std.debug.unlockStdErr();

            if (s.idx == 0) return;
            var iter = std.mem.splitScalar(u8, s.slice(), '\n');
            while (iter.next()) |line| {
                if (iter.index == null) { // reached the end
                    if (line.len == s.buf.len) { // the entire buffer was a single line (no '\n's)
                        s.idx = 0; // reset buffer and write the line "as is", without splitting
                    } else if (s.idx - line.len == 0) {
                        break; // the last line is already at the beginning of the buffer
                    } else { // otherwise, move the line to the buffer start
                        for (line, 0..) |byte, i| s.buf[i] = byte;
                        s.idx = line.len;
                        break;
                    }
                }
                try s.writeLineImpl(line);
            }
        }

        /// A direct write of a line with a configured prefix and postfix.
        /// Should not be used directly.
        inline fn writeLineImpl(s: *Self, line: []const u8) Error!void {
            if (opt.prefix.len > 0) try s.underlying_writer.writeAll(opt.prefix);
            try s.underlying_writer.writeAll(line);
            try s.underlying_writer.writeAll(if (opt.postfix.len > 0) opt.postfix ++ "\n" else "\n");
        }
    };
}

test {
    const t = std.testing;

    // test internals
    {
        var out = std.ArrayList(u8).init(t.allocator);
        const WriterType = @TypeOf(out.writer());
        defer out.deinit();

        {
            var plw = BufferedPerLineWriter(.{
                .Writer = WriterType,
                .prefix = "p: ",
                .buffer_size = 4,
                .skip_last_empty_line = false,
            }).init(out.writer());

            try t.expectEqual(plw.slice().len, 0); // (!) assert the slice is empty by default

            const written = try plw.write("1\n2\n3\n4");
            //                             ^^-^^- 4 bytes, 3 lines, the last one is empty
            try t.expectEqual(4, written); // (!) assert a larger input is written to a smaller buffer
            try t.expectEqual(plw.slice().len, 4); // and the slice grows

            try plw.flush();
            try t.expectEqual(0, plw.idx); // (!) assert flush resets the index
            try t.expectEqual(plw.slice().len, 0); // and the slice gets empty again

            try t.expectEqualStrings( // (!) assert buffer contains three lines
                \\p: 1
                \\p: 2
                \\p: 
                \\
            , out.items);
            out.clearAndFree();
        }
        {
            var plw = BufferedPerLineWriter(.{ .Writer = WriterType, .buffer_size = 4, .prefix = "p: " }).init(out.writer());

            const written = try plw.write("12");
            try t.expectEqual(2, written); // (!) assert a smaller input is written to a larger buffer
            out.clearAndFree();
        }
        {
            var plw = BufferedPerLineWriter(.{ .Writer = WriterType, .buffer_size = 1 }).init(out.writer());

            try plw.writer().writeAll("123456");
            try t.expectEqual('6', plw.slice()[0]); // (!) assert the writer interface was able to write all bytes
            out.clearAndFree();
        }
        {
            var plw = BufferedPerLineWriter(.{ .Writer = WriterType, .buffer_size = 4, .prefix = "p: " }).init(out.writer());

            try plw.writer().writeAll("11\n22");
            //                         ^^^-^ (first pass)
            //                              ^ (second pass)
            try t.expectEqual(2, plw.slice().len); // (!) assert the merge of last incomplete line was successful
            try t.expectEqualStrings("22", plw.slice());
            try t.expectEqualStrings( // (!) assert the first line was written to fit the next one
                \\p: 11
                \\
            , out.items);

            // (!) assert except-the-last-line flushes do not write the last line
            out.clearAndFree();
            try plw.flushExceptLastLine();
            try t.expectEqualStrings("", out.items); // nothing was written
            try t.expectEqualStrings("22", plw.slice()); // the last line stays

            out.clearAndFree();
            try plw.flushExceptLastLine();
            try t.expectEqualStrings("", out.items); // nothing was written
            try t.expectEqualStrings("22", plw.slice()); // the last line stays

            // (!) assert the "full" flush writes the remaining lines
            try plw.flush();
            try t.expectEqualStrings(
                \\p: 22
                \\
            , out.items);

            out.clearAndFree();
        }

        // (!) assert a single byte buffer behaves correctly
        {
            var plw = BufferedPerLineWriter(.{ .Writer = WriterType, .buffer_size = 1, .prefix = "p: " }).init(out.writer());
            try plw.writer().writeAll("y\nz");
            try plw.flush();
            try t.expectEqualStrings(
                \\p: y
                \\p: 
                \\p: z
                \\
            , out.items);
            out.clearAndFree();
        }
    }

    // test normal usage
    {
        const case = struct {
            pub fn run(
                input: []const u8,
                comptime expect_prefixed: []const u8,
                comptime expect_unprefixed: []const u8,
            ) !void {
                var buf = std.ArrayList(u8).init(t.allocator);
                defer buf.deinit();
                {
                    var plw = BufferedPerLineWriter(.{
                        .Writer = @TypeOf(buf.writer()),
                        .prefix = "p: ",
                        .buffer_size = 4, // (!) 4-byte size buffer
                        .skip_last_empty_line = true,
                    }).init(buf.writer());

                    try plw.writer().writeAll(input);
                    try plw.flush();

                    try t.expectEqualStrings(expect_prefixed, buf.items);
                    buf.clearAndFree();
                }
                {
                    var plw = BufferedPerLineWriter(.{
                        .Writer = @TypeOf(buf.writer()),
                        .prefix = "",
                        .buffer_size = 4,
                        .skip_last_empty_line = true,
                    }).init(buf.writer());

                    try plw.writer().writeAll(input);
                    try plw.flush();

                    try t.expectEqualStrings(expect_unprefixed, buf.items);
                }
            }
        };

        try case.run("",
            \\p: 
            \\
        ,
            \\
            \\
        );

        try case.run("\n",
            \\p: 
            \\
        ,
            \\
            \\
        );

        try case.run("1\n2",
            \\p: 1
            \\p: 2
            \\
        ,
            \\1
            \\2
            \\
        );

        try case.run("111\n222\n333",
            \\p: 111
            \\p: 222
            \\p: 333
            \\
        ,
            \\111
            \\222
            \\333
            \\
        );

        // (!) a 4-byte size buffer cannot split correctly 3+ byte lines
        try case.run("11111\n22222\n33333",
            \\p: 1111
            \\p: 1
            \\p: 2222
            \\p: 2
            \\p: 3333
            \\p: 3
            \\
        ,
            \\1111
            \\1
            \\2222
            \\2
            \\3333
            \\3
            \\
        );
    }
}
