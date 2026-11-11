//! The simulation of one level: the leader, the swarm, the lost fireflies,
//! the predators and the mound. No drawing, no sound: `step` takes the
//! player's `Controls`, advances a fixed `dt` and reports what happened as
//! `Events`. Same level, seed and controls give the same game.

const std = @import("std");
const levels = @import("levels.zig");
const boids = @import("boids.zig");
const predators = @import("predators.zig");

/// The fixed step. The screen runs as many steps as fit its frame.
pub const dt: f32 = 1.0 / 120.0;

pub const max_flies = 200;
pub const max_frogs = 8;
pub const max_webs = 12;
pub const max_owls = 4;

/// The numbers the game is tuned with.
pub const tune = struct {
    pub const leader_speed: f32 = 160;
    pub const leader_speed_dark: f32 = 70;
    /// Seconds for the swarm's glow to fade out or come back.
    pub const glow_time: f32 = 0.18;

    pub const pulse_cooldown: f32 = 2.6;
    /// A pulse spends the swarm's light: right after it the light reaches
    /// only this much of its radius, and grows back over the cooldown.
    pub const pulse_spent_light: f32 = 0.45;
    /// Lost fireflies this close to a pulse come flying.
    pub const pulse_call_radius: f32 = 430;
    /// Predators this close to a pulse wake up.
    pub const pulse_alert_radius: f32 = 520;
    pub const called_speed: f32 = 150;
    pub const called_seconds: f32 = 9;
    pub const join_radius: f32 = 34;

    /// A swarm firefly this far from the leader is lost again.
    pub const stray_radius: f32 = 230;
    pub const streak_seconds: f32 = 1.6;

    pub const frog_range: f32 = 140;
    pub const frog_range_alert: f32 = 260;
    pub const frog_windup: f32 = 0.5;
    pub const frog_cooldown: f32 = 0.9;
    pub const frog_cooldown_alert: f32 = 0.55;
    pub const frog_alert_seconds: f32 = 3.5;
    /// The swarm is seen while its glow is above this.
    pub const seen_glow: f32 = 0.35;

    /// A web holds at most this many.
    pub const web_capacity: u32 = 6;
    /// A pulse this close to a web tears it and frees who is in it.
    pub const web_free_radius: f32 = 230;
    /// Seconds between the spider's meals while it has someone trapped.
    pub const web_eat_seconds: f32 = 3.5;
    /// A torn web catches no one for this long.
    pub const web_torn_seconds: f32 = 6;
    /// A pulse shows the webs around for this long.
    pub const web_seen_seconds: f32 = 5;
    pub const web_slow: f32 = 0.55;

    /// The owl sees a shining swarm this far from where it flies.
    pub const owl_sight: f32 = 430;
    /// And turns to a pulse from this far.
    pub const owl_hearing: f32 = 850;
    pub const owl_windup: f32 = 1.6;
    /// The dive follows the swarm for this part of the windup, then is set.
    pub const owl_track: f32 = 0.45;
    pub const owl_strike_radius: f32 = 58;
    pub const owl_takes: u32 = 3;
    pub const owl_cooldown: f32 = 4.5;

    pub const wolf_speed: f32 = 85;
    /// Predators this close to the maned wolf hide for a while.
    pub const wolf_scare_radius: f32 = 280;
    pub const scared_seconds: f32 = 6;

    pub const mound_radius: f32 = 85;
};

/// How far the swarm's light reaches: more fireflies, more light.
pub fn lightRadius(count: u32, glow: f32) f32 {
    return (62 + 15 * @sqrt(@as(f32, @floatFromInt(count)))) * glow;
}

pub const Controls = struct {
    /// Where the leader should go, in world units.
    target_x: f32 = 0,
    target_y: f32 = 0,
    /// The player is pointing somewhere (finger or button down).
    guiding: bool = false,
    /// A pulse was asked for on this step.
    pulse: bool = false,
    /// Held: the swarm goes dark.
    dark: bool = false,
};

pub const FlyState = enum(u8) { none, lost, called, swarm, taken, stuck };

pub const Fly = struct {
    x: f32 = 0,
    y: f32 = 0,
    vx: f32 = 0,
    vy: f32 = 0,
    state: FlyState = .none,
    /// Lost: where it hovers. Swarm, in the dark: where it last saw the leader.
    home_x: f32 = 0,
    home_y: f32 = 0,
    /// Its own rhythm: blinking, hovering, wandering.
    phase: f32 = 0,
    /// Which blinking pattern (see `blink`).
    pattern: u8 = 0,
    /// Called: seconds left before it gives up.
    timer: f32 = 0,
    /// Stuck: in which web.
    web: u8 = 0,
};

pub const FrogState = enum(u8) { idle, windup, strike, cooldown };

pub const Frog = struct {
    x: f32,
    y: f32,
    state: FrogState = .idle,
    timer: f32 = 0,
    /// Seconds it stays woken up by a pulse.
    alert: f32 = 0,
    /// Where the tongue went on the last strike.
    tongue_x: f32 = 0,
    tongue_y: f32 = 0,
    hit: bool = false,
    /// Seconds it stays hidden after the maned wolf passed.
    scared: f32 = 0,
};

pub const Web = struct {
    x: f32,
    y: f32,
    r: f32,
    /// Fireflies trapped in it now.
    stuck: u32 = 0,
    /// Seconds until the spider eats again.
    eat: f32 = 0,
    /// Seconds it stays torn, catching no one.
    torn: f32 = 0,
    /// Seconds it stays visible after a pulse.
    seen: f32 = 0,
    scared: f32 = 0,
};

pub const OwlState = enum(u8) { patrol, dive, strike, climb };

pub const Owl = struct {
    /// It patrols an ellipse around (cx, cy), one turn every `period` seconds.
    cx: f32,
    cy: f32,
    rx: f32,
    ry: f32,
    period: f32,
    x: f32 = 0,
    y: f32 = 0,
    state: OwlState = .patrol,
    timer: f32 = 0,
    /// Where it dives: follows the swarm at first, then is set.
    target_x: f32 = 0,
    target_y: f32 = 0,
    /// Where it left the patrol from.
    from_x: f32 = 0,
    from_y: f32 = 0,
    scared: f32 = 0,
};

/// The maned wolf: no enemy. It crosses the level now and then, and the
/// predators near its path hide.
pub const Wolf = struct {
    active: bool = false,
    x: f32 = 0,
    y: f32 = 0,
    /// Along its path, 0 to 1.
    t: f32 = 0,
};

pub const Outcome = enum(u8) { playing, won, lost };

pub const EventKind = enum(u8) {
    /// A lost firefly joined; `value` is how many joined in a row.
    rescued,
    /// A predator took one.
    taken,
    /// One strayed in the dark and is lost again.
    strayed,
    pulse,
    /// A pulse was asked for too soon.
    pulse_denied,
    dark_on,
    dark_off,
    frog_windup,
    frog_miss,
    /// A swarm firefly flew into a web.
    stuck,
    /// A pulse (or the wolf) freed the ones in a web; `value` is how many.
    freed,
    /// The owl starts its dive.
    owl_dive,
    owl_miss,
    /// A gust of wind begins.
    gust,
    /// The maned wolf enters the level.
    wolf,
    /// At the mound with too few; `value` is how many are missing.
    mound_denied,
    won,
    lost,
};

pub const Event = struct {
    kind: EventKind,
    x: f32 = 0,
    y: f32 = 0,
    value: u32 = 0,
    /// `taken`: where the predator that took it is.
    by_x: f32 = 0,
    by_y: f32 = 0,
};

/// What happened in one or more steps. When full, later events are dropped.
pub const Events = struct {
    items: [64]Event = undefined,
    count: usize = 0,

    pub fn add(e: *Events, event: Event) void {
        if (e.count == e.items.len) return;
        e.items[e.count] = event;
        e.count += 1;
    }

    pub fn slice(e: *const Events) []const Event {
        return e.items[0..e.count];
    }

    pub fn has(e: *const Events, kind: EventKind) bool {
        for (e.slice()) |ev| {
            if (ev.kind == kind) return true;
        }
        return false;
    }
};

pub const leader = 0;

pub const Sim = struct {
    level_index: u32 = 0,
    width: f32 = 0,
    height: f32 = 0,
    random: u32 = 1,
    steps: u32 = 0,
    time: f32 = 0,
    outcome: Outcome = .playing,

    /// `flies[leader]` is the player.
    flies: [max_flies]Fly = @splat(.{}),
    fly_count: u32 = 0,
    /// Fireflies in the swarm, the leader included.
    swarm: u32 = 0,

    frogs: [max_frogs]Frog = undefined,
    frog_count: u32 = 0,

    webs: [max_webs]Web = undefined,
    web_count: u32 = 0,
    owls: [max_owls]Owl = undefined,
    owl_count: u32 = 0,
    wolf: Wolf = .{},
    wolf_path: ?levels.WolfPath = null,
    wind: ?levels.Wind = null,
    /// The wind's push right now (0 between gusts).
    wind_x: f32 = 0,
    wind_y: f32 = 0,

    mound_x: f32 = 0,
    mound_y: f32 = 0,
    need: u32 = 0,
    mound_timer: f32 = 0,

    dark: bool = false,
    /// 1 shining, 0 dark.
    glow: f32 = 1,
    pulse_cooldown: f32 = 0,
    /// Seconds since the last pulse (large when there was none).
    since_pulse: f32 = 100,
    pulse_x: f32 = 0,
    pulse_y: f32 = 0,
    streak: u32 = 0,
    streak_timer: f32 = 0,

    pub fn init(level_index: u32) Sim {
        const level = levels.get(level_index);
        var s: Sim = .{
            .level_index = level_index,
            .width = level.width,
            .height = level.height,
            .random = level.seed | 1,
            .mound_x = level.mound[0],
            .mound_y = level.mound[1],
            .need = level.need,
            .wind = level.wind,
            .wolf_path = level.wolf,
        };
        for (0..level.start_swarm) |i| {
            const a = s.rand() * std.math.tau;
            const r: f32 = if (i == 0) 0 else 14 + s.rand() * 22;
            s.addFly(.swarm, level.start[0] + @cos(a) * r, level.start[1] + @sin(a) * r);
        }
        for (level.lost) |group| {
            for (0..group.count) |_| {
                const a = s.rand() * std.math.tau;
                const r = @sqrt(s.rand()) * group.spread;
                s.addFly(.lost, group.x + @cos(a) * r, group.y + @sin(a) * r);
            }
        }
        for (level.ponds) |pond| {
            if (s.frog_count == max_frogs) break;
            s.frogs[s.frog_count] = .{
                .x = pond.x + @cos(pond.frog_angle) * pond.rx,
                .y = pond.y + @sin(pond.frog_angle) * pond.ry,
            };
            s.frog_count += 1;
        }
        for (level.webs) |web| {
            if (s.web_count == max_webs) break;
            s.webs[s.web_count] = .{ .x = web.x, .y = web.y, .r = web.r };
            s.web_count += 1;
        }
        for (level.owls) |owl| {
            if (s.owl_count == max_owls) break;
            s.owls[s.owl_count] = .{ .cx = owl.x, .cy = owl.y, .rx = owl.rx, .ry = owl.ry, .period = owl.period, .x = owl.x + owl.rx, .y = owl.y };
            s.owl_count += 1;
        }
        return s;
    }

    /// Uniform in [0, 1), from the level's own sequence.
    pub fn rand(s: *Sim) f32 {
        var x = s.random;
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        s.random = x;
        return @as(f32, @floatFromInt(x >> 8)) / @as(f32, 1 << 24);
    }

    pub fn addFly(s: *Sim, state: FlyState, x: f32, y: f32) void {
        if (s.fly_count == max_flies) return;
        s.flies[s.fly_count] = .{
            .x = x,
            .y = y,
            .home_x = x,
            .home_y = y,
            .state = state,
            .phase = s.rand() * std.math.tau,
            .pattern = @intFromFloat(s.rand() * 4),
        };
        s.fly_count += 1;
        if (state == .swarm) s.swarm += 1;
    }

    /// The swarm's light now: its size, whether it is dark, and how much
    /// of it the last pulse spent.
    pub fn lightRadiusNow(s: *const Sim) f32 {
        const back = 1 - s.pulse_cooldown / tune.pulse_cooldown;
        const spent = tune.pulse_spent_light + (1 - tune.pulse_spent_light) * back * back;
        return lightRadius(s.swarm, s.glow) * spent;
    }

    /// Predators see the swarm.
    pub fn seen(s: *const Sim) bool {
        return s.glow > tune.seen_glow;
    }

    pub fn step(s: *Sim, controls: Controls, events: *Events) void {
        if (s.outcome == .lost) return;
        s.steps += 1;
        s.time += dt;
        if (s.outcome == .won) {
            // The level is over; the swarm dances around the lit mound.
            s.dark = false;
            s.glow = @min(1, s.glow + dt / tune.glow_time);
            const a = s.time * 1.1;
            boids.moveLeader(s, .{ .guiding = true, .target_x = s.mound_x + @cos(a) * 70, .target_y = s.mound_y + 10 + @sin(a) * 45 });
            boids.moveSwarm(s, events);
            return;
        }

        if (controls.dark != s.dark) {
            s.dark = controls.dark;
            events.add(.{ .kind = if (s.dark) .dark_on else .dark_off, .x = s.flies[leader].x, .y = s.flies[leader].y });
            if (s.dark) boids.rememberLeader(s);
        }
        const glow_step = dt / tune.glow_time;
        s.glow = if (s.dark) @max(0, s.glow - glow_step) else @min(1, s.glow + glow_step);

        s.pulse_cooldown = @max(0, s.pulse_cooldown - dt);
        s.since_pulse += dt;
        s.mound_timer = @max(0, s.mound_timer - dt);
        if (s.streak_timer > 0) {
            s.streak_timer -= dt;
            if (s.streak_timer <= 0) s.streak = 0;
        }
        if (controls.pulse) s.pulse(events);

        predators.updateWind(s, events);
        boids.moveLeader(s, controls);
        boids.moveSwarm(s, events);
        boids.moveLost(s, events);
        predators.updateWolf(s, events);
        predators.updateFrogs(s, events);
        predators.updateWebs(s, events);
        predators.updateOwls(s, events);
        s.checkEnd(events);
    }

    fn pulse(s: *Sim, events: *Events) void {
        const me = s.flies[leader];
        if (s.dark or s.pulse_cooldown > 0) {
            events.add(.{ .kind = .pulse_denied, .x = me.x, .y = me.y });
            return;
        }
        s.pulse_cooldown = tune.pulse_cooldown;
        s.since_pulse = 0;
        s.pulse_x = me.x;
        s.pulse_y = me.y;
        events.add(.{ .kind = .pulse, .x = me.x, .y = me.y });
        for (s.flies[0..s.fly_count]) |*f| {
            if (f.state != .lost) continue;
            if (distance(f.x, f.y, me.x, me.y) > tune.pulse_call_radius) continue;
            f.state = .called;
            f.timer = tune.called_seconds;
        }
        predators.hearPulse(s, me.x, me.y, events);
    }

    /// A lost or called firefly joins the swarm.
    pub fn join(s: *Sim, f: *Fly, events: *Events) void {
        f.state = .swarm;
        s.swarm += 1;
        s.streak += 1;
        s.streak_timer = tune.streak_seconds;
        events.add(.{ .kind = .rescued, .x = f.x, .y = f.y, .value = s.streak });
    }

    /// A predator takes the swarm firefly nearest to (x, y) within `range`.
    /// The leader goes last. Returns where the taken one was.
    pub fn take(s: *Sim, x: f32, y: f32, range: f32, events: *Events) ?[2]f32 {
        var best: ?usize = null;
        var best_d: f32 = range;
        for (s.flies[1..s.fly_count], 1..) |f, i| {
            if (f.state != .swarm) continue;
            const d = distance(f.x, f.y, x, y);
            if (d <= best_d) {
                best_d = d;
                best = i;
            }
        }
        if (best == null and s.swarm == 1 and distance(s.flies[leader].x, s.flies[leader].y, x, y) <= range) best = leader;
        const i = best orelse return null;
        const f = &s.flies[i];
        f.state = .taken;
        s.swarm -= 1;
        events.add(.{ .kind = .taken, .x = f.x, .y = f.y, .value = s.swarm, .by_x = x, .by_y = y });
        return .{ f.x, f.y };
    }

    fn checkEnd(s: *Sim, events: *Events) void {
        const me = s.flies[leader];
        if (s.swarm == 0) {
            s.outcome = .lost;
            events.add(.{ .kind = .lost, .x = me.x, .y = me.y });
            return;
        }
        // With too few fireflies left in the whole level, the mound can
        // never be lit: the level is lost, not left hanging.
        if (s.steps % 60 == 0) {
            var alive: u32 = 0;
            for (s.flies[0..s.fly_count]) |f| {
                if (f.state != .none and f.state != .taken) alive += 1;
            }
            if (alive < s.need) {
                s.outcome = .lost;
                events.add(.{ .kind = .lost, .x = me.x, .y = me.y });
                return;
            }
        }
        if (s.dark or distance(me.x, me.y, s.mound_x, s.mound_y) > tune.mound_radius) return;
        if (s.swarm >= s.need) {
            s.outcome = .won;
            events.add(.{ .kind = .won, .x = s.mound_x, .y = s.mound_y, .value = s.swarm });
        } else if (s.mound_timer == 0) {
            s.mound_timer = 2.5;
            events.add(.{ .kind = .mound_denied, .x = s.mound_x, .y = s.mound_y, .value = s.need - s.swarm });
        }
    }

    /// Stars for ending the level with the swarm as it is (0 if not won).
    pub fn stars(s: *const Sim) u32 {
        if (s.outcome != .won) return 0;
        const level = levels.get(s.level_index);
        var n: u32 = 0;
        for (level.stars) |needed| {
            if (s.swarm >= needed) n += 1;
        }
        return n;
    }

    /// A number that changes if anything in the game's state does: for
    /// checking that two runs are the same.
    pub fn checksum(s: *const Sim) u64 {
        var h = std.hash.Wyhash.init(0);
        h.update(std.mem.asBytes(&s.steps));
        h.update(std.mem.asBytes(&s.swarm));
        h.update(std.mem.asBytes(&s.random));
        h.update(std.mem.asBytes(&s.glow));
        for (s.flies[0..s.fly_count]) |f| {
            h.update(std.mem.asBytes(&f.x));
            h.update(std.mem.asBytes(&f.y));
            h.update(std.mem.asBytes(&f.state));
        }
        for (s.frogs[0..s.frog_count]) |f| {
            h.update(std.mem.asBytes(&f.state));
            h.update(std.mem.asBytes(&f.timer));
        }
        for (s.webs[0..s.web_count]) |w| {
            h.update(std.mem.asBytes(&w.stuck));
            h.update(std.mem.asBytes(&w.eat));
        }
        for (s.owls[0..s.owl_count]) |o| {
            h.update(std.mem.asBytes(&o.x));
            h.update(std.mem.asBytes(&o.state));
        }
        h.update(std.mem.asBytes(&s.wolf.t));
        return h.final();
    }
};

pub fn distance(x0: f32, y0: f32, x1: f32, y1: f32) f32 {
    const dx = x1 - x0;
    const dy = y1 - y0;
    return @sqrt(dx * dx + dy * dy);
}

/// How bright a lost firefly is at `time`, 0 to 1: each pattern is its own
/// rhythm (a slow glow, a double flash, a long dash, a quick flicker).
pub fn blink(pattern: u8, phase: f32, time: f32) f32 {
    const t = time + phase;
    return switch (pattern % 4) {
        0 => 0.5 + 0.5 * @sin(t * 2.4),
        1 => blk: {
            const c = @mod(t, 2.2);
            break :blk if (c < 0.16 or (c > 0.34 and c < 0.5)) 1 else 0.12;
        },
        2 => blk: {
            const c = @mod(t, 3.0);
            break :blk if (c < 1.1) @sin(c / 1.1 * std.math.pi) else 0.08;
        },
        else => 0.35 + 0.65 * @abs(@sin(t * 7.0)) * @max(0, @sin(t * 1.3)),
    };
}

test {
    _ = levels;
    _ = boids;
    _ = predators;
    _ = @import("sim_test.zig");
    _ = @import("robot.zig");
}
