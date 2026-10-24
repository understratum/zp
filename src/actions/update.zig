const std = @import("std");
const p = @import("../parser.zig");
const a = @import("add.zig");
const linux = std.os.linux;
const zsys = @import("../libs/zsys/zsys.zig");

pub fn updatePkg(init: std.process.Init, pkg_name: []const u8, allocator: std.mem.Allocator) !void {
    const installed = try p.GetPkgsStatInstalled(pkg_name, allocator);

    if (installed.version) |iv| {
        const pkg = try p.GetPkgStatToInstall(pkg_name, allocator);

        defer {
            allocator.free(pkg.name);
            allocator.free(pkg.version);
            allocator.free(pkg.url);
        }

        if (!std.mem.eql(u8, iv, pkg.version)) {
            std.log.info("Updating {s}: {s} → {s}\n", .{ pkg_name, iv, pkg.version });
            try a.add(init, pkg_name, allocator);
        } else {
            std.debug.print("{s} is up to date ({s})\n", .{ pkg_name, iv });
        }
    } else {
        std.debug.print("Package '{s}' is not installed\n", .{pkg_name});
    }
}

pub fn updateAll(init: std.process.Init) !void {
    var fd = try zsys.File.openFile("/var/zp/install/packages.db", .{ .type = .read });
    defer fd.close();

    const content = try fd.read(init.arena.allocator());

    var reader = std.mem.tokenizeScalar(u8, content, '\n');
    while (reader.next()) |line| {
        var tokens = std.mem.tokenizeScalar(u8, line, ' ');
        const name = tokens.next() orelse continue;
        try updatePkg(init, name, init.arena.allocator());
    }
}

// update == upgrade
