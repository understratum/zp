const std = @import("std");
const zsys = @import("../libs/zsys/zsys.zig");
const runProcess = @import("add.zig").runProcess;
const removePkgEntry = @import("add.zig").removePkgEntry;

const DB_SEP = '\t';
fn dbPkg(line: []const u8) ?[]const u8 {
    const i = std.mem.indexOfScalar(u8, line, DB_SEP) orelse return null;
    return line[0..i];
}

fn dbPath(line: []const u8) ?[]const u8 {
    const i = std.mem.indexOfScalar(u8, line, DB_SEP) orelse return null;
    return line[i + 1 ..];
}

pub fn remove(init: std.process.Init, pkg_item: []const u8) !void {
    var list_path_buf: [256]u8 = undefined;
    const list_path = try std.fmt.bufPrint(&list_path_buf, "/var/zp/installed/{s}.list", .{pkg_item});
    const cwd = std.Io.Dir.cwd();
    const allocator = init.arena.allocator();
    const list_file = cwd.openFile(init.io, list_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Package '{s}' is not installed\n", .{pkg_item});
            return;
        }
        return err;
    };
    defer list_file.close(init.io);
    var root_dir = try std.Io.Dir.openDirAbsolute(init.io, "/", .{});
    defer root_dir.close(init.io);
    var file_paths: std.ArrayList([]const u8) = .empty;
    defer {
        for (file_paths.items) |path| allocator.free(path);
        file_paths.deinit(allocator);
    }
    var buffer: [4096]u8 = undefined;
    var reader = list_file.reader(init.io, &buffer);

    while (try reader.interface.takeDelimiter('\n')) |line| {
        if (line.len == 0) continue;

        const rel_path = if (std.mem.startsWith(u8, line, "/")) line[1..] else line;
        const path_copy = try allocator.dupe(u8, rel_path);
        try file_paths.append(allocator, path_copy);
        root_dir.deleteFile(init.io, rel_path) catch |err| switch (err) {
            error.FileNotFound => continue,
            error.IsDir => continue,
            else => {
                std.debug.print("Failed to remove {s}: {}\n", .{ rel_path, err });
                continue;
            },
        };
    }

    try removeEmptyDirs(init.io, allocator, file_paths, root_dir);
    try cwd.deleteFile(init.io, list_path);
    var cmd_buf: [4096]u8 = undefined;
    try removePkgEntry(init, "/var/zp/install/packages.db", pkg_item, &cmd_buf);
    try removePkgFromFilesDb(init, "/var/zp/installed/files.db", pkg_item);
    std.debug.print("Package '{s}' removed successfully\n", .{pkg_item});
}

pub fn removeEmptyDirs(io: anytype, allocator: std.mem.Allocator, file_paths: std.ArrayList([]const u8), root_dir: std.Io.Dir) !void {
    var dir_list: std.ArrayList([]const u8) = .empty;
    defer {
        for (dir_list.items) |item| allocator.free(item);
        dir_list.deinit(allocator);
    }

    for (file_paths.items) |rel_path| {
        if (std.fs.path.dirname(rel_path)) |parent| {
            const parent_copy = try allocator.dupe(u8, parent);
            var exists = false;
            for (dir_list.items) |existing| {
                if (std.mem.eql(u8, existing, parent_copy)) {
                    allocator.free(parent_copy);
                    exists = true;
                    break;
                }
            }
            if (!exists) {
                try dir_list.append(allocator, parent_copy);
            }
        }
    }
    std.mem.sort([]const u8, dir_list.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.count(u8, a, "/") > std.mem.count(u8, b, "/");
        }
    }.lessThan);
    for (dir_list.items) |dir_path| {
        root_dir.deleteDir(io, dir_path) catch |err| switch (err) {
            error.DirNotEmpty => continue,
            error.FileNotFound => continue,
            else => {
                std.debug.print("Failed to remove dir {s}: {}", .{ dir_path, err });
                continue;
            },
        };
    }
}

fn removePkgFromFilesDb(init: std.process.Init, file: []const u8, pkg: []const u8) !void {
    var file_ = try zsys.File.openFile(file, .{ .type = .read, .create = true });
    defer file_.close();

    var db = try file_.readMmap();
    defer db.deinit();

    const tmp_path = "/var/zp/installed/files.db.tmp";
    const tmp_file = try std.Io.Dir.createFileAbsolute(init.io, tmp_path, .{ .truncate = true });
    defer tmp_file.close(init.io);

    var kept: usize = 0;
    var dropped: usize = 0;
    var pos: u64 = 0;

    var it = std.mem.tokenizeScalar(u8, db.slice(), '\n');
    while (it.next()) |line| {
        if (line.len == 0) continue;

        const name = dbPkg(line) orelse {
            std.log.warn("files.db: строка без разделителя, оставляю: {s}", .{line});
            kept += 1;
            continue;
        };

        if (std.mem.eql(u8, name, pkg)) {
            dropped += 1;
            continue;
        }

        var line_buf: [4096]u8 = undefined;
        const out_line = try std.fmt.bufPrint(&line_buf, "{s}\n", .{line});
        _ = try tmp_file.writePositionalAll(init.io, out_line, pos);
        pos += out_line.len;
        kept += 1;
    }

    try std.Io.Dir.renameAbsolute(tmp_path, file, init.io);
}
