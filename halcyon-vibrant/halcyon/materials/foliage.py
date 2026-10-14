"""Leaves, grass tufts and ferns: alpha-cut, biome-tinted, subsurface-lit."""

from __future__ import annotations

import numpy as np

from .. import noise as nz
from ..lib import blade_shape, gray, leaf_shape, mix, rgb, stamp
from ..noise import fbm, smoothstep
from ..pbr import Material
from ..registry import add

# Inventory ("carried") tints approximating each species' default foliage colour.
CARRIED = {
    "oak": (0.36, 0.64, 0.17), "spruce": (0.38, 0.56, 0.38), "birch": (0.50, 0.66, 0.33),
    "jungle": (0.30, 0.66, 0.11), "acacia": (0.46, 0.60, 0.15), "big_oak": (0.36, 0.64, 0.17),
    "mangrove": (0.46, 0.62, 0.18),
}

LEAF_STYLE = {
    # count, length, width, curl
    "oak": (115, (8, 12), (5.0, 7.0), 0.15),
    "big_oak": (130, (8, 11), (5.0, 7.0), 0.15),
    "birch": (130, (6, 9), (4.5, 6.0), 0.1),
    "jungle": (50, (12, 18), (7.0, 10.0), 0.25),
    "acacia": (220, (5, 7), (3.0, 4.0), 0.05),
    "mangrove": (170, (8, 11), (4.5, 6.0), 0.1),
    "azalea": (155, (7, 10), (5.0, 7.0), 0.1),
    "cherry": (200, (6, 9), (5.0, 6.5), 0.05),
    "pale_oak": (160, (7, 11), (4.5, 6.5), 0.15),
}


def leaf_canopy(ctx, seed, style):
    W = ctx.w
    s = W / 64.0
    count, lr, wr, curl = LEAF_STYLE[style]
    hcan = np.zeros((W, W))
    vcan = np.zeros((W, W, 3))
    r = nz.rng(nz.sub(seed, "leaves"))
    # Twigs behind the leaves give the canopy a structure.
    for _ in range(int(6 * s)):
        cx, cy = r.random() * W, r.random() * W
        ang = r.uniform(0, 2 * np.pi)
        L = r.uniform(10, 22) * s
        bf = blade_shape(0, 0, np.cos(ang) * L, np.sin(ang) * L, 0.8 * s, 0.4 * s)

        def tw(DX, DY, bf=bf):
            h, val, m = bf(DX, DY)
            return 0.05 + h * 0.1, np.dstack([np.zeros_like(h) - 1, h, h]), m

        stamp(hcan, vcan, cx, cy, L + 2, tw)
    for i in range(int(count * s * s)):
        cx, cy = r.random() * W, r.random() * W
        L = r.uniform(*lr) * s
        Wd = r.uniform(*wr) * s
        ang = r.uniform(0, 2 * np.pi)
        layer = r.random()
        tone = r.random()
        fn0 = leaf_shape(L, Wd, ang, curl=curl * r.uniform(-1, 1))

        def fn(DX, DY, fn0=fn0, layer=layer, tone=tone):
            dome, val, m = fn0(DX, DY)
            h = 0.25 + 0.55 * layer + 0.2 * dome
            v = np.dstack([np.full(dome.shape, tone), val[..., 1], dome])
            return h * (m > 0), v, m

        stamp(hcan, vcan, cx, cy, L * 0.6 + 2, fn)
    alpha = (hcan > 0.0).astype(float)
    return hcan, vcan, alpha


def leaves(ctx, seed, style, tint=None, base_col=None, flowers=False, opaque=False):
    x, y = ctx.x, ctx.y
    hcan, vcan, alpha = leaf_canopy(ctx, seed, style)
    tone, vein, dome = vcan[..., 0], vcan[..., 1], vcan[..., 2]
    twig = tone < 0
    lum = 0.48 + 0.22 * tone + 0.14 * dome + 0.12 * hcan - 0.10 * vein
    lum = lum * (0.92 + 0.16 * fbm(x, y, 4, 3, seed=nz.sub(seed, "lt")))
    if base_col is None:
        col = gray(lum)
    else:
        col = rgb(base_col)[None, None, :] * (lum[..., None] / 0.6)
    col = np.where(twig[..., None], rgb((70, 52, 34)) * (0.7 + 0.5 * vein[..., None]), col)
    if flowers:
        fl = smoothstep(0.75, 0.82, fbm(x, y, 8, 3, seed=nz.sub(seed, "fl"))) * alpha
        col = mix(col, rgb((206, 112, 196))[None, None, :] * (0.85 + 0.3 * dome[..., None]), fl)
    if tint is not None:
        col = col * np.array(tint)[None, None, :] / 0.62
    rough = 0.52 + 0.2 * vein + 0.25 * twig
    sss = np.where(twig, 0.0, 0.72 + 0.2 * dome) * alpha
    if opaque:
        bg = 0.17 if base_col is None else 0.3
        back = gray(np.full(lum.shape, bg)) if base_col is None else rgb(base_col)[None, None, :] * bg
        if tint is not None:
            back = back * np.array(tint)[None, None, :] / 0.62
        col = np.where(alpha[..., None] > 0.5, col, back)
        a = None
        h = np.where(alpha > 0.5, hcan, 0.0)
    else:
        a = alpha
        h = hcan
    return Material(np.clip(col, 0, 1), h, rough, sss=sss, alpha=a, depth=2.6, ao=0.45)


TINTED = {
    "oak": "leaves_oak", "spruce": "leaves_spruce", "birch": "leaves_birch",
    "jungle": "leaves_jungle", "acacia": "leaves_acacia", "big_oak": "leaves_big_oak",
}


def needles(ctx, seed, tint=None, opaque=False):
    """Spruce: dense needle sprays along little branchlets."""
    W = ctx.w
    s = W / 64.0
    x, y = ctx.x, ctx.y
    hcan = np.zeros((W, W))
    vcan = np.zeros((W, W, 3))
    r = nz.rng(nz.sub(seed, "needles"))
    for _ in range(int(58 * s * s)):
        bx, by = r.random() * W, r.random() * W
        ang = r.uniform(0, 2 * np.pi)
        L = r.uniform(10, 18) * s
        layer = r.random()
        tone = r.random()
        for k in range(int(L / (1.4 * s))):
            t = k / max(L / (1.4 * s), 1)
            px_, py_ = bx + np.cos(ang) * L * t, by + np.sin(ang) * L * t
            for side in (-1, 1):
                a2 = ang + side * r.uniform(0.6, 1.1)
                nl = r.uniform(3.5, 5.5) * s * (1 - 0.4 * t)
                bf = blade_shape(0, 0, np.cos(a2) * nl, np.sin(a2) * nl, 0.55 * s, 0.25 * s)

                def fn(DX, DY, bf=bf, layer=layer, tone=tone, t=t):
                    h, val, m = bf(DX, DY)
                    return (0.3 + 0.5 * layer + 0.2 * h) * (m > 0), \
                        np.dstack([np.full(h.shape, tone), val[..., 2], h]), m

                stamp(hcan, vcan, px_, py_, nl + 2, fn)
    alpha = (hcan > 0).astype(float)
    tone, edge, dome = vcan[..., 0], vcan[..., 1], vcan[..., 2]
    lum = 0.42 + 0.2 * tone + 0.18 * dome + 0.12 * hcan
    col = gray(lum)
    if tint is not None:
        col = col * np.array(tint)[None, None, :] / 0.62
    sss = (0.6 + 0.2 * dome) * alpha
    if opaque:
        back = gray(np.full(lum.shape, 0.14))
        if tint is not None:
            back = back * np.array(tint)[None, None, :] / 0.62
        col = np.where(alpha[..., None] > 0.5, col, back)
        return Material(np.clip(col, 0, 1), hcan * alpha, 0.6, sss=sss, depth=2.4, ao=0.5)
    return Material(np.clip(col, 0, 1), hcan, 0.6, sss=sss, alpha=alpha, depth=2.4, ao=0.5)


def _bind(fn, *a, **kw):
    return lambda ctx, seed: fn(ctx, seed, *a, **kw)


for sp, name in TINTED.items():
    if sp == "spruce":
        add(name, _bind(needles), exts=("tga",))
        add(name + "_carried", lambda ctx, seed: needles(ctx, nz.sub("leaves_spruce"), tint=CARRIED["spruce"]),
            exts=("tga",))
        add(name + "_opaque", lambda ctx, seed: needles(ctx, nz.sub("leaves_spruce"), opaque=True))
        continue
    add(name, _bind(leaves, sp), exts=("tga",))
    add(name + "_carried", (lambda sp, name: lambda ctx, seed: leaves(ctx, nz.sub(name), sp, tint=CARRIED[sp]))(sp, name),
        exts=("tga",))
    add(name + "_opaque", (lambda sp, name: lambda ctx, seed: leaves(ctx, nz.sub(name), sp, opaque=True))(sp, name))

add("mangrove_leaves", _bind(leaves, "mangrove"), exts=("tga",))
add("mangrove_leaves_carried", lambda ctx, seed: leaves(ctx, nz.sub("mangrove_leaves"), "mangrove",
                                                        tint=CARRIED["mangrove"]), exts=("tga",))
add("mangrove_leaves_opaque", lambda ctx, seed: leaves(ctx, nz.sub("mangrove_leaves"), "mangrove", opaque=True))

# Untinted species carry their own colour.
add("cherry_leaves", _bind(leaves, "cherry", base_col=(232, 164, 196)), exts=("png", "tga"))
add("cherry_leaves_opaque", lambda ctx, seed: leaves(ctx, nz.sub("cherry_leaves"), "cherry",
                                                     base_col=(232, 164, 196), opaque=True))
add("azalea_leaves", _bind(leaves, "azalea", base_col=(92, 120, 38)), exts=("png", "tga"))
add("azalea_leaves_opaque", lambda ctx, seed: leaves(ctx, nz.sub("azalea_leaves"), "azalea",
                                                     base_col=(92, 120, 38), opaque=True))
add("azalea_leaves_flowers", _bind(leaves, "azalea", base_col=(92, 120, 38), flowers=True), exts=("png", "tga"))
add("azalea_leaves_flowers_opaque", lambda ctx, seed: leaves(ctx, nz.sub("azalea_leaves_flowers"), "azalea",
                                                             base_col=(92, 120, 38), flowers=True, opaque=True))
add("pale_oak_leaves", _bind(leaves, "pale_oak", base_col=(128, 134, 116)), exts=("tga",))
add("pale_oak_leaves_opaque", lambda ctx, seed: leaves(ctx, nz.sub("pale_oak_leaves"), "pale_oak",
                                                       base_col=(128, 134, 116), opaque=True))


# --------------------------------------------------------------------------
# Grass tufts and ferns (cross-plane plants)
# --------------------------------------------------------------------------

def _curve(p0, p1, p2, n):
    t = np.linspace(0, 1, n)[:, None]
    return (1 - t) ** 2 * p0 + 2 * (1 - t) * t * p1 + t ** 2 * p2


def tuft(ctx, seed, blades=85, height=(0.55, 0.98), spread=0.55, base_y=1.0,
         from_top=False, tint=None):
    """Grass blades rising from the bottom edge (or continuing upward from a
    lower half when from_top=True)."""
    W = ctx.w
    s = W / 64.0
    hcan = np.zeros((W, W))
    vcan = np.zeros((W, W))
    r = nz.rng(nz.sub(seed, "tuft"))
    for _ in range(blades):
        x0 = 0.5 + r.normal(0, spread * 0.35)
        lean = r.normal(0, 0.3)
        ht = r.uniform(*height) * (1 - 0.3 * abs(lean))
        p0 = np.array([x0 * W, base_y * W + (2 * s if not from_top else W * 0.2)])
        p2 = np.array([(x0 + lean) * W, (base_y - ht) * W])
        p1 = np.array([(x0 + lean * 0.05) * W, (base_y - ht * 0.75) * W])
        pts = _curve(p0, p1, p2, 14)
        w0 = r.uniform(1.4, 2.4) * s
        tone = r.random()
        layer = r.random()
        for k in range(len(pts) - 1):
            a, b = pts[k], pts[k + 1]
            t0 = k / (len(pts) - 1)
            wa = w0 * (1 - t0) + 0.2 * s
            wb = w0 * (1 - (k + 1) / (len(pts) - 1)) + 0.2 * s
            cx, cy = a
            bf = blade_shape(0, 0, b[0] - a[0], b[1] - a[1], wa, wb)

            def fn(DX, DY, bf=bf, tone=tone, layer=layer, t0=t0):
                h, val, m = bf(DX, DY)
                v = 0.45 + 0.25 * tone + 0.25 * t0 + 0.05 * h
                return (0.3 + 0.6 * layer + 0.1 * h) * (m > 0), v, m

            stamp(hcan, vcan, cx, cy, np.hypot(*(b - a)) + wa + 2, fn, wrap=False)
    alpha = (hcan > 0).astype(float)
    col = gray(vcan)
    if tint is not None:
        col = col * np.array(tint)[None, None, :]
    return Material(np.clip(col, 0, 1), hcan, 0.55, sss=0.8 * alpha, alpha=alpha, depth=1.8, ao=0.2)


def fern(ctx, seed, fronds=8, height=0.9, base_y=1.0, tint=None):
    W = ctx.w
    s = W / 64.0
    hcan = np.zeros((W, W))
    vcan = np.zeros((W, W))
    r = nz.rng(nz.sub(seed, "fern"))
    for f in range(fronds):
        ang = np.pi / 2 + (f - (fronds - 1) / 2) * 0.32 + r.normal(0, 0.08)
        L = r.uniform(0.6, 1.0) * height * W
        p0 = np.array([0.5 * W, base_y * W])
        p2 = p0 + np.array([-np.cos(ang) * L, -np.sin(ang) * L * 0.95])
        p1 = p0 + np.array([-np.cos(ang) * L * 0.4, -L * 0.75])
        pts = _curve(p0, p1, p2, 20)
        layer = r.random()
        for k in range(len(pts) - 1):
            a, b = pts[k], pts[k + 1]
            t0 = k / (len(pts) - 1)
            d = b - a
            nrm = np.array([-d[1], d[0]]) / (np.hypot(*d) + 1e-6)
            rb = blade_shape(0, 0, d[0], d[1], 0.7 * s, 0.6 * s)

            def fr(DX, DY, rb=rb, layer=layer):
                h, val, m = rb(DX, DY)
                return (0.4 + 0.5 * layer) * (m > 0), 0.35, m

            stamp(hcan, vcan, a[0], a[1], np.hypot(*d) + 2, fr, wrap=False)
            if 0.08 < t0 < 0.97:
                for side in (-1, 1):
                    ll = (1 - t0) * 9 * s + 2.0 * s
                    tip = a + nrm * side * ll + d * 0.6
                    lf = blade_shape(0, 0, tip[0] - a[0], tip[1] - a[1], 2.0 * s * (1 - t0 * 0.5), 0.5 * s)
                    tone = r.random()

                    def lfn(DX, DY, lf=lf, layer=layer, tone=tone, t0=t0):
                        h, val, m = lf(DX, DY)
                        return (0.45 + 0.5 * layer + 0.05 * h) * (m > 0), 0.5 + 0.2 * tone + 0.15 * t0, m

                    stamp(hcan, vcan, a[0], a[1], ll + 3 * s, lfn, wrap=False)
    alpha = (hcan > 0).astype(float)
    col = gray(vcan)
    if tint is not None:
        col = col * np.array(tint)[None, None, :]
    return Material(np.clip(col, 0, 1), hcan, 0.55, sss=0.8 * alpha, alpha=alpha, depth=1.8, ao=0.2)


GREEN = (0.53, 0.80, 0.30)
add("tallgrass", lambda ctx, seed: tuft(ctx, seed, height=(0.4, 0.85)), exts=("png", "tga"))
add("tallgrass_carried", lambda ctx, seed: tuft(ctx, nz.sub("tallgrass"), height=(0.4, 0.85), tint=GREEN),
    exts=("tga",))
add("double_plant_grass_bottom", lambda ctx, seed: tuft(ctx, seed, blades=70, height=(0.8, 1.3), spread=0.7),
    exts=("tga",))
add("double_plant_grass_top", lambda ctx, seed: tuft(ctx, seed, blades=40, height=(0.3, 0.9), from_top=True),
    exts=("tga",))
add("double_plant_grass_carried", lambda ctx, seed: tuft(ctx, nz.sub("double_plant_grass_bottom"), blades=60,
                                                         height=(0.6, 0.98), tint=GREEN))
add("fern", lambda ctx, seed: fern(ctx, seed, height=0.75), exts=("tga",))
add("fern_carried", lambda ctx, seed: fern(ctx, nz.sub("fern"), height=0.75, tint=GREEN), exts=("tga",))
add("double_plant_fern_bottom", lambda ctx, seed: fern(ctx, seed, fronds=11, height=1.15), exts=("tga",))
add("double_plant_fern_top", lambda ctx, seed: fern(ctx, seed, fronds=8, height=0.8), exts=("tga",))
add("double_plant_fern_carried", lambda ctx, seed: fern(ctx, nz.sub("double_plant_fern_bottom"), fronds=7,
                                                        height=0.85, tint=GREEN))
