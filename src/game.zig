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

pub const Frame = struct {
    input: *pequi.Input,
    render: *pequi.RenderCommands,
    art: *const Art,
    sounds: *Sounds,
    mixer: *pequi.audio.Mixer,
};

const DecorKind = enum(u8) { tree, bush, tuft };

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
    particles: juice.Particles(700),
    fx: juice.Rng,
    decor: [max_decor]Decor,
    decor_count: u32,
    /// Seconds since the level ended.
    end_time: f32,
    /// The red blink when a predator takes one, fading from 1.
    flash: f32,
    robot_on: bool,
    stress: bool,
    perf: Perf,

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
        g.plant(level);
    }

    /// Scatters the vegetation, away from the water, the start and the mound.
    fn plant(g: *Game, level: *const levels.Level) void {
        var rng: juice.Rng = .{ .state = level.seed ^ 0x2545f491 };
        g.decor_count = 0;
        const area = level.width * level.height;
        const wanted = [_]struct { DecorKind, f32, f32, f32 }{
            // kind, one per this many square units, smallest, largest
            .{ .tree, 52000, 110, 190 },
            .{ .bush, 42000, 26, 46 },
            .{ .tuft, 15000, 10, 20 },
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

    pub fn update(g: *Game, f: *const Frame) void {
        const api = pequi.platformApi();
        const t0 = api.perfCounter();
        const w: f32 = @floatFromInt(f.render.width);
        const h: f32 = @floatFromInt(f.render.height);
        const dt = @min(f.input.dt, 0.05);
        g.time += dt;

        const pointer = g.reader.read(f.input);
        if (pequi.internal) {
            if (pointer.robot) g.robot_on = !g.robot_on;
            if (pointer.fill) g.fill();
        }

        var controls: sim.Controls = .{
            .target_x = g.cam_x + (pointer.x - w / 2) / g.zoom,
            .target_y = g.cam_y + (pointer.y - h / 2) / g.zoom,
            .guiding = pointer.down,
            .pulse = pointer.tap,
            .dark = pointer.dark,
        };

        if (g.sim.outcome != .playing) {
            g.end_time += dt;
            if (g.end_time > 1.6 and pointer.tap) {
                g.start(g.sim.level_index);
                return;
            }
        }

        var events: sim.Events = .{};
        g.accumulator += dt;
        var steps: u32 = 0;
        while (g.accumulator >= sim.dt and steps < max_steps_per_frame) : (steps += 1) {
            g.accumulator -= sim.dt;
            if (g.robot_on) {
                const robot: Robot = .{ .goal = levels.get(g.sim.level_index).stars[2] };
                controls = robot.think(&g.sim);
            }
            g.sim.step(controls, &events);
            controls.pulse = false;
        }
        if (steps == max_steps_per_frame) g.accumulator = 0;
        g.react(f, &events);

        // The camera looks a little ahead of the leader, and backs away as
        // the swarm grows.
        const me = g.sim.flies[sim.leader];
        g.cam_x = juice.approach(g.cam_x, me.x + me.vx * 0.4, 0.22, dt);
        g.cam_y = juice.approach(g.cam_y, me.y + me.vy * 0.4, 0.22, dt);
        const wanted_zoom = std.math.clamp(1.0 - (@as(f32, @floatFromInt(g.sim.swarm)) - 8) * 0.0022, 0.72, 1.0);
        g.zoom = juice.approach(g.zoom, wanted_zoom, 0.8, dt);
        const half_w = w / 2 / g.zoom;
        const half_h = h / 2 / g.zoom;
        g.cam_x = if (g.sim.width > half_w * 2) std.math.clamp(g.cam_x, half_w, g.sim.width - half_w) else g.sim.width / 2;
        g.cam_y = if (g.sim.height > half_h * 2) std.math.clamp(g.cam_y, half_h, g.sim.height - half_h) else g.sim.height / 2;

        g.particles.update(dt);
        g.flash = @max(0, g.flash - dt * 3.5);
        f.sounds.update(f.mixer, dt);

        const t1 = api.perfCounter();
        g.paint(f);
        const t2 = api.perfCounter();
        if (pequi.internal and g.stress) g.measure(api, t1 -% t0, t2 -% t1);
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
                },
                .strayed => s.play(f.mixer, &s.strayed, 0.5, 1, pan),
                .pulse => {
                    s.play(f.mixer, &s.pulse, 0.9, 1, 0);
                    g.sparks(e.x, e.y, 30, 320, draw.rgb(0.9, 1, 0.6));
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
                .won => {
                    s.startChord();
                    g.end_time = 0;
                },
                .lost => {
                    s.play(f.mixer, &s.lose, 0.9, 1, 0);
                    g.end_time = 0;
                },
            }
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

    fn paint(g: *Game, f: *const Frame) void {
        const render = f.render;
        const art = f.art;
        const w: f32 = @floatFromInt(render.width);
        const h: f32 = @floatFromInt(render.height);
        const level = levels.get(g.sim.level_index);

        // 1. The night, and everything as a silhouette against it.
        draw.clear(render, 0, 0, 0);
        draw.setScreenSpace(render);
        draw.sprite(render, art.sky, 0, 0, w, h, .{}, draw.white);
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

        // 4. What shines by itself.
        draw.setCamera(render, g.cam_x, g.cam_y, g.zoom);
        g.drawShining(f);
        g.particles.draw(render, art.glow, &.{.{}}, .additive, 0, 0);
        draw.setBlend(render, .alpha);

        g.drawCanopy(f);
        draw.setScreenSpace(render);
        if (g.flash > 0) draw.rect(render, 0, 0, w, h, draw.color(1, 0.25, 0.1, g.flash * 0.22));
        g.drawHud(f, level);
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

        // The termite mound: a tall rounded tower.
        const mx = g.sim.mound_x;
        const my = g.sim.mound_y;
        const body = if (pass == .silhouette) dark else draw.rgb(0.62, 0.4, 0.2);
        draw.sprite(render, art.disc, mx - 46, my - 150, mx + 46, my + 20, .{}, body);
        draw.sprite(render, art.disc, mx - 62, my - 60, mx + 62, my + 40, .{}, body);
        if (pass == .color) draw.sprite(render, art.disc, mx - 30, my - 135, mx + 14, my - 30, .{}, draw.rgb(0.78, 0.54, 0.3));
    }

    /// How lit the mound is: 0 before the win, rising to 1 in the cascade.
    fn moundLight(g: *const Game) f32 {
        if (g.sim.outcome != .won) return 0;
        return juice.Ease.apply(.out_cubic, std.math.clamp(g.end_time / 3.2, 0, 1));
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
            if (fly.state != .lost and fly.state != .called) continue;
            if (!g.visible(f, fly.x, fly.y, 60)) continue;
            const b: f32 = if (fly.state == .called) 1 else sim.blink(fly.pattern, fly.phase, s.time);
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

        // Many halos on one spot would burn to white: each dims as they crowd.
        const crowd = @min(1.0, 4.5 / @sqrt(@as(f32, @floatFromInt(@max(s.swarm, 1)))));
        for (s.flies[0..s.fly_count], 0..) |fly, i| {
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
                .none, .taken => {},
            }
        }

        // The mound's larvae light up one after another, from the base up.
        const lit = g.moundLight();
        if (g.sim.outcome == .won) {
            for (0..larva_count) |i| {
                const order = @as(f32, @floatFromInt(i)) / larva_count;
                const on = std.math.clamp((g.end_time - order * 2.6) / 0.35, 0, 1);
                if (on <= 0) continue;
                const hx = hash(@intCast(i), 3, 901) - 0.5;
                // Higher larvae sit closer to the middle: the tower narrows.
                const lx = s.mound_x + hx * (100 - order * 60);
                const ly = s.mound_y + 20 - order * 160;
                const twinkle = 0.75 + 0.25 * @sin(g.time * 6 + @as(f32, @floatFromInt(i)));
                const size = 16 * juice.Ease.apply(.out_back, on);
                draw.sprite(render, glow_tex, lx - size, ly - size, lx + size, ly + size, .{}, draw.color(0.65, 1, 0.5, twinkle));
                draw.sprite(render, disc, lx - 2, ly - 2, lx + 2, ly + 2, .{}, draw.color(0.9, 1, 0.8, on));
            }
            draw.sprite(render, glow_tex, s.mound_x - 260, s.mound_y - 320, s.mound_x + 260, s.mound_y + 200, .{}, draw.color(0.6, 1, 0.4, 0.3 * lit));
        }
    }

    fn drawHud(g: *Game, f: *const Frame, level: *const levels.Level) void {
        const render = f.render;
        const w: f32 = @floatFromInt(render.width);
        const h: f32 = @floatFromInt(render.height);
        const top = f.input.safe_area.top + 18;
        const s = &g.sim;
        var buffer: [64]u8 = undefined;

        // The swarm, and what the mound asks for.
        const enough = s.swarm >= s.need;
        const count = std.fmt.bufPrint(&buffer, "{d} / {d}", .{ s.swarm, s.need }) catch "";
        const size: f32 = 26;
        const tw = draw.textWidth(size, count);
        const tint = if (enough) draw.rgb(0.8, 1, 0.45) else draw.rgb(0.75, 0.8, 0.9);
        draw.sprite(render, f.art.glow, w / 2 - tw / 2 - 40, top - 8, w / 2 - tw / 2 - 2, top + 30, .{}, draw.color(0.8, 1, 0.4, 0.9));
        draw.text(render, w / 2 - tw / 2 + 6, top, size, count, tint);

        // The pulse recharging.
        const ready = 1 - s.pulse_cooldown / sim.tune.pulse_cooldown;
        const bar_w: f32 = 120;
        draw.rect(render, w / 2 - bar_w / 2, top + 38, w / 2 + bar_w / 2, top + 42, draw.color(1, 1, 1, 0.12));
        draw.rect(render, w / 2 - bar_w / 2, top + 38, w / 2 - bar_w / 2 + bar_w * ready, top + 42, draw.color(0.8, 1, 0.45, if (ready >= 1) 0.8 else 0.4));

        if (pequi.internal and g.robot_on) draw.text(render, 12, top, 12, "ROBO", draw.rgb(1, 0.6, 0.3));

        const bottom = h - f.input.safe_area.bottom;
        if (s.outcome == .playing and s.time < 9) {
            const a = std.math.clamp(@min(s.time, 9 - s.time), 0, 1);
            const lines = [_][]const u8{ "ARRASTE: GUIAR", "TOQUE: PULSAR", "DOIS DEDOS: APAGAR" };
            for (lines, 0..) |line, i| {
                draw.text(render, w / 2 - draw.textWidth(16, line) / 2, bottom - 110 + @as(f32, @floatFromInt(i)) * 26, 16, line, draw.color(0.8, 0.85, 0.95, 0.75 * a));
            }
        }

        if (s.outcome == .playing) return;
        const a = std.math.clamp((g.end_time - 0.6) / 0.8, 0, 1);
        const won = s.outcome == .won;
        if (!won) draw.rect(render, 0, 0, w, h, draw.color(0, 0, 0.02, 0.6 * a));
        const title = if (won) "ACESO!" else "O ENXAME SE APAGOU";
        const title_size: f32 = if (won) 54 else 26;
        const y = h * 0.36;
        draw.text(render, w / 2 - draw.textWidth(title_size, title) / 2, y, title_size, title, draw.color(0.85, 1, 0.5, a));
        if (won) {
            // One to three stars, by the swarm that arrived.
            const stars = s.stars();
            for (0..3) |i| {
                const on = i < stars and g.end_time > 1.6 + @as(f32, @floatFromInt(i)) * 0.45;
                const sx = w / 2 + (@as(f32, @floatFromInt(i)) - 1) * 70;
                const r: f32 = if (on) 30 else 14;
                draw.setBlend(render, .additive);
                draw.sprite(render, f.art.glow, sx - r, y + 90 - r, sx + r, y + 90 + r, .{}, if (on) draw.color(1, 0.95, 0.5, a) else draw.color(0.5, 0.55, 0.7, 0.5 * a));
                draw.setBlend(render, .alpha);
            }
            const line = std.fmt.bufPrint(&buffer, "{d} VAGA-LUMES   {s}", .{ s.swarm, level.name }) catch "";
            draw.text(render, w / 2 - draw.textWidth(16, line) / 2, y + 140, 16, line, draw.color(0.8, 0.85, 0.95, a));
        }
        if (g.end_time > 1.6) {
            const again = "TOQUE PARA JOGAR DE NOVO";
            const blink = 0.6 + 0.4 * @sin(g.time * 3);
            draw.text(render, w / 2 - draw.textWidth(16, again) / 2, bottom - 90, 16, again, draw.color(0.8, 0.85, 0.95, blink));
        }
    }
};

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
