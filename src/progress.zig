//! What the player has done: the stars of each level. A level is open when
//! the one before it has been won.

const std = @import("std");
const pequi = @import("pequi");
const levels = @import("levels.zig");

const save_name = "progress";
const save_version = 1;

pub const Progress = extern struct {
    /// Best stars per level; 0 means not won yet.
    stars: [32]u8 = @splat(0),

    pub fn load(api: *const pequi.platform.PlatformApi) Progress {
        return pequi.save.read(api, save_name, save_version, Progress) catch .{};
    }

    pub fn save(p: *const Progress, api: *const pequi.platform.PlatformApi) void {
        pequi.save.write(api, save_name, save_version, p) catch |err| {
            pequi.log("lume: progress not saved: {s}", .{@errorName(err)});
        };
    }

    /// True if this is news (a first win, or more stars than before).
    pub fn record(p: *Progress, level: u32, stars: u32) bool {
        if (level >= levels.all.len or stars <= p.stars[level]) return false;
        p.stars[level] = @intCast(@min(stars, 3));
        return true;
    }

    pub fn isOpen(p: *const Progress, level: u32) bool {
        if (level >= levels.all.len) return false;
        return level == 0 or p.stars[level - 1] > 0;
    }

    /// The level to offer first: the earliest one not won yet.
    pub fn next(p: *const Progress) u32 {
        for (0..levels.all.len) |i| {
            if (p.stars[i] == 0) return @intCast(i);
        }
        return levels.all.len - 1;
    }

    pub fn total(p: *const Progress) u32 {
        var n: u32 = 0;
        for (p.stars[0..levels.all.len]) |s| n += s;
        return n;
    }
};

const testing = std.testing;

test "levels open one after another, and stars only go up" {
    var p: Progress = .{};
    try testing.expect(p.isOpen(0));
    try testing.expect(!p.isOpen(1));
    try testing.expectEqual(@as(u32, 0), p.next());
    try testing.expect(p.record(0, 2));
    try testing.expect(p.isOpen(1));
    try testing.expect(!p.isOpen(2));
    try testing.expect(!p.record(0, 1));
    try testing.expectEqual(@as(u8, 2), p.stars[0]);
    try testing.expect(p.record(0, 3));
    try testing.expectEqual(@as(u32, 1), p.next());
    try testing.expectEqual(@as(u32, 3), p.total());
    try testing.expect(!p.record(99, 3));
    try testing.expect(!p.record(1, 0));
}
