const std = @import("std");
const runProcess = @import("runProcess.zig").runProcess;
const add = @import("add.zig").add;
const Config = @import("../libs/ConfigLib/config.zig").Config;
pub fn unpack(init: std.process.Init, pkg: []const u8, config: Config, allocator: std.mem.Allocator) !void {
    try add(init, pkg, allocator, config, .unpack);
}
