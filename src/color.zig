const std = @import("std");

pub const reset = "\x1b[0m";
pub const bold = "\x1b[1m";
pub const dim = "\x1b[2m";

pub const red = "\x1b[31m";
pub const green = "\x1b[32m";
pub const yellow = "\x1b[33m";
pub const cyan = "\x1b[36m";

pub const bright_red = "\x1b[91m";
pub const bright_green = "\x1b[92m";
pub const bright_yellow = "\x1b[93m";

pub fn isTty() bool {
    return std.posix.isatty(std.fs.File.stdout().handle);
}
