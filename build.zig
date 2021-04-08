const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();
    const lib = b.addSharedLibrary("zig_libretro", "src/main.zig", .unversioned);
    lib.setBuildMode(mode);
    lib.setTarget(target);
    lib.install();
    lib.addIncludeDir("src/");

    var main_tests = b.addTest("src/main.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}
