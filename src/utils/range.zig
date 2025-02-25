// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

//! Public API:
//! - Side
//! - Dir
//! - DirVal
//! - DirPair
//! - TruncMode
//! - Range
//! - init
//! - initFromSlice
//! - View

const std = @import("std");
const num = @import("num.zig");
const meta = @import("meta.zig");

pub const Side = enum {
    left,
    right,
    both,
    none,
};

pub const Dir = enum {
    left,
    right,

    pub fn opposite(self: Dir) Dir {
        return if (self == .left) .right else .left;
    }
};

pub const DirVal = union(Dir) {
    left: usize,
    right: usize,

    pub fn val(self: DirVal) usize {
        return switch (self) {
            inline else => |v| v,
        };
    }
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

    pub fn shift(self: *DirPair, comptime dir: Dir, amt: usize) void {
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

    pub fn extend(self: *DirPair, comptime dir: Dir, amt: usize) void {
        switch (dir) {
            .left => self.left +|= amt,
            .right => self.right +|= amt,
        }
    }

    pub fn distribute(self: *DirPair, amt: usize, comptime around_rshift_odd: bool) void {
        self.left = amt / 2;
        self.right = amt / 2;
        if (amt & 1 != 0) { // compensate lost item during odd division
            if (around_rshift_odd) self.right +|= 1 else self.left +|= 1;
        }
    }

    pub fn uniqueNonZeroDir(self: *const DirPair) ?Dir {
        if (self.left != 0 and self.right == 0)
            return .left;
        if (self.left == 0 and self.right != 0)
            return .right;
        return null; // both 0 or >0
    }

    pub fn toRange(self: *const DirPair, pos: usize, comptime compensate: bool) Range {
        var range = Range.init(pos -| self.left, pos +| self.right);
        if (compensate) {
            // compensate potential overflow/underflow {
            var unused = DirPair.init(
                self.left - (pos - range.start),
                self.right - (range.end - pos),
            );
            if (unused.uniqueNonZeroDir()) |dir| switch (dir) {
                .left => range.end +|= unused.left,
                .right => range.start -|= unused.right,
            };
        }
        return range;
    }

    pub fn toRangeWithin(self: *const DirPair, pos: usize, within: Range, comptime trunc_mode: TruncMode) Range {
        var clamped = Range.init(pos -| self.left, pos +| self.right).clamp(within);
        switch (trunc_mode) {
            .hard => return clamped,
            .hard_flex, .soft => |mode| {
                if (pos < within.start) {
                    const end = (if (mode == .hard_flex) pos else within.start) +| self.len();
                    return Range.init(within.start, end).clampEnd(within);
                } else if (pos < within.end) {
                    var reminder = clamped.clampReminder(within);
                    // compensate potential overflow/underflow {
                    reminder.left +|= self.left - (pos - clamped.start);
                    reminder.right +|= self.right - (clamped.end - pos);
                    // }
                    if (reminder.uniqueNonZeroDir()) |dir| switch (dir) {
                        .left => {
                            clamped.end +|= reminder.left;
                            return clamped.clampEnd(within);
                        },
                        .right => {
                            clamped.start -|= reminder.right;
                            return clamped.clampStart(within);
                        },
                    };
                    return clamped;
                } else { // pos >= within.end
                    const start = (if (mode == .hard_flex) pos else within.end) -| self.len();
                    return Range.init(start, within.end).clampStart(within);
                }
            },
        }
    }
};

test DirPair {
    const equal = std.testing.expectEqualDeep;
    const max = std.math.maxInt(usize);

    // [nonZeroDir()]

    try equal(null, DirPair.init(5, 5).uniqueNonZeroDir());
    try equal(null, DirPair.init(0, 0).uniqueNonZeroDir());
    try equal(.right, DirPair.init(0, 5).uniqueNonZeroDir());
    try equal(.left, DirPair.init(5, 0).uniqueNonZeroDir());

    // [toRange()]

    //    012345678
    //  <<<^>++
    try equal(Range.init(0, 3), DirPair.init(3, 2).toRange(1, false));
    try equal(Range.init(0, 5), DirPair.init(3, 2).toRange(1, true));

    //    012345678
    //     <<<^>
    try equal(Range.init(1, 6), DirPair.init(3, 2).toRange(4, false));
    try equal(Range.init(1, 6), DirPair.init(3, 2).toRange(4, true));

    //    ..max_int
    //       +++<<^>>
    try equal(Range.init(max - 2, max), DirPair.init(2, 3).toRange(max, false));
    try equal(Range.init(max - 5, max), DirPair.init(2, 3).toRange(max, true));

    // [toRangeWithin()]

    const within = Range.init(5, 10); // Range is a half-open range [2, 7)

    // [.hard mode]
    //    0123456789ABCDEF
    //         -----        (within)
    //     ~~^              (case 1)
    //     ~~^^^^^^^        (case 2)
    //     ~~^^^^^^^^^      (case 3)
    try equal(Range.init(5, 5), DirPair.init(2, 1).toRangeWithin(3, within, .hard)); // 1
    try equal(Range.init(5, 10), DirPair.init(2, 7).toRangeWithin(3, within, .hard)); // 2
    try equal(Range.init(5, 10), DirPair.init(2, 9).toRangeWithin(3, within, .hard)); // 3

    // -*- [  ]

    // [.hard_flex mode]
    //    0123456789ABCDEF
    //         -----        (within)
    //     ~~^^++           (case 1)
    //    ~~^^ +            (case 2)
    //     ~~^^^^^^^        (case 3)
    //     ~~^^^^^^^^^      (case 4)
    try equal(Range.init(5, 7), DirPair.init(2, 2).toRangeWithin(3, within, .hard_flex)); // 1
    try equal(Range.init(5, 6), DirPair.init(2, 2).toRangeWithin(2, within, .hard_flex)); // 2
    try equal(Range.init(5, 10), DirPair.init(2, 7).toRangeWithin(3, within, .hard_flex)); // 3
    try equal(Range.init(5, 10), DirPair.init(2, 9).toRangeWithin(3, within, .hard_flex)); // 4

    // [.soft mode]
    //    0123456789ABCDEF
    //         -----        (within)
    //     ~~^^++++         (case 1)
    //    ~~^^ ++++         (case 2)
    //     ~~^^^^^^^        (case 3)
    //     ~~^^^^^^^^^      (case 4)
    try equal(Range.init(5, 9), DirPair.init(2, 2).toRangeWithin(3, within, .soft)); // 1
    try equal(Range.init(5, 9), DirPair.init(2, 2).toRangeWithin(2, within, .soft)); // 2
    try equal(Range.init(5, 10), DirPair.init(2, 7).toRangeWithin(3, within, .soft)); // 3
    try equal(Range.init(5, 10), DirPair.init(2, 9).toRangeWithin(3, within, .soft)); // 4

    // [  ] -*-

    // [.hard mode]
    //    0123456789ABCDEF
    //         -----        (within)
    //               ~^^    (case 1)
    //         ~~~~~~~^^    (case 2)
    //       ~~~~~~~~~^^    (case 3)
    try equal(Range.init(10, 10), DirPair.init(1, 2).toRangeWithin(12, within, .hard)); // 1
    try equal(Range.init(5, 10), DirPair.init(7, 2).toRangeWithin(12, within, .hard)); // 2
    try equal(Range.init(5, 10), DirPair.init(9, 2).toRangeWithin(12, within, .hard)); // 3

    // [.hard_flex mode]
    //    0123456789ABCDEF
    //         -----        (within)
    //            ++~~^^    (case 1)
    //             + ~~^^   (case 2)
    //         ~~~~~~~^^    (case 3)
    //       ~~~~~~~~~^^    (case 4)
    try equal(Range.init(8, 10), DirPair.init(2, 2).toRangeWithin(12, within, .hard_flex)); // 1
    try equal(Range.init(9, 10), DirPair.init(2, 2).toRangeWithin(13, within, .hard_flex)); // 2
    try equal(Range.init(5, 10), DirPair.init(7, 2).toRangeWithin(12, within, .hard_flex)); // 3
    try equal(Range.init(5, 10), DirPair.init(9, 2).toRangeWithin(12, within, .hard_flex)); // 4

    // [.soft mode]
    //    0123456789ABCDEF
    //         -----        (within)
    //          ++++~~^^    (case 1)
    //          ++++ ~~^^   (case 2)
    //         ~~~~~~~^^    (case 3)
    //       ~~~~~~~~~^^    (case 4)
    try equal(Range.init(6, 10), DirPair.init(2, 2).toRangeWithin(12, within, .soft)); // 1
    try equal(Range.init(6, 10), DirPair.init(2, 2).toRangeWithin(13, within, .soft)); // 2
    try equal(Range.init(5, 10), DirPair.init(7, 2).toRangeWithin(12, within, .soft)); // 3
    try equal(Range.init(5, 10), DirPair.init(9, 2).toRangeWithin(12, within, .soft)); // 4

    // [-*-]

    // [.hard mode]
    //    0123456789ABCDEF
    //         -----        (within)
    //         ~~^^^        (case 1)
    //           ~~^^^      (case 2)
    //       ~~^^^          (case 3)
    //       ~~~~^^^^^      (case 4)
    try equal(Range.init(5, 10), DirPair.init(2, 3).toRangeWithin(7, within, .hard)); // 1
    try equal(Range.init(7, 10), DirPair.init(2, 3).toRangeWithin(9, within, .hard)); // 2
    try equal(Range.init(5, 8), DirPair.init(2, 3).toRangeWithin(5, within, .hard)); // 3
    try equal(Range.init(5, 10), DirPair.init(max, max).toRangeWithin(7, within, .hard)); // 4

    // [.hard_flex mode]
    //    0123456789ABCDEF
    //         -----        (within)
    //         ~~^^         (case 1)
    //          +~~^^       (case 2)
    //       ~~^^++         (case 3)
    //       ~~~~^^^^^      (case 4)
    try equal(Range.init(5, 9), DirPair.init(2, 2).toRangeWithin(7, within, .hard_flex)); // 1
    try equal(Range.init(6, 10), DirPair.init(2, 2).toRangeWithin(9, within, .hard_flex)); // 2
    try equal(Range.init(5, 9), DirPair.init(2, 2).toRangeWithin(5, within, .hard_flex)); // 3
    try equal(Range.init(5, 10), DirPair.init(max, max).toRangeWithin(7, within, .hard_flex)); // 4

    // [.soft mode]
    //    0123456789ABCDEF
    //         -----        (within)
    //         ~~^^         (case 1)
    //          +~~^^       (case 2)
    //       ~~^^++         (case 3)
    //       ~~~~^^^^^      (case 4)
    try equal(Range.init(5, 9), DirPair.init(2, 2).toRangeWithin(7, within, .soft)); // 1
    try equal(Range.init(6, 10), DirPair.init(2, 2).toRangeWithin(9, within, .soft)); // 2
    try equal(Range.init(5, 9), DirPair.init(2, 2).toRangeWithin(5, within, .soft)); // 3
    try equal(Range.init(5, 10), DirPair.init(max, max).toRangeWithin(7, within, .soft)); // 4

    // [.hard_flex, .soft mode]
    // special case: range overflows/underflow

    //    012345678
    //     ------     (within)
    //   ~~~^+++
    try equal(Range.init(1, 6), DirPair.init(3, 2).toRangeWithin(2, Range.init(1, 7), .soft));
    try equal(Range.init(1, 6), DirPair.init(3, 2).toRangeWithin(2, Range.init(1, 7), .hard_flex));

    //    ..max_int
    //      ------     (within)
    //       +++~^^^^
    try equal(Range.init(max - 6, max - 1), DirPair.init(1, 4).toRangeWithin(max - 2, Range.init(max - 7, max - 1), .soft));
    try equal(Range.init(max - 6, max - 1), DirPair.init(1, 4).toRangeWithin(max - 2, Range.init(max - 7, max - 1), .hard_flex));
}

pub const TruncMode = enum {
    hard,
    hard_flex,
    soft,
};

pub const Range = struct {
    start: usize,
    end: usize,

    pub fn init(start: usize, end: usize) Range {
        return .{ .start = start, .end = end };
    }

    pub fn initFromSlice(sl: anytype) Range {
        return .{ .start = 0, .end = sl.len };
    }

    pub fn len(self: *const Range) usize {
        return self.end - self.start;
    }

    pub fn slice(self: *const Range, T: type, input: T) T {
        return input[self.start..self.end];
    }

    pub fn sliceBounded(self: *const Range, T: type, input: T) T {
        return input[@min(self.start, input.len)..@min(self.end, input.len)];
    }

    pub fn extendDir(self: *Range, comptime side: Dir, amt: usize) void {
        switch (side) {
            .left => self.start +|= amt,
            .right => self.end -|= amt,
        }
    }

    fn clamp(self: Range, within: Range) Range {
        return .{
            .start = std.math.clamp(self.start, within.start, within.end),
            .end = std.math.clamp(self.end, within.start, within.end),
        };
    }

    fn clampStart(self: Range, within: Range) Range {
        return .{
            .start = std.math.clamp(self.start, within.start, within.end),
            .end = self.end,
        };
    }

    fn clampEnd(self: Range, within: Range) Range {
        return .{
            .start = self.start,
            .end = std.math.clamp(self.end, within.start, within.end),
        };
    }

    fn leftComplement(self: Range) Range {
        return .{ .start = 0, .end = self.start };
    }

    fn rightComplement(self: Range) Range {
        return .{ .start = self.end, .end = std.math.maxInt(usize) };
    }

    fn clampReminder(self: Range, within: Range) DirPair {
        return .{
            .left = self.clamp(within.leftComplement()).len(),
            .right = self.clamp(within.rightComplement()).len(),
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

    const within = Range.init(3, 7);
    try equal(Range.init(3, 3), Range.init(1, 3).clamp(within)); // case 1
    try equal(Range.init(3, 5), Range.init(1, 5).clamp(within)); // case 5
    try equal(Range.init(3, 7), Range.init(1, 9).clamp(within)); // case 6
    try equal(Range.init(3, 7), Range.init(3, 7).clamp(within)); // case 3
    try equal(Range.init(5, 7), Range.init(5, 9).clamp(within)); // case 4
    try equal(Range.init(7, 7), Range.init(7, 9).clamp(within)); // case 2

    try equal(DirPair{ .left = 2, .right = 0 }, Range.init(1, 3).clampReminder(within)); // case 1
    try equal(DirPair{ .left = 2, .right = 0 }, Range.init(1, 5).clampReminder(within)); // case 5
    try equal(DirPair{ .left = 2, .right = 2 }, Range.init(1, 9).clampReminder(within)); // case 6
    try equal(DirPair{ .left = 0, .right = 0 }, Range.init(3, 7).clampReminder(within)); // case 3
    try equal(DirPair{ .left = 0, .right = 2 }, Range.init(5, 9).clampReminder(within)); // case 4
    try equal(DirPair{ .left = 0, .right = 2 }, Range.init(7, 9).clampReminder(within)); // case 2
}

pub fn init(start: usize, end: usize) Range {
    return Range.init(start, end);
}

pub fn initFromSlice(slc: anytype) Range {
    return Range.initFromSlice(slc);
}

pub const View = union(enum) {
    left: ?usize,
    right: ?usize,
    around: ?usize,
    custom: DirPair,

    pub const Options = struct {
        around_rshift_odd: bool = true,
        shift: ?DirVal = null,
    };

    pub fn len(self: View) usize {
        return switch (self) {
            .custom => |amt| amt.left +| amt.right,
            inline else => |amt| amt orelse std.math.maxInt(usize),
        };
    }

    pub fn fits(self: View, range: usize) bool {
        return self.len() >= range;
    }

    pub fn toPair(self: View, comptime opt: Options) DirPair {
        return self.toPairAddExtra(0, .right, opt);
    }

    pub fn toPairAddExtra(self: View, extra: usize, comptime extra_dir: Dir, comptime opt: Options) DirPair {
        var pair: DirPair = .{ .left = 0, .right = 0 };
        switch (self) {
            .left => pair.left = self.len(),
            .right => pair.right = self.len(),
            .around => pair.distribute(self.len(), opt.around_rshift_odd),
            .custom => |amt| pair = .{ .left = amt.left, .right = amt.right },
        }
        pair.extend(extra_dir, extra);
        if (opt.shift) |shift| pair.shift(shift, shift.val());
        return pair;
    }

    pub fn toPairFitExtra(
        self: View,
        extra: usize,
        comptime extra_dir: Dir,
        comptime fit_pad: ?DirVal,
        comptime opt: Options,
    ) DirPair {
        var pair: DirPair = .{ .left = 0, .right = 0 };
        const view_len = self.len();
        const extra_fitted = @min(view_len, extra);
        switch (self) {
            .left => pair.left = self.len() - extra_fitted,
            .right => pair.right = self.len() - extra_fitted,
            .around => pair.distribute(self.len() - extra_fitted, opt.around_rshift_odd),
            .custom => |amt| pair = .{ .left = amt.left, .right = amt.right },
        }
        pair.extend(extra_dir, extra_fitted);
        if (fit_pad) |pad| switch (pad) {
            .left => |fit_val| {
                if (pair.left < fit_val) pair.shift(.left, @min(view_len, fit_val) - pair.left);
            },
            .right => |fit_val| {
                if (pair.right < fit_val) pair.shift(.right, @min(view_len, fit_val) - pair.right);
            },
        };
        if (opt.shift) |shift| pair.shift(shift, shift.val());
        return pair;
    }
};

test View {
    const equal = std.testing.expectEqualDeep;
    const max = std.math.maxInt(usize);

    // [len()]

    try equal(max, (View{ .left = null }).len());
    try equal(max, (View{ .right = null }).len());
    try equal(max, (View{ .around = null }).len());
    try equal(10, (View{ .left = 10 }).len());
    try equal(10, (View{ .right = 10 }).len());
    try equal(10, (View{ .around = 10 }).len());
    try equal(10, (View{ .custom = .{ .left = 4, .right = 6 } }).len());

    // [fits()]

    try equal(true, (View{ .around = 10 }).fits(10));
    try equal(false, (View{ .around = 10 }).fits(11));

    // [toPair()]

    try equal(DirPair{ .left = 2, .right = 3 }, (View{ .around = 5 }).toPair(.{}));
    // [.shift]
    try equal(DirPair{ .left = 1, .right = 4 }, (View{ .around = 5 }).toPair(.{ .shift = .{ .right = 1 } }));
    // [.around_rshift_odd]
    try equal(DirPair{ .left = 3, .right = 2 }, (View{ .around = 5 }).toPair(.{ .around_rshift_odd = false }));

    // [toPairAddExtra()]

    // [.left mode]
    try equal(DirPair{ .left = 10, .right = 0 }, (View{ .left = 10 }).toPairAddExtra(0, .right, .{}));
    try equal(DirPair{ .left = 10, .right = 4 }, (View{ .left = 10 }).toPairAddExtra(4, .right, .{}));
    try equal(DirPair{ .left = 14, .right = 0 }, (View{ .left = 10 }).toPairAddExtra(4, .left, .{}));
    // [.right mode]
    try equal(DirPair{ .left = 0, .right = 10 }, (View{ .right = 10 }).toPairAddExtra(0, .right, .{}));
    try equal(DirPair{ .left = 0, .right = 14 }, (View{ .right = 10 }).toPairAddExtra(4, .right, .{}));
    try equal(DirPair{ .left = 4, .right = 10 }, (View{ .right = 10 }).toPairAddExtra(4, .left, .{}));
    // [.around mode]
    try equal(DirPair{ .left = 5, .right = 5 }, (View{ .around = 10 }).toPairAddExtra(0, .right, .{}));
    try equal(DirPair{ .left = 10, .right = 5 }, (View{ .around = 10 }).toPairAddExtra(5, .left, .{}));
    try equal(DirPair{ .left = 5, .right = 10 }, (View{ .around = 10 }).toPairAddExtra(5, .right, .{}));

    // [toPairFitExtra()]

    try equal(DirPair{ .left = 2, .right = 8 }, (View{ .around = 10 }).toPairFitExtra(5, .right, null, .{}));
    try equal(DirPair{ .left = 5, .right = 5 }, (View{ .around = 10 }).toPairFitExtra(5, .right, .{ .left = 5 }, .{}));
    // excessive fitting pad
    try equal(DirPair{ .left = 10, .right = 0 }, (View{ .around = 10 }).toPairFitExtra(5, .right, .{ .left = 11 }, .{}));
    try equal(DirPair{ .left = 0, .right = 10 }, (View{ .around = 10 }).toPairFitExtra(5, .right, .{ .right = 11 }, .{}));
    // excessive extra
    try equal(DirPair{ .left = 0, .right = 10 }, (View{ .around = 10 }).toPairFitExtra(15, .right, null, .{}));
    try equal(DirPair{ .left = 10, .right = 0 }, (View{ .around = 10 }).toPairFitExtra(15, .left, null, .{}));
}
