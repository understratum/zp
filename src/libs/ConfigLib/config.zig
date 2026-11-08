const std = @import("std");
const zsys = @import("../zsys/zsys.zig");

pub const Config = struct {
    root: []const u8 = "",
    db_dir: []const u8 = "/var/zp/installed",
    pkg_dir: []const u8 = ".local/zp/pkg",
    build_dir: []const u8 = ".local/zp/build",
    mirror_dir: []const u8 = "/var/zp/mirrors",
    cache_dir: []const u8 = ".local/zp/install",
    keep_build: bool = false,
    verify_hash: bool = true,
    jobs: usize = 1,

    pub fn parseConfig(allocator: std.mem.Allocator, src: [:0]const u8) !Config {
        var diag: std.zon.parse.Diagnostics = .{ .errors = &.{} };
        return std.zon.parse.fromSlice(Config, .{ .gpa = allocator, .arena = allocator, .source = src, .ignore_unknown_fields = true, .diagnostics = &diag }) catch |err| switch (err) {
            error.ParseZon => {
                std.log.warn("Failed to parse config.zon. Use standart config...", .{});
                return Config{};
            },
            else => return err,
        };
    }

    pub fn configApply(init: std.process.Init, allocator: std.mem.Allocator) !Config {
        const home = init.minimal.environ.getPosix("HOME") orelse return error.HomeNotSet;
        var cfg: Config = blk: {
            const data = zsys.File.readPath("/etc/zp/config.zon", allocator) catch |e| switch (e) {
                error.FileNotFound => break :blk Config{},
                else => return e,
            };
            defer allocator.free(data);
            if (data.len == 0) {
                break :blk Config{};
            }
            const ds = try allocator.dupeSentinel(u8, data, 0);
            break :blk try parseConfig(allocator, ds);
        };

        const root_raw = if (cfg.root.len > 0) cfg.root else home;
        cfg.root = try fixPath(root_raw, allocator);
        cfg.db_dir = try std.fmt.allocPrint(allocator, "{s}", .{try fixPath(cfg.db_dir, allocator)});
        cfg.pkg_dir = try std.fmt.allocPrint(allocator, "{s}{s}", .{ cfg.root, try fixPath(cfg.pkg_dir, allocator) });
        cfg.build_dir = try std.fmt.allocPrint(allocator, "{s}{s}", .{ cfg.root, try fixPath(cfg.build_dir, allocator) });
        cfg.mirror_dir = try std.fmt.allocPrint(allocator, "{s}", .{try fixPath(cfg.mirror_dir, allocator)});
        cfg.cache_dir = try std.fmt.allocPrint(allocator, "{s}{s}", .{ cfg.root, try fixPath(cfg.cache_dir, allocator) });

        return cfg;
    }

    pub fn fixPath(path: []const u8, allocator: std.mem.Allocator) ![]const u8 {
        if (!std.mem.eql(u8, path, "/")) {
            if (!std.mem.endsWith(u8, path, "/")) {
                const new_path = try std.fmt.allocPrint(allocator, "{s}/", .{path});
                return new_path;
            }
        }
        return try std.fmt.allocPrint(allocator, "{s}", .{path});
    }
};
