const std = @import("std");
const Build = std.Build;
const LazyPath = Build.LazyPath;

const zine = @import("zine");
const microzig = @import("microzig");

const PortSelect = microzig.PortSelect;

// Ensure that we always turn on every port so we can build a port list for the website
const MicroBuild = blk: {
    var port_select: PortSelect = undefined;
    for (@typeInfo(PortSelect).@"struct".fields) |field| {
        @field(port_select, field.name) = true;
    }

    break :blk microzig.MicroBuild(port_select);
};

const Chip = struct {
    name: []const u8,
    flag: []const u8,
    has_hal: bool,
    triple: []const u8,
};

const Board = struct {
    name: []const u8,
    chip_name: []const u8,
    flag: []const u8,
    // TODO: link chip
    has_hal: bool,
    triple: []const u8,
};

const Data = struct {
    chips: []const Chip,
    boards: []const Board,
};

fn generate_json_file(b: *std.Build, basename: []const u8, chips: []const Chip, boards: []const Board) LazyPath {
    const data = Data{
        .chips = chips,
        .boards = boards,
    };

    var buf: std.ArrayList(u8) = .init(b.allocator);
    std.json.stringify(data, .{}, buf.writer()) catch unreachable;
    const writefiles = b.addWriteFiles();
    return writefiles.add(basename, buf.items);
}

pub fn build(b: *std.Build) !void {
    const mb = MicroBuild.init(b, b.dependency("microzig", .{})) orelse return;

    var chips = std.ArrayList(Chip).init(b.allocator);
    const boards = std.ArrayList(Board).init(b.allocator);

    @setEvalBranchQuota(5000);
    inline for (@typeInfo(@TypeOf(mb.ports)).@"struct".fields) |base_field| {
        inline for (@typeInfo(@TypeOf(@field(mb.ports, base_field.name).chips)).@"struct".fields) |field| {
            //std.log.info("{}", .{@field(@field(mb.ports, base_field.name).chips, field.name)});
            const chip = @field(@field(mb.ports, base_field.name).chips, field.name);
            const triple = chip.zig_target.zigTriple(b.allocator) catch unreachable;
            chips.append(Chip{
                .name = chip.chip.name,
                .flag = base_field.name,
                .has_hal = chip.hal != null,
                .triple = triple,
            }) catch unreachable;
        }

        //inline for (@typeInfo(@TypeOf(@field(mb.ports, base_field.name).boards)).@"struct".fields) |field| {
        //    /std.log.info("base_field={s} field={s}", .{ base_field.name, field.name });

        //    // skip ch32v boards for now
        //    if (!std.mem.eql(u8, "ch32v", base_field.name)) {
        //        const board = @field(@field(mb.ports, base_field.name).boards, field.name);
        //        std.log.info("{}", .{board});

        //        if (board.board == null) {
        //            std.log.err("{s} is in a board namespace, but does not have the 'board' field set to a non-null value", .{board.name});
        //            @panic("Invalid");
        //        }

        //        const triple = board.zig_target.zigTriple(b.allocator) catch unreachable;
        //        boards.append(Chip{
        //            .name = board.board.?.name,
        //            .chip_name = board.chip.name,
        //            .flag = base_field.name,
        //            .has_hal = board.hal != null,
        //            .triple = triple,
        //        }) catch unreachable;
        //    }
        //}
    }

    const json_file = generate_json_file(b, "data.json", chips.items, boards.items);

    const zine_options = zine.Options{
        .build_assets = &.{
            .{
                .name = "data.json",
                .lp = json_file,
                .install_path = "data.json",
                .install_always = true,
            },
        },
    };

    b.getInstallStep().dependOn(&zine.website(b, zine_options).step);

    const serve = b.step("serve", "Start the Zine dev server");
    const run_zine = zine.serve(b, zine_options);
    serve.dependOn(&run_zine.step);
}
