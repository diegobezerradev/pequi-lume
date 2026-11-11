#!/usr/bin/env python3
"""Draws Lume's illustrations as SVG and renders them to data/*.png.

    python3 tools/art.py              # every picture
    python3 tools/art.py pequi frog   # only these ("icon" for the app's icons)
    python3 tools/art.py --preview    # also art/preview.png, on a night background

Needs rsvg-convert and Pillow. Sizes are in pixels, three per world unit
(a tablet shows about that many).
"""
import math
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
from draw import Svg, blob, leaf, limb, rnd, smooth  # noqa: E402

ROOT = os.path.join(os.path.dirname(__file__), "..")

# The palette: what the fireflies' light finds in the night.
LEAF = ["#12301f", "#1d4a2a", "#2c6e37", "#4a9a45", "#86c957", "#c4ec7a"]
BARK = ["#1c1512", "#33261f", "#4f3a2c", "#75573f", "#a07a55"]
EARTH = ["#3a2418", "#5c3a25", "#8a5a36", "#b78049", "#deab6a", "#f3d18f"]
WATER = ["#082632", "#0e3d4d", "#18657a", "#2f93a3", "#7fd0d2"]
INK = "#0b1220"


def foliage(s, cx, cy, rx, ry, seed, tones=(1, 2, 3, 4), leaves=34, leaf_len=0.42, palette=LEAF):
    """A mass of leaves: a lumpy body with leaf tips breaking its edge,
    shadow below, light above, and loose leaves catching the light."""
    r = rnd(seed)
    dark, base, mid, light = (palette[t] for t in tones)
    # Leaf tips all around, so the outline reads as leaves, not as a cloud.
    for i in range(leaves):
        a = i / leaves * math.tau + r.uniform(-0.1, 0.1)
        k = r.uniform(0.72, 0.98)
        x, y = cx + math.cos(a) * rx * k, cy + math.sin(a) * ry * k
        ln = min(rx, ry) * leaf_len * r.uniform(0.7, 1.2)
        s.path(leaf(x, y, ln, ln * 0.42, a + r.uniform(-0.5, 0.5), r.uniform(-0.2, 0.2)), base if math.sin(a) < 0.3 else dark)
    body = blob(cx, cy, rx * 0.92, ry * 0.92, seed, n=12, wobble=0.13)
    s.path(body, base)
    s.clip(body)
    s.path(blob(cx + rx * 0.22, cy + ry * 0.42, rx * 0.95, ry * 0.75, seed + 1, wobble=0.15), dark)
    s.path(blob(cx - rx * 0.2, cy - ry * 0.3, rx * 0.7, ry * 0.55, seed + 2, wobble=0.18), mid)
    s.path(blob(cx - rx * 0.32, cy - ry * 0.45, rx * 0.36, ry * 0.3, seed + 3, wobble=0.2), light, 0.75)
    s.end()
    # Loose leaves: dark ones low, bright ones high.
    for i in range(int(leaves * 0.9)):
        a = r.uniform(0, math.tau)
        k = math.sqrt(r.uniform(0, 1)) * 0.85
        x, y = cx + math.cos(a) * rx * k, cy + math.sin(a) * ry * k
        ln = min(rx, ry) * leaf_len * r.uniform(0.45, 0.8)
        up = (y - cy) / ry
        tone = light if up < -0.15 and r.random() < 0.7 else (mid if up < 0.35 else dark)
        s.path(leaf(x, y, ln, ln * 0.45, r.uniform(0, math.tau), r.uniform(-0.25, 0.25)), tone, 0.9)


def bark(s, d, points, widths, seed, palette=BARK):
    """A trunk or branch: dark body, a lit flank, and plates of bark."""
    r = rnd(seed)
    s.path(d, palette[1])
    s.clip(d)
    # Light from the upper left: the left flank is lit.
    lit = [(x - w * 0.28, y) for (x, y), w in zip(points, widths)]
    s.line(smooth(lit, closed=False), palette[2], max(widths) * 0.34)
    lit2 = [(x - w * 0.36, y) for (x, y), w in zip(points, widths)]
    s.line(smooth(lit2, closed=False), palette[3], max(widths) * 0.12, 0.8)
    # Cracks between the plates.
    for i in range(len(points) - 1):
        (x0, y0), (x1, y1) = points[i], points[i + 1]
        steps = max(2, int(math.hypot(x1 - x0, y1 - y0) / 16))
        for k in range(steps):
            t = (k + r.uniform(0.1, 0.9)) / steps
            x, y = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
            w = widths[i] + (widths[i + 1] - widths[i]) * t
            ox = r.uniform(-0.35, 0.4) * w
            s.line(f"M{x + ox:.1f},{y:.1f} q{r.uniform(-3, 3):.1f},{r.uniform(4, 9):.1f} {r.uniform(-2, 2):.1f},{r.uniform(9, 16):.1f}",
                   palette[0], r.uniform(1.4, 2.6), 0.8)
    s.end()


def pequi():
    """Pequizeiro: a low, crooked trunk and a wide crown, with fruit."""
    s = Svg(660, 640)
    # Ground shadow.
    s.ellipse(330, 618, 150, 16, INK, 0.45)
    trunk = [(322, 622), (316, 560), (338, 500), (318, 440), (330, 392)]
    tw = [58, 44, 40, 36, 30]
    left = [(322, 440), (268, 398), (220, 380), (176, 330)]
    right = [(330, 400), (392, 372), (446, 336), (500, 318)]
    mid = [(326, 396), (322, 340), (346, 286), (336, 236)]
    # Back foliage first, behind the branches.
    foliage(s, 200, 250, 150, 110, 11, tones=(0, 1, 2, 3))
    foliage(s, 470, 240, 150, 105, 12, tones=(0, 1, 2, 3))
    foliage(s, 330, 150, 170, 110, 13, tones=(0, 1, 2, 3))
    for pts, w, seed in ((left, [30, 24, 18, 10], 3), (right, [30, 24, 18, 10], 4), (mid, [30, 24, 18, 12], 5)):
        bark(s, limb(pts, w), pts, w, seed)
    bark(s, limb(trunk, tw), trunk, tw, 2)
    # Roots flaring at the base.
    for dx, w in ((-34, 20), (30, 22)):
        pts = [(322 + dx * 0.3, 596), (322 + dx, 618), (322 + dx * 1.7, 626)]
        bark(s, limb(pts, [w, w * 0.7, 4]), pts, [w, w * 0.7, 4], 7 + dx)
    # Front foliage, over the branches.
    foliage(s, 150, 320, 120, 82, 21)
    foliage(s, 520, 310, 118, 84, 22)
    foliage(s, 262, 196, 128, 92, 23)
    foliage(s, 410, 190, 126, 90, 24)
    foliage(s, 336, 262, 104, 70, 25, tones=(1, 2, 3, 4))
    # Pequis: green-gold fruit in twos and threes, and pale flowers.
    r = rnd(40)
    for cx, cy in ((180, 372), (300, 300), (430, 268), (512, 372), (250, 120), (400, 110)):
        for k in range(r.choice([2, 3])):
            x, y = cx + k * 17 + r.uniform(-3, 3), cy + r.uniform(-6, 8)
            s.circle(x, y, 10.5, "#5d6b1f")
            s.circle(x - 1.5, y - 1.5, 8.6, "#9aa32c")
            s.circle(x - 3.5, y - 3.8, 4, "#d9d45a", 0.9)
    for cx, cy in ((120, 286), (350, 70), (560, 262), (470, 150), (215, 205)):
        for k in range(5):
            a = k / 5 * math.tau
            s.path(leaf(cx, cy, 13, 7, a), "#f4efc4")
        s.circle(cx, cy, 3.6, "#e8c23a")
    return s


def buriti():
    """Buriti palm: a tall ringed trunk, a round head of fan leaves, old
    fronds hanging and a bunch of scaly red-brown fruit."""
    s = Svg(560, 800)
    s.ellipse(280, 782, 90, 12, INK, 0.45)
    r = rnd(5)
    top = (286, 250)
    trunk = [(280, 786), (276, 640), (284, 500), (280, 380), top]
    tw = [40, 32, 30, 28, 30]
    d = limb(trunk, tw)

    def frond(angle, length, tones, droop=0.0):
        """One fan leaf: a stalk, then narrow blades spreading from its end."""
        sx, sy = top
        ex = sx + math.cos(angle) * length * 0.36
        ey = sy + math.sin(angle) * length * 0.36 + droop * 30
        s.line(f"M{sx:.1f},{sy:.1f} Q{(sx + ex) / 2:.1f},{(sy + ey) / 2 - 14:.1f} {ex:.1f},{ey:.1f}", LEAF[tones[0]], 7)
        blades = 15
        for i in range(blades):
            t = i / (blades - 1) - 0.5
            a = angle + t * 2.5 + droop * 0.5
            ln = length * 0.78 * (1 - 0.3 * abs(t) * 2) * r.uniform(0.9, 1.08)
            tone = tones[1] if t > 0.05 else tones[2]
            s.path(leaf(ex, ey, ln, ln * 0.11, a, 0.1 + droop * 0.25), LEAF[tone])
        # The midribs catch the light.
        for i in range(0, blades, 3):
            t = i / (blades - 1) - 0.5
            a = angle + t * 2.5 + droop * 0.5
            ln = length * 0.5 * (1 - 0.35 * abs(t) * 2)
            s.line(f"M{ex:.1f},{ey:.1f} l{math.cos(a) * ln:.1f},{math.sin(a) * ln + droop * 14:.1f}", LEAF[tones[3]], 1.6, 0.7)

    # Dead fronds hang against the trunk.
    for a, ln in ((1.25, 150), (1.9, 160), (1.6, 190)):
        ex, ey = top[0] + math.cos(a) * 40, top[1] + math.sin(a) * ln
        s.line(f"M{top[0]},{top[1]} Q{top[0] + math.cos(a) * 70:.1f},{top[1] + 30:.1f} {ex:.1f},{ey:.1f}", "#5a4a2a", 6)
        for i in range(9):
            s.path(leaf(ex, ey, 70, 9, 1.57 + (i - 4) * 0.13, 0.05), "#6f5c31" if i % 2 else "#4d3f24")
    # Back fronds, darker.
    for a in (-2.9, -2.2, -1.2, -0.3, 0.35, 2.8):
        frond(a, 240, (1, 1, 2, 3), droop=max(0, math.sin(a)) * 0.6 + 0.15)
    # Trunk, with the rings old leaves left.
    s.path(d, BARK[1])
    s.clip(d)
    s.line(smooth([(x - w * 0.24, y) for (x, y), w in zip(trunk, tw)], closed=False), BARK[2], 13)
    s.line(smooth([(x - w * 0.32, y) for (x, y), w in zip(trunk, tw)], closed=False), BARK[3], 4, 0.8)
    for y in range(280, 790, 22):
        s.line(f"M230,{y + r.uniform(-3, 3):.1f} q50,{r.uniform(5, 9):.1f} 100,0", BARK[0], 2.4, 0.75)
    s.end()
    # The fruit bunch: a hanging cluster of small scaly fruits.
    for i in range(34):
        t = i / 34
        x = top[0] + 34 + math.sin(i * 2.4) * (16 - t * 8)
        y = top[1] + 40 + t * 110
        s.circle(x, y, 7.5, "#5a2416")
        s.circle(x - 1.2, y - 1.2, 5.8, "#8f3b1e")
        s.circle(x - 2.6, y - 2.6, 2.4, "#c96a32", 0.9)
    s.line(f"M{top[0] + 8},{top[1] + 6} q30,8 28,40", "#4d3f24", 5)
    # Front fronds, lit.
    for a in (-2.55, -1.95, -1.2, -0.6, 0.05, 3.25, -1.57):
        frond(a, 250, (2, 2, 3, 4), droop=max(0, math.sin(a)) * 0.6 + 0.1)
    s.circle(top[0], top[1], 20, BARK[1])
    s.circle(top[0] - 4, top[1] - 5, 11, BARK[2])
    return s


def canela():
    """Canela-de-ema: thick fibrous stems that fork, a tuft of stiff
    leaves at each tip, violet flowers."""
    s = Svg(340, 330)
    s.ellipse(170, 316, 70, 9, INK, 0.45)
    r = rnd(8)
    stems = [
        ([(170, 318), (164, 250), (130, 196), (104, 150)], [30, 26, 22, 20]),
        ([(168, 262), (190, 200), (226, 158), (246, 118)], [24, 22, 20, 18]),
        ([(166, 250), (166, 190), (176, 130)], [20, 19, 17]),
    ]
    tips = []
    for pts, w in stems:
        d = limb(pts, w)
        s.path(d, "#2a2522")
        s.clip(d)
        s.line(smooth([(x - ww * 0.25, y) for (x, y), ww in zip(pts, w)], closed=False), "#4a4039", 9)
        # The stem is wrapped in old leaf bases: short scales all the way up.
        for i in range(len(pts) - 1):
            (x0, y0), (x1, y1) = pts[i], pts[i + 1]
            for k in range(7):
                t = k / 7
                x, y = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
                s.line(f"M{x - 14:.1f},{y - 3:.1f} q14,9 28,0", "#15110f", 2.2, 0.8)
        s.end()
        tips.append((pts[-1], math.atan2(pts[-1][1] - pts[-2][1], pts[-1][0] - pts[-2][0])))
    for (x, y), a in tips:
        for layer, (tone, ln) in enumerate(((1, 96), (2, 88), (3, 74))):
            n = 15 - layer * 3
            for i in range(n):
                t = i / (n - 1) - 0.5
                la = a + t * (3.0 - layer * 0.5) + r.uniform(-0.06, 0.06)
                s.path(leaf(x, y, ln * r.uniform(0.82, 1.05), 9 - layer, la, t * 0.25), ["#16382f", "#1f5646", "#3a8a68", "#8fd0a0"][tone])
        # A flower among the leaves.
        fx, fy = x + math.cos(a) * 30 + r.uniform(-12, 12), y + math.sin(a) * 30
        for i in range(6):
            s.path(leaf(fx, fy, 23, 12, i / 6 * math.tau + 0.3), "#7e52c8" if i % 2 else "#9a74e0")
        s.circle(fx, fy, 5, "#f0cf48")
    return s


def tree():
    """A small crooked cerrado tree: corky twisted branches, sparse leaves."""
    s = Svg(480, 520)
    s.ellipse(240, 504, 100, 12, INK, 0.45)
    trunk = [(236, 508), (244, 440), (214, 380), (232, 320), (220, 270)]
    tw = [44, 34, 30, 26, 20]
    branches = [
        ([(222, 372), (170, 340), (130, 290), (96, 270)], [22, 18, 13, 7]),
        ([(232, 322), (290, 290), (330, 230), (376, 206)], [22, 18, 13, 7]),
        ([(222, 272), (200, 220), (226, 170), (212, 120)], [20, 16, 12, 7]),
        ([(318, 250), (352, 280), (396, 284)], [12, 9, 5]),
        ([(140, 300), (120, 250), (132, 200)], [12, 9, 5]),
    ]
    foliage(s, 110, 220, 86, 60, 31, tones=(0, 1, 2, 3), leaves=26)
    foliage(s, 372, 180, 92, 62, 32, tones=(0, 1, 2, 3), leaves=26)
    for i, (pts, w) in enumerate(branches):
        bark(s, limb(pts, w), pts, w, 50 + i)
    bark(s, limb(trunk, tw), trunk, tw, 49)
    foliage(s, 214, 100, 100, 66, 33, leaves=28)
    foliage(s, 80, 262, 62, 44, 34, leaves=20)
    foliage(s, 400, 262, 60, 42, 35, leaves=20)
    foliage(s, 300, 170, 60, 42, 36, tones=(1, 2, 3, 4), leaves=20)
    return s


def bush():
    s = Svg(300, 220)
    s.ellipse(150, 206, 110, 10, INK, 0.45)
    foliage(s, 100, 130, 80, 62, 61, tones=(0, 1, 2, 3), leaves=26)
    foliage(s, 205, 120, 78, 66, 62, tones=(0, 1, 2, 3), leaves=26)
    foliage(s, 150, 150, 96, 52, 63, leaves=30)
    r = rnd(64)
    for i in range(7):
        x, y = r.uniform(60, 240), r.uniform(90, 170)
        s.circle(x, y, 5, "#a8281e")
        s.circle(x - 1.4, y - 1.4, 2.4, "#ee6a4a")
    return s


def tuft():
    """A clump of tall grass, some blades bent, a few gone to seed."""
    s = Svg(200, 190)
    r = rnd(70)
    for layer, tone in enumerate((1, 2, 3, 4)):
        n = 16 - layer * 3
        for i in range(n):
            t = i / (n - 1) - 0.5
            a = -math.pi / 2 + t * (2.0 - layer * 0.25) + r.uniform(-0.08, 0.08)
            ln = r.uniform(90, 160) * (1 - 0.3 * abs(t))
            s.path(leaf(100 + t * 40, 184, ln, 9 - layer, a, t * 0.5 + r.uniform(-0.1, 0.1)), LEAF[tone])
    for t in (-0.3, 0.12, 0.38):
        a = -math.pi / 2 + t
        x1, y1 = 100 + math.cos(a) * 150, 184 + math.sin(a) * 150
        s.line(f"M{100 + t * 30:.1f},184 Q{100 + t * 60:.1f},100 {x1:.1f},{y1:.1f}", "#b9a15a", 2.4)
        for k in range(6):
            s.path(leaf(x1 - math.cos(a) * k * 6, y1 - math.sin(a) * k * 6, 14, 5, a + (0.9 if k % 2 else -0.9)), "#e3cf86")
    return s


def reeds():
    """Cattails for the edge of a pond."""
    s = Svg(300, 300)
    r = rnd(75)
    for i in range(13):
        t = i / 12 - 0.5
        a = -math.pi / 2 + t * 0.9 + r.uniform(-0.06, 0.06)
        s.path(leaf(150 + t * 90, 296, r.uniform(170, 270), 11, a, t * 0.35), LEAF[1 + i % 3])
    for x, h in ((110, 240), (158, 280), (200, 220)):
        s.line(f"M{x},296 L{x + 4},{296 - h}", "#3a5a2a", 4)
        s.add(f'<rect x="{x - 4}" y="{296 - h + 18}" width="15" height="62" rx="7.5" fill="#3d2315"/>')
        s.add(f'<rect x="{x - 2}" y="{296 - h + 22}" width="5" height="52" rx="2.5" fill="#7a4a2a"/>')
    return s


def mound():
    """The termite mound: a tall tower of red earth, lumpy and pitted,
    built up in rounded lobes. The larvae's lights are drawn by the game."""
    s = Svg(420, 620)
    s.ellipse(210, 600, 170, 18, INK, 0.5)
    outline = [(60, 600), (78, 520), (64, 440), (104, 370), (96, 290), (136, 230), (140, 150), (176, 90), (206, 34),
               (238, 76), (270, 130), (286, 210), (322, 260), (318, 340), (356, 410), (346, 500), (372, 600)]
    d = smooth(outline, tension=0.55)
    s.path(d, EARTH[2])
    s.clip(d)
    # The right side falls into shadow; the left catches the light.
    s.path(smooth([(230, 0), (300, 150), (270, 300), (330, 430), (300, 620), (440, 620), (440, 0)]), EARTH[1])
    s.path(smooth([(300, 300), (350, 430), (330, 620), (440, 620), (440, 280)]), EARTH[0], 0.8)
    s.path(smooth([(120, 620), (96, 500), (130, 380), (120, 300), (160, 220), (168, 130), (204, 50), (214, 150),
                   (190, 260), (200, 380), (170, 480), (190, 620)]), EARTH[3])
    s.path(smooth([(130, 560), (118, 470), (146, 390), (138, 310), (172, 240), (180, 150), (190, 250),
                   (170, 340), (176, 430), (150, 520)]), EARTH[4], 0.85)
    r = rnd(90)
    # Lobes: each built-up bulge has its own shadow under it.
    for cx, cy, rx, ry in ((150, 470, 70, 44), (270, 420, 60, 40), (196, 330, 62, 40), (252, 252, 44, 30),
                           (188, 190, 40, 28), (226, 122, 30, 22), (112, 556, 44, 30), (300, 546, 56, 34)):
        s.path(blob(cx + 6, cy + 16, rx, ry * 0.75, r.randint(0, 999), wobble=0.12), EARTH[0], 0.5)
        s.path(blob(cx, cy, rx, ry, r.randint(0, 999), wobble=0.12), EARTH[3] if cx < 230 else EARTH[2])
        s.path(blob(cx - rx * 0.25, cy - ry * 0.3, rx * 0.55, ry * 0.45, r.randint(0, 999), wobble=0.16),
               EARTH[4] if cx < 230 else EARTH[3], 0.9)
    # Holes where the termites come and go, and grains of earth.
    for i in range(46):
        x, y = r.uniform(70, 360), r.uniform(70, 590)
        rr = r.uniform(3, 8)
        s.ellipse(x, y, rr, rr * 0.8, EARTH[0], 0.85)
        s.ellipse(x - rr * 0.25, y + rr * 0.55, rr * 0.9, rr * 0.35, EARTH[5], 0.35)
    for i in range(90):
        x, y = r.uniform(60, 370), r.uniform(50, 600)
        s.circle(x, y, r.uniform(1, 2.4), EARTH[5] if x < 200 else EARTH[0], 0.5)
    s.end()
    # Grass at its foot.
    for i in range(22):
        x = r.uniform(40, 390)
        s.path(leaf(x, 606, r.uniform(26, 60), 7, -math.pi / 2 + r.uniform(-0.5, 0.5), r.uniform(-0.3, 0.3)), LEAF[r.choice([1, 2, 3])])
    return s


def frog():
    """A tree frog seen from above and behind, sitting: folded legs, a
    wide head, big eyes that the game lights."""
    s = Svg(240, 220)
    s.ellipse(120, 196, 86, 14, INK, 0.5)
    g = ["#1f4d24", "#2f7a2e", "#55a83a", "#9ad24e", "#d9ec8a"]
    # Hind legs, folded.
    for sx in (-1, 1):
        thigh = [(120 + sx * 28, 150), (120 + sx * 78, 128), (120 + sx * 96, 168), (120 + sx * 52, 186)]
        s.path(smooth(thigh, tension=0.7), g[1])
        s.path(blob(120 + sx * 66, 150, 22, 14, 3, wobble=0.1), g[2], 0.9)
        foot = [(120 + sx * 60, 180), (120 + sx * 100, 184), (120 + sx * 112, 200), (120 + sx * 70, 198)]
        s.path(smooth(foot, tension=0.7), g[1])
        for k in range(3):
            s.circle(120 + sx * (104 + k * 5), 196 + (k - 1) * 5, 5.5, g[2])
        # Front legs.
        arm = [(120 + sx * 44, 108), (120 + sx * 76, 96), (120 + sx * 84, 122), (120 + sx * 56, 130)]
        s.path(smooth(arm, tension=0.7), g[1])
        for k in range(3):
            s.circle(120 + sx * (84 + k * 5), 116 + (k - 1) * 6, 5, g[2])
    body = blob(120, 132, 62, 54, 4, n=10, wobble=0.05)
    s.path(body, g[1])
    s.clip(body)
    s.path(blob(134, 156, 60, 40, 5, wobble=0.1), g[0], 0.8)
    s.path(blob(104, 112, 44, 34, 6, wobble=0.12), g[2])
    s.path(blob(96, 100, 22, 15, 7, wobble=0.15), g[3], 0.85)
    r = rnd(8)
    for i in range(12):
        s.ellipse(r.uniform(74, 168), r.uniform(100, 172), r.uniform(3, 7), r.uniform(2.5, 5), g[0], 0.55)
    s.end()
    head = smooth([(60, 86), (76, 52), (120, 40), (164, 52), (180, 86), (160, 108), (120, 114), (80, 108)], tension=0.6)
    s.path(head, g[2])
    s.clip(head)
    s.path(blob(140, 100, 60, 26, 9, wobble=0.1), g[1], 0.9)
    s.path(blob(108, 62, 36, 14, 10, wobble=0.15), g[3], 0.85)
    s.end()
    s.line("M74,92 Q120,108 166,92", g[0], 2.6, 0.9)
    for sx in (-1, 1):
        ex = 120 + sx * 38
        s.circle(ex, 56, 21, g[1])
        s.circle(ex, 54, 17, "#e8b830")
        s.circle(ex - 2, 52, 16, "#f6d655", 0.9)
        s.ellipse(ex, 55, 10, 5.2, "#120c08")
        s.circle(ex - 6, 47, 4, "#ffffff", 0.9)
    return s


def spider():
    s = Svg(120, 120)
    c = (60, 60)
    for i in range(8):
        side = -1 if i < 4 else 1
        k = i % 4
        a = (-0.95 + k * 0.62) * 1.0
        kx, ky = c[0] + side * math.cos(a) * 30, c[1] + math.sin(a) * 30 - 8
        fx, fy = c[0] + side * math.cos(a) * 54, c[1] + math.sin(a) * 52 + 6
        s.line(f"M{c[0] + side * 8},{c[1]} L{kx:.1f},{ky:.1f} L{fx:.1f},{fy:.1f}", "#15100e", 5)
        s.line(f"M{c[0] + side * 8},{c[1]} L{kx:.1f},{ky:.1f} L{fx:.1f},{fy:.1f}", "#5a3a2a", 1.6, 0.8)
    s.ellipse(60, 72, 19, 23, "#1f1512")
    s.ellipse(56, 66, 10, 12, "#5c3524")
    s.path(leaf(60, 58, 28, 12, math.pi / 2), "#c9a24a", 0.9)
    s.ellipse(60, 46, 13, 12, "#2a1c17")
    s.ellipse(57, 43, 6, 5, "#6a4230")
    return s


def owl_body():
    """A barn owl from above: the heart-shaped pale face, the back and the
    fanned tail. The wings are separate, so they can beat."""
    s = Svg(200, 320)
    o = ["#3d2c1c", "#6b4d2c", "#9a7440", "#c9a564", "#ead9b0", "#fbf3dc"]
    tail = smooth([(72, 210), (60, 300), (100, 316), (140, 300), (128, 210)], tension=0.5)
    s.path(tail, o[2])
    s.clip(tail)
    for x in (72, 86, 100, 114, 128):
        s.line(f"M100,200 L{x},316", o[0], 2.2, 0.7)
    for y in (250, 276, 300):
        s.line(f"M50,{y} q50,14 100,0", o[1], 6, 0.8)
    s.end()
    body = blob(100, 170, 56, 82, 3, n=10, wobble=0.04)
    s.path(body, o[2])
    s.clip(body)
    s.path(blob(124, 196, 50, 70, 4, wobble=0.1), o[1], 0.9)
    s.path(blob(82, 140, 34, 50, 5, wobble=0.12), o[3])
    r = rnd(6)
    for i in range(46):
        x, y = r.uniform(52, 150), r.uniform(100, 250)
        s.path(leaf(x, y, 12, 8, math.pi / 2), o[0], 0.5)
        s.circle(x, y + 9, 1.6, o[5], 0.9)
    s.end()
    head = blob(100, 70, 54, 50, 7, n=10, wobble=0.03)
    s.path(head, o[3])
    face = "M100,112 C56,104 52,56 76,38 C90,28 100,38 100,50 C100,38 110,28 124,38 C148,56 144,104 100,112 Z"
    s.path(face, o[5])
    s.path(face, "none", stroke=o[2], width=3)
    s.clip(face)
    s.path(blob(120, 90, 30, 30, 8), o[4], 0.8)
    s.end()
    for ex in (82, 118):
        s.circle(ex, 66, 9.5, "#120c08")
        s.circle(ex - 3, 63, 2.6, "#ffffff", 0.9)
    s.path("M100,74 L94,90 L100,98 L106,90 Z", o[2])
    return s


def owl_wing():
    """The left wing, spread, seen from above: the shoulder at the right
    edge, the long flight feathers fanning back and out to the tip.
    Mirrored for the right wing."""
    s = Svg(440, 300)
    s.group('transform="translate(60,0)"')
    o = ["#3d2c1c", "#6b4d2c", "#9a7440", "#c9a564", "#ead9b0", "#fbf3dc"]
    sx, sy = 364, 70
    wrist = (150, 44)

    def root(t):
        """Along the arm: 0 at the tip end, 1 at the shoulder."""
        return (wrist[0] - 60 + (sx - wrist[0] + 60) * t, wrist[1] + 8 + (sy - wrist[1]) * t)

    def feathers(n, length, width, tones, spread_from, bars):
        for i in range(n):
            t = i / (n - 1)
            # At the tip they point out along the wing; at the body, straight back.
            a = spread_from - t * (spread_from - math.pi / 2 - 0.1)
            ln = length[0] + (length[1] - length[0]) * t
            x0, y0 = root(t)
            s.path(leaf(x0, y0, ln, width, a, 0.06), o[tones[i % 2]])
            s.line(f"M{x0:.1f},{y0:.1f} l{math.cos(a) * ln * 0.9:.1f},{math.sin(a) * ln * 0.9:.1f}", o[0], 1.5, 0.5)
            for k in bars:
                bx, by = x0 + math.cos(a) * ln * k, y0 + math.sin(a) * ln * k
                hw = width * 0.3 * math.sin(math.pi * k)
                s.line(f"M{bx - math.sin(a) * hw:.1f},{by + math.cos(a) * hw:.1f} L{bx + math.sin(a) * hw:.1f},{by - math.cos(a) * hw:.1f}", o[0], 5, 0.4)

    feathers(15, (150, 190), 44, (1, 2), math.pi - 0.12, (0.45, 0.63, 0.8))
    feathers(12, (84, 110), 40, (2, 3), math.pi - 0.3, (0.6,))
    feathers(10, (46, 62), 34, (3, 4), math.pi - 0.45, ())
    # The arm itself, pale, along the leading edge.
    arm = [(sx, sy), (270, 48), wrist, (86, 54)]
    s.path(limb(arm, [56, 46, 34, 14]), o[3])
    s.path(limb([(x - 2, y - 8) for x, y in arm], [24, 20, 14, 5]), o[4], 0.9)
    r = rnd(12)
    for i in range(30):
        t = r.uniform(0.05, 1)
        x, y = root(t)
        s.circle(x + r.uniform(-8, 8), y + r.uniform(-22, 10), 1.9, o[0], 0.55)
    s.end()
    return s


def wolf_body():
    """The maned wolf, seen from the side, head to the right: a short deep
    body on stilts, red-gold coat, black mane, long dark muzzle, very tall
    ears, white throat and tail tip. The legs are separate, so they walk."""
    s = Svg(520, 380)
    s.group('transform="translate(0,50)"')
    w = ["#4a1a0c", "#93381a", "#cf5f22", "#ee9440", "#f9c880"]
    cream = "#f6ecd8"
    black = "#1a1210"
    # Tail: bushy, hanging, the lower half white.
    tail = [(104, 158), (70, 190), (58, 240), (70, 286)]
    s.path(limb(tail, [24, 40, 40, 14]), w[2])
    s.clip(limb(tail, [24, 40, 40, 14]))
    s.path("M0,236 Q70,222 140,240 L140,330 L0,330 Z", cream)
    s.path(blob(84, 210, 16, 30, 2), w[1], 0.8)
    s.end()
    # Body: high at the shoulder, sloping to the rump.
    body = smooth([(96, 150), (120, 122), (190, 112), (262, 104), (318, 100), (350, 130), (342, 190), (300, 214),
                   (220, 214), (150, 206), (106, 192)], tension=0.6)
    s.path(body, w[2])
    s.clip(body)
    s.path(blob(220, 214, 150, 36, 3, wobble=0.1), w[1], 0.95)
    s.path(blob(150, 196, 50, 26, 13, wobble=0.1), w[0], 0.5)
    s.path(blob(210, 124, 120, 20, 4, wobble=0.12), w[3], 0.95)
    s.path(blob(190, 116, 70, 8, 5, wobble=0.15), w[4], 0.7)
    s.end()
    # Neck, rising; the throat is white.
    neck = smooth([(292, 104), (330, 74), (362, 50), (404, 60), (398, 110), (372, 168), (330, 196)], tension=0.6)
    s.path(neck, w[2])
    s.clip(neck)
    s.path(blob(360, 170, 46, 40, 6), w[1], 0.9)
    s.path(smooth([(392, 84), (402, 110), (384, 150), (366, 150), (376, 110)]), cream)
    s.path(blob(340, 76, 26, 16, 16), w[3], 0.8)
    s.end()
    # The mane: black, standing along the neck and over the shoulders.
    r = rnd(9)
    for i in range(22):
        t = i / 21
        x, y = 250 + t * 112, 106 - t * 56 + 8 * math.sin(t * 3)
        s.path(leaf(x + 8, y + 12, r.uniform(34, 46), 13, -2.15 + r.uniform(-0.25, 0.25)), black)
    s.path(smooth([(246, 108), (300, 92), (350, 60), (366, 52), (360, 76), (326, 108), (282, 122)], tension=0.5), black)
    # Head.
    skull = smooth([(356, 56), (372, 30), (404, 22), (432, 34), (440, 58), (424, 80), (392, 86), (366, 78)], tension=0.6)
    muzzle = smooth([(420, 42), (462, 56), (492, 68), (496, 80), (480, 90), (440, 88), (414, 80)], tension=0.55)
    s.path(muzzle, w[2])
    s.clip(muzzle)
    s.path("M448,40 L510,60 L510,100 L452,96 Q442,70 448,40 Z", black)
    s.path(smooth([(418, 80), (450, 84), (470, 92), (430, 94)]), cream)
    s.end()
    s.path(skull, w[2])
    s.clip(skull)
    s.path(blob(404, 30, 34, 12, 10), w[3], 0.95)
    s.path(blob(396, 82, 36, 12, 11), cream, 0.95)
    s.end()
    s.ellipse(494, 76, 6.5, 6, "#0a0605")
    # The eye: amber, the game lights it.
    s.ellipse(426, 52, 8, 6.5, black)
    s.circle(426, 52, 4.2, "#e8a020")
    s.circle(424.6, 50.6, 1.5, "#fff3c8")
    # Ears: very tall, the far one darker, pale inside.
    far = leaf(372, 36, 78, 34, -1.86)
    near = leaf(398, 30, 84, 38, -1.5)
    s.path(far, w[1])
    s.path(leaf(374, 30, 56, 16, -1.86), w[0])
    s.path(near, w[2])
    s.path(leaf(400, 22, 62, 22, -1.5), "#f4d9b4")
    s.path(leaf(403, 16, 40, 10, -1.5), "#e8b88c", 0.8)
    s.end()
    return s


def wolf_leg():
    """One long leg, hanging from its hip at the top: red thigh, black
    stocking."""
    s = Svg(70, 240)
    pts = [(35, 8), (30, 80), (40, 150), (34, 222)]
    s.path(limb(pts, [44, 26, 17, 13]), "#c95a1e")
    s.clip(limb(pts, [44, 26, 17, 13]))
    s.path("M0,96 Q35,80 70,100 L70,240 L0,240 Z", "#17100e")
    s.path("M0,0 L26,0 Q22,60 26,100 L0,100 Z", "#e88a36", 0.8)
    s.end()
    s.path(smooth([(24, 218), (30, 236), (56, 236), (48, 218)]), "#17100e")
    return s


def pond():
    """Still water in the night: deep in the middle, a rim of wet earth,
    lily pads, a few reflected stars and slow rings."""
    s = Svg(900, 620)
    cx, cy = 450, 310
    shore = blob(cx, cy, 430, 290, 3, n=16, wobble=0.045)
    s.path(shore, "#2b2018")
    s.path(blob(cx, cy, 418, 280, 3, n=16, wobble=0.045), "#4a3524")
    water = blob(cx, cy, 398, 262, 4, n=16, wobble=0.05)
    s.path(water, s.radial([(0, WATER[0], 1), (0.55, WATER[1], 1), (0.85, WATER[2], 1), (1, WATER[3], 1)]))
    s.clip(water)
    s.path(blob(cx - 120, cy - 90, 250, 110, 5, wobble=0.2), WATER[2], 0.35)
    s.path(blob(cx + 150, cy + 110, 220, 80, 6, wobble=0.2), WATER[0], 0.5)
    r = rnd(7)
    for i in range(9):
        x, y = r.uniform(120, 780), r.uniform(120, 500)
        rr = r.uniform(24, 60)
        for k in (1, 0.62):
            s.add(f'<ellipse cx="{x:.1f}" cy="{y:.1f}" rx="{rr * k:.1f}" ry="{rr * k * 0.45:.1f}" fill="none" stroke="{WATER[4]}" stroke-width="2" opacity="0.28"/>')
    for i in range(26):
        x, y = r.uniform(110, 790), r.uniform(100, 520)
        s.circle(x, y, r.uniform(1.4, 3), "#dff6ff", r.uniform(0.3, 0.8))
    # Light along the near edge of the water.
    s.add(f'<path d="{blob(cx, cy, 388, 252, 4, n=16, wobble=0.05)}" fill="none" stroke="{WATER[4]}" stroke-width="5" opacity="0.3"/>')
    s.end()
    # Lily pads, each with its notch, some with a flower.
    for i in range(15):
        a = r.uniform(0, math.tau)
        k = r.uniform(0.45, 0.9)
        x, y = cx + math.cos(a) * 390 * k, cy + math.sin(a) * 250 * k
        rr = r.uniform(20, 36)
        rot = r.uniform(0, 360)
        s.add(f'<g transform="translate({x:.1f},{y:.1f}) rotate({rot:.0f}) scale(1,0.62)">'
              f'<path d="M0,0 L{rr},{-rr * 0.22} A{rr},{rr} 0 1 0 {rr},{rr * 0.22} Z" fill="{LEAF[1]}"/>'
              f'<path d="M0,0 L{rr * 0.86},{-rr * 0.2} A{rr * 0.88},{rr * 0.88} 0 0 0 {-rr * 0.86},{-rr * 0.1} Z" fill="{LEAF[3]}" opacity="0.9"/>'
              f'<path d="M0,0 L{-rr * 0.8},0 M0,0 L0,{rr * 0.8} M0,0 L0,{-rr * 0.8}" stroke="{LEAF[0]}" stroke-width="1.6" opacity="0.6"/></g>')
        if i % 4 == 0:
            for p in range(7):
                s.path(leaf(x, y - 4, 17, 8, p / 7 * math.tau), "#f6e9f4" if p % 2 else "#e6b8dc")
            s.circle(x, y - 4, 4, "#f0cf48")
    return s


def ground():
    """A tile of meadow, seen when lit: mottled greens, blades, bare earth
    and tiny flowers. It repeats without a seam."""
    n = 512
    s = Svg(n, n)
    s.add(f'<rect width="{n}" height="{n}" fill="#1e3f24"/>')
    r = rnd(101)

    def wrapped(draw, x, y, reach):
        """Draws at (x, y) and at its copies across the tile's edges."""
        for ox in (-n, 0, n):
            for oy in (-n, 0, n):
                if -reach < x + ox < n + reach and -reach < y + oy < n + reach:
                    draw(x + ox, y + oy)
    for i in range(46):
        x, y, rx, ry, seed = r.uniform(0, n), r.uniform(0, n), r.uniform(40, 110), r.uniform(26, 70), r.randint(0, 9999)
        tone = r.choice(["#183420", "#255029", "#2c5f2c", "#1a3a22", "#33402a"])
        wrapped(lambda a, b: s.path(blob(a, b, rx, ry, seed, wobble=0.25), tone, 0.75), x, y, 130)
    for i in range(520):
        x, y = r.uniform(0, n), r.uniform(0, n)
        ln, a, bend = r.uniform(10, 26), -math.pi / 2 + r.uniform(-0.7, 0.7), r.uniform(-0.4, 0.4)
        tone = r.choice([LEAF[1], LEAF[2], LEAF[2], LEAF[3], "#6f8a3a"])
        wrapped(lambda p, q: s.path(leaf(p, q, ln, 3.4, a, bend), tone, 0.9), x, y, 30)
    for i in range(40):
        x, y, c = r.uniform(0, n), r.uniform(0, n), r.choice(["#f2e9a0", "#e6d8f4", "#f4c9a0"])
        wrapped(lambda p, q: s.circle(p, q, 2.4, c, 0.9), x, y, 6)
    return s


def sky():
    """The night sky: deep blue falling to a paler horizon, the band of
    the Milky Way, and stars of three sizes."""
    w, h = 1080, 2400
    s = Svg(w, h)
    s.add(f'<rect width="{w}" height="{h}" fill="{s.linear([(0, "#02040b", 1), (0.45, "#06112a", 1), (0.8, "#0c2244", 1), (1, "#143258", 1)])}"/>')
    r = rnd(123)
    # The Milky Way: a soft diagonal band of haze.
    blur = s.uid("f")
    s.defs.append(f'<filter id="{blur}" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="70"/></filter>')
    s.group(f'filter="url(#{blur})"')
    for i in range(16):
        t = i / 15
        s.ellipse(120 + t * 900 + r.uniform(-60, 60), 300 + t * 1300 + r.uniform(-80, 80), r.uniform(120, 220), r.uniform(90, 180), "#5a78c8", 0.11)
    for i in range(8):
        t = i / 7
        s.ellipse(160 + t * 820, 380 + t * 1200, 90, 80, "#c8b8e8", 0.07)
    s.end()
    for i in range(900):
        x, y = r.uniform(0, w), r.uniform(0, h * 0.92)
        # More of them along the band.
        band = abs((y - 300) - (x - 120) * 1.45) < 260
        if not band and r.random() < 0.45:
            continue
        size = r.choice([0.9, 0.9, 1.3, 1.3, 1.9, 2.8])
        s.circle(x, y, size, r.choice(["#ffffff", "#dfe8ff", "#fff2d8", "#cfe0ff"]), r.uniform(0.35, 0.95) * (1 - y / h * 0.5))
    for i in range(14):
        x, y = r.uniform(40, w - 40), r.uniform(40, h * 0.7)
        s.circle(x, y, 9, "#bcd0ff", 0.12)
        s.circle(x, y, 3.2, "#ffffff", 0.95)
        s.line(f"M{x - 12},{y} L{x + 12},{y} M{x},{y - 12} L{x},{y + 12}", "#ffffff", 1, 0.5)
    return s


def hills():
    """A far line of hills and treetops, to repeat side by side."""
    w, h = 1024, 300
    s = Svg(w, h)
    r = rnd(140)
    pts = [(0, 190)]
    for i in range(1, 16):
        pts.append((i * w / 16, 150 + math.sin(i * 0.8) * 34 + r.uniform(-16, 16)))
    pts.append((w, 190))
    d = smooth(pts, closed=False) + f" L{w},{h} L0,{h} Z"
    s.path(d, "#ffffff")
    # Trees along the ridge: palms and round crowns.
    for i in range(22):
        x = (i + 0.5) / 22 * w + r.uniform(-14, 14)
        y = 172 + math.sin(x / w * 16 * 0.8) * 30
        if i % 3 == 0:
            s.line(f"M{x},{y + 20} L{x + 3},{y - 70}", "#ffffff", 4)
            for k in range(9):
                s.path(leaf(x + 3, y - 70, 40, 7, -math.pi / 2 + (k - 4) * 0.55, 0.3), "#ffffff")
        else:
            s.line(f"M{x},{y + 20} L{x},{y - 20}", "#ffffff", 5)
            s.path(blob(x, y - 36, r.uniform(22, 38), r.uniform(16, 26), i, wobble=0.2), "#ffffff")
    return s


def branch():
    """A leafy branch close to the eye, for the dark foreground."""
    s = Svg(560, 420)
    s.group('transform="translate(20,60)"')
    stem = [(10, 150), (140, 138), (300, 160), (500, 120)]
    s.path(limb(stem, [20, 15, 10, 3]), "#ffffff")
    r = rnd(150)
    for i in range(26):
        t = i / 25
        x = 30 + t * 460
        y = 150 - 12 * math.sin(t * 3.2) + (10 if t > 0.5 else 0) - t * 20
        side = 1 if i % 2 else -1
        s.path(leaf(x, y, r.uniform(90, 150), r.uniform(26, 40), side * r.uniform(0.6, 1.3) + 0.1, side * 0.15), "#ffffff")
    s.end()
    return s


def icon_layers():
    """The app's icon in two layers, as Android's adaptive icons want: a
    background that fills the square, and a foreground (the lit mound and
    its fireflies) kept inside the middle, which is all a round or squircle
    mask is sure to show."""
    n = 432
    bg = Svg(n, n)
    bg.add(f'<rect width="{n}" height="{n}" fill="{bg.linear([(0, "#030816", 1), (1, "#12305a", 1)])}"/>')
    r = rnd(161)
    for i in range(70):
        bg.circle(r.uniform(0, n), r.uniform(0, n * 0.8), r.choice([0.9, 1.2, 1.8]), "#e8f0ff", r.uniform(0.3, 0.8))
    bg.circle(216, 236, 200, bg.radial([(0, "#c8f070", 0.55), (0.5, "#6fb84a", 0.2), (1, "#6fb84a", 0)]))
    bg.path(f"M0,340 Q216,318 {n},340 L{n},{n} L0,{n} Z", "#050b18")

    fg = Svg(n, n)
    # Everything a little smaller, around the middle: inside the safe zone.
    fg.group('transform="translate(216,222) scale(0.74) translate(-216,-240)"')
    d = smooth([(130, 372), (140, 300), (156, 236), (176, 172), (216, 110), (252, 170), (270, 236), (292, 300), (302, 372)], tension=0.55)
    fg.path(d, "#7a4c2a")
    fg.clip(d)
    fg.path(smooth([(216, 100), (250, 200), (240, 300), (270, 372), (320, 372), (320, 100)]), "#4a2c1b")
    fg.path(smooth([(150, 372), (160, 290), (180, 200), (212, 124), (204, 220), (190, 300), (186, 372)]), "#a8703e", 0.9)
    fg.end()
    r = rnd(160)
    for i in range(26):
        t = r.uniform(0, 1)
        x, y = 216 + r.uniform(-1, 1) * (78 - t * 54), 360 - t * 220
        fg.circle(x, y, 13, "#d8ff7a", 0.28)
        fg.circle(x, y, 4.2, "#f4ffc0")
    for x, y, rr in ((96, 170, 15), (330, 140, 12), (346, 262, 10), (86, 290, 9), (250, 74, 9)):
        fg.circle(x, y, rr * 2.6, "#d8ff7a", 0.22)
        fg.circle(x, y, rr * 1.3, "#d8ff7a", 0.4)
        fg.circle(x, y, rr * 0.55, "#fbffd8")
    fg.end()
    return bg, fg


def write_icons():
    """art/icon.png (both layers together), the launcher icons for old
    Android in every density, and the two layers for adaptive icons."""
    from PIL import Image
    bg, fg = icon_layers()
    layers = []
    for name, svg in (("icon_background", bg), ("icon_foreground", fg)):
        path = os.path.join(ROOT, "art", "svg", name + ".svg")
        with open(path, "w") as f:
            f.write(svg.text())
        out = os.path.join(ROOT, "art", name + ".png")
        subprocess.run(["rsvg-convert", path, "-o", out], check=True)
        layers.append(Image.open(out).convert("RGBA"))
        os.remove(out)
    res = os.path.join(ROOT, "android", "app", "src", "main", "res")
    # Old launchers show the middle two thirds of the layers, as a square.
    whole = Image.alpha_composite(layers[0], layers[1])
    legacy = whole.crop((54, 54, 378, 378))
    legacy.resize((512, 512), Image.LANCZOS).save(os.path.join(ROOT, "art", "icon.png"))
    for density, size in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
        folder = os.path.join(res, "mipmap-" + density)
        os.makedirs(folder, exist_ok=True)
        legacy.resize((size, size), Image.LANCZOS).save(os.path.join(folder, "ic_launcher.png"))
    # The layers are 108dp: 432 pixels at the highest density.
    folder = os.path.join(res, "mipmap-xxxhdpi")
    layers[0].convert("RGB").save(os.path.join(folder, "ic_launcher_background.png"))
    layers[1].save(os.path.join(folder, "ic_launcher_foreground.png"))
    folder = os.path.join(res, "mipmap-anydpi-v26")
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, "ic_launcher.xml"), "w") as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<!-- Android 8 and later: the launcher cuts its own shape out of these two layers. -->\n'
                '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                '    <background android:drawable="@mipmap/ic_launcher_background" />\n'
                '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
                '</adaptive-icon>\n')


def render(name, svg, width=None):
    os.makedirs(os.path.join(ROOT, "art", "svg"), exist_ok=True)
    path = os.path.join(ROOT, "art", "svg", name + ".svg")
    with open(path, "w") as f:
        f.write(svg.text())
    out = os.path.join(ROOT, "data", name + ".png")
    cmd = ["rsvg-convert", path, "-o", out]
    if width:
        cmd += ["-w", str(width)]
    subprocess.run(cmd, check=True)
    bleed(out)
    return out


def bleed(path, rounds=24):
    """Spreads each shape's edge colors into the transparent pixels around
    it (leaving them transparent). Without this, a texture drawn smaller or
    larger than it is picks up black from outside the shape and shows a
    dark fringe."""
    import numpy as np
    from PIL import Image
    im = np.asarray(Image.open(path).convert("RGBA")).astype(np.float32)
    alpha = im[..., 3]
    if alpha.min() >= 255:
        return
    rgb = im[..., :3].copy()
    known = alpha > 0
    for _ in range(rounds):
        if known.all():
            break
        total = np.zeros_like(rgb)
        count = np.zeros(alpha.shape, np.float32)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0), (1, 1), (1, -1), (-1, 1), (-1, -1)):
            shifted = np.roll(np.roll(known, dy, 0), dx, 1)
            total += np.roll(np.roll(rgb, dy, 0), dx, 1) * shifted[..., None]
            count += shifted
        grow = (~known) & (count > 0)
        rgb[grow] = total[grow] / count[grow][..., None]
        known = known | grow
    out = np.dstack([rgb, alpha]).clip(0, 255).astype(np.uint8)
    Image.fromarray(out, "RGBA").save(path)


PICTURES = {
    "pequi": pequi, "buriti": buriti, "canela": canela, "tree": tree, "bush": bush, "tuft": tuft, "reeds": reeds,
    "mound": mound, "frog": frog, "spider": spider, "owl_body": owl_body, "owl_wing": owl_wing,
    "wolf_body": wolf_body, "wolf_leg": wolf_leg, "pond": pond, "ground": ground, "sky": sky, "hills": hills,
    "branch": branch,
}


def preview(names):
    from PIL import Image
    ims = [Image.open(os.path.join(ROOT, "data", n + ".png")).convert("RGBA") for n in names]
    h = max(i.height for i in ims) + 40
    sheet = Image.new("RGBA", (sum(i.width + 30 for i in ims) + 30, h), (16, 26, 48, 255))
    x = 30
    for im in ims:
        sheet.alpha_composite(im, (x, h - im.height - 20))
        x += im.width + 30
    sheet.convert("RGB").save(os.path.join(ROOT, "art", "preview.png"))


if __name__ == "__main__":
    names = [a for a in sys.argv[1:] if not a.startswith("--")] or list(PICTURES) + ["icon"]
    if "icon" in names:
        names.remove("icon")
        write_icons()
        print("drew icon")
    for n in names:
        render(n, PICTURES[n]())
        print("drew", n)
    if "--preview" in sys.argv:
        preview(names)
