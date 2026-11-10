//! The pictures, made in code: a soft glow, a disc and the night sky's
//! gradient. Placeholder art is drawn from these and plain rectangles.

const std = @import("std");
const pequi = @import("pequi");
const draw = pequi.render;

const glow_size = 64;
const disc_size = 64;
const sky_rows = 64;

/// The light map: every light added together, at a quarter of the screen.
pub const light_width = 135;
pub const light_height = 300;
/// The lit colors of the scene, before they are added over the silhouettes.
pub const color_width = 540;
pub const color_height = 1200;

pub const Art = extern struct {
    textures: draw.Textures = .{},
    glow: pequi.Texture = .{},
    disc: pequi.Texture = .{},
    /// A pool of light for the light map: even in the middle, soft at the rim.
    pool: pequi.Texture = .{},
    sky: pequi.Texture = .{},
    light: pequi.Texture = .{},
    color: pequi.Texture = .{},
    created: bool = false,
    uploaded: bool = false,

    /// Call every frame until `uploaded` (again after the GPU lost its textures).
    pub fn upload(art: *Art, render: *pequi.RenderCommands) void {
        if (!art.created) {
            art.glow = art.textures.create(glow_size, glow_size);
            art.disc = art.textures.create(disc_size, disc_size);
            art.pool = art.textures.create(glow_size, glow_size);
            art.sky = art.textures.create(1, sky_rows);
            art.light = art.textures.create(light_width, light_height);
            art.color = art.textures.create(color_width, color_height);
            art.created = true;
        }

        var glow: [glow_size * glow_size]u32 = undefined;
        var disc: [disc_size * disc_size]u32 = undefined;
        var pool: [glow_size * glow_size]u32 = undefined;
        for (0..glow_size) |y| {
            for (0..glow_size) |x| {
                const fx = (@as(f32, @floatFromInt(x)) + 0.5) / glow_size * 2 - 1;
                const fy = (@as(f32, @floatFromInt(y)) + 0.5) / glow_size * 2 - 1;
                const r = @sqrt(fx * fx + fy * fy);
                // Bright in the middle, a long soft skirt, nothing at the edge.
                const a = std.math.clamp(1 - r, 0, 1);
                glow[y * glow_size + x] = draw.color(1, 1, 1, a * a * (3 - 2 * a) * a);
                const p = std.math.clamp(a * 1.6, 0, 1);
                pool[y * glow_size + x] = draw.color(1, 1, 1, p * p * (3 - 2 * p));
                // A filled circle with a pixel of soft edge.
                disc[y * disc_size + x] = draw.color(1, 1, 1, std.math.clamp((0.97 - r) * disc_size / 2, 0, 1));
            }
        }
        var sky: [sky_rows]u32 = undefined;
        for (0..sky_rows) |y| {
            const t = @as(f32, @floatFromInt(y)) / (sky_rows - 1);
            // Deep blue above, a faint glow of the horizon below.
            sky[y] = draw.rgb(0.012 + 0.03 * t * t, 0.02 + 0.055 * t, 0.055 + 0.085 * t);
        }
        const ok_glow = draw.uploadTexture(render, art.glow, &glow, .linear);
        const ok_disc = draw.uploadTexture(render, art.disc, &disc, .linear);
        const ok_sky = draw.uploadTexture(render, art.sky, &sky, .linear);
        const ok_pool = draw.uploadTexture(render, art.pool, &pool, .linear);
        art.uploaded = ok_glow and ok_disc and ok_sky and ok_pool;
    }
};
