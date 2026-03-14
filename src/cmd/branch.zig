const std = @import("std");
const git = @import("../git.zig");
const c = git.c;
const color = @import("../color.zig");

const Writer = std.Io.Writer;

/// Compact (default):
///   * main
///   feature-auth
///   fix-parser
///
/// Human (-H):
///   * main
///   feature-auth
///   fix-parser
///   (same but colored: current branch green+bold, others plain)
pub fn run(repo: *c.git_repository, human: bool, w: *Writer) !void {
    var iter: ?*c.git_branch_iterator = null;
    try git.check(c.git_branch_iterator_new(&iter, repo, c.GIT_BRANCH_LOCAL));
    defer c.git_branch_iterator_free(iter);

    const use_color = human and color.isTty();

    var ref: ?*c.git_reference = null;
    var branch_type: c.git_branch_t = undefined;

    while (true) {
        const err = c.git_branch_next(&ref, &branch_type, iter);
        if (err < 0) break;
        defer c.git_reference_free(ref);

        var name_ptr: [*c]const u8 = null;
        try git.check(c.git_branch_name(&name_ptr, ref));
        const name = if (name_ptr) |p| std.mem.span(p) else continue;

        const is_head = c.git_branch_is_head(ref) == 1;

        if (is_head) {
            if (use_color) {
                try w.print("{s}{s}* {s}{s}\n", .{ color.bold, color.staged, name, color.reset });
            } else {
                try w.print("* {s}\n", .{name});
            }
        } else {
            try w.print("  {s}\n", .{name});
        }
    }
}
