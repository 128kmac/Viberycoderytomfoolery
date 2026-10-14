"""Animated water and lava, plus the underwater caustics sprite sheet.

All animations loop seamlessly: spatial frequencies are integers per tile
(so every frame tiles) and temporal frequencies are integers per loop (so the
last frame flows back into the first).
"""

from __future__ import annotations

import numpy as np
from PIL import Image

from .. import noise as nz
from ..lib import mix
from ..noise import fbm, ramp, smoothstep, worley
from ..pbr import Material
from ..registry import add

WATER_FRAMES = 32
LAVA_FRAMES = 32


def wave_set(seed, n=14, kmax=6):
    r = nz.rng(nz.sub(seed, "waves"))
    waves = []
    for i in range(n):
        while True:
            kx, ky = r.integers(-kmax, kmax + 1, size=2)
            if (kx, ky) != (0, 0):
                break
        k = np.hypot(kx, ky)
        # Deep-water dispersion (omega ~ sqrt(k)) rounded to whole cycles per loop.
        w = max(1, int(round(np.sqrt(k) * 1.6)))
        amp = 1.0 / (k ** 1.2)
        waves.append((kx, ky, w * (1 if r.random() > 0.15 else -1), amp, r.uniform(0, 2 * np.pi)))
    return waves


def water_height(x, y, t, waves, chop=0.6):
    h = np.zeros_like(x)
    for kx, ky, w, a, ph in waves:
        phase = 2 * np.pi * (kx * x + ky * y - w * t) + ph
        # Trochoid-ish sharpening: crests narrower than troughs.
        s = np.sin(phase)
        h += a * (s - chop * 0.25 * (np.cos(2 * phase)))
    return h


def water_still(ctx, seed, frames=WATER_FRAMES):
    x, y = ctx.x, ctx.y
    waves = wave_set(seed)
    fine = wave_set(nz.sub(seed, "fine"), n=10, kmax=12)
    hs = [water_height(x, y, k / frames, waves) + 0.35 * water_height(x, y, k / frames, fine)
          for k in range(frames)]
    H = np.concatenate(hs)
    H = (H - H.min()) / (H.max() - H.min())
    tone = 0.62 + 0.06 * (H - 0.5)
    col = np.repeat(tone[..., None], 3, axis=2)
    # Foam-free, very smooth; crests are slightly rougher (micro ripples).
    rough = 0.05 + 0.06 * smoothstep(0.6, 1.0, H)
    return Material(col, H, rough, metal=0.07, alpha=240 / 255, depth=1.2, ao=0.0)


def water_flow(ctx, seed, frames=WATER_FRAMES):
    x, y = ctx.x, ctx.y
    hs = []
    for k in range(frames):
        t = k / frames
        # Scroll the whole field exactly one tile per loop, along +y (downstream).
        a = fbm(x, y - t, 3, 4, seed=seed, period_y=2)
        b = fbm(x, y - 2 * t, 6, 3, seed=nz.sub(seed, "b"), period_y=3)
        streak = fbm(x, y - t, 12, 2, seed=nz.sub(seed, "s"), period_y=2)
        hs.append(0.5 * a + 0.3 * b + 0.2 * streak)
    H = nz.norm01(np.concatenate(hs))
    tone = 0.63 + 0.08 * (H - 0.5)
    col = np.repeat(tone[..., None], 3, axis=2)
    foam = smoothstep(0.82, 0.95, H)
    col = mix(col, np.full(col.shape, 0.85), foam * 0.4)
    rough = 0.07 + 0.15 * foam
    return Material(col, H, rough, metal=0.07, alpha=240 / 255, depth=1.6, ao=0.0)


add("water_still_grey", lambda ctx, seed: water_still(ctx, seed), frames=WATER_FRAMES)
add("water_flow_grey", lambda ctx, seed: water_flow(ctx, seed), frames=WATER_FRAMES, width_mul=2)
add("cauldron_water", lambda ctx, seed: water_still(ctx, nz.sub("water_still_grey")), frames=WATER_FRAMES)


def lava_field(x, y, t, seed):
    # Convection cells whose centres orbit, so the loop closes on itself.
    ox, oy = np.cos(2 * np.pi * t) * 0.06, np.sin(2 * np.pi * t) * 0.06
    w = worley(x + ox, y + oy, 4, seed=seed, jitter=0.8)
    w2 = worley(x - oy * 1.5, y + ox * 1.5, 9, seed=nz.sub(seed, "2"), jitter=1.0)
    n = fbm(x + oy, y - ox, 4, 5, seed=nz.sub(seed, "n"))
    crust = smoothstep(0.08, 0.35, w["edge"]) * smoothstep(0.3, 0.7, n)
    crust = np.clip(crust + smoothstep(0.1, 0.3, w2["edge"]) * 0.3 * crust, 0, 1)
    heat = 1 - crust
    return heat, crust, n


def lava_still(ctx, seed, frames=LAVA_FRAMES):
    x, y = ctx.x, ctx.y
    cols, hs, es, rs = [], [], [], []
    for k in range(frames):
        heat, crust, n = lava_field(x, y, k / frames, seed)
        hot = ramp(0.5 * heat + 0.5 * n, [(0, (196, 60, 4)), (0.5, (246, 128, 18)), (0.85, (255, 196, 60)), (1, (255, 240, 150))])
        cold = ramp(n, [(0, (70, 18, 6)), (0.5, (110, 32, 8)), (1, (150, 50, 12))])
        cols.append(mix(hot, cold, crust))
        hs.append(np.clip(0.35 + 0.55 * crust + 0.1 * n, 0, 1))
        es.append(np.clip(0.35 + 0.65 * heat, 0, 1))
        rs.append(0.25 + 0.6 * crust)
    return Material(np.concatenate(cols), np.concatenate(hs), np.concatenate(rs), emissive=np.concatenate(es),
                    depth=2.4, ao=0.15)


def lava_flow(ctx, seed, frames=16):
    x, y = ctx.x, ctx.y
    cols, hs, es, rs = [], [], [], []
    for k in range(frames):
        t = k / frames
        n = fbm(x, y - t, 3, 5, seed=seed, period_y=2)
        st = fbm(x, y - t, 8, 3, seed=nz.sub(seed, "s"), period_y=2)
        crust = smoothstep(0.55, 0.75, 0.6 * n + 0.4 * st)
        heat = 1 - crust
        hot = ramp(0.5 * heat + 0.5 * st, [(0, (200, 64, 4)), (0.6, (248, 136, 20)), (1, (255, 226, 120))])
        cold = ramp(n, [(0, (76, 20, 6)), (1, (140, 44, 10))])
        cols.append(mix(hot, cold, crust))
        hs.append(np.clip(0.35 + 0.5 * crust + 0.15 * st, 0, 1))
        es.append(0.35 + 0.65 * heat)
        rs.append(0.25 + 0.6 * crust)
    return Material(np.concatenate(cols), np.concatenate(hs), np.concatenate(rs), emissive=np.concatenate(es),
                    depth=2.4, ao=0.15)


add("lava_still", lambda ctx, seed: lava_still(ctx, seed), frames=LAVA_FRAMES)
add("lava_flow", lambda ctx, seed: lava_flow(ctx, seed), frames=16, width_mul=2)


# --------------------------------------------------------------------------
# Caustics: photon-mapped through an animated wave surface
# --------------------------------------------------------------------------

def caustics_sheet(size=128, frames=32, photons=4, seed="caustics", strength=0.042):
    """Render a vertical sprite sheet of seamless, looping caustics.

    For each frame a periodic wave surface refracts a dense grid of light rays
    (Snell's law, small-slope approximation) down to a floor; the landing
    density of the rays is the caustic intensity.
    """
    waves = wave_set(seed, n=12, kmax=4)
    m = size * photons
    gx, gy = nz.grid(m)
    out = np.zeros((size * frames, size))
    for k in range(frames):
        t = k / frames
        h = water_height(gx, gy, t, waves, chop=0.3)
        dhx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * m / 2
        dhy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * m / 2
        scale = strength / np.abs(np.concatenate([dhx.ravel(), dhy.ravel()])).std()
        px = (gx - dhx * scale) % 1.0
        py = (gy - dhy * scale) % 1.0
        ix = np.floor(px * size).astype(int) % size
        iy = np.floor(py * size).astype(int) % size
        acc = np.bincount((iy * size + ix).ravel(), minlength=size * size).reshape(size, size).astype(float)
        acc = nz.blur(acc, 1, 1)
        out[k * size:(k + 1) * size] = acc
    out = out / np.percentile(out, 99.0)
    out = np.clip(out, 0, 1) ** 1.1
    return out


def write_caustics(path, size=128, frames=32):
    sheet = caustics_sheet(size, frames)
    img = (np.clip(sheet, 0, 1) * 255).astype(np.uint8)
    Image.fromarray(np.dstack([img, img, img]), "RGB").save(path, optimize=True)
    return path
