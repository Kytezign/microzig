const std = @import("std");
const Build = std.Build;

/// TODO: zig doesn't have these??
const eabi_headers = "/usr/arm-none-eabi/include/";

pub fn addTinyUSBLib(
    b: *Build,
    target: Build.ResolvedTarget,
    tusb_src: Build.LazyPath,
    c_code: Build.LazyPath,
) !*Build.Module {
    const module = b.addModule("tinyusb", .{
        .target = target,
        .optimize = .ReleaseFast,
        .link_libc = true,
    });

    module.addCMacro("CFG_TUSB_MCU", "OPT_MCU_NONE");
    module.addCMacro("CFG_TUSB_OS", "OPT_OS_NONE");
    module.addCMacro("TUP_DCD_EDPT_ISO_ALLOC", "");
    module.addCMacro("TUP_DCD_ENDPOINT_MAX", "16");
    module.addCMacro("TUP_MCU_MULTIPLE_CORE", "1");

    // module.addCSourceFile(.{ .file = b.path("src/usb_descriptors.c") });
    // module.addCSourceFile(.{ .file = b.path("src/printf.c") });

    // /usr/arm-none-eabi/include/
    // TODO: zig does not provide these headers for eabi I guess???
    module.addSystemIncludePath(.{ .cwd_relative = eabi_headers });
    module.addIncludePath(c_code);
    // TinyUSB src folder
    module.addIncludePath(tusb_src);

    // TODO: better to search files? but I don't know how
    // Find and add c files
    // std.debug.print("HERE: {s}\n", .{tusb_src.dependency.sub_path});
    // var dir = try b.build_root.handle.openDir(tusb_src.dependency.sub_path, .{
    //     .no_follow = true,
    //     .iterate = true,
    // });
    // var walker = try dir.walk(b.allocator);
    // defer walker.deinit();
    // defer dir.close();
    // while (try walker.next()) |entry| {
    //     if (std.mem.endsWith(u8, entry.basename, ".c") and entry.kind == .file) {
    //         if (std.mem.indexOf(u8, entry.path, "portable") != null)
    //             continue;
    //         // const full_path = try std.fmt.allocPrint(b.allocator, "{s}/{s}", .{ src_path, entry.path });
    //         std.debug.print("cfile: {s}", .{entry.path});
    //         module.addCSourceFile(.{ .file = tusb_src.path(b, entry.path) });
    //     }
    // }

    // Iterate and print each string
    for (c_files) |file| {
        module.addCSourceFile(.{ .file = tusb_src.path(b, file) });
    }

    const tinyusb = b.addLibrary(.{
        .linkage = .static,
        .name = "tinyusb",
        .root_module = module,
        .use_llvm = true,
    });

    const lib_step = b.addInstallArtifact(tinyusb, .{});
    b.getInstallStep().dependOn(&lib_step.step);

    // TODO: seem redundant to do all of the above then repeat for c translate???
    return addTinyUsbCTranslate(b, target, tusb_src, c_code);
}

fn addTinyUsbCTranslate(
    b: *Build,
    target: Build.ResolvedTarget,
    tusb_src: Build.LazyPath,
    c_code: Build.LazyPath,
) !*Build.Module {
    const tinyusb_c = b.addTranslateC(.{
        .root_source_file = c_code.path(b, "tusb_h.h"),
        .target = target,
        .optimize = .ReleaseFast,
        .link_libc = false,
    });
    tinyusb_c.defineCMacro("CFG_TUSB_MCU", "OPT_MCU_NONE");
    tinyusb_c.defineCMacro("CFG_TUSB_OS", "OPT_OS_NONE");
    tinyusb_c.defineCMacro("TUP_DCD_EDPT_ISO_ALLOC", "");
    tinyusb_c.defineCMacro("TUP_DCD_ENDPOINT_MAX", "16");
    tinyusb_c.defineCMacro("TUP_MCU_MULTIPLE_CORE", "1");

    tinyusb_c.addIncludePath(c_code);

    // TODO: zig does not provide these headers for eabi I guess???
    tinyusb_c.addSystemIncludePath(.{ .cwd_relative = eabi_headers });
    // TinyUSB src folder
    tinyusb_c.addIncludePath(tusb_src);
    tinyusb_c.addIncludePath(tusb_src.path(b, "device"));

    return tinyusb_c.addModule("tinyusb");
}

/// List of all .c files in the tinyUSB src directory less the portable directory files
const c_files = [_][]const u8{
    "tusb.c",
    "device/usbd.c",
    "device/usbd_control.c",
    "class/msc/msc_host.c",
    "class/msc/msc_device.c",
    "class/cdc/cdc_host.c",
    "class/cdc/cdc_rndis_host.c",
    "class/cdc/cdc_device.c",
    "class/dfu/dfu_rt_device.c",
    "class/dfu/dfu_device.c",
    "class/video/video_device.c",
    "class/usbtmc/usbtmc_device.c",
    "class/vendor/vendor_host.c",
    "class/vendor/vendor_device.c",
    "class/net/ecm_rndis_device.c",
    "class/net/ncm_device.c",
    "class/mtp/mtp_device.c",
    "class/audio/audio_device.c",
    "class/bth/bth_device.c",
    "class/midi/midi_device.c",
    "class/midi/midi_host.c",
    "class/hid/hid_device.c",
    "class/hid/hid_host.c",
    "host/usbh.c",
    "host/hub.c",
    "common/tusb_fifo.c",
    "typec/usbc.c",
};
