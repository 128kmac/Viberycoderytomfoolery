"""Contact-sheet renderer: shows each texture's colour, normal, MERS and a
2x2 tiled, normal-mapped, sun-lit render so seams and relief are visible."""

from __future__ import annotations

import numpy as np
from PIL import Image, ImageDraw

from .pbr import finalize, normal_from_height


def shade(alb, n_dx, rough, metal, emis, light=(-0.55, 0.65, 0.52)):
    nx = n_dx[..., 0]
    ny = -n_dx[..., 1]                 # DirectX green -> +Y up
    nzv = n_dx[..., 2]
    L = np.array(light, dtype=float)
    L /= np.linalg.norm(L)
    V = np.array([0.0, 0.0, 1.0])
    Hh = (L + V) / np.linalg.norm(L + V)
    ndl = np.clip(nx * L[0] + ny * L[1] + nzv * L[2], 0, 1)
    ndh = np.clip(nx * Hh[0] + ny * Hh[1] + nzv * Hh[2], 0, 1)
    a = np.clip(rough, 0.04, 1) ** 2
    d = a * a / (np.pi * ((ndh ** 2) * (a * a - 1) + 1) ** 2 + 1e-6)
    f0 = 0.04 * (1 - metal)[..., None] + alb * metal[..., None]
    spec = f0 * (d * ndl * 0.25)[..., None]
    diff = alb * (1 - metal)[..., None] * ndl[..., None]
    amb = alb * 0.22 + f0 * 0.15
    col = diff * 1.25 + spec + amb + alb * emis[..., None] * 1.5
    col = col / (1 + col * 0.35)
    return np.clip(col, 0, 1)


def tiles_for(mat, frames=1):
    alb, h, rough, metal, emis, sss, alpha = finalize(mat, frames)
    fh = h.shape[0] // frames
    sl = slice(0, fh)
    alb, h, rough, metal, emis, sss = alb[sl], h[sl], rough[sl], metal[sl], emis[sl], sss[sl]
    a = None if alpha is None else alpha[sl]
    n = normal_from_height(h, mat.depth, 1)
    lit = shade(np.tile(alb, (2, 2, 1)), np.tile(n, (2, 2, 1)), np.tile(rough, (2, 2)),
                np.tile(metal, (2, 2)), np.tile(emis, (2, 2)))
    if a is not None:
        aa = np.tile(a, (2, 2))[..., None]
        checker = ((np.indices(aa.shape[:2]).sum(0) // 8) % 2)[..., None] * 0.15 + 0.2
        lit = lit * aa + checker * (1 - aa)
        alb_v = alb * a[..., None] + (1 - a[..., None]) * 0.25
    else:
        alb_v = alb
    mers = np.dstack([metal, emis, rough])
    return [alb_v, n * 0.5 + 0.5, mers, lit]


def sheet(items, path, scale=2, cols=2):
    """items: list of (label, material, frames)."""
    rows = []
    for label, mat, frames in items:
        t = tiles_for(mat, frames)
        rows.append((label, t))
    if not rows:
        return
    n = rows[0][1][0].shape[0]
    cell_w = (n * 3 + n * 2 + 4 * 6) * scale
    cell_h = (n * 2) * scale + 18
    nrow = (len(rows) + cols - 1) // cols
    img = Image.new("RGB", (cell_w * cols, cell_h * nrow), (24, 24, 28))
    dr = ImageDraw.Draw(img)
    for i, (label, t) in enumerate(rows):
        cx = (i % cols) * cell_w
        cy = (i // cols) * cell_h
        dr.text((cx + 4, cy + 2), label, fill=(230, 230, 230))
        ox = cx + 4
        for j, a in enumerate(t):
            im = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))
            im = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
            img.paste(im, (ox, cy + 16))
            ox += im.width + 6 * scale
    img.save(path)
    return path
