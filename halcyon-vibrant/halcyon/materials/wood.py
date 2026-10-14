"""Planks, bark, log ends and stripped wood for every tree species."""

from __future__ import annotations

import numpy as np

from .. import noise as nz
from ..lib import grain_noise, hue_jitter, mix, rgb
from ..noise import fbm, perlin, ramp, ridged, smoothstep, worley
from ..pbr import Material
from ..registry import add

# (dark, mid, light) plank tones
WOOD = {
    "oak": [(124, 94, 56), (162, 130, 80), (190, 156, 100)],
    "spruce": [(86, 60, 36), (114, 84, 52), (138, 104, 66)],
    "birch": [(176, 156, 104), (196, 178, 124), (214, 198, 146)],
    "jungle": [(130, 88, 60), (160, 114, 80), (182, 136, 98)],
    "acacia": [(150, 74, 40), (172, 92, 52), (194, 112, 66)],
    "dark_oak": [(52, 34, 18), (70, 46, 24), (92, 64, 36)],
    "mangrove": [(100, 40, 36), (122, 52, 46), (144, 68, 58)],
    "cherry": [(196, 144, 138), (222, 170, 162), (238, 192, 184)],
    "pale_oak": [(206, 192, 188), (224, 212, 208), (238, 230, 226)],
    "crimson": [(90, 40, 60), (112, 52, 76), (134, 68, 94)],
    "warped": [(36, 90, 86), (46, 112, 106), (62, 134, 124)],
    "bamboo": [(176, 156, 72), (198, 178, 88), (216, 198, 106)],
}

BARK = {
    "oak": dict(stops=[(0, (52, 40, 26)), (0.5, (86, 68, 44)), (1, (118, 96, 64))], style="furrow"),
    "spruce": dict(stops=[(0, (34, 24, 14)), (0.5, (58, 42, 26)), (1, (88, 66, 44))], style="scaly"),
    "birch": dict(stops=[(0, (180, 176, 166)), (0.5, (214, 210, 200)), (1, (232, 230, 222))], style="birch"),
    "jungle": dict(stops=[(0, (64, 48, 20)), (0.5, (92, 72, 34)), (1, (124, 102, 56))], style="streak"),
    "acacia": dict(stops=[(0, (78, 72, 64)), (0.5, (104, 98, 88)), (1, (134, 128, 116))], style="split"),
    "dark_oak": dict(stops=[(0, (30, 22, 12)), (0.5, (52, 38, 22)), (1, (78, 60, 38))], style="furrow"),
    "mangrove": dict(stops=[(0, (64, 40, 28)), (0.5, (90, 60, 42)), (1, (116, 82, 60))], style="streak"),
    "cherry": dict(stops=[(0, (36, 20, 24)), (0.5, (58, 36, 40)), (1, (86, 58, 62))], style="lenticel"),
    "pale_oak": dict(stops=[(0, (92, 86, 82)), (0.5, (124, 118, 114)), (1, (156, 150, 146))], style="furrow"),
    "crimson": dict(stops=[(0, (60, 18, 30)), (0.5, (96, 28, 46)), (1, (130, 44, 60))], style="streak"),
    "warped": dict(stops=[(0, (24, 52, 56)), (0.5, (40, 84, 86)), (1, (60, 112, 108))], style="streak"),
}


def grain_at(a, b, seed, rings=12.0, warp=0.4):
    """Flat-sawn grain sampled at arbitrary coordinates (a along, b across).
    Periodic in both a and b over [0, 1)."""
    wv = fbm(a, b, 2, 4, seed=nz.sub(seed, "gw"), period_y=4) - 0.5
    t = b * rings + wv * warp * 3.0
    t = t + (fbm(a, b, 1, 3, seed=nz.sub(seed, "gw2"), period_y=2) - 0.5) * 1.5
    band = 0.5 + 0.5 * np.cos(t * 2 * np.pi)
    late = smoothstep(0.62, 0.98, band)
    pores = fbm(a, b, 2, 4, seed=nz.sub(seed, "p"), period_y=40)
    g = 0.5 * band + 0.3 * late + 0.35 * (pores - 0.5)
    return np.clip(g, 0, 1), late


def planks(ctx, seed, species, boards=4):
    x, y = ctx.x, ctx.y
    W = ctx.w
    px = ctx.px
    dark, mid, light = WOOD[species]
    stops = [(0, dark), (0.55, mid), (1, light)]
    row = np.floor(y * boards).astype(int)
    v = y * boards - row
    joints = np.array([0.25, 0.75, 0.0, 0.5])
    u = (x - joints[row % 4]) % 1.0
    r = nz.rng(nz.sub(seed, "boards")).random(boards * 4)
    gfield = np.zeros_like(x)
    lfield = np.zeros_like(x)
    for k in range(boards):
        a = (u * 0.5 + r[k]) % 1.0
        b = (v * 0.25 + r[k + boards]) % 1.0
        g, late = grain_at(a, b, nz.sub(seed, k), rings=10 + 6 * r[k + 2 * boards])
        sel = row == k
        gfield = np.where(sel, g, gfield)
        lfield = np.where(sel, late, lfield)
    tone = r[row % boards]
    col = ramp(gfield * 0.75 + tone * 0.25, stops)
    col = col * (0.92 + 0.12 * tone[..., None])
    du = np.minimum(u, 1 - u) * W
    dv = np.minimum(v, 1 - v) * (W / boards)
    gap = 1 - smoothstep(0.3 * px, 0.75 * px, np.minimum(du, dv))
    edge = smoothstep(0.3 * px, 1.6 * px, np.minimum(du, dv))
    col = col * (1 - gap[..., None] * 0.55) * (0.9 + 0.1 * edge[..., None])
    cup = 1 - (2 * v - 1) ** 2                      # boards cup slightly
    h = 0.35 + 0.25 * edge + 0.15 * cup + 0.12 * lfield + 0.08 * gfield - 0.35 * gap
    rough = 0.78 - 0.12 * lfield + gap * 0.15
    col = hue_jitter(col, 0.04, seed, ctx)
    col = np.clip(col + grain_noise(ctx, seed, 0.02)[..., None], 0, 1)
    return Material(col, np.clip(h, 0, 1), rough, depth=2.6, ao=0.35)


def bark(ctx, seed, species):
    x, y = ctx.x, ctx.y
    spec = BARK[species]
    style = spec["style"]
    n = fbm(x, y, 4, 5, seed=seed)
    if style == "furrow":
        wx = (fbm(x, y, 2, 3, seed=nz.sub(seed, "w"), period_y=1) - 0.5) * 0.15
        rid = ridged(x + wx, y, 6, 4, seed=nz.sub(seed, "r"), period_y=1)
        cross = smoothstep(0.85, 0.95, ridged(x, y, 2, 3, seed=nz.sub(seed, "c"), period_y=6))
        h = nz.norm01(0.6 * (1 - rid) + 0.3 * n - 0.25 * cross)
    elif style == "scaly":
        w = worley(x, y, 9, seed=nz.sub(seed, "s"), jitter=0.9, cells_y=4, stretch=(1.0, 0.45))
        plate = smoothstep(0.0, 0.12, w["edge"]) * (0.7 + 0.3 * w["rnd"])
        flake = fbm(x, y, 12, 3, seed=nz.sub(seed, "fl"), period_y=4)
        h = nz.norm01(0.45 * plate + 0.3 * n + 0.25 * flake)
    elif style == "birch":
        h = nz.norm01(0.7 * n + 0.3 * fbm(x, y, 8, 3, seed=nz.sub(seed, "b"), period_y=2))
    elif style == "streak":
        st = fbm(x, y, 16, 3, seed=nz.sub(seed, "st"), period_y=1)
        h = nz.norm01(0.6 * st + 0.4 * n)
    elif style == "split":
        wx = (fbm(x, y, 2, 3, seed=nz.sub(seed, "w"), period_y=1) - 0.5) * 0.1
        rid = ridged(x + wx, y, 4, 3, seed=nz.sub(seed, "r"), period_y=1)
        h = nz.norm01(0.5 * (1 - smoothstep(0.8, 0.95, rid)) + 0.5 * n)
    elif style == "lenticel":
        h = nz.norm01(0.6 * n + 0.4 * fbm(x, y, 3, 3, seed=nz.sub(seed, "l"), period_y=10))
    else:
        h = n
    col = ramp(0.7 * h + 0.3 * n, spec["stops"])
    rough = 0.9
    if style == "birch":
        # Dark horizontal lenticels and blotches on pale bark.
        len_ = fbm(x, y, 3, 3, seed=nz.sub(seed, "len"), period_y=14)
        marks = smoothstep(0.66, 0.74, len_)
        blot = smoothstep(0.7, 0.78, fbm(x, y, 3, 4, seed=nz.sub(seed, "blot")))
        dm = np.clip(marks + blot, 0, 1)
        col = mix(col, rgb((44, 40, 36))[None, None, :] * (0.8 + 0.4 * n[..., None]), dm)
        h = np.clip(h - dm * 0.3, 0, 1)
        rough = 0.75 + 0.2 * dm
    if style == "lenticel":
        len_ = fbm(x, y, 4, 3, seed=nz.sub(seed, "len"), period_y=16)
        marks = smoothstep(0.68, 0.75, len_)
        col = mix(col, rgb((120, 96, 92))[None, None, :], marks * 0.6)
        h = np.clip(h + marks * 0.2, 0, 1)
        rough = 0.6 + 0.3 * (1 - marks)
    if species == "jungle":
        moss = smoothstep(0.62, 0.75, fbm(x, y, 3, 4, seed=nz.sub(seed, "moss")))
        col = mix(col, rgb((70, 96, 34))[None, None, :], moss * 0.55)
    col = hue_jitter(col, 0.04, seed, ctx)
    col = np.clip(col + grain_noise(ctx, seed, 0.03)[..., None], 0, 1)
    return Material(col, h, rough, depth=3.4, ao=0.55)


def log_end(ctx, seed, species, stripped=False):
    x, y = ctx.x, ctx.y
    px = ctx.px
    dark, mid, light = WOOD[species]
    wx = (fbm(x, y, 2, 4, seed=nz.sub(seed, "wx")) - 0.5) * 0.05
    wy = (fbm(x, y, 2, 4, seed=nz.sub(seed, "wy")) - 0.5) * 0.05
    cx, cy = 0.5 + (nz.rng(seed).random() - 0.5) * 0.06, 0.5 + (nz.rng(seed + 1).random() - 0.5) * 0.06
    r = np.sqrt((x - cx + wx) ** 2 + (y - cy + wy) ** 2)
    # Square-ish outline: blocks are square, so the bark ring hugs the border.
    sq = np.maximum(np.abs(x - 0.5), np.abs(y - 0.5))
    rr = 0.55 * r + 0.45 * sq
    rings = 0.5 + 0.5 * np.cos(rr * 2 * np.pi * 9)
    late = smoothstep(0.7, 0.98, rings)
    ang = np.arctan2(y - cy, x - cx)
    radial = perlin(np.cos(ang) * 0.5 + 0.5, np.sin(ang) * 0.5 + 0.5, 12, seed=nz.sub(seed, "rad"))
    checks = smoothstep(0.42, 0.5, np.abs(radial)) * smoothstep(0.08, 0.3, rr)
    tone = 0.6 * rings + 0.25 * fbm(x, y, 6, 3, seed=nz.sub(seed, "t")) + 0.15 * (1 - rr * 2)
    col = ramp(tone, [(0, dark), (0.55, mid), (1, light)])
    col = col * (1 - late[..., None] * 0.18)
    h = 0.55 + 0.1 * late - checks * 0.4
    col = col * (1 - checks[..., None] * 0.5)
    rough = 0.82 - 0.1 * late
    ring_w = 1.6 / 16
    outer = sq > 0.5 - ring_w
    if stripped:
        sap = smoothstep(0.5 - ring_w - 0.02, 0.5 - ring_w + 0.01, sq)
        col = mix(col, ramp(fbm(x, y, 8, 3, seed=nz.sub(seed, "sap")), [(0, mid), (1, light)]), sap * 0.8)
        h = h * (1 - sap * 0.2) + sap * 0.1
    else:
        bk = bark(ctx, nz.sub(seed, "bark"), species)
        col = np.where(outer[..., None], bk.albedo, col)
        h = np.where(outer, 0.7 + 0.3 * bk.height, h)
        rough = np.where(outer, 0.92, rough)
        # Thin cambium line between bark and wood.
        line = np.exp(-(((sq - (0.5 - ring_w)) * 16) / 0.35) ** 2)
        col = col * (1 - line[..., None] * 0.35)
    col = np.clip(col + grain_noise(ctx, seed, 0.02)[..., None], 0, 1)
    return Material(col, np.clip(h, 0, 1), rough, depth=2.8, ao=0.4)


def stripped_side(ctx, seed, species):
    x, y = ctx.x, ctx.y
    dark, mid, light = WOOD[species]
    g, late = grain_at(y, x, nz.sub(seed, "s"), rings=7)
    fib = fbm(x, y, 20, 3, seed=nz.sub(seed, "fib"), period_y=2)
    col = ramp(0.7 * g + 0.3 * fib, [(0, dark), (0.5, mid), (1, light)])
    col = col * (1.02 + 0.08 * fib[..., None])
    h = nz.norm01(0.5 * g + 0.3 * fib + 0.2 * late)
    col = np.clip(col + grain_noise(ctx, seed, 0.02)[..., None], 0, 1)
    return Material(np.clip(col, 0, 1), h, 0.7 - 0.1 * late, depth=2.2, ao=0.3)


PLANKS = {
    "oak": "planks_oak", "spruce": "planks_spruce", "birch": "planks_birch",
    "jungle": "planks_jungle", "acacia": "planks_acacia", "dark_oak": "planks_big_oak",
    "mangrove": "mangrove_planks", "cherry": "cherry_planks", "pale_oak": "pale_oak_planks",
    "crimson": "huge_fungus/crimson_planks", "warped": "huge_fungus/warped_planks",
    "bamboo": "bamboo_planks",
}

LOGS = {
    "oak": ("log_oak", "log_oak_top"),
    "spruce": ("log_spruce", "log_spruce_top"),
    "birch": ("log_birch", "log_birch_top"),
    "jungle": ("log_jungle", "log_jungle_top"),
    "acacia": ("log_acacia", "log_acacia_top"),
    "dark_oak": ("log_big_oak", "log_big_oak_top"),
    "mangrove": ("mangrove_log_side", "mangrove_log_top"),
    "cherry": ("cherry_log_side", "cherry_log_top"),
    "pale_oak": ("pale_oak_log_side", "pale_oak_log_top"),
}
# Crimson/warped stem sides are animated in vanilla; only their ends are replaced.
STEM_TOPS = {"crimson": "huge_fungus/crimson_log_top", "warped": "huge_fungus/warped_stem_top"}

STRIPPED = {
    "oak": ("stripped_oak_log", "stripped_oak_log_top"),
    "spruce": ("stripped_spruce_log", "stripped_spruce_log_top"),
    "birch": ("stripped_birch_log", "stripped_birch_log_top"),
    "jungle": ("stripped_jungle_log", "stripped_jungle_log_top"),
    "acacia": ("stripped_acacia_log", "stripped_acacia_log_top"),
    "dark_oak": ("stripped_dark_oak_log", "stripped_dark_oak_log_top"),
    "mangrove": ("stripped_mangrove_log_side", "stripped_mangrove_log_top"),
    "cherry": ("stripped_cherry_log_side", "stripped_cherry_log_top"),
    "pale_oak": ("stripped_pale_oak_log_side", "stripped_pale_oak_log_top"),
    "crimson": ("huge_fungus/stripped_crimson_stem_side", "huge_fungus/stripped_crimson_stem_top"),
    "warped": ("huge_fungus/stripped_warped_stem_side", "huge_fungus/stripped_warped_stem_top"),
}


def _bind(fn, *a, **kw):
    return lambda ctx, seed: fn(ctx, seed, *a, **kw)


for sp, name in PLANKS.items():
    add(name, _bind(planks, sp))
for sp, (side, top) in LOGS.items():
    add(side, _bind(bark, sp))
    add(top, _bind(log_end, sp))
for sp, top in STEM_TOPS.items():
    add(top, _bind(log_end, sp))
for sp, (side, top) in STRIPPED.items():
    add(side, _bind(stripped_side, sp))
    add(top, _bind(log_end, sp, stripped=True))
