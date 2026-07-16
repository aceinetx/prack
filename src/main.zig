const std = @import("std");
const builtin = @import("builtin");
const Packer = @import("packer.zig").Packer;

pub fn main(init: std.process.Init) !void {
    var packer = Packer.init(init.gpa);
    try packer.addInput(.{
        .filenames = &.{ "lionbee.png", "shit.png", "yt.png", "yt.png", "yt.png", "yt.png" },
        .output = "output.png",
        .scale = 1.17,
    });

    try packer.pack(init.io);

    defer packer.deinit();
}
