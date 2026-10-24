const std = @import("std");
const e = @import("types.zig").Error;
const Dir = std.Io.Dir;
const linux = std.os.linux;
const zsys = @import("libs/zsys/zsys.zig");
const Pkg = @import("types.zig").Pkg;

pub const PkgStat = struct { name: []const u8, version: ?[]const u8 };

pub fn parsePkg(allocator: std.mem.Allocator, src: [:0]const u8) !Pkg {
    var diag: std.zon.parse.Diagnostics = .{ .errors = &.{} };

    return try std.zon.parse.fromSlice(Pkg, .{ .gpa = allocator, .arena = allocator, .source = src, .ignore_unknown_fields = true, .diagnostics = &diag });
}

pub fn GetPkgStatToInstall(pkg: []const u8, allocator: std.mem.Allocator) !Pkg {
    const buf = try std.fmt.allocPrint(allocator, "/var/zp/mirrors/zp-repo/pkgs/{s}/{s}.zon", .{ pkg, pkg });
    defer allocator.free(buf);

    var file = try zsys.File.openFile(buf, .{ .type = .read });
    defer file.close();

    const data = try file.read(allocator);
    const data_sentinel: [:0]const u8 = try allocator.dupeSentinel(u8, data, 0);

    const parsing = try parsePkg(allocator, data_sentinel);
    if (std.mem.eql(u8, parsing.name, pkg)) {
        return .{ .name = parsing.name, .version = parsing.version, .url = parsing.url, .license = parsing.license, .hash = parsing.hash, .deps = parsing.deps };
    }
    return e.PkgNotFound;
}

pub fn getInstalledVersion(pkg: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    var file = try zsys.File.openFile("/var/zp/install/packages.db", .{ .type = .read, .create = true });
    defer file.close();
    const data = try file.read(allocator);

    var reader = std.mem.tokenizeScalar(u8, data, '\n');
    while (reader.next()) |line| {
        var tokens = std.mem.tokenizeScalar(u8, line, ' ');
        const name = tokens.next() orelse continue;
        if (!std.mem.eql(u8, name, pkg)) continue;
        const version = tokens.next() orelse return null;
        return try allocator.dupe(u8, version);
    }
    return null;
}

pub fn GetPkgsStatInstalled(pkg: []const u8, allocator: std.mem.Allocator) !PkgStat {
    var fd = try zsys.File.openFile("/var/zp/install/packages.db", .{ .type = .read, .create = true });
    defer fd.close();

    const data = try fd.read(allocator);

    var reader = std.mem.tokenizeScalar(u8, data, '\n');
    while (reader.next()) |line| {
        var tokens = std.mem.tokenizeScalar(u8, line, ' ');
        const name = tokens.next() orelse continue;
        if (std.mem.eql(u8, name, pkg)) {
            const version = tokens.next() orelse null;
            return .{ .name = name, .version = version };
        }
    }
    return e.PkgNotFound;
}

pub fn GetInstalledPkgs(allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
    var file = try zsys.File.openFile("/var/zp/install/packages.db", .{ .type = .read, .create = true });
    defer file.close();

    const data = try file.read(allocator);

    var massive: std.ArrayList([]const u8) = .empty;
    var reader = std.mem.tokenizeScalar(u8, data, '\n');
    while (reader.next()) |line| {
        var tokens = std.mem.tokenizeScalar(u8, line, ' ');
        const name = tokens.next() orelse continue;
        try massive.append(allocator, try allocator.dupe(u8, name));
    }
    return massive;
}
