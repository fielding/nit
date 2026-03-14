const std = @import("std");
const git = @import("../git.zig");
const c = git.c;

const Writer = std.Io.Writer;

pub fn run(repo: *c.git_repository, human: bool, w: *Writer) !void {
    var opts: c.git_status_options = undefined;
    try git.check(c.git_status_options_init(&opts, c.GIT_STATUS_OPTIONS_VERSION));
    opts.show = c.GIT_STATUS_SHOW_INDEX_AND_WORKDIR;
    opts.flags = c.GIT_STATUS_OPT_INCLUDE_UNTRACKED |
        c.GIT_STATUS_OPT_RENAMES_HEAD_TO_INDEX |
        c.GIT_STATUS_OPT_SORT_CASE_SENSITIVELY;

    var status_list: ?*c.git_status_list = null;
    try git.check(c.git_status_list_new(&status_list, repo, &opts));
    defer c.git_status_list_free(status_list);

    const count = c.git_status_list_entrycount(status_list);
    if (count == 0) return;

    if (human) {
        try writeHuman(status_list, count, w);
    } else {
        try writeCompact(status_list, count, w);
    }
}

fn writeCompact(status_list: ?*c.git_status_list, count: usize, w: *Writer) !void {
    for (0..count) |i| {
        const entry = c.git_status_byindex(status_list, i);
        if (entry == null) continue;

        const s = entry.*.status;

        var ix: u8 = ' ';
        if (s & c.GIT_STATUS_INDEX_NEW != 0) ix = 'A'
        else if (s & c.GIT_STATUS_INDEX_MODIFIED != 0) ix = 'M'
        else if (s & c.GIT_STATUS_INDEX_DELETED != 0) ix = 'D'
        else if (s & c.GIT_STATUS_INDEX_RENAMED != 0) ix = 'R'
        else if (s & c.GIT_STATUS_INDEX_TYPECHANGE != 0) ix = 'T';

        var wt: u8 = ' ';
        if (s & c.GIT_STATUS_WT_NEW != 0) wt = '?'
        else if (s & c.GIT_STATUS_WT_MODIFIED != 0) wt = 'M'
        else if (s & c.GIT_STATUS_WT_DELETED != 0) wt = 'D'
        else if (s & c.GIT_STATUS_WT_RENAMED != 0) wt = 'R'
        else if (s & c.GIT_STATUS_WT_TYPECHANGE != 0) wt = 'T';

        if (s == c.GIT_STATUS_WT_NEW) {
            ix = '?';
            wt = '?';
        }

        const path = if (entry.*.index_to_workdir != null)
            entry.*.index_to_workdir.*.new_file.path
        else if (entry.*.head_to_index != null)
            entry.*.head_to_index.*.new_file.path
        else
            continue;

        try w.print("{c}{c} {s}\n", .{ ix, wt, std.mem.span(path) });
    }
}

fn writeHuman(status_list: ?*c.git_status_list, count: usize, w: *Writer) !void {
    var has_staged = false;
    var has_unstaged = false;
    var has_untracked = false;

    for (0..count) |i| {
        const entry = c.git_status_byindex(status_list, i);
        if (entry == null) continue;
        const s = entry.*.status;
        if (s & (c.GIT_STATUS_INDEX_NEW | c.GIT_STATUS_INDEX_MODIFIED | c.GIT_STATUS_INDEX_DELETED | c.GIT_STATUS_INDEX_RENAMED | c.GIT_STATUS_INDEX_TYPECHANGE) != 0) has_staged = true;
        if (s & (c.GIT_STATUS_WT_MODIFIED | c.GIT_STATUS_WT_DELETED | c.GIT_STATUS_WT_RENAMED | c.GIT_STATUS_WT_TYPECHANGE) != 0) has_unstaged = true;
        if (s == c.GIT_STATUS_WT_NEW) has_untracked = true;
    }

    if (has_staged) {
        try w.writeAll("staged:\n");
        for (0..count) |i| {
            const entry = c.git_status_byindex(status_list, i);
            if (entry == null) continue;
            const s = entry.*.status;
            const label: ?[]const u8 = if (s & c.GIT_STATUS_INDEX_NEW != 0) "new" else if (s & c.GIT_STATUS_INDEX_MODIFIED != 0) "modified" else if (s & c.GIT_STATUS_INDEX_DELETED != 0) "deleted" else if (s & c.GIT_STATUS_INDEX_RENAMED != 0) "renamed" else null;
            if (label) |l| {
                const path = if (entry.*.head_to_index != null) entry.*.head_to_index.*.new_file.path else continue;
                try w.print("  {s}: {s}\n", .{ l, std.mem.span(path) });
            }
        }
    }

    if (has_unstaged) {
        if (has_staged) try w.writeByte('\n');
        try w.writeAll("unstaged:\n");
        for (0..count) |i| {
            const entry = c.git_status_byindex(status_list, i);
            if (entry == null) continue;
            const s = entry.*.status;
            if (s == c.GIT_STATUS_WT_NEW) continue;
            const label: ?[]const u8 = if (s & c.GIT_STATUS_WT_MODIFIED != 0) "modified" else if (s & c.GIT_STATUS_WT_DELETED != 0) "deleted" else if (s & c.GIT_STATUS_WT_RENAMED != 0) "renamed" else null;
            if (label) |l| {
                const path = if (entry.*.index_to_workdir != null) entry.*.index_to_workdir.*.new_file.path else continue;
                try w.print("  {s}: {s}\n", .{ l, std.mem.span(path) });
            }
        }
    }

    if (has_untracked) {
        if (has_staged or has_unstaged) try w.writeByte('\n');
        try w.writeAll("untracked:\n");
        for (0..count) |i| {
            const entry = c.git_status_byindex(status_list, i);
            if (entry == null) continue;
            if (entry.*.status != c.GIT_STATUS_WT_NEW) continue;
            const path = if (entry.*.index_to_workdir != null) entry.*.index_to_workdir.*.new_file.path else continue;
            try w.print("  {s}\n", .{std.mem.span(path)});
        }
    }
}
