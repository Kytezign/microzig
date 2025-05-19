const microzig = @import("microzig");

pub const Options = struct {
    yield: ?*const fn () void = null,

    // POC
    spawn_task: ?*const fn (entry: *const fn () callconv(.c) void, stack: []u8) void = null,
};

const scheduler_options = microzig.options.scheduler;

pub inline fn yield() void {
    if (scheduler_options.yield) |yield_fn| {
        yield_fn();
    }
}

// POC
pub inline fn spawn_task(entry: *const fn () callconv(.c) void, stack: []u8) void {
    if (scheduler_options.spawn_task) |spawn_task_fn| {
        spawn_task_fn(entry, stack);
    } else {
        @compileError("create task not supported");
    }
}
