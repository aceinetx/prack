const std = @import("std");

const c = @cImport({
    @cInclude("stb_rect_pack.h");
    @cInclude("stb_image.h");
    @cInclude("stb_image_write.h");
});

const Input = struct {
    filenames: []const [:0]const u8,
    output: [:0]const u8,
    width: i32,
    height: i32,
};

const FileData = struct {
    data: [*c]c.stbi_uc,
    name: [:0]const u8,
    width: c_int,
    height: c_int,
    nr_channels: c_int,
};

pub const Packer = struct {
    const Error = error{
        StbiImageLoadFailed,
        StbrpPartiallyPacked,
        StbiOutputWriteFailed,
        UnsupportedNrChannels,
    };

    allocator: std.mem.Allocator,
    inputs: std.array_list.Managed(Input),

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .inputs = .init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.inputs.deinit();
    }

    /// Adds an input to the packer
    /// Does not manage the strings - that's your thing
    pub fn addInput(
        self: *@This(),
        filenames: []const [:0]const u8,
        output: [:0]const u8,
        width: i32,
        height: i32,
    ) !void {
        try self.inputs.append(.{
            .filenames = filenames,
            .output = output,
            .width = width,
            .height = height,
        });
    }

    fn packInput(self: *const @This(), io: std.Io, input: *const Input) !void {
        _ = io;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        var allocator = arena.allocator();
        defer arena.deinit();

        var files: std.array_list.Managed(FileData) = .init(allocator);
        defer {
            for (files.items) |file| {
                c.stbi_image_free(file.data);
            }
            files.deinit();
        }

        // Load all the files
        for (input.filenames) |file| {
            var w: c_int = undefined;
            var h: c_int = undefined;
            var nr_channels: c_int = undefined;
            const data = c.stbi_load(file.ptr, &w, &h, &nr_channels, 0);
            if (data == null) return Error.StbiImageLoadFailed;
            if (nr_channels != 3) return Error.UnsupportedNrChannels;
            try files.append(.{
                .data = data,
                .name = file,
                .width = w,
                .height = h,
                .nr_channels = nr_channels,
            });
            std.debug.print("[{s}] loaded: {s} (w = {}, h = {}, nr_channels = {})\n", .{
                input.output,
                file,
                w,
                h,
                nr_channels,
            });
        }

        // Pack rectangles
        var rects: std.array_list.Managed(c.stbrp_rect) = .init(allocator);
        defer rects.deinit();

        for (0.., files.items) |i, *file| {
            try rects.append(.{
                .id = @intCast(i),
                .w = file.width,
                .h = file.height,
            });
        }

        var ctx: c.stbrp_context = undefined;
        var nodes: [128]c.stbrp_node = undefined;
        c.stbrp_init_target(&ctx, input.width, input.height, &nodes, 128);

        const rect_count: c_int = @intCast(rects.items.len);
        if (c.stbrp_pack_rects(&ctx, rects.items.ptr, rect_count) == 0)
            return Error.StbrpPartiallyPacked;

        for (rects.items) |*rect| {
            std.debug.print("[{s}] packed: {s} ({} {} {})\n", .{
                input.output,
                files.items[@intCast(rect.id)].name,
                rect.x,
                rect.y,
                rect.was_packed,
            });
        }

        // Write the final spritesheet
        const data = try allocator.alloc(u8, @intCast(input.width * input.height * 4));
        defer allocator.free(data);

        @memset(data, 0);

        for (rects.items) |*rect| {
            const file = &files.items[@intCast(rect.id)];
            std.debug.print("[{s}] writing: {s}\n", .{ input.output, file.name });

            for (0..@intCast(file.width * file.height)) |i| {
                const pixel: []u8 = file.data[(i * 3)..(i * 3 + 3)];

                const ii: c_int = @intCast(i);
                const x = rect.x + @rem(ii, file.width);
                const y = rect.y + @divTrunc(ii, file.width);
                const base: usize = @intCast((y * input.width + x) * 4);
                data[base] = pixel[0];
                data[base + 1] = pixel[1];
                data[base + 2] = pixel[2];
                data[base + 3] = 255;
            }
        }

        if (c.stbi_write_png(input.output, input.width, input.height, 4, data.ptr, input.width * 4) == 0)
            return Error.StbiOutputWriteFailed;
        std.debug.print("[{s}] done\n", .{input.output});
    }

    fn packInputWorker(self: *const @This(), io: std.Io, input: *const Input) void {
        self.packInput(io, input) catch |err| {
            std.debug.print("[{s}] error: {}\n", .{
                input.output,
                err,
            });
        };
    }

    pub fn pack(self: *@This(), io: std.Io) !void {
        var g = std.Io.Group.init;
        errdefer g.cancel(io);

        for (self.inputs.items) |*input| {
            g.async(io, @This().packInputWorker, .{ self, io, input });
        }
        try g.await(io);
    }
};
