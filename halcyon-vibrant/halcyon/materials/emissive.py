"""Light-emitting blocks. Emissive drives glow and bloom in Vibrant Visuals;
the light *radius* still comes from the block's own light level."""

from __future__ import annotations

import numpy as np

from .. import noise as nz
from ..lib import bevel, bricks, frame_border, mix, rgb
from ..noise import fbm, ramp, smoothstep, worley
from ..pbr import Material
from ..registry import add, tex


@tex("glowstone")
def glowstone(ctx, seed):
    x, y = ctx.x, ctx.y
    w = worley(x, y, 9, seed=seed, jitter=1.0, metric="cheby")
    w2 = worley(x, y, 18, seed=nz.sub(seed, "2"), jitter=1.0, metric="cheby")
    n = fbm(x, y, 6, 3, seed=nz.sub(seed, "n"))
    bright = np.clip(0.55 * w["rnd"] + 0.25 * w2["rnd"] + 0.2 * n, 0, 1)
    gap = 1 - smoothstep(0.0, 0.06, w["edge"])
    glow = smoothstep(0.35, 0.85, bright) * (1 - gap)
    col = ramp(bright, [(0, (96, 62, 30)), (0.4, (170, 120, 60)), (0.75, (238, 196, 110)), (1, (255, 240, 180))])
    col = col * (1 - gap[..., None] * 0.6)
    h = np.clip(0.4 + 0.5 * bright - gap * 0.4, 0, 1)
    return Material(col, h, 0.35, emissive=0.15 + 0.85 * glow, sss=0.0, depth=2.4, ao=0.3)


@tex("sea_lantern", frames=5)
def sea_lantern(ctx, seed):
    x, y = ctx.x, ctx.y
    frames = []
    hs, es, rs = [], [], []
    b = bricks(ctx, 2, 2, offset=0.0, mortar=1.6, seed=seed, chip=0.0)
    prof = bevel(b["d"], 1.0 * ctx.px) * b["inside"]
    rim = 1 - b["inside"]
    for k in range(5):
        t = k / 5.0
        ox, oy = np.cos(2 * np.pi * t) * 0.12, np.sin(2 * np.pi * t) * 0.12
        flow = fbm(x + ox, y + oy, 3, 4, seed=nz.sub(seed, "flow"))
        core = smoothstep(0.25, 0.85, flow) * prof
        col = ramp(0.35 + 0.65 * core, [(0, (120, 170, 160)), (0.5, (190, 228, 218)), (1, (246, 255, 252))])
        col = mix(col, rgb((86, 128, 120))[None, None, :] * (0.9 + 0.2 * flow[..., None]), rim)
        frames.append(col)
        hs.append(np.clip(0.4 + 0.5 * prof - 0.3 * rim, 0, 1))
        es.append((0.55 + 0.45 * core) * (1 - rim) + rim * 0.1)
        rs.append(np.where(rim > 0.5, 0.6, 0.12))
    return Material(np.concatenate(frames), np.concatenate(hs), np.concatenate(rs),
                    emissive=np.concatenate(es), sss=0.0, depth=2.2, ao=0.2)


def redstone_lamp(ctx, seed, on):
    x, y = ctx.x, ctx.y
    d = frame_border(ctx, 1)
    frame = 1 - smoothstep(2.4, 3.0, d)
    n = fbm(x, y, 6, 4, seed=seed)
    w = worley(x, y, 5, seed=nz.sub(seed, "w"), jitter=0.8)
    cells = smoothstep(0.0, 0.15, w["edge"])
    if on:
        inner = ramp(0.5 * cells + 0.5 * n, [(0, (160, 90, 40)), (0.5, (236, 170, 90)), (1, (255, 236, 180))])
        emis = (0.55 + 0.45 * cells) * (1 - frame)
    else:
        inner = ramp(0.5 * cells + 0.5 * n, [(0, (50, 30, 20)), (0.5, (82, 52, 34)), (1, (110, 76, 52))])
        emis = 0.0
    fcol = ramp(n, [(0, (96, 54, 30)), (0.5, (126, 74, 44)), (1, (150, 96, 60))])
    col = mix(inner, fcol, frame)
    h = np.where(frame > 0.5, 0.8 + 0.2 * n, 0.4 + 0.2 * cells)
    rough = np.where(frame > 0.5, 0.75, 0.15)
    return Material(np.clip(col, 0, 1), h, rough, emissive=emis, depth=2.4, ao=0.35)


add("redstone_lamp_on", lambda ctx, seed: redstone_lamp(ctx, seed, True))
add("redstone_lamp_off", lambda ctx, seed: redstone_lamp(ctx, seed, False))


@tex("shroomlight")
def shroomlight(ctx, seed):
    x, y = ctx.x, ctx.y
    w = worley(x, y, 8, seed=seed, jitter=1.0)
    n = fbm(x, y, 5, 5, seed=nz.sub(seed, "n"))
    spots = smoothstep(0.35, 0.12, w["f1"]) * (w["rnd"] > 0.4)
    flesh = ramp(n, [(0, (196, 90, 34)), (0.5, (236, 138, 62)), (1, (250, 176, 96))])
    col = mix(flesh, rgb((255, 232, 170))[None, None, :], spots)
    h = nz.norm01(0.6 * n + 0.4 * spots)
    return Material(np.clip(col, 0, 1), h, 0.55, emissive=0.45 + 0.55 * np.maximum(spots, n * 0.5), sss=0.0,
                    depth=2.2, ao=0.3)


FROG = {
    "ochre": ((248, 238, 196), (232, 196, 90)),
    "verdant": ((232, 246, 226), (130, 200, 110)),
    "pearlescent": ((246, 236, 240), (206, 150, 210)),
}


def froglight(ctx, seed, kind, top):
    x, y = ctx.x, ctx.y
    pale, accent = FROG[kind]
    n = fbm(x, y, 4, 4, seed=seed)
    if top:
        r = np.maximum(np.abs(x - 0.5), np.abs(y - 0.5)) * 16
        pat = 0.5 + 0.5 * np.cos(r * 1.2 + n * 2)
    else:
        pat = 0.5 + 0.5 * np.cos(x * 2 * np.pi * 3 + (n - 0.5) * 3)
    col = mix(rgb(pale)[None, None, :] * np.ones(x.shape + (3,)), rgb(accent)[None, None, :] * np.ones(x.shape + (3,)),
              smoothstep(0.55, 0.9, pat) * 0.8)
    d = frame_border(ctx, 1)
    rim = 1 - smoothstep(0.8, 1.4, d)
    col = col * (1 - rim[..., None] * 0.25)
    h = 0.5 + 0.2 * pat + 0.2 * (1 - rim)
    return Material(np.clip(col, 0, 1), h, 0.4, emissive=0.85 - 0.3 * rim, sss=0.0, depth=1.8, ao=0.2)


for _k in FROG:
    add(f"{_k}_froglight_side", (lambda k: lambda ctx, seed: froglight(ctx, seed, k, False))(_k))
    add(f"{_k}_froglight_top", (lambda k: lambda ctx, seed: froglight(ctx, seed, k, True))(_k))


@tex("magma", frames=3)
def magma(ctx, seed):
    x, y = ctx.x, ctx.y
    w = worley(x, y, 5, seed=seed, jitter=0.9)
    n = fbm(x, y, 6, 4, seed=nz.sub(seed, "n"))
    crack = 1 - smoothstep(0.0, 0.09 + 0.05 * n, w["edge"])
    cols, hs, es = [], [], []
    for k in range(3):
        pulse = 0.75 + 0.25 * np.cos(2 * np.pi * k / 3 + w["rnd"] * 6)
        heat = np.clip(crack * pulse + smoothstep(0.7, 0.9, n) * 0.3, 0, 1)
        crust = ramp(0.6 * n + 0.4 * w["rnd"], [(0, (40, 14, 10)), (0.5, (72, 26, 16)), (1, (108, 44, 24))])
        hot = ramp(heat, [(0, (140, 30, 4)), (0.5, (240, 110, 20)), (1, (255, 214, 110))])
        cols.append(mix(crust, hot, heat))
        hs.append(np.clip(0.75 - crack * 0.5 + 0.15 * n, 0, 1))
        es.append(heat)
    return Material(np.concatenate(cols), np.concatenate(hs), 0.7, emissive=np.concatenate(es), depth=3.0, ao=0.4)
