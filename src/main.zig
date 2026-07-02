const cli = @import("cli.zig");
const compat = @import("compat.zig");

// Zig 0.16 passes std.process.Init to main; 0.15 requires a zero-arg main.
// compat.ProcessInit keeps both signatures valid on both versions.
pub const main = if (compat.is_modern) mainModern else mainLegacy;

fn mainModern(init: compat.ProcessInit) !void {
    try cli.run(init);
}

fn mainLegacy() !void {
    try cli.run({});
}
