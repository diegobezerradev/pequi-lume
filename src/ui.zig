//! The game's own widgets, drawn with light: text in the game's font and
//! round buttons big enough for a thumb.

const std = @import("std");
const pequi = @import("pequi");
const draw = pequi.render;
const Art = @import("art.zig").Art;
const Pointer = @import("input.zig").Pointer;

/// The smallest side of anything to be touched, in virtual units: 48 dp on
/// this screen, and never so small that it looks lost on a big one.
pub fn touchSize(input: *const pequi.Input, render: *const pequi.RenderCommands) f32 {
    return std.math.clamp(input.dpToVirtual(48, render.width), 60, 96);
}

pub const text_color = draw.rgb(0.82, 0.87, 0.95);
pub const light_color = draw.rgb(0.82, 1, 0.45);

pub const Ui = struct {
    render: *pequi.RenderCommands,
    art: *const Art,
    /// Null until the pack's font is loaded: then the built-in one is used.
    font: ?*const draw.Font,
    pointer: Pointer,
    /// See `touchSize`.
    touch: f32,

    pub fn init(input: *const pequi.Input, render: *pequi.RenderCommands, art: *const Art, font: ?*const draw.Font, pointer: Pointer) Ui {
        return .{ .render = render, .art = art, .font = font, .pointer = pointer, .touch = touchSize(input, render) };
    }

    pub fn width(ui: *const Ui, size: f32, bytes: []const u8) f32 {
        if (ui.font) |font| return draw.textFontWidth(font, size / font.size, bytes);
        return draw.textWidth(size * 0.7, bytes);
    }

    pub fn text(ui: *const Ui, x: f32, y: f32, size: f32, bytes: []const u8, rgba: u32) void {
        if (ui.font) |font| {
            draw.textFont(ui.render, font, x, y, size / font.size, bytes, rgba);
        } else {
            draw.text(ui.render, x, y, size * 0.7, bytes, rgba);
        }
    }

    /// Text centered on `cx`, its top at `y`.
    pub fn centered(ui: *const Ui, cx: f32, y: f32, size: f32, bytes: []const u8, rgba: u32) void {
        ui.text(cx - ui.width(size, bytes) / 2, y, size, bytes, rgba);
    }

    fn inside(x: f32, y: f32, cx: f32, cy: f32, w: f32, h: f32) bool {
        return @abs(x - cx) <= w / 2 and @abs(y - cy) <= h / 2;
    }

    /// True on the frame a press that began on (cx, cy, w, h) ends on it.
    pub fn pressed(ui: *const Ui, cx: f32, cy: f32, w: f32, h: f32) bool {
        const p = ui.pointer;
        return p.released and inside(p.x, p.y, cx, cy, w, h) and inside(p.press_x, p.press_y, cx, cy, w, h);
    }

    pub fn held(ui: *const Ui, cx: f32, cy: f32, w: f32, h: f32) bool {
        const p = ui.pointer;
        return p.down and inside(p.x, p.y, cx, cy, w, h) and inside(p.press_x, p.press_y, cx, cy, w, h);
    }

    /// A pill of soft light with a label, as tall as a touch target.
    pub fn button(ui: *const Ui, cx: f32, cy: f32, w: f32, label: []const u8, alpha: f32) bool {
        const h = ui.touch;
        const down = ui.held(cx, cy, w, h);
        const tint = draw.color(0.75, 1, 0.45, (if (down) @as(f32, 0.34) else 0.17) * alpha);
        const r = h / 2;
        // Two half discs for the round ends, a rectangle between them.
        draw.sprite(ui.render, ui.art.disc, cx - w / 2, cy - r, cx - w / 2 + r, cy + r, .{ .max_u = 0.5 }, tint);
        draw.sprite(ui.render, ui.art.disc, cx + w / 2 - r, cy - r, cx + w / 2, cy + r, .{ .min_u = 0.5 }, tint);
        draw.rect(ui.render, cx - w / 2 + r, cy - r, cx + w / 2 - r, cy + r, tint);
        const size: f32 = 26;
        ui.centered(cx, cy - size * 0.62, size, label, draw.color(0.9, 1, 0.7, alpha));
        return alpha > 0.5 and ui.pressed(cx, cy, w, h);
    }

    /// A star made of light: bright when earned, a dim dot when not.
    pub fn star(ui: *const Ui, cx: f32, cy: f32, size: f32, on: bool, alpha: f32) void {
        draw.setBlend(ui.render, .additive);
        const r: f32 = if (on) size else size * 0.45;
        const tint = if (on) draw.color(1, 0.93, 0.5, alpha) else draw.color(0.5, 0.55, 0.7, 0.45 * alpha);
        draw.sprite(ui.render, ui.art.glow, cx - r, cy - r, cx + r, cy + r, .{}, tint);
        if (on) draw.sprite(ui.render, ui.art.disc, cx - size * 0.16, cy - size * 0.16, cx + size * 0.16, cy + size * 0.16, .{}, draw.color(1, 1, 0.85, alpha));
        draw.setBlend(ui.render, .alpha);
    }
};
