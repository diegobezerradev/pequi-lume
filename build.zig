const std = @import("std");
const pequi = @import("pequi");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const pequi_dep = b.dependency("pequi", .{ .target = target, .optimize = optimize });

    const game = pequi.addGame(b, pequi_dep, .{
        .name = "lume",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .product_name = "Lume",
        // One version for Windows and Android (Gradle reads it too).
        .version = @import("build.zig.zon").version,
        .window_size = .{ 540, 960 },
    });

    pequi.addAssetPack(b, pequi_dep, game, b.path("data/manifest.txt"), "lume");

    const install_library = b.addInstallArtifact(game.library, .{});
    b.getInstallStep().dependOn(&install_library.step);

    const game_step = b.step("game", "Build only the game library (hot reload)");
    game_step.dependOn(&install_library.step);

    const run_step = b.step("run", "Run the game");
    if (game.executable) |exe| {
        const install_exe = b.addInstallArtifact(exe, .{});
        b.getInstallStep().dependOn(&install_exe.step);
        const run = b.addRunArtifact(exe);
        run.step.dependOn(&install_exe.step);
        run.step.dependOn(&install_library.step);
        run_step.dependOn(&run.step);
    } else {
        const fail = b.addFail("lume: the windowed platform is Win32 only for now; build with -Dtarget=x86_64-windows, or use `zig build check-render` on Linux");
        run_step.dependOn(&fail.step);
    }

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "pequi", .module = pequi_dep.module("pequi") }},
        }),
    });
    const test_step = b.step("test", "Run the game's tests (the simulation, with no window)");
    test_step.dependOn(&b.addRunArtifact(tests).step);

    // The rules alone (simulation, levels, robot), for the robots tool.
    const rules = b.createModule(.{
        .root_source_file = b.path("src/rules.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    const robots = b.addExecutable(.{
        .name = "robots",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/robots.zig"),
            .target = target,
            .optimize = .ReleaseFast,
            .imports = &.{.{ .name = "lume", .module = rules }},
        }),
    });
    const robots_step = b.step("robots", "Play every level with the robots and print how it went");
    robots_step.dependOn(&b.addRunArtifact(robots).step);

    const android_step = b.step("android", "Build for Android (libraries and assets for the Gradle project in android/)");
    const android = pequi.addAndroid(b, pequi_dep, game, .{
        .library_name = "lume",
        .root_source_file = b.path("src/main.zig"),
        .optimize = optimize,
    }, android_step);

    const check_android = b.step("check-android", "Run the Android library through a simulated Android lifecycle (x86_64 Linux + Mesa)");
    pequi.addAndroidCheck(b, pequi_dep, android, check_android, .{});

    // Scripted runs through the game, saving screenshots (Linux + Mesa).
    const shots = b.step("shots", "Play the scripts in tools/shots/ headless; screenshots go to zig-out/shots/<script>/");
    const scripts = [_]struct { []const u8, u32 }{
        .{ "tour", 340 },  .{ "play", 1300 }, .{ "win1", 3600 }, .{ "lose", 2000 },
        .{ "webs", 4900 }, .{ "wind", 5700 }, .{ "emas", 9600 },
    };
    for (scripts) |sc| {
        const script = b.path(b.fmt("tools/shots/{s}.txt", .{sc[0]}));
        const out = b.fmt("shots/{s}", .{sc[0]});
        pequi.addScriptedRun(b, game, shots, script, sc[1], "720x1280", out);
        // And each one alone: `zig build shot-tour`.
        const one = b.step(b.fmt("shot-{s}", .{sc[0]}), b.fmt("Play only tools/shots/{s}.txt", .{sc[0]}));
        pequi.addScriptedRun(b, game, one, script, sc[1], "720x1280", out);
    }

    // The same tour on a tall phone (9:20) and on the widest shape (4:5).
    pequi.addScriptedRun(b, game, shots, b.path("tools/shots/tall.txt"), 200, "720x1600", "shots/tall");
    pequi.addScriptedRun(b, game, shots, b.path("tools/shots/wide.txt"), 200, "800x1000", "shots/wide");

    // A tablet's pixels, to look at sharpness. Slow without a GPU, so on its own.
    const tablet = b.step("tablet", "Render a few frames at a tablet's resolution (1600x2560)");
    pequi.addScriptedRun(b, game, tablet, b.path("tools/shots/tablet.txt"), 200, "1600x2560", "shots/tablet");

    // 200 fireflies at once: the game logs what its frame costs.
    const stress = b.step("stress", "Fly 200 fireflies around headless and print the cost of the frame");
    pequi.addScriptedRun(b, game, stress, b.path("tools/shots/stress.txt"), 1600, "720x1280", "shots/stress");

    const check_render = b.step("check-render", "Render the game offscreen with GL 3.3 and GLES 3.0 (Linux + Mesa)");
    pequi.addRenderCheckIn(b, game, check_render, 120, "720x1280");
}
