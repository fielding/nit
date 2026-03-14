const std = @import("std");

// Default ANSI colors (respects terminal theme)
const defaults = struct {
    const reset = "\x1b[0m";
    const bold = "\x1b[1m";
    const dim = "\x1b[2m";
    const red = "\x1b[31m";
    const green = "\x1b[32m";
    const yellow = "\x1b[33m";
    const cyan = "\x1b[36m";
    const bright_red = "\x1b[91m";
    const bright_green = "\x1b[92m";
    const bright_yellow = "\x1b[93m";
};

// Color slots - populated from defaults, overridden by NIT_COLORS env var.
// Format: NIT_COLORS="add=32:del=31:hunk=36:staged=32:unstaged=31"
// Values are ANSI SGR parameters (e.g., "32" for green, "38;2;255;0;0" for true-color red).
pub var add: []const u8 = defaults.bright_green;
pub var del: []const u8 = defaults.bright_red;
pub var hunk: []const u8 = defaults.cyan;
pub var context: []const u8 = defaults.dim;
pub var staged: []const u8 = defaults.green;
pub var staged_label: []const u8 = defaults.bright_green;
pub var unstaged: []const u8 = defaults.red;
pub var unstaged_label: []const u8 = defaults.bright_red;
pub var hash: []const u8 = defaults.yellow;
pub var date: []const u8 = defaults.dim;

// These are always fixed
pub const reset = defaults.reset;
pub const bold = defaults.bold;
pub const dim = defaults.dim;

// Scratch buffers for building "\x1b[" ++ value ++ "m" strings
var bufs: [10][32]u8 = undefined;
var buf_idx: usize = 0;

fn makeEscape(sgr: []const u8) []const u8 {
    if (buf_idx >= bufs.len) return defaults.reset;
    var buf = &bufs[buf_idx];
    buf_idx += 1;

    const prefix = "\x1b[";
    const suffix = "m";
    const total = prefix.len + sgr.len + suffix.len;
    if (total > buf.len) return defaults.reset;

    @memcpy(buf[0..prefix.len], prefix);
    @memcpy(buf[prefix.len .. prefix.len + sgr.len], sgr);
    @memcpy(buf[prefix.len + sgr.len .. total], suffix);
    return buf[0..total];
}

pub fn init() void {
    const env = std.posix.getenv("NIT_COLORS") orelse return;

    // Parse "key=value:key=value:..."
    var iter = std.mem.splitScalar(u8, env, ':');
    while (iter.next()) |pair| {
        const eq = std.mem.indexOfScalar(u8, pair, '=') orelse continue;
        const key = pair[0..eq];
        const val = pair[eq + 1 ..];
        if (val.len == 0) continue;

        const esc = makeEscape(val);
        if (std.mem.eql(u8, key, "add")) {
            add = esc;
        } else if (std.mem.eql(u8, key, "del")) {
            del = esc;
        } else if (std.mem.eql(u8, key, "hunk")) {
            hunk = esc;
        } else if (std.mem.eql(u8, key, "context")) {
            context = esc;
        } else if (std.mem.eql(u8, key, "staged")) {
            staged = esc;
            staged_label = esc;
        } else if (std.mem.eql(u8, key, "unstaged")) {
            unstaged = esc;
            unstaged_label = esc;
        } else if (std.mem.eql(u8, key, "hash")) {
            hash = esc;
        } else if (std.mem.eql(u8, key, "date")) {
            date = esc;
        }
    }
}

pub fn isTty() bool {
    return std.posix.isatty(std.fs.File.stdout().handle);
}
