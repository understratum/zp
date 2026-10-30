const std = @import("std");
const Dir = std.Io.Dir;
const runProcess = @import("add.zig").runProcess;
const zsys = @import("../libs/zsys/zsys.zig");

pub fn createDirectories(io: anytype, root: []const u8) !void {
    var path_buf: [256]u8 = undefined;
    const dir = Dir.cwd();

    var path_len: usize = if (root[0] == '/') 1 else 0;
    if (path_len == 1) path_buf[0] = '/';
    var parts = std.mem.tokenizeScalar(u8, root, '/');
    while (parts.next()) |part| {
        if (path_len > 1) {
            path_buf[path_len] = '/';
            path_len += 1;
        }
        @memcpy(path_buf[path_len..][0..part.len], part);
        path_len += part.len;
        const path = path_buf[0..path_len];
        dir.createDir(io, path, .default_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }

    for ([_][]const u8{ "build", "install", "mirrors", "pkg" }) |part| {
        const path = try std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ root, part });
        dir.createDir(io, path, .default_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }
}

pub fn init(io: anytype) !void {
    std.debug.print("Initializing zp...\n", .{});

    try createDirectories(io, "/var/zp");
    var files_db = try zsys.File.openFile("/var/zp/installed/files.db", .{ .create = true });
    defer files_db.close();
    var packagesdb = try zsys.File.openFile("/var/zp/install/packages.db", .{ .create = true });
    defer packagesdb.close();

    const REPO_URL: []const u8 = "https://github.com/understratum/zp-repo.git";
    const repo_path = "/var/zp/mirrors/zp-repo";
    std.Io.Dir.accessAbsolute(io, "/var/zp/mirrors/zp-repo", .{}) catch |err| switch (err) {
        error.FileNotFound => {
            const argv = [_][]const u8{ "git", "clone", "--depth", "1", REPO_URL, repo_path };
            try runProcess(io, &argv, ".");
        },
        else => return err,
    };

    const argv = [_][]const u8{ "git", "-C", repo_path, "pull", "--ff-only" };
    try runProcess(io, &argv, ".");

    std.debug.print("Update successfull\n", .{});
}

test "createDirectories creates nested init paths" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [256]u8 = undefined;
    const root = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}/var/zp", .{tmp.sub_path});

    try createDirectories(io, root);
    try createDirectories(io, root);

    var root_dir = try Dir.cwd().openDir(io, root, .{});
    defer root_dir.close(io);

    for ([_][]const u8{ "build", "install", "mirrors", "pkg" }) |path| {
        var child = try root_dir.openDir(io, path, .{});
        child.close(io);
    }
}
