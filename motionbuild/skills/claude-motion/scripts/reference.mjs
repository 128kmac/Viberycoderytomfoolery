#!/usr/bin/env node
// Turn a style reference (video, image, or folder of images) into sheets you
// can look at and numbers you can build to. It does not write the style guide;
// you do, from these, in <film>/docs/style_guide.md.
// usage: node <skill>/scripts/reference.mjs <video|image|folder> <film> [--threshold 0.3]
// out:   <film>/docs/reference/{shots.png, seconds.png, cuts.json} for video, sheet.png for images
import fs from 'node:fs';
import path from 'node:path';
import { parseArgs, die, log, filmPaths, writeJSON, mkdirp, run, ffmpeg, probe, rel } from './lib/common.mjs';

const a = parseArgs();
const [src, film] = a._;
if (!src || !film) die('usage: reference.mjs <video|image|folder> <film> [--threshold 0.3]');
if (!fs.existsSync(src)) die(`${src} not found`);
const P = filmPaths(film);
const out = mkdirp(path.join(P.docs, 'reference'));
const IMG = /\.(png|jpe?g|webp|gif|bmp|avif)$/i;

// Grid of files -> one PNG, letterboxed cells on grey with 8 px gutters.
function sheet(files, dest, { cols, w, h }) {
  const tmp = mkdirp(path.join(out, '.tmp'));
  files.forEach((f, i) => ffmpeg(['-i', f, '-frames:v', '1', '-vf', `scale=${w}:${h}:force_original_aspect_ratio=decrease,pad=${w}:${h}:(ow-iw)/2:(oh-ih)/2:0x777777`, path.join(tmp, `${String(i).padStart(4, '0')}.png`)]));
  const rows = Math.ceil(files.length / cols);
  ffmpeg(['-framerate', '1', '-i', path.join(tmp, '%04d.png'), '-vf', `pad=iw+8:ih+8:4:4:0x777777,tile=${cols}x${rows}:color=0x777777`, '-frames:v', '1', '-update', '1', dest]);
  fs.rmSync(tmp, { recursive: true, force: true });
}

const stat = fs.statSync(src);
if (stat.isDirectory() || IMG.test(src)) {
  const files = stat.isDirectory() ? fs.readdirSync(src).filter((f) => IMG.test(f)).sort().slice(0, 24).map((f) => path.join(src, f)) : [src];
  if (!files.length) die('no images found');
  const dest = path.join(out, 'sheet.png');
  sheet(files, dest, { cols: Math.min(4, files.length), w: 480, h: 360 });
  log(`✓ ${rel(dest)}  ${files.length} images`);
  log('Now write docs/style_guide.md from it (composition, colour, type, texture).');
  process.exit(0);
}

const j = probe(src), v = j.streams.find((s) => s.codec_type === 'video');
if (!v) die('no video stream');
const dur = Number(j.format.duration), [fn, fd] = v.r_frame_rate.split('/').map(Number);
const thr = Number(a.threshold ?? 0.3);
// Hard cuts via scene score. Match cuts, morphs, whip-pans and irises don't register: read seconds.png for those.
const r = run('ffmpeg', ['-hide_banner', '-i', src, '-vf', `select='gt(scene,${thr})',showinfo`, '-an', '-f', 'null', '-'], { allowFail: true });
const raw = [...r.stderr.matchAll(/pts_time:([\d.]+)/g)].map((m) => Number(m[1]));
const cuts = raw.filter((t, i) => i === 0 || t - raw[i - 1] > 0.1);
const bounds = [0, ...cuts, dur], shots = [];
for (let i = 0; i < bounds.length - 1; i++) if (bounds[i + 1] - bounds[i] > 0.04) shots.push([bounds[i], bounds[i + 1]]);
const lens = shots.map(([s, e]) => e - s).sort((x, y) => x - y);
const median = lens[Math.floor(lens.length / 2)];

// One mid-frame per shot (evenly sampled if there are more than 40 shots).
const pick = shots.length <= 40 ? shots : Array.from({ length: 40 }, (_, i) => shots[Math.floor(i * shots.length / 40)]);
const tmp = mkdirp(path.join(out, '.mid'));
const mids = pick.map(([s, e], i) => { const f = path.join(tmp, `${i}.png`); ffmpeg(['-ss', ((s + e) / 2).toFixed(3), '-i', src, '-frames:v', '1', '-vf', 'scale=640:-2', f]); return f; });
sheet(mids, path.join(out, 'shots.png'), { cols: 5, w: 384, h: Math.round(384 * v.height / v.width) || 216 });
fs.rmSync(tmp, { recursive: true, force: true });

// One frame per second (first 60 s) to read motion between cuts.
const secs = Math.min(60, Math.ceil(dur));
ffmpeg(['-i', src, '-t', String(secs), '-vf', `fps=1,scale=384:-2,pad=iw+8:ih+8:4:4:0x777777,tile=6x${Math.ceil(secs / 6)}:color=0x777777`, '-frames:v', '1', '-update', '1', path.join(out, 'seconds.png')]);

writeJSON(path.join(out, 'cuts.json'), {
  source: path.resolve(src), duration: dur, fps: fn / fd, size: [v.width, v.height], threshold: thr,
  note: 'hard cuts only; read seconds.png for match cuts, morphs and transitions',
  shot_count: shots.length, median_shot_s: +median.toFixed(3), mean_shot_s: +(dur / shots.length).toFixed(3),
  cuts_per_10s: +(cuts.length / dur * 10).toFixed(2), cuts: cuts.map((t) => +t.toFixed(3)), shots: shots.map(([s, e]) => [+s.toFixed(3), +e.toFixed(3)]),
});
log(`✓ ${rel(out)}/shots.png  ${shots.length} shots · median ${median.toFixed(2)} s · ${(cuts.length / dur * 10).toFixed(1)} cuts/10 s`);
log(`✓ ${rel(out)}/seconds.png  1 fps, first ${secs} s`);
log(`✓ ${rel(out)}/cuts.json`);
log('If fast in-shot motion is counted as cuts, raise --threshold. Now write docs/style_guide.md.');
