// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

//! Public API:
//! - Side
//! - TruncMode
//! - Options
//! - Mode
//! - Span
//! - Range

const std = @import("std");
const num = @import("num.zig");
const meta = @import("meta.zig");

pub const Side = enum { left, right };
pub const TruncMode = enum { hard, hard_flex, soft };

pub const Options = struct {
    rshift_uneven: bool = true,
    fit: ?struct { min_pad: usize = 0 } = null,
    shift: ?union(Side) { left: usize, right: usize } = null,
    extra_side: Side = .right,
    trunc_mode: TruncMode = .hard,
};

pub const Mode = union(enum) {
    // first: ?usize,
    // last: ?usize,
    // middle: ?usize,
    // all: ?void,
    // one: ?void,
    left: ?usize,
    right: ?usize,
    around: ?usize,
    custom: Span, // native

    pub fn toSpan(
        self: Mode,
        extra: usize,
        comptime opt: Options,
    ) if (opt.fit == null) Span else ?Span {
        if (opt.fit) |fit| {
            if (switch (self) {
                .around => extra +| fit.min_pad *| 2 > self.len(),
                inline .left, .right => extra +| fit.min_pad > self.len(),
                .custom => extra > self.len(),
            }) return null;
        }

        var span: Span = .{ .left = 0, .right = 0 };
        const span_extends = opt.fit == null;
        switch (self) {
            .left => {
                span.left = if (span_extends) self.len() else self.len() - extra;
                span.extendSide(opt.extra_side, extra);
            },
            .right => {
                span.right = if (span_extends) self.len() else self.len() - extra;
                span.extendSide(opt.extra_side, extra);
            },
            .around => {
                const avail_len = if (span_extends) self.len() else self.len() - extra;
                span = .{ .left = avail_len / 2, .right = avail_len / 2 };
                if (avail_len & 1 != 0) { // compensate lost item during odd division
                    if (opt.rshift_uneven) span.right +|= 1 else span.left +|= 1;
                }
                span.extendSide(opt.extra_side, extra);
            },
            .custom => |amt| {
                span = .{ .left = amt.left, .right = amt.right };
                if (span_extends) span.extendSide(opt.extra_side, extra);
            },
        }

        if (opt.shift) |shift| switch (shift) {
            .left => |amt| span.shift(shift, amt),
            .right => |amt| span.shift(shift, amt),
        };

        return span;
    }

    // pub fn toRange(
    //     self: Mode,
    //     extra: usize,
    //     pos: usize,
    //     within: Range,
    //     comptime opt: Options,
    // ) ?Range {
    //     const span = self.toSpanExtra(extra, opt);
    //     if (meta.isOptional(span))
    //         if (span) |v| v.toRange(within, pos, opt.compensate) else null;
    //     return span.toRange(within, pos, opt.compensate);
    // }

    pub fn len(self: Mode) usize {
        return switch (self) {
            // .all => std.math.maxInt(usize),
            .custom => |amt| amt.left +| amt.right,
            inline else => |amt| amt orelse std.math.maxInt(usize),
        };
    }
};

test Mode {
    const equal = std.testing.expectEqualDeep;
    const max = std.math.maxInt(usize);

    // [len()]
    try equal(max, (Mode{ .left = null }).len());
    try equal(max, (Mode{ .right = null }).len());
    try equal(max, (Mode{ .around = null }).len());

    try equal(10, (Mode{ .left = 10 }).len());
    try equal(10, (Mode{ .right = 10 }).len());
    try equal(10, (Mode{ .around = 10 }).len());
    try equal(10, (Mode{ .custom = .{ .left = 4, .right = 6 } }).len());

    // [toSpan()]

    // [.fit == null]
    // [.left]
    try equal(Span{ .left = 10, .right = 0 }, (Mode{ .left = 10 }).toSpan(0, .{}));
    try equal(Span{ .left = 10, .right = 4 }, (Mode{ .left = 10 }).toSpan(4, .{ .extra_side = .right }));
    try equal(Span{ .left = 14, .right = 0 }, (Mode{ .left = 10 }).toSpan(4, .{ .extra_side = .left }));
    // [.right]
    try equal(Span{ .left = 0, .right = 10 }, (Mode{ .right = 10 }).toSpan(0, .{}));
    try equal(Span{ .left = 0, .right = 14 }, (Mode{ .right = 10 }).toSpan(4, .{ .extra_side = .right }));
    try equal(Span{ .left = 4, .right = 10 }, (Mode{ .right = 10 }).toSpan(4, .{ .extra_side = .left }));
    // [.around]
    try equal(Span{ .left = 4, .right = 5 }, (Mode{ .around = 9 }).toSpan(0, .{}));
    try equal(Span{ .left = 5, .right = 4 }, (Mode{ .around = 9 }).toSpan(0, .{ .rshift_uneven = false }));
    try equal(Span{ .left = 9, .right = 5 }, (Mode{ .around = 9 }).toSpan(5, .{ .extra_side = .left }));
    try equal(Span{ .left = 4, .right = 10 }, (Mode{ .around = 9 }).toSpan(5, .{ .extra_side = .right }));

    // [.fit != null]
    // [.left]
    try equal(null, (Mode{ .left = 10 }).toSpan(11, .{ .fit = .{} }));
    try equal(Span{ .left = 0, .right = 10 }, (Mode{ .left = 10 }).toSpan(10, .{ .extra_side = .right, .fit = .{} }));
    try equal(Span{ .left = 6, .right = 4 }, (Mode{ .left = 10 }).toSpan(4, .{ .extra_side = .right, .fit = .{} }));
    try equal(Span{ .left = 10, .right = 0 }, (Mode{ .left = 10 }).toSpan(4, .{ .extra_side = .left, .fit = .{ .min_pad = 6 } }));
    try equal(null, (Mode{ .left = 10 }).toSpan(4, .{ .extra_side = .left, .fit = .{ .min_pad = 7 } }));
    // [.right]
    try equal(null, (Mode{ .right = 10 }).toSpan(11, .{ .fit = .{} }));
    try equal(Span{ .left = 0, .right = 10 }, (Mode{ .right = 10 }).toSpan(10, .{ .extra_side = .right, .fit = .{} }));
    try equal(Span{ .left = 4, .right = 6 }, (Mode{ .right = 10 }).toSpan(4, .{ .extra_side = .left, .fit = .{} }));
    try equal(Span{ .left = 0, .right = 10 }, (Mode{ .right = 10 }).toSpan(4, .{ .extra_side = .right, .fit = .{ .min_pad = 6 } }));
    try equal(null, (Mode{ .right = 10 }).toSpan(4, .{ .extra_side = .right, .fit = .{ .min_pad = 7 } }));
    // [.around]
    try equal(null, (Mode{ .around = 10 }).toSpan(11, .{ .fit = .{} }));
    try equal(Span{ .left = 0, .right = 10 }, (Mode{ .around = 10 }).toSpan(10, .{ .extra_side = .right, .fit = .{} }));
    try equal(Span{ .left = 2, .right = 8 }, (Mode{ .around = 10 }).toSpan(5, .{ .extra_side = .right, .fit = .{} }));
    try equal(Span{ .left = 8, .right = 2 }, (Mode{ .around = 10 }).toSpan(5, .{ .extra_side = .left, .fit = .{}, .rshift_uneven = false }));
    try equal(Span{ .left = 7, .right = 3 }, (Mode{ .around = 10 }).toSpan(5, .{ .extra_side = .left, .fit = .{} }));
    try equal(Span{ .left = 7, .right = 3 }, (Mode{ .around = 10 }).toSpan(5, .{ .extra_side = .left, .fit = .{ .min_pad = 2 } }));
    try equal(null, (Mode{ .around = 10 }).toSpan(5, .{ .extra_side = .left, .fit = .{ .min_pad = 3 } }));
}

pub const Span = struct {
    left: usize,
    right: usize,

    pub fn init(left: usize, right: usize) Span {
        return .{ .left = left, .right = right };
    }

    pub fn len(self: *const Span) usize {
        return self.left +| self.right;
    }

    pub fn shift(self: *Span, comptime side: Side, amt: usize) void {
        switch (side) {
            .left => {
                self.left +|= amt;
                self.right -|= amt;
            },
            .right => {
                self.left -|= amt;
                self.right +|= amt;
            },
        }
    }

    pub fn extendSide(self: *Span, comptime side: Side, amt: usize) void {
        switch (side) {
            .left => self.left +|= amt,
            .right => self.right +|= amt,
        }
    }

    pub fn extendBySpan(self: *Span, span: Span) void {
        self.left +|= span.left;
        self.right +|= span.right;
    }

    pub fn nonZeroSide(self: *const Span) ?Side {
        if (self.left != 0 and self.right == 0)
            return .left;
        if (self.left == 0 and self.right != 0)
            return .right;
        return null; // both 0 or 1+
    }

    pub fn toRange(
        self: *const Span,
        pos: usize,
        within: Range,
        comptime trunc_mode: TruncMode,
    ) Range {
        if (pos < within.start) { // -*- [  ]
            const end = switch (trunc_mode) {
                .hard => pos +| self.right,
                .hard_flex => pos +| self.len(),
                .soft => within.start +| self.len(),
            };
            return Range.init(within.start, @min(within.end, end));
        } else if (pos < within.end) { // [-*-]
            switch (trunc_mode) {
                .hard => {
                    const start = @max(within.start, pos -| self.left);
                    const end = @min(within.end, pos +| self.right);
                    return Range.init(start, end);
                },
                else => {
                    const start = pos -| self.left;
                    const end = pos +| self.right;
                    const unused_left = self.left - (pos - start);
                    const unused_right = self.right - (end - pos);

                    if (start < within.start) {
                        const overrun = within.start - start;
                        return Range.init(
                            within.start,
                            @min(within.end, end +| overrun +| unused_left),
                        );
                    } else if (end > within.end) {
                        const overrun = end - within.end;
                        return Range.init(
                            @max(within.start, start -| overrun -| unused_right),
                            within.end,
                        );
                    }

                    return Range.init(
                        @max(within.start, start -| unused_right),
                        @min(within.end, end +| unused_left),
                    );
                },
            }
        } else { // [  ] -*-
            const start = switch (trunc_mode) {
                .hard => pos -| self.left,
                .hard_flex => pos -| self.len(),
                .soft => within.end -| self.len(),
            };
            return Range.init(@max(within.start, start), within.end);
        }
    }
};

test Span {
    const equal = std.testing.expectEqualDeep;

    // [nonZeroSide()]
    try equal(null, Span.init(5, 5).nonZeroSide());
    try equal(null, Span.init(0, 0).nonZeroSide());
    try equal(.right, Span.init(0, 5).nonZeroSide());
    try equal(.left, Span.init(5, 0).nonZeroSide());

    // [toRange()]
    const within = Range.init(5, 10); // Range is a half-open range [2, 7)

    // -*- [  ]

    // [.hard]
    //    0123456789abcdef
    //         -----      (within)
    try equal(Range.init(5, 5), Span.init(2, 2).toRange(3, within, .hard));
    //     ~~^^
    try equal(Range.init(5, 10), Span.init(2, 7).toRange(3, within, .hard));
    //     ~~^^^^^^^
    try equal(Range.init(5, 10), Span.init(2, 9).toRange(3, within, .hard));
    //     ~~^^^^^^^^^

    // [.hard_flex]
    //    0123456789abcdef
    //         -----      (within)
    try equal(Range.init(5, 7), Span.init(2, 2).toRange(3, within, .hard_flex));
    //     ~~^^++
    try equal(Range.init(5, 8), Span.init(2, 2).toRange(4, within, .hard_flex));
    //      ~~^^++
    try equal(Range.init(5, 6), Span.init(2, 2).toRange(2, within, .hard_flex));
    //    ~~^^ +
    try equal(Range.init(5, 10), Span.init(2, 7).toRange(3, within, .hard_flex));
    //     ~~^^^^^^^
    try equal(Range.init(5, 10), Span.init(2, 9).toRange(3, within, .hard_flex));
    //     ~~^^^^^^^^^

    // [.soft]
    //    0123456789abcdef
    //         -----      (within)
    try equal(Range.init(5, 9), Span.init(2, 2).toRange(3, within, .soft));
    //     ~~^^++++
    try equal(Range.init(5, 9), Span.init(2, 2).toRange(2, within, .soft));
    //    ~~^^ ++++
    try equal(Range.init(5, 9), Span.init(2, 2).toRange(4, within, .soft));
    //      ~~^^+++
    try equal(Range.init(5, 10), Span.init(2, 7).toRange(3, within, .soft));
    //     ~~^^^^^^^
    try equal(Range.init(5, 10), Span.init(2, 9).toRange(3, within, .soft));
    //     ~~^^^^^^^^^

    // [  ] -*-

    // [.hard]
    //    0123456789abcdef
    //         -----      (within)
    try equal(Range.init(10, 10), Span.init(2, 2).toRange(12, within, .hard));
    //              ~~^^
    try equal(Range.init(5, 10), Span.init(7, 2).toRange(12, within, .hard));
    //         ~~~~~~~^^
    try equal(Range.init(5, 10), Span.init(9, 2).toRange(12, within, .hard));
    //       ~~~~~~~~~^^

    // [.hard_flex]
    //    0123456789abcdef
    //         -----      (within)
    try equal(Range.init(8, 10), Span.init(2, 2).toRange(12, within, .hard_flex));
    //            ++~~^^
    try equal(Range.init(9, 10), Span.init(2, 2).toRange(13, within, .hard_flex));
    //             + ~~^^
    try equal(Range.init(7, 10), Span.init(2, 2).toRange(11, within, .hard_flex));
    //           ++~~^^
    try equal(Range.init(5, 10), Span.init(7, 2).toRange(12, within, .hard_flex));
    //         ~~~~~~~^^
    try equal(Range.init(5, 10), Span.init(9, 2).toRange(12, within, .hard_flex));
    //       ~~~~~~~~~^^

    // [.soft]
    //    0123456789abcdef
    //         -----      (within)
    try equal(Range.init(6, 10), Span.init(2, 2).toRange(12, within, .soft));
    //          ++++~~^^
    try equal(Range.init(6, 10), Span.init(2, 2).toRange(13, within, .soft));
    //          ++++ ~~^^
    try equal(Range.init(6, 10), Span.init(2, 2).toRange(11, within, .soft));
    //          +++~~^^
    try equal(Range.init(5, 10), Span.init(7, 2).toRange(12, within, .soft));
    //         ~~~~~~~^^
    try equal(Range.init(5, 10), Span.init(9, 2).toRange(12, within, .soft));
    //       ~~~~~~~~~^^

    // [-*-]
    const max = std.math.maxInt(usize);
    // [.hard]
    //    0123456789abcdef
    //         -----      (within)
    try equal(Range.init(5, 10), Span.init(2, 3).toRange(7, within, .hard));
    //         ~~^^^
    try equal(Range.init(7, 10), Span.init(2, 3).toRange(9, within, .hard));
    //           ~~^^^
    try equal(Range.init(5, 8), Span.init(2, 3).toRange(5, within, .hard));
    //       ~~^^^
    try equal(Range.init(5, 10), Span.init(max, max).toRange(7, within, .hard));
    //       ~~~~^^^^^

    // [.hard_flex]
    //    0123456789abcdef
    //         -----      (within)
    try equal(Range.init(5, 9), Span.init(2, 2).toRange(7, within, .hard_flex));
    //         ~~^^
    try equal(Range.init(6, 10), Span.init(2, 2).toRange(9, within, .hard_flex));
    //          +~~^^
    try equal(Range.init(6, 10), Span.init(2, 2).toRange(10, within, .hard_flex));
    //          ++~~^^
    try equal(Range.init(5, 9), Span.init(2, 2).toRange(5, within, .hard_flex));
    //       ~~^^++
    try equal(Range.init(5, 10), Span.init(max, max).toRange(7, within, .hard_flex));
    //       ~~~~^^^^^

    // [.soft]
    //    0123456789abcdef
    //         -----      (within)
    try equal(Range.init(5, 9), Span.init(2, 2).toRange(7, within, .soft));
    //         ~~^^
    try equal(Range.init(6, 10), Span.init(2, 2).toRange(9, within, .soft));
    //          +~~^^
    try equal(Range.init(6, 10), Span.init(2, 2).toRange(10, within, .soft));
    //          ++~~^^
    try equal(Range.init(5, 9), Span.init(2, 2).toRange(5, within, .soft));
    //       ~~^^++
    try equal(Range.init(5, 10), Span.init(max, max).toRange(7, within, .soft));
    //       ~~~~^^^^^

    // special case: span overflows type boundaries

    // [.hard_flex, .soft]
    const within1 = Range.init(1, 7);
    //    012345678
    //     ------     (within)
    //   ~~~^+++
    try equal(Range.init(1, 6), Span.init(3, 2).toRange(2, within1, .soft));
    try equal(Range.init(1, 6), Span.init(3, 2).toRange(2, within1, .hard_flex));

    const within2 = Range.init(0, 6);
    //    012345678
    //    ------     (within)
    // ~~~^^+++
    try equal(Range.init(0, 5), Span.init(3, 2).toRange(0, within2, .soft));
    try equal(Range.init(0, 5), Span.init(3, 2).toRange(0, within2, .hard_flex));

    const within3 = Range.init(max - 7, max - 1);
    //    max_int
    //    ------     (within)
    //     ++~^^^^
    try equal(Range.init(max - 6, max - 1), Span.init(1, 4).toRange(max - 2, within3, .soft));
    try equal(Range.init(max - 6, max - 1), Span.init(1, 4).toRange(max - 2, within3, .hard_flex));

    const within4 = Range.init(max - 6, max);
    //    max_int
    //     ------    (within)
    //      ++~^^^^
    try equal(Range.init(max - 5, max), Span.init(1, 4).toRange(max - 2, within4, .soft));
    try equal(Range.init(max - 5, max), Span.init(1, 4).toRange(max - 2, within4, .hard_flex));
}

pub const Range = struct {
    start: usize,
    end: usize,

    pub fn init(start: usize, end: usize) Range {
        return .{ .start = start, .end = end };
    }

    /// Returns the total range length.
    pub fn len(self: *const Range) usize {
        return self.end - self.start;
    }

    /// Returns `input[start..end]`.
    pub fn slice(self: *const Range, T: type, input: T) T {
        return input[self.start..self.end];
    }

    /// Returns `input[start..end]`, clamped to the bounds of `input`.
    pub fn sliceBounded(self: *const Range, T: type, input: T) T {
        return input[@min(self.start, input.len)..@min(self.end, input.len)];
    }

    pub fn extend(self: *Range, comptime side: Side, amt: usize) void {
        switch (side) {
            .left => self.start +|= amt,
            .right => self.end -|= amt,
        }
    }

    /// Projects `seg` range onto `within` range. The function also returns
    /// `Span` that represents the portion of `seg` that wasn't applied during
    /// projection.
    fn project(seg: Range, within: Range) struct { Range, Span } {
        if (seg.start < within.start) {
            if (seg.end <= within.start) return .{ // case [ ] ----
                Range.init(within.start, within.start),
                Span.init(seg.len(), 0),
            } else if (seg.end <= within.end) return .{ // case [ --]--
                Range.init(within.start, seg.end),
                Span.init(within.start - seg.start, 0),
            } else return .{ // case [ ---- ]
                Range.init(within.start, within.end),
                Span.init(within.start - seg.start, seg.end - within.end),
            };
        } else if (seg.start < within.end) {
            if (seg.end <= within.end) return .{ // case -[--]-
                Range.init(seg.start, seg.end),
                Span.init(0, 0),
            } else return .{ // case --[-- ]
                Range.init(seg.start, within.end),
                Span.init(0, seg.end - within.end),
            };
        } else return .{ // case ---- [ ]
            Range.init(within.end, within.end),
            Span.init(0, seg.len()),
        };
    }
};

test Range {
    const equal = std.testing.expectEqualDeep;
    //             0123456789
    //                ----
    //              ^^          (case 1)
    //              ^^^^        (case 5)
    //              ^^^^^^^^    (case 6)
    //                ^^^^      (case 3)
    //                  ^^^^    (case 4)
    //                    ^^    (case 2)

    // [project()]
    const within = Range.init(3, 7);
    try equal(.{ Range.init(3, 3), Span{ .left = 2, .right = 0 } }, Range.init(1, 3).project(within)); // case 1
    try equal(.{ Range.init(3, 5), Span{ .left = 2, .right = 0 } }, Range.init(1, 5).project(within)); // case 5
    try equal(.{ Range.init(3, 7), Span{ .left = 2, .right = 2 } }, Range.init(1, 9).project(within)); // case 6

    try equal(.{ Range.init(3, 7), Span{ .left = 0, .right = 0 } }, Range.init(3, 7).project(within)); // case 3
    try equal(.{ Range.init(5, 7), Span{ .left = 0, .right = 2 } }, Range.init(5, 9).project(within)); // case 4
    try equal(.{ Range.init(7, 7), Span{ .left = 0, .right = 2 } }, Range.init(7, 9).project(within)); // case 2
}
