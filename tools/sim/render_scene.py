#!/usr/bin/env python3
"""Export the harness scene and render it with three.js (render3d/render.mjs) to a PNG."""
import json
import os
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))


def render(sim, out, size=(1280, 720), cam=None, **opts):
    scene = sim.export_scene(**opts)
    import math

    def finite(x):
        return all(isinstance(v, (int, float)) and math.isfinite(v) for v in x)
    for key in ('parts', 'beams', 'particles', 'lights'):
        items = scene.get(key) or []
        if isinstance(items, dict):
            items = list(items.values())
        good = []
        for it in items:
            vals = []
            for k2 in ('cf', 'pos', 'p0', 'p1', 'size'):
                v = it.get(k2)
                if isinstance(v, list):
                    vals += v
                elif isinstance(v, (int, float)):
                    vals.append(v)
            if finite(vals):
                good.append(it)
        scene[key] = good
    tmp = os.path.join(HERE, 'out', '_scene.json')
    os.makedirs(os.path.dirname(tmp), exist_ok=True)
    with open(tmp, 'w') as f:
        json.dump(scene, f)
    args = ['node', os.path.join(HERE, 'render3d', 'render.mjs'), tmp, out, str(size[0]), str(size[1])]
    if cam:
        args.append(json.dumps(cam))
    r = subprocess.run(args, capture_output=True, text=True, timeout=240)
    if r.returncode != 0:
        raise RuntimeError(r.stderr[-2000:])
    return out
