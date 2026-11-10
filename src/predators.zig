//! The predators. Each has one rule a player can read.
//!
//! Frog: sits at a pond's edge. When a shining firefly comes within reach
//! it swells for a moment, then its tongue takes the nearest one. It cannot
//! see a dark swarm. A pulse nearby wakes it: for a few seconds it reaches
//! almost twice as far and strikes more often.
//!
//! Spider: its web cannot be seen, except for a while after a pulse.
//! Fireflies of the swarm that fly into it are stuck, and the spider eats
//! one every few seconds. A pulse close to the web tears it and frees them.
//!
//! Owl: flies a round high above. It dives at a shining swarm it sees, or
//! at a pulse from much farther. Its shadow follows the swarm for half the
//! dive and then stays: whoever is still there, shining, is taken.
//!
//! Maned wolf: not a predator. It crosses the level now and then; frogs,
//! spiders and owls near its path hide for a while, and webs let go.
//!
//! Wind: gusts push the swarm, harder on those who cannot see the leader.

const std = @import("std");
const sim = @import("sim.zig");
const Sim = sim.Sim;
const tune = sim.tune;

pub fn frogRange(frog: *const sim.Frog) f32 {
    return if (frog.alert > 0) tune.frog_range_alert else tune.frog_range;
}

pub fn hearPulse(s: *Sim, x: f32, y: f32, events: *sim.Events) void {
    for (s.frogs[0..s.frog_count]) |*frog| {
        if (sim.distance(frog.x, frog.y, x, y) <= tune.pulse_alert_radius) frog.alert = tune.frog_alert_seconds;
    }
    for (s.webs[0..s.web_count], 0..) |*web, i| {
        const d = sim.distance(web.x, web.y, x, y);
        if (d <= tune.pulse_alert_radius) web.seen = tune.web_seen_seconds;
        if (d <= tune.web_free_radius) freeWeb(s, i, events);
    }
    for (s.owls[0..s.owl_count]) |*owl| {
        if (owl.state != .patrol or owl.scared > 0) continue;
        if (sim.distance(owl.x, owl.y, x, y) <= tune.owl_hearing) startDive(owl, x, y, events);
    }
}

/// Tears a web: who was stuck in it flies back to the leader.
fn freeWeb(s: *Sim, index: usize, events: *sim.Events) void {
    const web = &s.webs[index];
    web.torn = tune.web_torn_seconds;
    if (web.stuck == 0) return;
    for (s.flies[1..s.fly_count]) |*f| {
        if (f.state != .stuck or f.web != index) continue;
        f.state = .called;
        f.timer = tune.called_seconds;
    }
    events.add(.{ .kind = .freed, .x = web.x, .y = web.y, .value = web.stuck });
    web.stuck = 0;
}

pub fn updateWebs(s: *Sim, events: *sim.Events) void {
    for (s.webs[0..s.web_count], 0..) |*web, i| {
        web.torn = @max(0, web.torn - sim.dt);
        web.seen = @max(0, web.seen - sim.dt);
        web.scared = @max(0, web.scared - sim.dt);

        if (web.torn == 0) {
            for (s.flies[1..s.fly_count]) |*f| {
                if (web.stuck >= tune.web_capacity) break;
                if (f.state != .swarm) continue;
                if (sim.distance(f.x, f.y, web.x, web.y) > web.r * 0.9) continue;
                f.state = .stuck;
                f.web = @intCast(i);
                f.vx = 0;
                f.vy = 0;
                s.swarm -= 1;
                if (web.stuck == 0) web.eat = tune.web_eat_seconds;
                web.stuck += 1;
                events.add(.{ .kind = .stuck, .x = f.x, .y = f.y, .value = s.swarm });
            }
        }

        if (web.stuck == 0 or web.scared > 0) continue;
        web.eat -= sim.dt;
        if (web.eat > 0) continue;
        web.eat = tune.web_eat_seconds;
        // The spider takes the one nearest to the middle, where it sits.
        var best: ?*sim.Fly = null;
        var best_d: f32 = std.math.floatMax(f32);
        for (s.flies[1..s.fly_count]) |*f| {
            if (f.state != .stuck or f.web != i) continue;
            const d = sim.distance(f.x, f.y, web.x, web.y);
            if (d < best_d) {
                best_d = d;
                best = f;
            }
        }
        if (best) |f| {
            f.state = .taken;
            web.stuck -= 1;
            events.add(.{ .kind = .taken, .x = f.x, .y = f.y, .value = s.swarm });
        }
    }
}

fn startDive(owl: *sim.Owl, x: f32, y: f32, events: *sim.Events) void {
    owl.state = .dive;
    owl.timer = tune.owl_windup;
    owl.from_x = owl.x;
    owl.from_y = owl.y;
    owl.target_x = x;
    owl.target_y = y;
    events.add(.{ .kind = .owl_dive, .x = x, .y = y });
}

/// Where the owl is on its round at `time`.
fn patrolPoint(owl: *const sim.Owl, time: f32) [2]f32 {
    const a = time / owl.period * std.math.tau;
    return .{ owl.cx + @cos(a) * owl.rx, owl.cy + @sin(a) * owl.ry };
}

pub fn updateOwls(s: *Sim, events: *sim.Events) void {
    const me = s.flies[sim.leader];
    for (s.owls[0..s.owl_count]) |*owl| {
        owl.scared = @max(0, owl.scared - sim.dt);
        const home = patrolPoint(owl, s.time);
        switch (owl.state) {
            .patrol => {
                owl.x = home[0];
                owl.y = home[1];
                if (owl.scared > 0 or !s.seen()) continue;
                if (sim.distance(owl.x, owl.y, me.x, me.y) <= tune.owl_sight) startDive(owl, me.x, me.y, events);
            },
            .dive => {
                owl.timer -= sim.dt;
                const t = 1 - owl.timer / tune.owl_windup;
                // It follows the swarm at first; then the dive is set.
                if (t < tune.owl_track and s.seen()) {
                    owl.target_x = me.x;
                    owl.target_y = me.y;
                }
                const k = t * t;
                owl.x = owl.from_x + (owl.target_x - owl.from_x) * k;
                owl.y = owl.from_y + (owl.target_y - owl.from_y) * k;
                if (owl.scared > 0) {
                    owl.state = .climb;
                    owl.timer = tune.owl_cooldown;
                    owl.from_x = owl.x;
                    owl.from_y = owl.y;
                    continue;
                }
                if (owl.timer > 0) continue;
                var took: u32 = 0;
                if (s.seen()) {
                    while (took < tune.owl_takes) : (took += 1) {
                        if (s.take(owl.target_x, owl.target_y, tune.owl_strike_radius, events) == null) break;
                    }
                }
                if (took == 0) events.add(.{ .kind = .owl_miss, .x = owl.target_x, .y = owl.target_y });
                owl.state = .strike;
                owl.timer = 0.25;
            },
            .strike => {
                owl.timer -= sim.dt;
                if (owl.timer > 0) continue;
                owl.state = .climb;
                owl.timer = tune.owl_cooldown;
                owl.from_x = owl.x;
                owl.from_y = owl.y;
            },
            .climb => {
                owl.timer -= sim.dt;
                const t = std.math.clamp(1 - owl.timer / tune.owl_cooldown, 0, 1);
                const k = t * t * (3 - 2 * t);
                owl.x = owl.from_x + (home[0] - owl.from_x) * k;
                owl.y = owl.from_y + (home[1] - owl.from_y) * k;
                if (owl.timer <= 0) owl.state = .patrol;
            },
        }
    }
}

pub fn updateWind(s: *Sim, events: *sim.Events) void {
    const wind = s.wind orelse return;
    const phase = @mod(s.time, wind.period);
    const before = @mod(s.time - sim.dt, wind.period);
    if (phase < before) events.add(.{ .kind = .gust, .x = wind.dx, .y = wind.dy });
    var g: f32 = 0;
    if (phase < wind.gust) {
        const w = @sin(phase / wind.gust * std.math.pi);
        g = w * w;
    }
    s.wind_x = wind.dx * wind.strength * g;
    s.wind_y = wind.dy * wind.strength * g;
}

pub fn updateWolf(s: *Sim, events: *sim.Events) void {
    const path = s.wolf_path orelse return;
    const wolf = &s.wolf;
    if (!wolf.active) {
        if (s.time < path.first) return;
        const since = @mod(s.time - path.first, path.period);
        if (since >= sim.dt) return;
        wolf.active = true;
        wolf.t = 0;
        events.add(.{ .kind = .wolf, .x = path.x0, .y = path.y0 });
    }
    const length = sim.distance(path.x0, path.y0, path.x1, path.y1);
    wolf.t += tune.wolf_speed * sim.dt / length;
    wolf.x = path.x0 + (path.x1 - path.x0) * wolf.t;
    wolf.y = path.y0 + (path.y1 - path.y0) * wolf.t;
    if (wolf.t >= 1) {
        wolf.active = false;
        return;
    }
    for (s.frogs[0..s.frog_count]) |*frog| {
        if (sim.distance(frog.x, frog.y, wolf.x, wolf.y) < tune.wolf_scare_radius) frog.scared = tune.scared_seconds;
    }
    for (s.webs[0..s.web_count], 0..) |*web, i| {
        if (sim.distance(web.x, web.y, wolf.x, wolf.y) > tune.wolf_scare_radius) continue;
        web.scared = tune.scared_seconds;
        if (web.stuck > 0) freeWeb(s, i, events);
    }
    for (s.owls[0..s.owl_count]) |*owl| {
        if (sim.distance(owl.x, owl.y, wolf.x, wolf.y) < tune.wolf_scare_radius) owl.scared = tune.scared_seconds;
    }
}

/// Distance from (x, y) to the nearest swarm firefly, or null with none.
fn nearestSwarm(s: *const Sim, x: f32, y: f32) ?f32 {
    var best: ?f32 = null;
    for (s.flies[0..s.fly_count]) |f| {
        if (f.state != .swarm) continue;
        const d = sim.distance(f.x, f.y, x, y);
        if (best == null or d < best.?) best = d;
    }
    return best;
}

pub fn updateFrogs(s: *Sim, events: *sim.Events) void {
    for (s.frogs[0..s.frog_count]) |*frog| {
        frog.alert = @max(0, frog.alert - sim.dt);
        frog.scared = @max(0, frog.scared - sim.dt);
        if (frog.scared > 0) {
            // Under the water until the wolf is gone.
            frog.state = .idle;
            continue;
        }
        const range = frogRange(frog);
        switch (frog.state) {
            .idle => {
                if (!s.seen()) continue;
                const d = nearestSwarm(s, frog.x, frog.y) orelse continue;
                if (d > range) continue;
                frog.state = .windup;
                frog.timer = tune.frog_windup;
                events.add(.{ .kind = .frog_windup, .x = frog.x, .y = frog.y });
            },
            .windup => {
                frog.timer -= sim.dt;
                if (frog.timer > 0) continue;
                // The swarm went dark or flew off in time: the tongue finds nothing.
                const got = if (s.seen()) s.take(frog.x, frog.y, range * 1.1, events) else null;
                frog.hit = got != null;
                if (got) |p| {
                    frog.tongue_x = p[0];
                    frog.tongue_y = p[1];
                } else {
                    const me = s.flies[sim.leader];
                    const d = sim.distance(frog.x, frog.y, me.x, me.y) + 0.001;
                    const reach = @min(d, range);
                    frog.tongue_x = frog.x + (me.x - frog.x) / d * reach;
                    frog.tongue_y = frog.y + (me.y - frog.y) / d * reach;
                    events.add(.{ .kind = .frog_miss, .x = frog.x, .y = frog.y });
                }
                frog.state = .strike;
                frog.timer = 0.16;
            },
            .strike => {
                frog.timer -= sim.dt;
                if (frog.timer > 0) continue;
                frog.state = .cooldown;
                frog.timer = if (frog.alert > 0) tune.frog_cooldown_alert else tune.frog_cooldown;
            },
            .cooldown => {
                frog.timer -= sim.dt;
                if (frog.timer <= 0) frog.state = .idle;
            },
        }
    }
}
