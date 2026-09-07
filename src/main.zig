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
            var threads = try allocator.alloc(std.Thread, pkgs.items.len);

            for (pkgs.items, 0..) |pkg, i| {
                // try add(init, pkg, allocator);
                threads[i] = try std.Thread.spawn(.{}, add, .{ init, pkg, allocator });
            }

            for (threads) |t| {
                t.join();
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
            try search(init, pkg);
        },
    }
}
