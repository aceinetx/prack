const std = @import("std");
const builtin = @import("builtin");
const Packer = @import("packer.zig").Packer;

pub fn main(init: std.process.Init) !void {
    var allocator = std.heap.DebugAllocator(.{}).init;
    defer _ = allocator.deinit();

    var packer = Packer.init(allocator.allocator());
    try packer.addInput(&.{ "lionbee.png", "shit.png" }, "output.png", 1024, 1024);

    try packer.pack(init.io);

    defer packer.deinit();
}
