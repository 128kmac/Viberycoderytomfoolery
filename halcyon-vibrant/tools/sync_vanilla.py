"""Refresh vanilla_data/ from a checkout of Mojang/bedrock-samples.

The pack rewires every vanilla biome to Halcyon's own lighting, sky, water and
fog profiles. Client biome files replace the vanilla ones wholesale, so we keep
a copy of each vanilla file (music, sounds, grass/foliage colours, ...) and
only swap the Vibrant Visuals identifiers at build time.

Usage: python tools/sync_vanilla.py /path/to/bedrock-samples
"""

import json
import os
import re
import subprocess
import sys


def load(path):
    text = open(path, encoding="utf8").read()
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"^\s*//.*$", "", text, flags=re.M)
    return json.loads(text)


def colour_stats(src, names):
    """Mean colour (opaque texels, first flipbook frame) and alpha coverage of
    each vanilla block texture. Halcyon tones its textures to these numbers so
    biome tints and the world's overall palette stay where players expect."""
    import io

    import numpy as np
    from PIL import Image

    order = []
    for base, exts in sorted(names.items()):
        ext = "png" if "png" in exts else exts[0]
        order.append((base, ext))
    req = "".join(f"HEAD:resource_pack/textures/blocks/{b}.{e}\n" for b, e in order)
    blob = subprocess.run(["git", "-C", src, "cat-file", "--batch"], input=req.encode(),
                          capture_output=True, check=True).stdout
    stats, i = {}, 0
    for base, ext in order:
        nl = blob.index(b"\n", i)
        hdr = blob[i:nl].split()
        i = nl + 1
        if hdr[1] == b"missing":
            continue
        size = int(hdr[2])
        data = blob[i:i + size]
        i += size + 1
        try:
            a = np.asarray(Image.open(io.BytesIO(data)).convert("RGBA")).astype(float)
        except Exception:  # noqa: BLE001
            continue
        a = a[: a.shape[1]]
        m = a[..., 3] > 128
        cov = float(m.mean())
        if not m.any():
            m = np.ones(a.shape[:2], bool)
        stats[base] = {"mean": [round(float(v), 1) for v in a[..., :3][m].mean(0)], "coverage": round(cov, 3)}
    return stats


def main(src):
    rp = os.path.join(src, "resource_pack")
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(here, "vanilla_data")
    for sub in ("biomes", "fogs"):
        os.makedirs(os.path.join(out, sub), exist_ok=True)
    n = 0
    for f in sorted(os.listdir(os.path.join(rp, "biomes"))):
        if f.endswith(".client_biome.json"):
            d = load(os.path.join(rp, "biomes", f))
            json.dump(d, open(os.path.join(out, "biomes", f), "w"), indent=1, sort_keys=True)
            n += 1
    m = 0
    for f in sorted(os.listdir(os.path.join(rp, "fogs"))):
        if f.endswith(".json"):
            d = load(os.path.join(rp, "fogs", f))
            json.dump(d, open(os.path.join(out, "fogs", f), "w"), indent=1, sort_keys=True)
            m += 1
    # Names of every vanilla block texture (works on sparse/blobless clones too).
    listing = subprocess.run(["git", "-C", src, "ls-tree", "-r", "--name-only", "HEAD",
                              "resource_pack/textures/blocks/"], capture_output=True, text=True, check=True)
    names = {}
    for line in listing.stdout.splitlines():
        rel = line[len("resource_pack/textures/blocks/"):]
        base, ext = os.path.splitext(rel)
        if ext in (".png", ".tga") and not re.search(r"_(mers|mer|heightmap)$", base):
            names.setdefault(base, []).append(ext[1:])
    json.dump({k: sorted(v) for k, v in sorted(names.items())},
              open(os.path.join(out, "block_textures.json"), "w"), indent=0)
    json.dump(colour_stats(src, names), open(os.path.join(out, "block_stats.json"), "w"), indent=0)
    ver = load(os.path.join(rp, "manifest.json"))["header"]["min_engine_version"]
    json.dump({"source": "Mojang/bedrock-samples", "engine_version": ver},
              open(os.path.join(out, "VERSION.json"), "w"), indent=1)
    print(f"synced {n} client biomes and {m} fogs from vanilla {ver}")


if __name__ == "__main__":
    main(sys.argv[1])
