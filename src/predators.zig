//! The predators. Each has one rule a player can read.
//!
//! Frog: sits at a pond's edge. When a shining firefly comes within reach
//! it swells for a moment, then its tongue takes the nearest one. It cannot
//! see a dark swarm. A pulse nearby wakes it: for a few seconds it reaches
//! almost twice as far and strikes more often.

const std = @import("std");
const sim = @import("sim.zig");
const Sim = sim.Sim;
const tune = sim.tune;

pub fn frogRange(frog: *const sim.Frog) f32 {
    return if (frog.alert > 0) tune.frog_range_alert else tune.frog_range;
}

pub fn hearPulse(s: *Sim, x: f32, y: f32) void {
    for (s.frogs[0..s.frog_count]) |*frog| {
        if (sim.distance(frog.x, frog.y, x, y) <= tune.pulse_alert_radius) frog.alert = tune.frog_alert_seconds;
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
