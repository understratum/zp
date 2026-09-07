const std = @import("std");
const Dir = std.Io.Dir;
const runProcess = @import("add.zig").runProcess;

pub fn createDirectories(io: anytype, root: []const u8) !void {
    var path_buf: [256]u8 = undefined;
    const dir = Dir.cwd();

    var path_len: usize = if (root[0] == '/') 1 else 0;
    if (path_len == 1) path_buf[0] = '/';
    var parts = std.mem.tokenizeScalar(u8, root, '/');
    while (parts.next()) |part| {
        if (path_len > 1) {
            path_buf[path_len] = '/';
            path_len += 1;
        }
        @memcpy(path_buf[path_len..][0..part.len], part);
        path_len += part.len;
        const path = path_buf[0..path_len];
        dir.createDir(io, path, .default_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }

    for ([_][]const u8{ "build", "install", "mirrors", "pkg" }) |part| {
        const path = try std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ root, part });
        dir.createDir(io, path, .default_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }
}

pub fn init(io: anytype, allocator: std.mem.Allocator) !void {
    std.debug.print("Initializing zp...\n", .{});

    var massive: std.ArrayList([]const u8) = .empty;
    defer massive.deinit(allocator);

    try createDirectories(io, "/var/zp");

    const VOID_URL: []const u8 = "https://github.com/void-linux/void-packages";
    std.Io.Dir.accessAbsolute(io, "/var/zp/mirrors/tree/.git", .{}) catch |err| switch (err) {
        error.FileNotFound => {
            const argv = [_][]const u8{ "git", "clone", "--depth", "1", VOID_URL, "/var/zp/mirrors/tree" };
            try runProcess(io, &argv, ".");
        },
        else => {
            const argv = [_][]const u8{ "sh", "-c", "git -C /var/zp/mirrors/tree pull --ff-only >/dev/null 2>&1" };
            try runProcess(io, &argv, ".");
        },
    };

    const data = try Dir.openDirAbsolute(io, "/var/zp/mirrors/tree/srcpkgs", .{ .iterate = true });
    defer data.close(io);

    var reader = data.iterate();
    while (try reader.next(io)) |target| {
        if (target.kind != .directory) continue;

        const path = try std.fmt.allocPrint(allocator, "/var/zp/mirrors/tree/srcpkgs/{s}/template", .{target.name});
        defer allocator.free(path);

        const file_template = Dir.openFileAbsolute(io, path, .{}) catch continue;
        defer file_template.close(io);

        var buffer: [8192]u8 = undefined;
        var reader_template = file_template.reader(io, &buffer);
        var vars: std.StringHashMap([]const u8) = .init(allocator);
        defer vars.deinit();

        while (try reader_template.interface.takeDelimiter('\n')) |line| {
            if (line.len == 0 or line[0] == '#') continue;
            const first = line[0];
            if (!std.ascii.isAlphabetic(first) and first != '_') continue;
            const eq_pos = std.mem.indexOfScalar(u8, line, '=') orelse continue;

            const key = line[0..eq_pos];
            var value = line[eq_pos + 1 ..];
            if (value.len >= 2) {
                if ((value[0] == '"' and value[value.len - 1] == '"') or (value[0] == '\'' and value[value.len - 1] == '\'')) {
                    value = value[1 .. value.len - 1];
                }
            }

            try vars.put(key, value);
        }
        const pkgname = vars.get("pkgname") orelse target.name;
        const version = vars.get("version") orelse continue;
        const distfiles = vars.get("distfiles") orelse continue;
        var url = try allocator.dupe(u8, distfiles);
        defer allocator.free(url);
        for (0..3) |_| {
            var iter = vars.iterator();
            while (iter.next()) |entry| {
                const var_name = entry.key_ptr.*;
                const var_value = entry.value_ptr.*;
                const value1 = try std.fmt.allocPrint(allocator, "${{{s}}}", .{var_name});
                defer allocator.free(value1);

                url = try replaceAll(allocator, url, value1, var_value);
                const value2 = try std.fmt.allocPrint(allocator, "${s}", .{var_name});
                defer allocator.free(value2);

                url = try replaceAll(allocator, url, value2, var_value);
            }
        }
        if (std.mem.indexOfScalar(u8, url, '$') != null) continue;
        if (std.mem.indexOfScalar(u8, url, '{') != null) continue;
        if (std.mem.indexOfScalar(u8, url, '}') != null) continue;
        if (std.mem.indexOfScalar(u8, url, '>') != null) continue;
        if (!std.mem.startsWith(u8, url, "http://") and !std.mem.startsWith(u8, url, "https://")) continue;
        const line_out = try std.fmt.allocPrint(allocator, "{s} {s} {s}\n", .{ pkgname, version, url });
        try massive.append(allocator, line_out);
    }
    const file_zp = try Dir.createFileAbsolute(io, "/var/zp/mirrors/zp.packages", .{});
    defer file_zp.close(io);

    var write_pos: u64 = 0;
    for (massive.items) |item| {
        try file_zp.writePositionalAll(io, item, write_pos);
        write_pos += item.len;
    }

    const pkgs = try Dir.createFileAbsolute(io, "/var/zp/install/packages.db", .{});
    defer pkgs.close(io);

    std.debug.print("Done. Packages: {}\n", .{massive.items.len});
}

fn replaceAll(allocator: std.mem.Allocator, stack_const: []const u8, needle: []const u8, replace_path: []const u8) ![]u8 {
    if (std.mem.indexOf(u8, stack_const, needle) == null) {
        const result = try allocator.dupe(u8, stack_const);
        allocator.free(stack_const);
        return result;
    }
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);
    var i: usize = 0;
    while (i < stack_const.len) {
        if (i + needle.len <= stack_const.len and std.mem.eql(u8, stack_const[i .. i + needle.len], needle)) {
            try result.appendSlice(allocator, replace_path);
            i += needle.len;
        } else {
            try result.append(allocator, stack_const[i]);
            i += 1;
        }
    }
    allocator.free(stack_const);
    return try result.toOwnedSlice(allocator);
}

test "createDirectories creates nested init paths" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [256]u8 = undefined;
    const root = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}/var/zp", .{tmp.sub_path});

    try createDirectories(io, root);
    try createDirectories(io, root);

    var root_dir = try Dir.cwd().openDir(io, root, .{});
    defer root_dir.close(io);

    for ([_][]const u8{ "build", "install", "mirrors", "pkg" }) |path| {
        var child = try root_dir.openDir(io, path, .{});
        child.close(io);
    }
}
