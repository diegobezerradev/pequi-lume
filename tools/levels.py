#!/usr/bin/env python3
"""Lays out Lume's 12 levels and writes them as a Zig table.

    python3 tools/levels.py            # writes src/level_table.zig
    python3 tools/levels.py --maps     # also draws art/maps/NN.png to look at

A level is a list of "bands" from the start (bottom) to the mound (top).
Each band holds one feature: a free group, a pond with its frog, a gate of
two ponds, webs, an owl's round. Positions inside a band come from the
level's seed, so the table is the same on every run.
"""
import math
import random
import sys

W = 1080
BAND = 330


class Level:
    def __init__(self, name, region, seed, bands, start_swarm=5, need=0.45,
                 wind=None, wolf=None):
        self.name, self.region, self.seed = name, region, seed
        self.bands, self.start_swarm, self.need_ratio = bands, start_swarm, need
        self.wind, self.wolf = wind, wolf
        self.lost, self.ponds, self.webs, self.owls = [], [], [], []
        self.height = 700 + BAND * len(bands)
        self.start = (540, self.height - 150)
        self.rng = random.Random(seed)
        for i, band in enumerate(bands):
            # The middle of the band; the first one is nearest the start.
            y = self.height - 430 - BAND * i - BAND / 2
            getattr(self, "band_" + band)(y)
        self.mound = (540 + self.rng.choice([-1, 1]) * self.rng.randint(0, 160), 210)
        total = start_swarm + sum(g[2] for g in self.lost)
        self.total = total
        n = round(total * need)
        self.need = n
        self.stars = (n, n + round((total - n) * 0.45), n + round((total - n) * 0.85))

    # Helpers
    def side(self):
        return self.rng.choice([-1, 1])

    def jitter(self, amount):
        return self.rng.uniform(-amount, amount)

    def group(self, x, y, count, spread=40):
        self.lost.append((round(x), round(y), count, spread))

    def pond(self, x, y, rx, ry, toward):
        """A pond whose frog sits on the edge facing the point `toward`."""
        angle = math.atan2((toward[1] - y) / ry, (toward[0] - x) / rx)
        self.ponds.append((round(x), round(y), rx, ry, round(angle, 2)))
        return (x + math.cos(angle) * rx, y + math.sin(angle) * ry)

    # Bands
    def band_free(self, y):
        self.group(540 + self.jitter(300), y + self.jitter(60), self.rng.randint(2, 3))

    def band_far(self, y):
        s = self.side()
        self.group(540 + s * (400 + self.jitter(40)), y + self.jitter(60), 3)
        self.group(540 - s * (250 + self.jitter(80)), y + self.jitter(80), 2)

    def band_pond(self, y):
        """One pond at a side; a prize right under the frog, a safe one across."""
        s = self.side()
        x = 540 + s * (250 + self.jitter(40))
        frog = self.pond(x, y, 170 + self.jitter(20), 115 + self.jitter(15), (540, y + self.jitter(80)))
        self.group(frog[0] + s * 80, frog[1] + self.jitter(30), 4, 45)
        self.group(540 - s * (330 + self.jitter(60)), y + self.jitter(90), 2)

    def band_gate(self, y):
        """Two frogs close the middle; the best prize is between them."""
        left = self.pond(300 + self.jitter(20), y + 40, 130, 95, (540, y))
        right = self.pond(800 + self.jitter(20), y - 30, 160, 120, (540, y))
        self.group((left[0] + right[0]) / 2, y + self.jitter(20), 5, 40)
        s = self.side()
        self.group(540 + s * 440, y + self.jitter(80), 2)

    def band_web(self, y):
        """A web on the way to a group, and one around another."""
        x = 540 + self.jitter(220)
        self.webs.append((round(x), round(y + 50), 72))
        self.group(x + self.jitter(20), y - 70, 3, 30)
        s = self.side()
        x2 = min(980, max(100, x + s * (330 + self.jitter(40))))
        self.webs.append((round(x2), round(y - 20), 64))
        self.group(x2, y - 20, 3, 22)

    def band_webgate(self, y):
        """Three webs in a row: the free ways are by the edges."""
        for x in (300, 540, 780):
            self.webs.append((round(x + self.jitter(30)), round(y + self.jitter(25)), 80))
        self.group(540 + self.jitter(60), y - 130, 4, 40)
        self.group(540 + self.side() * 450, y + self.jitter(40), 2)

    def band_webpond(self, y):
        """A frog on one side, webs on the other: the middle is the way."""
        s = self.side()
        x = 540 + s * 270
        frog = self.pond(x, y, 165, 110, (540, y))
        self.group(frog[0] + s * 70, frog[1] - 30, 4, 40)
        self.webs.append((round(540 - s * 300), round(y + 30), 78))
        self.webs.append((round(540 - s * 130), round(y - 90), 62))
        self.group(540 - s * 300, y + 30, 3, 24)

    def band_owl(self, y):
        """An owl's round over open ground, with groups under it."""
        self.owls.append((540 + round(self.jitter(60)), round(y), 300, 150, 22 + self.rng.randint(0, 6)))
        self.group(540 + self.jitter(280), y + self.jitter(70), 3)
        self.group(540 + self.jitter(280), y + self.jitter(70), 3)

    def band_owlpond(self, y):
        s = self.side()
        x = 540 + s * 260
        frog = self.pond(x, y, 160, 110, (540, y + self.jitter(60)))
        self.group(frog[0] + s * 75, frog[1], 4, 40)
        self.owls.append((round(540 - s * 180), round(y), 250, 140, 24))
        self.group(540 - s * 300, y + self.jitter(60), 3)


def wind(dx, dy, strength=650, period=11, gust=4):
    d = math.hypot(dx, dy)
    return (round(dx / d, 3), round(dy / d, 3), strength, period, gust)


def build():
    L = Level
    levels = [
        # Vereda: ponds and frogs.
        L("Primeira luz", "vereda", 11, ["free", "far", "free", "pond"], start_swarm=4, need=0.42),
        L("Brejo", "vereda", 12, ["free", "pond", "far", "pond", "free", "pond"], need=0.45),
        L("Vereda", "vereda", 13, ["free", "pond", "free", "gate", "far", "pond", "pond"], need=0.47),
        L("Buritizal", "vereda", 14, ["free", "gate", "pond", "far", "gate", "pond", "free", "gate"], need=0.5,
          wolf="auto"),
        # Campo Sujo: webs and spiders, with what came before.
        L("Fios", "campo_sujo", 21, ["free", "web", "free", "web", "pond", "web"], need=0.45),
        L("Campo sujo", "campo_sujo", 22, ["free", "web", "webgate", "pond", "web", "far", "webpond"], need=0.48,
          wolf="auto"),
        L("Teia", "campo_sujo", 23, ["web", "pond", "webgate", "free", "webpond", "web", "gate", "web"], need=0.5),
        L("Canela-de-ema", "campo_sujo", 24, ["free", "webpond", "webgate", "gate", "web", "webpond", "far", "webgate", "pond"],
          need=0.52, wolf="auto"),
        # Chapada: owls and wind, with everything else.
        L("Chapada", "chapada", 31, ["free", "owl", "far", "owlpond", "free", "owl"], need=0.45),
        L("Vento", "chapada", 32, ["free", "owl", "web", "far", "owlpond", "webgate", "owl"], need=0.48,
          wind=wind(1, 0.15)),
        L("Rajada", "chapada", 33, ["owl", "webpond", "far", "owlpond", "gate", "web", "owl", "webgate"], need=0.5,
          wind=wind(-1, 0.3, strength=720, period=10), wolf="auto"),
        L("Emas", "chapada", 34, ["free", "owlpond", "webgate", "gate", "owl", "webpond", "far", "owlpond", "web", "gate", "owl"],
          need=0.52, wind=wind(0.8, -0.6, strength=720, period=10), wolf="auto"),
    ]
    for lv in levels:
        if lv.wolf == "auto":
            # It crosses the level through the middle, side to side.
            y = lv.height * 0.5
            s = lv.rng.choice([-1, 1])
            lv.wolf = (540 - s * 600, round(y + 260), 540 + s * 600, round(y - 260), 18, 50)
    return levels


def zig(levels):
    out = ["//! Generated by tools/levels.py. Do not edit: change the script and run it.",
           "", 'const levels = @import("levels.zig");', "", "pub const all = [_]levels.Level{"]
    for lv in levels:
        out.append("    .{")
        out.append(f'        .name = "{lv.name}",')
        out.append(f"        .region = .{lv.region},")
        out.append(f"        .width = {W},")
        out.append(f"        .height = {lv.height},")
        out.append(f"        .start = .{{ {lv.start[0]}, {lv.start[1]} }},")
        out.append(f"        .start_swarm = {lv.start_swarm},")
        out.append(f"        .mound = .{{ {lv.mound[0]}, {lv.mound[1]} }},")
        out.append(f"        .need = {lv.need},")
        out.append(f"        .stars = .{{ {lv.stars[0]}, {lv.stars[1]}, {lv.stars[2]} }},")
        out.append(f"        .seed = 0x{(lv.seed * 2654435761) & 0xffffffff:08x},")
        out.append("        .lost = &.{")
        for g in lv.lost:
            out.append(f"            .{{ .x = {g[0]}, .y = {g[1]}, .count = {g[2]}, .spread = {g[3]} }},")
        out.append("        },")
        if lv.ponds:
            out.append("        .ponds = &.{")
            for p in lv.ponds:
                out.append(f"            .{{ .x = {p[0]}, .y = {p[1]}, .rx = {p[2]:.0f}, .ry = {p[3]:.0f}, .frog_angle = {p[4]} }},")
            out.append("        },")
        if lv.webs:
            out.append("        .webs = &.{")
            for w in lv.webs:
                out.append(f"            .{{ .x = {w[0]}, .y = {w[1]}, .r = {w[2]} }},")
            out.append("        },")
        if lv.owls:
            out.append("        .owls = &.{")
            for o in lv.owls:
                out.append(f"            .{{ .x = {o[0]}, .y = {o[1]}, .rx = {o[2]}, .ry = {o[3]}, .period = {o[4]} }},")
            out.append("        },")
        if lv.wind:
            w = lv.wind
            out.append(f"        .wind = .{{ .dx = {w[0]}, .dy = {w[1]}, .strength = {w[2]}, .period = {w[3]}, .gust = {w[4]} }},")
        if lv.wolf:
            w = lv.wolf
            out.append(f"        .wolf = .{{ .x0 = {w[0]}, .y0 = {w[1]}, .x1 = {w[2]}, .y1 = {w[3]}, .first = {w[4]}, .period = {w[5]} }},")
        out.append("    },")
    out.append("};")
    return "\n".join(out) + "\n"


def maps(levels):
    import os
    from PIL import Image, ImageDraw
    os.makedirs("art/maps", exist_ok=True)
    for i, lv in enumerate(levels):
        s = 0.25
        im = Image.new("RGB", (int(W * s), int(lv.height * s)), (10, 14, 28))
        d = ImageDraw.Draw(im)

        def ell(x, y, rx, ry, **kw):
            d.ellipse([(x - rx) * s, (y - ry) * s, (x + rx) * s, (y + ry) * s], **kw)
        for p in lv.ponds:
            ell(p[0], p[1], p[2], p[3], fill=(20, 60, 90))
            fx, fy = p[0] + math.cos(p[4]) * p[2], p[1] + math.sin(p[4]) * p[3]
            ell(fx, fy, 140, 140, outline=(120, 60, 40))
            ell(fx, fy, 14, 14, fill=(90, 200, 60))
        for w in lv.webs:
            ell(w[0], w[1], w[2], w[2], outline=(200, 200, 220))
        for o in lv.owls:
            ell(o[0], o[1], o[2], o[3], outline=(200, 120, 220))
        if lv.wolf:
            d.line([lv.wolf[0] * s, lv.wolf[1] * s, lv.wolf[2] * s, lv.wolf[3] * s], fill=(220, 120, 40))
        for g in lv.lost:
            ell(g[0], g[1], 8 + 3 * g[2], 8 + 3 * g[2], fill=(200, 240, 80))
        ell(lv.start[0], lv.start[1], 14, 14, fill=(255, 255, 255))
        ell(lv.mound[0], lv.mound[1], 30, 50, fill=(200, 140, 70))
        im.save(f"art/maps/{i + 1:02}.png")


if __name__ == "__main__":
    levels = build()
    with open("src/level_table.zig", "w") as f:
        f.write(zig(levels))
    for i, lv in enumerate(levels):
        print(f"{i + 1:2} {lv.name:14} h={lv.height:5} total={lv.total:3} need={lv.need:3} stars={lv.stars} "
              f"ponds={len(lv.ponds)} webs={len(lv.webs)} owls={len(lv.owls)}")
    if "--maps" in sys.argv:
        maps(levels)
