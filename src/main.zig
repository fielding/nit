const std = @import("std");
const git = @import("git.zig");
const status = @import("status.zig");
const log = @import("log.zig");
const diff = @import("diff.zig");

const usage =
    \\nit - the smallest unit of git
    \\
    \\usage: nit <command> [options]
    \\
    \\commands:
    \\  status    working tree status (compact)
    \\  log       commit history (oneline)
    \\  diff      unstaged changes (1-line context)
    \\  diff -s   staged changes
    \\
    \\flags:
    \\  -H        human-readable output
    \\  -n <N>    limit entries (log)
    \\
;

const Writer = std.Io.Writer;

pub fn main() !void {
    var buf: [8192]u8 = undefined;
    var file_writer = std.fs.File.stdout().writer(&buf);
    const w = &file_writer.interface;

    try git.init();
    defer git.deinit();

    var repo = Repository.openFromCwd() catch {
        try w.writeAll("fatal: not a git repository\n");
        try w.flush();
        std.process.exit(128);
    };
    defer repo.deinit();

    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, args);

    if (args.len < 2) {
        try w.writeAll(usage);
        try w.flush();
        return;
    }

    var human = false;
    var count: usize = 20;
    var staged = false;

    // Parse flags
    for (args[2..]) |arg| {
        if (std.mem.eql(u8, arg, "-H") or std.mem.eql(u8, arg, "--human")) {
            human = true;
        } else if (std.mem.eql(u8, arg, "-s") or std.mem.eql(u8, arg, "--staged")) {
            staged = true;
        }
    }

    // Parse -n <count>
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-n") and i + 1 < args.len) {
            count = std.fmt.parseInt(usize, args[i + 1], 10) catch 20;
            i += 1;
        }
    }

    const cmd = args[1];

    if (std.mem.eql(u8, cmd, "status") or std.mem.eql(u8, cmd, "s")) {
        try status.run(repo.repo, human, w);
    } else if (std.mem.eql(u8, cmd, "log") or std.mem.eql(u8, cmd, "l")) {
        try log.run(repo.repo, human, count, w);
    } else if (std.mem.eql(u8, cmd, "diff") or std.mem.eql(u8, cmd, "d")) {
        try diff.run(repo.repo, human, staged, w);
    } else if (std.mem.eql(u8, cmd, "help") or std.mem.eql(u8, cmd, "-h") or std.mem.eql(u8, cmd, "--help")) {
        try w.writeAll(usage);
    } else {
        try w.print("nit: unknown command '{s}'\n", .{cmd});
        try w.writeAll(usage);
        try w.flush();
        std.process.exit(1);
    }

    try w.flush();
}

const Repository = git.Repository;
