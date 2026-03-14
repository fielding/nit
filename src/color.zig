const std = @import("std");

const Writer = std.Io.Writer;

// ANSI escape sequences
pub const reset = "\x1b[0m";
pub const bold = "\x1b[1m";
pub const dim = "\x1b[2m";

pub const red = "\x1b[31m";
pub const green = "\x1b[32m";
pub const yellow = "\x1b[33m";
pub const blue = "\x1b[34m";
pub const magenta = "\x1b[35m";
pub const cyan = "\x1b[36m";
pub const white = "\x1b[37m";

pub const bright_red = "\x1b[91m";
pub const bright_green = "\x1b[92m";
pub const bright_yellow = "\x1b[93m";

pub const bg_red = "\x1b[41m";
pub const bg_green = "\x1b[42m";

/// Check if stdout is a TTY (colors should only be used for interactive output)
pub fn isTty() bool {
    const handle = std.fs.File.stdout().handle;
    return std.posix.isatty(handle);
}
