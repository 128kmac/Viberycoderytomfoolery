"""Soils, grass, sand, gravel, clay, moss, snow and ice."""

from __future__ import annotations

import numpy as np

from .. import noise as nz
from ..lib import (blade_shape, frame_border, gray, grain_noise, hue_jitter,
                   mix, pebbles, rgb, stamp, strata)
from ..noise import fbm, ramp, ridged, smoothstep, worley
from ..pbr import Material
from ..registry import add, tex

GRASS_CARRIED = np.array([0.53, 0.80, 0.30])
DIRT = [(0, (88, 60, 40)), (0.4, (120, 85, 58)), (0.75, (146, 106, 74)), (1, (170, 128, 92))]


# --------------------------------------------------------------------------
# Dirt family
# --------------------------------------------------------------------------

def dirt_mat(ctx, seed, stops=DIRT, stones=0.25, organic=0.4, rough=0.95):
    x, y = ctx.x, ctx.y
    clod = worley(x, y, 9, seed=nz.sub(seed, "clod"), jitter=1.0)
    n = fbm(x, y, 4, 6, seed=seed)
    fine = fbm(x, y, 16, 3, seed=nz.sub(seed, "f"))
    clods = smoothstep(0.95, 0.15, clod["f1"]) * (0.4 + 0.6 * clod["rnd"])
    h = 0.3 * clods + 0.5 * n + 0.2 * fine
    tone = 0.6 * n + 0.15 * clod["rnd"] + 0.25 * fine
    col = ramp(tone, stops)
    # Small embedded stones
    if stones > 0:
        st = worley(x, y, 18, seed=nz.sub(seed, "st"), jitter=1.0)
        sel = st["rnd"] < stones
        sm = np.where(sel, smoothstep(0.35, 0.12, st["f1"]), 0)
        scol = ramp(st["rnd"] / max(stones, 1e-3),
                    [(0, (96, 92, 88)), (0.5, (130, 124, 116)), (1, (160, 150, 138))])
        col = mix(col, scol, sm)
        h = np.maximum(h, 0.55 + 0.4 * sm) * (sm > 0.05) + h * (sm <= 0.05)
    # Dark organic specks (humus)
    if organic > 0:
        sp = smoothstep(0.78, 0.9, fbm(x, y, 24, 2, seed=nz.sub(seed, "org")))
        col = col * (1 - sp[..., None] * organic * 0.6)
    col = hue_jitter(col, 0.05, seed, ctx)
    col = np.clip(col + grain_noise(ctx, seed, 0.04)[..., None], 0, 1)
    return Material(col, np.clip(nz.norm01(h), 0, 1), rough, depth=2.8, ao=0.45)


@tex("dirt")
def dirt(ctx, seed):
    return dirt_mat(ctx, seed)


@tex("coarse_dirt")
def coarse_dirt(ctx, seed):
    x, y = ctx.x, ctx.y
    m = dirt_mat(ctx, seed, stops=[(0, (80, 56, 38)), (0.5, (112, 80, 56)), (1, (150, 112, 82))], stones=0.0)
    dome, w = pebbles(ctx, nz.sub(seed, "g"), cells=11, round_=0.4, gap=0.08)
    sel = w["rnd"] < 0.45
    g = np.where(sel, dome, 0)
    gcol = ramp(w["rnd"] / 0.45, [(0, (84, 80, 76)), (0.5, (122, 116, 108)), (1, (150, 142, 130))])
    m.albedo = mix(m.albedo, gcol, smoothstep(0.05, 0.3, g))
    m.height = np.maximum(m.height * 0.7, g)
    m.rough = 0.92
    return m


@tex("dirt_with_roots")
def dirt_with_roots(ctx, seed):
    x, y = ctx.x, ctx.y
    m = dirt_mat(ctx, seed)
    wx = (fbm(x, y, 2, 4, seed=nz.sub(seed, "rw")) - 0.5) * 0.3
    roots = ridged(x + wx, y, 3, 3, seed=nz.sub(seed, "roots"), period_y=1)
    rm = smoothstep(0.86, 0.97, roots)
    rc = ramp(fbm(x, y, 8, 3, seed=nz.sub(seed, "rc")), [(0, (120, 92, 64)), (1, (176, 140, 100))])
    m.albedo = mix(m.albedo, rc, rm)
    m.height = np.maximum(m.height, 0.7 + 0.3 * rm) * (rm > 0.1) + m.height * (rm <= 0.1)
    return m


def top_band(ctx, seed, depth_vpx=3.5, jag=1.6, drips=10, drip_len=4.0):
    """Mask for a soil-top overhang on side textures (1 = overhang)."""
    x, y = ctx.x, ctx.y
    W = ctx.w
    edge = (depth_vpx + (fbm(x, y * 0, 8, 3, seed=nz.sub(seed, "j")) - 0.5) * jag * 2) / 16
    m = (y < edge).astype(float)
    r = nz.rng(nz.sub(seed, "drips"))
    for _ in range(drips):
        cx = r.random()
        wv = (0.5 + r.random() * 1.1) / 16
        ln = (depth_vpx * 0.6 + r.random() * drip_len) / 16 + edge.mean()
        slant = (r.random() - 0.5) * 0.25
        dx = x - cx - slant * y
        dx = np.abs((dx + 0.5) % 1.0 - 0.5)
        tip = np.clip(1 - (y / ln), 0, 1)
        m = np.maximum(m, ((dx < wv * tip ** 0.8) & (y < ln)).astype(float))
    return m


# --------------------------------------------------------------------------
# Grass
# --------------------------------------------------------------------------

def grass_canvas(ctx, seed, count_per_px=0.11, length=(4.5, 8.5), width=(0.7, 1.15),
                 vertical=None, base=0.5):
    """Top-down (or hanging) grass blades. Returns (height, value) in [0,1]."""
    W = ctx.w
    s = W / 64.0
    x, y = ctx.x, ctx.y
    hcan = 0.2 + 0.2 * fbm(x, y, 6, 3, seed=nz.sub(seed, "gh"))
    vcan = base + 0.15 * (fbm(x, y, 4, 4, seed=nz.sub(seed, "gv")) - 0.5)
    vcan = vcan.copy()
    r = nz.rng(nz.sub(seed, "blades"))
    count = int(W * W * count_per_px / (s * s) * s * s)
    for _ in range(count):
        cx, cy = r.random() * W, r.random() * W
        if vertical is None:
            ang = r.uniform(0, 2 * np.pi)
        else:
            ang = np.pi / 2 + r.normal(0, vertical)
        L = r.uniform(*length) * s
        w0 = r.uniform(*width) * s
        bx, by = np.cos(ang) * L, np.sin(ang) * L
        tall = r.uniform(0.55, 1.0)
        bright = r.uniform(0.0, 1.0)
        bf = blade_shape(0.0, 0.0, bx, by, w0, w0 * 0.2)

        def fn(DX, DY, bf=bf, tall=tall, bright=bright):
            h, val, m = bf(DX, DY)
            t = val[..., 1]
            v = 0.50 + 0.16 * bright + 0.12 * t + 0.06 * h
            return 0.45 + h * tall * 0.55, v, m

        stamp(hcan, vcan, cx, cy, L + w0 + 1, fn)
    return np.clip(hcan, 0, 1), np.clip(vcan, 0, 1)


@tex("grass_top")
def grass_top(ctx, seed):
    h, v = grass_canvas(ctx, seed)
    col = gray(v * 1.02)
    col = np.clip(col + grain_noise(ctx, seed, 0.015)[..., None], 0, 1)
    return Material(col, h, 0.75 + 0.2 * (1 - h), sss=0.18 * h, depth=2.0, ao=0.3)


@tex("grass_carried")
def grass_carried(ctx, seed):
    m = grass_top(ctx, nz.sub("grass_top"))
    m.albedo = np.clip(m.albedo * GRASS_CARRIED[None, None, :], 0, 1)
    return m


def grass_side_parts(ctx, seed):
    d = dirt_mat(ctx, nz.sub(seed, "dirt"))
    band = top_band(ctx, seed, depth_vpx=3.2, drips=12, drip_len=4.5)
    gh, gv = grass_canvas(ctx, nz.sub(seed, "side"), count_per_px=0.06,
                          length=(4.0, 7.0), vertical=0.3, base=0.5)
    return d, band, gh, gv


@tex("grass_side", exts=("tga",))
def grass_side(ctx, seed):
    d, band, gh, gv = grass_side_parts(ctx, seed)
    col = mix(d.albedo, gray(gv), band)
    h = np.where(band > 0.5, 0.55 + 0.45 * gh, d.height * 0.85)
    m = Material(col, h, np.where(band > 0.5, 0.85, 0.95), sss=band * 0.15,
                 alpha=band, depth=2.8, ao=0.45)
    return m


@tex("grass_side_carried")
def grass_side_carried(ctx, seed):
    d, band, gh, gv = grass_side_parts(ctx, nz.sub("grass_side"))
    g = gray(gv) * GRASS_CARRIED[None, None, :]
    col = mix(d.albedo, g, band)
    h = np.where(band > 0.5, 0.55 + 0.45 * gh, d.height * 0.85)
    return Material(col, h, 0.9, depth=2.8, ao=0.45)


def snow_overhang(ctx, seed, base_mat):
    x, y = ctx.x, ctx.y
    band = top_band(ctx, seed, depth_vpx=4.0, jag=1.2, drips=7, drip_len=2.5)
    sn = fbm(x, y, 16, 3, seed=nz.sub(seed, "sn"))
    scol = ramp(sn, [(0, (214, 226, 236)), (1, (246, 250, 252))])
    col = mix(base_mat.albedo, scol, band)
    h = np.where(band > 0.5, 0.7 + 0.3 * sn, base_mat.height * 0.85)
    return Material(col, h, np.where(band > 0.5, 0.6, 0.95), sss=band * 0.5, depth=2.6, ao=0.4)


@tex("grass_side_snowed", exts=("png", "tga"), tga_alpha=0.0)
def grass_side_snowed(ctx, seed):
    return snow_overhang(ctx, seed, dirt_mat(ctx, nz.sub(seed, "dirt")))


@tex("dirt_podzol_top")
def podzol_top(ctx, seed):
    x, y = ctx.x, ctx.y
    W = ctx.w
    base = dirt_mat(ctx, seed, stops=[(0, (62, 40, 18)), (0.5, (90, 62, 30)), (1, (118, 84, 44))], stones=0.05)
    hcan = base.height * 0.5
    vcan = np.zeros((W, W, 3))
    vcan[:] = base.albedo
    r = nz.rng(nz.sub(seed, "needles"))
    s = W / 64
    for _ in range(int(220 * s * s)):
        cx, cy = r.random() * W, r.random() * W
        ang = r.uniform(0, 2 * np.pi)
        L = r.uniform(3, 6) * s
        c = rgb((150 + r.integers(-20, 30), 92 + r.integers(-15, 20), 40 + r.integers(-10, 10)))
        bf = blade_shape(0, 0, np.cos(ang) * L, np.sin(ang) * L, 0.45 * s, 0.35 * s)

        def fn(DX, DY, bf=bf, c=c):
            h, val, m = bf(DX, DY)
            return 0.5 + 0.5 * h, np.broadcast_to(c, h.shape + (3,)) * (0.8 + 0.2 * h[..., None]), m

        stamp(hcan, vcan, cx, cy, L + 2, fn)
    return Material(np.clip(vcan, 0, 1), hcan, 0.95, depth=2.4, ao=0.45)


@tex("dirt_podzol_side")
def podzol_side(ctx, seed):
    d = dirt_mat(ctx, nz.sub(seed, "dirt"))
    top = podzol_top(ctx, nz.sub(seed, "top"))
    band = top_band(ctx, seed, depth_vpx=3.0, drips=6, drip_len=2.0)
    return Material(mix(d.albedo, top.albedo, band), np.where(band > 0.5, 0.6 + 0.4 * top.height, d.height * 0.85),
                    0.95, depth=2.6, ao=0.45)


@tex("mycelium_top")
def mycelium_top(ctx, seed):
    x, y = ctx.x, ctx.y
    n = fbm(x, y, 5, 5, seed=seed)
    fuzz = fbm(x, y, 24, 3, seed=nz.sub(seed, "fz"))
    spores = smoothstep(0.80, 0.9, fbm(x, y, 20, 2, seed=nz.sub(seed, "sp")))
    col = ramp(0.6 * n + 0.4 * fuzz, [(0, (92, 76, 86)), (0.5, (116, 100, 110)), (1, (138, 124, 132))])
    col = mix(col, rgb((196, 178, 190))[None, None, :], spores * 0.8)
    h = nz.norm01(0.5 * n + 0.5 * fuzz + 0.3 * spores)
    return Material(col, h, 0.97, sss=0.1, depth=2.0, ao=0.4)


@tex("mycelium_side")
def mycelium_side(ctx, seed):
    d = dirt_mat(ctx, nz.sub(seed, "dirt"))
    top = mycelium_top(ctx, nz.sub(seed, "top"))
    band = top_band(ctx, seed, depth_vpx=3.0, drips=8, drip_len=2.5)
    return Material(mix(d.albedo, top.albedo, band), np.where(band > 0.5, 0.6 + 0.4 * top.height, d.height * 0.85),
                    0.96, depth=2.6, ao=0.45)


@tex("grass_path_top")
def grass_path_top(ctx, seed):
    x, y = ctx.x, ctx.y
    m = dirt_mat(ctx, seed, stops=[(0, (118, 92, 54)), (0.5, (146, 118, 74)), (1, (170, 142, 96))], stones=0.35)
    m.height = m.height * 0.6
    tufts = smoothstep(0.78, 0.86, fbm(x, y, 6, 4, seed=nz.sub(seed, "tuft")))
    m.albedo = mix(m.albedo, rgb((96, 112, 52))[None, None, :] * (0.8 + 0.4 * fbm(x, y, 24, 2, seed=1)[..., None]), tufts)
    m.rough = 0.9
    return m


@tex("grass_path_side")
def grass_path_side(ctx, seed):
    d = dirt_mat(ctx, nz.sub(seed, "dirt"))
    top = grass_path_top(ctx, nz.sub(seed, "top"))
    band = top_band(ctx, seed, depth_vpx=3.0, jag=0.8, drips=4, drip_len=1.5)
    return Material(mix(d.albedo, top.albedo, band), np.where(band > 0.5, 0.6 + 0.3 * top.height, d.height * 0.85),
                    0.94, depth=2.6, ao=0.45)


def farmland(ctx, seed, wet):
    x, y = ctx.x, ctx.y
    stops = [(0, (60, 38, 22)), (0.5, (82, 54, 32)), (1, (104, 72, 44))] if wet else \
        [(0, (100, 70, 46)), (0.5, (128, 92, 62)), (1, (152, 112, 78))]
    m = dirt_mat(ctx, seed, stops=stops, stones=0.08)
    furrow = 0.5 + 0.5 * np.cos(y * 4 * 2 * np.pi + (fbm(x, y, 4, 3, seed=nz.sub(seed, "fw")) - 0.5) * 1.5)
    clods = smoothstep(0.0, 0.3, worley(x, y, 12, seed=nz.sub(seed, "cl"))["edge"])
    m.height = nz.norm01(0.55 * furrow + 0.3 * clods + 0.15 * m.height)
    m.albedo = m.albedo * (0.75 + 0.25 * furrow[..., None])
    m.rough = (0.45 + 0.3 * (1 - furrow)) if wet else 0.96
    return m


add("farmland_dry", lambda ctx, seed: farmland(ctx, seed, False))
add("farmland_wet", lambda ctx, seed: farmland(ctx, seed, True))


@tex("mud")
def mud(ctx, seed):
    x, y = ctx.x, ctx.y
    n = fbm(x, y, 3, 6, seed=seed)
    wet = smoothstep(0.42, 0.6, fbm(x, y, 3, 4, seed=nz.sub(seed, "wet")))
    tracks = smoothstep(0.85, 0.95, ridged(x, y, 2, 3, seed=nz.sub(seed, "tr")))
    col = ramp(n, [(0, (46, 40, 44)), (0.5, (62, 56, 60)), (1, (78, 72, 74))])
    col = col * (1 - wet[..., None] * 0.18)
    h = nz.norm01(0.7 * n - 0.4 * wet - 0.2 * tracks)
    rough = 0.6 - 0.48 * wet
    return Material(col, h, rough, depth=2.2, ao=0.3)


@tex("packed_mud")
def packed_mud(ctx, seed):
    x, y = ctx.x, ctx.y
    m = dirt_mat(ctx, seed, stops=[(0, (122, 88, 64)), (0.5, (142, 106, 78)), (1, (162, 124, 94))], stones=0.0, organic=0.2)
    straw = smoothstep(0.88, 0.97, ridged(x, y, 6, 2, seed=nz.sub(seed, "straw"), period_y=24))
    m.albedo = mix(m.albedo, rgb((196, 160, 96))[None, None, :], straw * 0.7)
    m.height = np.clip(m.height * 0.6 + straw * 0.3, 0, 1)
    m.rough = 0.9
    return m


@tex("clay")
def clay(ctx, seed):
    x, y = ctx.x, ctx.y
    n = fbm(x, y, 3, 6, seed=seed)
    smear = fbm(x, y, 2, 3, seed=nz.sub(seed, "sm"), period_y=6)
    col = ramp(0.7 * n + 0.3 * smear, [(0, (142, 148, 162)), (0.5, (160, 166, 178)), (1, (178, 184, 194))])
    h = nz.norm01(0.6 * n + 0.4 * smear)
    return Material(col, h, 0.5 + 0.25 * (1 - n), depth=1.6, ao=0.2)


@tex("moss_block")
def moss_block(ctx, seed):
    x, y = ctx.x, ctx.y
    clumps = worley(x, y, 9, seed=seed, jitter=1.0)
    fuzz = fbm(x, y, 32, 3, seed=nz.sub(seed, "fz"))
    n = fbm(x, y, 4, 4, seed=nz.sub(seed, "n"))
    dome = smoothstep(0.95, 0.1, clumps["f1"])
    h = nz.norm01(0.3 * dome + 0.4 * fuzz + 0.3 * n)
    col = ramp(0.5 * h + 0.3 * n + 0.2 * clumps["rnd"],
               [(0, (52, 70, 26)), (0.45, (82, 104, 40)), (0.8, (104, 126, 50)), (1, (128, 148, 66))])
    return Material(col, h, 0.98, sss=0.35, depth=3.0, ao=0.55)


@tex("pale_moss_block")
def pale_moss_block(ctx, seed):
    m = moss_block(ctx, seed)
    lum = m.albedo.mean(axis=2, keepdims=True)
    m.albedo = np.clip(lum * np.array([0.96, 1.02, 0.94]) * 1.25 + 0.05, 0, 1)
    return m


# --------------------------------------------------------------------------
# Sand, gravel, sandstone
# --------------------------------------------------------------------------

def sand_mat(ctx, seed, stops, ripple=0.35, glint=(250, 245, 230)):
    x, y = ctx.x, ctx.y
    W = ctx.w
    r = nz.rng(nz.sub(seed, "grains"))
    grains = nz.blur(r.random((W, W)), 1, 1) * 0.7 + r.random((W, W)) * 0.3
    warp = fbm(x, y, 2, 3, seed=nz.sub(seed, "rw"))
    rip = 0.5 + 0.5 * np.sin((y * 5 + x * 1 + warp * 1.2) * 2 * np.pi)
    rip = rip ** 1.6 * (0.5 + 0.5 * fbm(x, y, 3, 3, seed=nz.sub(seed, "ra")))
    n = fbm(x, y, 4, 4, seed=seed)
    h = nz.norm01(ripple * rip + 0.45 * grains + 0.2 * n)
    col = ramp(0.5 * n + 0.4 * grains + 0.1 * rip, stops)
    # Quartz glints: rare smooth grains that catch the sun.
    gl = (r.random((W, W)) > 0.985).astype(float)
    col = mix(col, rgb(glint)[None, None, :], gl * 0.6)
    rough = 0.9 - gl * 0.6
    dark = (r.random((W, W)) > 0.99).astype(float)
    col = col * (1 - dark[..., None] * 0.18)
    return Material(np.clip(col, 0, 1), h, rough, depth=1.6, ao=0.3)


SAND = [(0, (196, 182, 136)), (0.5, (218, 206, 162)), (1, (236, 226, 188))]
RED_SAND = [(0, (164, 82, 28)), (0.5, (190, 102, 38)), (1, (212, 124, 56))]


@tex("sand")
def sand(ctx, seed):
    return sand_mat(ctx, seed, SAND)


@tex("red_sand")
def red_sand(ctx, seed):
    return sand_mat(ctx, seed, RED_SAND, glint=(240, 200, 160))


@tex("gravel")
def gravel(ctx, seed):
    x, y = ctx.x, ctx.y
    d1, w1 = pebbles(ctx, seed, cells=8, round_=0.45, gap=0.06)
    d2, w2 = pebbles(ctx, nz.sub(seed, "small"), cells=15, round_=0.4, gap=0.05)
    pal = [(0, (88, 84, 82)), (0.25, (120, 116, 112)), (0.45, (142, 132, 122)), (0.6, (110, 98, 90)),
           (0.8, (150, 146, 142)), (1, (70, 66, 66))]
    c1 = ramp(w1["rnd"], pal)
    c2 = ramp(w2["rnd"], pal)
    big = d1 > 0.15
    col = np.where(big[..., None], c1, c2 * 0.85)
    h = np.where(big, 0.35 + 0.65 * d1, d2 * 0.55)
    surf = fbm(x, y, 16, 3, seed=nz.sub(seed, "s"))
    col = col * (0.85 + 0.3 * surf[..., None])
    gap = (d1 < 0.05) & (d2 < 0.1)
    col = np.where(gap[..., None], rgb((50, 46, 44)), col)
    col = np.clip(col + grain_noise(ctx, seed, 0.03)[..., None], 0, 1)
    return Material(col, h, 0.85 - 0.15 * d1, depth=3.2, ao=0.55)


def sandstone(ctx, seed, stops, kind):
    x, y = ctx.x, ctx.y
    s = sand_mat(ctx, seed, stops, ripple=0.0)
    if kind == "top":
        cr = smoothstep(0.9, 0.98, ridged(x, y, 3, 3, seed=nz.sub(seed, "cr")))
        s.height = nz.norm01(s.height * 0.5 + fbm(x, y, 4, 4, seed=seed) * 0.5 - cr * 0.4)
        s.albedo = s.albedo * (1 - cr[..., None] * 0.2)
    elif kind == "side":
        lay, band = strata(ctx, seed, bands=7, wobble=0.04, sharp=0.6)
        topb = (y < 3.5 / 16).astype(float)
        botb = (y > 13 / 16).astype(float)
        s.albedo = s.albedo * (0.86 + 0.1 * band[..., None] + 0.04 * lay[..., None])
        s.albedo = s.albedo * (1 + 0.06 * topb[..., None]) * (1 - 0.06 * botb[..., None])
        groove = np.exp(-((y - 3.5 / 16) * 16 / 0.5) ** 2)
        s.height = nz.norm01(0.4 * lay + 0.3 * s.height + 0.3 * band - groove * 0.8)
        erosion = smoothstep(0.75, 0.9, fbm(x, y, 6, 4, seed=nz.sub(seed, "er"))) * botb
        s.height = s.height - erosion * 0.4
        s.albedo = s.albedo * (1 - erosion[..., None] * 0.2)
    elif kind == "bottom":
        s.height = nz.norm01(0.6 * s.height + 0.4 * fbm(x, y, 6, 5, seed=seed))
    elif kind == "smooth":
        s.height = s.height * 0.3
        s.rough = 0.75
    elif kind == "carved":
        d = frame_border(ctx, 1)
        frame = smoothstep(1.4, 2.2, d)
        r = np.sqrt((x - 0.5) ** 2 + (y - 0.5) ** 2) * 16
        glyph = np.exp(-((r - 3.0) / 0.5) ** 2) + (np.abs(x - 0.5) * 16 < 0.6) * (np.abs(y - 0.5) * 16 < 5.5) * 1.0
        glyph += (np.abs(y - 0.5) * 16 < 0.6) * (np.abs(x - 0.5) * 16 < 5.5)
        glyph = np.clip(glyph, 0, 1) * frame
        s.height = np.clip(s.height * 0.3 + 0.7 - (1 - frame) * 0.4 * (d > 0.6) - glyph * 0.5, 0, 1)
        s.albedo = s.albedo * (1 - glyph[..., None] * 0.25)
    s.rough = s.rough if kind != "smooth" else 0.75
    return s


for _pre, _st in [("sandstone", SAND), ("red_sandstone", RED_SAND)]:
    add(f"{_pre}_top", (lambda st: lambda ctx, seed: sandstone(ctx, seed, st, "top"))(_st))
    add(f"{_pre}_normal", (lambda st: lambda ctx, seed: sandstone(ctx, seed, st, "side"))(_st))
    add(f"{_pre}_bottom", (lambda st: lambda ctx, seed: sandstone(ctx, seed, st, "bottom"))(_st))
    add(f"{_pre}_smooth", (lambda st: lambda ctx, seed: sandstone(ctx, seed, st, "smooth"))(_st))
    add(f"{_pre}_carved", (lambda st: lambda ctx, seed: sandstone(ctx, seed, st, "carved"))(_st))


# --------------------------------------------------------------------------
# Snow and ice
# --------------------------------------------------------------------------

def snow_mat(ctx, seed, fluff=1.0, sss=0.55):
    x, y = ctx.x, ctx.y
    W = ctx.w
    n = fbm(x, y, 4, 5, seed=seed)
    drift = fbm(x, y, 2, 3, seed=nz.sub(seed, "d"))
    r = nz.rng(nz.sub(seed, "sparkle"))
    sparkle = (r.random((W, W)) > 0.988).astype(float)
    col = ramp(0.6 * n + 0.4 * drift, [(0, (218, 228, 238)), (0.5, (236, 242, 248)), (1, (250, 252, 255))])
    col = mix(col, np.ones(3)[None, None, :], sparkle * 0.6)
    h = nz.norm01(0.6 * n + 0.4 * drift) * fluff
    rough = 0.62 - sparkle * 0.5
    return Material(col, h, rough, sss=sss, depth=1.6, ao=0.25)


@tex("snow")
def snow(ctx, seed):
    return snow_mat(ctx, seed)


@tex("powder_snow")
def powder_snow(ctx, seed):
    m = snow_mat(ctx, seed, fluff=1.0, sss=0.7)
    m.rough = np.clip(m.rough + 0.15, 0, 1)
    return m


def ice_mat(ctx, seed, base, alpha=None, rough=0.04, bubbles=True, cracks=1.0, frost=0.0):
    x, y = ctx.x, ctx.y
    n = fbm(x, y, 3, 5, seed=seed)
    cr = ridged(x, y, 2, 4, seed=nz.sub(seed, "cr"))
    cmask = smoothstep(0.88, 0.98, cr) * cracks
    col = ramp(n, [(0, tuple(np.array(base) * 0.85)), (0.6, base), (1, tuple(np.minimum(np.array(base) * 1.1, 255)))])
    col = mix(col, np.ones(3)[None, None, :] * 0.95, cmask * 0.7)
    h = nz.norm01(0.3 * n - 0.6 * cmask)
    rgh = rough + cmask * 0.25
    if bubbles:
        w = worley(x, y, 12, seed=nz.sub(seed, "b"))
        bub = np.where(w["rnd"] > 0.75, smoothstep(0.25, 0.1, w["f1"]), 0)
        col = mix(col, np.ones(3)[None, None, :], bub * 0.35)
        h = h + bub * 0.15
    if frost > 0:
        fr = fbm(x, y, 8, 5, seed=nz.sub(seed, "fr"))
        col = mix(col, rgb((236, 244, 255))[None, None, :], smoothstep(0.4, 0.8, fr) * frost)
        rgh = rgh + frost * 0.25 * fr
        h = h * 0.6 + fr * 0.4 * frost
    return Material(col, np.clip(h, 0, 1), rgh, sss=0.25, alpha=alpha, depth=2.0, ao=0.1)


@tex("ice")
def ice(ctx, seed):
    return ice_mat(ctx, seed, (150, 188, 250), alpha=190 / 255, rough=0.03)


@tex("ice_packed")
def ice_packed(ctx, seed):
    return ice_mat(ctx, seed, (160, 190, 238), rough=0.18, bubbles=False, cracks=0.6, frost=0.6)


@tex("blue_ice")
def blue_ice(ctx, seed):
    return ice_mat(ctx, seed, (112, 164, 250), rough=0.05, bubbles=True, cracks=0.8)
