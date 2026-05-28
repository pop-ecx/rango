const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Conditional compilation for commands chosen by the user
    const shell_option = b.option(bool, "shell", "Include shell command") orelse false;
    const pwd_option = b.option(bool, "pwd", "Include pwd command") orelse false;
    const ls_option = b.option(bool, "ls", "Include ls command") orelse false;
    const cat_option = b.option(bool, "cat", "Include cat command") orelse false;
    const download_option = b.option(bool, "download", "Include download command") orelse false;
    const upload_option = b.option(bool, "upload", "Include upload command") orelse false;
    const deletefile_option = b.option(bool, "deletefile", "Include deletefile command") orelse false;
    const deletedirectory_option = b.option(bool, "deletedirectory", "Include deletedirectory command") orelse false;
    const portscan_option = b.option(bool, "portscan", "Include portscan command") orelse false;

    std.debug.print(
        \\Build Options:
        \\  -Dshell   Include shell commands      [{}]
        \\  -Dpwd     Include pwd command         [{}]
        \\  -Dls      Include ls command          [{}]
        \\  -Dcat     Include cat command         [{}]
        \\  -Ddownload Include download command   [{}]
        \\  -Dupload   Include upload command     [{}]
        \\  -Ddeletefile Include deletefile command [{}]
        \\  -Ddeletedirectory Include deletedirectory command [{}]
        \\  -Dportscan Include portscan command   [{}]
        \\
    , .{ shell_option, pwd_option, ls_option, cat_option, download_option, upload_option, deletefile_option, deletedirectory_option, portscan_option });

    const build_options = b.addOptions();
    build_options.addOption(bool, "shell", shell_option);
    build_options.addOption(bool, "pwd", pwd_option);
    build_options.addOption(bool, "ls", ls_option);
    build_options.addOption(bool, "cat", cat_option);
    build_options.addOption(bool, "download", download_option);
    build_options.addOption(bool, "upload", upload_option);
    build_options.addOption(bool, "deletefile", deletefile_option);
    build_options.addOption(bool, "deletedirectory", deletedirectory_option);
    build_options.addOption(bool, "portscan", portscan_option);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_mod.addOptions("build_options", build_options);

    const exe = b.addExecutable(.{
        .name = "rango",
        .root_module = exe_mod,
    });

    if (target.result.os.tag == .windows) {
        exe.subsystem = .Windows;
    }

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
