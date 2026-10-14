"""PBR material container and the writers that turn it into Bedrock files.

A Material holds float fields in [0, 1]:
  albedo    (H, W, 3)  base colour, linear-ish sRGB as authored
  height    (H, W)     0 = deepest, 1 = highest; drives the normal map
  rough     (H, W)     perceptual roughness
  metal     (H, W)     metalness (binary in practice)
  emissive  (H, W)     emissive strength
  sss       (H, W)     subsurface scattering amount (non-metals only)
  alpha     (H, W)     optional opacity / tint mask

Output per texture (name = the vanilla texture name it replaces):
  <name>.png|.tga         colour (RGB or RGBA)
  <name>_nrm.tga          normal map, DirectX convention (green = -Y), the
                          same convention Mojang's own water/lava normals use
  <name>_mers.tga         RGBA = metalness, emissive, roughness, subsurface
  <name>.texture_set.json
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, field

import numpy as np
from PIL import Image

from . import noise as nz


@dataclass
class Material:
    albedo: np.ndarray
    height: np.ndarray
    rough: object = 0.85
    metal: object = 0.0
    emissive: object = 0.0
    sss: object = 0.0
    alpha: object = None
    depth: float = 3.0          # normal strength: pixels of relief per unit height
    ao: float = 0.35            # cavity darkening baked into albedo
    meta: dict = field(default_factory=dict)

    @property
    def shape(self):
        return self.height.shape


def _full(v, shape):
    if v is None:
        return None
    a = np.asarray(v, dtype=float)
    if a.ndim == 0:
        return np.full(shape, float(a))
    return a


# --------------------------------------------------------------------------
# Derived maps
# --------------------------------------------------------------------------

def normal_from_height(h, depth=3.0, frames=1):
    """Tangent-space normal map (DirectX / Y-down) from a height field.

    `depth` scales slopes: a full 0->1 height step across one pixel tilts the
    normal by atan(depth). Flipbook textures are processed frame by frame so
    the wrap stays inside each frame.
    """
    H, W = h.shape
    fh = H // frames
    out = np.empty((H, W, 3))
    for f in range(frames):
        fr = h[f * fh:(f + 1) * fh]
        # Sobel on a wrapped field gives smoother, less aliased gradients
        # than a plain central difference at 64px.
        def r(a, dy, dx):
            return np.roll(np.roll(a, dy, axis=0), dx, axis=1)
        gx = ((r(fr, 1, -1) + 2 * r(fr, 0, -1) + r(fr, -1, -1))
              - (r(fr, 1, 1) + 2 * r(fr, 0, 1) + r(fr, -1, 1))) / 8.0
        grow = ((r(fr, -1, 1) + 2 * r(fr, -1, 0) + r(fr, -1, -1))
                - (r(fr, 1, 1) + 2 * r(fr, 1, 0) + r(fr, 1, -1))) / 8.0
        # gx = dh/dx, grow = dh/drow (row index grows downward)
        nx = -gx * depth
        ny_dx = -grow * depth          # DirectX green: -(dh/dy_up) flipped
        nzv = np.ones_like(nx)
        inv = 1.0 / np.sqrt(nx * nx + ny_dx * ny_dx + nzv * nzv)
        out[f * fh:(f + 1) * fh, :, 0] = nx * inv
        out[f * fh:(f + 1) * fh, :, 1] = ny_dx * inv
        out[f * fh:(f + 1) * fh, :, 2] = nzv * inv
    return out


def cavity(h, radius=2, frames=1):
    """Approximate ambient occlusion: how far a texel sits below its
    neighbourhood average."""
    H, W = h.shape
    fh = H // frames
    out = np.empty_like(h)
    for f in range(frames):
        fr = h[f * fh:(f + 1) * fh]
        b = nz.blur(fr, radius, passes=2)
        out[f * fh:(f + 1) * fh] = np.clip(b - fr, 0, 1)
    return out


# --------------------------------------------------------------------------
# Writers
# --------------------------------------------------------------------------

def _u8(a):
    return np.clip(np.round(np.asarray(a) * 255.0), 0, 255).astype(np.uint8)


def _save(img: Image.Image, path: str):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if path.endswith(".tga"):
        img.save(path, compression=None)
    else:
        img.save(path, optimize=True)


def calibrate(alb, alpha, target, frames=1, strength=1.0):
    """Tone the albedo so its mean colour (opaque texels of the first frame)
    matches `target` (0-255 RGB). A per-channel gamma is solved instead of a
    plain gain so highlights roll off rather than clip, and detail survives."""
    fh = alb.shape[0] // frames
    first = alb[:fh]
    mask = np.ones(first.shape[:2], bool) if alpha is None else (alpha[:fh] > 0.5)
    if mask.sum() < 8:
        return alb
    out = alb.copy()
    for c in range(3):
        v = np.clip(first[..., c][mask], 1e-4, 1.0)
        want = np.clip(target[c] / 255.0, 0.01, 0.99)
        cur = v.mean()
        want = cur + (want - cur) * strength
        lo, hi = 0.2, 5.0
        for _ in range(40):
            g = np.sqrt(lo * hi)
            if (v ** g).mean() > want:
                lo = g
            else:
                hi = g
        out[..., c] = np.clip(alb[..., c], 0, 1) ** np.sqrt(lo * hi)
    return out


def finalize(m: Material, frames=1, target=None):
    """Bake AO into albedo, tone-match to the vanilla palette and expand
    scalar channels."""
    shape = m.shape
    h = np.clip(m.height, 0, 1)
    alb = np.clip(m.albedo, 0, 1)
    if m.ao > 0:
        cav = cavity(h, 2, frames)
        occl = np.clip(1.0 - cav * m.ao * 6.0, 0.55, 1.0)
        alb = alb * occl[..., None]
    if target is not None:
        alb = calibrate(alb, _full(m.alpha, shape), target, frames)
    rough = np.clip(_full(m.rough, shape), 0.0, 1.0)
    metal = np.clip(_full(m.metal, shape), 0.0, 1.0)
    emis = np.clip(_full(m.emissive, shape), 0.0, 1.0)
    sss = np.clip(_full(m.sss, shape), 0.0, 1.0)
    # Metalness and subsurface are mutually exclusive per texel; the engine
    # keeps the larger one. Make that explicit so the data matches intent.
    sss = np.where(metal > sss, 0.0, sss)
    metal = np.where(metal > sss, metal, 0.0)
    alpha = _full(m.alpha, shape)
    return alb, h, rough, metal, emis, sss, alpha


def write(m: Material, outdir: str, name: str, color_exts=("png",),
          frames=1, rel_dir="textures/blocks", tga_alpha_override=None, target=None):
    """Write all layers for one texture and return the list of files."""
    alb, h, rough, metal, emis, sss, alpha = finalize(m, frames, target)
    base = os.path.join(outdir, rel_dir, name)
    files = []

    col = _u8(alb)
    for ext in color_exts:
        a = alpha
        if ext == "tga" and tga_alpha_override is not None:
            a = _full(tga_alpha_override, h.shape)
        if a is not None:
            img = Image.fromarray(np.dstack([col, _u8(a)]), "RGBA")
        else:
            img = Image.fromarray(col, "RGB")
        _save(img, f"{base}.{ext}")
        files.append(f"{base}.{ext}")

    n = normal_from_height(h, m.depth, frames)
    nimg = Image.fromarray(_u8(n * 0.5 + 0.5), "RGB")
    _save(nimg, f"{base}_nrm.tga")
    files.append(f"{base}_nrm.tga")

    mers = np.dstack([_u8(metal), _u8(emis), _u8(rough), _u8(sss)])
    _save(Image.fromarray(mers, "RGBA"), f"{base}_mers.tga")
    files.append(f"{base}_mers.tga")

    leaf = os.path.basename(name)
    ts = {
        "format_version": "1.21.30",
        "minecraft:texture_set": {
            "color": leaf,
            "metalness_emissive_roughness_subsurface": f"{leaf}_mers",
            "normal": f"{leaf}_nrm",
        },
    }
    with open(f"{base}.texture_set.json", "w") as fp:
        json.dump(ts, fp, indent=2)
        fp.write("\n")
    files.append(f"{base}.texture_set.json")
    return files
