// MIT License (c) Timur Fayzrakhmanov.
// tim.fayzrakhmanov@gmail.com (github.com/timfayz)

//! Common set of errors used across functions.

pub const Generic = struct {
    pub const NoSpaceLeft = error{NoSpaceLeft};
    pub const OutOfBounds = error{OutOfBounds};
};
