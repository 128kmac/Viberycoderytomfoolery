"""Bricks, quartz, prismarine, dyed blocks, glass, nether and end blocks."""

from __future__ import annotations

import numpy as np

from .. import noise as nz
from ..lib import (bricks, frame_border, grain_noise, mix, rgb, strata)
from ..noise import fbm, ramp, ridged, smoothstep, worley
from ..pbr import Material
from ..registry import add, tex
from .terrain import masonry, polished, stone_like

DYES = ["white", "orange", "magenta", "light_blue", "yellow", "lime", "pink", "gray",
        "silver", "cyan", "purple", "blue", "brown", "green", "red", "black"]

CONCRETE = {
    "white": (207, 213, 214), "orange": (224, 97, 1), "magenta": (169, 48, 159),
    "light_blue": (36, 137, 199), "yellow": (241, 175, 21), "lime": (94, 169, 24),
    "pink": (214, 101, 143), "gray": (55, 58, 62), "silver": (125, 125, 115),
    "cyan": (21, 119, 136), "purple": (100, 32, 156), "blue": (45, 47, 143),
    "brown": (96, 60, 32), "green": (73, 91, 36), "red": (142, 33, 33), "black": (8, 10, 15),
}
WOOL = {
    "white": (234, 236, 237), "orange": (241, 118, 20), "magenta": (190, 69, 180),
    "light_blue": (58, 175, 217), "yellow": (249, 198, 40), "lime": (112, 185, 26),
    "pink": (238, 141, 172), "gray": (63, 68, 72), "silver": (142, 142, 135),
    "cyan": (21, 138, 145), "purple": (122, 42, 173), "blue": (53, 57, 157),
    "brown": (114, 72, 41), "green": (85, 110, 28), "red": (161, 39, 35), "black": (21, 21, 26),
}
TERRACOTTA = {
    "white": (210, 178, 161), "orange": (162, 84, 38), "magenta": (150, 88, 109),
    "light_blue": (113, 109, 138), "yellow": (186, 133, 35), "lime": (104, 118, 53),
    "pink": (162, 78, 79), "gray": (58, 42, 36), "silver": (135, 107, 98),
    "cyan": (87, 91, 91), "purple": (118, 70, 86), "blue": (74, 60, 91),
    "brown": (77, 51, 36), "green": (76, 83, 42), "red": (143, 61, 47), "black": (37, 23, 16),
}
GLASS = {
    "white": (255, 255, 255), "orange": (216, 127, 51), "magenta": (178, 76, 216),
    "light_blue": (102, 153, 216), "yellow": (229, 229, 51), "lime": (127, 204, 25),
    "pink": (242, 127, 165), "gray": (76, 76, 76), "silver": (153, 153, 153),
    "cyan": (76, 127, 153), "purple": (127, 63, 178), "blue": (51, 76, 178),
    "brown": (102, 76, 51), "green": (102, 127, 51), "red": (153, 51, 51), "black": (25, 25, 25),
}


def _bind(fn, *a, **kw):
    return lambda ctx, seed: fn(ctx, seed, *a, **kw)


def tone_stops(c, lo=0.82, hi=1.12):
    c = np.array(c, dtype=float)
    return [(0, tuple(np.clip(c * lo, 0, 255))), (0.55, tuple(c)), (1, tuple(np.clip(c * hi, 0, 255)))]


# --------------------------------------------------------------------------
# Dyed families
# --------------------------------------------------------------------------

def concrete(ctx, seed, c):
    x, y = ctx.x, ctx.y
    n = fbm(x, y, 4, 5, seed=seed)
    w = worley(x, y, 20, seed=nz.sub(seed, "pits"))
    pits = np.where(w["rnd"] > 0.8, smoothstep(0.3, 0.1, w["f1"]), 0)
    col = ramp(n, tone_stops(c, 0.94, 1.05))
    col = col * (1 - pits[..., None] * 0.15)
    h = 0.6 + 0.2 * n - 0.4 * pits
    col = np.clip(col + grain_noise(ctx, seed, 0.015)[..., None], 0, 1)
    return Material(col, h, 0.52 + 0.12 * n + 0.2 * pits, depth=1.4, ao=0.2)


def concrete_powder(ctx, seed, c):
    x, y = ctx.x, ctx.y
    W = ctx.w
    r = nz.rng(nz.sub(seed, "g"))
    g = nz.blur(r.random((W, W)), 1, 1) * 0.6 + r.random((W, W)) * 0.4
    n = fbm(x, y, 4, 4, seed=seed)
    col = ramp(0.5 * g + 0.5 * n, tone_stops(np.array(c) * 1.05 + 12, 0.85, 1.1))
    return Material(np.clip(col, 0, 1), nz.norm01(0.6 * g + 0.4 * n), 0.96, depth=1.8, ao=0.35)


def wool(ctx, seed, c):
    x, y = ctx.x, ctx.y
    wx = (fbm(x, y, 4, 3, seed=nz.sub(seed, "a")) - 0.5) * 0.08
    wy = (fbm(x, y, 4, 3, seed=nz.sub(seed, "b")) - 0.5) * 0.08
    fib = ridged(x + wx, y + wy, 10, 3, seed=nz.sub(seed, "fib"))
    fib2 = ridged(x - wy, y + wx, 14, 2, seed=nz.sub(seed, "fib2"))
    felt = fbm(x, y, 6, 4, seed=seed)
    h = nz.norm01(0.4 * fib + 0.25 * fib2 + 0.35 * felt)
    col = ramp(0.6 * h + 0.4 * felt, tone_stops(c, 0.78, 1.08))
    return Material(np.clip(col, 0, 1), h, 0.98, sss=0.22, depth=2.4, ao=0.5)


def terracotta(ctx, seed, c):
    x, y = ctx.x, ctx.y
    n = fbm(x, y, 3, 6, seed=seed)
    lay, band = strata(ctx, nz.sub(seed, "s"), bands=5, wobble=0.08, sharp=0.2)
    sp = smoothstep(0.82, 0.92, fbm(x, y, 20, 2, seed=nz.sub(seed, "sp")))
    col = ramp(0.7 * n + 0.3 * band, tone_stops(c, 0.88, 1.08))
    col = col * (1 - sp[..., None] * 0.12)
    h = nz.norm01(0.7 * n + 0.3 * band - 0.2 * sp)
    col = np.clip(col + grain_noise(ctx, seed, 0.02)[..., None], 0, 1)
    return Material(col, h, 0.82, depth=1.6, ao=0.25)


for d in DYES:
    add(f"concrete_{d}", _bind(concrete, CONCRETE[d]))
    add(f"concrete_powder_{d}", _bind(concrete_powder, CONCRETE[d]))
    add(f"wool_colored_{d}", _bind(wool, WOOL[d]))
    add(f"hardened_clay_stained_{d}", _bind(terracotta, TERRACOTTA[d]))
add("hardened_clay", _bind(terracotta, (152, 94, 68)))


# --------------------------------------------------------------------------
# Glass
# --------------------------------------------------------------------------

def glass(ctx, seed, tint=None, interior_alpha=0.06, tinted=False):
    x, y = ctx.x, ctx.y
    d = frame_border(ctx, 1)
    frame = 1 - smoothstep(0.9, 1.1, d)
    streak = smoothstep(0.55, 0.9, fbm(x, y, 2, 3, seed=nz.sub(seed, "st"), period_y=1)) * \
        smoothstep(0.6, 0.0, np.abs(((x + y) * 3) % 1 - 0.5) * 2)
    smudge = fbm(x, y, 4, 4, seed=nz.sub(seed, "sm"))
    base = np.array([226, 238, 244], dtype=float) if tint is None else np.array(tint, dtype=float)
    fcol = (np.array([196, 222, 230]) if tint is None else base * 0.85) / 255.0
    col = np.broadcast_to(base / 255.0, x.shape + (3,)).copy()
    col = mix(col, np.ones(3)[None, None, :], streak * 0.5)
    col = mix(col, np.broadcast_to(fcol, col.shape), frame)
    if tinted:
        col = col * 0.35
    ia = interior_alpha + streak * 0.18 + (smudge - 0.5) * 0.03
    alpha = np.clip(np.where(frame > 0.5, 0.92, ia), 0, 1)
    h = 0.5 + 0.35 * frame + 0.05 * smudge
    rough = np.where(frame > 0.5, 0.18, 0.02 + 0.06 * smoothstep(0.6, 0.8, smudge))
    return Material(np.clip(col, 0, 1), h, rough, alpha=alpha, depth=2.0, ao=0.0)


def pane_edge(ctx, seed, tint=None):
    x, y = ctx.x, ctx.y
    base = np.array([196, 222, 230], dtype=float) if tint is None else np.array(tint, dtype=float) * 0.85
    n = fbm(x, y, 2, 3, seed=seed, period_y=8)
    col = np.broadcast_to(base / 255.0, x.shape + (3,)) * (0.9 + 0.2 * n[..., None])
    return Material(np.clip(col, 0, 1), 0.5 + 0.1 * n, 0.15, depth=1.0, ao=0.0)


add("glass", _bind(glass), tags=("nocal",))
add("glass_pane_top", _bind(pane_edge))
add("tinted_glass", _bind(glass, tint=(70, 58, 84), interior_alpha=0.55, tinted=True), tags=("nocal",))
for d in DYES:
    add(f"glass_{d}", _bind(glass, tint=GLASS[d], interior_alpha=0.42), tags=("nocal",))
    add(f"glass_pane_top_{d}", _bind(pane_edge, tint=GLASS[d]))


# --------------------------------------------------------------------------
# Clay bricks, quartz, prismarine
# --------------------------------------------------------------------------

@tex("brick")
def brick(ctx, seed):
    m = masonry(ctx, seed, [(0, (122, 58, 44)), (0.4, (146, 72, 54)), (0.75, (162, 88, 68)), (1, (178, 108, 86))],
                4, 2, offset=0.5, mortar=1.2, mortar_col=(150, 140, 128), bev=1.0, rough=0.86,
                per_brick=0.6, chip=0.8, surface_period=8)
    # Burnt (clinker) bricks are darker and slightly glossy.
    x, y = ctx.x, ctx.y
    b = bricks(ctx, 4, 2, offset=0.5, mortar=1.2, seed=seed, chip=0.8)
    clink = (b["rnd"] > 0.82).astype(float) * b["inside"]
    m.albedo = m.albedo * (1 - clink[..., None] * 0.3)
    m.rough = np.where(clink > 0.5, 0.6, m.rough)
    return m


@tex("mud_bricks")
def mud_bricks(ctx, seed):
    return masonry(ctx, seed, [(0, (120, 92, 66)), (0.5, (140, 108, 80)), (1, (160, 126, 96))],
                   4, 2, offset=0.5, mortar=1.0, mortar_col=(96, 72, 52), bev=0.9, rough=0.92, chip=0.9)


QUARTZ = [(0, (222, 214, 206)), (0.6, (234, 228, 222)), (1, (244, 240, 236))]


def quartz(ctx, seed, kind="side"):
    x, y = ctx.x, ctx.y
    n = fbm(x, y, 3, 6, seed=seed)
    wx = (fbm(x, y, 2, 4, seed=nz.sub(seed, "w")) - 0.5) * 0.4
    vein = smoothstep(0.92, 0.99, ridged(x + wx, y - wx, 2, 4, seed=nz.sub(seed, "v")))
    col = ramp(n, QUARTZ)
    col = col * (1 - vein[..., None] * 0.12)
    d = frame_border(ctx, 1)
    if kind in ("side", "top"):
        edge = smoothstep(0.0, 0.8, d)
    else:
        edge = np.ones_like(d)
    h = 0.15 * n + 0.85 * edge
    col = col * (0.9 + 0.1 * edge[..., None])
    return Material(np.clip(col, 0, 1), h, 0.12 + 0.1 * (1 - n) + 0.3 * (1 - edge), sss=0.05, depth=1.8, ao=0.15)


add("quartz_block_side", _bind(quartz, kind="side"))
add("quartz_block_top", _bind(quartz, kind="top"))
add("quartz_block_bottom", _bind(quartz, kind="bottom"))


@tex("quartz_block_lines")
def quartz_lines(ctx, seed):
    x, y = ctx.x, ctx.y
    m = quartz(ctx, seed, kind="bottom")
    fl = np.cos(x * 2 * np.pi * 4) * 0.5 + 0.5
    m.height = 0.4 + 0.6 * fl
    m.albedo = m.albedo * (0.92 + 0.08 * fl[..., None])
    return m


@tex("quartz_block_lines_top")
def quartz_lines_top(ctx, seed):
    return quartz(ctx, seed, kind="top")


@tex("quartz_bricks")
def quartz_bricks(ctx, seed):
    return masonry(ctx, seed, QUARTZ, 4, 2, offset=0.5, mortar=0.8, mortar_col=(196, 188, 180), bev=0.8,
                   polish=0.15, chip=0.3)


@tex("prismarine_rough", frames=4)
def prismarine_rough(ctx, seed):
    x, y = ctx.x, ctx.y
    base = stone_like(ctx, seed, [(0, (70, 120, 112)), (0.5, (100, 156, 148)), (1, (130, 184, 170))],
                      period=4, crack=0.25, depth=2.8)
    # Prismarine slowly shifts hue; vanilla cycles four frames.
    shifts = [(1.0, 1.0, 1.0), (0.92, 1.0, 1.08), (1.06, 1.02, 0.92), (0.9, 0.96, 1.12)]
    alb = np.concatenate([np.clip(base.albedo * np.array(s)[None, None, :], 0, 1) for s in shifts], axis=0)
    h = np.concatenate([base.height] * 4, axis=0)
    rough = np.concatenate([np.asarray(base.rough) * np.ones_like(base.height)] * 4, axis=0)
    return Material(alb, h, rough * 0.8, depth=2.8)


@tex("prismarine_bricks")
def prismarine_bricks(ctx, seed):
    return masonry(ctx, seed, [(0, (78, 140, 126)), (0.5, (98, 164, 148)), (1, (122, 186, 168))],
                   4, 2, offset=0.5, mortar=1.0, mortar_col=(52, 92, 86), bev=0.9, polish=0.35)


@tex("prismarine_dark")
def prismarine_dark(ctx, seed):
    m = masonry(ctx, seed, [(0, (34, 70, 56)), (0.5, (48, 90, 74)), (1, (62, 108, 90))],
                2, 2, offset=0.0, mortar=1.4, mortar_col=(22, 46, 38), bev=1.2, polish=0.3)
    return m


# --------------------------------------------------------------------------
# Nether
# --------------------------------------------------------------------------

@tex("netherrack")
def netherrack(ctx, seed):
    x, y = ctx.x, ctx.y
    w = worley(x, y, 8, seed=seed, jitter=1.0)
    n = fbm(x, y, 4, 6, seed=nz.sub(seed, "n"))
    lump = smoothstep(0.0, 0.4, w["edge"]) * (0.5 + 0.5 * w["rnd"])
    pores = smoothstep(0.75, 0.88, fbm(x, y, 16, 2, seed=nz.sub(seed, "p")))
    h = nz.norm01(0.5 * lump + 0.4 * n - 0.3 * pores)
    col = ramp(0.5 * h + 0.5 * n, [(0, (70, 18, 18)), (0.4, (104, 30, 30)), (0.75, (132, 46, 44)), (1, (156, 66, 60))])
    col = col * (1 - pores[..., None] * 0.35)
    col = np.clip(col + grain_noise(ctx, seed, 0.03)[..., None], 0, 1)
    return Material(col, h, 0.88, depth=3.0, ao=0.5)


NBRICK = [(0, (36, 16, 20)), (0.5, (50, 24, 28)), (1, (68, 34, 38))]


@tex("nether_brick")
def nether_brick(ctx, seed):
    return masonry(ctx, seed, NBRICK, 4, 2, offset=0.5, mortar=1.0, mortar_col=(20, 10, 12), bev=0.9, rough=0.8)


@tex("cracked_nether_bricks")
def cracked_nether_bricks(ctx, seed):
    return masonry(ctx, seed, NBRICK, 4, 2, offset=0.5, mortar=1.0, mortar_col=(20, 10, 12), bev=0.9,
                   rough=0.82, cracked=1.0)


@tex("red_nether_brick")
def red_nether_brick(ctx, seed):
    return masonry(ctx, seed, [(0, (76, 8, 10)), (0.5, (98, 14, 16)), (1, (120, 24, 24))],
                   4, 2, offset=0.5, mortar=1.0, mortar_col=(40, 4, 6), bev=0.9, rough=0.8)


def wart(ctx, seed, stops):
    x, y = ctx.x, ctx.y
    w = worley(x, y, 10, seed=seed, jitter=1.0)
    n = fbm(x, y, 6, 4, seed=nz.sub(seed, "n"))
    nod = smoothstep(0.9, 0.2, w["f1"])
    h = nz.norm01(0.6 * nod + 0.4 * n)
    col = ramp(0.6 * h + 0.4 * w["rnd"], stops)
    return Material(col, h, 0.55 + 0.3 * (1 - h), sss=0.35, depth=2.8, ao=0.5)


add("nether_wart_block", _bind(wart, [(0, (90, 4, 6)), (0.5, (122, 10, 12)), (1, (160, 30, 26))]))
add("warped_wart_block", _bind(wart, [(0, (14, 96, 92)), (0.5, (22, 120, 116)), (1, (40, 150, 140))]))


def nylium_top(ctx, seed, stops):
    x, y = ctx.x, ctx.y
    m = wart(ctx, seed, stops)
    fz = fbm(x, y, 24, 3, seed=nz.sub(seed, "fz"))
    m.height = nz.norm01(m.height * 0.6 + fz * 0.4)
    m.rough = 0.9
    return m


def nylium_side(ctx, seed, stops):
    from .earth import top_band
    rack = netherrack(ctx, nz.sub(seed, "rack"))
    top = nylium_top(ctx, nz.sub(seed, "top"), stops)
    band = top_band(ctx, seed, depth_vpx=3.5, drips=10, drip_len=4.0)
    return Material(mix(rack.albedo, top.albedo, band), np.where(band > 0.5, 0.6 + 0.4 * top.height, rack.height * 0.85),
                    np.where(band > 0.5, 0.9, 0.88), sss=band * 0.3, depth=3.0, ao=0.5)


CRIMSON_N = [(0, (100, 10, 14)), (0.5, (132, 20, 20)), (1, (168, 40, 34))]
WARPED_N = [(0, (20, 92, 80)), (0.5, (30, 118, 104)), (1, (46, 146, 124))]
add("crimson_nylium_top", _bind(nylium_top, CRIMSON_N))
add("crimson_nylium_side", _bind(nylium_side, CRIMSON_N))
add("warped_nylium_top", _bind(nylium_top, WARPED_N))
add("warped_nylium_side", _bind(nylium_side, WARPED_N))


@tex("soul_sand")
def soul_sand(ctx, seed):
    x, y = ctx.x, ctx.y
    W = ctx.w
    r = nz.rng(nz.sub(seed, "g"))
    g = nz.blur(r.random((W, W)), 1, 1)
    n = fbm(x, y, 4, 5, seed=seed)
    # Faint anguished faces: pairs of dark sockets above a mouth hollow.
    faces = np.zeros_like(x)
    for k in range(3):
        cx, cy = r.random(), r.random()
        dx = (x - cx + 0.5) % 1 - 0.5
        dy = (y - cy + 0.5) % 1 - 0.5
        eyes = np.exp(-(((np.abs(dx) - 0.07) / 0.03) ** 2 + ((dy + 0.03) / 0.03) ** 2))
        mouth = np.exp(-((dx / 0.05) ** 2 + ((dy - 0.07) / 0.04) ** 2))
        faces = np.maximum(faces, np.clip(eyes + mouth, 0, 1))
    h = nz.norm01(0.5 * n + 0.3 * g - 0.5 * faces)
    col = ramp(0.6 * n + 0.4 * g, [(0, (60, 44, 34)), (0.5, (84, 64, 50)), (1, (108, 84, 66))])
    col = col * (1 - faces[..., None] * 0.45)
    return Material(col, h, 0.95, depth=2.6, ao=0.5)


@tex("soul_soil")
def soul_soil(ctx, seed):
    from .earth import dirt_mat
    return dirt_mat(ctx, seed, stops=[(0, (54, 40, 30)), (0.5, (76, 58, 44)), (1, (98, 78, 62))], stones=0.15)


@tex("ancient_debris_side")
def ancient_debris_side(ctx, seed):
    x, y = ctx.x, ctx.y
    lay, band = strata(ctx, seed, bands=5, wobble=0.15, sharp=0.6)
    n = fbm(x, y, 4, 5, seed=nz.sub(seed, "n"))
    rid = ridged(x, y, 4, 3, seed=nz.sub(seed, "r"))
    col = ramp(0.5 * band + 0.5 * n, [(0, (50, 34, 30)), (0.5, (86, 62, 54)), (1, (120, 92, 80))])
    metal = smoothstep(0.8, 0.92, rid)
    col = mix(col, rgb((110, 92, 96))[None, None, :], metal * 0.7)
    h = nz.norm01(0.4 * lay + 0.4 * n + 0.3 * metal)
    return Material(col, h, 0.8 - metal * 0.4, metal=metal * 0.9, depth=3.0, ao=0.5)


@tex("ancient_debris_top")
def ancient_debris_top(ctx, seed):
    x, y = ctx.x, ctx.y
    r = np.sqrt((x - 0.5) ** 2 + (y - 0.5) ** 2)
    rings = 0.5 + 0.5 * np.cos(r * 2 * np.pi * 6 + fbm(x, y, 3, 3, seed=seed) * 3)
    n = fbm(x, y, 4, 5, seed=nz.sub(seed, "n"))
    col = ramp(0.6 * rings + 0.4 * n, [(0, (58, 40, 36)), (0.5, (92, 66, 58)), (1, (126, 98, 86))])
    metal = smoothstep(0.85, 0.95, rings) * smoothstep(0.4, 0.6, n)
    h = nz.norm01(0.5 * rings + 0.5 * n)
    return Material(col, h, 0.75 - metal * 0.4, metal=metal * 0.9, depth=2.6, ao=0.4)


# --------------------------------------------------------------------------
# End
# --------------------------------------------------------------------------

@tex("end_stone")
def end_stone(ctx, seed):
    x, y = ctx.x, ctx.y
    w = worley(x, y, 12, seed=nz.sub(seed, "p"), jitter=1.0)
    pits = np.where(w["rnd"] > 0.6, smoothstep(0.35, 0.1, w["f1"]), 0)
    m = stone_like(ctx, seed, [(0, (196, 192, 140)), (0.5, (218, 216, 160)), (1, (232, 232, 178))],
                   period=4, crack=0.12, depth=2.6)
    m.height = np.clip(m.height - pits * 0.5, 0, 1)
    m.albedo = m.albedo * (1 - pits[..., None] * 0.25)
    return m


@tex("end_bricks")
def end_bricks(ctx, seed):
    return masonry(ctx, seed, [(0, (204, 202, 148)), (0.5, (222, 220, 166)), (1, (236, 236, 184))],
                   4, 2, offset=0.5, mortar=1.0, mortar_col=(160, 156, 110), bev=0.9, rough=0.8)


PURPUR = [(0, (148, 98, 148)), (0.5, (168, 120, 168)), (1, (188, 142, 188))]


@tex("purpur_block")
def purpur_block(ctx, seed):
    return masonry(ctx, seed, PURPUR, 4, 4, offset=0.0, mortar=0.8, mortar_col=(110, 70, 110), bev=0.7,
                   polish=0.4, chip=0.2)


@tex("purpur_pillar")
def purpur_pillar(ctx, seed):
    x, y = ctx.x, ctx.y
    m = polished(ctx, seed, PURPUR, rough=0.4)
    fl = 0.5 + 0.5 * np.cos(x * 2 * np.pi * 3)
    m.height = 0.4 + 0.6 * fl
    m.albedo = m.albedo * (0.9 + 0.1 * fl[..., None])
    return m


@tex("purpur_pillar_top")
def purpur_pillar_top(ctx, seed):
    x, y = ctx.x, ctx.y
    m = polished(ctx, seed, PURPUR, rough=0.4)
    sq = np.maximum(np.abs(x - 0.5), np.abs(y - 0.5)) * 16
    groove = np.exp(-((sq - 5.0) / 0.5) ** 2)
    m.height = np.clip(m.height - groove * 0.5, 0, 1)
    return m


# --------------------------------------------------------------------------
# Organic blocks
# --------------------------------------------------------------------------

@tex("hay_block_side")
def hay_side(ctx, seed):
    x, y = ctx.x, ctx.y
    straw = fbm(x, y, 24, 3, seed=seed, period_y=2)
    rid = ridged(x, y, 16, 2, seed=nz.sub(seed, "r"), period_y=1)
    band = np.exp(-(((y - 0.25) * 16) / 0.9) ** 2) + np.exp(-(((y - 0.75) * 16) / 0.9) ** 2)
    h = nz.norm01(0.5 * straw + 0.4 * rid - 0.3 * band)
    col = ramp(0.6 * straw + 0.4 * rid, [(0, (150, 112, 18)), (0.5, (186, 150, 30)), (1, (218, 186, 60))])
    col = mix(col, rgb((132, 30, 22))[None, None, :] * (0.8 + 0.4 * straw[..., None]), np.clip(band, 0, 1) * 0.85)
    return Material(col, h, 0.85, sss=0.2, depth=3.0, ao=0.5)


@tex("hay_block_top")
def hay_top(ctx, seed):
    x, y = ctx.x, ctx.y
    w = worley(x, y, 22, seed=seed, jitter=1.0)
    tube = smoothstep(0.2, 0.45, w["f1"])
    h = nz.norm01(tube + 0.3 * w["rnd"])
    col = ramp(0.5 * tube + 0.5 * w["rnd"], [(0, (110, 82, 10)), (0.5, (180, 146, 30)), (1, (214, 184, 64))])
    return Material(col, h, 0.85, sss=0.2, depth=2.4, ao=0.5)


@tex("bone_block_side")
def bone_side(ctx, seed):
    x, y = ctx.x, ctx.y
    n = fbm(x, y, 4, 5, seed=seed, period_y=1)
    pores = smoothstep(0.75, 0.88, fbm(x, y, 16, 2, seed=nz.sub(seed, "p"), period_y=4))
    col = ramp(n, [(0, (196, 190, 160)), (0.5, (220, 214, 186)), (1, (236, 232, 208))])
    col = col * (1 - pores[..., None] * 0.15)
    return Material(col, nz.norm01(0.7 * n - 0.3 * pores), 0.6, sss=0.15, depth=2.0, ao=0.3)


@tex("bone_block_top")
def bone_top(ctx, seed):
    x, y = ctx.x, ctx.y
    w = worley(x, y, 10, seed=seed)
    spongy = smoothstep(0.3, 0.1, w["f1"])
    d = frame_border(ctx, 1)
    rim = smoothstep(2.6, 1.6, d)
    n = fbm(x, y, 6, 4, seed=nz.sub(seed, "n"))
    col = ramp(n, [(0, (200, 194, 164)), (1, (232, 228, 204))])
    col = mix(col * (1 - spongy[..., None] * 0.25), rgb((226, 222, 198))[None, None, :], rim)
    h = np.where(rim > 0.5, 0.8, 0.5 - spongy * 0.3)
    return Material(col, h, 0.65, sss=0.15, depth=2.0, ao=0.35)


@tex("melon_side")
def melon_side(ctx, seed):
    x, y = ctx.x, ctx.y
    stripes = 0.5 + 0.5 * np.cos((x * 6 + (fbm(x, y, 2, 3, seed=seed, period_y=1) - 0.5) * 0.8) * 2 * np.pi)
    n = fbm(x, y, 8, 4, seed=nz.sub(seed, "n"))
    col = ramp(0.6 * stripes + 0.4 * n, [(0, (60, 96, 20)), (0.5, (96, 134, 28)), (1, (140, 168, 46))])
    return Material(col, nz.norm01(0.3 * stripes + 0.7 * n), 0.42, sss=0.2, depth=1.6, ao=0.2)


@tex("melon_top")
def melon_top(ctx, seed):
    x, y = ctx.x, ctx.y
    r = np.sqrt((x - 0.5) ** 2 + (y - 0.5) ** 2)
    ang = np.arctan2(y - 0.5, x - 0.5)
    stripes = 0.5 + 0.5 * np.cos(ang * 6)
    n = fbm(x, y, 8, 4, seed=seed)
    col = ramp(0.6 * stripes + 0.4 * n, [(0, (60, 96, 20)), (0.5, (96, 134, 28)), (1, (140, 168, 46))])
    stem = np.exp(-(r / 0.05) ** 2)
    col = mix(col, rgb((110, 90, 40))[None, None, :], stem)
    return Material(col, nz.norm01(0.3 * stripes + 0.7 * n - stem), 0.42, sss=0.2, depth=1.6, ao=0.2)


@tex("pumpkin_side")
def pumpkin_side(ctx, seed):
    x, y = ctx.x, ctx.y
    rib = np.abs(np.sin(x * np.pi * 4))
    n = fbm(x, y, 6, 4, seed=seed, period_y=2)
    col = ramp(0.5 * rib + 0.5 * n, [(0, (170, 82, 6)), (0.5, (206, 116, 20)), (1, (228, 146, 40))])
    return Material(col, nz.norm01(0.7 * rib + 0.3 * n), 0.45, sss=0.15, depth=3.0, ao=0.4)


@tex("pumpkin_top")
def pumpkin_top(ctx, seed):
    x, y = ctx.x, ctx.y
    ang = np.arctan2(y - 0.5, x - 0.5)
    r = np.sqrt((x - 0.5) ** 2 + (y - 0.5) ** 2)
    rib = np.abs(np.sin(ang * 4))
    n = fbm(x, y, 6, 4, seed=seed)
    col = ramp(0.5 * rib + 0.5 * n, [(0, (170, 82, 6)), (0.5, (206, 116, 20)), (1, (228, 146, 40))])
    stem = smoothstep(0.09, 0.06, r)
    col = mix(col, rgb((96, 82, 34))[None, None, :], stem)
    h = nz.norm01(0.5 * rib * smoothstep(0.0, 0.2, r) + 0.3 * n + stem)
    return Material(col, h, np.where(stem > 0.5, 0.8, 0.45), sss=0.15, depth=3.0, ao=0.4)


def mushroom_skin(ctx, seed, base, spots):
    x, y = ctx.x, ctx.y
    n = fbm(x, y, 5, 4, seed=seed)
    col = ramp(n, tone_stops(base, 0.85, 1.1))
    h = 0.5 + 0.3 * n
    if spots is not None:
        w = worley(x, y, 4, seed=nz.sub(seed, "sp"), jitter=0.8)
        sp = smoothstep(0.38, 0.3, w["f1"]) * (w["rnd"] > 0.25)
        col = mix(col, rgb(spots)[None, None, :] * (0.92 + 0.1 * n[..., None]), sp)
        h = h + sp * 0.25
    return Material(np.clip(col, 0, 1), h, 0.5, sss=0.3, depth=2.2, ao=0.3)


add("mushroom_block_skin_red", _bind(mushroom_skin, (182, 30, 28), (226, 220, 210)))
add("mushroom_block_skin_brown", _bind(mushroom_skin, (148, 110, 80), None))
add("mushroom_block_skin_stem", _bind(mushroom_skin, (204, 196, 180), None))


@tex("mushroom_block_inside")
def mushroom_inside(ctx, seed):
    x, y = ctx.x, ctx.y
    n = fbm(x, y, 8, 4, seed=seed)
    col = ramp(n, [(0, (196, 168, 130)), (1, (226, 204, 168))])
    return Material(col, n, 0.85, sss=0.35, depth=1.6, ao=0.3)


def sponge(ctx, seed, wet=False):
    x, y = ctx.x, ctx.y
    w = worley(x, y, 9, seed=seed)
    w2 = worley(x, y, 18, seed=nz.sub(seed, "2"))
    holes = np.maximum(smoothstep(0.35, 0.15, w["f1"]) * (w["rnd"] > 0.3), smoothstep(0.3, 0.12, w2["f1"]) * (w2["rnd"] > 0.5))
    n = fbm(x, y, 6, 4, seed=nz.sub(seed, "n"))
    base = (160, 152, 50) if wet else (196, 190, 72)
    col = ramp(n, tone_stops(base, 0.85, 1.1))
    col = col * (1 - holes[..., None] * 0.5)
    h = nz.norm01(0.6 - holes * 0.6 + n * 0.3)
    return Material(np.clip(col, 0, 1), h, 0.35 if wet else 0.95, sss=0.3, depth=3.0, ao=0.6)


add("sponge", _bind(sponge))
add("sponge_wet", _bind(sponge, wet=True))
