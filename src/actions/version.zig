const std = @import("std");
const build_options = @import("build_options");

pub inline fn version() void {
    std.debug.print("zp version {s}\n", .{build_options.version});
}
