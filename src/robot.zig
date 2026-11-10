//! A robot that plays through `Controls`, like a player would: it gathers
//! lost fireflies, goes dark when a frog swells, pulses where it is safe
//! and heads for the mound when the swarm is big enough. It is how levels
//! are checked without hands (tests, scripted runs, the debug autoplay).

const std = @import("std");
const sim = @import("sim.zig");
const predators = @import("predators.zig");
const Sim = sim.Sim;
const tune = sim.tune;

pub const Robot = struct {
    /// The swarm size it wants before going to the mound (0: just enough).
    goal: u32 = 0,
    /// A careless robot never goes dark and walks straight at things.
    careful: bool = true,

    pub fn think(r: Robot, s: *const Sim) sim.Controls {
        const me = s.flies[sim.leader];
        var c: sim.Controls = .{ .guiding = true, .target_x = me.x, .target_y = me.y };
        const goal = @max(r.goal, s.need);

        // Where to: the mound, or the nearest lost firefly.
        var lost_near: f32 = std.math.floatMax(f32);
        var any_called = false;
        if (s.swarm >= goal) {
            c.target_x = s.mound_x;
            c.target_y = s.mound_y;
        } else {
            var found = false;
            for (s.flies[1..s.fly_count]) |f| {
                if (f.state == .called) any_called = true;
                if (f.state != .lost) continue;
                const d = sim.distance(f.x, f.y, me.x, me.y);
                if (d < lost_near) {
                    lost_near = d;
                    c.target_x = f.x;
                    c.target_y = f.y;
                    found = true;
                }
            }
            if (!found and !any_called) {
                // No one left to find: the mound, with what there is.
                c.target_x = s.mound_x;
                c.target_y = s.mound_y;
            }
        }
        if (!r.careful) return c;

        // Frogs. One that swells: go dark and wait for the miss. One that
        // just struck is harmless for a moment: that is when to cross its
        // reach. An idle one guarding the target: step in to make it swell.
        var frog_near: f32 = std.math.floatMax(f32);
        var push_x: f32 = 0;
        var push_y: f32 = 0;
        for (s.frogs[0..s.frog_count]) |*frog| {
            const d = sim.distance(frog.x, frog.y, me.x, me.y);
            frog_near = @min(frog_near, d);
            const range = predators.frogRange(frog);
            // The swarm trails around the leader: keep a margin.
            const margin = range + 55;
            if (frog.state == .windup and d < margin + 20) {
                c.dark = true;
                c.guiding = false;
            }
            const resting = frog.state == .strike or (frog.state == .cooldown and frog.timer > 0.35);
            const guards_target = sim.distance(frog.x, frog.y, c.target_x, c.target_y) < margin + 40;
            if (resting or guards_target) continue;
            if (d < margin + 60) {
                const w = (margin + 60 - d) / 60;
                push_x += (me.x - frog.x) / (d + 0.001) * w;
                push_y += (me.y - frog.y) / (d + 0.001) * w;
            }
        }
        if (push_x != 0 or push_y != 0) {
            // Slide around the frog: away from it, and along toward the target.
            const tx = c.target_x - me.x;
            const ty = c.target_y - me.y;
            const td = @sqrt(tx * tx + ty * ty) + 0.001;
            c.target_x = me.x + (tx / td + push_x * 1.6) * 120;
            c.target_y = me.y + (ty / td + push_y * 1.6) * 120;
        }

        // A pulse brings in the ones it would be risky to fetch, when no
        // frog is close enough to be woken within reach.
        if (s.pulse_cooldown == 0 and !c.dark and s.swarm < goal and
            lost_near < tune.pulse_call_radius * 0.9 and lost_near > s.lightRadiusNow() and
            frog_near > tune.frog_range_alert + 70)
        {
            c.pulse = true;
        }
        // Wait for the called ones instead of walking into trouble.
        if (any_called and s.since_pulse < 2.5) c.guiding = false;
        return c;
    }
};

const testing = std.testing;

fn play(robot: Robot, seconds: f32) Sim {
    var s = Sim.init(0);
    var events: sim.Events = .{};
    const steps: u32 = @intFromFloat(seconds / sim.dt);
    for (0..steps) |_| {
        events.count = 0;
        s.step(robot.think(&s), &events);
        if (s.outcome != .playing) break;
    }
    return s;
}

test "a careful robot lights the first mound" {
    const s = play(.{}, 300);
    try testing.expectEqual(sim.Outcome.won, s.outcome);
    try testing.expect(s.stars() >= 1);
}

test "a greedy careful robot can get three stars" {
    const s = play(.{ .goal = @import("levels.zig").get(0).stars[2] }, 400);
    try testing.expectEqual(sim.Outcome.won, s.outcome);
    try testing.expectEqual(@as(u32, 3), s.stars());
}

test "a careless robot pays for it" {
    const careful = play(.{ .goal = 24 }, 400);
    const careless = play(.{ .goal = 24, .careful = false }, 400);
    try testing.expect(careless.outcome != .won or careless.swarm < careful.swarm);
}
