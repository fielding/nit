//! Zig version compatibility layer.
//!
//! nit supports both Zig 0.15.x (what CI pins) and 0.16-dev (where the std
//! I/O and process APIs changed shape). Everything version-sensitive lives
//! here so the rest of the codebase can stay on the shared std.Io.Writer
//! interface, which is identical across both versions.
const std = @import("std");

/// Zig 0.16 introduced std.process.Init and moved File I/O behind std.Io.
pub const is_modern = @hasDecl(std.process, "Init");

/// On 0.16 main receives std.process.Init (which carries the Io instance
/// and args); on 0.15 main takes no arguments and we reach for globals.
pub const ProcessInit = if (is_modern) std.process.Init else void;

pub const StdoutWriter = if (is_modern) std.Io.File.Writer else std.fs.File.Writer;

pub fn stdoutWriter(init: ProcessInit, buffer: []u8) StdoutWriter {
    if (is_modern) {
        // Streaming, not positional: positional mode pwrites from offset 0,
        // which overwrites earlier output when stdout is redirected to a file.
        return std.Io.File.stdout().writerStreaming(init.io, buffer);
    } else {
        return std.fs.File.stdout().writer(buffer);
    }
}

/// Argument slices live for the whole process (nit is a short-lived CLI):
/// arena-backed on 0.16, page-allocated and never freed on 0.15.
pub fn argsSlice(init: ProcessInit) ![]const [:0]const u8 {
    if (is_modern) {
        return init.minimal.args.toSlice(init.arena.allocator());
    } else {
        const raw = try std.process.argsAlloc(std.heap.page_allocator);
        return @ptrCast(raw);
    }
}

/// libc getenv: identical on both versions (std.posix.getenv was removed in 0.16).
pub fn getenv(name: [*:0]const u8) ?[]const u8 {
    const val = std.c.getenv(name) orelse return null;
    return std.mem.span(val);
}

pub fn stdoutIsTty() bool {
    return std.c.isatty(std.posix.STDOUT_FILENO) == 1;
}

// std.posix.execvpeZ was removed in 0.16; libc execvp (which inherits the
// process environment) covers both versions since we always link libc.
extern "c" fn execvp(file: [*:0]const u8, argv: [*:null]const ?[*:0]const u8) c_int;

/// Replace the current process with `git`. Only returns on failure.
pub fn execGit(argv: [*:null]const ?[*:0]const u8) error{ExecFailed} {
    _ = execvp("git", argv);
    return error.ExecFailed;
}
