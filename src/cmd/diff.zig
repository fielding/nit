const std = @import("std");
const git = @import("../git.zig");
const c = git.c;
const color = @import("../color.zig");
const fmt = @import("../fmt.zig");

const Writer = std.Io.Writer;

pub fn run(repo: *c.git_repository, human: bool, staged: bool, w: *Writer) !void {
    var opts: c.git_diff_options = undefined;
    try git.check(c.git_diff_options_init(&opts, c.GIT_DIFF_OPTIONS_VERSION));

    opts.context_lines = if (human) 3 else 1;
    opts.flags = c.GIT_DIFF_INCLUDE_UNTRACKED;

    var diff_result: ?*c.git_diff = null;

    if (staged) {
        // Diff HEAD to index. HEAD may not exist yet (initial commit).
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
        var ctx = fmt.CompactCtx{ .writer = w };
        _ = c.git_diff_print(diff_result, c.GIT_DIFF_FORMAT_PATCH, fmt.compactCallback, @ptrCast(&ctx));
    }
}

fn printHuman(diff_result: ?*c.git_diff, w: *Writer) !void {
    const use_color = color.isTty();
    const num_deltas = c.git_diff_num_deltas(diff_result);
    if (num_deltas == 0) return;

    try fmt.writeStat(diff_result, use_color, w);
    try w.writeByte('\n');

    var ctx = fmt.HumanCtx{ .writer = w, .use_color = use_color, .current_file = null };
    _ = c.git_diff_print(diff_result, c.GIT_DIFF_FORMAT_PATCH, fmt.humanCallback, @ptrCast(&ctx));
}
