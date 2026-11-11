#!/usr/bin/env python3
"""Synthesizes Lume's music: one quiet loop per region, written to
data/music_<region>.ogg.

    python3 tools/music.py          # needs numpy, scipy and ffmpeg

Everything is in A major and its pentatonic scale, the same notes the game
plays for rescues and for the mound's chord, so those always fit the music.
Each loop ends where it begins: echoes that ring past the end are folded
back onto the start.
"""
import os
import subprocess
import wave

import numpy as np
from scipy import signal

SR = 48000
ROOT = os.path.join(os.path.dirname(__file__), "..")
NOTES = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}


def hz(name):
    """'A4' -> 440.0"""
    pitch, octave = name[:-1], int(name[-1])
    return 440.0 * 2 ** ((NOTES[pitch] - 9) / 12 + octave - 4)


def lowpass(x, f):
    b, a = signal.butter(2, f / (SR / 2), "low")
    return signal.lfilter(b, a, x)


def highpass(x, f):
    b, a = signal.butter(2, f / (SR / 2), "high")
    return signal.lfilter(b, a, x)


def pad(freq, seconds, bright=900):
    """A slow, warm chord tone: a few detuned voices, soft in and out."""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for detune, level in ((-0.004, 0.5), (0, 1), (0.005, 0.5)):
        f = freq * (1 + detune)
        x += level * (np.sin(2 * np.pi * f * t) + 0.35 * np.sin(2 * np.pi * 2 * f * t + 0.5) + 0.15 * np.sin(2 * np.pi * 3 * f * t))
    attack, release = min(1.6, seconds * 0.35), min(2.2, seconds * 0.45)
    e = np.ones(n)
    a, r = int(attack * SR), int(release * SR)
    e[:a] = np.sin(np.linspace(0, np.pi / 2, a)) ** 2
    e[-r:] = np.cos(np.linspace(0, np.pi / 2, r)) ** 2
    # A slow swell, so the chord breathes.
    e *= 0.85 + 0.15 * np.sin(2 * np.pi * 0.11 * t + freq)
    return lowpass(x * e, bright) * 0.2


def viola(freq, seconds, rng, bright=0.5):
    """A plucked steel string, like a viola caipira (Karplus-Strong)."""
    n = int(seconds * SR)
    period = int(SR / freq)
    line = lowpass(rng.uniform(-1, 1, period), 3000 + 5000 * bright)
    out = np.zeros(n)
    damp = 0.996 - 30 / (freq * 400)
    for i in range(n):
        j = i % period
        out[i] = line[j]
        line[j] = damp * 0.5 * (line[j] + line[(j + 1) % period])
    out *= np.exp(-np.arange(n) / SR / (seconds * 0.6))
    return highpass(out, 90) * 0.5


def kalimba(freq, seconds):
    """A thumb piano: a pure tone with a bright tick that dies fast."""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    x = np.sin(2 * np.pi * freq * t) * np.exp(-t / 0.7)
    x += 0.3 * np.sin(2 * np.pi * freq * 5.4 * t) * np.exp(-t / 0.05)
    x += 0.12 * np.sin(2 * np.pi * freq * 2 * t) * np.exp(-t / 0.3)
    x[: int(0.004 * SR)] *= np.linspace(0, 1, int(0.004 * SR))
    return x * 0.4


def flute(freq, seconds, rng):
    """A breathy wooden flute: soft start, vibrato that comes in late."""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    vib = 1 + 0.006 * np.sin(2 * np.pi * 4.8 * t) * np.clip((t - 0.5) / 0.8, 0, 1)
    phase = 2 * np.pi * np.cumsum(freq * vib) / SR
    x = np.sin(phase) + 0.22 * np.sin(2 * phase) + 0.07 * np.sin(3 * phase)
    breath = lowpass(highpass(rng.normal(0, 1, n), freq * 1.5), freq * 5) * 0.07
    e = np.ones(n)
    a, r = int(min(0.22, seconds * 0.3) * SR), int(min(0.6, seconds * 0.4) * SR)
    e[:a] = np.linspace(0, 1, a) ** 1.5
    e[-r:] = np.linspace(1, 0, r) ** 1.5
    return (x + breath) * e * 0.3


def bass(freq, seconds):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    x = np.sin(2 * np.pi * freq * t) + 0.25 * np.sin(2 * np.pi * 2 * freq * t)
    e = np.minimum(1, t / 0.06) * np.exp(-t / (seconds * 0.7))
    return x * e * 0.4


class Loop:
    """A stereo loop of a fixed length; whatever is placed past the end
    wraps around to the beginning."""

    def __init__(self, seconds):
        self.n = int(round(seconds * SR))
        self.left = np.zeros(self.n)
        self.right = np.zeros(self.n)

    def add(self, x, at, pan=0.0, gain=1.0):
        start = int(round(at * SR)) % self.n
        gl, gr = gain * np.cos((pan + 1) * np.pi / 4), gain * np.sin((pan + 1) * np.pi / 4)
        idx = (start + np.arange(len(x))) % self.n
        np.add.at(self.left, idx, x * gl)
        np.add.at(self.right, idx, x * gr)

    def echo(self, seconds, feedback=0.35, wet=0.3, cutoff=2500):
        """A soft echo that wraps around the loop, each side its own delay."""
        for side, delay in ((self.left, seconds), (self.right, seconds * 1.27)):
            d = int(delay * SR)
            tail = lowpass(side.copy(), cutoff)
            total = np.zeros(self.n)
            for k in range(1, 7):
                total += np.roll(tail, d * k) * feedback ** k
            side += total * wet / feedback

    def write(self, name):
        peak = max(np.abs(self.left).max(), np.abs(self.right).max())
        scale = 0.7 / peak
        stereo = np.stack([self.left, self.right], 1) * scale
        wav_path = os.path.join(ROOT, "data", name + ".wav")
        with wave.open(wav_path, "wb") as w:
            w.setnchannels(2)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes((stereo * 32767).astype(np.int16).tobytes())
        ogg_path = os.path.join(ROOT, "data", name + ".ogg")
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", wav_path, "-c:a", "libvorbis", "-q:a", "5", ogg_path], check=True)
        os.remove(wav_path)
        print(f"{name}.ogg  {self.n / SR:.1f} s")


# A major pentatonic, over three octaves: the melody walks on these.
PENTA = ["A3", "B3", "C#4", "E4", "F#4", "A4", "B4", "C#5", "E5", "F#5", "A5"]
CHORDS = {
    "A": ["A2", "E3", "A3", "C#4", "E4"],
    "F#m": ["F#2", "C#3", "F#3", "A3", "C#4"],
    "D": ["D2", "A2", "D3", "F#3", "A3"],
    "E": ["E2", "B2", "E3", "G#3", "B3"],
    "Bm": ["B2", "F#3", "B3", "D4", "F#4"],
    "Esus": ["E2", "B2", "E3", "A3", "B3"],
}


def melody(rng, bars, beats, start=5, rest=0.35, leap=2):
    """A wandering line on the pentatonic scale: mostly steps, some rests,
    coming home to A at the end of every four bars. Returns (beat, note,
    beats long)."""
    out, at, i = [], 0.0, start
    total = bars * beats
    while at < total:
        length = rng.choice([1, 1, 2, 2, 3, 4])
        if at + length > total:
            length = total - at
        phrase_end = (at + length) % (4 * beats) == 0
        if rng.random() > rest or phrase_end:
            i = int(np.clip(i + rng.integers(-leap, leap + 1), 2, len(PENTA) - 1))
            if phrase_end:
                i = min((5, 10, 0), key=lambda k: abs(k - i))
            out.append((at, PENTA[i], length))
        at += length
    return out


def vereda():
    """Vereda: water and palms. Slow, open, a viola picking through the
    chords and a thumb piano answering."""
    bpm, bars = 72, 16
    beat = 60 / bpm
    loop = Loop(bars * 4 * beat)
    rng = np.random.default_rng(11)
    progression = ["A", "F#m", "D", "E", "A", "F#m", "D", "Esus"]
    for i, name in enumerate(progression):
        at = i * 8 * beat
        for k, note in enumerate(CHORDS[name][1:]):
            loop.add(pad(hz(note), 8 * beat + 1.5), at, pan=(k - 1.5) * 0.3, gain=0.8)
        loop.add(bass(hz(CHORDS[name][0]), 6 * beat), at, gain=0.7)
        # The viola: a broken chord, up and back, leaving room.
        tones = CHORDS[name][1:]
        pattern = [0, 2, 3, 2, 1, 3, 2, None, 0, 2, 3, 1, 2, None, 3, None]
        for step, p in enumerate(pattern):
            if p is None or (i < 1 and step % 2):
                continue
            note = tones[p]
            loop.add(viola(hz(note) * 2, 2.6, rng, 0.45), at + step * beat / 2, pan=-0.3 + 0.15 * (p - 1.5), gain=0.5 + 0.15 * (step % 4 == 0))
    for at, note, length in melody(rng, bars - 4, 4, start=6, rest=0.4):
        loop.add(kalimba(hz(note) * 2, 2.5), (at + 16) * beat, pan=0.4, gain=0.55)
    loop.echo(beat * 0.75, 0.38, 0.32)
    loop.write("music_vereda")


def campo_sujo():
    """Campo sujo: webs in the dark. A low circling figure, wide silences,
    high notes like something glinting."""
    bpm, bars = 66, 16
    beat = 60 / bpm
    loop = Loop(bars * 4 * beat)
    rng = np.random.default_rng(22)
    progression = ["F#m", "D", "F#m", "E", "F#m", "D", "A", "Esus"]
    for i, name in enumerate(progression):
        at = i * 8 * beat
        for k, note in enumerate(CHORDS[name][:4]):
            loop.add(pad(hz(note), 8 * beat + 2, bright=600), at, pan=(k - 1.5) * 0.35, gain=0.9)
        # The circling figure: four notes, the last held.
        tones = CHORDS[name]
        for rep in range(2):
            for step, p in enumerate((1, 3, 2, 4)):
                if rep == 1 and i % 2 == 0 and step > 1:
                    continue
                loop.add(kalimba(hz(tones[p]), 2.2), at + (rep * 4 + step * 0.75) * beat, pan=-0.2 + step * 0.12, gain=0.6)
        if i % 2 == 1:
            loop.add(bass(hz(CHORDS[name][0]), 7 * beat), at, gain=0.6)
    # Glints: single high viola notes, far apart.
    for at, note, length in melody(rng, bars, 4, start=7, rest=0.72, leap=3):
        loop.add(viola(hz(note) * 2, 3.5, rng, 0.8), (at + 0.5) * beat, pan=float(rng.uniform(-0.7, 0.7)), gain=0.45)
    loop.echo(beat * 1.5, 0.45, 0.4, cutoff=1800)
    loop.write("music_campo_sujo")


def chapada():
    """Chapada: high and windy. Long chords, a flute that takes its time."""
    bpm, bars = 60, 16
    beat = 60 / bpm
    loop = Loop(bars * 4 * beat)
    rng = np.random.default_rng(33)
    progression = ["D", "A", "Bm", "E", "D", "A", "F#m", "Esus"]
    for i, name in enumerate(progression):
        at = i * 8 * beat
        for k, note in enumerate(CHORDS[name]):
            loop.add(pad(hz(note), 8 * beat + 2.5, bright=1300), at, pan=(k - 2) * 0.3, gain=0.75)
            loop.add(pad(hz(note) * 2, 8 * beat + 2.5, bright=2200), at, pan=-(k - 2) * 0.3, gain=0.18)
        # Two harmonics on the viola at the turn of each chord.
        loop.add(viola(hz(CHORDS[name][2]) * 4, 4, rng, 0.9), at, pan=-0.5, gain=0.35)
        loop.add(viola(hz(CHORDS[name][4]) * 2, 4, rng, 0.9), at + 3 * beat, pan=0.5, gain=0.3)
    for at, note, length in melody(rng, bars, 4, start=6, rest=0.3, leap=2):
        if length < 2:
            length = 2
        loop.add(flute(hz(note), length * beat * 1.1, rng), at * beat, pan=0.15, gain=0.6)
    loop.echo(beat, 0.42, 0.38, cutoff=2200)
    loop.write("music_chapada")


if __name__ == "__main__":
    vereda()
    campo_sujo()
    chapada()
