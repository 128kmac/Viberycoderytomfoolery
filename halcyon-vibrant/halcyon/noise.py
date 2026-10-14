"""Tileable procedural noise.

Every function here samples a field that wraps seamlessly over the unit
square, so a 64x64 (or any size) texture generated from it tiles across
neighbouring blocks with no visible seam. Coordinates are in "tile units":
(0, 0) is the top-left corner of the texture and (1, 1) the bottom-right.
Periods are integer lattice counts per tile, which is what makes the
wrap exact.
"""

from __future__ import annotations

import zlib

import numpy as np

TAU = 2.0 * np.pi


# --------------------------------------------------------------------------
# Coordinates and RNG
# --------------------------------------------------------------------------

def grid(n: int, m: int | None = None) -> tuple[np.ndarray, np.ndarray]:
    """Pixel-centre coordinates for an n (wide) x m (tall) texture."""
    m = n if m is None else m
    x = (np.arange(n) + 0.5) / n
    y = (np.arange(m) + 0.5) / m
    return np.meshgrid(x, y)


def sub(*parts) -> int:
    """Deterministic seed derived from any mix of ints/strings (Python's
    built-in hash is salted per process, so it can't be used here)."""
    return zlib.crc32(repr(parts).encode("utf8"))


def rng(seed) -> np.random.Generator:
    if not isinstance(seed, (int, np.integer)):
        seed = sub(seed)
    return np.random.default_rng(int(seed))


def _fade(t):
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


# --------------------------------------------------------------------------
# Lattice noises
# --------------------------------------------------------------------------

def perlin(x, y, period, seed=0, period_y=None):
    """Periodic gradient noise in roughly [-0.7, 0.7]."""
    px = int(period)
    py = int(period if period_y is None else period_y)
    r = rng(seed)
    ang = r.uniform(0.0, TAU, size=(py, px))
    gx, gy = np.cos(ang), np.sin(ang)

    X = np.asarray(x) * px
    Y = np.asarray(y) * py
    x0 = np.floor(X).astype(np.int64)
    y0 = np.floor(Y).astype(np.int64)
    fx = X - x0
    fy = Y - y0
    x0 %= px
    y0 %= py
    x1 = (x0 + 1) % px
    y1 = (y0 + 1) % py

    def dot(ix, iy, dx, dy):
        return gx[iy, ix] * dx + gy[iy, ix] * dy

    n00 = dot(x0, y0, fx, fy)
    n10 = dot(x1, y0, fx - 1.0, fy)
    n01 = dot(x0, y1, fx, fy - 1.0)
    n11 = dot(x1, y1, fx - 1.0, fy - 1.0)
    u, v = _fade(fx), _fade(fy)
    nx0 = n00 + u * (n10 - n00)
    nx1 = n01 + u * (n11 - n01)
    return nx0 + v * (nx1 - nx0)


def value(x, y, period, seed=0, period_y=None):
    """Periodic value noise in [0, 1]."""
    px = int(period)
    py = int(period if period_y is None else period_y)
    lat = rng(seed).random((py, px))
    X = np.asarray(x) * px
    Y = np.asarray(y) * py
    x0 = np.floor(X).astype(np.int64)
    y0 = np.floor(Y).astype(np.int64)
    u = _fade(X - x0)
    v = _fade(Y - y0)
    x0 %= px
    y0 %= py
    x1 = (x0 + 1) % px
    y1 = (y0 + 1) % py
    a = lat[y0, x0] + u * (lat[y0, x1] - lat[y0, x0])
    b = lat[y1, x0] + u * (lat[y1, x1] - lat[y1, x0])
    return a + v * (b - a)


def fbm(x, y, period=4, octaves=5, gain=0.5, lacunarity=2, seed=0,
        kind="perlin", period_y=None):
    """Fractal sum, normalised to roughly [0, 1]. Lacunarity must be an
    integer so every octave keeps an integer period (and therefore tiles)."""
    fn = perlin if kind == "perlin" else value
    total = np.zeros(np.shape(x))
    amp, norm = 1.0, 0.0
    p = int(period)
    pyy = int(period if period_y is None else period_y)
    for o in range(octaves):
        n = fn(x, y, p, seed=sub(seed, o, kind), period_y=pyy)
        if kind == "perlin":
            n = n * 0.7 + 0.5
        total += n * amp
        norm += amp
        amp *= gain
        p *= int(lacunarity)
        pyy *= int(lacunarity)
    return total / norm


def ridged(x, y, period=4, octaves=5, gain=0.5, seed=0, period_y=None):
    """Ridged multifractal: sharp creases, good for cracks and veins."""
    total = np.zeros(np.shape(x))
    amp, norm = 1.0, 0.0
    p = int(period)
    pyy = int(period if period_y is None else period_y)
    for o in range(octaves):
        n = 1.0 - np.abs(perlin(x, y, p, seed=sub(seed, o, "r"),
                                period_y=pyy)) * 1.6
        total += np.clip(n, 0, 1) ** 2 * amp
        norm += amp
        amp *= gain
        p *= 2
        pyy *= 2
    return total / norm


def turbulence(x, y, period=4, octaves=5, gain=0.5, seed=0):
    total = np.zeros(np.shape(x))
    amp, norm = 1.0, 0.0
    p = int(period)
    for o in range(octaves):
        total += np.abs(perlin(x, y, p, seed=sub(seed, o, "t"))) * amp
        norm += amp
        amp *= gain
        p *= 2
    return np.clip(total / norm * 2.2, 0, 1)


# --------------------------------------------------------------------------
# Cellular (Worley / Voronoi)
# --------------------------------------------------------------------------

def worley(x, y, cells=6, seed=0, jitter=1.0, cells_y=None, metric="euclid",
           stretch=(1.0, 1.0)):
    """Periodic Worley noise.

    Returns a dict with:
      f1, f2   nearest / second-nearest feature distance (in cell units)
      edge     f2 - f1 (0 on the Voronoi border, grows towards centres)
      id       integer id of the owning cell (stable per cell)
      rnd      a uniform random value in [0,1) per owning cell
      cx, cy   owning feature point position (tile units, unwrapped)
    """
    cx_n = int(cells)
    cy_n = int(cells if cells_y is None else cells_y)
    r = rng(seed)
    off = r.random((cy_n, cx_n, 2))
    off = 0.5 + (off - 0.5) * jitter
    cell_rnd = r.random((cy_n, cx_n))

    X = np.asarray(x) * cx_n
    Y = np.asarray(y) * cy_n
    ix = np.floor(X).astype(np.int64)
    iy = np.floor(Y).astype(np.int64)

    shape = np.shape(X)
    f1 = np.full(shape, 1e9)
    f2 = np.full(shape, 1e9)
    own = np.zeros(shape, dtype=np.int64)
    ocx = np.zeros(shape)
    ocy = np.zeros(shape)
    sx, sy = stretch
    for dj in (-1, 0, 1):
        for di in (-1, 0, 1):
            nx = ix + di
            ny = iy + dj
            wx = nx % cx_n
            wy = ny % cy_n
            px = nx + off[wy, wx, 0]
            py = ny + off[wy, wx, 1]
            dx = (X - px) * sx
            dy = (Y - py) * sy
            if metric == "manhattan":
                d = np.abs(dx) + np.abs(dy)
            elif metric == "cheby":
                d = np.maximum(np.abs(dx), np.abs(dy))
            else:
                d = np.sqrt(dx * dx + dy * dy)
            closer = d < f1
            f2 = np.where(closer, f1, np.minimum(f2, d))
            f1 = np.where(closer, d, f1)
            cid = wy * cx_n + wx
            own = np.where(closer, cid, own)
            ocx = np.where(closer, px / cx_n, ocx)
            ocy = np.where(closer, py / cy_n, ocy)
    return {
        "f1": f1,
        "f2": f2,
        "edge": f2 - f1,
        "id": own,
        "rnd": cell_rnd.ravel()[own],
        "cx": ocx,
        "cy": ocy,
    }


# --------------------------------------------------------------------------
# Field utilities
# --------------------------------------------------------------------------

def norm01(a):
    lo, hi = np.min(a), np.max(a)
    if hi - lo < 1e-9:
        return np.zeros_like(a)
    return (a - lo) / (hi - lo)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def levels(a, lo, hi, gamma=1.0):
    return np.clip((a - lo) / (hi - lo), 0, 1) ** gamma


def blur(a, radius=1, passes=1):
    """Wrapping box blur (repeated passes approximate a gaussian)."""
    out = a.astype(float)
    for _ in range(passes):
        acc = np.zeros_like(out)
        for d in range(-radius, radius + 1):
            acc += np.roll(out, d, axis=1)
        out = acc / (2 * radius + 1)
        acc = np.zeros_like(out)
        for d in range(-radius, radius + 1):
            acc += np.roll(out, d, axis=0)
        out = acc / (2 * radius + 1)
    return out


def sample_wrap(field, x, y):
    """Bilinear sample of a periodic 2-D field at tile coordinates."""
    h, w = field.shape[:2]
    X = np.asarray(x) * w - 0.5
    Y = np.asarray(y) * h - 0.5
    x0 = np.floor(X).astype(np.int64)
    y0 = np.floor(Y).astype(np.int64)
    fx = X - x0
    fy = Y - y0
    x0 %= w
    y0 %= h
    x1 = (x0 + 1) % w
    y1 = (y0 + 1) % h
    if field.ndim == 3:
        fx = fx[..., None]
        fy = fy[..., None]
    a = field[y0, x0] * (1 - fx) + field[y0, x1] * fx
    b = field[y1, x0] * (1 - fx) + field[y1, x1] * fx
    return a * (1 - fy) + b * fy


def ramp(t, stops):
    """Gradient map: stops is [(pos, (r,g,b)), ...] with colours in 0-255."""
    t = np.clip(t, 0, 1)
    pos = np.array([s[0] for s in stops], dtype=float)
    col = np.array([s[1] for s in stops], dtype=float) / 255.0
    out = np.empty(np.shape(t) + (3,))
    for c in range(3):
        out[..., c] = np.interp(t, pos, col[:, c])
    return out


def hexrgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
