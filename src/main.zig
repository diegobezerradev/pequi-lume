//! Lume: the library the Pequi platform loads. It owns the memory, the
//! pictures and sounds, the mixer and the player's progress, and moves
//! between the screens: title, map, settings and the level itself.

const std = @import("std");
const pequi = @import("pequi");
const game = @import("game.zig");
const screens = @import("screens.zig");
const levels = @import("levels.zig");
const Art = @import("art.zig").Art;
const Sounds = @import("sfx.zig").Sounds;
const Progress = @import("progress.zig").Progress;
const Reader = @import("input.zig").Reader;
const Ui = @import("ui.zig").Ui;

comptime {
    pequi.exportGame(@This());
}

/// A panic in game code goes to the player's log (log.txt) before the game stops.
pub const panic = pequi.panic;

const Screen = enum { title, map, settings, play };

const App = struct {
    /// Owns this struct and everything the game allocates.
    arena: pequi.Arena,
    /// Detects a changed layout after a hot reload (then everything restarts).
    layout_size: usize,

    mixer: pequi.audio.Mixer,
    volumes: pequi.audio.Volumes,
    art: Art,
    sounds: Sounds,
    pack: pequi.assets.Pack,
    has_pack: bool,
    progress: Progress,

    screen: Screen,
    /// A screen fades in from the dark: 1 just after a change, then to 0.
    fade: f32,
    /// Seconds on the menus, for what moves on them.
    time: f32,
    reader: Reader,
    menu: pequi.ui.Ui,
    game: game.Game,
    show_debug: bool,
};

fn init(memory: *pequi.GameMemory) *App {
    const api = pequi.platformApi();
    const app = pequi.memory.bootstrap(App, "arena", &memory.platform.block_allocator);
    memory.game_state = app;
    app.layout_size = @sizeOf(App);
    app.mixer = .{};
    app.volumes = pequi.audio.Volumes.load(api);
    app.volumes.apply(&app.mixer);
    app.art = .{};
    app.sounds.init(&app.arena);
    app.has_pack = false;
    if (pequi.assets.Pack.open(&app.arena, api, "lume.pqa")) |pack| {
        app.pack = pack;
        app.has_pack = true;
    } else |err| {
        pequi.log("lume: asset pack: {s} (using the built-in font)", .{@errorName(err)});
    }
    app.progress = Progress.load(api);
    app.screen = .title;
    app.fade = 1;
    app.time = 0;
    app.reader = .{};
    app.menu = .{};
    app.game.robot_on = false;
    app.game.start(app.progress.next());
    return app;
}

pub fn updateAndRender(memory: *pequi.GameMemory, input: *pequi.Input, render: *pequi.RenderCommands) void {
    var app: *App = if (memory.game_state) |ptr| @ptrCast(@alignCast(ptr)) else init(memory);
    if (app.layout_size != @sizeOf(App)) {
        app.mixer.stopAll();
        app.arena.clear();
        app = init(memory);
    }
    const api = pequi.platformApi();
    // Portrait: 540 wide, as tall as the screen's shape allows.
    memory.display.width = 540;
    memory.display.height = 960;
    memory.display.scaling = .expand_height;
    memory.display.min_aspect = 9.0 / 22.0;
    memory.display.max_aspect = 4.0 / 5.0;

    if (memory.gpu_resources_lost) app.art.lost();
    if (!app.art.ready()) {
        app.art.load(if (app.has_pack) &app.pack else null, api, &app.arena, render);
        if (!app.art.ready()) {
            // Still loading: the night, and a thin line of light filling.
            const w: f32 = @floatFromInt(render.width);
            const h: f32 = @floatFromInt(render.height);
            pequi.render.clear(render, 0.01, 0.02, 0.05);
            pequi.render.rect(render, w * 0.3, h * 0.5, w * 0.7, h * 0.5 + 3, pequi.render.color(1, 1, 1, 0.12));
            pequi.render.rect(render, w * 0.3, h * 0.5, w * (0.3 + 0.4 * app.art.progress()), h * 0.5 + 3, pequi.render.rgb(0.8, 1, 0.45));
            app.fade = 1;
            return;
        }
    }
    app.art.fitColorTarget(input, render);

    if (app.screen == .play) {
        const index = app.game.sim.level_index;
        const frame: game.Frame = .{
            .input = input,
            .render = render,
            .art = &app.art,
            .sounds = &app.sounds,
            .mixer = &app.mixer,
            .volumes = &app.volumes,
            .fullscreen = &memory.display.fullscreen,
            .best_stars = app.progress.stars[index],
            .is_last_level = index + 1 >= levels.all.len,
        };
        switch (app.game.update(&frame)) {
            .none => {},
            .won => {
                if (app.progress.record(index, app.game.sim.stars())) app.progress.save(api);
            },
            .map => goTo(app, .map),
            .next => {
                app.game.start(index + 1);
                app.fade = 1;
            },
        }
    } else {
        app.time += input.dt;
        // The menus keep the night's sound, quieter.
        app.sounds.ambience(&app.mixer, .{ 0.35, 0.2, 0.03 });
        const ui = Ui.init(input, render, &app.art, app.reader.read(input));
        const action: screens.Action = switch (app.screen) {
            .title => screens.title(&ui, input, app.time),
            .map => screens.map(&ui, input, app.time, &app.progress),
            .settings => screens.settings(&ui, &app.menu, input, app.time, &app.volumes, &app.mixer, &memory.display.fullscreen),
            .play => unreachable,
        };
        switch (action) {
            .none => {},
            .title => goTo(app, .title),
            .map => goTo(app, .map),
            .settings => goTo(app, .settings),
            .play => |index| {
                app.game.start(index);
                goTo(app, .play);
            },
        }
        // Back on the title closes the game (Esc, or Android's Back).
        if (app.screen == .title and action == .none and ui.pointer.back) input.quit_requested = true;
    }

    if (app.fade > 0) {
        app.fade = @max(0, app.fade - input.dt / 0.4);
        pequi.render.setScreenSpace(render);
        pequi.render.setBlend(render, .alpha);
        pequi.render.rect(render, 0, 0, @floatFromInt(render.width), @floatFromInt(render.height), pequi.render.color(0, 0.005, 0.02, app.fade * app.fade));
    }

    // F1 or ` (three fingers on Android), in Debug and ReleaseSafe builds.
    if (input.debug_toggle) app.show_debug = !app.show_debug;
    if (pequi.internal and app.show_debug) {
        pequi.debug.drawOverlay(render, null, &.{.{ .name = "lume", .arena = &app.arena }});
    }
}

fn goTo(app: *App, screen: Screen) void {
    app.screen = screen;
    app.fade = 1;
    app.reader = .{};
    app.menu = .{};
}

pub fn getSoundSamples(memory: *pequi.GameMemory, buffer: *pequi.SoundBuffer) void {
    const ptr = memory.game_state orelse {
        @memset(buffer.samples[0 .. buffer.frame_count * 2], 0);
        return;
    };
    const app: *App = @ptrCast(@alignCast(ptr));
    if (app.layout_size != @sizeOf(App)) {
        @memset(buffer.samples[0 .. buffer.frame_count * 2], 0);
        return;
    }
    app.mixer.mix(buffer);
}

test {
    _ = @import("sim.zig");
    _ = @import("input.zig");
    _ = @import("progress.zig");
    _ = game;
    _ = screens;
}
