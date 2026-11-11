"""Drawing helpers for Lume's art: organic shapes as smooth SVG paths,
shaded in a few flat tones, the way a vector illustrator would build them.

Everything is deterministic: shapes take a seed.
"""
import math
import random


def rnd(seed):
    return random.Random(seed)


def smooth(points, closed=True, tension=0.5):
    """An SVG path through the points, rounded (Catmull-Rom as Beziers)."""
    n = len(points)
    if n < 3:
        return "M" + " L".join(f"{x:.1f},{y:.1f}" for x, y in points)
    d = [f"M{points[0][0]:.1f},{points[0][1]:.1f}"]
    last = n if closed else n - 1
    for i in range(last):
        p0 = points[(i - 1) % n] if closed or i > 0 else points[0]
        p1 = points[i % n]
        p2 = points[(i + 1) % n]
        p3 = points[(i + 2) % n] if closed or i + 2 < n else points[n - 1]
        c1 = (p1[0] + (p2[0] - p0[0]) * tension / 3, p1[1] + (p2[1] - p0[1]) * tension / 3)
        c2 = (p2[0] - (p3[0] - p1[0]) * tension / 3, p2[1] - (p3[1] - p1[1]) * tension / 3)
        d.append(f"C{c1[0]:.1f},{c1[1]:.1f} {c2[0]:.1f},{c2[1]:.1f} {p2[0]:.1f},{p2[1]:.1f}")
    if closed:
        d.append("Z")
    return " ".join(d)


def blob(cx, cy, rx, ry, seed, n=11, wobble=0.16, rotate=0.0):
    """A lumpy closed shape around an ellipse."""
    r = rnd(seed)
    pts = []
    start = r.uniform(0, math.tau)
    for i in range(n):
        a = start + i / n * math.tau
        k = 1 + r.uniform(-wobble, wobble)
        x, y = math.cos(a) * rx * k, math.sin(a) * ry * k
        ca, sa = math.cos(rotate), math.sin(rotate)
        pts.append((cx + x * ca - y * sa, cy + x * sa + y * ca))
    return smooth(pts)


def limb(points, widths):
    """A tapering branch along a centre line: the outline as a closed path."""
    left, right = [], []
    n = len(points)
    for i, (x, y) in enumerate(points):
        ax, ay = points[max(i - 1, 0)]
        bx, by = points[min(i + 1, n - 1)]
        dx, dy = bx - ax, by - ay
        d = math.hypot(dx, dy) or 1
        nx, ny = -dy / d, dx / d
        w = widths[i] / 2
        left.append((x + nx * w, y + ny * w))
        right.append((x - nx * w, y - ny * w))
    return smooth(left + right[::-1], tension=0.45)


def leaf(x, y, length, width, angle, bend=0.0):
    """A pointed leaf from (x, y), `angle` in radians; `bend` curls it."""
    ca, sa = math.cos(angle), math.sin(angle)

    def at(t, side):
        px = t * length
        py = side * width / 2 * math.sin(math.pi * min(t * 1.15, 1)) ** 0.8 + bend * length * t * t
        return (x + px * ca - py * sa, y + px * sa + py * ca)
    tip = at(1, 0)
    a1, a2 = at(0.3, 1), at(0.7, 1)
    b1, b2 = at(0.7, -1), at(0.3, -1)
    return (f"M{x:.1f},{y:.1f} C{a1[0]:.1f},{a1[1]:.1f} {a2[0]:.1f},{a2[1]:.1f} {tip[0]:.1f},{tip[1]:.1f} "
            f"C{b1[0]:.1f},{b1[1]:.1f} {b2[0]:.1f},{b2[1]:.1f} {x:.1f},{y:.1f} Z")


class Svg:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.defs, self.body = [], []
        self.ids = 0

    def uid(self, prefix="i"):
        self.ids += 1
        return f"{prefix}{self.ids}"

    def add(self, s):
        self.body.append(s)

    def path(self, d, fill, opacity=1.0, stroke=None, width=0, extra=""):
        s = f'<path d="{d}" fill="{fill}"'
        if opacity < 1:
            s += f' opacity="{opacity:.3f}"'
        if stroke:
            s += f' stroke="{stroke}" stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round"'
        self.add(s + f" {extra}/>")

    def line(self, d, stroke, width, opacity=1.0, extra=""):
        self.add(f'<path d="{d}" fill="none" stroke="{stroke}" stroke-width="{width}" stroke-linecap="round" '
                 f'stroke-linejoin="round" opacity="{opacity:.3f}" {extra}/>')

    def circle(self, cx, cy, r, fill, opacity=1.0):
        self.add(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r:.1f}" fill="{fill}" opacity="{opacity:.3f}"/>')

    def ellipse(self, cx, cy, rx, ry, fill, opacity=1.0, extra=""):
        self.add(f'<ellipse cx="{cx:.1f}" cy="{cy:.1f}" rx="{rx:.1f}" ry="{ry:.1f}" fill="{fill}" opacity="{opacity:.3f}" {extra}/>')

    def clip(self, d):
        """Starts a group clipped to the path; close it with `end`."""
        i = self.uid("c")
        self.defs.append(f'<clipPath id="{i}"><path d="{d}"/></clipPath>')
        self.add(f'<g clip-path="url(#{i})">')

    def group(self, extra=""):
        self.add(f"<g {extra}>")

    def end(self):
        self.add("</g>")

    def linear(self, stops, x1=0, y1=0, x2=0, y2=1, units="objectBoundingBox"):
        i = self.uid("g")
        s = "".join(f'<stop offset="{o}" stop-color="{c}" stop-opacity="{a}"/>' for o, c, a in stops)
        self.defs.append(f'<linearGradient id="{i}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" gradientUnits="{units}">{s}</linearGradient>')
        return f"url(#{i})"

    def radial(self, stops, cx=0.5, cy=0.5, r=0.5, units="objectBoundingBox"):
        i = self.uid("g")
        s = "".join(f'<stop offset="{o}" stop-color="{c}" stop-opacity="{a}"/>' for o, c, a in stops)
        self.defs.append(f'<radialGradient id="{i}" cx="{cx}" cy="{cy}" r="{r}" gradientUnits="{units}">{s}</radialGradient>')
        return f"url(#{i})"

    def shaded(self, d, base, shade=None, light=None, shade_at=(0.25, 0.3), light_at=(-0.2, -0.25), size=None, seed=1):
        """A form in three tones: the base, a shadow mass low on one side
        and a lit mass high on the other, both cut to the form's outline."""
        self.path(d, base)
        if size is None:
            return
        cx, cy, rx, ry = size
        self.clip(d)
        if shade:
            self.path(blob(cx + rx * shade_at[0], cy + ry * shade_at[1], rx * 0.95, ry * 0.9, seed + 1, wobble=0.12), shade)
        if light:
            self.path(blob(cx + rx * light_at[0], cy + ry * light_at[1], rx * 0.62, ry * 0.55, seed + 2, wobble=0.14), light)
        self.end()

    def text(self):
        return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.w}" height="{self.h}" viewBox="0 0 {self.w} {self.h}">'
                f'<defs>{"".join(self.defs)}</defs>{"".join(self.body)}</svg>')
