//! The pictures. The illustrations come from the asset pack (drawn by
//! tools/art.py at three pixels per world unit, so they stay sharp on a
//! tablet); the lights are soft shapes made here in code; and two render
//! targets hold the light map and the lit colors of the scene.

const std = @import("std");
const pequi = @import("pequi");
const draw = pequi.render;

const glow_size = 128;
const disc_size = 256;

/// The light map: every light added together. Light is soft, so it is
/// small; it is stretched over the screen.
pub const light_width = 270;
pub const light_height = 600;
/// The lit colors are drawn at the screen's own resolution, up to this width.
const color_max_width = 1440;

/// World units per pixel of an illustration.
pub const unit: f32 = 1.0 / 3.0;

/// The illustrations, by the name they have in the pack.
pub const Picture = enum {
    sky,
    hills,
    ground,
    pond,
    reeds,
    pequi,
    buriti,
    canela,
    tree,
    bush,
    tuft,
    mound,
    frog,
    spider,
    owl_body,
    owl_wing,
    wolf_body,
    wolf_leg,
    branch,
};
const picture_count = @typeInfo(Picture).@"enum".field_names.len;

/// The font in three sizes; text picks the one nearest its size on screen.
const font_names = [_][]const u8{ "ui_s", "ui_m", "ui_l" };

pub const Art = struct {
    textures: draw.Textures = .{},
    /// `textures` with only the shapes and targets made: where loading starts.
    base: draw.Textures = .{},
    glow: pequi.Texture = .{},
    disc: pequi.Texture = .{},
    /// A pool of light for the light map: even in the middle, soft at the rim.
    pool: pequi.Texture = .{},
    light: pequi.Texture = .{},
    color: pequi.Texture = .{},
    pictures: [picture_count]pequi.Texture = @splat(.{}),
    fonts: [font_names.len]draw.Font = undefined,
    created: bool = false,
    shapes_uploaded: bool = false,
    /// How many pictures and fonts are loaded so far.
    pictures_loaded: u32 = 0,
    fonts_loaded: u32 = 0,
    failed: bool = false,

    pub fn ready(art: *const Art) bool {
        return art.shapes_uploaded and art.pictures_loaded == picture_count and art.fonts_loaded == font_names.len;
    }

    /// 0 to 1, for a loading bar.
    pub fn progress(art: *const Art) f32 {
        const done: f32 = @floatFromInt(art.pictures_loaded + art.fonts_loaded);
        return done / @as(f32, picture_count + font_names.len);
    }

    pub fn get(art: *const Art, picture: Picture) pequi.Texture {
        return art.pictures[@backingInt(picture)];
    }

    /// The font whose own size is nearest above `pixels`, so text is never
    /// stretched much (stretched text is what looks blurred).
    pub fn font(art: *const Art, pixels: f32) ?*const draw.Font {
        if (art.fonts_loaded < font_names.len) return null;
        for (&art.fonts) |*f| {
            if (f.size >= pixels * 0.85) return f;
        }
        return &art.fonts[font_names.len - 1];
    }

    /// After the GPU lost its textures: everything is sent again, into the
    /// same slots (loading always goes in the same order).
    pub fn lost(art: *Art) void {
        art.textures = art.base;
        art.shapes_uploaded = false;
        art.pictures_loaded = 0;
        art.fonts_loaded = 0;
    }

    /// Call every frame until `ready`: loads as much as fits in a frame.
    pub fn load(art: *Art, pack: ?*const pequi.assets.Pack, api: *const pequi.platform.PlatformApi, arena: *pequi.Arena, render: *pequi.RenderCommands) void {
        if (!art.created) {
            art.glow = art.textures.create(glow_size, glow_size);
            art.disc = art.textures.create(disc_size, disc_size);
            art.pool = art.textures.create(glow_size, glow_size);
            art.light = art.textures.create(light_width, light_height);
            art.color = art.textures.create(540, 1200);
            art.base = art.textures;
            art.created = true;
        }
        if (!art.shapes_uploaded) art.uploadShapes(arena, render);
        const p = pack orelse return;
        if (art.failed) return;
        while (art.fonts_loaded < font_names.len) {
            // A load that does not fit this frame must not keep its slot.
            const before = art.textures;
            const slot = &art.fonts[art.fonts_loaded];
            slot.* = p.loadFont(api, arena, render, &art.textures, font_names[art.fonts_loaded]) catch |err| {
                art.textures = before;
                if (err != error.NoRoomThisFrame) art.fail(font_names[art.fonts_loaded], err);
                return;
            };
            art.fonts_loaded += 1;
        }
        while (art.pictures_loaded < picture_count) {
            const name = @typeInfo(Picture).@"enum".field_names[art.pictures_loaded];
            const before = art.textures;
            art.pictures[art.pictures_loaded] = p.loadBitmap(api, arena, render, &art.textures, name) catch |err| {
                art.textures = before;
                if (err != error.NoRoomThisFrame) art.fail(name, err);
                return;
            };
            art.pictures_loaded += 1;
        }
    }

    fn fail(art: *Art, name: []const u8, err: anyerror) void {
        pequi.log("lume: could not load {s}: {s}", .{ name, @errorName(err) });
        art.failed = true;
    }

    fn uploadShapes(art: *Art, arena: *pequi.Arena, render: *pequi.RenderCommands) void {
        const temp = arena.beginTemp();
        defer temp.end();
        const glow = arena.pushArray(u32, glow_size * glow_size);
        const pool = arena.pushArray(u32, glow_size * glow_size);
        const disc = arena.pushArray(u32, disc_size * disc_size);
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
            }
        }
        for (0..disc_size) |y| {
            for (0..disc_size) |x| {
                const fx = (@as(f32, @floatFromInt(x)) + 0.5) / disc_size * 2 - 1;
                const fy = (@as(f32, @floatFromInt(y)) + 0.5) / disc_size * 2 - 1;
                const r = @sqrt(fx * fx + fy * fy);
                // A filled circle with a pixel of soft edge.
                disc[y * disc_size + x] = draw.color(1, 1, 1, std.math.clamp((0.985 - r) * disc_size / 2, 0, 1));
            }
        }
        const ok_glow = draw.uploadTexture(render, art.glow, glow, .linear);
        const ok_pool = draw.uploadTexture(render, art.pool, pool, .linear);
        const ok_disc = draw.uploadTexture(render, art.disc, disc, .mipmapped);
        art.shapes_uploaded = ok_glow and ok_pool and ok_disc;
    }

    /// The lit colors are drawn as sharp as the screen: the target follows
    /// the window's size in pixels.
    pub fn fitColorTarget(art: *Art, input: *const pequi.Input, render: *const pequi.RenderCommands) void {
        if (input.window_width == 0 or render.width == 0) return;
        const w: u32 = @min(@max(input.window_width, 540), color_max_width);
        const h: u32 = w * render.height / render.width;
        art.color.width = w;
        art.color.height = h;
    }
};
