const std = @import("std");
const p = @import("../parser.zig");

pub fn search(init: std.process.Init, pkg_item: []const u8, allocator: std.mem.Allocator) !std.ArrayList([*:0]const u8) {
    const file = try std.Io.Dir.openFileAbsolute(init.io, "/var/zp/mirrors/zp.packages", .{});
    defer file.close(init.io);
    var massive: std.ArrayList([*:0]const u8) = .empty;

    var buffer: [8192]u8 = undefined;
    var reader = file.reader(init.io, &buffer);

    while (try reader.interface.takeDelimiter('\n')) |line| {
        if (line.len == 0) continue;
        var tokens = std.mem.tokenizeScalar(u8, line, ' ');
        const name = tokens.next() orelse continue;

        if (std.mem.indexOf(u8, name, pkg_item)) |_| {
            const name_new = try toNullTerminated(allocator, name);
            try massive.append(allocator, name_new);
        }
    }

    return massive;
}

pub fn toNullTerminated(allocator: std.mem.Allocator, slice: []const u8) ![*:0]const u8 {
    const buf = try allocator.allocSentinel(u8, slice.len, 0);
    @memcpy(buf[0..slice.len], slice);
    return buf;
}
