"""Natural terrain: stone family, deepslate, earth, grass, sand, snow, ice."""

from __future__ import annotations

import numpy as np

from .. import noise as nz
from ..lib import (bevel, bricks, frame_border, grain_noise, hue_jitter, mix,
                   pebbles, rgb, rock, strata)
from ..noise import fbm, ramp, ridged, smoothstep, worley
from ..pbr import Material
from ..registry import add, tex

GRASS_CARRIED = np.array([0.53, 0.80, 0.30])


# --------------------------------------------------------------------------
# Stone family
# --------------------------------------------------------------------------

def stone_like(ctx, seed, stops, period=4, crack=0.18, speck_col=None,
               speck_amt=0.0, rough=(0.78, 0.92), depth=2.6, jitter=0.06):
    x, y = ctx.x, ctx.y
    h, cracks = rock(ctx, seed, period=period, crack=crack)
    tone = 0.55 * fbm(x, y, 3, 5, seed=nz.sub(seed, "tone")) + 0.45 * h
    col = ramp(tone, stops)
    speck = smoothstep(0.80, 0.92, fbm(x, y, 16, 2, seed=nz.sub(seed, "sp")))
    if speck_col is not None and speck_amt > 0:
        col = mix(col, rgb(speck_col)[None, None, :], speck * speck_amt)
    col = col * (1 - cracks[..., None] * 0.30)
    col = hue_jitter(col, jitter, seed, ctx)
    col = np.clip(col + grain_noise(ctx, seed, 0.035)[..., None], 0, 1)
    r = rough[0] + (rough[1] - rough[0]) * (1 - h) - speck * 0.08
    return Material(col, h * 0.85 + speck * 0.1, r, depth=depth)


STONE = [(0, (88, 88, 90)), (0.45, (118, 118, 120)), (0.8, (138, 138, 140)), (1, (156, 155, 154))]


@tex("stone")
def stone(ctx, seed):
    return stone_like(ctx, seed, STONE, speck_col=(170, 168, 164), speck_amt=0.45)


def crystalline(ctx, seed, base_stops, crystals, cells=20, amount=0.75,
                smooth=False):
    """Igneous stones: interlocking mineral grains of several colours."""
    x, y = ctx.x, ctx.y
    wx = (fbm(x, y, 3, 3, seed=nz.sub(seed, "wx")) - 0.5) * 0.06
    wy = (fbm(x, y, 3, 3, seed=nz.sub(seed, "wy")) - 0.5) * 0.06
    w = worley(x + wx, y + wy, cells, seed=nz.sub(seed, "grains"), jitter=1.0)
    w2 = worley(x - wy, y + wx, cells * 2, seed=nz.sub(seed, "grains2"), jitter=1.0)
    base = fbm(x, y, 4, 5, seed=seed)
    col = ramp(base, base_stops)
    pal = np.array([rgb(c) for c, _ in crystals])
    wts = np.cumsum([p for _, p in crystals])
    wts = wts / wts[-1]
    pick = np.clip(np.searchsorted(wts, w["rnd"]), 0, len(pal) - 1)
    pick2 = np.clip(np.searchsorted(wts, w2["rnd"]), 0, len(pal) - 1)
    clump = smoothstep(0.35, 0.65, fbm(x, y, 6, 3, seed=nz.sub(seed, "clump")))
    m1 = smoothstep(0.02, 0.12, w["edge"]) * amount * (0.55 + 0.45 * clump)
    col = mix(col, pal[pick], m1 * 0.75)
    col = mix(col, pal[pick2], smoothstep(0.05, 0.15, w2["edge"]) * 0.3 * amount)
    col = hue_jitter(col, 0.05, seed, ctx)
    col = np.clip(col + grain_noise(ctx, seed, 0.03)[..., None], 0, 1)
    h = 0.75 * base + 0.15 * smoothstep(0.0, 0.2, w["edge"]) * w["rnd"] + 0.10 * w2["edge"]
    h = nz.norm01(h)
    if smooth:
        d = frame_border(ctx, 1)
        edge = smoothstep(0.0, 0.6, d)
        h = 0.12 * h + 0.88 * edge
        col = col * (0.90 + 0.10 * edge[..., None])
        rough = 0.20 + 0.08 * (1 - base) + (1 - edge) * 0.3
        return Material(col, h, rough, depth=2.0, ao=0.15)
    rough = 0.72 + 0.18 * (1 - h)
    return Material(col, h, rough, depth=2.2)


GRANITE_BASE = [(0, (128, 82, 66)), (0.6, (154, 104, 86)), (1, (176, 124, 104))]
GRANITE_XTAL = [((182, 120, 98), 3), ((120, 70, 56), 2), ((205, 168, 150), 1.4), ((60, 44, 42), 0.8)]
DIORITE_BASE = [(0, (170, 170, 172)), (0.6, (196, 196, 196)), (1, (220, 220, 218))]
DIORITE_XTAL = [((226, 226, 224), 4), ((182, 182, 184), 2), ((80, 80, 84), 1.0), ((130, 130, 134), 1)]
ANDESITE_BASE = [(0, (112, 112, 112)), (0.6, (134, 134, 134)), (1, (152, 152, 150))]
ANDESITE_XTAL = [((146, 146, 146), 3), ((120, 120, 122), 3), ((170, 170, 168), 1.3), ((92, 92, 94), 1)]

for _n, _b, _x in [("stone_granite", GRANITE_BASE, GRANITE_XTAL),
                   ("stone_diorite", DIORITE_BASE, DIORITE_XTAL),
                   ("stone_andesite", ANDESITE_BASE, ANDESITE_XTAL)]:
    add(_n, (lambda b, xt: lambda ctx, seed: crystalline(ctx, seed, b, xt))(_b, _x))
    add(_n + "_smooth", (lambda b, xt: lambda ctx, seed: crystalline(ctx, seed, b, xt, smooth=True))(_b, _x))


def cobble(ctx, seed, stops, cells=5, mortar=(58, 58, 60), moss=0.0,
           angular=False, rough=0.86):
    x, y = ctx.x, ctx.y
    if angular:
        w = worley(x, y, cells, seed=seed, jitter=0.95, metric="cheby")
        dome = np.sqrt(np.clip(smoothstep(0.03, 0.30, w["edge"]), 0, 1))
    else:
        dome, w = pebbles(ctx, seed, cells=cells, round_=0.42, gap=0.05)
    surf = fbm(x, y, 8, 4, seed=nz.sub(seed, "surf"))
    chips = ridged(x, y, 6, 3, seed=nz.sub(seed, "chips"))
    h = dome * (0.72 + 0.28 * surf) - smoothstep(0.8, 0.95, chips) * 0.12 * dome
    # Each stone gets its own tone and a slight tilt so light catches facets.
    tilt = (w["rnd"] - 0.5) * 0.25
    h = h + tilt * (x - w["cx"]) * cells * dome
    tone = 0.45 * w["rnd"] + 0.55 * surf
    col = ramp(tone, stops)
    gap = 1 - smoothstep(0.0, 0.25, dome)
    col = mix(col, rgb(mortar)[None, None, :] * (0.8 + 0.4 * surf[..., None]), gap)
    r = rough + 0.1 * gap
    sss = 0.0
    if moss > 0:
        mm = fbm(x, y, 4, 5, seed=nz.sub(seed, "moss"))
        mask = smoothstep(0.62 - moss * 0.3, 0.75 - moss * 0.3, mm + gap * 0.35)
        fuzz = fbm(x, y, 32, 2, seed=nz.sub(seed, "fz"))
        mcol = ramp(fuzz * 0.7 + mm * 0.3, [(0, (52, 74, 30)), (0.6, (84, 110, 44)), (1, (118, 142, 62))])
        col = mix(col, mcol, mask)
        h = np.maximum(h, (0.55 + 0.35 * fuzz) * mask)
        r = np.where(mask > 0.5, 0.98, r)
        sss = mask * 0.25
    col = hue_jitter(col, 0.05, seed, ctx)
    col = np.clip(col + grain_noise(ctx, seed, 0.03)[..., None], 0, 1)
    return Material(col, np.clip(h, 0, 1), r, sss=sss, depth=3.4, ao=0.45)


COBBLE = [(0, (82, 82, 84)), (0.5, (118, 118, 118)), (0.85, (140, 140, 140)), (1, (160, 158, 156))]


@tex("cobblestone")
def cobblestone(ctx, seed):
    return cobble(ctx, seed, COBBLE)


@tex("cobblestone_mossy")
def cobblestone_mossy(ctx, seed):
    return cobble(ctx, seed, COBBLE, moss=0.55)


def masonry(ctx, seed, stops, rows, cols, offset=0.5, mortar=1.0,
            mortar_col=(70, 70, 72), cracked=0.0, moss=0.0, bev=1.6,
            rough=0.8, per_brick=0.5, chip=0.6, surface_period=6,
            polish=None):
    x, y = ctx.x, ctx.y
    b = bricks(ctx, rows, cols, offset=offset, mortar=mortar, seed=seed, chip=chip)
    surf = fbm(x, y, surface_period, 5, seed=nz.sub(seed, "s"))
    prof = bevel(b["d"], bev * ctx.px) * b["inside"]
    h = prof * (0.78 + 0.22 * surf)
    tone = per_brick * b["rnd"] + (1 - per_brick) * surf
    col = ramp(tone, stops)
    col = col * (0.88 + 0.12 * prof[..., None])
    mc = rgb(mortar_col)[None, None, :] * (0.85 + 0.3 * surf[..., None])
    col = mix(mc, col, b["inside"])
    r = np.where(b["inside"] > 0.5, rough, 0.95) + 0.0 * surf
    if polish is not None:
        r = np.where(b["inside"] > 0.5, polish + 0.15 * (1 - surf), 0.9)
    sss = 0.0
    if cracked > 0:
        cr = ridged(x, y, 3, 4, seed=nz.sub(seed, "crk"))
        cmask = smoothstep(0.86 - cracked * 0.08, 0.97, cr) * b["inside"]
        h = h - cmask * 0.6
        col = col * (1 - cmask[..., None] * 0.6)
    if moss > 0:
        mm = fbm(x, y, 4, 5, seed=nz.sub(seed, "moss"))
        gapm = 1 - b["inside"]
        mask = smoothstep(0.6 - moss * 0.25, 0.72 - moss * 0.25, mm + gapm * 0.3 + (1 - y) * 0.05)
        fuzz = fbm(x, y, 32, 2, seed=nz.sub(seed, "fz"))
        mcol = ramp(fuzz * 0.7 + mm * 0.3, [(0, (50, 72, 30)), (0.6, (82, 108, 44)), (1, (116, 140, 60))])
        col = mix(col, mcol, mask)
        h = np.maximum(h, (0.5 + 0.4 * fuzz) * mask)
        r = np.where(mask > 0.5, 0.98, r)
        sss = mask * 0.25
    col = hue_jitter(col, 0.04, seed, ctx)
    col = np.clip(col + grain_noise(ctx, seed, 0.03)[..., None], 0, 1)
    return Material(col, np.clip(h, 0, 1), r, sss=sss, depth=3.0, ao=0.4)


STONEBRICK = [(0, (100, 100, 102)), (0.5, (122, 121, 122)), (1, (146, 145, 144))]


@tex("stonebrick")
def stonebrick(ctx, seed):
    return masonry(ctx, seed, STONEBRICK, 2, 1, offset=0.5, mortar=1.0, mortar_col=(78, 78, 80))


@tex("stonebrick_cracked")
def stonebrick_cracked(ctx, seed):
    return masonry(ctx, seed, STONEBRICK, 2, 1, offset=0.5, cracked=1.0, mortar_col=(78, 78, 80))


@tex("stonebrick_mossy")
def stonebrick_mossy(ctx, seed):
    return masonry(ctx, seed, STONEBRICK, 2, 1, offset=0.5, moss=0.6, mortar_col=(78, 78, 80))


@tex("stonebrick_carved")
def stonebrick_carved(ctx, seed):
    x, y = ctx.x, ctx.y
    m = masonry(ctx, seed, STONEBRICK, 1, 1, offset=0.0, mortar=1.0, mortar_col=(78, 78, 80))
    # Engraved concentric ring with a central boss.
    r = np.sqrt((x - 0.5) ** 2 + (y - 0.5) ** 2) * 16
    groove = np.exp(-((r - 4.6) / 0.7) ** 2) + np.exp(-((r - 1.4) / 0.6) ** 2) * 0.8
    sq = np.maximum(np.abs(x - 0.5), np.abs(y - 0.5)) * 16
    groove += np.exp(-((sq - 6.4) / 0.55) ** 2)
    m.height = np.clip(m.height - groove * 0.45, 0, 1)
    m.albedo = m.albedo * (1 - np.clip(groove, 0, 1)[..., None] * 0.35)
    return m


@tex("stone_slab_top")
def stone_slab_top(ctx, seed):
    x, y = ctx.x, ctx.y
    m = stone_like(ctx, seed, [(0, (150, 150, 150)), (0.6, (166, 166, 166)), (1, (178, 178, 176))],
                   period=4, crack=0.05, rough=(0.55, 0.7), depth=1.4)
    d = frame_border(ctx, 1)
    edge = smoothstep(0.0, 1.0, d)
    m.height = m.height * 0.4 * edge + edge * 0.6
    m.albedo = m.albedo * (0.80 + 0.20 * edge[..., None])
    return m


@tex("stone_slab_side")
def stone_slab_side(ctx, seed):
    x, y = ctx.x, ctx.y
    m = stone_slab_top(ctx, seed)
    seam = np.exp(-(((y - 0.5) * 16) / 0.5) ** 2)
    m.height = np.clip(m.height - seam * 0.5, 0, 1)
    m.albedo = m.albedo * (1 - seam[..., None] * 0.3)
    return m


@tex("bedrock")
def bedrock(ctx, seed):
    x, y = ctx.x, ctx.y
    w = worley(x, y, 7, seed=seed, jitter=1.0)
    n = fbm(x, y, 4, 6, seed=nz.sub(seed, "n"))
    t = 0.6 * w["rnd"] + 0.4 * n
    col = ramp(t, [(0, (30, 30, 32)), (0.35, (62, 62, 64)), (0.6, (96, 96, 98)), (0.85, (130, 130, 132)), (1, (160, 160, 160))])
    h = nz.norm01(0.6 * smoothstep(0.0, 0.3, w["edge"]) * (0.4 + 0.6 * w["rnd"]) + 0.4 * n)
    col = np.clip(col + grain_noise(ctx, seed, 0.05)[..., None], 0, 1)
    return Material(col, h, 0.9, depth=4.0, ao=0.6)


# --------------------------------------------------------------------------
# Deepslate, tuff, calcite, dripstone, basalt family
# --------------------------------------------------------------------------

DEEPSLATE = [(0, (52, 52, 58)), (0.5, (74, 74, 80)), (1, (98, 98, 104))]


@tex("deepslate/deepslate")
def deepslate(ctx, seed):
    x, y = ctx.x, ctx.y
    # Foliated metamorphic rock: vertical schistosity with lens-shaped layers.
    wx = (fbm(x, y, 3, 3, seed=nz.sub(seed, "w")) - 0.5) * 0.12
    lay = fbm(x + wx, y, 12, 4, seed=seed, period_y=3)
    lens = ridged(x + wx, y, 6, 3, seed=nz.sub(seed, "l"), period_y=2)
    n = fbm(x, y, 5, 5, seed=nz.sub(seed, "n"))
    cw = worley(x, y, 5, seed=nz.sub(seed, "c"), jitter=1.0, cells_y=3)
    crack = smoothstep(0.025, 0.0, cw["edge"]) * (cw["rnd"] > 0.65) * \
        smoothstep(0.4, 0.6, fbm(x, y, 4, 2, seed=nz.sub(seed, "cm")))
    t = 0.4 * lay + 0.4 * n + 0.2 * lens
    col = ramp(t, DEEPSLATE) * (1 - crack[..., None] * 0.25)
    h = nz.norm01(0.45 * lay + 0.2 * lens + 0.35 * n - 0.25 * crack)
    col = np.clip(col + grain_noise(ctx, seed, 0.03)[..., None], 0, 1)
    return Material(col, h, 0.8 + 0.1 * (1 - h), depth=2.6)


@tex("deepslate/deepslate_top")
def deepslate_top(ctx, seed):
    x, y = ctx.x, ctx.y
    wx = fbm(x, y, 2, 4, seed=nz.sub(seed, "a")) - 0.5
    wy = fbm(x, y, 2, 4, seed=nz.sub(seed, "b")) - 0.5
    swirl = fbm(x + wx * 0.35, y + wy * 0.35, 6, 5, seed=seed)
    col = ramp(swirl, DEEPSLATE)
    col = np.clip(col + grain_noise(ctx, seed, 0.03)[..., None], 0, 1)
    return Material(col, swirl, 0.82, depth=2.0)


@tex("deepslate/cobbled_deepslate")
def cobbled_deepslate(ctx, seed):
    return cobble(ctx, seed, [(0, (40, 40, 46)), (0.5, (66, 66, 72)), (1, (96, 96, 102))],
                  cells=6, mortar=(28, 28, 32), angular=True)


def polished(ctx, seed, stops, rough=0.3, border=1.0, period=4):
    x, y = ctx.x, ctx.y
    n = fbm(x, y, period, 5, seed=seed)
    col = ramp(n, stops)
    d = frame_border(ctx, 1)
    edge = smoothstep(0.0, border, d)
    h = 0.1 * n + 0.9 * edge
    col = col * (0.78 + 0.22 * edge[..., None])
    scratches = smoothstep(0.92, 0.99, ridged(x, y, 3, 3, seed=nz.sub(seed, "sc")))
    r = rough + 0.12 * (1 - n) + scratches * 0.2 + (1 - edge) * 0.3
    col = np.clip(col + grain_noise(ctx, seed, 0.02)[..., None], 0, 1)
    return Material(col, h, r, depth=2.0, ao=0.25)


@tex("deepslate/polished_deepslate")
def polished_deepslate(ctx, seed):
    return polished(ctx, seed, [(0, (56, 56, 62)), (0.6, (72, 72, 78)), (1, (88, 88, 94))], rough=0.28)


@tex("deepslate/deepslate_bricks")
def deepslate_bricks(ctx, seed):
    return masonry(ctx, seed, [(0, (56, 56, 62)), (0.5, (74, 74, 80)), (1, (94, 94, 100))],
                   4, 2, offset=0.5, mortar=1.0, mortar_col=(30, 30, 34), bev=1.0)


@tex("deepslate/cracked_deepslate_bricks")
def cracked_deepslate_bricks(ctx, seed):
    return masonry(ctx, seed, [(0, (56, 56, 62)), (0.5, (74, 74, 80)), (1, (94, 94, 100))],
                   4, 2, offset=0.5, mortar=1.0, mortar_col=(30, 30, 34), bev=1.0, cracked=1.0)


@tex("deepslate/deepslate_tiles")
def deepslate_tiles(ctx, seed):
    return masonry(ctx, seed, [(0, (44, 44, 50)), (0.5, (60, 60, 66)), (1, (80, 80, 86))],
                   4, 4, offset=0.0, mortar=1.0, mortar_col=(30, 30, 34), bev=0.5, chip=0.12)


@tex("deepslate/cracked_deepslate_tiles")
def cracked_deepslate_tiles(ctx, seed):
    return masonry(ctx, seed, [(0, (44, 44, 50)), (0.5, (60, 60, 66)), (1, (80, 80, 86))],
                   4, 4, offset=0.0, mortar=1.0, mortar_col=(30, 30, 34), bev=0.5, chip=0.12,
                   cracked=1.0)


@tex("deepslate/chiseled_deepslate")
def chiseled_deepslate(ctx, seed):
    x, y = ctx.x, ctx.y
    m = polished(ctx, seed, [(0, (50, 50, 56)), (0.6, (66, 66, 72)), (1, (84, 84, 90))], rough=0.35)
    sq = np.maximum(np.abs(x - 0.5), np.abs(y - 0.5)) * 16
    groove = sum(np.exp(-((sq - r) / 0.45) ** 2) for r in (2.0, 4.5, 6.8))
    m.height = np.clip(m.height - groove * 0.5, 0, 1)
    m.albedo = m.albedo * (1 - np.clip(groove, 0, 1)[..., None] * 0.4)
    return m


@tex("tuff")
def tuff(ctx, seed):
    x, y = ctx.x, ctx.y
    base = fbm(x, y, 4, 5, seed=seed)
    w = worley(x, y, 16, seed=nz.sub(seed, "pores"), jitter=1.0)
    pores = 1 - smoothstep(0.0, 0.22, w["f1"]) * (w["rnd"] > 0.55)
    pores = np.where(w["rnd"] > 0.55, 1 - smoothstep(0.05, 0.25, w["f1"]), 0)
    clasts = smoothstep(0.1, 0.3, worley(x, y, 7, seed=nz.sub(seed, "cl"))["edge"]) * \
        (worley(x, y, 7, seed=nz.sub(seed, "cl"))["rnd"] > 0.7)
    col = ramp(base, [(0, (90, 92, 84)), (0.5, (110, 112, 102)), (1, (130, 130, 118))])
    col = mix(col, rgb((150, 146, 128))[None, None, :], clasts * 0.5)
    col = col * (1 - pores[..., None] * 0.45)
    h = nz.norm01(0.6 * base + 0.2 * clasts - 0.5 * pores)
    col = np.clip(col + grain_noise(ctx, seed, 0.04)[..., None], 0, 1)
    return Material(col, h, 0.92, depth=3.0)


@tex("polished_tuff")
def polished_tuff(ctx, seed):
    return polished(ctx, seed, [(0, (96, 100, 92)), (0.6, (112, 116, 106)), (1, (128, 130, 120))], rough=0.4)


@tex("tuff_bricks")
def tuff_bricks(ctx, seed):
    return masonry(ctx, seed, [(0, (92, 96, 88)), (0.5, (108, 112, 102)), (1, (126, 128, 118))],
                   4, 2, offset=0.5, mortar=1.0, mortar_col=(60, 62, 56), bev=1.0)


@tex("calcite")
def calcite(ctx, seed):
    x, y = ctx.x, ctx.y
    n = fbm(x, y, 3, 6, seed=seed)
    w = worley(x, y, 9, seed=nz.sub(seed, "x"), jitter=1.0)
    veins = smoothstep(0.08, 0.0, w["edge"]) * 0.5
    col = ramp(n, [(0, (196, 198, 196)), (0.6, (220, 222, 220)), (1, (236, 238, 236))])
    col = col * (1 - veins[..., None] * 0.3)
    h = nz.norm01(0.6 * n + 0.4 * smoothstep(0, 0.3, w["edge"]))
    return Material(col, h, 0.55 + 0.2 * (1 - h), sss=0.08, depth=2.0, ao=0.2)


@tex("dripstone_block")
def dripstone_block(ctx, seed):
    x, y = ctx.x, ctx.y
    lay, band = strata(ctx, seed, bands=8, wobble=0.12, sharp=0.8)
    n = fbm(x, y, 4, 5, seed=nz.sub(seed, "n"))
    t = 0.5 * band + 0.5 * n
    col = ramp(t, [(0, (106, 78, 62)), (0.5, (134, 104, 84)), (1, (162, 130, 106))])
    col = col * (0.85 + 0.15 * lay[..., None])
    h = nz.norm01(0.5 * lay + 0.5 * n)
    return Material(col, h, 0.75, depth=2.6)


@tex("basalt_side")
def basalt_side(ctx, seed):
    x, y = ctx.x, ctx.y
    cols = fbm(x, y, 10, 4, seed=seed, period_y=1)
    rid = ridged(x, y, 8, 3, seed=nz.sub(seed, "r"), period_y=1)
    n = fbm(x, y, 6, 4, seed=nz.sub(seed, "n"))
    h = nz.norm01(0.5 * cols + 0.3 * rid + 0.2 * n)
    col = ramp(h * 0.7 + n * 0.3, [(0, (40, 40, 44)), (0.5, (72, 72, 76)), (1, (104, 104, 108))])
    return Material(col, h, 0.85, depth=3.2)


@tex("basalt_top")
def basalt_top(ctx, seed):
    x, y = ctx.x, ctx.y
    w = worley(x, y, 4, seed=seed, jitter=0.6)
    n = fbm(x, y, 8, 4, seed=nz.sub(seed, "n"))
    ring = smoothstep(0.0, 0.15, w["edge"])
    h = nz.norm01(ring * 0.7 + n * 0.3)
    col = ramp(0.6 * n + 0.4 * w["rnd"], [(0, (44, 44, 48)), (0.5, (70, 70, 74)), (1, (96, 96, 100))])
    col = col * (0.7 + 0.3 * ring[..., None])
    return Material(col, h, 0.85, depth=3.0)


@tex("polished_basalt_side")
def polished_basalt_side(ctx, seed):
    x, y = ctx.x, ctx.y
    cols = np.abs(np.sin(x * np.pi * 4))
    n = fbm(x, y, 8, 4, seed=seed, period_y=2)
    h = nz.norm01(0.7 * cols + 0.3 * n)
    col = ramp(h, [(0, (54, 54, 58)), (0.6, (88, 88, 92)), (1, (110, 110, 114))])
    return Material(col, h, 0.42, depth=2.2)


@tex("polished_basalt_top")
def polished_basalt_top(ctx, seed):
    return polished(ctx, seed, [(0, (60, 60, 64)), (0.6, (84, 84, 88)), (1, (100, 100, 104))], rough=0.38)


@tex("smooth_basalt")
def smooth_basalt(ctx, seed):
    return stone_like(ctx, seed, [(0, (50, 50, 54)), (0.6, (70, 70, 74)), (1, (88, 88, 92))],
                      crack=0.08, rough=(0.55, 0.7), depth=1.6)


@tex("blackstone")
def blackstone(ctx, seed):
    m = stone_like(ctx, seed, [(0, (30, 26, 32)), (0.5, (46, 40, 48)), (1, (66, 58, 66))],
                   period=5, crack=0.3, speck_col=(96, 70, 52), speck_amt=0.4, depth=3.0)
    return m


@tex("blackstone_top")
def blackstone_top(ctx, seed):
    return cobble(ctx, seed, [(0, (28, 24, 30)), (0.5, (44, 38, 46)), (1, (64, 56, 64))],
                  cells=4, mortar=(18, 16, 20), angular=True)


@tex("polished_blackstone")
def polished_blackstone(ctx, seed):
    return polished(ctx, seed, [(0, (40, 36, 44)), (0.6, (54, 48, 58)), (1, (66, 60, 70))], rough=0.3)


@tex("polished_blackstone_bricks")
def polished_blackstone_bricks(ctx, seed):
    return masonry(ctx, seed, [(0, (40, 36, 44)), (0.5, (54, 48, 58)), (1, (68, 62, 72))],
                   4, 2, offset=0.5, mortar=1.0, mortar_col=(20, 18, 24), bev=1.0, polish=0.35)


@tex("cracked_polished_blackstone_bricks")
def cracked_polished_blackstone_bricks(ctx, seed):
    return masonry(ctx, seed, [(0, (40, 36, 44)), (0.5, (54, 48, 58)), (1, (68, 62, 72))],
                   4, 2, offset=0.5, mortar=1.0, mortar_col=(20, 18, 24), bev=1.0, polish=0.4,
                   cracked=1.0)


@tex("obsidian")
def obsidian(ctx, seed):
    x, y = ctx.x, ctx.y
    w = worley(x, y, 5, seed=seed, jitter=1.0, metric="cheby")
    n = fbm(x, y, 4, 5, seed=nz.sub(seed, "n"))
    # Conchoidal fractures: faceted planes with sharp ridges.
    facet = (w["rnd"] - 0.5) * (x - w["cx"]) * 5 + (n - 0.5) * 0.4
    h = nz.norm01(facet + smoothstep(0.0, 0.08, w["edge"]) * 0.3)
    col = ramp(0.5 * n + 0.5 * w["rnd"], [(0, (10, 8, 18)), (0.5, (22, 16, 36)), (0.85, (44, 30, 66)), (1, (70, 50, 96))])
    edge_hi = smoothstep(0.04, 0.0, w["edge"])
    col = col + edge_hi[..., None] * rgb((60, 40, 90)) * 0.5
    return Material(np.clip(col, 0, 1), h, 0.06 + 0.12 * n, depth=2.0, ao=0.1)


@tex("crying_obsidian")
def crying_obsidian(ctx, seed):
    x, y = ctx.x, ctx.y
    m = obsidian(ctx, seed)
    w = worley(x, y, 6, seed=nz.sub(seed, "tears"), jitter=1.0, cells_y=3)
    drip = (1 - smoothstep(0.0, 0.25, np.abs(x - w["cx"]) * 6)) * \
        smoothstep(0.6, 0.0, np.abs(y - w["cy"]) * 3) * (w["rnd"] > 0.45)
    glow = np.clip(drip * 1.4, 0, 1)
    tear = ramp(glow, [(0, (60, 10, 140)), (0.6, (140, 40, 230)), (1, (220, 140, 255))])
    m.albedo = mix(m.albedo, tear, glow)
    m.emissive = glow * 0.9
    m.rough = np.where(glow > 0.2, 0.05, m.rough)
    return m
