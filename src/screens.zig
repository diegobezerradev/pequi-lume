//! The screens around the levels: the title, the map of the 12 levels and
//! the settings.

const std = @import("std");
const pequi = @import("pequi");
const draw = pequi.render;
const juice = pequi.juice;
const levels = @import("levels.zig");
const Progress = @import("progress.zig").Progress;
const game = @import("game.zig");
const ui_mod = @import("ui.zig");
const art_mod = @import("art.zig");
const Ui = ui_mod.Ui;

pub const Action = union(enum) {
    none,
    title,
    map,
    settings,
    play: u32,
};

/// The night behind the menus: the sky, the cerrado in silhouette on the
/// horizon, and fireflies drifting far away.
pub fn backdrop(ui: *const Ui, time: f32, tint: u32) void {
    const render = ui.render;
    const art = ui.art;
    const w: f32 = @floatFromInt(render.width);
    const h: f32 = @floatFromInt(render.height);
    draw.clear(render, 0, 0, 0);
    game.drawSky(render, art, 0.15 + 0.05 * @sin(time * 0.05), tint);
    draw.setScreenSpace(render);

    // Two ridges of hills, the far one paler, then trees close by.
    const hills = art.get(.hills);
    if (hills.width != 0) {
        const strip_h: f32 = 150;
        const strip_w = strip_h * @as(f32, @floatFromInt(hills.width)) / @as(f32, @floatFromInt(hills.height));
        draw.sprite(render, hills, 0, h - 250, w, h - 250 + strip_h, .{ .min_u = 0.2, .max_u = 0.2 + w / strip_w }, draw.rgb(0.05, 0.1, 0.2));
        draw.sprite(render, hills, 0, h - 170, w, h - 170 + strip_h * 1.2, .{ .min_u = 0.65, .max_u = 0.65 + w / (strip_w * 1.2) }, draw.rgb(0.025, 0.05, 0.11));
        draw.rect(render, 0, h - 60, w, h, draw.rgb(0.025, 0.05, 0.11));
    }
    const dark = draw.rgb(0.03, 0.05, 0.1);
    const trees = [_]struct { art_mod.Picture, f32, f32 }{
        .{ .buriti, 0.1, 330 }, .{ .pequi, 0.86, 250 }, .{ .canela, 0.3, 110 }, .{ .tree, 0.62, 170 }, .{ .buriti, 0.97, 260 },
    };
    for (trees, 0..) |t, i| {
        const sway = @sin(time * 0.8 + @as(f32, @floatFromInt(i)) * 1.7) * 0.012;
        game.stand(render, art, t[0], w * t[1], h + 14, t[2], sway, dark, i % 2 == 1);
    }

    draw.setBlend(render, .additive);
    for (0..26) |i| {
        const fi: f32 = @floatFromInt(i);
        const x = @mod(fi * 97.3 + @sin(time * 0.21 + fi) * 40, w);
        const y = @mod(fi * 61.7 + @cos(time * 0.17 + fi * 1.3) * 30 + h * 0.2, h * 0.75) + h * 0.15;
        const b = 0.5 + 0.5 * @sin(time * (0.8 + @mod(fi, 5) * 0.3) + fi * 2);
        const r = 5 + @mod(fi, 4) * 2.5;
        draw.sprite(render, art.glow, x - r, y - r, x + r, y + r, .{}, draw.color(0.75, 1, 0.4, 0.7 * b * b));
    }
    draw.setBlend(render, .alpha);
}

pub fn title(ui: *const Ui, input: *const pequi.Input, time: f32) Action {
    const render = ui.render;
    const w: f32 = @floatFromInt(render.width);
    const h: f32 = @floatFromInt(render.height);
    backdrop(ui, time, draw.white);

    // The name, with a light of its own that breathes.
    const y = h * 0.24;
    const breath = 0.75 + 0.25 * @sin(time * 1.3);
    draw.setBlend(render, .additive);
    draw.sprite(render, ui.art.glow, w / 2 - 260, y - 130, w / 2 + 260, y + 250, .{}, draw.color(0.7, 1, 0.35, 0.3 * breath));
    draw.setBlend(render, .alpha);
    ui.centered(w / 2, y, 124, "Lume", draw.rgb(0.88, 1, 0.55));
    ui.centered(w / 2, y + 150, 20, "uma noite no cerrado", draw.rgb(0.6, 0.66, 0.78));

    const bottom = h - input.safe_area.bottom;
    if (ui.button(w / 2, bottom - 150 - ui.touch - 18, 300, "Jogar", 1)) return .map;
    if (ui.button(w / 2, bottom - 150, 300, "Ajustes", 1)) return .settings;
    return .none;
}

pub const region_names = [_][]const u8{ "Vereda", "Campo Sujo", "Chapada" };

pub fn map(ui: *const Ui, input: *const pequi.Input, time: f32, progress: *Progress) Action {
    const render = ui.render;
    const w: f32 = @floatFromInt(render.width);
    const h: f32 = @floatFromInt(render.height);
    backdrop(ui, time, draw.white);
    var buffer: [48]u8 = undefined;

    const top = input.safe_area.top + 20;
    const bottom = h - input.safe_area.bottom;
    const back_x = input.safe_area.left + ui.touch / 2 + 6;
    const back_y = top + ui.touch / 2 - 12;
    // Back: an arrow made of two strokes.
    const back_alpha: f32 = if (ui.held(back_x, back_y, ui.touch, ui.touch)) 1 else 0.6;
    draw.spriteRotated(render, ui.art.disc, back_x - 2, back_y - 7, 24, 5, -0.75, .{}, draw.color(0.85, 0.9, 1, back_alpha));
    draw.spriteRotated(render, ui.art.disc, back_x - 2, back_y + 7, 24, 5, 0.75, .{}, draw.color(0.85, 0.9, 1, back_alpha));
    if (ui.pressed(back_x, back_y, ui.touch, ui.touch) or ui.pointer.back) return .title;

    const stars = std.fmt.bufPrint(&buffer, "{d} / {d}", .{ progress.total(), levels.all.len * 3 }) catch "";
    ui.star(w - input.safe_area.right - 34 - ui.width(22, stars) - 16, back_y, 20, true, 1);
    ui.text(w - input.safe_area.right - 24 - ui.width(22, stars), back_y - 14, 22, stars, ui_mod.text_color);

    // Debug builds: Enter opens every level (not saved).
    if (pequi.internal and ui.pointer.robot) {
        for (progress.stars[0..levels.all.len]) |*s| s.* = @max(s.*, 1);
    }

    // Three regions, four mounds each. Lit mounds are levels already won.
    const room = bottom - top - 90;
    const block = @min(310, room / 3);
    var action: Action = .none;
    for (0..3) |region| {
        const by = top + 80 + (room - block * 3) / 2 + block * @as(f32, @floatFromInt(region));
        ui.centered(w / 2, by, 26, region_names[region], draw.rgb(0.7, 0.76, 0.88));
        // The mound shrinks on short screens so three rows always fit.
        const mound_h = std.math.clamp(block * 0.37, 56, 104);
        for (0..4) |i| {
            const index: u32 = @intCast(region * 4 + i);
            const cx = w / 2 + (@as(f32, @floatFromInt(i)) - 1.5) * 118;
            const number_y = by + 36 + @sin(@as(f32, @floatFromInt(index)) * 1.9) * 6;
            const base_y = number_y + 26 + mound_h;
            const cy = base_y - mound_h / 2;
            const hit_h = mound_h + 70;
            const open = progress.isOpen(index);
            const won = progress.stars[index] > 0;
            const held = open and ui.held(cx, cy + 6, 104, hit_h);

            // The mound: lit if won, a dark shape waiting if open, barely
            // there if still closed.
            if (won or open) {
                draw.setBlend(render, .additive);
                const beat: f32 = if (won) 0.55 else 0.25 + 0.2 * @sin(time * 3);
                draw.sprite(render, ui.art.glow, cx - mound_h * 0.75, cy - mound_h * 0.8, cx + mound_h * 0.75, cy + mound_h * 0.75, .{}, if (won) draw.color(0.7, 1, 0.4, beat) else draw.color(0.6, 0.7, 1, beat));
                draw.setBlend(render, .alpha);
            }
            const grow: f32 = if (held) 1.08 else 1;
            const body = if (won) draw.white else if (open) draw.rgb(0.2, 0.26, 0.42) else draw.rgb(0.06, 0.08, 0.14);
            game.stand(render, ui.art, .mound, cx, base_y + mound_h * 0.03, mound_h * grow, 0, body, index % 2 == 1);
            if (won) {
                // Its larvae, twinkling.
                draw.setBlend(render, .additive);
                for (0..9) |k| {
                    const fk: f32 = @floatFromInt(k);
                    const lx = cx + @sin(fk * 2.4 + @as(f32, @floatFromInt(index))) * (0.2 - fk * 0.016) * mound_h;
                    const ly = base_y - mound_h * (0.12 + fk * 0.08);
                    const b = 0.6 + 0.4 * @sin(time * 4 + fk * 1.7);
                    draw.sprite(render, ui.art.glow, lx - 7, ly - 7, lx + 7, ly + 7, .{}, draw.color(0.7, 1, 0.5, b));
                }
                draw.setBlend(render, .alpha);
            }
            const number = std.fmt.bufPrint(&buffer, "{d}", .{index + 1}) catch "";
            ui.centered(cx, number_y, 22, number, if (open) draw.rgb(0.9, 0.95, 1) else draw.rgb(0.25, 0.28, 0.38));
            if (open) {
                for (0..3) |k| ui.star(cx + (@as(f32, @floatFromInt(k)) - 1) * 26, base_y + 16, 13, k < progress.stars[index], 1);
                if (ui.pressed(cx, cy + 6, 104, hit_h)) action = .{ .play = index };
            }
        }
    }
    return action;
}

pub fn settings(ui: *const Ui, menu: *pequi.ui.Ui, input: *pequi.Input, time: f32, volumes: *pequi.audio.Volumes, mixer: *pequi.audio.Mixer, fullscreen: *bool) Action {
    backdrop(ui, time, draw.white);
    var action: Action = .none;
    var m = pequi.ui.begin(menu, input, ui.render, ui.menuFont(), .{ .title = "Ajustes", .theme = game.theme, .item_height = ui.touch, .width = 440 });
    var changed = m.slider("Ambiente", &volumes.music, 0, 1);
    changed = m.slider("Efeitos", &volumes.effects, 0, 1) or changed;
    if (@import("builtin").os.tag == .windows) _ = m.toggle("Tela cheia", fullscreen);
    if (m.button("Voltar") or ui.pointer.back) action = .title;
    m.end();
    if (changed) volumes.apply(mixer);
    if (action != .none) game.saveVolumes(volumes);
    return action;
}
