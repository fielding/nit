const std = @import("std");
const git = @import("../git.zig");
const c = git.c;
const color = @import("../color.zig");

const Writer = std.Io.Writer;

pub fn run(repo: *c.git_repository, human: bool, stat: bool, rev: ?[]const u8, w: *Writer) !void {
    var oid: c.git_oid = undefined;

    if (rev) |r| {
        var obj: ?*c.git_object = null;
        const rev_z = try std.heap.page_allocator.dupeZ(u8, r);
        defer std.heap.page_allocator.free(rev_z);
        try git.check(c.git_revparse_single(&obj, repo, rev_z));
        defer c.git_object_free(obj);
        oid = c.git_object_id(obj).*;
    } else {
        var head: ?*c.git_object = null;
        try git.check(c.git_revparse_single(&head, repo, "HEAD"));
        defer c.git_object_free(head);
        oid = c.git_object_id(head).*;
    }

    var commit: ?*c.git_commit = null;
    try git.check(c.git_commit_lookup(&commit, repo, &oid));
    defer c.git_commit_free(commit);

    var oid_buf: [c.GIT_OID_SHA1_HEXSIZE + 1]u8 = undefined;
    _ = c.git_oid_tostr(&oid_buf, oid_buf.len, &oid);
    const short_hash = oid_buf[0..7];
    const summary = std.mem.span(c.git_commit_summary(commit));
    const use_color = human and color.isTty();

    if (human) {
        const full_hash = std.mem.span(c.git_oid_tostr(&oid_buf, oid_buf.len, &oid));
        const author = c.git_commit_author(commit);
        const name = if (author != null) std.mem.span(author.*.name) else "unknown";
        const email = if (author != null) std.mem.span(author.*.email) else "unknown";

        const time = c.git_commit_time(commit);
        const ts: u64 = @intCast(time);
        const epoch = std.time.epoch.EpochSeconds{ .secs = ts };
        const day = epoch.getEpochDay();
        const yd = day.calculateYearDay();
        const md = yd.calculateMonthDay();

        if (use_color) {
            try w.print("{s}commit {s}{s}\n", .{ color.yellow, full_hash, color.reset });
            try w.print("{s}Author:{s} {s} <{s}>\n", .{ color.bold, color.reset, name, email });
            try w.print("{s}Date:{s}   {d}-{d:0>2}-{d:0>2}\n", .{ color.bold, color.reset, yd.year, @intFromEnum(md.month), md.day_index + 1 });
            try w.print("\n    {s}\n\n", .{summary});
        } else {
            try w.print("commit {s}\n", .{full_hash});
            try w.print("Author: {s} <{s}>\n", .{ name, email });
            try w.print("Date:   {d}-{d:0>2}-{d:0>2}\n", .{ yd.year, @intFromEnum(md.month), md.day_index + 1 });
            try w.print("\n    {s}\n\n", .{summary});
        }
    } else {
        try w.print("{s} {s}\n", .{ short_hash, summary });
    }

    // Diff parent tree to commit tree
    var commit_tree: ?*c.git_tree = null;
    try git.check(c.git_commit_tree(&commit_tree, commit));
    defer c.git_tree_free(commit_tree);

    var parent_tree: ?*c.git_tree = null;
    if (c.git_commit_parentcount(commit) > 0) {
        var parent: ?*c.git_commit = null;
        try git.check(c.git_commit_parent(&parent, commit, 0));
        defer c.git_commit_free(parent);
        try git.check(c.git_commit_tree(&parent_tree, parent));
    }
    defer if (parent_tree != null) c.git_tree_free(parent_tree);

    var opts: c.git_diff_options = undefined;
    try git.check(c.git_diff_options_init(&opts, c.GIT_DIFF_OPTIONS_VERSION));
    opts.context_lines = if (human) 3 else 1;

    var diff_result: ?*c.git_diff = null;
    try git.check(c.git_diff_tree_to_tree(&diff_result, repo, parent_tree, commit_tree, &opts));
    defer c.git_diff_free(diff_result);

    if (stat) {
        try writeStat(diff_result, use_color, w);
    } else if (human) {
        var ctx = HumanCtx{ .writer = w, .use_color = use_color, .current_file = null };
        _ = c.git_diff_print(diff_result, c.GIT_DIFF_FORMAT_PATCH, humanCallback, @ptrCast(&ctx));
    } else {
        var ctx = CompactCtx{ .writer = w };
        _ = c.git_diff_print(diff_result, c.GIT_DIFF_FORMAT_PATCH, compactCallback, @ptrCast(&ctx));
    }
}

// --- Stat ---

fn writeStat(diff_result: ?*c.git_diff, use_color: bool, w: *Writer) !void {
    var stats: ?*c.git_diff_stats = null;
    try git.check(c.git_diff_get_stats(&stats, diff_result));
    defer c.git_diff_stats_free(stats);

    const total_files = c.git_diff_stats_files_changed(stats);
    const total_add = c.git_diff_stats_insertions(stats);
    const total_del = c.git_diff_stats_deletions(stats);

    // Summary line
    if (use_color) {
        try w.print("{s}{d} file{s}{s}, ", .{ color.bold, total_files, if (total_files != 1) "s" else "", color.reset });
        try w.print("{s}+{d}{s} ", .{ color.bright_green, total_add, color.reset });
        try w.print("{s}-{d}{s}\n", .{ color.bright_red, total_del, color.reset });
    } else {
        try w.print("{d} file{s}, +{d} -{d}\n", .{ total_files, if (total_files != 1) "s" else "", total_add, total_del });
    }

    // Per-file lines via git_patch
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

// --- Compact ---

const CompactCtx = struct {
    writer: *Writer,
};

fn compactCallback(
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

// --- Human ---

const HumanCtx = struct {
    writer: *Writer,
    use_color: bool,
    current_file: ?[*:0]const u8,
};

fn humanCallback(
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
                    const new_path = path;
                    if (ctx.current_file == null or ctx.current_file != new_path) {
                        if (ctx.current_file != null) w.writeByte('\n') catch return -1;
                        ctx.current_file = new_path;
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
            if (ctx.use_color) w.writeAll(color.bright_green) catch return -1;
            w.writeByte('+') catch return -1;
            w.writeAll(slice) catch return -1;
            if (ctx.use_color) w.writeAll(color.reset) catch return -1;
        },
        '-' => {
            if (ctx.use_color) w.writeAll(color.bright_red) catch return -1;
            w.writeByte('-') catch return -1;
            w.writeAll(slice) catch return -1;
            if (ctx.use_color) w.writeAll(color.reset) catch return -1;
        },
        ' ' => {
            if (ctx.use_color) w.writeAll(color.dim) catch return -1;
            w.writeByte(' ') catch return -1;
            w.writeAll(slice) catch return -1;
            if (ctx.use_color) w.writeAll(color.reset) catch return -1;
        },
        else => {},
    }
    return 0;
}
