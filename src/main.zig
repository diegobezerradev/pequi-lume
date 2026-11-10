//! Lume: the library the Pequi platform loads. It owns the memory, the
//! generated pictures and sounds and the mixer, and runs `game.zig`.

const std = @import("std");
const pequi = @import("pequi");
const game = @import("game.zig");
const Art = @import("art.zig").Art;
const Sounds = @import("sfx.zig").Sounds;

comptime {
    pequi.exportGame(@This());
}

/// A panic in game code goes to the player's log (log.txt) before the game stops.
pub const panic = pequi.panic;

const App = struct {
    /// Owns this struct and everything the game allocates.
    arena: pequi.Arena,
    /// Detects a changed layout after a hot reload (then everything restarts).
    layout_size: usize,

    mixer: pequi.audio.Mixer,
    volumes: pequi.audio.Volumes,
    art: Art,
    sounds: Sounds,
    game: game.Game,
    show_debug: bool,
};

fn init(memory: *pequi.GameMemory) *App {
    const app = pequi.memory.bootstrap(App, "arena", &memory.platform.block_allocator);
    memory.game_state = app;
    app.layout_size = @sizeOf(App);
    app.mixer = .{};
    app.volumes = pequi.audio.Volumes.load(pequi.platformApi());
    app.volumes.apply(&app.mixer);
    app.art = .{};
    app.sounds.init(&app.arena);
    app.game.robot_on = false;
    app.game.start(0);
    return app;
}

pub fn updateAndRender(memory: *pequi.GameMemory, input: *pequi.Input, render: *pequi.RenderCommands) void {
    var app: *App = if (memory.game_state) |ptr| @ptrCast(@alignCast(ptr)) else init(memory);
    if (app.layout_size != @sizeOf(App)) {
        app.mixer.stopAll();
        app.arena.clear();
        app = init(memory);
    }
    // Portrait: 540 wide, as tall as the screen's shape allows.
    memory.display.width = 540;
    memory.display.height = 960;
    memory.display.scaling = .expand_height;
    memory.display.min_aspect = 9.0 / 22.0;
    memory.display.max_aspect = 4.0 / 5.0;

    if (memory.gpu_resources_lost) app.art.uploaded = false;
    if (!app.art.uploaded) app.art.upload(render);

    app.sounds.ambience(&app.mixer);
    var frame: game.Frame = .{
        .input = input,
        .render = render,
        .art = &app.art,
        .sounds = &app.sounds,
        .mixer = &app.mixer,
    };
    app.game.update(&frame);

    // F1 or ` (three fingers on Android), in Debug and ReleaseSafe builds.
    if (input.debug_toggle) app.show_debug = !app.show_debug;
    if (pequi.internal and app.show_debug) {
        pequi.debug.drawOverlay(render, null, &.{.{ .name = "lume", .arena = &app.arena }});
    }
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
    _ = game;
}
