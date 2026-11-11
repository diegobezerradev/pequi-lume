//! The sounds, made in code when the game starts: one per action, a note
//! that climbs a scale for rescues in a row, the chord of the lit mound,
//! and the night's crickets.

const std = @import("std");
const pequi = @import("pequi");
const synth = pequi.audio.synth;

const rate = 48000;

/// A pentatonic scale, in semitones: rescues in a row climb it.
const scale = [_]f32{ 0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24 };
/// The mound's chord, built one note at a time.
const chord = [_]f32{ -12, -5, 0, 4, 7, 12, 16, 19 };

pub const Sounds = extern struct {
    note: pequi.audio.Sound,
    pulse: pequi.audio.Sound,
    dark_on: pequi.audio.Sound,
    dark_off: pequi.audio.Sound,
    taken: pequi.audio.Sound,
    strayed: pequi.audio.Sound,
    croak: pequi.audio.Sound,
    miss: pequi.audio.Sound,
    denied: pequi.audio.Sound,
    lose: pequi.audio.Sound,
    stuck: pequi.audio.Sound,
    screech: pequi.audio.Sound,
    whoosh: pequi.audio.Sound,
    howl: pequi.audio.Sound,
    /// The night, in layers: each loops, and the region sets the mix.
    crickets: pequi.audio.Sound,
    frogs: pequi.audio.Sound,
    wind: pequi.audio.Sound,
    crickets_handle: pequi.audio.Handle,
    frogs_handle: pequi.audio.Handle,
    wind_handle: pequi.audio.Handle,
    ready: bool,

    pub fn init(s: *Sounds, arena: *pequi.Arena) void {
        // A soft bell around A4: a sine with a quieter octave above it.
        s.note = build(arena, 0.9, &.{
            .{ .wave = .sine, .frequency = 440, .seconds = 0.9, .volume = 0.45, .attack = 0.004, .decay = 0.25, .sustain = 0.25, .release = 0.5 },
            .{ .wave = .sine, .frequency = 880, .seconds = 0.5, .volume = 0.14, .attack = 0.002, .decay = 0.2, .sustain = 0.1, .release = 0.25 },
        }, &.{ 0, 0 });
        s.pulse = build(arena, 1.1, &.{
            .{ .wave = .sine, .frequency = 196, .frequency_end = 392, .seconds = 0.35, .volume = 0.4, .attack = 0.01, .release = 0.2 },
            .{ .wave = .sine, .frequency = 392, .seconds = 1.0, .volume = 0.3, .attack = 0.05, .decay = 0.3, .sustain = 0.3, .release = 0.6 },
            .{ .wave = .sine, .frequency = 587.3, .seconds = 0.9, .volume = 0.16, .attack = 0.08, .decay = 0.3, .sustain = 0.2, .release = 0.5 },
        }, &.{ 0, 0.05, 0.08 });
        s.dark_on = synth.tone(arena, rate, .{ .wave = .sine, .frequency = 330, .frequency_end = 110, .seconds = 0.28, .volume = 0.3, .release = 0.15 });
        s.dark_off = synth.tone(arena, rate, .{ .wave = .sine, .frequency = 165, .frequency_end = 392, .seconds = 0.22, .volume = 0.25, .release = 0.12 });
        s.taken = build(arena, 0.4, &.{
            .{ .wave = .noise, .frequency = 2400, .seconds = 0.07, .volume = 0.35, .attack = 0.001, .decay = 0.03, .sustain = 0.2, .release = 0.03 },
            .{ .wave = .triangle, .frequency = 300, .frequency_end = 70, .seconds = 0.32, .volume = 0.45, .release = 0.15 },
        }, &.{ 0, 0.02 });
        s.strayed = synth.tone(arena, rate, .{ .wave = .sine, .frequency = 660, .frequency_end = 330, .seconds = 0.4, .volume = 0.16, .release = 0.25 });
        s.croak = build(arena, 0.5, &.{
            .{ .wave = .square, .frequency = 82, .frequency_end = 105, .seconds = 0.2, .volume = 0.22, .duty = 0.3, .release = 0.05 },
            .{ .wave = .square, .frequency = 98, .frequency_end = 130, .seconds = 0.24, .volume = 0.26, .duty = 0.3, .release = 0.06 },
        }, &.{ 0, 0.22 });
        s.miss = synth.tone(arena, rate, .{ .wave = .noise, .frequency = 900, .seconds = 0.09, .volume = 0.18, .attack = 0.001, .decay = 0.04, .sustain = 0.1, .release = 0.04 });
        s.denied = build(arena, 0.6, &.{
            .{ .wave = .triangle, .frequency = 196, .seconds = 0.22, .volume = 0.3, .release = 0.1 },
            .{ .wave = .triangle, .frequency = 174.6, .seconds = 0.3, .volume = 0.3, .release = 0.15 },
        }, &.{ 0, 0.2 });
        s.lose = build(arena, 1.6, &.{
            .{ .wave = .sine, .frequency = 392, .frequency_end = 370, .seconds = 0.5, .volume = 0.3, .release = 0.3 },
            .{ .wave = .sine, .frequency = 311, .frequency_end = 294, .seconds = 0.5, .volume = 0.3, .release = 0.3 },
            .{ .wave = .sine, .frequency = 233, .frequency_end = 196, .seconds = 0.9, .volume = 0.32, .release = 0.6 },
        }, &.{ 0, 0.4, 0.8 });
        s.stuck = synth.tone(arena, rate, .{ .wave = .triangle, .frequency = 620, .frequency_end = 520, .seconds = 0.16, .volume = 0.3, .attack = 0.002, .decay = 0.05, .sustain = 0.3, .release = 0.08 });
        s.screech = build(arena, 0.7, &.{
            .{ .wave = .square, .frequency = 1250, .frequency_end = 620, .seconds = 0.55, .volume = 0.16, .duty = 0.2, .attack = 0.03, .release = 0.25 },
            .{ .wave = .noise, .frequency = 5000, .seconds = 0.5, .volume = 0.1, .attack = 0.05, .release = 0.3 },
        }, &.{ 0, 0.02 });
        s.whoosh = synth.tone(arena, rate, .{ .wave = .noise, .frequency = 700, .seconds = 0.35, .volume = 0.3, .attack = 0.08, .decay = 0.1, .sustain = 0.5, .release = 0.15 });
        s.howl = build(arena, 2.2, &.{
            .{ .wave = .sine, .frequency = 294, .frequency_end = 440, .seconds = 0.7, .volume = 0.22, .attack = 0.15, .release = 0.2 },
            .{ .wave = .sine, .frequency = 440, .frequency_end = 392, .seconds = 1.4, .volume = 0.22, .attack = 0.1, .decay = 0.4, .sustain = 0.6, .release = 0.7 },
        }, &.{ 0, 0.6 });
        s.crickets = crickets(arena);
        s.frogs = frogChorus(arena);
        s.wind = windLoop(arena);
        s.crickets_handle = .none;
        s.frogs_handle = .none;
        s.wind_handle = .none;
        s.ready = true;
    }

    /// The night goes on in loops under everything. `mix` is how loud each
    /// layer is here and now: crickets, frogs, wind.
    pub fn ambience(s: *Sounds, mixer: *pequi.audio.Mixer, mix: [3]f32) void {
        if (!s.ready) return;
        const layers = [_]struct { *pequi.audio.Handle, *const pequi.audio.Sound }{
            .{ &s.crickets_handle, &s.crickets },
            .{ &s.frogs_handle, &s.frogs },
            .{ &s.wind_handle, &s.wind },
        };
        for (layers, mix) |layer, volume| {
            if (!mixer.isPlaying(layer[0].*)) {
                layer[0].* = mixer.play(layer[1], .{ .bus = .music, .volume = 0, .looping = true });
            }
            mixer.setVolume(layer[0].*, volume, 0, 0.4);
        }
    }

    /// `streak`: how many were rescued in a row (1 for the first).
    pub fn rescued(s: *const Sounds, mixer: *pequi.audio.Mixer, streak: u32, pan: f32) void {
        const step = scale[@min(streak -| 1, scale.len - 1)];
        _ = mixer.play(&s.note, .{ .volume = 0.8, .pitch = semitones(step), .pan = pan });
    }

    pub fn play(_: *const Sounds, mixer: *pequi.audio.Mixer, sound: *const pequi.audio.Sound, volume: f32, pitch: f32, pan: f32) void {
        _ = mixer.play(sound, .{ .volume = volume, .pitch = pitch, .pan = pan });
    }

    /// Left or right by where it happened on screen.
    pub fn panFor(x: f32, center: f32) f32 {
        return std.math.clamp((x - center) / 400, -0.8, 0.8);
    }

    pub const chord_notes = chord.len;

    /// One note of the mound's chord (0 is the lowest); the game plays them
    /// as the light climbs the mound.
    pub fn chordNote(s: *const Sounds, mixer: *pequi.audio.Mixer, index: usize) void {
        _ = mixer.play(&s.note, .{ .volume = 0.7, .pitch = semitones(chord[@min(index, chord.len - 1)]) * 0.75 });
    }

    /// A star on the end screen: the first, second or third, each higher.
    pub fn star(s: *const Sounds, mixer: *pequi.audio.Mixer, index: usize) void {
        _ = mixer.play(&s.note, .{ .volume = 0.6, .pitch = semitones(12 + 4 * @as(f32, @floatFromInt(index))) });
    }
};

/// The playback speed that raises a sound by `n` semitones.
fn semitones(n: f32) f32 {
    return std.math.pow(f32, 2.0, n / 12.0);
}

/// Several notes into one sound, each starting at its own time.
fn build(arena: *pequi.Arena, seconds: f32, notes: []const synth.Note, starts: []const f32) pequi.audio.Sound {
    const frames: usize = @intFromFloat(seconds * rate);
    const samples = arena.pushArray(i16, frames);
    const temp = arena.beginTemp();
    defer temp.end();
    const buffer = arena.pushArray(f32, frames);
    for (notes, starts) |note, start| synth.addNote(buffer, rate, start, note);
    for (buffer, samples) |value, *out| out.* = @intFromFloat(std.math.clamp(value, -1, 1) * 32767);
    return .{ .samples = samples.ptr, .frame_count = @intCast(frames), .channel_count = 1, .sample_rate = rate };
}

/// Six seconds of wind: a low, soft rush with no hiss in it (noise through
/// two gentle low-pass filters), rising and falling, its end blended into
/// its beginning so the loop has no seam.
fn windLoop(arena: *pequi.Arena) pequi.audio.Sound {
    const seconds: f32 = 6;
    const frames: usize = @intFromFloat(seconds * rate);
    const blend: usize = rate / 2;
    const samples = arena.pushArray(i16, frames);
    const temp = arena.beginTemp();
    defer temp.end();
    const buffer = arena.pushArray(f32, frames + blend);
    var seed: u32 = 0x9e3779b9;
    var low1: f32 = 0;
    var low2: f32 = 0;
    // One-pole low-pass at about 320 Hz, twice.
    const k: f32 = 1 - @exp(-std.math.tau * 320.0 / @as(f32, rate));
    for (buffer, 0..) |*out, i| {
        seed ^= seed << 13;
        seed ^= seed >> 17;
        seed ^= seed << 5;
        const white = @as(f32, @floatFromInt(seed >> 8)) / @as(f32, 1 << 23) - 1;
        low1 += (white - low1) * k;
        low2 += (low1 - low2) * k;
        // Two slow swells whose periods divide the loop.
        const t = @as(f32, @floatFromInt(i % frames)) / @as(f32, rate);
        const swell = 0.7 + 0.2 * @sin(t * std.math.tau / 6) + 0.1 * @sin(t * std.math.tau / 2 + 1);
        out.* = low2 * swell * 6;
    }
    for (samples, 0..) |*out, i| {
        var value = buffer[i];
        if (i < blend) {
            // The start fades in while the overhang past the end fades out.
            const a = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(blend));
            value = value * a + buffer[frames + i] * (1 - a);
        }
        out.* = @intFromFloat(std.math.clamp(value, -1, 1) * 32767);
    }
    return .{ .samples = samples.ptr, .frame_count = @intCast(frames), .channel_count = 1, .sample_rate = rate };
}

/// Eight seconds of frogs far away: low double croaks, now here, now there.
fn frogChorus(arena: *pequi.Arena) pequi.audio.Sound {
    const seconds: f32 = 8;
    const frames: usize = @intFromFloat(seconds * rate);
    const samples = arena.pushArray(i16, frames);
    const temp = arena.beginTemp();
    defer temp.end();
    const buffer = arena.pushArray(f32, frames);
    const calls = [_]struct { f32, f32, f32 }{
        // when, pitch, volume
        .{ 0.3, 92, 0.1 },   .{ 1.9, 110, 0.07 }, .{ 2.6, 84, 0.09 },  .{ 4.2, 98, 0.1 },
        .{ 5.0, 120, 0.06 }, .{ 6.1, 88, 0.09 },  .{ 7.0, 104, 0.07 },
    };
    for (calls) |c| {
        for (0..2) |i| {
            synth.addNote(buffer, rate, c[0] + @as(f32, @floatFromInt(i)) * 0.2, .{ .wave = .square, .frequency = c[1], .frequency_end = c[1] * 1.25, .seconds = 0.16, .volume = c[2], .duty = 0.3, .attack = 0.01, .release = 0.05 });
        }
    }
    for (buffer, samples) |value, *out| out.* = @intFromFloat(std.math.clamp(value, -1, 1) * 32767);
    return .{ .samples = samples.ptr, .frame_count = @intCast(frames), .channel_count = 1, .sample_rate = rate };
}

/// Six seconds of crickets: a few insects, each chirping at its own pace.
fn crickets(arena: *pequi.Arena) pequi.audio.Sound {
    const seconds: f32 = 6;
    const frames: usize = @intFromFloat(seconds * rate);
    const samples = arena.pushArray(i16, frames);
    const temp = arena.beginTemp();
    defer temp.end();
    const buffer = arena.pushArray(f32, frames);
    const voices = [_]struct { f32, f32, f32, f32 }{
        // frequency, seconds between chirps, first chirp, volume
        .{ 4300, 0.75, 0.05, 0.05 },
        .{ 3900, 1.0, 0.4, 0.04 },
        .{ 4700, 1.5, 0.9, 0.03 },
        .{ 3500, 2.0, 0.2, 0.025 },
    };
    for (voices) |v| {
        var t = v[2];
        while (t + 0.25 < seconds) : (t += v[1]) {
            // A chirp is three quick pulses.
            for (0..3) |i| {
                synth.addNote(buffer, rate, t + @as(f32, @floatFromInt(i)) * 0.055, .{ .wave = .sine, .frequency = v[0], .seconds = 0.035, .volume = v[3], .attack = 0.008, .decay = 0.01, .sustain = 0.8, .release = 0.012 });
            }
        }
    }
    for (buffer, samples) |value, *out| out.* = @intFromFloat(std.math.clamp(value, -1, 1) * 32767);
    return .{ .samples = samples.ptr, .frame_count = @intCast(frames), .channel_count = 1, .sample_rate = rate };
}
