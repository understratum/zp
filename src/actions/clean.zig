const std = @import("std");
const zsys = @import("../libs/zsys/zsys.zig");
const Config = @import("../libs/ConfigLib/config.zig").Config;

pub fn clean(config: Config) !void {
    const dir = try zsys.Dir.open(config.cache_dir, .{ .type = .read, .iterate = true });
    defer dir.close();

    var iterator = dir.iterate();

    while (try iterator.next()) |entry| {
        switch (entry.kind) {
            .file => try dir.deleteFile(entry.name),
            else => continue,
        }
    }

    std.debug.print("Done.\n", .{});
}
