"""Procedural pack icon: golden-hour sun over voxel hills and a calm sea."""

from __future__ import annotations

import numpy as np
from PIL import Image

from . import noise as nz


def render(size=256):
    s = size
    y, x = np.mgrid[0:s, 0:s] / s
    horizon = 0.62
    # Sky: deep zenith to warm horizon
    t = np.clip(y / horizon, 0, 1)
    zen = np.array([0.10, 0.16, 0.38])
    mid = np.array([0.55, 0.42, 0.62])
    hor = np.array([1.0, 0.62, 0.34])
    sky = np.where((t < 0.55)[..., None],
                   zen + (mid - zen) * (t / 0.55)[..., None],
                   mid + (hor - mid) * ((t - 0.55) / 0.45)[..., None])
    sx, sy = 0.62, 0.53
    d = np.sqrt((x - sx) ** 2 + ((y - sy) * 1.0) ** 2)
    glow = np.exp(-d * 9) * 0.9 + np.exp(-d * 30) * 0.6
    sky = sky + glow[..., None] * np.array([1.0, 0.75, 0.45])
    sun = d < 0.055
    sky = np.where(sun[..., None], np.array([1.0, 0.96, 0.85]), sky)
    img = sky.copy()

    # Water with sun glitter column
    water = y > horizon
    wt = (y - horizon) / (1 - horizon)
    wcol = np.array([0.08, 0.16, 0.30]) * (1 - wt[..., None] * 0.5) + np.array([0.6, 0.38, 0.3]) * (1 - wt[..., None]) * 0.35
    # Horizontal glitter streaks, finer near the horizon (perspective).
    ripple = nz.fbm(x * (0.5 + wt), y * (1.0 + 0.0 * wt), 8, 3, seed=11, period_y=96)
    col_w = np.exp(-((x - sx) / (0.03 + wt * 0.12)) ** 2)
    glint = nz.smoothstep(0.6, 0.72, ripple) * col_w * (1 - wt * 0.6)
    wcol = wcol + glint[..., None] * np.array([1.0, 0.8, 0.5])
    img = np.where(water[..., None], wcol, img)

    # Voxel hills (stepped silhouettes), two layers
    for layer, (base, amp, colr, seed) in enumerate([
        (0.56, 0.12, np.array([0.30, 0.22, 0.36]), 3),
        (0.64, 0.16, np.array([0.08, 0.10, 0.12]), 7),
    ]):
        cols = 16 + layer * 8
        r = nz.rng(seed)
        heights = np.convolve(r.random(cols + 4), np.ones(3) / 3, mode="same")[2:-2]
        hx = np.floor(x * cols).astype(int).clip(0, cols - 1)
        top = base - heights[hx] * amp - (layer == 1) * np.where(x < 0.35, (0.35 - x) * 0.5, 0)
        if layer == 1:
            # Foreground cliff on the left only, leaving the sea open to the sun.
            top = np.where(x > 0.42, 2.0, top + np.clip(x - 0.2, 0, 1) * 0.6)
        top = np.round(top * cols * 1.5) / (cols * 1.5)
        mask = (y > top) & (y < 0.72 + layer * 0.3)
        if layer == 0:
            mask &= y < horizon + 0.005
        rim = (y > top) & (y < top + 0.012)
        c = np.where(rim[..., None], colr + np.array([0.5, 0.3, 0.1]) * (0.6 - layer * 0.4), colr)
        img = np.where(mask[..., None], c, img)

    # Vignette
    v = 1 - 0.35 * (((x - 0.5) ** 2 + (y - 0.5) ** 2) * 2)
    img = np.clip(img * v[..., None], 0, 1)
    return Image.fromarray((img * 255).astype(np.uint8), "RGB")
