const std = @import("std");
const git = @import("../git.zig");
const c = git.c;
const color = @import("../color.zig");

const Writer = std.Io.Writer;

pub fn run(repo: *c.git_repository, human: bool, staged: bool, w: *Writer) !void {
    var opts: c.git_diff_options = undefined;
    try git.check(c.git_diff_options_init(&opts, c.GIT_DIFF_OPTIONS_VERSION));

    opts.context_lines = if (human) 3 else 1;
    opts.flags = c.GIT_DIFF_INCLUDE_UNTRACKED;

    var diff_result: ?*c.git_diff = null;

    if (staged) {
        var head: ?*c.git_object = null;
        _ = c.git_revparse_single(&head, repo, "HEAD");
        defer if (head != null) c.git_object_free(head);

        var tree: ?*c.git_tree = null;
        if (head != null) {
            var commit: ?*c.git_commit = null;
            try git.check(c.git_commit_lookup(&commit, repo, c.git_object_id(head)));
            defer c.git_commit_free(commit);
            try git.check(c.git_commit_tree(&tree, commit));
        }
        defer if (tree != null) c.git_tree_free(tree);

        var index: ?*c.git_index = null;
        try git.check(c.git_repository_index(&index, repo));
        defer c.git_index_free(index);

        try git.check(c.git_diff_tree_to_index(&diff_result, repo, tree, index, &opts));
    } else {
        try git.check(c.git_diff_index_to_workdir(&diff_result, repo, null, &opts));
    }
    defer c.git_diff_free(diff_result);

    if (human) {
        try printHuman(diff_result, w);
    } else {
        var ctx = PrintCtx{ .writer = w, .last_file = null };
        _ = c.git_diff_print(diff_result, c.GIT_DIFF_FORMAT_PATCH, compactCallback, @ptrCast(&ctx));
    }
}

// --- Compact (agent) output ---

const PrintCtx = struct {
    writer: *Writer,
    last_file: ?[*:0]const u8,
};

fn compactCallback(
    delta: [*c]const c.git_diff_delta,
    _: [*c]const c.git_diff_hunk,
    line: [*c]const c.git_diff_line,
    payload: ?*anyopaque,
) callconv(.c) c_int {
    const ctx: *PrintCtx = @ptrCast(@alignCast(payload));
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
            // Strip trailing context text after closing @@
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
                if (path != null) {
                    if (slice.len >= 4 and std.mem.eql(u8, slice[0..4], "diff")) {
                        w.writeAll("--- ") catch return -1;
                        w.writeAll(std.mem.span(path)) catch return -1;
                        w.writeByte('\n') catch return -1;
                    }
                }
            }
        },
        else => {},
    }

    return 0;
}

// --- Human output ---

fn printHuman(diff_result: ?*c.git_diff, w: *Writer) !void {
    const use_color = color.isTty();

    // Print per-file stat + patch
    const num_deltas = c.git_diff_num_deltas(diff_result);
    if (num_deltas == 0) return;

    // Collect stats first
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
        try w.print("{s}-{d}{s}\n\n", .{ color.bright_red, total_del, color.reset });
    } else {
        try w.print("{d} file{s}, +{d} -{d}\n\n", .{ total_files, if (total_files != 1) "s" else "", total_add, total_del });
    }

    // Print each file's patch
    var ctx = HumanCtx{ .writer = w, .use_color = use_color, .current_file = null };
    _ = c.git_diff_print(diff_result, c.GIT_DIFF_FORMAT_PATCH, humanCallback, @ptrCast(&ctx));
}

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
            // File header - print a clean colored separator on first line only
            if (delta != null) {
                const path = delta.*.new_file.path;
                if (path != null and slice.len >= 4 and std.mem.eql(u8, slice[0..4], "diff")) {
                    // Check if this is a new file vs the last one we printed
                    const new_path = path;
                    if (ctx.current_file == null or ctx.current_file != new_path) {
                        if (ctx.current_file != null) {
                            // Separator between files
                            w.writeByte('\n') catch return -1;
                        }
                        ctx.current_file = new_path;

                        const path_str = std.mem.span(path);

                        if (ctx.use_color) {
                            // Bold filename
                            w.writeAll(color.bold) catch return -1;
                            w.writeAll(path_str) catch return -1;
                            w.writeAll(color.reset) catch return -1;
                            w.writeByte('\n') catch return -1;
                        } else {
                            w.writeAll(path_str) catch return -1;
                            w.writeByte('\n') catch return -1;
                        }
                    }
                }
            }
        },
        'H' => {
            // Hunk header
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
