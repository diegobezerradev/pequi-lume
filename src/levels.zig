//! The levels, as data: where things are and what the mound asks for.
//! World units are virtual pixels at zoom 1, y down.

pub const Group = struct {
    x: f32,
    y: f32,
    count: u8,
    /// How far from the middle the fireflies of the group hover.
    spread: f32 = 40,
};

pub const Pond = struct {
    x: f32,
    y: f32,
    rx: f32,
    ry: f32,
    /// Where on the pond's edge the frog sits (radians, 0 = right, clockwise).
    frog_angle: f32,
};

pub const Web = struct {
    x: f32,
    y: f32,
    r: f32 = 70,
};

pub const Owl = struct {
    /// The middle and the size of the round it flies.
    x: f32,
    y: f32,
    rx: f32,
    ry: f32,
    /// Seconds for one round.
    period: f32 = 24,
};

pub const Wind = struct {
    /// Direction (a unit vector).
    dx: f32,
    dy: f32,
    /// The push at the height of a gust.
    strength: f32 = 650,
    /// A gust every `period` seconds, lasting `gust`.
    period: f32 = 11,
    gust: f32 = 4,
};

pub const WolfPath = struct {
    x0: f32,
    y0: f32,
    x1: f32,
    y1: f32,
    /// Seconds into the level when it first comes, and between visits.
    first: f32 = 20,
    period: f32 = 45,
};

pub const Region = enum(u8) { vereda, campo_sujo, chapada };

pub const Level = struct {
    name: []const u8,
    region: Region = .vereda,
    width: f32,
    height: f32,
    start: [2]f32,
    /// Fireflies the player starts with, the leader included.
    start_swarm: u8,
    mound: [2]f32,
    /// Fireflies the mound needs to light up.
    need: u16,
    /// Swarm sizes at the end worth one, two and three stars.
    stars: [3]u16,
    lost: []const Group,
    ponds: []const Pond = &.{},
    webs: []const Web = &.{},
    owls: []const Owl = &.{},
    wind: ?Wind = null,
    wolf: ?WolfPath = null,
    seed: u32,
};

/// The 12 levels: three regions of four (the table is made by tools/levels.py).
pub const all = @import("level_table.zig").all;

pub fn get(index: u32) *const Level {
    return &all[@min(index, all.len - 1)];
}

const std = @import("std");
const sim_limits = @import("sim.zig");

test "there are 12 levels, four in each region, each with room for its things" {
    try std.testing.expectEqual(@as(usize, 12), all.len);
    for (all, 0..) |level, i| try std.testing.expectEqual(@as(usize, i / 4), @backingInt(level.region));
    for (all) |level| {
        var total: u32 = level.start_swarm;
        for (level.lost) |g| total += g.count;
        try std.testing.expect(total <= sim_limits.max_flies);
        try std.testing.expect(level.stars[0] == level.need);
        try std.testing.expect(level.webs.len <= sim_limits.max_webs and level.owls.len <= sim_limits.max_owls and level.ponds.len <= sim_limits.max_frogs);
        try std.testing.expect(level.stars[1] > level.stars[0] and level.stars[2] > level.stars[1]);
        try std.testing.expect(level.stars[2] <= total);
    }
}
