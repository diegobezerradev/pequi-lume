//! Plays every level with the robots and prints how it went:
//!
//!     zig build robots
//!
//! "careful" hides from frogs and pulses where it is safe; "greedy" does the
//! same but wants three stars; "careless" never hides.

const std = @import("std");
const lume = @import("lume");
const sim = lume.sim;

const Run = struct { name: []const u8, careful: bool, greedy: bool };
const runs = [_]Run{
    .{ .name = "careful", .careful = true, .greedy = false },
    .{ .name = "greedy", .careful = true, .greedy = true },
    .{ .name = "careless", .careful = false, .greedy = true },
};

pub fn main() void {
    std.debug.print("level  robot     outcome  time  swarm  stars  taken strayed pulses rescued\n", .{});
    for (lume.levels.all, 0..) |level, index| {
        for (runs) |run| {
            const robot: lume.robot.Robot = .{ .careful = run.careful, .goal = if (run.greedy) level.stars[2] else 0 };
            var s = sim.Sim.init(@intCast(index));
            var counts: [@typeInfo(sim.EventKind).@"enum".field_names.len]u32 = @splat(0);
            var events: sim.Events = .{};
            while (s.outcome == .playing and s.time < 600) {
                events.count = 0;
                s.step(robot.think(&s), &events);
                for (events.slice()) |e| counts[@backingInt(e.kind)] += 1;
            }
            std.debug.print("{d:>5}  {s:<9} {s:<8} {d:>4.0}s {d:>5} {d:>6} {d:>6} {d:>7} {d:>6} {d:>7}\n", .{
                index + 1,                                run.name,
                @tagName(s.outcome),                      s.time,
                s.swarm,                                  s.stars(),
                counts[@backingInt(sim.EventKind.taken)], counts[@backingInt(sim.EventKind.strayed)],
                counts[@backingInt(sim.EventKind.pulse)], counts[@backingInt(sim.EventKind.rescued)],
            });
        }
    }
}
