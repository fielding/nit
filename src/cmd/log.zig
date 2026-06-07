const std = @import("std");
const git = @import("../git.zig");
const c = git.c;
const color = @import("../color.zig");
const fmt = @import("../fmt.zig");

const Writer = std.Io.Writer;

pub fn run(repo: *c.git_repository, human: bool, count: usize, w: *Writer) !void {
    var walk: ?*c.git_revwalk = null;
    try git.check(c.git_revwalk_new(&walk, repo));
    defer c.git_revwalk_free(walk);

    try git.check(c.git_revwalk_push_head(walk));
    _ = c.git_revwalk_sorting(walk, c.GIT_SORT_TIME | c.GIT_SORT_TOPOLOGICAL);

    var oid: c.git_oid = undefined;
    var shown: usize = 0;

    while (shown < count) {
        const err = c.git_revwalk_next(&oid, walk);
        if (err < 0) break;

        var commit: ?*c.git_commit = null;
        try git.check(c.git_commit_lookup(&commit, repo, &oid));
        defer c.git_commit_free(commit);

        const raw_summary = c.git_commit_summary(commit);
        const summary: []const u8 = if (raw_summary != null) std.mem.span(raw_summary) else "(empty)";

        var oid_buf: [c.GIT_OID_HEXSZ + 1]u8 = undefined;
        _ = c.git_oid_tostr(&oid_buf, oid_buf.len, &oid);
        const short_hash = oid_buf[0..7];

        if (human) {
            const use_color = color.isTty();
            const d = fmt.epochToDate(c.git_commit_time(commit));
            if (use_color) {
                try w.print("{s}{s}{s} {s}{d}-{d:0>2}-{d:0>2}{s} {s}\n", .{
                    color.hash,   short_hash, color.reset,
                    color.date,   d.year,  d.month, d.day, color.reset,
                    summary,
                });
            } else {
                try w.print("{s} {d}-{d:0>2}-{d:0>2} {s}\n", .{ short_hash, d.year, d.month, d.day, summary });
            }
        } else {
            try w.print("{s} {s}\n", .{ short_hash, summary });
        }

        shown += 1;
    }
}
