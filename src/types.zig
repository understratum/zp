pub const Error = error{ PkgNotFound, BuildError, MalformedLine, NoURLFound, VersionNotFound, ProcessFailed, Conflict };

pub const Pkg = struct {
    name: []const u8,
    version: []const u8,
    license: []const u8,
    url: []const u8,
    hash: []const u8,
    deps: []const []const u8 = &.{},
};
