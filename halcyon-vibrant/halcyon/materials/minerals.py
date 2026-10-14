"""Ores, metal blocks, gem blocks and amethyst."""

from __future__ import annotations

import numpy as np

from .. import noise as nz
from ..lib import bevel, bricks, frame_border, mix, rgb
from ..noise import fbm, ramp, smoothstep, worley
from ..pbr import Material
from ..registry import add
from .building import netherrack
from .terrain import STONE, deepslate, stone_like

# name: color stops, metal, rough, emissive, faceted, grain cells, coverage
MINERALS = {
    "coal": dict(stops=[(0, (18, 18, 20)), (0.6, (38, 38, 40)), (1, (70, 68, 68))], metal=0, rough=0.32, emis=0,
                 facet=True, cells=20, cover=0.55),
    "iron": dict(stops=[(0, (170, 124, 96)), (0.6, (206, 162, 132)), (1, (232, 200, 174))], metal=0, rough=0.55,
                 emis=0, facet=False, cells=22, cover=0.55),
    "copper": dict(stops=[(0, (150, 72, 44)), (0.6, (200, 110, 74)), (1, (228, 150, 110))], metal=1, rough=0.4,
                   emis=0, facet=False, cells=22, cover=0.6, patina=(84, 156, 120)),
    "gold": dict(stops=[(0, (196, 146, 20)), (0.6, (240, 196, 50)), (1, (255, 236, 120))], metal=1, rough=0.26,
                 emis=0, facet=False, cells=24, cover=0.5),
    "diamond": dict(stops=[(0, (40, 170, 166)), (0.6, (96, 222, 214)), (1, (200, 255, 250))], metal=0, rough=0.04,
                    emis=0.08, facet=True, cells=18, cover=0.5),
    "emerald": dict(stops=[(0, (10, 120, 50)), (0.6, (30, 190, 86)), (1, (150, 250, 170))], metal=0, rough=0.05,
                    emis=0.06, facet=True, cells=16, cover=0.45),
    "lapis": dict(stops=[(0, (20, 40, 130)), (0.6, (36, 72, 186)), (1, (96, 134, 230))], metal=0, rough=0.3,
                  emis=0, facet=False, cells=22, cover=0.6),
    "redstone": dict(stops=[(0, (120, 4, 4)), (0.6, (196, 16, 10)), (1, (255, 92, 70))], metal=0, rough=0.32,
                     emis=0.4, facet=True, cells=22, cover=0.6),
    "quartz": dict(stops=[(0, (200, 188, 176)), (0.6, (232, 224, 214)), (1, (252, 248, 242))], metal=0, rough=0.14,
                   emis=0, facet=True, cells=20, cover=0.55),
    "nether_gold": dict(stops=[(0, (196, 146, 20)), (0.6, (240, 196, 50)), (1, (255, 236, 120))], metal=1,
                        rough=0.28, emis=0, facet=False, cells=30, cover=0.45),
}


def ore(ctx, seed, base, kind):
    x, y = ctx.x, ctx.y
    spec = MINERALS[kind]
    clusters = worley(x, y, 3, seed=nz.sub(seed, "cl"), jitter=0.9)
    breakup = fbm(x, y, 8, 3, seed=nz.sub(seed, "bk"))
    # A few compact veins per face rather than speckle everywhere.
    cmask = smoothstep(0.58, 0.28, clusters["f1"] + (breakup - 0.5) * 0.5) * (clusters["rnd"] > 0.2)
    metric = "cheby" if spec["facet"] else "euclid"
    cells = max(8, int(spec["cells"] * 0.62))
    g = worley(x, y, cells, seed=nz.sub(seed, "g"), jitter=1.0, metric=metric)
    sel = g["rnd"] < min(0.9, spec["cover"] + 0.25)
    grain = np.where(sel, smoothstep(0.5, 0.18, g["f1"]), 0) * cmask
    grain = smoothstep(0.15, 0.5, grain)
    tone = 0.5 * g["rnd"] / min(0.9, spec["cover"] + 0.25) + 0.5 * fbm(x, y, 16, 2, seed=nz.sub(seed, "t"))
    if spec["facet"]:
        # Flat crystal faces: tilt each grain so it glints at its own angle.
        tilt_x = (nz.rng(nz.sub(seed, "tx")).random(cells ** 2) - 0.5)[g["id"]]
        tilt_y = (nz.rng(nz.sub(seed, "ty")).random(cells ** 2) - 0.5)[g["id"]]
        facet = (x - g["cx"]) * tilt_x * cells + (y - g["cy"]) * tilt_y * cells
        tone = tone + facet * 0.5
    mcol = ramp(tone, spec["stops"])
    col = mix(base.albedo, mcol, grain)
    # Rim of darker host rock around each inclusion
    rim = np.clip(smoothstep(0.0, 0.3, np.where(sel, smoothstep(0.62, 0.3, g["f1"]), 0) * cmask) - grain, 0, 1)
    col = col * (1 - rim[..., None] * 0.35)
    h = np.maximum(base.height * (1 - 0.3 * rim), (0.6 + 0.4 * grain) * (grain > 0.05))
    if spec["facet"]:
        h = np.where(grain > 0.05, np.clip(0.75 + facet * 0.5, 0, 1), h)
    metal = spec["metal"] * (grain > 0.4)
    rough = np.where(grain > 0.4, spec["rough"], np.asarray(base.rough) * np.ones_like(grain))
    emis = spec["emis"] * grain * smoothstep(0.3, 0.9, tone)
    if "patina" in spec:
        pat = smoothstep(0.55, 0.7, fbm(x, y, 10, 3, seed=nz.sub(seed, "pat"))) * grain
        col = mix(col, rgb(spec["patina"])[None, None, :], pat)
        metal = metal * (1 - pat)
        rough = np.where(pat > 0.5, 0.8, rough)
    return Material(np.clip(col, 0, 1), np.clip(h, 0, 1), rough, metal=metal, emissive=emis,
                    depth=3.0, ao=0.45)


def stone_base(ctx, seed):
    return stone_like(ctx, seed, STONE, speck_col=(170, 168, 164), speck_amt=0.3)


for k in ["coal", "iron", "copper", "gold", "diamond", "emerald", "lapis", "redstone"]:
    add(f"{k}_ore", (lambda k: lambda ctx, seed: ore(ctx, seed, stone_base(ctx, nz.sub(seed, "b")), k))(k))
    add(f"deepslate/deepslate_{k}_ore",
        (lambda k: lambda ctx, seed: ore(ctx, seed, deepslate(ctx, nz.sub(seed, "b")), k))(k))
add("quartz_ore", lambda ctx, seed: ore(ctx, seed, netherrack(ctx, nz.sub(seed, "b")), "quartz"))
add("nether_gold_ore", lambda ctx, seed: ore(ctx, seed, netherrack(ctx, nz.sub(seed, "b")), "nether_gold"))


# --------------------------------------------------------------------------
# Metal blocks
# --------------------------------------------------------------------------

def metal_plate(ctx, seed, color, rough=0.3, brushed=True, hammered=0.0, panels=1, rivets=True):
    x, y = ctx.x, ctx.y
    px = ctx.px
    b = bricks(ctx, panels, panels, offset=0.0, mortar=0.6, seed=seed, chip=0.0)
    prof = bevel(b["d"], 1.2 * px) * b["inside"]
    brush = fbm(x, y, 1, 4, seed=nz.sub(seed, "br"), period_y=48) if brushed else fbm(x, y, 6, 4, seed=seed)
    n = fbm(x, y, 3, 4, seed=nz.sub(seed, "n"))
    h = 0.3 + 0.55 * prof + 0.04 * brush
    if hammered > 0:
        w = worley(x, y, 10, seed=nz.sub(seed, "ham"))
        dent = smoothstep(0.0, 0.8, w["f1"])
        h = h + hammered * 0.25 * dent * prof
    col = rgb(color)[None, None, :] * (0.88 + 0.12 * brush[..., None] + 0.08 * n[..., None])
    col = col * (0.78 + 0.22 * prof[..., None])
    if rivets:
        rv = np.zeros_like(x)
        for cx in (2.2 / 16, 1 - 2.2 / 16):
            for cy in (2.2 / 16, 1 - 2.2 / 16):
                d = np.sqrt(((x - cx) * 16) ** 2 + ((y - cy) * 16) ** 2)
                rv = np.maximum(rv, smoothstep(0.85, 0.4, d))
        if panels == 1:
            h = np.maximum(h, 0.85 + 0.15 * rv * (rv > 0.05))
            col = col * (1 + rv[..., None] * 0.08)
    r = rough + 0.12 * (1 - brush) + 0.15 * (1 - b["inside"]) + 0.06 * (1 - n)
    return Material(np.clip(col, 0, 1), np.clip(h, 0, 1), r, metal=1.0, depth=2.6, ao=0.35)


def copper(ctx, seed, stage, cut=False):
    x, y = ctx.x, ctx.y
    if cut:
        base = metal_plate(ctx, seed, (194, 110, 80), rough=0.32, brushed=False, panels=4, rivets=False)
    else:
        base = metal_plate(ctx, seed, (194, 110, 80), rough=0.3, brushed=True, rivets=False)
    if stage == 0:
        return base
    patina_amount = {1: 0.35, 2: 0.7, 3: 1.0}[stage]
    n = fbm(x, y, 4, 6, seed=nz.sub(seed, "pat"))
    # Patina gathers in recesses first.
    recess = 1 - base.height
    pat = smoothstep(0.75 - patina_amount * 0.8, 0.85 - patina_amount * 0.8, n + recess * 0.3)
    if stage == 3:
        pat = np.ones_like(pat)
    tarnish = rgb((150, 104, 82)) if stage == 1 else rgb((110, 130, 100))
    verdigris = ramp(fbm(x, y, 8, 4, seed=nz.sub(seed, "v")),
                     [(0, (58, 130, 100)), (0.5, (82, 162, 132)), (1, (120, 190, 160))])
    col = mix(base.albedo, tarnish[None, None, :] * np.ones_like(base.albedo), min(1.0, patina_amount * 0.6))
    col = mix(col, verdigris, pat)
    metal = 1 - pat
    rough = np.where(pat > 0.5, 0.82, np.asarray(base.rough) + 0.1 * stage)
    h = np.clip(base.height + pat * 0.06 * fbm(x, y, 16, 2, seed=nz.sub(seed, "ph")), 0, 1)
    return Material(np.clip(col, 0, 1), h, rough, metal=metal, depth=2.6, ao=0.4)


def raw_block(ctx, seed, stops, metal=0.0, rough=0.5):
    x, y = ctx.x, ctx.y
    w = worley(x, y, 6, seed=seed, jitter=1.0)
    w2 = worley(x, y, 13, seed=nz.sub(seed, "2"), jitter=1.0)
    lumps = smoothstep(0.0, 0.35, w["edge"]) * 0.7 + smoothstep(0.0, 0.3, w2["edge"]) * 0.3
    n = fbm(x, y, 8, 4, seed=nz.sub(seed, "n"))
    h = nz.norm01(lumps + 0.2 * n)
    col = ramp(0.5 * h + 0.3 * w["rnd"] + 0.2 * n, stops)
    m = metal * smoothstep(0.55, 0.75, h)
    return Material(col, h, rough - 0.15 * h, metal=m, depth=3.2, ao=0.55)


def gem_block(ctx, seed, stops, rough=0.03, emis=0.0, sss=0.12):
    x, y = ctx.x, ctx.y
    b = bricks(ctx, 4, 4, offset=0.0, mortar=0.6, seed=seed, chip=0.0)
    w = worley(x, y, 8, seed=nz.sub(seed, "f"), jitter=0.9, metric="cheby")
    tx = (nz.rng(nz.sub(seed, "tx")).random(64) - 0.5)[w["id"] % 64]
    ty = (nz.rng(nz.sub(seed, "ty")).random(64) - 0.5)[w["id"] % 64]
    facet = (x - w["cx"]) * tx * 8 + (y - w["cy"]) * ty * 8
    prof = bevel(b["d"], 0.8 * ctx.px) * b["inside"]
    h = np.clip(0.3 + 0.5 * prof + 0.25 * facet * prof, 0, 1)
    tone = 0.55 + facet * 0.8 + 0.2 * (b["rnd"] - 0.5)
    col = ramp(tone, stops)
    col = col * (0.75 + 0.25 * prof[..., None])
    e = emis * smoothstep(0.6, 1.0, tone) * prof
    return Material(np.clip(col, 0, 1), h, rough + 0.2 * (1 - b["inside"]), emissive=e, sss=sss * prof,
                    depth=2.4, ao=0.3)


add("iron_block", lambda ctx, seed: metal_plate(ctx, seed, (200, 200, 204), rough=0.26))
add("gold_block", lambda ctx, seed: metal_plate(ctx, seed, (246, 204, 76), rough=0.16, brushed=False, hammered=0.6))
add("netherite_block", lambda ctx, seed: metal_plate(ctx, seed, (70, 64, 68), rough=0.32, brushed=False,
                                                      hammered=0.3, panels=2, rivets=False))
add("copper_block", lambda ctx, seed: copper(ctx, seed, 0))
add("exposed_copper", lambda ctx, seed: copper(ctx, seed, 1))
add("weathered_copper", lambda ctx, seed: copper(ctx, seed, 2))
add("oxidized_copper", lambda ctx, seed: copper(ctx, seed, 3))
add("cut_copper", lambda ctx, seed: copper(ctx, seed, 0, cut=True))
add("exposed_cut_copper", lambda ctx, seed: copper(ctx, seed, 1, cut=True))
add("weathered_cut_copper", lambda ctx, seed: copper(ctx, seed, 2, cut=True))
add("oxidized_cut_copper", lambda ctx, seed: copper(ctx, seed, 3, cut=True))
add("raw_iron_block", lambda ctx, seed: raw_block(ctx, seed, [(0, (120, 92, 72)), (0.5, (166, 134, 108)), (1, (204, 176, 150))]))
add("raw_gold_block", lambda ctx, seed: raw_block(ctx, seed, [(0, (160, 110, 20)), (0.5, (220, 168, 46)), (1, (250, 214, 100))],
                                                  metal=1.0, rough=0.5))
add("raw_copper_block", lambda ctx, seed: raw_block(ctx, seed, [(0, (110, 66, 46)), (0.5, (154, 104, 78)), (1, (200, 140, 106))],
                                                    metal=1.0, rough=0.55))
add("diamond_block", lambda ctx, seed: gem_block(ctx, seed, [(0, (40, 160, 156)), (0.5, (98, 222, 214)), (1, (210, 255, 250))],
                                                 emis=0.05))
add("emerald_block", lambda ctx, seed: gem_block(ctx, seed, [(0, (10, 120, 50)), (0.5, (42, 200, 88)), (1, (160, 250, 180))],
                                                 emis=0.04))


def lapis_block(ctx, seed):
    x, y = ctx.x, ctx.y
    W = ctx.w
    m = stone_like(ctx, seed, [(0, (22, 46, 112)), (0.5, (34, 66, 142)), (1, (54, 92, 176))], crack=0.1,
                   rough=(0.3, 0.42), depth=1.8)
    r = nz.rng(nz.sub(seed, "pyrite"))
    fl = nz.blur((r.random((W, W)) > 0.975).astype(float), 1, 1) > 0.1
    m.albedo = mix(m.albedo, rgb((220, 190, 90))[None, None, :], fl * 0.9)
    m.metal = fl.astype(float)
    m.rough = np.where(fl, 0.25, m.rough)
    d = frame_border(ctx, 1)
    edge = smoothstep(0.0, 0.8, d)
    m.height = m.height * 0.3 + edge * 0.7
    return m


add("lapis_block", lapis_block)


def redstone_block(ctx, seed):
    x, y = ctx.x, ctx.y
    m = gem_block(ctx, seed, [(0, (110, 6, 2)), (0.5, (178, 26, 8)), (1, (255, 90, 60))], rough=0.28, emis=0.45,
                  sss=0.0)
    return m


add("redstone_block", redstone_block)


def coal_block(ctx, seed):
    x, y = ctx.x, ctx.y
    w = worley(x, y, 7, seed=seed, jitter=1.0, metric="cheby")
    tx = (nz.rng(nz.sub(seed, "tx")).random(49) - 0.5)[w["id"]]
    facet = (x - w["cx"]) * tx * 7
    n = fbm(x, y, 8, 3, seed=nz.sub(seed, "n"))
    h = nz.norm01(facet + smoothstep(0.0, 0.1, w["edge"]) * 0.3)
    col = ramp(0.5 + facet * 0.8 + 0.1 * n, [(0, (10, 10, 11)), (0.5, (22, 22, 24)), (1, (54, 54, 56))])
    return Material(col, h, 0.25 + 0.35 * n, depth=2.4, ao=0.3)


add("coal_block", coal_block)


def amethyst(ctx, seed, budding=False):
    x, y = ctx.x, ctx.y
    m = gem_block(ctx, seed, [(0, (84, 54, 140)), (0.5, (138, 98, 196)), (1, (214, 176, 250))],
                  rough=0.08, emis=0.06, sss=0.25)
    w = worley(x, y, 5, seed=nz.sub(seed, "a"), jitter=1.0, metric="cheby")
    m.height = np.clip(0.6 * m.height + 0.4 * smoothstep(0.0, 0.2, w["edge"]), 0, 1)
    if budding:
        bud = smoothstep(0.35, 0.2, w["f1"]) * (w["rnd"] > 0.5)
        m.albedo = mix(m.albedo, rgb((40, 20, 70))[None, None, :], bud * 0.8)
        m.height = np.clip(m.height - bud * 0.5, 0, 1)
    return m


add("amethyst_block", amethyst)
add("budding_amethyst", lambda ctx, seed: amethyst(ctx, seed, budding=True))
