const std = @import("std");
const p = @import("../parser.zig");
const e = @import("../types.zig").Error;
const Dir = std.Io.Dir;
const zsys = @import("../libs/zsys/zsys.zig");
const Sha256 = std.crypto.hash.sha2.Sha256;
const Config = @import("../libs/ConfigLib/config.zig").Config;

pub const ErrorConflict = struct { name: []const u8, path: []const u8, err: ?e = null };

pub fn buildSpawnArgv(allocator: std.mem.Allocator, config: Config, name: []const u8, script_path: []const u8) ![]const []const u8 {
    const src_dir = try std.fmt.allocPrint(allocator, "{s}{s}", .{ config.build_dir, name });
    const destdir = try std.fmt.allocPrint(allocator, "{s}{s}", .{ config.pkg_dir, name });
    const jobs = try std.fmt.allocPrint(allocator, "{d}", .{config.jobs});

    var list: std.ArrayList([]const u8) = .empty;
    try list.append(allocator, "env");

    const pairs = [_]struct { k: []const u8, v: []const u8 }{
        .{ .k = "ZP_ROOT", .v = config.root },
        .{ .k = "ZP_SRC_DIR", .v = src_dir },
        .{ .k = "ZP_DESTDIR", .v = destdir },
        .{ .k = "ZP_BUILD_DIR", .v = try std.fmt.allocPrint(allocator, "{s}", .{config.build_dir}) },
        .{ .k = "ZP_PKG_DIR", .v = try std.fmt.allocPrint(allocator, "{s}", .{config.pkg_dir}) },
        .{ .k = "ZP_CACHE_DIR", .v = try std.fmt.allocPrint(allocator, "{s}", .{config.cache_dir}) },
        .{ .k = "ZP_MIRROR_DIR", .v = try std.fmt.allocPrint(allocator, "{s}", .{config.mirror_dir}) },
        .{ .k = "ZP_DB_DIR", .v = try std.fmt.allocPrint(allocator, "{s}", .{config.db_dir}) },
        .{ .k = "ZP_JOBS", .v = jobs },
    };
    for (pairs) |part| {
        try list.append(allocator, try std.fmt.allocPrint(allocator, "{s}={s}", .{ part.k, part.v }));
    }
    try list.append(allocator, "/bin/sh");
    try list.append(allocator, script_path);
    return list.items;
}

pub fn checkConflicts(pkg: []const u8, path: []const u8, allocator: std.mem.Allocator, config: Config) !?ErrorConflict {
    const buf = try std.fmt.allocPrint(allocator, "{s}files.db", .{config.db_dir});
    var file = try zsys.File.openFile(buf, .{ .type = .read, .create = true });
    defer file.close();

    var reader = try file.readMmap();
    defer reader.deinit();

    var data = std.mem.tokenizeScalar(u8, reader.slice(), '\n');
    while (data.next()) |line| {
        var tokens = std.mem.tokenizeScalar(u8, line, ' ');
        const name = tokens.next() orelse continue;
        const path_file = tokens.next() orelse continue;

        if (std.mem.eql(u8, path, path_file)) {
            if (!std.mem.eql(u8, pkg, name)) {
                return .{ .name = try allocator.dupe(u8, name), .path = try allocator.dupe(u8, path_file), .err = e.Conflict };
            }
        }
    }
    return null;
}

pub fn checkHex(src: []const u8, expected_hash: []const u8, allocator: std.mem.Allocator) !bool {
    var hasher = Sha256.init(.{});

    var file = try zsys.File.openFile(src, .{ .type = .read });
    defer file.close();

    var read = try file.readMmap();
    defer read.deinit();

    hasher.update(read.slice());
    const digest = hasher.finalResult();

    const hex: []const u8 = try std.fmt.allocPrint(allocator, "{s}", .{std.fmt.bytesToHex(digest, .lower)});

    return std.mem.eql(u8, hex, expected_hash);
}

pub fn runProcess(io: anytype, argv: []const []const u8, path: []const u8) !void {
    var child = try std.process.spawn(io, .{
        .argv = argv,
        .cwd = .{ .path = path },
        .stdout = .inherit,
        .stderr = .inherit,
        .stdin = .inherit,
    });
    const term = try child.wait(io);
    switch (term) {
        .exited => |code| if (code != 0) return error.ProcessFailed,
        else => return error.ProcessFailed,
    }
}

pub fn createDirPath(io: anytype, base_dir: Dir, path: []const u8) !void {
    var cur: Dir = base_dir;
    var is_base: bool = true;
    var it = std.mem.tokenizeScalar(u8, path, '/');

    while (it.next()) |part| {
        if (part.len == 0) continue;
        cur.createDir(io, part, .default_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
        const next_dir = try cur.openDir(io, part, .{});
        if (!is_base) {
            cur.close(io);
        }
        cur = next_dir;
        is_base = false;
    }
    if (!is_base) {
        cur.close(io);
    }
}

pub fn add(init: std.process.Init, pkg_item: []const u8, allocator: std.mem.Allocator, config: Config) !void {
    const root = try Dir.openDirAbsolute(init.io, "/", .{});
    defer root.close(init.io);
    const packages_db = try std.fmt.allocPrint(allocator, "{s}packages.db", .{config.db_dir});
    const cache_dir = try std.fmt.allocPrint(allocator, "{s}", .{config.cache_dir});
    const pkg = try p.GetPkgStatToInstall(pkg_item, allocator, config);
    const file_name = if (std.mem.lastIndexOfScalar(u8, pkg.url, '/')) |i| pkg.url[i + 1 ..] else pkg.url;

    const installedPkgs = try p.GetInstalledPkgs(allocator, config);

    for (pkg.deps) |dep| {
        var found = false;
        for (installedPkgs.items) |item| {
            if (std.mem.eql(u8, item, dep)) {
                found = true;
                break;
            }
        }
        if (!found) try add(init, dep, allocator, config);
    }

    std.log.info("Installing tar file '{s}'...\n", .{pkg_item});

    const argv = [_][]const u8{ "curl", "-fSL", "-o", file_name, pkg.url };
    try runProcess(init.io, &argv, cache_dir);
    const path_buf: []const u8 = try std.fmt.allocPrint(allocator, "{s}{s}", .{ config.cache_dir, file_name });

    if (config.verify_hash) {
        const check = try checkHex(path_buf, pkg.hash, allocator);
        if (!check) {
            Dir.deleteFileAbsolute(init.io, path_buf) catch |err| switch (err) {
                error.FileNotFound => {},
                else => return err,
            };
            return error.InvalidHash;
        } else {
            std.log.info("hash check: successful\n", .{});
        }
    } else {
        std.log.warn("Check hash: false. Continue...", .{});
    }

    var tar_cmd_buf: [8096]u8 = undefined;

    const build_dir = try std.fmt.allocPrint(allocator, "{s}{s}", .{ config.build_dir, pkg_item });
    try root.deleteTree(init.io, build_dir);

    Dir.createDirAbsolute(init.io, try std.fmt.bufPrint(&tar_cmd_buf, "{s}{s}", .{ config.build_dir, pkg_item }), .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    const tar_cmd = try std.fmt.bufPrint(&tar_cmd_buf, "tar -xf {s}{s} -C {s}{s} --strip-components=1", .{ config.cache_dir, file_name, config.build_dir, pkg_item });
    const argv_tar = [_][]const u8{ "sh", "-c", tar_cmd };
    try runProcess(init.io, &argv_tar, cache_dir);

    var buff: [256]u8 = undefined;
    const src = try std.fmt.bufPrint(&buff, "{s}/zp-repo/pkgs/{s}/BuildFile", .{ config.mirror_dir, pkg_item });
    const argv_build = try buildSpawnArgv(allocator, config, pkg.name, src);
    const src_dir = try std.fmt.allocPrint(allocator, "{s}{s}", .{ config.build_dir, pkg.name });
    std.log.info("Installing '{s}'...\n", .{pkg_item});
    const pkg_bin = try std.fmt.allocPrint(allocator, "{s}{s}", .{ config.pkg_dir, pkg_item });
    defer allocator.free(pkg_bin);
    Dir.createDirAbsolute(init.io, pkg_bin, .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    runProcess(init.io, argv_build, src_dir) catch |err| switch (err) {
        error.ProcessFailed => {
            if (config.keep_build) {
                const massive = [_][]const u8{ path_buf, build_dir };

                inline for (massive) |item| {
                    try root.deleteTree(init.io, item);
                }
                return err;
            }
            return err;
        },
        else => return err,
    };

    var list_path_buf: [256]u8 = undefined;
    const list_path = try std.fmt.bufPrint(&list_path_buf, "{s}{s}.list", .{ config.db_dir, pkg_item });

    try runProcess(init.io, &[_][]const u8{ "sudo", "zp", "__copy", pkg_bin, "/", "", list_path, pkg_item }, ".");

    try runProcess(init.io, &[_][]const u8{ "sudo", "zp", "__removePkgEntry", packages_db, pkg_item }, ".");

    try runProcess(init.io, &[_][]const u8{ "sudo", "zp", "__writeFile", packages_db, pkg_item, pkg.version }, ".");

    try runProcess(init.io, &[_][]const u8{ "sudo", "zp", "__writeFileDb", list_path, pkg_item }, ".");
}
