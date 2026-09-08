const std = @import("std");
const p = @import("../parser.zig");
const Dir = std.Io.Dir;

const BuildSystem = enum { autotools, cmake, meson, make, unknown, cargo, zig, setup_py };

pub fn runProcess(io: anytype, argv: []const []const u8, path: []const u8) !void {
    var child = try std.process.spawn(io, .{
        .argv = argv,
        .cwd = .{ .path = path },
        .stdout = .inherit,
        .stderr = .inherit,
        .stdin = .inherit,
    });
    _ = try child.wait(io);
}

fn hasFile(dir: Dir, io: anytype, name: []const u8) bool {
    _ = dir.statFile(io, name, .{}) catch return false;
    return true;
}

fn detectBuildSystem(src_dir: Dir, io: anytype) BuildSystem {
    if (hasFile(src_dir, io, "Cargo.toml")) return .cargo;
    if (hasFile(src_dir, io, "setup.py")) return .setup_py;
    if (hasFile(src_dir, io, "pyproject.toml")) return .setup_py;
    if (hasFile(src_dir, io, "build.zig")) return .zig;
    if (hasFile(src_dir, io, "configure")) return .autotools;
    if (hasFile(src_dir, io, "CMakeLists.txt")) return .cmake;
    if (hasFile(src_dir, io, "meson.build")) return .meson;
    if (hasFile(src_dir, io, "Makefile") or hasFile(src_dir, io, "makefile") or hasFile(src_dir, io, "GNUmakefile")) {
        return .make;
    }
    return .unknown;
}

pub fn buildAndInstall(init: std.process.Init, src: []const u8, pkg_bin: []const u8) !void {
    var src_dir = try Dir.openDirAbsolute(init.io, src, .{});
    defer src_dir.close(init.io);
    const allocator = init.arena.allocator();
    const build_type = detectBuildSystem(src_dir, init.io);
    const cpu_count = try std.Thread.getCpuCount();
    const j_flag = try std.fmt.allocPrint(allocator, "-j{}", .{cpu_count});

    switch (build_type) {
        .autotools => {
            const autogen_true_false = hasFile(src_dir, init.io, "configure.ac") or hasFile(src_dir, init.io, "configure.in");
            if (autogen_true_false) {
                if (hasFile(src_dir, init.io, "autogen.sh")) {
                    try runProcess(init.io, &[_][]const u8{ "sh", "./autogen.sh" }, src);
                } else {
                    try runProcess(init.io, &[_][]const u8{ "autoreconf", "-fi" }, src);
                }
            }
            try runProcess(init.io, &[_][]const u8{ "./configure", "--prefix=/usr" }, src);
            runProcess(init.io, &[_][]const u8{ "make", j_flag }, src) catch {
                return error.MakeNotFound;
            };
            runProcess(init.io, &[_][]const u8{ "make", "install", try std.fmt.allocPrint(allocator, "DESTDIR={s}", .{pkg_bin}) }, src) catch {
                return error.MakeNotFound;
            };
        },
        .cmake => {
            runProcess(init.io, &[_][]const u8{ "cmake", "-B", "_zb", "-DCMAKE_INSTALL_PREFIX=/usr" }, src) catch {
                return error.CmakeNotFound;
            };
            runProcess(init.io, &[_][]const u8{ "cmake", "--build", "_zb", "--parallel", try std.fmt.allocPrint(allocator, "{}", .{cpu_count}) }, src) catch {
                return error.CmakeNotFound;
            };
            runProcess(init.io, &[_][]const u8{ "cmake", "--install", "_zb" }, src) catch {
                return error.CmakeNotFound;
            };
        },
        .meson => {
            runProcess(init.io, &[_][]const u8{ "meson", "setup", "_zb", "--prefix=/usr" }, src) catch return error.MesonNotFound;
            runProcess(init.io, &[_][]const u8{ "meson", "compile", "-C", "_zb" }, src) catch return error.MesonNotFound;
            runProcess(init.io, &[_][]const u8{ "meson", "install", "-C", "_zb", "--destdir", pkg_bin }, src) catch return error.MesonNotFound;
        },
        .make => {
            runProcess(init.io, &[_][]const u8{ "make", j_flag }, src) catch return error.MakeNotFound;
            runProcess(init.io, &[_][]const u8{ "make", "install", try std.fmt.allocPrint(allocator, "DESTDIR={s}", .{pkg_bin}) }, src) catch return error.MakeNotFound;
        },
        .cargo => {
            const argv = [_][]const u8{
                "cargo",
                "install",
                "--root",
                pkg_bin,
                "--path",
                ".",
            };
            runProcess(init.io, &argv, src) catch return error.CargoNotFound;
        },
        .setup_py => {
            const argv_setup = [_][]const u8{
                "python",
                "setup.py",
                "install",
                "--prefix=/usr",
                try std.fmt.allocPrint(allocator, "--root={s}", .{pkg_bin}),
            };
            runProcess(init.io, &argv_setup, src) catch return error.SetupPyNotFound;
            if (hasFile(src_dir, init.io, "pyproject.toml")) {
                const argv_pip = [_][]const u8{
                    "pip",
                    "install",
                    "--prefix=/usr",
                    try std.fmt.allocPrint(allocator, "--root={s}", .{pkg_bin}),
                    ".",
                };
                runProcess(init.io, &argv_pip, src) catch return error.PipNotFound;
            }
        },
        .zig => {
            const argv = [_][]const u8{
                "zig",
                "build",
                "install",
                "--prefix",
                "/usr",
                try std.fmt.allocPrint(allocator, "--sysroot={s}", .{pkg_bin}),
            };
            try runProcess(init.io, &argv, src);
        },
        .unknown => {
            std.log.err("No make files found in {s}", .{src});
            return error.UnknownBuildSystem;
        },
    }
}

pub fn createDirPath(io: anytype, base_dir: Dir, path: []const u8) !void {
    var cur: Dir = base_dir;
    var is_base: bool = true;
    var it = std.mem.tokenizeScalar(u8, path, '/');

    while (it.next()) |part| {
        if (part.len == 0) continue;
        cur.createDir(io, part, .default_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
        const next_dir = try cur.openDir(io, part, .{});
        if (!is_base) {
            cur.close(io);
        }
        cur = next_dir;
        is_base = false;
    }
    if (!is_base) {
        cur.close(io);
    }
}

pub fn copy(io: anytype, allocator: std.mem.Allocator, src_dir: Dir, dest_dir: Dir, dest_path_prefix: []const u8, list_file: std.Io.File) !void {
    var walker = try src_dir.walk(allocator);
    defer walker.deinit();

    var write_pos: u64 = 0;
    while (try walker.next(io)) |entry| {
        var dest_path_buf: [8096]u8 = undefined;
        const dest_path = if (dest_path_prefix.len == 0 or std.mem.eql(u8, dest_path_prefix, "."))
            entry.path
        else
            try std.fmt.bufPrint(&dest_path_buf, "{s}/{s}", .{ dest_path_prefix, entry.path });

        switch (entry.kind) {
            .file => {
                try entry.dir.copyFile(entry.basename, dest_dir, dest_path, io, .{});
                var abs_path_buf: [4096]u8 = undefined;
                const abs_path = try std.fmt.bufPrint(&abs_path_buf, "/{s}\n", .{dest_path});
                _ = try list_file.writePositionalAll(io, abs_path, write_pos);
                write_pos += abs_path.len;
            },
            .directory => try createDirPath(io, dest_dir, dest_path),
            else => continue,
        }
    }
}
pub fn add(init: std.process.Init, pkg_item: []const u8, allocator: std.mem.Allocator) !void {
    const pkg = try p.GetPkgStatToInstall(pkg_item, allocator);
    const file_name = if (std.mem.lastIndexOfScalar(u8, pkg.url, '/')) |i| pkg.url[i + 1 ..] else pkg.url;

    std.log.info("Install tar file...\n", .{});

    const argv = [_][]const u8{ "curl", "-fSL", "-o", file_name, pkg.url };
    try runProcess(init.io, &argv, "/var/zp/install/");

    var tar_cmd_buf: [8096]u8 = undefined;

    Dir.createDirAbsolute(init.io, try std.fmt.bufPrint(&tar_cmd_buf, "/var/zp/build/{s}", .{pkg_item}), .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    const tar_cmd = try std.fmt.bufPrint(&tar_cmd_buf, "tar -xf /var/zp/install/{s} -C /var/zp/build/{s} --strip-components=1", .{ file_name, pkg_item });
    const argv_tar = [_][]const u8{ "sh", "-c", tar_cmd };
    try runProcess(init.io, &argv_tar, "/var/zp/install/");

    var buff: [256]u8 = undefined;
    const src = try std.fmt.bufPrint(&buff, "/var/zp/build/{s}", .{pkg_item});
    std.log.info("Install '{s}'...\n", .{pkg_item});
    const pkg_bin = try std.fmt.allocPrint(allocator, "/var/zp/pkg/{s}", .{pkg_item});
    defer allocator.free(pkg_bin);
    Dir.createDirAbsolute(init.io, pkg_bin, .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    try buildAndInstall(init, src, pkg_bin);

    var pkg_dir = try Dir.openDirAbsolute(init.io, pkg_bin, .{ .iterate = true });
    defer pkg_dir.close(init.io);

    var root_dir = try Dir.openDirAbsolute(init.io, "/", .{});
    defer root_dir.close(init.io);

    var list_path_buf: [256]u8 = undefined;
    const list_path = try std.fmt.bufPrint(&list_path_buf, "/var/zp/installed/{s}.list", .{pkg_item});

    Dir.createDirAbsolute(init.io, "/var/zp/installed", .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    const list_file = try Dir.createFileAbsolute(init.io, list_path, .{ .truncate = true });
    defer list_file.close(init.io);

    try copy(init.io, allocator, pkg_dir, root_dir, "", list_file);
    var cmd: [4096]u8 = undefined;
    try removePkgEntry(init, "/var/zp/install/packages.db", pkg_item, &cmd);

    var buffer: [4096]u8 = undefined;
    try writeFile(init, "/var/zp/install/packages.db", pkg_item, pkg.version, &buffer);
}

pub fn writeFile(init: std.process.Init, file: []const u8, pkg: []const u8, version: []const u8, buffer: []u8) !void {
    try removePkgEntry(init, file, pkg, buffer);
    const clean_version = std.mem.trim(u8, version, "\n\r ");
    const open_file = Dir.openFileAbsolute(init.io, file, .{ .mode = .read_write }) catch |err| {
        if (err == error.FileNotFound) {
            const new_file = try Dir.createFileAbsolute(init.io, file, .{});
            defer new_file.close(init.io);
            const name_version = try std.fmt.bufPrint(buffer, "{s} {s}\n", .{ pkg, clean_version });
            const stat = try new_file.stat(init.io);
            const size = stat.size;
            _ = try new_file.writePositionalAll(init.io, name_version, size);
            return;
        }
        return err;
    };
    defer open_file.close(init.io);

    const stat = try open_file.stat(init.io);
    const file_size = stat.size;
    const name_version = try std.fmt.bufPrint(buffer, "{s} {s}\n", .{ pkg, clean_version });
    _ = try open_file.writePositionalAll(init.io, name_version, file_size);
}

pub fn removePkgEntry(init: std.process.Init, file: []const u8, pkg: []const u8, buffer: []u8) !void {
    const open_file = Dir.openFileAbsolute(init.io, file, .{}) catch return;
    defer open_file.close(init.io);

    var reader = open_file.reader(init.io, buffer);
    const tmp_path = "/var/zp/install/packages.db.tmp";
    const tmp_file = try Dir.createFileAbsolute(init.io, tmp_path, .{});
    defer tmp_file.close(init.io);

    while (try reader.interface.takeDelimiter('\n')) |line| {
        if (line.len == 0) continue;
        var tokens = std.mem.tokenizeScalar(u8, line, ' ');
        const name = tokens.next() orelse continue;
        if (std.mem.eql(u8, name, pkg)) continue;

        var line_buf: [4096]u8 = undefined;
        const line_with_newline = try std.fmt.bufPrint(&line_buf, "{s}\n", .{line});
        const stat_file = try tmp_file.stat(init.io);
        const size = stat_file.size;
        _ = try tmp_file.writePositionalAll(init.io, line_with_newline, size);
    }

    try Dir.renameAbsolute(tmp_path, file, init.io);
}
