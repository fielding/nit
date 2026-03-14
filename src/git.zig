const std = @import("std");

pub const c = @cImport({
    @cInclude("git2.h");
});

pub const Repository = struct {
    repo: *c.git_repository,

    pub fn openFromCwd() !Repository {
        var repo: ?*c.git_repository = null;
        const cwd_dir = std.fs.cwd();
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = try cwd_dir.realpath(".", &buf);
        const path_z = try std.heap.page_allocator.dupeZ(u8, path);
        defer std.heap.page_allocator.free(path_z);

        try check(c.git_repository_open_ext(&repo, path_z, 0, null));
        return .{ .repo = repo.? };
    }

    pub fn deinit(self: *Repository) void {
        c.git_repository_free(self.repo);
    }
};

pub fn init() !void {
    try check(c.git_libgit2_init());
}

pub fn deinit() void {
    _ = c.git_libgit2_shutdown();
}

pub fn check(err: c_int) !void {
    if (err < 0) {
        const e = c.git_error_last();
        if (e) |err_info| {
            const msg = std.mem.span(err_info.*.message);
            std.debug.print("nit: {s}\n", .{msg});
        }
        return error.GitError;
    }
}
