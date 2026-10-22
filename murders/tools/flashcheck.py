# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy"]
# ///
"""Find unintended flashes: 1-3 frame runs that jump away from the shot and straight back.

    uv run murders/tools/flashcheck.py out/murders/frames [--fps 30] [--analysis murders/analysis/analysis.json]

Each frame is shrunk to 64x36 grey. A flash is a jump into frames f..f+L-1 (L <= 3) where the frame before and
the frame after the run are close to each other but both far from the run. Intended cuts don't come back, so they
aren't reported. With --analysis, a flash starting within 2 frames of a measured crash or impact is labelled as
intended (the storm's lightning strikes on the crashes); anything else is unexplained.
"""
import json, os, subprocess, sys
import numpy as np

src = sys.argv[1]
fps = float(sys.argv[sys.argv.index('--fps') + 1]) if '--fps' in sys.argv else 30.0
hits = []
if '--analysis' in sys.argv:
    A = json.load(open(sys.argv[sys.argv.index('--analysis') + 1]))
    hits = [c['t'] for c in A['drums']['crash']] + [e['t'] for e in A['events'] if e['type'] == 'impact']
names = sorted(n for n in os.listdir(src) if n.endswith('.png'))
idx = [int(n[:-4]) for n in names]
raw = subprocess.run(['ffmpeg', '-v', 'error', '-framerate', str(fps), '-pattern_type', 'glob', '-i', os.path.join(src, '*.png'),
                      '-vf', 'scale=64:36:flags=area,format=gray', '-fps_mode', 'passthrough', '-f', 'rawvideo', '-'],
                     capture_output=True, check=True).stdout
F = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 36, 64).astype(np.float32)
assert len(F) == len(names), (len(F), len(names))
d = lambda a, b: float(np.abs(F[a] - F[b]).mean())
found = []
for i in range(1, len(F) - 1):
    if idx[i] - idx[i - 1] != 1:
        continue
    jump = d(i - 1, i)
    if jump < 12:
        continue
    for L in (1, 2, 3):
        j = i + L
        if j >= len(F) or idx[j] - idx[i - 1] != L + 1:
            break
        back = d(i - 1, j)
        if back < jump / 3:
            found.append((idx[i], L, jump, back))
            break
print(f'{len(F)} frames checked')
bad = 0
for f0, L, jump, back in found:
    on = [h for h in hits if abs(h - f0 / fps) <= 2 / fps]
    bad += not on
    why = f'on the measured hit at {on[0]:.3f} s' if on else 'UNEXPLAINED'
    print(f'  flash at frame {f0} ({f0 / fps:.2f} s), {L} frame(s): jump {jump:.1f}, before vs after {back:.1f}: {why}')
print(f'{len(found)} flash(es) found, {bad} unexplained')
sys.exit(1 if bad else 0)
