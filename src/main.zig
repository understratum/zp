const std = @import("std");
const initialize = @import("actions/sync.zig");
const help = @import("actions/help.zig").help;
const version = @import("actions/version.zig").version;
const add = @import("actions/add.zig").add;
const remove = @import("actions/remove.zig").remove;
const u = @import("actions/update.zig");
const list = @import("actions/list.zig").list;
const search = @import("actions/search.zig").search;
const info = @import("actions/info.zig").info;
const copy = @import("actions/__copy.zig").copy;
const writeFile = @import("actions/__writeFile.zig").writeFile;
const removePkgEntry = @import("actions/__removePkgEntry.zig").removePkgEntry;
const writeFileDb = @import("actions/__writeFileDb.zig").writeFileDb;
const Config = @import("libs/ConfigLib/config.zig").Config;
const StrList = std.ArrayList([]const u8);

const Action = enum { help, version, add, remove, sync, update, list, search, info, __copy, __writeFile, __removePkgEntry, __writeFileDb };

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    var args = try init.minimal.args.toSlice(allocator);
    var pkgs: StrList = .empty;
    var flags: StrList = .empty;

    defer pkgs.deinit(allocator);
    defer flags.deinit(allocator);

    var strAction: ?[]const u8 = null;

    for (args[1..]) |arg| {
        if (std.mem.startsWith(u8, arg, "-")) {
            try flags.append(allocator, arg);
        } else {
            if (strAction == null) {
                strAction = arg;
            } else {
                try pkgs.append(allocator, arg);
            }
        }
    }
    const config = try Config.configApply(init, allocator);

    const action = std.meta.stringToEnum(Action, strAction orelse "") orelse .help;

    switch (action) {
        .help => help(),
        .version => version(),
        .add => if (pkgs.items.len == 0) {
            std.log.err("Package unspecified", .{});
            help();
        } else {
            const ThreadResult = struct {
                err: ?anyerror,
            };
            const results = try allocator.alloc(ThreadResult, pkgs.items.len);
            for (results) |*r| r.* = .{ .err = null };

            var threads = try allocator.alloc(std.Thread, pkgs.items.len);

            for (pkgs.items, 0..) |pkg, i| {
                threads[i] = try std.Thread.spawn(.{}, struct {
                    fn run(index: usize, init_: std.process.Init, pkg_: []const u8, allocator_: std.mem.Allocator, config_: Config, results_: []ThreadResult) void {
                        add(init_, pkg_, allocator_, config_) catch |err| {
                            results_[index].err = err;
                        };
                    }
                }.run, .{ i, init, pkg, allocator, config, results });
            }

            for (threads) |t| {
                t.join();
            }

            for (pkgs.items, results) |pkg, r| {
                if (r.err) |err| {
                    std.log.err("failed to add {s}: {}", .{ pkg, err });
                }
            }
        },
        .remove => for (pkgs.items) |pkg| {
            try remove(init, pkg, config);
        },
        .sync => _ = try initialize.sync(init.io, allocator, config),
        .update => if (pkgs.items.len == 0) {
            try u.updateAll(init, config);
        } else {
            for (pkgs.items) |pkg| {
                try u.updatePkg(init, pkg, allocator, config);
            }
        },
        .list => try list(allocator, config),
        .search => for (pkgs.items) |pkg| {
            var result = try search(pkg, allocator, config);
            defer result.deinit(allocator);

            for (result.items) |item| {
                std.debug.print("{s}\n", .{item});
            }
        },
        .info => {
            for (pkgs.items) |item| {
                try info(item, allocator, config);
            }
        },
        .__copy => {
            try copy(init.io, allocator, args[2], args[3], args[4], args[5], args[6], config);
        },
        .__writeFile => {
            try writeFile(init, args[2], args[3], args[4], config);
        },
        .__removePkgEntry => {
            try removePkgEntry(init, args[2], args[3], config);
        },
        .__writeFileDb => {
            try writeFileDb(init, args[2], args[3], allocator, config);
        },
    }
}
