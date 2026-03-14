const std = @import("std");

pub const reset = "\x1b[0m";
pub const bold = "\x1b[1m";
pub const dim = "\x1b[2m";

// Standard ANSI
pub const green = "\x1b[32m";
pub const yellow = "\x1b[33m";
pub const cyan = "\x1b[36m";
pub const bright_red = "\x1b[91m";
pub const bright_green = "\x1b[92m";
pub const bright_yellow = "\x1b[93m";

// Human++ palette (true-color)
pub const hpp_pink = "\x1b[38;2;231;52;156m"; // base08 #e7349c
pub const hpp_amber = "\x1b[38;2;242;166;51m"; // base0A #f2a633
pub const hpp_cyan = "\x1b[38;2;26;208;214m"; // base0C #1ad0d6
pub const hpp_green = "\x1b[38;2;4;179;114m"; // base0B #04b372
pub const hpp_lime = "\x1b[38;2;187;255;0m"; // base0F #bbff00
pub const hpp_quiet_green = "\x1b[38;2;97;177;134m"; // base13 #61b186
pub const hpp_quiet_red = "\x1b[38;2;200;81;143m"; // base10 #c8518f
pub const hpp_fg_dim = "\x1b[38;2;130;128;121m"; // base04 #828079

pub fn isTty() bool {
    return std.posix.isatty(std.fs.File.stdout().handle);
}
