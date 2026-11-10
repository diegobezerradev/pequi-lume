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

pub const Level = struct {
    name: []const u8,
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
    seed: u32,
};

pub const all = [_]Level{
    .{
        .name = "Vereda",
        .width = 1080,
        .height = 3000,
        .start = .{ 540, 2850 },
        .start_swarm = 5,
        .mound = .{ 560, 230 },
        .need = 16,
        .stars = .{ 16, 23, 30 },
        .seed = 0x1a2b3c4d,
        .lost = &.{
            // Out in the open: free, to learn the rescue.
            .{ .x = 360, .y = 2620, .count = 3 },
            .{ .x = 760, .y = 2500, .count = 2 },
            // The first pond: its far side is out of the frog's reach.
            .{ .x = 290, .y = 2170, .count = 4, .spread = 60 },
            .{ .x = 660, .y = 2140, .count = 2, .spread = 30 },
            // Two frogs close a passage, with the best prize in the middle.
            // Around the ponds, by the edges of the map, the way is free.
            .{ .x = 550, .y = 1650, .count = 5, .spread = 40 },
            .{ .x = 110, .y = 1500, .count = 2 },
            .{ .x = 990, .y = 1380, .count = 2 },
            // Over the water, right under a frog.
            .{ .x = 900, .y = 980, .count = 4, .spread = 50 },
            // The last stretch.
            .{ .x = 240, .y = 780, .count = 3 },
            .{ .x = 430, .y = 650, .count = 3, .spread = 45 },
            .{ .x = 780, .y = 520, .count = 2 },
        },
        .ponds = &.{
            .{ .x = 300, .y = 2150, .rx = 190, .ry = 120, .frog_angle = -0.5 },
            .{ .x = 800, .y = 1640, .rx = 170, .ry = 130, .frog_angle = 2.6 },
            .{ .x = 330, .y = 1560, .rx = 120, .ry = 90, .frog_angle = 0.4 },
            .{ .x = 900, .y = 1000, .rx = 150, .ry = 100, .frog_angle = 2.2 },
            .{ .x = 420, .y = 640, .rx = 160, .ry = 100, .frog_angle = -0.9 },
        },
    },
};

pub fn get(index: u32) *const Level {
    return &all[@min(index, all.len - 1)];
}

const std = @import("std");

test "levels fit the swarm and can be won with three stars" {
    for (all) |level| {
        var total: u32 = level.start_swarm;
        for (level.lost) |g| total += g.count;
        try std.testing.expect(total <= @import("sim.zig").max_flies);
        try std.testing.expect(level.stars[0] == level.need);
        try std.testing.expect(level.stars[1] > level.stars[0] and level.stars[2] > level.stars[1]);
        try std.testing.expect(level.stars[2] <= total);
    }
}
