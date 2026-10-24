const std = @import("std");
const p = @import("../parser.zig");
const zsys = @import("../libs/zsys/zsys.zig");

pub fn search(pkg_item: []const u8, allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
    var dir = try zsys.Dir.open("/var/zp/mirrors/zp-repo/pkgs/", .{ .type = .read, .iterate = true });
    defer dir.close();

    var massive: std.ArrayList([]const u8) = .empty;
    var iterate = dir.iterate();

    while (try iterate.next()) |entry| {
        switch (entry.kind) {
            .directory => {
                if (std.mem.indexOf(u8, entry.name, pkg_item)) |_| {
                    try massive.append(allocator, entry.name);
                }
            },
            else => {},
        }
    }

    return massive;
}
