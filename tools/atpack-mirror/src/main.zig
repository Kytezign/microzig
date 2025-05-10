const std = @import("std");
const Allocator = std.mem.Allocator;

const httpz = @import("httpz");

const rate_limit_period_s = 3600;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var mirror = try Mirror.init(gpa.allocator(), "./atpack-cache");
    defer mirror.deinit();

    // More advance cases will use a custom "Handler" instead of "void".
    // The last parameter is our handler instance, since we have a "void"
    // handler, we passed a void ({}) value.
    var server = try httpz.Server(*Mirror).init(allocator, .{ .port = 3000 }, &mirror);
    defer {
        // clean shutdown, finishes serving any live request
        server.stop();
        server.deinit();
    }

    var router = try server.router(.{});
    router.get("/:atpack", get_atpack, .{});

    // blocks
    try server.listen();
}

pub fn get_atpack(mirror: *Mirror, req: *httpz.Request, res: *httpz.Response) !void {
    var arena = std.heap.ArenaAllocator.init(mirror.gpa);
    defer arena.deinit();

    const path = req.url.path;
    std.log.info("path: {s}", .{path});
    var it = std.mem.tokenizeScalar(u8, path, '/');
    const atpack = it.next() orelse return {
        res.status = 404;
        return;
    };

    if (it.next()) |_| {
        res.status = 404;
        return;
    }

    if (!std.mem.endsWith(u8, atpack, ".atpack")) {
        res.status = 404;
        return;
    }

    // http://packs.download.atmel.com/Atmel.ATautomotive_DFP.2.0.214.atpack
    std.log.info("atpack: {s}", .{atpack});

    const body = mirror.get_atpack(atpack, arena.allocator()) catch |err| switch (err) {
        error.NotFound => {
            res.status = 404;
            return;
        },
        else => {
            res.status = 503;
            return;
        },
    };

    res.headers.add("Content-Type", "application/zip");
    res.body = body;
}

pub const Mirror = struct {
    mtx: std.Thread.Mutex = .{},
    gpa: Allocator,
    cache_dir: std.fs.Dir,
    failed_fetches: std.StringArrayHashMapUnmanaged(i64),

    pub fn init(gpa: Allocator, cache_path: []const u8) !Mirror {
        return Mirror{
            .gpa = gpa,
            .cache_dir = try std.fs.cwd().makeOpenPath(cache_path, .{}),
            .failed_fetches = try .init(gpa, &.{}, &.{}),
        };
    }

    pub fn deinit(mirror: *Mirror) void {
        mirror.cache_dir.close();
    }

    fn rate_limit_failed_fetch(mirror: *Mirror, url: []const u8) !void {
        const timestamp = mirror.failed_fetches.get(url) orelse return;
        const now = std.time.timestamp();

        if (now - timestamp < rate_limit_period_s) {
            std.log.info("rate limiting failed fetch", .{});
            return error.NotFound;
        }

        const url_copy = mirror.failed_fetches.getKey(url).?;
        defer mirror.gpa.free(url_copy);
        _ = mirror.failed_fetches.swapRemove(url);
    }

    fn set_failed_fetch(mirror: *Mirror, url: []const u8) !void {
        const now = std.time.timestamp();
        const url_copy = try mirror.gpa.dupe(u8, url);
        errdefer mirror.gpa.free(url_copy);

        try mirror.failed_fetches.putNoClobber(mirror.gpa, url_copy, now);
    }

    pub fn get_atpack(mirror: *Mirror, atpack_name: []const u8, arena: Allocator) ![]u8 {
        mirror.mtx.lock();
        defer mirror.mtx.unlock();

        return mirror.cache_dir.readFileAlloc(arena, atpack_name, 100 * 1024 * 1024) catch blk: {
            const url = try std.fmt.allocPrint(arena, "http://packs.download.atmel.com/{s}", .{atpack_name});
            try mirror.rate_limit_failed_fetch(url);

            var client = std.http.Client{
                .allocator = arena,
            };

            var body = std.ArrayList(u8).init(arena);
            defer body.deinit();

            std.log.info("making request to {s}", .{url});
            const result = client.fetch(.{
                .location = .{ .url = url },
                .response_storage = .{ .dynamic = &body },
                .max_append_size = 100 * 1024 * 1024,
            }) catch |err| {
                std.log.err("Failed to fetch '{s}': {}", .{ url, err });
                return err;
            };

            std.log.info("result: {}", .{result});
            if (result.status != .ok) {
                try mirror.set_failed_fetch(url);
                return error.NotFound;
            }

            mirror.cache_dir.writeFile(.{
                .sub_path = atpack_name,
                .data = body.items,
                .flags = .{
                    .read = true,
                },
            }) catch |err| {
                std.log.err("Failed to write file '{s}': {}", .{ atpack_name, err });
                return err;
            };

            break :blk body.toOwnedSlice();
        };
    }
};
