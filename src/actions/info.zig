const std = @import("std");
const p = @import("../parser.zig");
const Config = @import("../libs/ConfigLib/config.zig").Config;

pub fn info(pkg: []const u8, allocator: std.mem.Allocator, config: Config) !void {
    const stat = try p.GetPkgStatToInstall(pkg, allocator, config);
    const deps: []const u8 = try std.mem.join(allocator, ", ", stat.deps);
    std.debug.print("Name: {s}\nVersion: {s}\nLicense: {s}\nURL: {s}\nhash: {s}\nDeps: {s}\n", .{ stat.name, stat.version, stat.license, stat.url, stat.hash, deps });
}
