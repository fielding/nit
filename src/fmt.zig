/// Shared formatting helpers for diff output (used by diff.zig and show.zig).
const std = @import("std");
const git = @import("git.zig");
const c = git.c;
const color = @import("color.zig");

const Writer = std.Io.Writer;

// --- Compact diff callback ---

pub const CompactCtx = struct {
    writer: *Writer,
};

pub fn compactCallback(
    delta: [*c]const c.git_diff_delta,
    _: [*c]const c.git_diff_hunk,
    line: [*c]const c.git_diff_line,
    payload: ?*anyopaque,
) callconv(.c) c_int {
    const ctx: *CompactCtx = @ptrCast(@alignCast(payload));
    const content = line.*.content;
    const len = line.*.content_len;
    if (len == 0 or content == null) return 0;
    const slice = content[0..len];
    const w = ctx.writer;

    switch (line.*.origin) {
        '+', '-', ' ' => {
            w.writeByte(@intCast(line.*.origin)) catch return -1;
            w.writeAll(slice) catch return -1;
        },
        'H' => {
            if (std.mem.indexOf(u8, slice, " @@")) |pos| {
                w.writeAll(slice[0 .. pos + 3]) catch return -1;
                w.writeByte('\n') catch return -1;
            } else {
                w.writeAll(slice) catch return -1;
            }
        },
        'F' => {
            if (delta != null) {
                const path = delta.*.new_file.path;
                if (path != null and slice.len >= 4 and std.mem.eql(u8, slice[0..4], "diff")) {
                    w.writeAll("--- ") catch return -1;
                    w.writeAll(std.mem.span(path)) catch return -1;
                    w.writeByte('\n') catch return -1;
                }
            }
        },
        else => {},
    }
    return 0;
}

// --- Human diff callback ---

pub const HumanCtx = struct {
    writer: *Writer,
    use_color: bool,
    current_file: ?[*:0]const u8,
};

pub fn humanCallback(
    delta: [*c]const c.git_diff_delta,
    _: [*c]const c.git_diff_hunk,
    line: [*c]const c.git_diff_line,
    payload: ?*anyopaque,
) callconv(.c) c_int {
    const ctx: *HumanCtx = @ptrCast(@alignCast(payload));
    const content = line.*.content;
    const len = line.*.content_len;
    if (len == 0 or content == null) return 0;
    const slice = content[0..len];
    const w = ctx.writer;

    switch (line.*.origin) {
        'F' => {
            if (delta != null) {
                const path = delta.*.new_file.path;
                if (path != null and slice.len >= 4 and std.mem.eql(u8, slice[0..4], "diff")) {
                    const new_path = std.mem.span(path);
                    const cur = if (ctx.current_file) |cf| std.mem.span(cf) else "";
                    if (!std.mem.eql(u8, cur, new_path)) {
                        if (ctx.current_file != null) w.writeByte('\n') catch return -1;
                        ctx.current_file = path;
                        const path_str = std.mem.span(path);
                        if (ctx.use_color) {
                            w.writeAll(color.bold) catch return -1;
                            w.writeAll(path_str) catch return -1;
                            w.writeAll(color.reset) catch return -1;
                        } else {
                            w.writeAll(path_str) catch return -1;
                        }
                        w.writeByte('\n') catch return -1;
                    }
                }
            }
        },
        'H' => {
            if (ctx.use_color) {
                w.writeAll(color.cyan) catch return -1;
                w.writeAll(slice) catch return -1;
                w.writeAll(color.reset) catch return -1;
            } else {
                w.writeAll(slice) catch return -1;
            }
        },
        '+' => {
            if (ctx.use_color) {
                w.writeAll(color.bright_green) catch return -1;
                w.writeByte('+') catch return -1;
                w.writeAll(slice) catch return -1;
                w.writeAll(color.reset) catch return -1;
            } else {
                w.writeByte('+') catch return -1;
                w.writeAll(slice) catch return -1;
            }
        },
        '-' => {
            if (ctx.use_color) {
                w.writeAll(color.bright_red) catch return -1;
                w.writeByte('-') catch return -1;
                w.writeAll(slice) catch return -1;
                w.writeAll(color.reset) catch return -1;
            } else {
                w.writeByte('-') catch return -1;
                w.writeAll(slice) catch return -1;
            }
        },
        ' ' => {
            if (ctx.use_color) {
                w.writeAll(color.dim) catch return -1;
                w.writeByte(' ') catch return -1;
                w.writeAll(slice) catch return -1;
                w.writeAll(color.reset) catch return -1;
            } else {
                w.writeByte(' ') catch return -1;
                w.writeAll(slice) catch return -1;
            }
        },
        else => {},
    }
    return 0;
}

// --- Stat summary ---

pub fn writeStat(diff_result: ?*c.git_diff, use_color: bool, w: *Writer) !void {
    var stats: ?*c.git_diff_stats = null;
    try git.check(c.git_diff_get_stats(&stats, diff_result));
    defer c.git_diff_stats_free(stats);

    const total_files = c.git_diff_stats_files_changed(stats);
    const total_add = c.git_diff_stats_insertions(stats);
    const total_del = c.git_diff_stats_deletions(stats);

    if (use_color) {
        try w.print("{s}{d} file{s}{s}, ", .{ color.bold, total_files, if (total_files != 1) "s" else "", color.reset });
        try w.print("{s}+{d}{s} ", .{ color.bright_green, total_add, color.reset });
        try w.print("{s}-{d}{s}\n", .{ color.bright_red, total_del, color.reset });
    } else {
        try w.print("{d} file{s}, +{d} -{d}\n", .{ total_files, if (total_files != 1) "s" else "", total_add, total_del });
    }

    const num_deltas = c.git_diff_num_deltas(diff_result);
    for (0..num_deltas) |i| {
        var patch: ?*c.git_patch = null;
        try git.check(c.git_patch_from_diff(&patch, diff_result, i));
        defer c.git_patch_free(patch);

        const delta = c.git_patch_get_delta(patch);
        if (delta == null) continue;

        const path = if (delta.*.new_file.path != null)
            std.mem.span(delta.*.new_file.path)
        else if (delta.*.old_file.path != null)
            std.mem.span(delta.*.old_file.path)
        else
            continue;

        var ctx_lines: usize = 0;
        var file_add: usize = 0;
        var file_del: usize = 0;
        try git.check(c.git_patch_line_stats(&ctx_lines, &file_add, &file_del, patch));

        if (use_color) {
            try w.print("  {s} ", .{path});
            if (file_add > 0) try w.print("{s}+{d}{s}", .{ color.bright_green, file_add, color.reset });
            if (file_add > 0 and file_del > 0) try w.writeByte(' ');
            if (file_del > 0) try w.print("{s}-{d}{s}", .{ color.bright_red, file_del, color.reset });
            try w.writeByte('\n');
        } else {
            try w.print("  {s} ", .{path});
            if (file_add > 0) try w.print("+{d}", .{file_add});
            if (file_add > 0 and file_del > 0) try w.writeByte(' ');
            if (file_del > 0) try w.print("-{d}", .{file_del});
            try w.writeByte('\n');
        }
    }
}

// --- Date formatting ---

pub const Date = struct {
    year: i32,
    month: u5,
    day: u5,
};

pub fn epochToDate(timestamp: c_long) Date {
    // Pre-1970 timestamps are negative; clamp to epoch
    const ts: u64 = if (timestamp > 0) @intCast(timestamp) else 0;
    const epoch = std.time.epoch.EpochSeconds{ .secs = ts };
    const day_count = epoch.getEpochDay();
    const yd = day_count.calculateYearDay();
    const md = yd.calculateMonthDay();
    return .{
        .year = yd.year,
        .month = @intFromEnum(md.month),
        .day = md.day_index + 1,
    };
}
