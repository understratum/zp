const std = @import("std");
const zsys = @import("../libs/zsys/zsys.zig");
const Dir = std.Io.Dir;
const Config = @import("../libs/ConfigLib/config.zig").Config;
const checkConflicts = @import("add.zig").checkConflicts;
const createDirPath = @import("add.zig").createDirPath;

pub fn copy(io: anytype, allocator: std.mem.Allocator, src_dir: []const u8, dest_dir: []const u8, dest_path_prefix: []const u8, list_file: []const u8, pkg: []const u8, config: Config) !void {
    const src = try Dir.openDirAbsolute(io, src_dir, .{ .iterate = true });
    defer src.close(io);
    const dest = try Dir.openDirAbsolute(io, dest_dir, .{});
    defer dest.close(io);
    var list = try zsys.File.openFile(list_file, .{ .trunc = true, .type = .read_write, .create = true, .append = true });
    defer list.close();
    var walker = try src.walk(allocator);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        const dest_path = if (dest_path_prefix.len == 0 or std.mem.eql(u8, dest_path_prefix, "."))
            entry.path
        else
            try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dest_path_prefix, entry.path });

        const abs_path = try std.fmt.allocPrint(allocator, "/{s}", .{dest_path});

        switch (entry.kind) {
            .file => {
                if (try checkConflicts(pkg, abs_path, allocator, config)) |c| {
                    std.debug.print("Path conflict found at {s} (package {s}); Resolve it yourself to continue the installation process.\n", .{ c.path, c.name });
                    return error.Conflict;
                }
                try entry.dir.copyFile(entry.basename, dest, dest_path, io, .{});

                const line = try std.fmt.allocPrint(allocator, "{s}\n", .{abs_path});
                try list.writeFile(line);
                try list.syncData();
            },
            .directory => try createDirPath(io, dest, dest_path),
            .sym_link => {
                var target_buf: [4096]u8 = undefined;
                const len = try entry.dir.readLink(io, entry.basename, &target_buf);

                if (try checkConflicts(pkg, abs_path, allocator, config)) |c| {
                    std.debug.print("Path conflict found at {s} (package {s}); Resolve it yourself to continue the installation process.\n", .{ c.path, c.name });
                    return error.Conflict;
                }

                dest.deleteFile(io, dest_path) catch {};
                try dest.symLink(io, target_buf[0..len], dest_path, .{});

                const line = try std.fmt.allocPrint(allocator, "{s}\n", .{abs_path});
                try list.writeFile(line);
                try list.syncData();
            },
            else => continue,
        }
    }
}
