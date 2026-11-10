//! The player's hand, whatever it holds: `pequi.Input` (mouse, fingers,
//! keys) becomes one `Pointer` per frame, and that is all the game reads.
//!
//!   guide: left button or a finger held down, pointing at a place
//!   pulse: a quick tap or click that did not move
//!   dark:  two fingers held, the right button, or Space

const pequi = @import("pequi");

/// A press shorter than this, that stayed in place, is a tap.
const tap_seconds: f32 = 0.24;
const tap_distance: f32 = 16;

pub const Pointer = struct {
    /// In virtual screen units.
    x: f32 = 0,
    y: f32 = 0,
    down: bool = false,
    pressed: bool = false,
    tap: bool = false,
    dark: bool = false,
    back: bool = false,
    /// Debug builds: Enter turns the robot on and off.
    robot: bool = false,
    /// Debug builds: the I key fills the swarm (to measure the frame).
    fill: bool = false,
};

/// What has to be remembered between frames to tell a tap from a drag.
pub const Reader = extern struct {
    held_seconds: f32 = 0,
    press_x: f32 = 0,
    press_y: f32 = 0,
    /// This press moved, or met a second finger: not a tap any more.
    spoiled: bool = false,

    pub fn read(r: *Reader, input: *const pequi.Input) Pointer {
        var p: Pointer = .{ .x = input.mouse.x, .y = input.mouse.y };
        const left = input.mouse.button(.left);

        var fingers: u32 = 0;
        for (input.touches) |t| {
            if (t.down) fingers += 1;
        }
        for (&input.controllers) |*c| {
            if (!c.connected and c != &input.controllers[0]) continue;
            if (c.button(.action_down).isDown()) p.dark = true;
            if (c.button(.back).wasPressed()) p.back = true;
            if (c.button(.start).wasPressed()) p.robot = true;
            if (c.button(.action_up).wasPressed()) p.fill = true;
        }
        if (fingers >= 2 or input.mouse.button(.right).isDown()) p.dark = true;

        p.down = left.isDown();
        p.pressed = left.wasPressed();
        if (p.pressed) {
            r.held_seconds = 0;
            r.press_x = p.x;
            r.press_y = p.y;
            r.spoiled = false;
        }
        if (p.down or left.wasReleased()) {
            r.held_seconds += input.dt;
            const dx = p.x - r.press_x;
            const dy = p.y - r.press_y;
            if (dx * dx + dy * dy > tap_distance * tap_distance or p.dark) r.spoiled = true;
        }
        if (left.wasReleased() and !r.spoiled and r.held_seconds <= tap_seconds) p.tap = true;
        return p;
    }
};

const std = @import("std");
const testing = std.testing;

fn frame(reader: *Reader, down: bool, x: f32, y: f32, was: *bool) Pointer {
    var input: pequi.Input = .{ .dt = 1.0 / 60.0 };
    input.mouse.x = x;
    input.mouse.y = y;
    const b = &input.mouse.buttons[@backingInt(pequi.MouseButton.left)];
    b.ended_down = down;
    b.half_transition_count = if (down != was.*) 1 else 0;
    was.* = down;
    return reader.read(&input);
}

test "a short press in place is a tap; a drag or a long press is not" {
    var r: Reader = .{};
    var was = false;
    _ = frame(&r, true, 100, 100, &was);
    _ = frame(&r, true, 102, 101, &was);
    try testing.expect(frame(&r, false, 102, 101, &was).tap);

    _ = frame(&r, true, 100, 100, &was);
    _ = frame(&r, true, 160, 100, &was);
    try testing.expect(!frame(&r, false, 160, 100, &was).tap);

    _ = frame(&r, true, 100, 100, &was);
    for (0..30) |_| _ = frame(&r, true, 100, 100, &was);
    try testing.expect(!frame(&r, false, 100, 100, &was).tap);
}

test "two fingers mean dark, and their press is no tap" {
    var r: Reader = .{};
    var input: pequi.Input = .{ .dt = 1.0 / 60.0 };
    const b = &input.mouse.buttons[@backingInt(pequi.MouseButton.left)];
    b.ended_down = true;
    b.half_transition_count = 1;
    input.touches[0] = .{ .id = 0, .down = true };
    input.touches[1] = .{ .id = 1, .down = true };
    try testing.expect(r.read(&input).dark);
    b.ended_down = false;
    input.touches[0].down = false;
    input.touches[1].down = false;
    try testing.expect(!r.read(&input).tap);
}
