"""Reusable procedural building blocks shared by the material recipes."""

from __future__ import annotations

import numpy as np

from . import noise as nz
from .noise import fbm, ridged, smoothstep, worley


class Ctx:
    """Resolution context: every recipe receives one of these."""

    def __init__(self, n: int, frames: int = 1, width_mul: int = 1):
        self.n = n
        self.w = n * width_mul
        self.h = self.w
        self.x, self.y = nz.grid(self.w)

    @property
    def px(self):
        """Size of one vanilla (16x) pixel, in texture pixels."""
        return self.w / 16.0


# --------------------------------------------------------------------------
# Colour helpers
# --------------------------------------------------------------------------

def rgb(c):
    if isinstance(c, str):
        c = nz.hexrgb(c)
    return np.array(c, dtype=float) / 255.0


def shade(base, t, lo=0.75, hi=1.2):
    """Scale a base colour by a scalar field mapped to [lo, hi]."""
    s = lo + (hi - lo) * np.clip(t, 0, 1)
    return np.clip(rgb(base)[None, None, :] * s[..., None], 0, 1)


def mix(a, b, t):
    t = np.asarray(t)
    if t.ndim == 2:
        t = t[..., None]
    return a * (1 - t) + b * t


def solid(ctx, c):
    return np.broadcast_to(rgb(c), (ctx.h, ctx.w, 3)).copy()


def gray(v):
    return np.repeat(np.asarray(v)[..., None], 3, axis=2)


def hue_jitter(col, amount, seed, ctx, period=4):
    """Low-frequency per-channel colour drift (keeps big surfaces lively)."""
    out = col.copy()
    for c in range(3):
        out[..., c] *= 1.0 + (fbm(ctx.x, ctx.y, period, 3, seed=nz.sub(seed, c)) - 0.5) * amount
    return np.clip(out, 0, 1)


def grain_noise(ctx, seed, amount=0.06):
    """Pixel-scale grain."""
    r = nz.rng(nz.sub(seed, "grain"))
    return (r.random((ctx.h, ctx.w)) - 0.5) * amount


def desat(col, k):
    l = col.mean(axis=2, keepdims=True)
    return col * (1 - k) + l * k


# --------------------------------------------------------------------------
# Rock and earth fields
# --------------------------------------------------------------------------

def rock(ctx, seed, period=4, crack=0.25, warp=0.08, octaves=6):
    """General rock height field with domain warp and hairline cracks."""
    x, y = ctx.x, ctx.y
    wx = (fbm(x, y, 2, 3, seed=nz.sub(seed, "wx")) - 0.5) * warp
    wy = (fbm(x, y, 2, 3, seed=nz.sub(seed, "wy")) - 0.5) * warp
    base = fbm(x + wx, y + wy, period, octaves, gain=0.55, seed=seed)
    cr = ridged(x + wx, y + wy, period, 4, seed=nz.sub(seed, "cr"))
    cracks = smoothstep(0.72, 0.95, cr)
    h = base - cracks * crack
    return nz.norm01(h), cracks


def pebbles(ctx, seed, cells=10, round_=0.6, jitter=0.9, gap=0.05):
    """Rounded pebbles packed in a wrapping Voronoi diagram."""
    w = worley(ctx.x, ctx.y, cells, seed=seed, jitter=jitter)
    e = w["edge"]
    dome = smoothstep(gap, gap + round_, e)
    dome = np.sqrt(np.clip(dome, 0, 1))
    return dome, w


def strata(ctx, seed, bands=6, wobble=0.05, sharp=0.5):
    """Horizontal sedimentary layers."""
    x, y = ctx.x, ctx.y
    off = (fbm(x, y, 3, 3, seed=nz.sub(seed, "s")) - 0.5) * wobble
    t = (y + off) * bands
    band_id = np.floor(t)
    f = t - band_id
    edge = smoothstep(0.0, sharp * 0.2, f) * smoothstep(1.0, 1.0 - sharp * 0.2, f)
    r = nz.rng(nz.sub(seed, "b")).random(int(bands) + 2)
    return edge, r[(band_id.astype(int) % int(bands))]


# --------------------------------------------------------------------------
# Masonry layouts
# --------------------------------------------------------------------------

def bricks(ctx, rows, cols, offset=0.5, mortar=1.0, seed=0, chip=0.6,
           col_per_row=None):
    """Running-bond brick layout.

    mortar and chip are expressed in vanilla pixels so the look is the same
    at any output resolution. Returns dict with:
      d      distance (texture px) from the nearest joint
      inside 1 inside a brick, 0 in the mortar
      rnd    per-brick random value, id per-brick integer, u/v local coords
    """
    x, y = ctx.x, ctx.y
    W = ctx.w
    row = np.floor(y * rows).astype(int)
    v = y * rows - row
    c = cols if col_per_row is None else np.asarray(col_per_row)[row % len(col_per_row)]
    shift = (row * offset) % 1.0
    bx = x * c + shift
    col = np.floor(bx).astype(int) % c
    u = bx - np.floor(bx)
    du = np.minimum(u, 1 - u) * (W / c)
    dv = np.minimum(v, 1 - v) * (W / rows)
    d = np.minimum(du, dv)
    # Chipped, irregular brick edges.
    n = fbm(x, y, 8, 3, seed=nz.sub(seed, "chip"))
    d = d + (n - 0.5) * chip * ctx.px * 2
    m = mortar * ctx.px * 0.5
    inside = smoothstep(m - 0.5, m + 0.5, d)
    bid = (row % rows) * 97 + col
    r = nz.rng(nz.sub(seed, "bricks")).random(rows * 97 + 97)
    return {"d": d - m, "inside": inside, "rnd": r[bid], "id": bid,
            "u": u, "v": v, "row": row, "col": col}


def bevel(d, width_px):
    """Brick/stone edge profile: rises from 0 at the joint to 1."""
    t = np.clip(d / max(width_px, 1e-6), 0, 1)
    return np.sin(t * np.pi / 2)


def grid_tiles(ctx, nx, ny, mortar=1.0, seed=0, chip=0.3):
    return bricks(ctx, ny, nx, offset=0.0, mortar=mortar, seed=seed, chip=chip)


def frame_border(ctx, width_vpx):
    """Distance (in vanilla px) from the texture border, for framed blocks."""
    x, y = ctx.x, ctx.y
    d = np.minimum(np.minimum(x, 1 - x), np.minimum(y, 1 - y)) * 16
    return d


# --------------------------------------------------------------------------
# Wood
# --------------------------------------------------------------------------

def wood_grain(ctx, seed, along="x", rings=14, warp=0.35, fine=0.35):
    """Flat-sawn grain field in [0,1]: smooth bands with darker latewood."""
    x, y = ctx.x, ctx.y
    if along == "x":
        a, b = x, y
    else:
        a, b = y, x
    # Warp across the grain so rings meander but stay periodic.
    wv = fbm(a, b, 2, 4, seed=nz.sub(seed, "gw"), period_y=6) - 0.5
    t = b * rings + wv * warp * rings * 0.25
    t = t + (fbm(a, b, 1, 3, seed=nz.sub(seed, "gw2"), period_y=3) - 0.5) * 2.0
    band = 0.5 + 0.5 * np.cos(t * 2 * np.pi)
    late = smoothstep(0.65, 0.98, band)
    # Fine pores along the grain.
    if along == "x":
        pores = fbm(x, y, 2, 4, seed=nz.sub(seed, "p"), period_y=32)
    else:
        pores = fbm(x, y, 32, 4, seed=nz.sub(seed, "p"), period_y=2)
    g = 0.55 * band + 0.25 * late + fine * (pores - 0.5)
    return np.clip(g, 0, 1), late


def planks_layout(ctx, boards=4, seed=0, joints=(0.25, 0.75, 0.5, 0.0)):
    """Horizontal boards with staggered butt joints (vanilla-like rhythm)."""
    x, y = ctx.x, ctx.y
    W = ctx.w
    row = np.floor(y * boards).astype(int)
    v = y * boards - row
    j = np.asarray(joints)[row % len(joints)]
    u = (x - j) % 1.0
    du = np.minimum(u, 1 - u) * W
    dv = np.minimum(v, 1 - v) * (W / boards)
    return {"row": row, "u": u, "v": v, "du": du, "dv": dv}


# --------------------------------------------------------------------------
# Stamping (grass blades, leaves, needles)
# --------------------------------------------------------------------------

def stamp(canvas_h, canvas_v, cx, cy, radius, fn, wrap=True):
    """Composite a small stamp onto wrapping canvases.

    fn(dx, dy) -> (height, value, mask) evaluated on the stamp's local pixel
    offsets; the stamp wins wherever its height exceeds what is there.
    """
    H, W = canvas_h.shape
    r = int(np.ceil(radius)) + 1
    ix = int(np.floor(cx))
    iy = int(np.floor(cy))
    xs = np.arange(ix - r, ix + r + 1)
    ys = np.arange(iy - r, iy + r + 1)
    DX, DY = np.meshgrid(xs + 0.5 - cx, ys + 0.5 - cy)
    h, val, m = fn(DX, DY)
    if not wrap:
        inb = ((ys >= 0) & (ys < H))[:, None] & ((xs >= 0) & (xs < W))[None, :]
        m = np.where(inb, m, 0)
    yy = (ys % H)[:, None]
    xx = (xs % W)[None, :]
    cur = canvas_h[yy, xx]
    win = (m > 0) & (h > cur)
    canvas_h[yy, xx] = np.where(win, h, cur)
    if canvas_v is not None:
        if canvas_v.ndim == 3:
            cv = canvas_v[yy, xx]
            canvas_v[yy, xx] = np.where(win[..., None], val, cv)
        else:
            canvas_v[yy, xx] = np.where(win, val, canvas_v[yy, xx])
    return win


def segment_dist(DX, DY, ax, ay, bx, by):
    px, py = DX - ax, DY - ay
    vx, vy = bx - ax, by - ay
    L2 = vx * vx + vy * vy + 1e-9
    t = np.clip((px * vx + py * vy) / L2, 0, 1)
    qx, qy = px - t * vx, py - t * vy
    return np.sqrt(qx * qx + qy * qy), t


def leaf_shape(length, width, angle, curl=0.0):
    """Returns a stamp function for a pointed elliptical leaf."""
    ca, sa = np.cos(angle), np.sin(angle)

    def fn(DX, DY):
        u = DX * ca + DY * sa            # along the leaf
        v = -DX * sa + DY * ca           # across
        v = v - curl * (u / length) ** 2 * width
        t = u / (length * 0.5)
        half = width * 0.5 * np.clip(1 - t * t, 0, 1) ** 0.75
        inside = np.abs(v) < half
        dome = np.where(inside, np.sqrt(np.clip(1 - (v / (half + 1e-6)) ** 2, 0, 1))
                        * np.clip(1 - np.abs(t) ** 3, 0, 1), 0)
        vein = np.exp(-(v / (0.12 * width + 0.3)) ** 2) * inside
        return dome, np.dstack([dome, vein, (t + 1) * 0.5]), inside.astype(float)

    return fn


def blade_shape(ax, ay, bx, by, w0, w1):
    """Tapered blade from (ax,ay) to (bx,by) in stamp-local coordinates."""

    def fn(DX, DY):
        d, t = segment_dist(DX, DY, ax, ay, bx, by)
        w = w0 + (w1 - w0) * t
        inside = d < w
        prof = np.where(inside, np.sqrt(np.clip(1 - (d / (w + 1e-6)) ** 2, 0, 1)), 0)
        return prof * (0.6 + 0.4 * t), np.dstack([prof, t, d / (w + 1e-6)]), inside.astype(float)

    return fn
