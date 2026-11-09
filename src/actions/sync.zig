const std = @import("std");
const Dir = std.Io.Dir;
const runProcess = @import("add.zig").runProcess;
const zsys = @import("../libs/zsys/zsys.zig");
const Config = @import("../libs/ConfigLib/config.zig").Config;

fn ensureDir(io: anytype, path: []const u8) !void {
    const dir = Dir.cwd();
    var buf: [4096]u8 = undefined;
    var len: usize = if (path.len > 0 and path[0] == '/') 1 else 0;
    if (len == 1) buf[0] = '/';
    var it = std.mem.tokenizeScalar(u8, path, '/');
    while (it.next()) |part| {
        if (len > 1) {
            if (len + 1 + part.len > buf.len) return error.NameTooLong;
            buf[len] = '/';
            len += 1;
        } else if (part.len > buf.len) {
            return error.NameTooLong;
        }
        @memcpy(buf[len..][0..part.len], part);
        len += part.len;

        dir.createDir(io, buf[0..len], .default_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }
}

fn absSub(buf: []u8, root: []const u8, sub: []const u8) ![]const u8 {
    return std.fmt.bufPrint(buf, "{s}/{s}", .{
        std.mem.trimEnd(u8, root, "/"),
        std.mem.trimEnd(u8, sub, "/"),
    });
}

pub fn createDirectories(io: anytype, root: []const u8, config: Config) !void {
    try ensureDir(io, root);
    try ensureDir(io, config.db_dir);
    try ensureDir(io, config.mirror_dir);
    const subs = [_][]const u8{ config.build_dir, config.cache_dir, config.pkg_dir };
    for (subs) |sub| try ensureDir(io, sub);
}

pub fn init(io: anytype, allocator: std.mem.Allocator, config: Config) !void {
    try createDirectories(io, config.root, config);
    var files_db = try zsys.File.openFile(try std.fmt.allocPrint(allocator, "{s}files.db", .{config.db_dir}), .{ .create = true });
    defer files_db.close();
    var packagesdb = try zsys.File.openFile(try std.fmt.allocPrint(allocator, "{s}packages.db", .{config.db_dir}), .{ .create = true });
    defer packagesdb.close();
}

pub fn sync(io: anytype, allocator: std.mem.Allocator, config: Config) !void {
    std.debug.print("Initializing zp...\n", .{});

    try init(io, allocator, config);

    const REPO_URL: []const u8 = "https://github.com/understratum/zp-repo.git";
    const repo_path = try std.fmt.allocPrint(allocator, "{s}zp-repo", .{config.mirror_dir});
    std.Io.Dir.accessAbsolute(io, repo_path, .{}) catch |err| switch (err) {
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
