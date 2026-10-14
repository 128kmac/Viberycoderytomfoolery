"""Render a gallery of built textures (colour, lit by a low sun with the
normal and MERS maps applied, 2x2 tiled to show seams).

Usage: python tools/gallery.py build/Halcyon_RP/textures/blocks out.png stone dirt ...
"""

import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from halcyon.preview import shade  # noqa: E402


def main(root, out, names, cols=8, size=128):
    tiles = []
    for n in names:
        for ext in ("tga", "png"):
            p = os.path.join(root, n + "." + ext)
            if os.path.exists(p):
                break
        c = np.asarray(Image.open(p).convert("RGBA")).astype(float) / 255
        w = c.shape[1]
        c = c[:w]
        nm = np.asarray(Image.open(os.path.join(root, n + "_nrm.tga")).convert("RGB")).astype(float)[:w] / 255 * 2 - 1
        me = np.asarray(Image.open(os.path.join(root, n + "_mers.tga")).convert("RGBA")).astype(float)[:w] / 255
        t = lambda a: np.tile(a, (2, 2, 1) if a.ndim == 3 else (2, 2))  # noqa: E731
        lit = shade(t(c[..., :3]), t(nm), t(me[..., 2]), t(me[..., 0]), t(me[..., 1]))
        a = t(c[..., 3])[..., None]
        lit = lit * a + 0.12 * (1 - a)
        tiles.append((n, (lit * 255).astype(np.uint8)))
    rows = (len(tiles) + cols - 1) // cols
    img = Image.new("RGB", (cols * (size + 6), rows * (size + 16)), (20, 20, 24))
    d = ImageDraw.Draw(img)
    for i, (n, tile) in enumerate(tiles):
        x = (i % cols) * (size + 6)
        y = (i // cols) * (size + 16)
        im = Image.fromarray(tile)
        if im.width != size:
            im = im.resize((size, size), Image.NEAREST)
        img.paste(im, (x, y + 14))
        d.text((x + 2, y + 1), n.split("/")[-1][:22], fill=(220, 220, 220))
    img.save(out)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3:])
