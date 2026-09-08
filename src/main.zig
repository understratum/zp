const std = @import("std");
const initialize = @import("actions/sync.zig").init;
const help = @import("actions/help.zig").help;
const version = @import("actions/version.zig").version;
const add = @import("actions/add.zig").add;
const remove = @import("actions/remove.zig").remove;
const u = @import("actions/update.zig");
const list = @import("actions/list.zig").list;
const search = @import("actions/search.zig").search;
const StrList = std.ArrayList([]const u8);
const linux = std.os.linux;

const Action = enum {
    help,
    version,
    add,
    remove,
    sync,
    update,
    list,
    search,
};

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
                    fn run(index: usize, init_: std.process.Init, pkg_: []const u8, allocator_: std.mem.Allocator, results_: []ThreadResult) void {
                        add(init_, pkg_, allocator_) catch |err| {
                            results_[index].err = err;
                        };
                    }
                }.run, .{ i, init, pkg, allocator, results });
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
            try remove(init, pkg);
        },
        .sync => _ = try initialize(init.io, allocator),
        .update => if (pkgs.items.len == 0) {
            try u.updateAll(init);
        } else {
            for (pkgs.items) |pkg| {
                try u.updatePkg(init, pkg, allocator);
            }
        },
        .list => try list(allocator),
        .search => for (pkgs.items) |pkg| {
            var result = try search(init, pkg, allocator);
            defer result.deinit(allocator);

            for (result.items) |item| {
                const item_len: []const u8 = std.mem.span(item);
                _ = linux.write(1, item, item_len.len);
                _ = linux.write(1, "\n", 1);
            }
        },
    }
}
