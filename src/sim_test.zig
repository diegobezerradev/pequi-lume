//! Tests of the simulation, with no window: rules, predators, determinism.

const std = @import("std");
const sim = @import("sim.zig");
const levels = @import("levels.zig");
const testing = std.testing;
const Sim = sim.Sim;
const tune = sim.tune;

/// An empty field with a swarm of `count` around (x, y).
fn field(count: u32, x: f32, y: f32) Sim {
    var s: Sim = .{ .width = 4000, .height = 4000, .mound_x = 3900, .mound_y = 3900, .need = 5, .random = 77 };
    for (0..count) |i| {
        const a = @as(f32, @floatFromInt(i)) * 2.4;
        const r: f32 = if (i == 0) 0 else 10 + @as(f32, @floatFromInt(i % 7)) * 4;
        s.addFly(.swarm, x + @cos(a) * r, y + @sin(a) * r);
    }
    return s;
}

fn addFrog(s: *Sim, x: f32, y: f32) void {
    s.frogs[s.frog_count] = .{ .x = x, .y = y };
    s.frog_count += 1;
}

fn run(s: *Sim, seconds: f32, controls: sim.Controls, events: *sim.Events) void {
    const steps: u32 = @intFromFloat(seconds / sim.dt);
    for (0..steps) |_| s.step(controls, events);
}

fn countState(s: *const Sim, state: sim.FlyState) u32 {
    var n: u32 = 0;
    for (s.flies[0..s.fly_count]) |f| {
        if (f.state == state) n += 1;
    }
    return n;
}

fn scripted(step: u32) sim.Controls {
    const t = @as(f32, @floatFromInt(step)) * sim.dt;
    return .{
        .target_x = 540 + @sin(t * 0.5) * 300,
        .target_y = 2250 - t * 60,
        .guiding = true,
        .pulse = step % 300 == 150,
        .dark = step % 1000 > 900,
    };
}

test "same level and controls: the same game, step by step" {
    var a = Sim.init(0);
    var b = Sim.init(0);
    var ea: sim.Events = .{};
    var eb: sim.Events = .{};
    for (0..4000) |i| {
        const c = scripted(@intCast(i));
        a.step(c, &ea);
        b.step(c, &eb);
        if (i % 500 == 0) try testing.expectEqual(a.checksum(), b.checksum());
    }
    try testing.expectEqual(a.checksum(), b.checksum());
    try testing.expectEqual(ea.count, eb.count);

    // And other controls give another game.
    var c = Sim.init(0);
    var ec: sim.Events = .{};
    for (0..4000) |i| {
        var controls = scripted(@intCast(i));
        controls.target_x += 200;
        c.step(controls, &ec);
    }
    try testing.expect(c.checksum() != a.checksum());
}

test "the swarm count is the number of fireflies in the swarm" {
    var s = Sim.init(0);
    var e: sim.Events = .{};
    for (0..6000) |i| {
        s.step(scripted(@intCast(i)), &e);
        if (i % 97 == 0) try testing.expectEqual(countState(&s, .swarm), s.swarm);
    }
}

test "the swarm's light brings in a lost firefly; rescues in a row count up" {
    var s = field(3, 500, 500);
    s.addFly(.lost, 560, 500);
    s.addFly(.lost, 500, 565);
    var e: sim.Events = .{};
    run(&s, 0.5, .{}, &e);
    try testing.expectEqual(@as(u32, 5), s.swarm);
    try testing.expectEqual(@as(usize, 2), e.count);
    try testing.expectEqual(sim.EventKind.rescued, e.items[0].kind);
    try testing.expectEqual(@as(u32, 1), e.items[0].value);
    try testing.expectEqual(@as(u32, 2), e.items[1].value);
}

test "a dark swarm rescues no one" {
    var s = field(3, 500, 500);
    s.addFly(.lost, 560, 500);
    var e: sim.Events = .{};
    run(&s, 2, .{ .dark = true }, &e);
    try testing.expectEqual(@as(u32, 3), s.swarm);
}

test "a pulse calls lost fireflies from far away, and has a cooldown" {
    var s = field(3, 500, 500);
    s.addFly(.lost, 500 + tune.pulse_call_radius - 30, 500);
    s.addFly(.lost, 500 + tune.pulse_call_radius + 60, 500);
    var e: sim.Events = .{};
    s.step(.{ .pulse = true }, &e);
    try testing.expect(e.has(.pulse));
    try testing.expectEqual(@as(u32, 1), countState(&s, .called));
    s.step(.{ .pulse = true }, &e);
    try testing.expect(e.has(.pulse_denied));
    run(&s, 4, .{}, &e);
    try testing.expectEqual(@as(u32, 4), s.swarm);
    try testing.expectEqual(@as(u32, 1), countState(&s, .lost));
}

test "a called firefly that never arrives gives up" {
    var s = field(1, 500, 500);
    s.addFly(.lost, 800, 500);
    var e: sim.Events = .{};
    s.step(.{ .pulse = true }, &e);
    // The leader runs away from it, in the dark, slower than the caller...
    s.flies[1].timer = 0.2;
    run(&s, 0.5, .{}, &e);
    try testing.expectEqual(@as(u32, 1), countState(&s, .lost));
}

test "frog: swells, then takes the nearest shining firefly in reach" {
    var s = field(4, 500, 500);
    addFrog(&s, 500 + tune.frog_range - 40, 500);
    var e: sim.Events = .{};
    s.step(.{}, &e);
    try testing.expect(e.has(.frog_windup));
    try testing.expect(!e.has(.taken));
    run(&s, tune.frog_windup + 0.1, .{}, &e);
    try testing.expect(e.has(.taken));
    try testing.expectEqual(@as(u32, 3), s.swarm);
    // The leader is not the one taken while others are left.
    try testing.expectEqual(sim.FlyState.swarm, s.flies[sim.leader].state);
    // It strikes again only after its cooldown.
    run(&s, tune.frog_cooldown * 0.5, .{}, &e);
    try testing.expectEqual(@as(u32, 3), s.swarm);
    run(&s, tune.frog_cooldown + tune.frog_windup, .{}, &e);
    try testing.expectEqual(@as(u32, 2), s.swarm);
}

test "frog: out of reach, nothing happens" {
    var s = field(4, 500, 500);
    addFrog(&s, 500 + tune.frog_range + 80, 500);
    var e: sim.Events = .{};
    run(&s, 4, .{}, &e);
    try testing.expectEqual(@as(u32, 4), s.swarm);
    try testing.expectEqual(@as(usize, 0), e.count);
}

test "frog: cannot see a dark swarm" {
    var s = field(4, 500, 500);
    addFrog(&s, 560, 500);
    var e: sim.Events = .{};
    // Dark before the frog has time to strike.
    run(&s, 5, .{ .dark = true }, &e);
    try testing.expectEqual(@as(u32, 4), s.swarm);
    try testing.expect(!e.has(.taken));
}

test "frog: going dark while it swells makes it miss" {
    var s = field(4, 500, 500);
    addFrog(&s, 560, 500);
    var e: sim.Events = .{};
    run(&s, tune.frog_windup * 0.4, .{}, &e);
    try testing.expect(e.has(.frog_windup));
    run(&s, 1, .{ .dark = true }, &e);
    try testing.expect(e.has(.frog_miss));
    try testing.expectEqual(@as(u32, 4), s.swarm);
}

test "frog: a pulse wakes it and it reaches farther" {
    const gap = (tune.frog_range + tune.frog_range_alert) / 2;
    var quiet = field(4, 500, 500);
    addFrog(&quiet, 500 + gap, 500);
    var e: sim.Events = .{};
    run(&quiet, 3, .{}, &e);
    try testing.expectEqual(@as(u32, 4), quiet.swarm);

    var loud = field(4, 500, 500);
    addFrog(&loud, 500 + gap, 500);
    loud.step(.{ .pulse = true }, &e);
    run(&loud, 2, .{}, &e);
    try testing.expect(loud.swarm < 4);
    // After a while it calms down.
    run(&loud, tune.frog_alert_seconds + 3, .{ .dark = true }, &e);
    const before = loud.swarm;
    run(&loud, 3, .{}, &e);
    try testing.expectEqual(before, loud.swarm);
}

test "losing: the leader goes last, and then the level is lost" {
    var s = field(2, 500, 500);
    addFrog(&s, 540, 500);
    var e: sim.Events = .{};
    run(&s, tune.frog_windup + 0.2, .{}, &e);
    try testing.expectEqual(@as(u32, 1), s.swarm);
    try testing.expectEqual(sim.FlyState.swarm, s.flies[sim.leader].state);
    try testing.expectEqual(sim.Outcome.playing, s.outcome);
    run(&s, 6, .{}, &e);
    try testing.expectEqual(@as(u32, 0), s.swarm);
    try testing.expectEqual(sim.Outcome.lost, s.outcome);
    try testing.expect(e.has(.lost));
    // Nothing moves after the end.
    const sum = s.checksum();
    run(&s, 1, .{ .guiding = true, .target_x = 0 }, &e);
    try testing.expectEqual(sum, s.checksum());
}

test "winning: the mound lights with enough fireflies, shining, and not before" {
    var few = field(4, 500, 500);
    few.mound_x = 520;
    few.mound_y = 500;
    var e: sim.Events = .{};
    run(&few, 1, .{}, &e);
    try testing.expectEqual(sim.Outcome.playing, few.outcome);
    try testing.expect(e.has(.mound_denied));
    try testing.expectEqual(@as(u32, 1), e.items[0].value);

    var dark = field(6, 500, 500);
    dark.mound_x = 520;
    dark.mound_y = 500;
    var e2: sim.Events = .{};
    run(&dark, 1, .{ .dark = true }, &e2);
    try testing.expectEqual(sim.Outcome.playing, dark.outcome);
    run(&dark, 0.5, .{}, &e2);
    try testing.expectEqual(sim.Outcome.won, dark.outcome);
    try testing.expect(e2.has(.won));
}

test "stars follow the swarm that reached the mound" {
    const level = levels.get(0);
    var s = Sim.init(0);
    try testing.expectEqual(@as(u32, 0), s.stars());
    s.outcome = .won;
    s.swarm = level.stars[0];
    try testing.expectEqual(@as(u32, 1), s.stars());
    s.swarm = level.stars[1];
    try testing.expectEqual(@as(u32, 2), s.stars());
    s.swarm = level.stars[2] + 3;
    try testing.expectEqual(@as(u32, 3), s.stars());
}

test "shining, the swarm keeps up with the leader" {
    var s = field(40, 300, 300);
    var e: sim.Events = .{};
    run(&s, 20, .{ .guiding = true, .target_x = 3000, .target_y = 2600 }, &e);
    try testing.expectEqual(@as(u32, 40), s.swarm);
    try testing.expect(!e.has(.strayed));
    // And stays a loose ball: no two on the same spot, none far off.
    const me = s.flies[sim.leader];
    for (s.flies[1..s.fly_count]) |f| try testing.expect(sim.distance(f.x, f.y, me.x, me.y) < 150);
}

test "in the dark: standing still is safe, travelling sheds fireflies" {
    var still = field(30, 500, 500);
    var e: sim.Events = .{};
    run(&still, 10, .{ .dark = true }, &e);
    try testing.expectEqual(@as(u32, 30), still.swarm);

    var moving = field(30, 500, 500);
    var e2: sim.Events = .{};
    run(&moving, 14, .{ .dark = true, .guiding = true, .target_x = 3500, .target_y = 500 }, &e2);
    try testing.expect(e2.has(.strayed));
    try testing.expect(moving.swarm < 30);
    try testing.expect(moving.swarm > 8);
    // The strays are lost, not gone: they can be rescued again.
    try testing.expectEqual(30 - moving.swarm, countState(&moving, .lost));
}

test "dark is slower than shining" {
    var lit = field(1, 500, 500);
    var dark = field(1, 500, 500);
    var e: sim.Events = .{};
    run(&lit, 3, .{ .guiding = true, .target_x = 3500, .target_y = 500 }, &e);
    run(&dark, 3, .{ .dark = true, .guiding = true, .target_x = 3500, .target_y = 500 }, &e);
    try testing.expect(dark.flies[0].x - 500 < (lit.flies[0].x - 500) * 0.5);
}

test "200 fireflies fit and stay together" {
    var s = field(sim.max_flies, 2000, 2000);
    var e: sim.Events = .{};
    run(&s, 5, .{ .guiding = true, .target_x = 2600, .target_y = 2300 }, &e);
    try testing.expectEqual(@as(u32, sim.max_flies), s.swarm);
    try testing.expectApproxEqAbs(sim.lightRadius(200, 1), s.lightRadiusNow(), 0.01);
}

test "blink patterns stay between 0 and 1" {
    for (0..4) |p| {
        for (0..600) |i| {
            const b = sim.blink(@intCast(p), 1.7, @as(f32, @floatFromInt(i)) * 0.01);
            try testing.expect(b >= 0 and b <= 1);
        }
    }
}
