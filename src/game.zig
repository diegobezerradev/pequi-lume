//! The level on screen: reads the player's hand, runs the simulation in
//! fixed steps, and turns its state and events into picture and sound.
//!
//! How the picture is built, every frame:
//!   1. the night sky and the silhouettes of everything, far to near;
//!   2. the light map: every light added together in a small texture;
//!   3. the colors of the scene, multiplied by the light map in a second
//!      texture, and added over the silhouettes: color only where light is;
//!   4. what shines by itself (fireflies, sparks), then the dark leaves
//!      passing close to the eye, then the HUD.

const std = @import("std");
const pequi = @import("pequi");
const draw = pequi.render;
const juice = pequi.juice;
const sim = @import("sim.zig");
const levels = @import("levels.zig");
const predators = @import("predators.zig");
const Art = @import("art.zig").Art;
const input_mod = @import("input.zig");
const Sounds = @import("sfx.zig").Sounds;
const Robot = @import("robot.zig").Robot;
const ui_mod = @import("ui.zig");
const Ui = ui_mod.Ui;

pub const Frame = struct {
    input: *pequi.Input,
    render: *pequi.RenderCommands,
    art: *const Art,
    sounds: *Sounds,
    mixer: *pequi.audio.Mixer,
    volumes: *pequi.audio.Volumes,
    font: ?*const draw.Font,
    fullscreen: *bool,
    /// The stars this level already had, for the end screen.
    best_stars: u32,
    is_last_level: bool,
};

/// What the level asks of the app when its frame ends.
pub const Action = enum { none, map, next, won };

const DecorKind = enum(u8) { tree, bush, tuft, buriti, canela, pequi };

const Decor = struct {
    x: f32,
    y: f32,
    kind: DecorKind,
    size: f32,
    phase: f32,
};

const max_decor = 420;
/// Steps the simulation may run in one frame (after a hitch it slows down
/// instead of trying to catch up).
const max_steps_per_frame = 6;
const larva_count = 44;

const Pass = enum { silhouette, color };

const Ghost = struct {
    x: f32 = 0,
    y: f32 = 0,
    to_x: f32 = 0,
    to_y: f32 = 0,
    /// 0 to 1; done at 1.
    t: f32 = 1,
};

const ghost_seconds: f32 = 0.55;
const cascade_seconds: f32 = 2.6;

/// Averages and peaks of the frame's cost, for the stress test's log.
const Perf = struct {
    frames: u32 = 0,
    sim_ticks: u64 = 0,
    draw_ticks: u64 = 0,
    sim_max: u64 = 0,
    draw_max: u64 = 0,
};

pub const Game = struct {
    sim: sim.Sim,
    reader: input_mod.Reader,
    accumulator: f32,
    time: f32,
    cam_x: f32,
    cam_y: f32,
    zoom: f32,
    particles: juice.Particles(1200),
    fx: juice.Rng,
    decor: [max_decor]Decor,
    decor_count: u32,
    /// Seconds since the level ended.
    end_time: f32,
    /// The red blink when a predator takes one, fading from 1.
    flash: f32,
    robot_on: bool,
    robot: Robot,
    stress: bool,
    perf: Perf,
    paused: bool,
    menu: pequi.ui.Ui,
    /// The win was already reported to the app.
    reported: bool,
    /// The tutorial: what the player has already done by themselves.
    flown: f32,
    did_pulse: bool,
    did_dark: bool,
    /// Short freeze when a predator takes one.
    hit_stop: f32,
    /// Fireflies just taken: their light is pulled to the predator and dies.
    ghosts: [12]Ghost,
    /// The pulse's kick on the camera, fading from 1.
    punch: f32,
    /// The swarm count grew or shrank: the number jumps.
    count_bump: f32,
    last_swarm: u32,
    /// The mound's cascade: larvae lit and stars shown so far.
    larvae_lit: u32,
    stars_shown: u32,
    trail_timer: f32,

    pub fn start(g: *Game, level_index: u32) void {
        const level = levels.get(level_index);
        g.sim = sim.Sim.init(level_index);
        g.reader = .{};
        g.accumulator = 0;
        g.time = 0;
        g.cam_x = level.start[0];
        g.cam_y = level.start[1];
        g.zoom = 1;
        g.particles.clear();
        g.fx = .{ .state = level.seed ^ 0x5bd1e995 };
        g.end_time = 0;
        g.flash = 0;
        g.stress = false;
        g.perf = .{};
        g.robot = .{ .goal = level.stars[2] };
        g.paused = false;
        g.menu = .{};
        g.reported = false;
        g.flown = 0;
        g.did_pulse = false;
        g.did_dark = false;
        g.hit_stop = 0;
        g.ghosts = @splat(.{});
        g.punch = 0;
        g.count_bump = 0;
        g.last_swarm = g.sim.swarm;
        g.larvae_lit = 0;
        g.stars_shown = 0;
        g.trail_timer = 0;
        g.plant(level);
    }

    /// Scatters the vegetation, away from the water, the start and the mound.
    fn plant(g: *Game, level: *const levels.Level) void {
        var rng: juice.Rng = .{ .state = level.seed ^ 0x2545f491 };
        g.decor_count = 0;
        const area = level.width * level.height;
        // Each region has its plants: buriti palms by the water of the
        // vereda, canela-de-ema in the campo sujo, pequi trees on the chapada.
        const Want = struct { DecorKind, f32, f32, f32 };
        const wanted: [5]Want = switch (level.region) {
            // kind, one per this many square units, smallest, largest
            .vereda => .{ .{ .buriti, 70000, 170, 250 }, .{ .tree, 160000, 110, 170 }, .{ .bush, 50000, 26, 44 }, .{ .tuft, 13000, 10, 20 }, .{ .canela, 400000, 50, 70 } },
            .campo_sujo => .{ .{ .canela, 34000, 46, 84 }, .{ .tree, 190000, 100, 150 }, .{ .bush, 36000, 24, 46 }, .{ .tuft, 11000, 10, 22 }, .{ .pequi, 260000, 120, 160 } },
            .chapada => .{ .{ .pequi, 90000, 130, 190 }, .{ .canela, 110000, 44, 70 }, .{ .bush, 70000, 22, 40 }, .{ .tuft, 9000, 10, 24 }, .{ .buriti, 500000, 170, 220 } },
        };
        for (wanted) |w| {
            const count: u32 = @intFromFloat(area / w[1]);
            var made: u32 = 0;
            var tries: u32 = 0;
            while (made < count and tries < count * 6 and g.decor_count < max_decor) : (tries += 1) {
                const x = rng.range(20, level.width - 20);
                const y = rng.range(20, level.height - 20);
                if (w[0] != .tuft) {
                    if (sim.distance(x, y, level.start[0], level.start[1]) < 110) continue;
                    if (sim.distance(x, y, level.mound[0], level.mound[1]) < 150) continue;
                    var wet = false;
                    for (level.ponds) |p| {
                        const dx = (x - p.x) / (p.rx + 40);
                        const dy = (y - p.y) / (p.ry + 40);
                        if (dx * dx + dy * dy < 1) wet = true;
                    }
                    if (wet) continue;
                }
                g.decor[g.decor_count] = .{ .x = x, .y = y, .kind = w[0], .size = rng.range(w[2], w[3]), .phase = rng.range(0, std.math.tau) };
                g.decor_count += 1;
                made += 1;
            }
        }
        // Back to front, so nearer things cover farther ones.
        const items = g.decor[0..g.decor_count];
        std.mem.sort(Decor, items, {}, struct {
            fn before(_: void, a: Decor, b: Decor) bool {
                return a.y < b.y;
            }
        }.before);
    }

    pub fn update(g: *Game, f: *const Frame) Action {
        const api = pequi.platformApi();
        const t0 = api.perfCounter();
        const w: f32 = @floatFromInt(f.render.width);
        const h: f32 = @floatFromInt(f.render.height);
        const dt = @min(f.input.dt, 0.05);
        const level = levels.get(g.sim.level_index);

        const pointer = g.reader.read(f.input);
        const ui = Ui.init(f.input, f.render, f.art, f.font, pointer);
        if (pequi.internal) {
            if (pointer.robot) g.robot_on = !g.robot_on;
            if (pointer.fill) g.fill();
        }

        // The pause button, top right; Esc and Android's Back too.
        const pause_x = w - f.input.safe_area.right - ui.touch / 2 - 6;
        const pause_y = f.input.safe_area.top + ui.touch / 2 + 2;
        const playing = g.sim.outcome == .playing;
        const on_pause = @abs(pointer.press_x - pause_x) <= ui.touch / 2 and @abs(pointer.press_y - pause_y) <= ui.touch / 2;
        if (playing and !g.paused and (pointer.back or ui.pressed(pause_x, pause_y, ui.touch, ui.touch))) {
            g.paused = true;
            g.menu = .{};
        } else if (g.paused and pointer.back) {
            g.paused = false;
        }

        var action: Action = .none;
        if (!g.paused) {
            g.time += dt;
            var controls: sim.Controls = .{
                .target_x = g.cam_x + (pointer.x - w / 2) / g.zoom,
                .target_y = g.cam_y + (pointer.y - h / 2) / g.zoom,
                .guiding = pointer.down and !on_pause,
                .pulse = pointer.tap and !on_pause,
                .dark = pointer.dark,
            };
            if (!playing) {
                g.end_time += dt;
                controls = .{};
            }

            // A predator's catch stops time for an instant.
            var sim_dt = dt;
            if (g.hit_stop > 0) {
                g.hit_stop -= dt;
                sim_dt = 0;
            }
            var events: sim.Events = .{};
            g.accumulator += sim_dt;
            var steps: u32 = 0;
            while (g.accumulator >= sim.dt and steps < max_steps_per_frame) : (steps += 1) {
                g.accumulator -= sim.dt;
                if (g.robot_on) controls = g.robot.think(&g.sim);
                const before = g.sim.flies[sim.leader];
                g.sim.step(controls, &events);
                controls.pulse = false;
                g.flown += sim.distance(before.x, before.y, g.sim.flies[sim.leader].x, g.sim.flies[sim.leader].y);
            }
            if (steps == max_steps_per_frame) g.accumulator = 0;
            if (events.has(.pulse)) g.did_pulse = true;
            if (events.has(.dark_on)) g.did_dark = true;
            g.react(f, &events);
            g.blowLeaves(w, h, dt);

            // The camera looks a little ahead of the leader, and backs away
            // as the swarm grows.
            const me = g.sim.flies[sim.leader];
            var look_x = me.x + me.vx * 0.4;
            var look_y = me.y + me.vy * 0.4;
            var wanted_zoom = std.math.clamp(1.0 - (@as(f32, @floatFromInt(g.sim.swarm)) - 8) * 0.0035, 0.74, 1.0);
            if (g.sim.outcome == .won) {
                // The mound takes the stage.
                look_x = g.sim.mound_x;
                look_y = g.sim.mound_y - 40;
                wanted_zoom = 1.05;
            }
            g.cam_x = juice.approach(g.cam_x, look_x, if (playing) 0.22 else 0.5, dt);
            g.cam_y = juice.approach(g.cam_y, look_y, if (playing) 0.22 else 0.5, dt);
            g.zoom = juice.approach(g.zoom, wanted_zoom, 0.8, dt);
            g.punch = @max(0, g.punch - dt * 3);
            g.count_bump = @max(0, g.count_bump - dt * 4);
            if (g.sim.swarm != g.last_swarm) {
                g.last_swarm = g.sim.swarm;
                g.count_bump = 1;
            }
            for (&g.ghosts) |*ghost| {
                if (ghost.t < 1) ghost.t = @min(1, ghost.t + dt / ghost_seconds);
            }
            g.leaveTrails(dt);
            if (g.sim.outcome == .won) g.cascade(f);
            const half_w = w / 2 / g.zoom;
            const half_h = h / 2 / g.zoom;
            g.cam_x = if (g.sim.width > half_w * 2) std.math.clamp(g.cam_x, half_w, g.sim.width - half_w) else g.sim.width / 2;
            g.cam_y = if (g.sim.height > half_h * 2) std.math.clamp(g.cam_y, half_h, g.sim.height - half_h) else g.sim.height / 2;

            g.particles.update(dt);
            g.flash = @max(0, g.flash - dt * 3.5);
            if (g.sim.outcome == .won and !g.reported) {
                g.reported = true;
                action = .won;
            }
        }

        // The night's layers: by region, and the wind by its gusts.
        const gust = @sqrt(g.sim.wind_x * g.sim.wind_x + g.sim.wind_y * g.sim.wind_y) / 700;
        const quiet: f32 = if (g.paused) 0.4 else 1;
        f.sounds.ambience(f.mixer, switch (level.region) {
            .vereda => .{ 0.45 * quiet, 0.5 * quiet, 0.02 },
            .campo_sujo => .{ 0.6 * quiet, 0.12 * quiet, 0.05 * quiet },
            .chapada => .{ 0.22 * quiet, 0, (0.1 + 0.55 * gust) * quiet },
        });

        const t1 = api.perfCounter();
        g.paint(f, &ui, level);
        g.drawHud(f, &ui, level, pause_x, pause_y);
        const menu_action = if (g.paused) g.pauseMenu(f, ui.touch) else g.endScreen(f, &ui, level);
        if (menu_action != .none) action = menu_action;
        const t2 = api.perfCounter();
        if (pequi.internal and g.stress) g.measure(api, t1 -% t0, t2 -% t1);
        return action;
    }

    /// Leaves in the wind: where it blows, and how hard, is seen.
    fn blowLeaves(g: *Game, w: f32, h: f32, dt: f32) void {
        const strength = @sqrt(g.sim.wind_x * g.sim.wind_x + g.sim.wind_y * g.sim.wind_y);
        if (strength < 60) return;
        const per_second = strength / 14;
        var n = per_second * dt + g.fx.range(0, 1);
        while (n >= 1) : (n -= 1) {
            const dx = g.sim.wind_x / strength;
            const dy = g.sim.wind_y / strength;
            // They enter from the side the wind comes from.
            const along = g.fx.range(-0.75, 0.75);
            const x = g.cam_x - dx * w * 0.6 / g.zoom + -dy * along * h / g.zoom;
            const y = g.cam_y - dy * h * 0.6 / g.zoom + dx * along * h / g.zoom;
            const speed = g.fx.range(380, 620);
            g.particles.emit(.{
                .x = x,
                .y = y,
                .vx = dx * speed,
                .vy = dy * speed + g.fx.range(-40, 40),
                .life = g.fx.range(1.2, 2.2),
                .size_start = g.fx.range(3, 6),
                .size_end = 3,
                .color_start = draw.color(0.55, 0.65, 0.8, 0.55),
                .color_end = draw.color(0.55, 0.65, 0.8, 0.55),
                .fade_out = 0.3,
                .blend = .alpha,
            });
        }
    }

    fn pauseMenu(g: *Game, f: *const Frame, touch: f32) Action {
        var action: Action = .none;
        var menu = pequi.ui.begin(&g.menu, f.input, f.render, f.font, .{ .title = "Pausa", .theme = menu_theme, .item_height = touch, .width = 440 });
        if (menu.button("Continuar")) g.paused = false;
        if (menu.button("Recomeçar")) g.start(g.sim.level_index);
        if (menu.button("Mapa")) action = .map;
        var changed = menu.slider("Ambiente", &f.volumes.music, 0, 1);
        changed = menu.slider("Efeitos", &f.volumes.effects, 0, 1) or changed;
        if (@import("builtin").os.tag == .windows) _ = menu.toggle("Tela cheia", f.fullscreen);
        menu.end();
        if (changed) f.volumes.apply(f.mixer);
        if (action != .none or !g.paused) saveVolumes(f.volumes);
        return action;
    }

    /// Won or lost: what happened, the stars, and where to go from here.
    fn endScreen(g: *Game, f: *const Frame, ui: *const Ui, level: *const levels.Level) Action {
        const s = &g.sim;
        if (s.outcome == .playing) return .none;
        const render = f.render;
        const w: f32 = @floatFromInt(render.width);
        const h: f32 = @floatFromInt(render.height);
        const won = s.outcome == .won;
        // The mound's cascade plays out first.
        const wait: f32 = if (won) 3.4 else 0.9;
        const a = std.math.clamp((g.end_time - wait) / 0.7, 0, 1);
        if (a <= 0) return .none;
        var buffer: [96]u8 = undefined;
        draw.setScreenSpace(render);
        draw.rect(render, 0, 0, w, h, draw.color(0, 0.01, 0.03, (if (won) @as(f32, 0.35) else 0.62) * a));

        const y = h * 0.3;
        if (won) {
            ui.centered(w / 2, y, 60, "Aceso!", draw.color(0.85, 1, 0.5, a));
            const stars = s.stars();
            for (0..3) |i| {
                const since = g.end_time - (wait + 0.6 + @as(f32, @floatFromInt(i)) * 0.4);
                const on = i < stars and since > 0;
                if (on and g.stars_shown == i) {
                    g.stars_shown += 1;
                    f.sounds.star(f.mixer, i);
                    buzz(14, 0.5);
                }
                // Each star lands a little too big and settles.
                const pop = 1 + 0.5 * (1 - juice.Ease.apply(.out_cubic, std.math.clamp(since / 0.3, 0, 1)));
                ui.star(w / 2 + (@as(f32, @floatFromInt(i)) - 1) * 84, y + 130, 44 * (if (on) pop else 1), on, a);
            }
            const line = std.fmt.bufPrint(&buffer, "{d} vaga-lumes chegaram", .{s.swarm}) catch "";
            ui.centered(w / 2, y + 186, 22, line, draw.color(0.82, 0.87, 0.95, a));
            if (stars < 3) {
                const more = std.fmt.bufPrint(&buffer, "{d} para a próxima estrela", .{level.stars[stars]}) catch "";
                ui.centered(w / 2, y + 218, 18, more, draw.color(0.6, 0.66, 0.78, a));
            }
        } else {
            const title = if (s.swarm == 0) "O enxame se apagou" else "Vaga-lumes de menos";
            ui.centered(w / 2, y, 38, title, draw.color(0.85, 0.9, 1, a));
            if (s.swarm > 0) {
                const line = std.fmt.bufPrint(&buffer, "o cupinzeiro pede {d}", .{s.need}) catch "";
                ui.centered(w / 2, y + 56, 22, line, draw.color(0.6, 0.66, 0.78, a));
            }
        }

        const bottom = h - f.input.safe_area.bottom;
        var action: Action = .none;
        if (won and !f.is_last_level) {
            if (ui.button(w / 2, bottom - 54 - (ui.touch + 16) * 2, 300, "Próxima", a)) action = .next;
        }
        if (ui.button(w / 2, bottom - 54 - (ui.touch + 16), 300, if (won) "De novo" else "Tentar de novo", a)) g.start(s.level_index);
        if (ui.button(w / 2, bottom - 54, 300, "Mapa", a)) action = .map;
        return action;
    }

    /// Debug: a swarm of 200, to measure the frame at its heaviest.
    fn fill(g: *Game) void {
        const me = g.sim.flies[sim.leader];
        while (g.sim.fly_count < sim.max_flies) {
            const a = g.fx.range(0, std.math.tau);
            const r = g.fx.range(10, 80);
            g.sim.addFly(.swarm, me.x + @cos(a) * r, me.y + @sin(a) * r);
        }
        g.stress = true;
        g.perf = .{};
    }

    fn measure(g: *Game, api: *const pequi.platform.PlatformApi, sim_ticks: u64, draw_ticks: u64) void {
        const p = &g.perf;
        p.frames += 1;
        p.sim_ticks += sim_ticks;
        p.draw_ticks += draw_ticks;
        p.sim_max = @max(p.sim_max, sim_ticks);
        p.draw_max = @max(p.draw_max, draw_ticks);
        if (p.frames < 300) return;
        const to_ms = 1000.0 / @as(f64, @floatFromInt(api.perf_frequency));
        const n: f64 = @floatFromInt(p.frames);
        pequi.log("lume: {d} fireflies, {d} frames: update {d:.3} ms (peak {d:.3}), draw commands {d:.3} ms (peak {d:.3})", .{
            g.sim.swarm,                                       p.frames,
            @as(f64, @floatFromInt(p.sim_ticks)) / n * to_ms,  @as(f64, @floatFromInt(p.sim_max)) * to_ms,
            @as(f64, @floatFromInt(p.draw_ticks)) / n * to_ms, @as(f64, @floatFromInt(p.draw_max)) * to_ms,
        });
        p.* = .{};
    }

    /// Sound and sparks for what the simulation reported.
    fn react(g: *Game, f: *const Frame, events: *const sim.Events) void {
        const s = f.sounds;
        for (events.slice()) |e| {
            const pan = Sounds.panFor(e.x, g.cam_x);
            switch (e.kind) {
                .rescued => {
                    s.rescued(f.mixer, e.value, pan);
                    g.sparks(e.x, e.y, 7, 90, draw.rgb(0.8, 1, 0.4));
                },
                .taken => {
                    s.play(f.mixer, &s.taken, 0.9, 1, pan);
                    g.sparks(e.x, e.y, 16, 150, draw.rgb(1, 0.55, 0.3));
                    g.flash = 1;
                    g.hit_stop = 0.07;
                    buzz(35, 0.9);
                    // Its light is dragged off to whoever took it.
                    var slot: *Ghost = &g.ghosts[0];
                    for (&g.ghosts) |*ghost| {
                        if (ghost.t > slot.t) slot = ghost;
                    }
                    slot.* = .{ .x = e.x, .y = e.y, .to_x = e.by_x, .to_y = e.by_y, .t = 0 };
                },
                .stuck => {
                    s.play(f.mixer, &s.stuck, 0.7, 0.9 + g.fx.range(0, 0.3), pan);
                    buzz(10, 0.3);
                },
                .freed => {
                    s.rescued(f.mixer, 3 + e.value, pan);
                    g.sparks(e.x, e.y, 20, 200, draw.rgb(0.85, 0.9, 1));
                },
                .owl_dive => s.play(f.mixer, &s.screech, 0.8, 1, pan),
                .owl_miss => s.play(f.mixer, &s.whoosh, 0.7, 1, pan),
                .gust => s.play(f.mixer, &s.whoosh, 0.35, 0.6, e.x * 0.6),
                .wolf => s.play(f.mixer, &s.howl, 0.7, 1, 0),
                .strayed => s.play(f.mixer, &s.strayed, 0.5, 1, pan),
                .pulse => {
                    s.play(f.mixer, &s.pulse, 0.9, 1, 0);
                    g.sparks(e.x, e.y, 30, 320, draw.rgb(0.9, 1, 0.6));
                    g.punch = 1;
                    buzz(18, 0.45);
                },
                .pulse_denied => {},
                .dark_on => s.play(f.mixer, &s.dark_on, 0.7, 1, 0),
                .dark_off => s.play(f.mixer, &s.dark_off, 0.6, 1, 0),
                .frog_windup => {
                    // Heard from afar, louder up close: the warning to hide.
                    const d = sim.distance(e.x, e.y, g.sim.flies[sim.leader].x, g.sim.flies[sim.leader].y);
                    s.play(f.mixer, &s.croak, std.math.clamp(1.2 - d / 500, 0.15, 1), 1, pan);
                },
                .frog_miss => s.play(f.mixer, &s.miss, 0.6, 1, pan),
                .mound_denied => s.play(f.mixer, &s.denied, 0.7, 1, pan),
                .won => g.end_time = 0,
                .lost => {
                    s.play(f.mixer, &s.lose, 0.9, 1, 0);
                    g.end_time = 0;
                    buzz(60, 0.6);
                },
            }
        }
    }

    /// Where larva `i` of the mound sits: higher ones closer to the middle.
    fn larva(g: *const Game, i: usize) [2]f32 {
        const order = @as(f32, @floatFromInt(i)) / larva_count;
        const hx = hash(@intCast(i), 3, 901) - 0.5;
        return .{ g.sim.mound_x + hx * (100 - order * 60), g.sim.mound_y + 20 - order * 160 };
    }

    /// The mound lights from the base up: each larva with a spark, the
    /// chord one note higher every few, a last burst at the top.
    fn cascade(g: *Game, f: *const Frame) void {
        const lit: u32 = @intFromFloat(std.math.clamp(g.end_time / cascade_seconds, 0, 1) * larva_count);
        const per_note = larva_count / Sounds.chord_notes;
        while (g.larvae_lit < lit) : (g.larvae_lit += 1) {
            const p = g.larva(g.larvae_lit);
            g.sparks(p[0], p[1], 3, 70, draw.rgb(0.75, 1, 0.5));
            if (g.larvae_lit % per_note == 0) {
                f.sounds.chordNote(f.mixer, g.larvae_lit / per_note);
                buzz(12, 0.35);
            }
            if (g.larvae_lit + 1 == larva_count) {
                g.sparks(g.sim.mound_x, g.sim.mound_y - 150, 60, 380, draw.rgb(0.9, 1, 0.6));
                g.punch = 1;
                buzz(70, 1);
            }
        }
    }

    /// Fireflies called by a pulse draw a thin line of light as they come.
    fn leaveTrails(g: *Game, dt: f32) void {
        g.trail_timer -= dt;
        if (g.trail_timer > 0) return;
        g.trail_timer = 0.045;
        for (g.sim.flies[1..g.sim.fly_count]) |fly| {
            if (fly.state != .called) continue;
            g.particles.emit(.{
                .x = fly.x,
                .y = fly.y,
                .life = 0.5,
                .size_start = 7,
                .size_end = 1,
                .color_start = draw.color(0.75, 1, 0.4, 0.6),
                .color_end = draw.color(0.75, 1, 0.4, 0.6),
                .fade_out = 1,
                .blend = .additive,
            });
        }
    }

    fn sparks(g: *Game, x: f32, y: f32, count: u32, speed: f32, rgba: u32) void {
        for (0..count) |_| {
            const a = g.fx.range(0, std.math.tau);
            const v = g.fx.range(speed * 0.3, speed);
            g.particles.emit(.{
                .x = x,
                .y = y,
                .vx = @cos(a) * v,
                .vy = @sin(a) * v,
                .drag = 0.08,
                .life = g.fx.range(0.4, 0.9),
                .size_start = g.fx.range(8, 14),
                .size_end = 2,
                .color_start = rgba,
                .color_end = rgba,
                .fade_out = 0.7,
                .blend = .additive,
            });
        }
    }

    //
    // Drawing
    //

    fn paint(g: *Game, f: *const Frame, ui: *const Ui, level: *const levels.Level) void {
        const render = f.render;
        const art = f.art;
        const w: f32 = @floatFromInt(render.width);
        const h: f32 = @floatFromInt(render.height);

        // A pulse pushes the camera back for a moment.
        const zoom = g.zoom;
        g.zoom = zoom * (1 - 0.035 * juice.Ease.apply(.out_cubic, g.punch));
        defer g.zoom = zoom;

        // 1. The night, and everything as a silhouette against it.
        draw.clear(render, 0, 0, 0);
        draw.setScreenSpace(render);
        // Each region has its own night: bluer, more violet, greener.
        draw.sprite(render, art.sky, 0, 0, w, h, .{}, switch (level.region) {
            .vereda => draw.white,
            .campo_sujo => draw.rgb(1, 0.8, 1),
            .chapada => draw.rgb(0.75, 1, 0.95),
        });
        g.drawFar(f, 0.5, 150, 0.55);
        g.drawFar(f, 0.75, 210, 0.8);
        draw.setCamera(render, g.cam_x, g.cam_y, g.zoom);
        g.drawWorld(f, level, .silhouette);

        // 2. The light map.
        draw.beginTarget(render, art.light);
        draw.clear(render, 0, 0, 0);
        draw.setCamera(render, g.cam_x, g.cam_y, g.zoom);
        g.drawLights(f);
        draw.endTarget(render);

        // 3. The scene's colors, only where the light map has light.
        draw.beginTarget(render, art.color);
        draw.clear(render, 0, 0, 0);
        draw.setCamera(render, g.cam_x, g.cam_y, g.zoom);
        g.drawWorld(f, level, .color);
        draw.setScreenSpace(render);
        draw.setBlend(render, .multiply);
        draw.sprite(render, art.light, 0, 0, w, h, .{}, draw.white);
        draw.setBlend(render, .alpha);
        draw.endTarget(render);

        draw.setScreenSpace(render);
        draw.setBlend(render, .additive);
        draw.sprite(render, art.color, 0, 0, w, h, .{}, draw.white);

        // The owl's shadow falls on the ground, under the fireflies.
        draw.setCamera(render, g.cam_x, g.cam_y, g.zoom);
        draw.setBlend(render, .alpha);
        g.drawShadows(f);

        // 4. What shines by itself.
        draw.setBlend(render, .additive);
        g.drawShining(f);
        g.particles.draw(render, art.glow, &.{.{}}, .additive, 0, 0);
        draw.setBlend(render, .alpha);
        g.particles.draw(render, art.disc, &.{.{}}, .alpha, 0, 0);

        g.drawOwls(f);
        g.drawCanopy(f);
        draw.setScreenSpace(render);
        // Dark, the whole night closes in a little.
        if (g.sim.glow < 1) draw.rect(render, 0, 0, w, h, draw.color(0, 0.005, 0.03, (1 - g.sim.glow) * 0.3));
        if (g.flash > 0) draw.rect(render, 0, 0, w, h, draw.color(1, 0.25, 0.1, g.flash * 0.22));
        if (g.sim.level_index == 0) g.drawTutorial(f, ui);
    }

    /// Where the owl will land: a shadow that grows as it comes down.
    fn drawShadows(g: *Game, f: *const Frame) void {
        for (g.sim.owls[0..g.sim.owl_count]) |owl| {
            if (owl.state != .dive) continue;
            const t = 1 - owl.timer / sim.tune.owl_windup;
            const r = sim.tune.owl_strike_radius * (0.35 + 0.65 * t);
            draw.sprite(f.render, f.art.glow, owl.target_x - r * 1.7, owl.target_y - r * 1.7, owl.target_x + r * 1.7, owl.target_y + r * 1.7, .{}, draw.color(0, 0, 0.02, 0.5 + 0.5 * t));
            // Once the dive is set the shadow gets a hard edge: time to leave.
            if (t >= sim.tune.owl_track) draw.sprite(f.render, f.art.disc, owl.target_x - r, owl.target_y - r, owl.target_x + r, owl.target_y + r, .{}, draw.color(0, 0, 0.02, 0.55));
        }
    }

    /// The owls themselves, above everything on the ground.
    fn drawOwls(g: *Game, f: *const Frame) void {
        const render = f.render;
        const disc = f.art.disc;
        draw.setCamera(render, g.cam_x, g.cam_y, g.zoom);
        for (g.sim.owls[0..g.sim.owl_count]) |owl| {
            if (!g.visible(f, owl.x, owl.y, 200)) continue;
            // High up it is large and faint; coming down it sharpens.
            const low: f32 = switch (owl.state) {
                .patrol => 0,
                .dive => 1 - owl.timer / sim.tune.owl_windup,
                .strike => 1,
                .climb => owl.timer / sim.tune.owl_cooldown,
            };
            const size = 170 - 60 * low;
            const tint = draw.color(0.01, 0.014, 0.03, 0.45 + 0.5 * low);
            const flap = @sin(g.time * (2.2 + 4 * low) + owl.cx) * 0.25;
            draw.spriteRotated(render, disc, owl.x - size * 0.38, owl.y, size * 0.8, size * 0.3, -0.25 + flap, .{}, tint);
            draw.spriteRotated(render, disc, owl.x + size * 0.38, owl.y, size * 0.8, size * 0.3, 0.25 - flap, .{}, tint);
            draw.sprite(render, disc, owl.x - size * 0.16, owl.y - size * 0.22, owl.x + size * 0.16, owl.y + size * 0.26, .{}, tint);
            if (owl.state == .dive or owl.state == .strike) {
                draw.setBlend(render, .additive);
                draw.sprite(render, f.art.glow, owl.x - 14, owl.y - 20, owl.x - 2, owl.y - 8, .{}, draw.color(1, 0.75, 0.2, low));
                draw.sprite(render, f.art.glow, owl.x + 2, owl.y - 20, owl.x + 14, owl.y - 8, .{}, draw.color(1, 0.75, 0.2, low));
                draw.setBlend(render, .alpha);
            }
        }
    }

    /// The first level teaches by showing: a hand that drags, taps, or
    /// rests two fingers, each until the player has done it once.
    fn drawTutorial(g: *Game, f: *const Frame, ui: *const Ui) void {
        const s = &g.sim;
        if (s.outcome != .playing) return;
        const render = f.render;
        const w: f32 = @floatFromInt(render.width);
        const h: f32 = @floatFromInt(render.height);
        const y = h * 0.6;
        const cycle = @mod(g.time, 2.0) / 2.0;
        const finger = draw.color(0.85, 0.9, 1, 0.75);
        const me = s.flies[sim.leader];

        var frog_near = false;
        for (s.frogs[0..s.frog_count]) |frog| {
            if (sim.distance(frog.x, frog.y, me.x, me.y) < 330) frog_near = true;
        }
        var lost_far = false;
        for (s.flies[1..s.fly_count]) |fly| {
            if (fly.state != .lost) continue;
            const d = sim.distance(fly.x, fly.y, me.x, me.y);
            if (d > s.lightRadiusNow() + 60 and d < sim.tune.pulse_call_radius) lost_far = true;
        }

        if (g.flown < 260) {
            // A finger sliding up, a trail behind it.
            const t = juice.Ease.apply(.in_out_cubic, cycle);
            const fy = y + 40 - 90 * t;
            draw.rect(render, w / 2 - 3, fy, w / 2 + 3, y + 40, draw.color(0.85, 0.9, 1, 0.25));
            draw.sprite(render, f.art.disc, w / 2 - 22, fy - 22, w / 2 + 22, fy + 22, .{}, finger);
            ui.centered(w / 2, y + 62, 22, "arraste", ui_mod.text_color);
        } else if (frog_near and !g.did_dark) {
            // Two fingers resting.
            const press = 1 - 0.12 * @abs(@sin(g.time * 2));
            for ([_]f32{ -34, 34 }) |dx| {
                draw.sprite(render, f.art.disc, w / 2 + dx - 22 * press, y - 22 * press, w / 2 + dx + 22 * press, y + 22 * press, .{}, finger);
            }
            const label = if (@import("builtin").os.tag == .windows) "segure o botão direito" else "segure dois dedos";
            ui.centered(w / 2, y + 40, 22, label, ui_mod.text_color);
        } else if (lost_far and !g.did_pulse and !frog_near) {
            // A quick tap: a ring that opens.
            const r = 20 + 46 * cycle;
            draw.setBlend(render, .additive);
            draw.sprite(render, f.art.glow, w / 2 - r * 1.6, y - r * 1.6, w / 2 + r * 1.6, y + r * 1.6, .{}, draw.color(0.8, 1, 0.5, 0.6 * (1 - cycle)));
            draw.setBlend(render, .alpha);
            if (cycle < 0.25) draw.sprite(render, f.art.disc, w / 2 - 22, y - 22, w / 2 + 22, y + 22, .{}, finger);
            ui.centered(w / 2, y + 62, 22, "toque", ui_mod.text_color);
        }
    }

    /// A far layer of hills and trees, moving slower than the world
    /// (`parallax` below 1) and closer to the sky's color the farther it is.
    fn drawFar(g: *Game, f: *const Frame, parallax: f32, cell: f32, darkness: f32) void {
        const render = f.render;
        const art = f.art;
        const w: f32 = @floatFromInt(render.width);
        const h: f32 = @floatFromInt(render.height);
        const cx = g.cam_x * parallax;
        const cy = g.cam_y * parallax;
        draw.setCamera(render, cx, cy, g.zoom);
        const half_w = w / 2 / g.zoom + cell;
        const half_h = h / 2 / g.zoom + cell * 2;
        const tint = draw.color(0.012, 0.02, 0.045, darkness);
        const salt: u32 = @intFromFloat(parallax * 1000);
        var iy: i32 = @intFromFloat(@floor((cy - half_h) / cell));
        const iy_end: i32 = @intFromFloat(@floor((cy + half_h) / cell));
        while (iy <= iy_end) : (iy += 1) {
            var ix: i32 = @intFromFloat(@floor((cx - half_w) / cell));
            const ix_end: i32 = @intFromFloat(@floor((cx + half_w) / cell));
            while (ix <= ix_end) : (ix += 1) {
                const pick = hash(ix, iy, salt);
                if (pick > 0.42) continue;
                const x = (@as(f32, @floatFromInt(ix)) + hash(ix, iy, salt + 1)) * cell;
                const y = (@as(f32, @floatFromInt(iy)) + hash(ix, iy, salt + 2)) * cell;
                const size = cell * (0.5 + hash(ix, iy, salt + 3) * 0.6);
                if (pick < 0.24) {
                    // A tree: a thin trunk under a round crown, swaying.
                    const sway = @sin(g.time * 0.8 + x * 0.01) * size * 0.02;
                    draw.rect(render, x - size * 0.035, y - size, x + size * 0.035, y, tint);
                    draw.sprite(render, art.disc, x - size * 0.33 + sway, y - size * 1.3, x + size * 0.33 + sway, y - size * 0.7, .{}, tint);
                } else {
                    // A low hill or a clump of scrub.
                    draw.sprite(render, art.disc, x - size, y - size * 0.3, x + size, y + size * 0.3, .{}, tint);
                }
            }
        }
    }

    /// Dark leaves close to the eye, moving faster than the world.
    fn drawCanopy(g: *Game, f: *const Frame) void {
        const render = f.render;
        const w: f32 = @floatFromInt(render.width);
        const h: f32 = @floatFromInt(render.height);
        const parallax: f32 = 1.4;
        const cell: f32 = 420;
        const cx = g.cam_x * parallax;
        const cy = g.cam_y * parallax;
        draw.setCamera(render, cx, cy, g.zoom);
        const half_w = w / 2 / g.zoom + cell;
        const half_h = h / 2 / g.zoom + cell;
        const tint = draw.color(0.004, 0.007, 0.018, 0.9);
        var iy: i32 = @intFromFloat(@floor((cy - half_h) / cell));
        const iy_end: i32 = @intFromFloat(@floor((cy + half_h) / cell));
        while (iy <= iy_end) : (iy += 1) {
            var ix: i32 = @intFromFloat(@floor((cx - half_w) / cell));
            const ix_end: i32 = @intFromFloat(@floor((cx + half_w) / cell));
            while (ix <= ix_end) : (ix += 1) {
                if (hash(ix, iy, 77) > 0.3) continue;
                const x = (@as(f32, @floatFromInt(ix)) + hash(ix, iy, 78)) * cell;
                const y = (@as(f32, @floatFromInt(iy)) + hash(ix, iy, 79)) * cell;
                // A branch: a few long leaves fanning out, swaying together.
                const sway = @sin(g.time * 0.6 + x * 0.01) * 0.06;
                const base = hash(ix, iy, 80) * std.math.tau;
                for (0..5) |i| {
                    const a = base + (@as(f32, @floatFromInt(i)) - 2) * 0.42 + sway;
                    const len: f32 = 150 - @abs(@as(f32, @floatFromInt(i)) - 2) * 22;
                    draw.spriteRotated(render, f.art.disc, x + @cos(a) * len / 2, y + @sin(a) * len / 2, len, 26, a, .{}, tint);
                }
            }
        }
    }

    fn visible(g: *const Game, f: *const Frame, x: f32, y: f32, margin: f32) bool {
        const half_w = @as(f32, @floatFromInt(f.render.width)) / 2 / g.zoom + margin;
        const half_h = @as(f32, @floatFromInt(f.render.height)) / 2 / g.zoom + margin;
        return @abs(x - g.cam_x) < half_w and @abs(y - g.cam_y) < half_h;
    }

    /// The level's own layer: water, plants, frogs, the mound. Once as
    /// silhouettes, once in the colors light gives them.
    fn drawWorld(g: *Game, f: *const Frame, level: *const levels.Level, pass: Pass) void {
        const render = f.render;
        const art = f.art;
        const dark = draw.rgb(0.006, 0.01, 0.024);

        // Lit, the ground is a meadow; unlit it is just the night.
        if (pass == .color) {
            const reach = 2000;
            draw.rect(render, g.cam_x - reach, g.cam_y - reach, g.cam_x + reach, g.cam_y + reach, draw.rgb(0.085, 0.15, 0.07));
        }

        for (level.ponds) |p| {
            if (!g.visible(f, p.x, p.y, @max(p.rx, p.ry))) continue;
            if (pass == .silhouette) {
                // Even in the dark, still water holds a little of the sky.
                draw.sprite(render, art.disc, p.x - p.rx, p.y - p.ry, p.x + p.rx, p.y + p.ry, .{}, draw.color(0.05, 0.085, 0.15, 0.55));
            } else {
                draw.sprite(render, art.disc, p.x - p.rx, p.y - p.ry, p.x + p.rx, p.y + p.ry, .{}, draw.rgb(0.1, 0.42, 0.55));
                draw.sprite(render, art.disc, p.x - p.rx * 0.8, p.y - p.ry * 0.85, p.x + p.rx * 0.6, p.y + p.ry * 0.35, .{}, draw.rgb(0.18, 0.58, 0.68));
            }
        }

        // Frogs show only in the light.
        if (pass == .color) {
            for (g.sim.frogs[0..g.sim.frog_count]) |frog| {
                if (!g.visible(f, frog.x, frog.y, 60)) continue;
                // Swelling before the strike: the warning.
                const swell: f32 = if (frog.state == .windup) 1 + 0.4 * (1 - frog.timer / sim.tune.frog_windup) else 1;
                const r = 17 * swell;
                draw.sprite(render, art.disc, frog.x - r * 1.2, frog.y - r, frog.x + r * 1.2, frog.y + r, .{}, draw.rgb(0.42, 0.72, 0.2));
                draw.sprite(render, art.disc, frog.x - r * 0.7, frog.y - r * 0.2, frog.x + r * 0.7, frog.y + r * 0.9, .{}, draw.rgb(0.8, 0.88, 0.4));
            }
        }

        for (g.decor[0..g.decor_count]) |d| {
            if (!g.visible(f, d.x, d.y, d.size * 1.5)) continue;
            const sway = @sin(g.time * 1.1 + d.phase) * d.size * 0.025;
            switch (d.kind) {
                .tuft => {
                    const tint = if (pass == .silhouette) dark else draw.rgb(0.3, 0.6, 0.18);
                    for (0..3) |i| {
                        const a = (@as(f32, @floatFromInt(i)) - 1) * 0.5 + sway * 0.08 - std.math.pi / 2.0;
                        draw.spriteRotated(render, art.disc, d.x + @cos(a) * d.size / 2, d.y + @sin(a) * d.size / 2, d.size, 4, a, .{}, tint);
                    }
                },
                .bush => {
                    const tint = if (pass == .silhouette) dark else draw.rgb(0.16, 0.44, 0.15);
                    const s = d.size;
                    draw.sprite(render, art.disc, d.x - s + sway, d.y - s * 0.9, d.x + s * 0.3 + sway, d.y, .{}, tint);
                    draw.sprite(render, art.disc, d.x - s * 0.3 - sway, d.y - s * 1.2, d.x + s - sway, d.y, .{}, tint);
                    if (pass == .color) draw.sprite(render, art.disc, d.x - s * 0.1, d.y - s * 1.05, d.x + s * 0.6, d.y - s * 0.45, .{}, draw.rgb(0.3, 0.6, 0.2));
                },
                .buriti => {
                    // A tall bare trunk and a round fan of fronds.
                    const s = d.size;
                    const trunk = if (pass == .silhouette) dark else draw.rgb(0.42, 0.3, 0.18);
                    const frond = if (pass == .silhouette) dark else draw.rgb(0.16, 0.46, 0.18);
                    draw.rect(render, d.x - s * 0.022, d.y - s, d.x + s * 0.022, d.y, trunk);
                    const tx = d.x + sway * 0.6;
                    const ty = d.y - s;
                    for (0..11) |i| {
                        const fi: f32 = @floatFromInt(i);
                        // All around, the lower ones longer and drooping.
                        const a = -std.math.pi / 2.0 + (fi - 5) * 0.5 + sway * 0.01;
                        const len = s * (0.3 + 0.012 * @abs(fi - 5) * @abs(fi - 5));
                        draw.spriteRotated(render, art.disc, tx + @cos(a) * len / 2, ty + @sin(a) * len / 2, len, s * 0.06, a, .{}, frond);
                    }
                    draw.sprite(render, art.disc, tx - s * 0.05, ty - s * 0.05, tx + s * 0.05, ty + s * 0.05, .{}, trunk);
                },
                .canela => {
                    // Forked grey stems, each ending in a tuft of stiff leaves.
                    const s = d.size;
                    const stem = if (pass == .silhouette) dark else draw.rgb(0.3, 0.27, 0.24);
                    const leaf = if (pass == .silhouette) dark else draw.rgb(0.22, 0.46, 0.36);
                    for (0..3) |k| {
                        const fk: f32 = @floatFromInt(k);
                        const lean = (fk - 1) * 0.42 + @sin(d.phase + fk) * 0.12;
                        const a = -std.math.pi / 2.0 + lean;
                        const len = s * (0.75 + 0.2 * @sin(d.phase * 3 + fk * 2));
                        const ex = d.x + @cos(a) * len;
                        const ey = d.y + @sin(a) * len;
                        draw.spriteRotated(render, art.disc, (d.x + ex) / 2, (d.y + ey) / 2, len, s * 0.09, a, .{}, stem);
                        for (0..6) |i| {
                            const la = a + (@as(f32, @floatFromInt(i)) - 2.5) * 0.36 + sway * 0.02;
                            const ll = s * 0.38;
                            draw.spriteRotated(render, art.disc, ex + @cos(la) * ll / 2, ey + @sin(la) * ll / 2, ll, 3, la, .{}, leaf);
                        }
                        // Its violet flower, when the light finds it.
                        if (pass == .color and k == 1) draw.sprite(render, art.disc, ex - 4, ey - s * 0.3 - 4, ex + 4, ey - s * 0.3 + 4, .{}, draw.rgb(0.62, 0.4, 0.85));
                    }
                },
                .pequi => {
                    // A crooked trunk under a wide, lumpy crown, with fruit.
                    const s = d.size;
                    const trunk = if (pass == .silhouette) dark else draw.rgb(0.34, 0.24, 0.15);
                    const crown = if (pass == .silhouette) dark else draw.rgb(0.2, 0.42, 0.14);
                    const bend = @sin(d.phase) * s * 0.12;
                    draw.spriteRotated(render, art.disc, d.x + bend / 2, d.y - s * 0.25, s * 0.55, s * 0.09, -std.math.pi / 2.0 + bend / s, .{}, trunk);
                    draw.spriteRotated(render, art.disc, d.x + bend - s * 0.14, d.y - s * 0.62, s * 0.42, s * 0.06, -2.1, .{}, trunk);
                    draw.spriteRotated(render, art.disc, d.x + bend + s * 0.14, d.y - s * 0.62, s * 0.42, s * 0.06, -1.05, .{}, trunk);
                    for (0..5) |i| {
                        const fi: f32 = @floatFromInt(i);
                        const cx = d.x + bend + (fi - 2) * s * 0.2 + sway;
                        const cy = d.y - s * (0.86 + 0.1 * @sin(d.phase * 2 + fi * 1.9));
                        const r = s * (0.2 + 0.05 * @sin(d.phase + fi));
                        draw.sprite(render, art.disc, cx - r, cy - r * 0.8, cx + r, cy + r * 0.8, .{}, crown);
                        if (pass == .color and i % 2 == 0) draw.sprite(render, art.disc, cx - 5, cy + r * 0.3, cx + 5, cy + r * 0.3 + 10, .{}, draw.rgb(0.85, 0.75, 0.2));
                    }
                },
                .tree => {
                    const s = d.size;
                    const trunk = if (pass == .silhouette) dark else draw.rgb(0.45, 0.28, 0.15);
                    const crown = if (pass == .silhouette) dark else draw.rgb(0.14, 0.42, 0.16);
                    draw.rect(render, d.x - s * 0.04, d.y - s, d.x + s * 0.04, d.y, trunk);
                    draw.sprite(render, art.disc, d.x - s * 0.36 + sway, d.y - s * 1.3, d.x + s * 0.36 + sway, d.y - s * 0.62, .{}, crown);
                    if (pass == .color) draw.sprite(render, art.disc, d.x - s * 0.2 + sway, d.y - s * 1.24, d.x + s * 0.24 + sway, d.y - s * 0.86, .{}, draw.rgb(0.24, 0.56, 0.2));
                },
            }
        }

        // Webs: thin threads that only a strong light picks out, and the
        // spider in the middle.
        if (pass == .color) {
            for (g.sim.webs[0..g.sim.web_count]) |web| {
                if (!g.visible(f, web.x, web.y, web.r)) continue;
                g.drawWeb(f, web, draw.rgb(0.3, 0.32, 0.36));
                draw.sprite(render, art.disc, web.x - 7, web.y - 9, web.x + 7, web.y + 9, .{}, draw.rgb(0.25, 0.12, 0.1));
            }
        }

        // The maned wolf: long legs, big ears, walking across.
        if (g.sim.wolf.active) {
            const wolf = g.sim.wolf;
            const path = g.sim.wolf_path.?;
            const dir: f32 = if (path.x1 > path.x0) 1 else -1;
            const fur = if (pass == .silhouette) dark else draw.rgb(0.8, 0.38, 0.14);
            const legs = if (pass == .silhouette) dark else draw.rgb(0.12, 0.08, 0.07);
            const x = wolf.x;
            const y = wolf.y;
            for ([_]f32{ -26, -14, 16, 28 }, 0..) |lx, i| {
                const swing = @sin(g.time * 7 + @as(f32, @floatFromInt(i)) * 1.6) * 7;
                draw.rect(render, x + lx * dir + swing - 3, y - 52, x + lx * dir + swing + 3, y, legs);
            }
            draw.sprite(render, art.disc, x - 44, y - 82, x + 44, y - 44, .{}, fur);
            draw.sprite(render, art.disc, x + dir * 30 - 18, y - 108, x + dir * 30 + 18, y - 72, .{}, fur);
            draw.spriteRotated(render, art.disc, x + dir * 24, y - 116, 26, 10, -1.2, .{}, fur);
            draw.spriteRotated(render, art.disc, x + dir * 38, y - 116, 26, 10, -1.9, .{}, fur);
            draw.spriteRotated(render, art.disc, x - dir * 50, y - 60, 40, 9, dir * 0.9, .{}, fur);
        }

        // The termite mound: a tall rounded tower.
        const mx = g.sim.mound_x;
        const my = g.sim.mound_y;
        const body = if (pass == .silhouette) dark else draw.rgb(0.62, 0.4, 0.2);
        draw.sprite(render, art.disc, mx - 46, my - 150, mx + 46, my + 20, .{}, body);
        draw.sprite(render, art.disc, mx - 62, my - 60, mx + 62, my + 40, .{}, body);
        if (pass == .color) draw.sprite(render, art.disc, mx - 30, my - 135, mx + 14, my - 30, .{}, draw.rgb(0.78, 0.54, 0.3));
    }

    /// A web's threads: spokes from the middle and rings across them.
    fn drawWeb(g: *Game, f: *const Frame, web: sim.Web, tint: u32) void {
        _ = g;
        const spokes = 8;
        for (0..spokes) |i| {
            const a = @as(f32, @floatFromInt(i)) / spokes * std.math.tau + web.x;
            draw.spriteRotated(f.render, f.art.disc, web.x + @cos(a) * web.r / 2, web.y + @sin(a) * web.r / 2, web.r, 1.6, a, .{}, tint);
            // Rings: short threads from spoke to spoke.
            const b = a + std.math.tau / @as(f32, spokes);
            for ([_]f32{ 0.35, 0.62, 0.9 }) |k| {
                const x0 = web.x + @cos(a) * web.r * k;
                const y0 = web.y + @sin(a) * web.r * k;
                const x1 = web.x + @cos(b) * web.r * k;
                const y1 = web.y + @sin(b) * web.r * k;
                const len = @sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
                draw.spriteRotated(f.render, f.art.disc, (x0 + x1) / 2, (y0 + y1) / 2, len, 1.4, std.math.atan2(y1 - y0, x1 - x0), .{}, tint);
            }
        }
    }

    /// How lit the mound is: 0 before the win, rising to 1 in the cascade.
    fn moundLight(g: *const Game) f32 {
        if (g.sim.outcome != .won) return 0;
        return juice.Ease.apply(.in_out_cubic, std.math.clamp(g.end_time / (cascade_seconds + 0.6), 0, 1));
    }

    /// Everything that gives light, into the light map.
    fn drawLights(g: *Game, f: *const Frame) void {
        const render = f.render;
        const glow_tex = f.art.glow;
        const s = &g.sim;
        draw.setBlend(render, .additive);

        // The swarm: one wide pool of light, and each firefly's own.
        if (s.swarm > 0 and s.glow > 0) {
            var cx: f32 = 0;
            var cy: f32 = 0;
            for (s.flies[0..s.fly_count]) |fly| {
                if (fly.state != .swarm) continue;
                cx += fly.x;
                cy += fly.y;
                draw.sprite(render, glow_tex, fly.x - 44, fly.y - 44, fly.x + 44, fly.y + 44, .{}, draw.color(0.8, 1, 0.45, 0.16 * s.glow));
            }
            const n: f32 = @floatFromInt(s.swarm);
            cx /= n;
            cy /= n;
            const r = s.lightRadiusNow() * 1.45;
            draw.sprite(render, f.art.pool, cx - r, cy - r, cx + r, cy + r, .{}, draw.color(1, 1, 0.8, s.glow));
        }

        // A pulse: a flash that runs outward and fades.
        if (s.since_pulse < 1.4) {
            const t = s.since_pulse / 1.4;
            const r = 200 + 1500 * juice.Ease.apply(.out_cubic, t);
            const a = (1 - t) * (1 - t);
            draw.sprite(render, glow_tex, s.pulse_x - r, s.pulse_y - r, s.pulse_x + r, s.pulse_y + r, .{}, draw.color(0.95, 1, 0.8, a));
            // Flat light too: for an instant the whole view is seen.
            const view = 2000;
            draw.rect(render, g.cam_x - view, g.cam_y - view, g.cam_x + view, g.cam_y + view, draw.color(0.9, 1, 0.8, a * 0.35));
        }

        // Lost fireflies light a little ground of their own.
        for (s.flies[0..s.fly_count]) |fly| {
            if (fly.state != .lost and fly.state != .called and fly.state != .stuck) continue;
            if (!g.visible(f, fly.x, fly.y, 60)) continue;
            const b: f32 = if (fly.state == .lost) sim.blink(fly.pattern, fly.phase, s.time) else 1;
            draw.sprite(render, glow_tex, fly.x - 38, fly.y - 38, fly.x + 38, fly.y + 38, .{}, draw.color(0.8, 1, 0.45, 0.5 * b));
        }

        const lit = g.moundLight();
        if (lit > 0) {
            const r = 120 + 900 * lit;
            draw.sprite(render, glow_tex, s.mound_x - r, s.mound_y - 60 - r, s.mound_x + r, s.mound_y - 60 + r, .{}, draw.color(0.9, 1, 0.6, lit));
        }
        draw.setBlend(render, .alpha);
    }

    /// The fireflies themselves, the frog's eyes and tongue, the larvae.
    fn drawShining(g: *Game, f: *const Frame) void {
        const render = f.render;
        const glow_tex = f.art.glow;
        const disc = f.art.disc;
        const s = &g.sim;

        for (s.frogs[0..s.frog_count]) |frog| {
            if (!g.visible(f, frog.x, frog.y, 300)) continue;
            // Its eyes catch the light when it is about to strike, or awake.
            const eyes: f32 = if (frog.state == .windup) 1 else if (frog.alert > 0) 0.55 else 0;
            if (eyes > 0) {
                draw.sprite(render, glow_tex, frog.x - 13, frog.y - 15, frog.x - 1, frog.y - 3, .{}, draw.color(1, 0.85, 0.3, eyes));
                draw.sprite(render, glow_tex, frog.x + 1, frog.y - 15, frog.x + 13, frog.y - 3, .{}, draw.color(1, 0.85, 0.3, eyes));
            }
            if (frog.state == .strike) {
                const dx = frog.tongue_x - frog.x;
                const dy = frog.tongue_y - frog.y;
                const len = @sqrt(dx * dx + dy * dy);
                draw.spriteRotated(render, disc, frog.x + dx / 2, frog.y + dy / 2, len, 5, std.math.atan2(dy, dx), .{}, draw.color(1, 0.45, 0.5, 0.9));
            }
        }

        // The light of the ones just taken: pulled away, shrinking, gone.
        for (g.ghosts) |ghost| {
            if (ghost.t >= 1) continue;
            const k = ghost.t * ghost.t * ghost.t;
            for (0..6) |i| {
                // A short tail behind the light.
                const back = std.math.clamp(k - @as(f32, @floatFromInt(i)) * 0.06, 0, 1);
                const x = ghost.x + (ghost.to_x - ghost.x) * back;
                const y = ghost.y + (ghost.to_y - ghost.y) * back;
                const r = (14 - @as(f32, @floatFromInt(i)) * 1.8) * (1 - ghost.t * 0.6);
                draw.sprite(render, glow_tex, x - r, y - r, x + r, y + r, .{}, draw.color(1, 0.75, 0.35, (1 - ghost.t) * (1 - @as(f32, @floatFromInt(i)) / 6)));
            }
        }

        // Webs shown by a pulse, or given away by who is stuck in them.
        for (s.webs[0..s.web_count]) |web| {
            if (!g.visible(f, web.x, web.y, web.r)) continue;
            const shown = @max(std.math.clamp(web.seen, 0, 1), if (web.stuck > 0) @as(f32, 0.8) else 0);
            if (shown <= 0) continue;
            const torn: f32 = if (web.torn > 0) 0.35 else 1;
            g.drawWeb(f, web, draw.color(0.75, 0.85, 1, 0.5 * shown * torn));
            if (web.stuck > 0 and web.scared == 0) {
                // The spider's eyes, when it has something to eat.
                draw.sprite(render, glow_tex, web.x - 9, web.y - 9, web.x + 9, web.y + 9, .{}, draw.color(1, 0.25, 0.2, 0.9));
            }
        }

        // The maned wolf's eyes shine back.
        if (s.wolf.active) {
            const path = s.wolf_path.?;
            const dir: f32 = if (path.x1 > path.x0) 1 else -1;
            draw.sprite(render, glow_tex, s.wolf.x + dir * 34 - 7, s.wolf.y - 97, s.wolf.x + dir * 34 + 7, s.wolf.y - 83, .{}, draw.color(1, 0.8, 0.4, 0.9));
        }

        // Many halos on one spot would burn to white: each dims as they crowd.
        const crowd = @min(1.0, 4.5 / @sqrt(@as(f32, @floatFromInt(@max(s.swarm, 1)))));
        for (s.flies[0..s.fly_count], 0..) |sim_fly, i| {
            // Drawn a little ahead, by the time the simulation has not run
            // yet: steady motion on screens that are not 60 or 120 Hz.
            var fly = sim_fly;
            if (fly.state != .stuck and !g.paused and g.hit_stop <= 0) {
                fly.x += fly.vx * g.accumulator;
                fly.y += fly.vy * g.accumulator;
            }
            if (!g.visible(f, fly.x, fly.y, 40)) continue;
            switch (fly.state) {
                .lost, .called => {
                    const b: f32 = if (fly.state == .called) 1 else sim.blink(fly.pattern, fly.phase, s.time);
                    draw.sprite(render, glow_tex, fly.x - 15, fly.y - 15, fly.x + 15, fly.y + 15, .{}, draw.color(0.75, 1, 0.35, 0.75 * b));
                    draw.sprite(render, disc, fly.x - 2.5, fly.y - 2.5, fly.x + 2.5, fly.y + 2.5, .{}, draw.color(0.95, 1, 0.7, 0.25 + 0.75 * b));
                },
                .swarm => {
                    const is_leader = i == sim.leader;
                    // Each one flickers a little; in the dark only an ember is left.
                    const flicker = 0.85 + 0.15 * @sin(s.time * 9 + fly.phase * 7);
                    const halo: f32 = if (is_leader) 30 else 17;
                    const core: f32 = if (is_leader) 4.5 else 2.8;
                    const ember: f32 = if (is_leader) 0.4 else 0.16;
                    draw.sprite(render, glow_tex, fly.x - halo, fly.y - halo, fly.x + halo, fly.y + halo, .{}, draw.color(0.78, 1, 0.3, 0.8 * s.glow * flicker * (if (is_leader) 1 else crowd)));
                    draw.sprite(render, disc, fly.x - core, fly.y - core, fly.x + core, fly.y + core, .{}, draw.color(1, 1, 0.75, ember + (1 - ember) * s.glow));
                },
                .stuck => {
                    // Struggling: a nervous flicker.
                    const b = 0.45 + 0.55 * @abs(@sin(s.time * 13 + fly.phase * 5));
                    draw.sprite(render, glow_tex, fly.x - 14, fly.y - 14, fly.x + 14, fly.y + 14, .{}, draw.color(1, 0.9, 0.4, 0.7 * b));
                    draw.sprite(render, disc, fly.x - 2.5, fly.y - 2.5, fly.x + 2.5, fly.y + 2.5, .{}, draw.color(1, 1, 0.7, b));
                },
                .none, .taken => {},
            }
        }

        // The mound's larvae light up one after another, from the base up.
        const lit = g.moundLight();
        if (g.sim.outcome == .won) {
            for (0..larva_count) |i| {
                const order = @as(f32, @floatFromInt(i)) / larva_count;
                const on = std.math.clamp((g.end_time - order * cascade_seconds) / 0.35, 0, 1);
                if (on <= 0) continue;
                const p = g.larva(i);
                const lx = p[0];
                const ly = p[1];
                const twinkle = 0.75 + 0.25 * @sin(g.time * 6 + @as(f32, @floatFromInt(i)));
                const size = 16 * juice.Ease.apply(.out_back, on);
                draw.sprite(render, glow_tex, lx - size, ly - size, lx + size, ly + size, .{}, draw.color(0.65, 1, 0.5, twinkle));
                draw.sprite(render, disc, lx - 2, ly - 2, lx + 2, ly + 2, .{}, draw.color(0.9, 1, 0.8, on));
            }
            draw.sprite(render, glow_tex, s.mound_x - 260, s.mound_y - 320, s.mound_x + 260, s.mound_y + 200, .{}, draw.color(0.6, 1, 0.4, 0.3 * lit));
        }
    }

    fn drawHud(g: *Game, f: *const Frame, ui: *const Ui, level: *const levels.Level, pause_x: f32, pause_y: f32) void {
        const render = f.render;
        const w: f32 = @floatFromInt(render.width);
        const h: f32 = @floatFromInt(render.height);
        const top = f.input.safe_area.top + 14;
        const s = &g.sim;
        var buffer: [64]u8 = undefined;
        draw.setScreenSpace(render);
        draw.setBlend(render, .alpha);

        // The swarm, and what the mound asks for.
        const enough = s.swarm >= s.need;
        const count = std.fmt.bufPrint(&buffer, "{d} / {d}", .{ s.swarm, s.need }) catch "";
        const size: f32 = 30 + 9 * juice.Ease.apply(.out_cubic, g.count_bump);
        const tw = ui.width(size, count);
        const tint = if (enough) ui_mod.light_color else ui_mod.text_color;
        draw.sprite(render, f.art.glow, w / 2 - tw / 2 - 40, top - 4, w / 2 - tw / 2 - 2, top + 34, .{}, draw.color(0.8, 1, 0.4, 0.9));
        ui.text(w / 2 - tw / 2 + 6, top, size, count, tint);

        // The pulse recharging.
        const ready = 1 - s.pulse_cooldown / sim.tune.pulse_cooldown;
        const bar_w: f32 = 120;
        draw.rect(render, w / 2 - bar_w / 2, top + 44, w / 2 + bar_w / 2, top + 48, draw.color(1, 1, 1, 0.12));
        draw.rect(render, w / 2 - bar_w / 2, top + 44, w / 2 - bar_w / 2 + bar_w * ready, top + 48, draw.color(0.8, 1, 0.45, if (ready >= 1) 0.8 else 0.4));

        // The level's name, for a moment.
        if (s.outcome == .playing and g.time < 4 and !g.paused) {
            const a = std.math.clamp(@min(g.time, 4 - g.time), 0, 1);
            const number = std.fmt.bufPrint(&buffer, "{d}", .{s.level_index + 1}) catch "";
            ui.centered(w / 2, h * 0.24, 22, number, draw.color(0.6, 0.66, 0.78, a));
            ui.centered(w / 2, h * 0.24 + 28, 40, level.name, draw.color(0.85, 0.9, 1, a));
        }

        if (s.outcome == .playing and !g.paused) {
            // Pause: two bars.
            const held = ui.held(pause_x, pause_y, ui.touch, ui.touch);
            const a: f32 = if (held) 0.9 else 0.5;
            draw.rect(render, pause_x - 11, pause_y - 13, pause_x - 3, pause_y + 13, draw.color(0.85, 0.9, 1, a));
            draw.rect(render, pause_x + 3, pause_y - 13, pause_x + 11, pause_y + 13, draw.color(0.85, 0.9, 1, a));

            // With enough fireflies, a glow at the screen's edge points to the mound.
            if (enough and !g.visible(f, s.mound_x, s.mound_y, -40)) {
                const dx = s.mound_x - g.cam_x;
                const dy = s.mound_y - g.cam_y;
                const k = @min((w / 2 - 34) / (@abs(dx) + 0.001), (h / 2 - 90) / (@abs(dy) + 0.001));
                const px = w / 2 + dx * k;
                const py = h / 2 + dy * k;
                const beat = 0.6 + 0.4 * @sin(g.time * 4);
                draw.setBlend(render, .additive);
                draw.sprite(render, f.art.glow, px - 30, py - 30, px + 30, py + 30, .{}, draw.color(1, 0.75, 0.35, beat));
                draw.setBlend(render, .alpha);
            }
        }
        if (pequi.internal and g.robot_on) ui.text(12, top, 14, "robô", draw.rgb(1, 0.6, 0.3));
    }
};

/// A short buzz on phones (nothing elsewhere).
fn buzz(milliseconds: u32, strength: f32) void {
    pequi.platformApi().vibrate(milliseconds, strength);
}

/// Keeps the volumes for next time; a failure only goes to the log.
pub fn saveVolumes(volumes: *const pequi.audio.Volumes) void {
    volumes.save(pequi.platformApi()) catch |err| pequi.log("lume: volumes not saved: {s}", .{@errorName(err)});
}

const menu_theme: pequi.ui.Theme = .{
    .text = draw.rgb(0.85, 0.9, 1),
    .dim = draw.rgb(0.6, 0.66, 0.78),
    .title = draw.rgb(0.85, 1, 0.5),
    .accent = draw.rgb(0.82, 1, 0.45),
    .item = draw.color(0.75, 1, 0.45, 0.08),
    .item_focused = draw.color(0.75, 1, 0.45, 0.2),
    .track = draw.color(1, 1, 1, 0.16),
    .backdrop = draw.color(0, 0.01, 0.03, 0.72),
    .text_size = 24,
    .title_size = 44,
};

pub const theme = menu_theme;

/// A steady pseudo-random number in [0, 1) for a grid cell.
fn hash(ix: i32, iy: i32, salt: u32) f32 {
    var x: u32 = @as(u32, @bitCast(ix)) *% 0x27d4eb2d +% @as(u32, @bitCast(iy)) *% 0x165667b1 +% salt *% 0x9e3779b9;
    x ^= x >> 15;
    x *%= 0x2c1b3c6d;
    x ^= x >> 12;
    x *%= 0x297a2d39;
    x ^= x >> 15;
    return @as(f32, @floatFromInt(x >> 8)) / @as(f32, 1 << 24);
}

test "hash stays in [0, 1) and differs between cells" {
    var sum: f32 = 0;
    for (0..100) |i| {
        const v = hash(@intCast(i), -3, 5);
        try std.testing.expect(v >= 0 and v < 1);
        sum += v;
    }
    try std.testing.expect(sum > 30 and sum < 70);
}
