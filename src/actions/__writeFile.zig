const std = @import("std");
const zsys = @import("../libs/zsys/zsys.zig");
const Config = @import("../libs/ConfigLib/config.zig").Config;
const Dir = std.Io.Dir;
const removePkgEntry = @import("__removePkgEntry.zig").removePkgEntry;

pub fn writeFile(init: std.process.Init, file: []const u8, pkg: []const u8, version: []const u8, config: Config) !void {
    try removePkgEntry(init, file, pkg, config);
    const clean_version = std.mem.trim(u8, version, "\n\r ");
    var open_file = try zsys.File.openFile(file, .{ .append = true, .create = true, .type = .read_write, .lock = .exclusive });
    defer open_file.close();

    const name_version = try std.fmt.allocPrint(init.arena.allocator(), "{s} {s}\n", .{ pkg, clean_version });
    try open_file.writeFile(name_version);
}
