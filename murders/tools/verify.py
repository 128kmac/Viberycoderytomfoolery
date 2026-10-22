# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy", "scipy"]
# ///
"""Check the delivered video against the song file.

    uv run murders/tools/verify.py final/music-video.mp4 murders/audio/Murders.mp3

1. Streams: codec, size, frame rate, pixel format, audio codec, durations, start times.
2. A full decode of every video and audio packet (ffmpeg -f null); any decoder error fails the check.
3. The last frame is extracted to murders/review/last-frame.png.
4. Sync: both audio tracks are decoded with their timestamps honoured (aresample first_pts=0 pads or trims
   to put pts 0 at sample 0), then cross-correlated in 4 s windows across the song. An offset of 0 samples
   means the music sits exactly where it does in the song file. AAC is lossy, so the correlation peak is a
   little under 1.
"""
import json, subprocess, sys
import numpy as np
from scipy import signal

SR = 44100
video, song = sys.argv[1], sys.argv[2]


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def probe(path):
    out = run(['ffprobe', '-v', 'error', '-show_streams', '-show_format', '-of', 'json', path]).stdout
    return json.loads(out)


def decode(path):
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', path, '-map', '0:a:0', '-af', 'aresample=async=1:first_pts=0',
                          '-ac', '1', '-ar', str(SR), '-f', 'f32le', '-'], capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32)


ok = True
def check(name, cond, detail):
    global ok
    ok &= bool(cond)
    print(f"  [{'ok' if cond else 'FAIL'}] {name}: {detail}")


print('1. streams')
pv, ps = probe(video), probe(song)
v = next(s for s in pv['streams'] if s['codec_type'] == 'video')
a = next(s for s in pv['streams'] if s['codec_type'] == 'audio')
check('video codec', v['codec_name'] == 'h264', f"{v['codec_name']} ({v.get('profile')})")
check('size', (v['width'], v['height']) == (1920, 1080), f"{v['width']}x{v['height']}")
check('frame rate', v['r_frame_rate'] == '30/1' and v['avg_frame_rate'] == '30/1', f"r {v['r_frame_rate']}, avg {v['avg_frame_rate']}")
check('pixel format', v['pix_fmt'] == 'yuv420p', v['pix_fmt'])
check('audio codec', a['codec_name'] == 'aac', f"{a['codec_name']} {a['sample_rate']} Hz, {a['channels']} ch, {int(a.get('bit_rate', 0)) // 1000} kb/s")
sa = next(s for s in ps['streams'] if s['codec_type'] == 'audio')
check('audio sample rate matches song', a['sample_rate'] == sa['sample_rate'], f"{a['sample_rate']} vs {sa['sample_rate']}")
check('start times', float(v['start_time']) == 0 and float(a['start_time']) == 0, f"video {v['start_time']}, audio {a['start_time']}")
song_len = len(decode(song)) / SR
vd, ad, fd = float(v['duration']), float(a['duration']), float(pv['format']['duration'])
check('length vs song', abs(fd - song_len) < 1 / 30 and abs(ad - song_len) < 0.005,
      f"file {fd:.3f} s, video {vd:.3f} s ({v.get('nb_frames')} frames), audio {ad:.3f} s; song decodes to {song_len:.3f} s "
      f"(container {float(ps['format']['duration']):.3f} s incl. the mp3's {float(sa.get('start_time', 0)):.3f} s encoder delay)")

print('2. full decode')
r = run(['ffmpeg', '-v', 'error', '-i', video, '-f', 'null', '-'])
check('decodes to the end without errors', r.returncode == 0 and not r.stderr.strip(), f"exit {r.returncode}, {len(r.stderr.strip().splitlines())} error lines")
r = run(['ffprobe', '-v', 'error', '-count_frames', '-select_streams', 'v:0', '-show_entries', 'stream=nb_read_frames', '-of', 'csv=p=0', video])
nread = int(r.stdout.strip().strip(','))
check('every frame decoded', nread == int(v.get('nb_frames', nread)), f"{nread} frames read = {nread / 30:.3f} s")

print('3. last frame')
r = run(['ffmpeg', '-v', 'error', '-y', '-sseof', '-0.2', '-i', video, '-update', '1', '-frames:v', '1', 'murders/review/last-frame.png'])
check('last frame extracted', r.returncode == 0, 'murders/review/last-frame.png')

print('4. sync (cross-correlation of the decoded audio against the song file)')
x, y = decode(song), decode(video)
check('decoded lengths', abs(len(x) - len(y)) <= 2048, f"song {len(x)} samples, video {len(y)} samples ({(len(y) - len(x)) / SR * 1000:+.1f} ms)")
W, PAD = 4 * SR, 8000
worst = 0
for start in (5, 20, 45, 60, 90, 120, 150, 180, 200, 215):
    i = int(start * SR)
    ref = x[i:i + W]
    seg = y[max(0, i - PAD):i + W + PAD]
    c = signal.correlate(seg, ref, mode='valid')
    lag = int(np.argmax(c)) - (i - max(0, i - PAD))
    m = seg[lag + (i - max(0, i - PAD)):][:W]
    corr = float(np.dot(ref, m) / (np.linalg.norm(ref) * np.linalg.norm(m) + 1e-12))
    worst = max(worst, abs(lag))
    print(f"     at {start:>3} s: offset {lag:+d} samples ({lag / SR * 1000:+.2f} ms), correlation {corr:.4f}")
check('music in sync', worst <= 1, f"largest offset {worst} samples")
print('ALL CHECKS PASSED' if ok else 'SOME CHECKS FAILED')
sys.exit(0 if ok else 1)
