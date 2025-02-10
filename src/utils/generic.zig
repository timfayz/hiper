// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

//! Public API:
//! - Error
//! - TruncMode
//! - DirTag
//! - DirVal
//! - DirPair
//! - AbsDir
//! - RelDir
//! - Range

const std = @import("std");
const num = @import("num.zig");
const meta = @import("meta.zig");

pub const Error = struct {
    pub const NoSpaceLeft = error{NoSpaceLeft};
    pub const OutOfBounds = error{OutOfBounds};
};

pub const TruncMode = enum { hard, hard_flex, soft };

pub const DirTag = enum {
    left,
    right,

    pub fn opposite(self: DirTag) DirTag {
        return if (self == .left) .right else .left;
    }
};

pub const DirVal = union(DirTag) {
    left: usize,
    right: usize,
};

pub const DirPair = struct {
    left: usize,
    right: usize,

    pub fn init(left: usize, right: usize) DirPair {
        return .{ .left = left, .right = right };
    }

    pub fn len(self: *const DirPair) usize {
        return self.left + self.right;
    }

    pub fn shift(self: *DirPair, comptime dir: DirTag, amt: usize) void {
        switch (dir) {
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

    pub fn extend(self: *DirPair, comptime dir: DirTag, amt: usize) void {
        switch (dir) {
            .left => self.left +|= amt,
            .right => self.right +|= amt,
        }
    }

    pub fn nonZeroDir(self: *const DirPair) ?DirTag {
        if (self.left != 0 and self.right == 0)
            return .left;
        if (self.left == 0 and self.right != 0)
            return .right;
        return null; // both 0 or 1+
    }

    pub fn toRange(
        self: *const DirPair,
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

test DirPair {
    const equal = std.testing.expectEqualDeep;

    // [nonZeroSide()]
    try equal(null, DirPair.init(5, 5).nonZeroDir());
    try equal(null, DirPair.init(0, 0).nonZeroDir());
    try equal(.right, DirPair.init(0, 5).nonZeroDir());
    try equal(.left, DirPair.init(5, 0).nonZeroDir());

    // [toRange()]
    const within = Range.init(5, 10); // Range is a half-open range [2, 7)

    // -*- [  ]

    // [.hard]
    //    0123456789abcdef
    //         -----      (within)
    try equal(Range.init(5, 5), DirPair.init(2, 2).toRange(3, within, .hard));
    //     ~~^^
    try equal(Range.init(5, 10), DirPair.init(2, 7).toRange(3, within, .hard));
    //     ~~^^^^^^^
    try equal(Range.init(5, 10), DirPair.init(2, 9).toRange(3, within, .hard));
    //     ~~^^^^^^^^^

    // [.hard_flex]
    //    0123456789abcdef
    //         -----      (within)
    try equal(Range.init(5, 7), DirPair.init(2, 2).toRange(3, within, .hard_flex));
    //     ~~^^++
    try equal(Range.init(5, 8), DirPair.init(2, 2).toRange(4, within, .hard_flex));
    //      ~~^^++
    try equal(Range.init(5, 6), DirPair.init(2, 2).toRange(2, within, .hard_flex));
    //    ~~^^ +
    try equal(Range.init(5, 10), DirPair.init(2, 7).toRange(3, within, .hard_flex));
    //     ~~^^^^^^^
    try equal(Range.init(5, 10), DirPair.init(2, 9).toRange(3, within, .hard_flex));
    //     ~~^^^^^^^^^

    // [.soft]
    //    0123456789abcdef
    //         -----      (within)
    try equal(Range.init(5, 9), DirPair.init(2, 2).toRange(3, within, .soft));
    //     ~~^^++++
    try equal(Range.init(5, 9), DirPair.init(2, 2).toRange(2, within, .soft));
    //    ~~^^ ++++
    try equal(Range.init(5, 9), DirPair.init(2, 2).toRange(4, within, .soft));
    //      ~~^^+++
    try equal(Range.init(5, 10), DirPair.init(2, 7).toRange(3, within, .soft));
    //     ~~^^^^^^^
    try equal(Range.init(5, 10), DirPair.init(2, 9).toRange(3, within, .soft));
    //     ~~^^^^^^^^^

    // [  ] -*-

    // [.hard]
    //    0123456789abcdef
    //         -----      (within)
    try equal(Range.init(10, 10), DirPair.init(2, 2).toRange(12, within, .hard));
    //              ~~^^
    try equal(Range.init(5, 10), DirPair.init(7, 2).toRange(12, within, .hard));
    //         ~~~~~~~^^
    try equal(Range.init(5, 10), DirPair.init(9, 2).toRange(12, within, .hard));
    //       ~~~~~~~~~^^

    // [.hard_flex]
    //    0123456789abcdef
    //         -----      (within)
    try equal(Range.init(8, 10), DirPair.init(2, 2).toRange(12, within, .hard_flex));
    //            ++~~^^
    try equal(Range.init(9, 10), DirPair.init(2, 2).toRange(13, within, .hard_flex));
    //             + ~~^^
    try equal(Range.init(7, 10), DirPair.init(2, 2).toRange(11, within, .hard_flex));
    //           ++~~^^
    try equal(Range.init(5, 10), DirPair.init(7, 2).toRange(12, within, .hard_flex));
    //         ~~~~~~~^^
    try equal(Range.init(5, 10), DirPair.init(9, 2).toRange(12, within, .hard_flex));
    //       ~~~~~~~~~^^

    // [.soft]
    //    0123456789abcdef
    //         -----      (within)
    try equal(Range.init(6, 10), DirPair.init(2, 2).toRange(12, within, .soft));
    //          ++++~~^^
    try equal(Range.init(6, 10), DirPair.init(2, 2).toRange(13, within, .soft));
    //          ++++ ~~^^
    try equal(Range.init(6, 10), DirPair.init(2, 2).toRange(11, within, .soft));
    //          +++~~^^
    try equal(Range.init(5, 10), DirPair.init(7, 2).toRange(12, within, .soft));
    //         ~~~~~~~^^
    try equal(Range.init(5, 10), DirPair.init(9, 2).toRange(12, within, .soft));
    //       ~~~~~~~~~^^

    // [-*-]
    const max = std.math.maxInt(usize);
    // [.hard]
    //    0123456789abcdef
    //         -----      (within)
    try equal(Range.init(5, 10), DirPair.init(2, 3).toRange(7, within, .hard));
    //         ~~^^^
    try equal(Range.init(7, 10), DirPair.init(2, 3).toRange(9, within, .hard));
    //           ~~^^^
    try equal(Range.init(5, 8), DirPair.init(2, 3).toRange(5, within, .hard));
    //       ~~^^^
    try equal(Range.init(5, 10), DirPair.init(max, max).toRange(7, within, .hard));
    //       ~~~~^^^^^

    // [.hard_flex]
    //    0123456789abcdef
    //         -----      (within)
    try equal(Range.init(5, 9), DirPair.init(2, 2).toRange(7, within, .hard_flex));
    //         ~~^^
    try equal(Range.init(6, 10), DirPair.init(2, 2).toRange(9, within, .hard_flex));
    //          +~~^^
    try equal(Range.init(6, 10), DirPair.init(2, 2).toRange(10, within, .hard_flex));
    //          ++~~^^
    try equal(Range.init(5, 9), DirPair.init(2, 2).toRange(5, within, .hard_flex));
    //       ~~^^++
    try equal(Range.init(5, 10), DirPair.init(max, max).toRange(7, within, .hard_flex));
    //       ~~~~^^^^^

    // [.soft]
    //    0123456789abcdef
    //         -----      (within)
    try equal(Range.init(5, 9), DirPair.init(2, 2).toRange(7, within, .soft));
    //         ~~^^
    try equal(Range.init(6, 10), DirPair.init(2, 2).toRange(9, within, .soft));
    //          +~~^^
    try equal(Range.init(6, 10), DirPair.init(2, 2).toRange(10, within, .soft));
    //          ++~~^^
    try equal(Range.init(5, 9), DirPair.init(2, 2).toRange(5, within, .soft));
    //       ~~^^++
    try equal(Range.init(5, 10), DirPair.init(max, max).toRange(7, within, .soft));
    //       ~~~~^^^^^

    // special case: span overflows type boundaries

    // [.hard_flex, .soft]
    const within1 = Range.init(1, 7);
    //    012345678
    //     ------     (within)
    //   ~~~^+++
    try equal(Range.init(1, 6), DirPair.init(3, 2).toRange(2, within1, .soft));
    try equal(Range.init(1, 6), DirPair.init(3, 2).toRange(2, within1, .hard_flex));

    const within2 = Range.init(0, 6);
    //    012345678
    //    ------     (within)
    // ~~~^^+++
    try equal(Range.init(0, 5), DirPair.init(3, 2).toRange(0, within2, .soft));
    try equal(Range.init(0, 5), DirPair.init(3, 2).toRange(0, within2, .hard_flex));

    const within3 = Range.init(max - 7, max - 1);
    //    max_int
    //    ------     (within)
    //     ++~^^^^
    try equal(Range.init(max - 6, max - 1), DirPair.init(1, 4).toRange(max - 2, within3, .soft));
    try equal(Range.init(max - 6, max - 1), DirPair.init(1, 4).toRange(max - 2, within3, .hard_flex));

    const within4 = Range.init(max - 6, max);
    //    max_int
    //     ------    (within)
    //      ++~^^^^
    try equal(Range.init(max - 5, max), DirPair.init(1, 4).toRange(max - 2, within4, .soft));
    try equal(Range.init(max - 5, max), DirPair.init(1, 4).toRange(max - 2, within4, .hard_flex));
}

pub const AbsDir = union(enum) {
    first: ?usize,
    last: ?usize,
    middle: ?usize,
    all: ?void,
    one: ?void,

    pub fn len(self: AbsDir) usize {
        return switch (self) {
            inline else => |amt| amt orelse std.math.maxInt(usize),
        };
    }
};

pub const RelDir = union(enum) {
    left: ?usize,
    right: ?usize,
    around: ?usize,
    custom: DirPair,

    pub const Options = struct {
        rshift_uneven: bool = true,
        extra_dir: DirTag = .right,
        fit_extra: bool = false,
        fit_pad: usize = 0,
        shift: ?DirVal = null,
    };

    fn toDirPair(
        self: RelDir,
        extra: usize,
        comptime opt: Options,
    ) if (opt.fit_extra) ?DirPair else DirPair {
        var pair: DirPair = .{ .left = 0, .right = 0 };
        switch (self) {
            .left => {
                if (opt.fit_extra and extra +| opt.fit_pad > self.len()) return null;
                pair.left = if (opt.fit_extra) self.len() - extra else self.len();
                pair.extend(opt.extra_dir, extra);
            },
            .right => {
                if (opt.fit_extra and extra +| opt.fit_pad > self.len()) return null;
                pair.right = if (opt.fit_extra) self.len() - extra else self.len();
                pair.extend(opt.extra_dir, extra);
            },
            .around => {
                if (opt.fit_extra and extra +| opt.fit_pad *| 2 > self.len()) return null;
                const avail_len = if (opt.fit_extra) self.len() - extra else self.len();
                pair = .{ .left = avail_len / 2, .right = avail_len / 2 };
                if (avail_len & 1 != 0) { // compensate lost item during odd division
                    if (opt.rshift_uneven) pair.right +|= 1 else pair.left +|= 1;
                }
                pair.extend(opt.extra_dir, extra);
            },
            .custom => |amt| {
                pair = .{ .left = amt.left, .right = amt.right };
                pair.extend(opt.extra_dir, extra);
            },
        }

        if (opt.shift) |shift| switch (shift) {
            .left => |amt| pair.shift(shift, amt),
            .right => |amt| pair.shift(shift, amt),
        };

        return pair;
    }

    fn toDirPairFit(self: RelDir, extra: usize, comptime opt: Options) ?DirPair {
        comptime var opt_ = opt;
        opt_.fit_extra = true;
        return self.toDirPair(extra, opt_);
    }

    pub fn len(self: RelDir) usize {
        return switch (self) {
            .custom => |amt| amt.left +| amt.right,
            inline else => |amt| amt orelse std.math.maxInt(usize),
        };
    }
};

test RelDir {
    const equal = std.testing.expectEqualDeep;
    const max = std.math.maxInt(usize);

    // [len()]
    try equal(max, (RelDir{ .left = null }).len());
    try equal(max, (RelDir{ .right = null }).len());
    try equal(max, (RelDir{ .around = null }).len());

    try equal(10, (RelDir{ .left = 10 }).len());
    try equal(10, (RelDir{ .right = 10 }).len());
    try equal(10, (RelDir{ .around = 10 }).len());
    try equal(10, (RelDir{ .custom = .{ .left = 4, .right = 6 } }).len());

    // [.fit_extra = false]

    // [.left mode]
    try equal(DirPair{ .left = 10, .right = 0 }, (RelDir{ .left = 10 }).toDirPair(0, .{}));
    try equal(DirPair{ .left = 10, .right = 4 }, (RelDir{ .left = 10 }).toDirPair(4, .{ .extra_dir = .right }));
    try equal(DirPair{ .left = 14, .right = 0 }, (RelDir{ .left = 10 }).toDirPair(4, .{ .extra_dir = .left }));
    // [.right mode]
    try equal(DirPair{ .left = 0, .right = 10 }, (RelDir{ .right = 10 }).toDirPair(0, .{}));
    try equal(DirPair{ .left = 0, .right = 14 }, (RelDir{ .right = 10 }).toDirPair(4, .{ .extra_dir = .right }));
    try equal(DirPair{ .left = 4, .right = 10 }, (RelDir{ .right = 10 }).toDirPair(4, .{ .extra_dir = .left }));
    // [.around mode]
    try equal(DirPair{ .left = 4, .right = 5 }, (RelDir{ .around = 9 }).toDirPair(0, .{}));
    try equal(DirPair{ .left = 5, .right = 4 }, (RelDir{ .around = 9 }).toDirPair(0, .{ .rshift_uneven = false }));
    try equal(DirPair{ .left = 9, .right = 5 }, (RelDir{ .around = 9 }).toDirPair(5, .{ .extra_dir = .left }));
    try equal(DirPair{ .left = 4, .right = 10 }, (RelDir{ .around = 9 }).toDirPair(5, .{ .extra_dir = .right }));

    // [.fit_extra = true]

    // [.left mode]
    try equal(null, (RelDir{ .left = 10 }).toDirPairFit(11, .{}));
    try equal(DirPair{ .left = 0, .right = 10 }, (RelDir{ .left = 10 }).toDirPairFit(10, .{ .extra_dir = .right }));
    try equal(DirPair{ .left = 6, .right = 4 }, (RelDir{ .left = 10 }).toDirPairFit(4, .{ .extra_dir = .right }));
    try equal(DirPair{ .left = 10, .right = 0 }, (RelDir{ .left = 10 }).toDirPairFit(4, .{ .extra_dir = .left, .fit_pad = 6 }));
    try equal(null, (RelDir{ .left = 10 }).toDirPairFit(4, .{ .extra_dir = .left, .fit_pad = 7 }));
    // [.right mode]
    try equal(null, (RelDir{ .right = 10 }).toDirPairFit(11, .{}));
    try equal(DirPair{ .left = 0, .right = 10 }, (RelDir{ .right = 10 }).toDirPairFit(10, .{ .extra_dir = .right }));
    try equal(DirPair{ .left = 4, .right = 6 }, (RelDir{ .right = 10 }).toDirPairFit(4, .{ .extra_dir = .left }));
    try equal(DirPair{ .left = 0, .right = 10 }, (RelDir{ .right = 10 }).toDirPairFit(4, .{ .extra_dir = .right, .fit_pad = 6 }));
    try equal(null, (RelDir{ .right = 10 }).toDirPairFit(4, .{ .extra_dir = .right, .fit_pad = 7 }));
    // [.around mode]
    try equal(null, (RelDir{ .around = 10 }).toDirPairFit(11, .{}));
    try equal(DirPair{ .left = 0, .right = 10 }, (RelDir{ .around = 10 }).toDirPairFit(10, .{ .extra_dir = .right }));
    try equal(DirPair{ .left = 2, .right = 8 }, (RelDir{ .around = 10 }).toDirPairFit(5, .{ .extra_dir = .right }));
    try equal(DirPair{ .left = 8, .right = 2 }, (RelDir{ .around = 10 }).toDirPairFit(5, .{ .rshift_uneven = false, .extra_dir = .left }));
    try equal(DirPair{ .left = 7, .right = 3 }, (RelDir{ .around = 10 }).toDirPairFit(5, .{ .extra_dir = .left }));
    try equal(DirPair{ .left = 7, .right = 3 }, (RelDir{ .around = 10 }).toDirPairFit(5, .{ .extra_dir = .left, .fit_pad = 2 }));
    try equal(null, (RelDir{ .around = 10 }).toDirPairFit(5, .{ .extra_dir = .left, .fit_pad = 3 }));
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

    pub fn extendDir(self: *Range, comptime side: DirTag, amt: usize) void {
        switch (side) {
            .left => self.start +|= amt,
            .right => self.end -|= amt,
        }
    }

    /// Projects the given range onto `within` range, returning portions that fall outside.
    fn truncate(self: Range, within: Range) struct { Range, DirPair } {
        if (self.start < within.start) {
            if (self.end <= within.start) return .{ // case [ ] ----
                Range.init(within.start, within.start),
                DirPair.init(self.len(), 0),
            } else if (self.end <= within.end) return .{ // case [ --]--
                Range.init(within.start, self.end),
                DirPair.init(within.start - self.start, 0),
            } else return .{ // case [ ---- ]
                Range.init(within.start, within.end),
                DirPair.init(within.start - self.start, self.end - within.end),
            };
        } else if (self.start < within.end) {
            if (self.end <= within.end) return .{ // case -[--]-
                Range.init(self.start, self.end),
                DirPair.init(0, 0),
            } else return .{ // case --[-- ]
                Range.init(self.start, within.end),
                DirPair.init(0, self.end - within.end),
            };
        } else return .{ // case ---- [ ]
            Range.init(within.end, within.end),
            DirPair.init(0, self.len()),
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
    try equal(.{ Range.init(3, 3), DirPair{ .left = 2, .right = 0 } }, Range.init(1, 3).truncate(within)); // case 1
    try equal(.{ Range.init(3, 5), DirPair{ .left = 2, .right = 0 } }, Range.init(1, 5).truncate(within)); // case 5
    try equal(.{ Range.init(3, 7), DirPair{ .left = 2, .right = 2 } }, Range.init(1, 9).truncate(within)); // case 6

    try equal(.{ Range.init(3, 7), DirPair{ .left = 0, .right = 0 } }, Range.init(3, 7).truncate(within)); // case 3
    try equal(.{ Range.init(5, 7), DirPair{ .left = 0, .right = 2 } }, Range.init(5, 9).truncate(within)); // case 4
    try equal(.{ Range.init(7, 7), DirPair{ .left = 0, .right = 2 } }, Range.init(7, 9).truncate(within)); // case 2
}
