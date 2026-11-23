pub const Error = error{ PkgNotFound, BuildError, MalformedLine, NoURLFound, VersionNotFound, ProcessFailed, Conflict };

pub const Pkg = struct {
    name: []const u8,
    version: []const u8,
    license: []const u8,
    url: []const u8,
    hash: []const u8,
    deps: []const []const u8 = &.{},
    hooks: Hooks = .{},
};

pub const Hooks = struct {
    post_install: []const []const u8 = &.{},
    pre_remove: []const []const u8 = &.{},
};

pub const Options = enum { update, unpack, nothing };
