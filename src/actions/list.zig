const std = @import("std");
const p = @import("../parser.zig");
const Config = @import("../libs/ConfigLib/config.zig").Config;

pub fn list(allocator: std.mem.Allocator, config: Config) !void {
    var massive: std.ArrayList([]const u8) = try p.GetInstalledPkgs(allocator, config);

    defer {
        for (massive.items) |i| {
            allocator.free(i);
        }
        massive.deinit(allocator);
    }

    if (massive.items.len == 0) {
        std.debug.print("No pkgs installed.\n", .{});
    } else {
        for (massive.items) |i| {
            std.debug.print("{s}\n", .{i});
        }
    }
}
