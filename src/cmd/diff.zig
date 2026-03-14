const std = @import("std");
const git = @import("../git.zig");
const c = git.c;

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

    var ctx = PrintCtx{ .writer = w, .human = human };
    _ = c.git_diff_print(diff_result, c.GIT_DIFF_FORMAT_PATCH, printCallback, @ptrCast(&ctx));
}

const PrintCtx = struct {
    writer: *Writer,
    human: bool,
};

fn printCallback(
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

    if (!ctx.human) {
        switch (line.*.origin) {
            '+', '-', ' ' => {
                w.writeByte(@intCast(line.*.origin)) catch return -1;
                w.writeAll(slice) catch return -1;
            },
            'H' => {
                // Keep hunk headers - they show line numbers
                w.writeAll(slice) catch return -1;
            },
            'F' => {
                // Replace verbose file header with just the path
                // Only print once per file (the file header fires multiple lines)
                if (delta != null) {
                    const path = delta.*.new_file.path;
                    if (path != null) {
                        // Check if this is the first header line (starts with "diff")
                        if (slice.len >= 4 and std.mem.eql(u8, slice[0..4], "diff")) {
                            w.writeAll("--- ") catch return -1;
                            w.writeAll(std.mem.span(path)) catch return -1;
                            w.writeByte('\n') catch return -1;
                        }
                        // Skip all other file header lines (index, ---, +++)
                    }
                }
            },
            else => {},
        }
    } else {
        switch (line.*.origin) {
            '+', '-', ' ' => {
                w.writeByte(@intCast(line.*.origin)) catch return -1;
                w.writeAll(slice) catch return -1;
            },
            else => {
                w.writeAll(slice) catch return -1;
            },
        }
    }

    return 0;
}
