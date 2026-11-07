const std = @import("std");
const zsys = @import("../libs/zsys/zsys.zig");
const Config = @import("../libs/ConfigLib/config.zig").Config;
const Dir = std.Io.Dir;

pub fn removePkgEntry(init: std.process.Init, file: []const u8, pkg: []const u8, config: Config) !void {
    var open_file = zsys.File.openFile(file, .{ .type = .read_write, .lock = .exclusive, .create = true }) catch return;
    defer open_file.close();

    var reader = try open_file.readMmap();
    defer reader.deinit();
    const tmp_path = try std.fmt.allocPrint(init.arena.allocator(), "{s}packages.db.tmp", .{config.db_dir});
    var tmp_file = try zsys.File.openFile(tmp_path, .{ .create = true, .type = .read_write });
    defer tmp_file.close();
    var data = std.mem.tokenizeScalar(u8, reader.slice(), '\n');

    while (data.next()) |line| {
        if (line.len == 0) continue;
        var tokens = std.mem.tokenizeScalar(u8, line, ' ');
        const name = tokens.next() orelse continue;
        if (std.mem.eql(u8, name, pkg)) continue;

        var line_buf: [168]u8 = undefined;
        const line_with_newline = try std.fmt.bufPrint(&line_buf, "{s}\n", .{line});
        _ = try tmp_file.writeFile(line_with_newline);
    }

    try Dir.renameAbsolute(tmp_path, file, init.io);
}
