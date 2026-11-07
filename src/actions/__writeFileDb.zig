const std = @import("std");
const Config = @import("../libs/ConfigLib/config.zig").Config;
const zsys = @import("../libs/zsys/zsys.zig");
const Dir = std.Io.Dir;

pub fn writeFileDb(init: std.process.Init, list_path: []const u8, pkg: []const u8, allocator: std.mem.Allocator, config: Config) !void {
    const buf = try std.fmt.allocPrint(allocator, "{s}files.db", .{config.db_dir});
    var list_file = try zsys.File.openFile(list_path, .{ .type = .read });
    defer list_file.close();

    var list_data = try list_file.readMmap();
    defer list_data.deinit();
    var db_file = try zsys.File.openFile(buf, .{ .type = .read, .create = true });
    defer db_file.close();
    var db_data = try db_file.readMmap();
    defer db_data.deinit();

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    var old = std.mem.tokenizeScalar(u8, db_data.slice(), '\n');
    while (old.next()) |line| {
        if (line.len == 0) continue;
        const tab = std.mem.indexOfScalar(u8, line, '\t') orelse continue;
        if (std.mem.eql(u8, line[0..tab], pkg)) continue;
        try out.appendSlice(allocator, line);
        try out.append(allocator, '\n');
    }
    var fresh = std.mem.tokenizeScalar(u8, list_data.slice(), '\n');
    while (fresh.next()) |path| {
        if (path.len == 0) continue;
        try out.print(allocator, "{s}\t{s}\n", .{ pkg, path });
    }
    const tmp_path = try std.fmt.allocPrint(allocator, "{s}files.db.tmp", .{config.db_dir});
    const tmp_file = try Dir.createFileAbsolute(init.io, tmp_path, .{ .truncate = true });
    defer tmp_file.close(init.io);
    const st = try tmp_file.stat(init.io);
    _ = try tmp_file.writePositionalAll(init.io, out.items, st.size);

    try Dir.renameAbsolute(tmp_path, buf, init.io);
}
