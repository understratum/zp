const std = @import("std");
const linux = std.os.linux;

pub const DirOptions = struct { type: enum { read, write, read_write }, iterate: bool = false, no_follow: bool = false, cloexec: bool = true, exclusive: bool = false, create: bool = false, mode: u32 = 0o755 };

const EntryKind = enum {
    file,
    directory,
    symlink,
    fifo,
    block_device,
    socket,
    unknown,
    char_device,
};

pub const EntryType = struct {
    kind: EntryKind,
    inode: u64,
    name: []const u8,
};

pub const Iterator = struct {
    fd: i32,
    buffer: [4096]u8 = undefined,
    offset: usize = 0,
    done: bool = false,
    len: usize = 0,

    pub fn next(self: *Iterator) !?EntryType {
        if (self.done) return null;

        if (self.offset >= self.len) {
            const bytes_read = linux.getdents64(self.fd, &self.buffer, self.buffer.len);

            if (bytes_read == 0) {
                self.done = true;
                return null;
            }

            self.len = bytes_read;
            self.offset = 0;
        }

        const base: [*]u8 = @ptrCast(&self.buffer);
        const dirent_ptr = base + self.offset;
        const dirent: *align(1) const linux.dirent64 = @ptrCast(dirent_ptr);

        self.offset += dirent.reclen;

        const name_ptr: [*:0]const u8 = @ptrCast(&dirent.name);
        const name = std.mem.span(name_ptr);
        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) {
            return self.next();
        }

        return EntryType{ .inode = dirent.ino, .kind = fromU8(dirent.type), .name = name };
    }

    pub fn reset(self: *Iterator) void {
        self.offset = 0;
        self.done = false;
        self.len = 0;
        _ = linux.lseek(self.fd, 0, linux.SEEK.SET);
    }

    pub fn find(self: *Iterator, name: []const u8) !?EntryType {
        while (try self.next()) |entry| {
            if (std.mem.eql(u8, entry.name, name)) {
                return entry;
            }
        }
        return null;
    }

    pub fn fromU8(value: u8) EntryKind {
        switch (value) {
            0 => return .unknown,
            1 => return .fifo,
            2 => return .char_device,
            4 => return .directory,
            6 => return .block_device,
            8 => return .file,
            10 => return .symlink,
            12 => return .socket,
            else => return .unknown,
        }
    }
};

pub const Dir = struct {
    fd: i32,

    pub fn open(path: []const u8, options: DirOptions) !Dir {
        var path_buf: [4096:0]u8 = undefined;
        if (path.len > path_buf.len) return error.PathTooLong;
        const buf = try std.fmt.bufPrintSentinel(&path_buf, "{s}", .{path}, 0);

        var O = linux.O{};

        O.ACCMODE = .RDONLY;

        O.CREAT = options.create;
        O.CLOEXEC = options.cloexec;
        O.NOFOLLOW = options.no_follow;
        O.EXCL = options.exclusive;
        O.DIRECTORY = true;

        if (options.create) {
            _ = linux.mkdir(buf, options.mode);
        }

        const fd = linux.open(buf, O, options.mode);
        if (linux.errno(fd) != .SUCCESS) {
            return error.OpenFailed;
        }

        const fd_i32: i32 = @intCast(fd);

        return .{ .fd = fd_i32 };
    }

    pub fn createDir(self: *Dir, name: []const u8, mode: u32) !Dir {
        var path_buf: [4096:0]u8 = undefined;
        if (name.len > path_buf.len) return error.PathTooLong;
        const buf = try std.fmt.bufPrintSentinel(&path_buf, name, .{}, 0);

        const result = linux.mkdirat(self.fd, buf, mode);

        if (linux.errno(result) != .SUCCESS) {
            return error.MkdirFailed;
        }

        return .{ .fd = @intCast(result) };
    }

    pub fn deleteFile(self: *Dir, name: []const u8) !void {
        var path_buf: [4096:0]u8 = undefined;
        if (name.len > path_buf.len) return error.PathTooLong;
        const buf = try std.fmt.bufPrintSentinel(&path_buf, name, .{}, 0);

        const result = linux.unlinkat(self.fd, buf);

        if (linux.errno(result) != .SUCCESS) {
            return error.DeleteFileFailed;
        }
    }

    pub fn deleteFilePath(path: []const u8) !void {
        var path_buf: [4096:0]u8 = undefined;
        if (path.len > path_buf.len) return error.PathTooLong;
        const buf = try std.fmt.bufPrintSentinel(&path_buf, path, .{}, 0);

        const result = linux.unlink(buf);

        if (linux.errno(result) != .SUCCESS) {
            return error.DeleteFileFailed;
        }
    }

    pub fn openDir(self: *Dir, name: []const u8) !Dir {
        var path_buf: [256:0]u8 = undefined;
        if (name.len > path_buf.len) return error.PathTooLong;
        const buf = try std.fmt.bufPrintSentinel(&path_buf, name, .{}, 0);

        var O = linux.O{};

        O.ACCMODE = .RDONLY;
        O.DIRECTORY = true;
        O.CLOEXEC = true;

        const fd = linux.openat(self.fd, buf, O, 0);

        if (linux.errno(fd) != .SUCCESS) {
            return error.OpenFailed;
        }

        return .{ .fd = @intCast(fd) };
    }

    pub fn createFile(self: *Dir, name: []const u8, options: FileOptions) !File {
        var opts = options;
        opts.create = true;
        return self.openFile(name, opts);
    }

    /// Create file
    ///
    /// Example:
    ///
    /// ```zig
    /// const zsys = @import("zsys");
    ///
    /// pub fn main() !void {
    ///     const file = try zsys.Dir.createFile("/tmp/test", .{});
    ///     defer file.close(); // close file
    /// }
    /// ```
    pub fn openFile(self: *Dir, path: []const u8, options: FileOptions) !File {
        var path_buf: [1026:0]u8 = undefined;
        if (path.len >= path_buf.len) return error.PathTooLong;
        const buf = try std.fmt.bufPrintSentinel(&path_buf, "{s}", .{path}, 0);

        var O = linux.O{};

        if (options.type == .read_write) {
            O.ACCMODE = .RDWR;
        } else if (options.type == .write) {
            O.ACCMODE = .WRONLY;
        } else {
            O.ACCMODE = .RDONLY;
        }

        O.CREAT = true;
        O.EXCL = options.excl;
        O.TRUNC = options.trunc;
        O.APPEND = options.append;
        O.TMPFILE = options.temp;
        O.NOATIME = options.noatime;
        O.CLOEXEC = options.cloexec;

        const fd: usize = linux.openat(self.fd, buf, O, options.mode);
        if (linux.errno(fd) != .SUCCESS) {
            return error.OpenFailed;
        }

        const fd_i32: i32 = @intCast(fd);

        if (options.lock != .none) {
            const lock_type: i32 = switch (options.lock) {
                .none => 0,
                .shared => 1,
                .exclusive => 2,
            };

            const result = linux.flock(fd_i32, lock_type);
            if (linux.errno(result) != .SUCCESS) {
                return error.LockFailed;
            }

            return .{ .fd = fd_i32, .is_locked = true };
        }

        return .{ .fd = fd_i32, .is_locked = false };
    }

    pub fn close(self: *Dir) void {
        _ = linux.close(self.fd);
    }

    pub fn iterate(self: *Dir) Iterator {
        return .{ .fd = self.fd };
    }
};

/// Standart file functions
pub const File = struct {
    fd: i32,
    is_locked: bool = false,

    /// Create file
    ///
    /// Example:
    ///
    /// ```zig
    /// const zsys = @import("zsys");
    ///
    /// pub fn main() !void {
    ///     const file = try zsys.Dir.createFile("/tmp/test", .{});
    ///     defer file.close(); // close file
    /// }
    /// ```
    pub fn openFile(path: []const u8, options: FileOptions) !File {
        var path_buf: [1026:0]u8 = undefined;
        if (path.len >= path_buf.len) return error.PathTooLong;
        const buf = try std.fmt.bufPrintSentinel(&path_buf, "{s}", .{path}, 0);

        var O = linux.O{};

        if (options.type == .read_write) {
            O.ACCMODE = .RDWR;
        } else if (options.type == .write) {
            O.ACCMODE = .WRONLY;
        } else {
            O.ACCMODE = .RDONLY;
        }

        O.CREAT = true;
        O.EXCL = options.excl;
        O.TRUNC = options.trunc;
        O.APPEND = options.append;
        O.TMPFILE = options.temp;
        O.NOATIME = options.noatime;
        O.CLOEXEC = options.cloexec;

        const fd: usize = linux.open(buf, O, options.mode);
        if (linux.errno(fd) != .SUCCESS) {
            return error.OpenFailed;
        }

        const fd_i32: i32 = @intCast(fd);

        if (options.lock != .none) {
            const lock_type: i32 = switch (options.lock) {
                .none => 0,
                .shared => 1,
                .exclusive => 2,
            };

            const result = linux.flock(fd_i32, lock_type);
            if (linux.errno(result) != .SUCCESS) {
                return error.LockFailed;
            }

            return .{ .fd = fd_i32, .is_locked = true };
        }

        return .{ .fd = fd_i32, .is_locked = false };
    }

    /// Close file descriptor
    pub fn close(self: *File) void {
        if (self.is_locked) {
            _ = linux.flock(self.fd, 8);
        }
        _ = linux.close(self.fd);
    }

    /// Read file
    pub fn read(self: *File, allocator: std.mem.Allocator) ![]const u8 {
        var statx: linux.Statx = undefined;

        const statx_result = linux.statx(self.fd, "", linux.AT.EMPTY_PATH, linux.STATX{ .SIZE = true }, &statx);
        if (linux.errno(statx_result) != .SUCCESS) {
            return error.StatxFailed;
        }

        const file_size: usize = @intCast(statx.size);
        if (file_size == 0) {
            return "";
        }

        const buffer = try allocator.alloc(u8, file_size);
        errdefer allocator.free(buffer);

        _ = linux.lseek(self.fd, 0, linux.SEEK.SET);
        var total_read: usize = 0;
        while (total_read < file_size) {
            const n = linux.read(self.fd, buffer[total_read..].ptr, file_size - total_read);
            if (linux.errno(n) != .SUCCESS) {
                return error.ReadFailed;
            }
            if (n == 0) break;
            total_read += n;
        }

        return buffer[0..total_read];
    }

    /// Read file from path
    pub fn readPath(path: []const u8, allocator: std.mem.Allocator) ![]const u8 {
        const file = try File.openFile(path, .{ .type = .read });
        defer file.close();

        return try file.read(allocator);
    }

    /// Read file with mmap
    pub fn readMmap(self: *File) !MmapedFile {
        var statx: linux.Statx = undefined;

        const statx_result = linux.statx(self.fd, "", linux.AT.EMPTY_PATH, linux.STATX{ .SIZE = true }, &statx);

        if (linux.errno(statx_result) != .SUCCESS) {
            return error.StatxFailed;
        }

        const file_size: usize = @intCast(statx.size);
        if (file_size == 0) {
            return .{ .ptr = "", .len = 0 };
        }

        const mmap_result = linux.mmap(null, file_size, linux.PROT{ .READ = true }, linux.MAP{ .TYPE = .PRIVATE }, self.fd, 0);
        if (linux.errno(mmap_result) != .SUCCESS) {
            return error.MmapFailed;
        }

        return .{ .ptr = @ptrFromInt(mmap_result), .len = file_size };
    }

    /// Read file from path with mmap
    pub fn readMmapPath(path: []const u8) !MmapedFile {
        var file = try File.openFile(path, .{ .type = .read });
        defer file.close();

        return file.readMmap();
    }

    /// Writes data to the file.
    ///
    /// Handles partial writes automatically by looping until all data
    /// is written. The file position advances by the number of bytes written.
    ///
    /// **Note:** For durability guarantees, call `sync()` after writing.
    ///
    /// ## Example
    ///
    /// ```zig
    /// const file = try File.open("/tmp/data.txt", .{
    ///     .write = true,
    ///     .create = true,
    /// });
    /// defer file.close();
    ///
    /// try file.writeFile("Hello, World!\n");
    /// try file.sync();  // ensure data is on disk
    /// ```
    ///
    /// ## Errors
    ///
    /// - `error.WriteFailed` - disk I/O error or file opened read-only
    pub fn writeFile(self: *File, data: []const u8) !void {
        var written: usize = 0;
        while (written < data.len) {
            const n = linux.write(self.fd, data[written..].ptr, data.len - written);
            if (linux.errno(n) != .SUCCESS) return error.WriteFailed;
            written += n;
        }
    }

    /// File exists true/false
    ///
    /// ## Errors
    ///
    /// - `error.PathToLong`
    pub fn exists(path: []const u8) !bool {
        var buf: [8096:0]u8 = undefined;
        if (path.len >= buf.len) {
            return error.PathToLong;
        }

        @memcpy(buf[0..path.len], path);
        buf[path.len] = 0;

        const result = linux.access(&buf, 0);
        return linux.errno(result) == .SUCCESS;
    }

    /// Read file without lseek
    ///
    /// Example:
    ///
    /// ```zig
    /// const zsys = @import("zsys.zig");
    ///
    /// const allocator = std.mem.Allocator;
    /// const file = try zsys.File.open("/tmp/testfile", .{ .read = true });
    /// defer file.close();
    ///
    /// const data = try file.pread(allocator, 0);
    ///
    /// std.debug.print("data: {}\n", .{ data });
    ///
    /// ## Errors
    ///
    /// - `error.ReadError`
    pub fn pread(self: *File, allocator: std.mem.Allocator, offset: i64) ![]const u8 {
        var statx: linux.Statx = undefined;

        const statx_result = linux.statx(self.fd, "", linux.AT.EMPTY_PATH, linux.STATX{ .SIZE = true }, &statx);
        if (linux.errno(statx_result) != .SUCCESS) {
            return error.StatxFailed;
        }

        const file_size: usize = @intCast(statx.size);

        var buffer = try allocator.alloc(u8, file_size);

        const data = linux.pread(self.fd, &buffer.ptr, &buffer.len, offset);

        if (linux.errno(data) != .SUCCESS) {
            return error.ReadError;
        }

        const text: []const u8 = buffer[0..data];

        return text;
    }

    /// Read file from path without lseek
    ///
    /// Example:
    ///
    /// ```zig
    /// const zsys = @import("zsys.zig")
    ///
    /// const allocator = std.mem.Allocator;
    /// const data = try zsys.File.preadPath("/tmp/testfile", allocator, 0);
    ///
    /// std.debug.print("data: {s}\n", .{ data });
    ///
    /// ## Errors
    ///
    /// - `error.ReadError`
    pub fn preadPath(path: []const u8, allocator: std.mem.Allocator, offset: i64) ![]const u8 {
        const file = try File.openFile(path, .{ .read = true });
        defer file.close();

        return try file.pread(allocator, offset);
    }

    /// Flushes buffered data and metadata to disk.
    ///
    /// Ensures all modifications are physically written to storage.
    /// Call after `write()` when data durability matters.
    ///
    /// ## Example
    ///
    /// ```zig
    /// const file = try File.open("/var/log/app.log", .{
    ///     .write_only = true,
    ///     .append = true,
    /// });
    /// defer file.close();
    ///
    /// try file.write("Important log entry\n");
    /// try file.sync();  // guarantee data is on disk
    /// ```
    ///
    /// ## Errors
    ///
    /// - `error.SyncFailed` — disk I/O error or read-only filesystem
    pub fn sync(self: *File) !void {
        const result = linux.fsync(self.fd);
        if (linux.errno(result) != .SUCCESS) {
            return error.SyncFailed;
        }
    }

    /// Flushes only file data to disk (skips metadata like mtime).
    ///
    /// Faster than `sync()` when you only care about data integrity.
    ///
    /// ## Example
    ///
    /// ```zig
    /// try log.write("entry\n");
    /// try log.syncData();  // faster than sync()
    /// ```
    ///
    /// ## Errors
    ///
    /// - `error.SyncFailed` — disk I/O error
    pub fn syncData(self: *File) !void {
        const result = linux.fdatasync(self.fd);
        if (linux.errno(result) != .SUCCESS) {
            return error.SyncFailed;
        }
    }
};

/// linux.O options
pub const FileOptions = struct {
    type: Access = .read,
    create: bool = false,
    excl: bool = false,
    trunc: bool = false,
    append: bool = false,
    directory: bool = false,
    temp: bool = false,
    noatime: bool = false,
    cloexec: bool = true,
    mode: u32 = 0o644,
    lock: Lock = .none,
};

pub const Access = enum { read, write, read_write };

pub const MmapedFile = struct {
    ptr: [*]const u8,
    len: usize,

    pub fn slice(self: *MmapedFile) []const u8 {
        return self.ptr[0..self.len];
    }

    pub fn deinit(self: *MmapedFile) void {
        _ = linux.munmap(self.ptr, self.len);
    }
};

pub const Lock = enum {
    none,
    shared,
    exclusive,
};
