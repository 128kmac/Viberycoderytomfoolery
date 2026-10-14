#!/usr/bin/env python3
"""Build the Halcyon Vibrant Visuals resource pack.

    python build.py                 # 64x textures -> dist/Halcyon-Vibrant-Visuals.mcaddon
    python build.py --res 128       # sharper (and ~4x larger) textures
    python build.py --only stone    # rebuild a subset while iterating

Output:
    build/Halcyon_RP/                     the unpacked resource pack
    dist/Halcyon-Vibrant-Visuals.mcaddon  double-click to import into Minecraft
    dist/Halcyon-Vibrant-Visuals.mcpack   same pack, single-pack format
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import time
import zipfile
from concurrent.futures import ProcessPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from halcyon import noise as nz  # noqa: E402
from halcyon import pbr  # noqa: E402

PACK_NAME = "Halcyon_RP"
VERSION = [1, 0, 0]
HEADER_UUID = "ee308659-4b33-4e35-bd4c-39841bcbac3e"
MODULE_UUID = "b988b36f-d5b5-4522-988e-65bbad5c578c"
MIN_ENGINE = [1, 26, 0]


def _render(args):
    name, res, out = args
    from halcyon import materials  # noqa: F401  (registers recipes in the worker)
    from halcyon.lib import Ctx
    from halcyon.registry import REGISTRY
    e = REGISTRY[name]
    ctx = Ctx(res, width_mul=e.width_mul)
    m = e.fn(ctx, nz.sub(name))
    target = None
    if "nocal" not in e.tags:
        target = _stats().get(name, {}).get("mean")
    files = pbr.write(m, out, name, color_exts=e.exts, frames=e.frames, tga_alpha_override=e.tga_alpha,
                      target=target)
    return name, len(files)


_STATS = None


def _stats():
    global _STATS
    if _STATS is None:
        with open(os.path.join(HERE, "vanilla_data", "block_stats.json")) as fp:
            _STATS = json.load(fp)
    return _STATS


def manifest():
    desc = ("Physically based Vibrant Visuals pack: 370+ hand-built PBR block textures "
            "with normal maps and MERS, filmic sky and sun, volumetric fog, waves and caustics.")
    return {
        "format_version": 2,
        "header": {
            "name": "Halcyon Vibrant Visuals",
            "description": desc,
            "uuid": HEADER_UUID,
            "version": VERSION,
            "min_engine_version": MIN_ENGINE,
        },
        "modules": [{
            "description": "Halcyon PBR textures and Vibrant Visuals lighting",
            "type": "resources",
            "uuid": MODULE_UUID,
            "version": VERSION,
        }],
        "capabilities": ["pbr"],
        "metadata": {"authors": ["Halcyon"], "generated_with": {"halcyon_build": ["1.0.0"]}},
    }


def write_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fp:
        json.dump(data, fp, indent=2)
        fp.write("\n")


def zipdir(src, dest, prefix):
    with zipfile.ZipFile(dest, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for root, _, files in os.walk(src):
            for f in sorted(files):
                full = os.path.join(root, f)
                rel = os.path.relpath(full, src)
                z.write(full, os.path.join(prefix, rel) if prefix else rel)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--res", type=int, default=64, help="block texture resolution (32, 64, 128)")
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 4)
    ap.add_argument("--only", nargs="*", help="only render these texture names")
    ap.add_argument("--no-package", action="store_true")
    args = ap.parse_args()

    from halcyon import materials  # noqa: F401
    from halcyon.config.vv import write_config
    from halcyon.icon import render as render_icon
    from halcyon.materials.fluids import write_caustics
    from halcyon.registry import REGISTRY

    out = os.path.join(HERE, "build", PACK_NAME)
    if not args.only and os.path.isdir(out):
        shutil.rmtree(out)
    os.makedirs(out, exist_ok=True)
    t0 = time.time()

    write_json(os.path.join(out, "manifest.json"), manifest())
    render_icon(256).save(os.path.join(out, "pack_icon.png"))

    names = args.only or sorted(REGISTRY)
    with ProcessPoolExecutor(max_workers=args.jobs) as ex:
        for i, (name, n) in enumerate(ex.map(_render, [(nm, args.res, out) for nm in names]), 1):
            if i % 50 == 0 or i == len(names):
                print(f"  textures {i}/{len(names)}  ({time.time() - t0:.1f}s)")

    env = os.path.join(out, "textures", "environment")
    os.makedirs(env, exist_ok=True)
    write_caustics(os.path.join(env, "halcyon_caustics.png"), size=128, frames=32)
    # Caustics must be declared so the engine loads it without a block using it.
    write_json(os.path.join(out, "textures", "texture_list.json"), ["textures/environment/halcyon_caustics"])

    files, biome_map = write_config(out, os.path.join(HERE, "vanilla_data"))
    write_json(os.path.join(HERE, "build", "biome_map.json"), biome_map)
    print(f"  config: {len(files)} files, {len(biome_map)} biomes rewired")

    from tools.validate import validate
    problems = validate(out)
    if problems:
        print("VALIDATION FAILED:")
        for p in problems[:50]:
            print("  -", p)
        sys.exit(1)
    print("  validation passed")

    if not args.no_package:
        dist = os.path.join(HERE, "dist")
        os.makedirs(dist, exist_ok=True)
        mcpack = os.path.join(dist, "Halcyon-Vibrant-Visuals.mcpack")
        mcaddon = os.path.join(dist, "Halcyon-Vibrant-Visuals.mcaddon")
        zipdir(out, mcpack, "")
        zipdir(out, mcaddon, PACK_NAME)
        for p in (mcpack, mcaddon):
            print(f"  wrote {os.path.relpath(p, HERE)} ({os.path.getsize(p) / 1e6:.1f} MB)")
    print(f"done in {time.time() - t0:.1f}s")


if __name__ == "__main__":
    main()
