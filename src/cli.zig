const std = @import("std");
const git = @import("git.zig");
const status = @import("cmd/status.zig");
const log = @import("cmd/log.zig");
const diff = @import("cmd/diff.zig");
const show = @import("cmd/show.zig");

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
    \\  show      commit details + patch
    \\
    \\flags:
    \\  -H        human-readable output
    \\  -n <N>    limit entries (log)
    \\
;

pub fn run() !void {
    var buf: [8192]u8 = undefined;
    var file_writer = std.fs.File.stdout().writer(&buf);
    const w = &file_writer.interface;

    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, args);

    if (args.len < 2) {
        try w.writeAll(usage);
        try w.flush();
        return;
    }

    const cmd = args[1];

    var human = false;
    var count: usize = 20;
    var staged = false;
    var stat = false;
    var has_unknown_flags = false;

    for (args[2..]) |arg| {
        if (std.mem.eql(u8, arg, "-H") or std.mem.eql(u8, arg, "--human")) {
            human = true;
        } else if (std.mem.eql(u8, arg, "-s") or std.mem.eql(u8, arg, "--staged")) {
            staged = true;
        } else if (std.mem.eql(u8, arg, "--stat") and std.mem.eql(u8, cmd, "show")) {
            stat = true;
        } else if (std.mem.eql(u8, arg, "-n")) {
            // Handled below with value parsing
        } else if (arg.len > 0 and arg[0] == '-') {
            // Flag we don't recognize - passthrough to git
            has_unknown_flags = true;
        }
    }

    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-n") and i + 1 < args.len) {
            count = std.fmt.parseInt(usize, args[i + 1], 10) catch 20;
            i += 1;
        }
    }

    // If we see flags we don't handle, let git deal with it
    if (has_unknown_flags) {
        try w.flush();
        return passthrough(args);
    }

    // Passthrough and help skip libgit2 entirely for faster startup
    if (std.mem.eql(u8, cmd, "help") or std.mem.eql(u8, cmd, "-h") or std.mem.eql(u8, cmd, "--help")) {
        try w.writeAll(usage);
        try w.flush();
        return;
    }

    const is_native = std.mem.eql(u8, cmd, "status") or std.mem.eql(u8, cmd, "s") or
        std.mem.eql(u8, cmd, "log") or std.mem.eql(u8, cmd, "l") or
        std.mem.eql(u8, cmd, "diff") or std.mem.eql(u8, cmd, "d") or
        std.mem.eql(u8, cmd, "show");

    if (!is_native) {
        try w.flush();
        return passthrough(args);
    }

    // Only init libgit2 for native commands
    try git.init();
    defer git.deinit();

    // Native commands — optimized output via libgit2
    if (std.mem.eql(u8, cmd, "status") or std.mem.eql(u8, cmd, "s")) {
        var repo = try openRepo(w);
        defer repo.deinit();
        try status.run(repo.repo, human, w);
    } else if (std.mem.eql(u8, cmd, "log") or std.mem.eql(u8, cmd, "l")) {
        var repo = try openRepo(w);
        defer repo.deinit();
        try log.run(repo.repo, human, count, w);
    } else if (std.mem.eql(u8, cmd, "diff") or std.mem.eql(u8, cmd, "d")) {
        var repo = try openRepo(w);
        defer repo.deinit();
        try diff.run(repo.repo, human, staged, w);
    } else if (std.mem.eql(u8, cmd, "show")) {
        var repo = try openRepo(w);
        defer repo.deinit();
        // Find revision arg (first non-flag arg after "show")
        var rev: ?[]const u8 = null;
        for (args[2..]) |arg| {
            if (arg.len > 0 and arg[0] != '-') {
                rev = arg;
                break;
            }
        }
        try show.run(repo.repo, human, stat, rev, w);
    }

    try w.flush();
}

fn openRepo(_: *std.Io.Writer) !git.Repository {
    return git.Repository.openFromCwd() catch {
        std.debug.print("fatal: not a git repository\n", .{});
        std.process.exit(128);
    };
}

fn passthrough(args: []const [:0]const u8) !void {
    // Build null-terminated argv: ["git", args[1..], null]
    const alloc = std.heap.page_allocator;
    const argv = try alloc.alloc(?[*:0]const u8, args.len + 1);
    argv[0] = "git";
    for (args[1..], 1..) |arg, idx| {
        argv[idx] = arg.ptr;
    }
    argv[args.len] = null;

    const argv_ptr: [*:null]const ?[*:0]const u8 = @ptrCast(argv.ptr);
    const envp: [*:null]const ?[*:0]const u8 = @ptrCast(std.c.environ);

    return std.posix.execvpeZ("git", argv_ptr, envp);
}
