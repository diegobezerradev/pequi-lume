//! How fireflies move: the leader after the player's finger, the swarm
//! after the leader (separation, alignment, cohesion), the lost ones
//! hovering where they are or flying to a pulse.

const std = @import("std");
const sim = @import("sim.zig");
const Sim = sim.Sim;
const tune = sim.tune;

const separation_radius: f32 = 17;
const neighbor_radius: f32 = 58;
const swarm_speed: f32 = 230;
/// In the dark some keep up with the leader and some fall behind: each
/// firefly's top speed is between these.
const swarm_speed_dark_slow: f32 = 34;
const swarm_speed_dark_fast: f32 = 80;
/// In the dark each firefly only learns where the leader is this often.
const dark_glimpse_seconds: f32 = 1.3;

pub fn moveLeader(s: *Sim, controls: sim.Controls) void {
    const me = &s.flies[sim.leader];
    const top = if (s.dark) tune.leader_speed_dark else tune.leader_speed;
    var want_x: f32 = 0;
    var want_y: f32 = 0;
    if (controls.guiding) {
        const dx = controls.target_x - me.x;
        const dy = controls.target_y - me.y;
        const d = @sqrt(dx * dx + dy * dy);
        if (d > 1) {
            // Full speed from a little way off, easing in on arrival.
            const speed = @min(top, d * 5);
            want_x = dx / d * speed;
            want_y = dy / d * speed;
        }
    }
    // Reaches the wanted speed with a short lag, so turns are round.
    const k = 1 - std.math.exp(-sim.dt / 0.09);
    me.vx += (want_x - me.vx) * k;
    me.vy += (want_y - me.vy) * k;
    me.x = std.math.clamp(me.x + me.vx * sim.dt, 12, s.width - 12);
    me.y = std.math.clamp(me.y + me.vy * sim.dt, 12, s.height - 12);
}

/// Going dark: every firefly remembers where the leader was.
pub fn rememberLeader(s: *Sim) void {
    const me = s.flies[sim.leader];
    for (s.flies[1..s.fly_count]) |*f| {
        if (f.state != .swarm) continue;
        f.home_x = me.x;
        f.home_y = me.y;
    }
}

pub fn moveSwarm(s: *Sim, events: *sim.Events) void {
    const me = s.flies[sim.leader];
    // The swarm keeps a loose ball around the leader, bigger with more of them.
    const ring = 16 + 4.2 * @sqrt(@as(f32, @floatFromInt(s.swarm)));

    for (s.flies[1..s.fly_count], 1..) |*f, i| {
        if (f.state != .swarm) continue;

        var sep_x: f32 = 0;
        var sep_y: f32 = 0;
        var avg_x: f32 = 0;
        var avg_y: f32 = 0;
        var avg_vx: f32 = 0;
        var avg_vy: f32 = 0;
        var neighbors: f32 = 0;
        for (s.flies[0..s.fly_count], 0..) |o, j| {
            if (j == i or o.state != .swarm) continue;
            const dx = f.x - o.x;
            const dy = f.y - o.y;
            const d2 = dx * dx + dy * dy;
            if (d2 > neighbor_radius * neighbor_radius) continue;
            const d = @sqrt(d2) + 0.001;
            if (d < separation_radius) {
                const push = (separation_radius - d) / separation_radius;
                sep_x += dx / d * push;
                sep_y += dy / d * push;
            }
            avg_x += o.x;
            avg_y += o.y;
            avg_vx += o.vx;
            avg_vy += o.vy;
            neighbors += 1;
        }

        // Where it believes the leader is: in the dark, a glimpse now and then.
        if (s.dark) {
            const before = @mod(s.time - sim.dt + f.phase, dark_glimpse_seconds);
            const now = @mod(s.time + f.phase, dark_glimpse_seconds);
            if (now < before) {
                f.home_x = me.x;
                f.home_y = me.y;
            }
        } else {
            f.home_x = me.x;
            f.home_y = me.y;
        }

        var ax: f32 = 0;
        var ay: f32 = 0;
        // Toward the leader, harder the farther outside the ball.
        const lx = f.home_x - f.x;
        const ly = f.home_y - f.y;
        const ld = @sqrt(lx * lx + ly * ly) + 0.001;
        const pull = std.math.clamp((ld - ring) / 40, -0.4, 3.0);
        ax += lx / ld * pull * 420;
        ay += ly / ld * pull * 420;
        // Apart from the ones too close.
        ax += sep_x * 900;
        ay += sep_y * 900;
        if (neighbors > 0) {
            const sight: f32 = if (s.dark) 0.25 else 1;
            // Toward the middle of the neighbors, and flying their way.
            ax += (avg_x / neighbors - f.x) * 1.6 * sight;
            ay += (avg_y / neighbors - f.y) * 1.6 * sight;
            ax += (avg_vx / neighbors - f.vx) * 2.2 * sight;
            ay += (avg_vy / neighbors - f.vy) * 2.2 * sight;
        }
        // Each one's own restlessness; more of it when they cannot see.
        const wander: f32 = if (s.dark) 150 else 70;
        ax += @cos(s.time * 2.3 + f.phase * 3) * wander + @sin(s.time * 5.1 + f.phase) * wander * 0.5;
        ay += @sin(s.time * 2.9 + f.phase * 2) * wander + @cos(s.time * 4.3 + f.phase * 5) * wander * 0.5;

        f.vx += ax * sim.dt;
        f.vy += ay * sim.dt;
        // Air drag, then the speed limit.
        const keep = std.math.exp(-sim.dt * 1.8);
        f.vx *= keep;
        f.vy *= keep;
        const top = if (s.dark) swarm_speed_dark_slow + (swarm_speed_dark_fast - swarm_speed_dark_slow) * f.phase / std.math.tau else swarm_speed;
        const speed = @sqrt(f.vx * f.vx + f.vy * f.vy);
        if (speed > top) {
            f.vx *= top / speed;
            f.vy *= top / speed;
        }
        f.x = std.math.clamp(f.x + f.vx * sim.dt, 4, s.width - 4);
        f.y = std.math.clamp(f.y + f.vy * sim.dt, 4, s.height - 4);

        if (sim.distance(f.x, f.y, me.x, me.y) > tune.stray_radius) {
            f.state = .lost;
            f.home_x = f.x;
            f.home_y = f.y;
            s.swarm -= 1;
            events.add(.{ .kind = .strayed, .x = f.x, .y = f.y, .value = s.swarm });
        }
    }
}

pub fn moveLost(s: *Sim, events: *sim.Events) void {
    const me = s.flies[sim.leader];
    const reach = s.lightRadiusNow() * 0.8;
    for (s.flies[1..s.fly_count]) |*f| {
        switch (f.state) {
            .lost => {
                // Hovering in a slow loop around its place.
                const tx = f.home_x + @cos(s.time * 0.7 + f.phase) * 14;
                const ty = f.home_y + @sin(s.time * 0.9 + f.phase * 2) * 10;
                f.vx = (tx - f.x) * 2;
                f.vy = (ty - f.y) * 2;
                f.x += f.vx * sim.dt;
                f.y += f.vy * sim.dt;
                // The swarm's light reaching it brings it in.
                if (!s.dark and sim.distance(f.x, f.y, me.x, me.y) < reach) s.join(f, events);
            },
            .called => {
                const dx = me.x - f.x;
                const dy = me.y - f.y;
                const d = @sqrt(dx * dx + dy * dy) + 0.001;
                // A weaving flight, not a straight line.
                const weave = @sin(s.time * 6 + f.phase * 4) * 0.5;
                const want_x = (dx / d - dy / d * weave) * tune.called_speed;
                const want_y = (dy / d + dx / d * weave) * tune.called_speed;
                const k = 1 - std.math.exp(-sim.dt / 0.2);
                f.vx += (want_x - f.vx) * k;
                f.vy += (want_y - f.vy) * k;
                f.x += f.vx * sim.dt;
                f.y += f.vy * sim.dt;
                f.timer -= sim.dt;
                if (d < tune.join_radius) {
                    s.join(f, events);
                } else if (f.timer <= 0) {
                    f.state = .lost;
                    f.home_x = f.x;
                    f.home_y = f.y;
                }
            },
            else => {},
        }
    }
}
