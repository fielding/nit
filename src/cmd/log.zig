const std = @import("std");
const git = @import("../git.zig");
const c = git.c;
const clr = @import("../color.zig");

const Writer = std.Io.Writer;
const default_count: usize = 20;

pub fn run(repo: *c.git_repository, human: bool, count: usize, w: *Writer) !void {
    var walk: ?*c.git_revwalk = null;
    try git.check(c.git_revwalk_new(&walk, repo));
    defer c.git_revwalk_free(walk);

    try git.check(c.git_revwalk_push_head(walk));
    _ = c.git_revwalk_sorting(walk, c.GIT_SORT_TIME);

    var oid: c.git_oid = undefined;
    var shown: usize = 0;
    const max = if (count == 0) default_count else count;

    while (shown < max) {
        const err = c.git_revwalk_next(&oid, walk);
        if (err < 0) break;

        var commit: ?*c.git_commit = null;
        try git.check(c.git_commit_lookup(&commit, repo, &oid));
        defer c.git_commit_free(commit);

        const summary = std.mem.span(c.git_commit_summary(commit));

        var oid_buf: [c.GIT_OID_SHA1_HEXSIZE + 1]u8 = undefined;
        _ = c.git_oid_tostr(&oid_buf, oid_buf.len, &oid);
        const short_hash = oid_buf[0..7];

        if (human) {
            const use_color = clr.isTty();
            const time = c.git_commit_time(commit);
            const ts: u64 = @intCast(time);
            const epoch = std.time.epoch.EpochSeconds{ .secs = ts };
            const day = epoch.getEpochDay();
            const yd = day.calculateYearDay();
            const md = yd.calculateMonthDay();
            if (use_color) {
                try w.print("{s}{s}{s} {s}{d}-{d:0>2}-{d:0>2}{s} {s}\n", .{
                    clr.yellow,
                    short_hash,
                    clr.reset,
                    clr.dim,
                    yd.year,
                    @intFromEnum(md.month),
                    md.day_index + 1,
                    clr.reset,
                    summary,
                });
            } else {
                try w.print("{s} {d}-{d:0>2}-{d:0>2} {s}\n", .{
                    short_hash,
                    yd.year,
                    @intFromEnum(md.month),
                    md.day_index + 1,
                    summary,
                });
            }
        } else {
            try w.print("{s} {s}\n", .{ short_hash, summary });
        }

        shown += 1;
    }
}
