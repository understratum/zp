const std = @import("std");

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
