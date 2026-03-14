const std = @import("std");
const git = @import("../git.zig");
const c = git.c;

const Writer = std.Io.Writer;

/// Compact agent output (default):
///   a1b2c3d Fix null pointer in parser
///   --- src/main.zig
///   @@ -10,3 +10,3 @@
///   -old line
///   +new line
///
/// Human output (-H):
///   commit a1b2c3d
///   Author: Name <email>
///   Date:   2026-03-14
///
///   Fix null pointer in parser
///
///   diff --git a/src/main.zig b/src/main.zig
///   ...
pub fn run(repo: *c.git_repository, human: bool, rev: ?[]const u8, w: *Writer) !void {
    var oid: c.git_oid = undefined;

    if (rev) |r| {
        // Resolve the given revision
        var obj: ?*c.git_object = null;
        const rev_z = try std.heap.page_allocator.dupeZ(u8, r);
        defer std.heap.page_allocator.free(rev_z);
        try git.check(c.git_revparse_single(&obj, repo, rev_z));
        defer c.git_object_free(obj);
        oid = c.git_object_id(obj).*;
    } else {
        // Default to HEAD
        var head: ?*c.git_object = null;
        try git.check(c.git_revparse_single(&head, repo, "HEAD"));
        defer c.git_object_free(head);
        oid = c.git_object_id(head).*;
    }

    var commit: ?*c.git_commit = null;
    try git.check(c.git_commit_lookup(&commit, repo, &oid));
    defer c.git_commit_free(commit);

    // Print commit info
    var oid_buf: [c.GIT_OID_SHA1_HEXSIZE + 1]u8 = undefined;
    _ = c.git_oid_tostr(&oid_buf, oid_buf.len, &oid);
    const short_hash = oid_buf[0..7];
    const summary = std.mem.span(c.git_commit_summary(commit));

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

        try w.print("commit {s}\n", .{full_hash});
        try w.print("Author: {s} <{s}>\n", .{ name, email });
        try w.print("Date:   {d}-{d:0>2}-{d:0>2}\n", .{ yd.year, @intFromEnum(md.month), md.day_index + 1 });
        try w.print("\n    {s}\n\n", .{summary});
    } else {
        try w.print("{s} {s}\n", .{ short_hash, summary });
    }

    // Get the commit's tree and parent's tree for diff
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

    // Diff parent tree to commit tree
    var opts: c.git_diff_options = undefined;
    try git.check(c.git_diff_options_init(&opts, c.GIT_DIFF_OPTIONS_VERSION));
    opts.context_lines = if (human) 3 else 1;

    var diff_result: ?*c.git_diff = null;
    try git.check(c.git_diff_tree_to_tree(&diff_result, repo, parent_tree, commit_tree, &opts));
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
                w.writeAll(slice) catch return -1;
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
