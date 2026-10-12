#!/usr/bin/env node
// Frame-exact renderer. Serves the project, opens N headless pages, calls
// window.capture(t) (seek + lossless canvas PNG) for each frame in parallel,
// reorders, and pipes straight into ffmpeg — no frames on disk.
//
// usage: node <skill>/scripts/render.mjs <film> [mode] [--format 16x9] [--fps 60] [--workers 4] [--noblur] [--samples 8] [--draft]
// modes:
//   (default)        out/<film>/video_<fmt>.mp4   video only, H.264 CRF 16 yuv420p bt709, +faststart
//   --contact        out/<film>/contact_<fmt>.png  one frame per beat (+ _a/_b halves if long)
//   --at 1.2,3.4     out/<film>/stills/t1.200_<fmt>.png
//   --strip a:b:n    out/<film>/strip_<fmt>.png    n frames from a to b seconds (transition check)
//   --poster [t]     out/<film>/poster_<fmt>.png   default film.json poster
//   --all-formats    run the chosen mode for every format in film.json
//   --draft          video: no blur, veryfast/CRF 22 — for quick watch-throughs only
import fs from 'node:fs';
import path from 'node:path';
import { FORMATS, parseArgs, die, log, loadFilm, readJSON, launch, serve, ffmpeg, ffmpegStream, mkdirp, rel, ROOT } from './lib/common.mjs';

const a = parseArgs();
const film = a._[0] ?? a.film;
const { P, cfg } = loadFilm(film);
if (!fs.existsSync(path.join(P.dir, 'index.html'))) die(`${rel(P.dir)}/index.html missing`);
if (!fs.existsSync(P.beats)) die(`${rel(P.beats)} missing: run score.mjs (or beats.mjs --track) first`);
const beats = readJSON(P.beats);
const fps = Number(a.fps ?? cfg.fps ?? 60);
const workers = Math.max(1, Number(a.workers ?? 4));
const formats = a['all-formats'] ? cfg.formats : [a.format ?? cfg.formats[0]];
for (const f of formats) if (!FORMATS[f]) die(`unknown format ${f}`);
mkdirp(P.out);

const snap = (t) => Math.round(t * fps) / fps;
const urlRel = path.relative(ROOT, P.dir).split(path.sep).map(encodeURIComponent).join('/');

const server = await serve(ROOT);
const browser = await launch();
try {
  for (const fmt of formats) await renderFormat(fmt);
} finally {
  await browser.close();
  server.close();
}

async function openPages(fmt, blur, n) {
  const { w, h } = FORMATS[fmt];
  const url = `${server.url}/${urlRel}/index.html?render=1&format=${fmt}&w=${w}&h=${h}&fps=${fps}&blur=${blur ? 1 : 0}${a.samples ? `&samples=${a.samples}` : ''}`;
  const pages = await Promise.all(Array.from({ length: n }, async () => {
    const page = await browser.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: 1 });
    page.on('pageerror', (e) => console.error(`[page] ${e.message}`));
    // 404s on optional font formats (woff2/ttf/otf fallbacks) are expected noise.
    page.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource/.test(m.text())) console.error(`[console] ${m.text()}`); });
    page.on('response', (r) => { if (r.status() >= 400 && !/\/fonts\//.test(r.url())) console.error(`[http ${r.status()}] ${r.url().replace(server.url, '')}`); });
    await page.goto(url);
    await page.waitForFunction(() => window.filmReady === true, null, { timeout: 60000 });
    return page;
  }));
  return pages;
}

// Capture a list of times; returns PNG buffers in order (or streams them to sink).
async function captureAll(fmt, times, { blur = true, sink, progress = false } = {}) {
  const pages = await openPages(fmt, blur, Math.min(workers, times.length));
  const results = new Array(times.length);
  let next = 0, flushed = 0, done = 0;
  const t0 = Date.now();
  const flush = async () => {
    while (flushed < times.length && results[flushed]) {
      if (sink) { await sink(results[flushed]); results[flushed] = true; }
      flushed++;
    }
  };
  let flushing = Promise.resolve();
  await Promise.all(pages.map(async (page) => {
    while (next < times.length) {
      const i = next++;
      const dataUrl = await page.evaluate((t) => window.capture(t), times[i]);
      results[i] = Buffer.from(dataUrl.slice(dataUrl.indexOf(',') + 1), 'base64');
      done++;
      flushing = flushing.then(flush);
      // Backpressure: don't let unflushed frames pile up in memory.
      while (sink && i - flushed > workers * 8) { await flushing; await new Promise((r) => setTimeout(r, 5)); }
      if (progress && done % fps === 0) {
        const el = (Date.now() - t0) / 1000;
        process.stdout.write(`\r  ${fmt}: ${done}/${times.length} frames · ${(done / el).toFixed(1)} fps · eta ${((times.length - done) / (done / el)).toFixed(0)}s   `);
      }
    }
  }));
  await flushing.then(flush);
  if (progress) process.stdout.write('\n');
  await Promise.all(pages.map((p) => p.close()));
  return results;
}

function tile(pngs, out, { cols, tw, th }) {
  // Write temp PNGs, tile with ffmpeg (8px grey gutters).
  const tmp = mkdirp(path.join(P.out, '.tiles'));
  pngs.forEach((b, i) => fs.writeFileSync(path.join(tmp, `${String(i).padStart(4, '0')}.png`), b));
  const rows = Math.ceil(pngs.length / cols);
  ffmpeg(['-framerate', '1', '-i', path.join(tmp, '%04d.png'),
    '-vf', `scale=${tw}:${th}:flags=area,pad=iw+8:ih+8:4:4:0x777777,tile=${cols}x${rows}:color=0x777777`,
    '-frames:v', '1', '-update', '1', out]);
  fs.rmSync(tmp, { recursive: true, force: true });
}

async function renderFormat(fmt) {
  const { w, h } = FORMATS[fmt];
  const suffix = `_${fmt}`;
  const thumb = { '16x9': [4, 384, 216], '9x16': [8, 216, 384], '1x1': [6, 300, 300] }[fmt];

  if (a.contact) {
    const bt = (beats.beats ?? []).filter((t) => t >= 0 && t < cfg.duration);
    if (!bt.length) die('beats.json has no beats');
    const times = bt.map(snap);
    log(`contact ${fmt}: ${times.length} beats`);
    const pngs = await captureAll(fmt, times, { blur: !a.noblur });
    const dir = mkdirp(path.join(P.out, `contact${suffix}`));
    pngs.forEach((b, i) => fs.writeFileSync(path.join(dir, `b${String(i).padStart(3, '0')}.png`), b));
    const [cols, tw, th] = thumb;
    tile(pngs, path.join(P.out, `contact${suffix}.png`), { cols, tw, th });
    // Long films: also two larger halves so detail stays legible.
    if (pngs.length > cols * 4) {
      const half = Math.ceil(pngs.length / 2);
      tile(pngs.slice(0, half), path.join(P.out, `contact${suffix}_a.png`), { cols, tw: Math.round(tw * 4 / 3), th: Math.round(th * 4 / 3) });
      tile(pngs.slice(half), path.join(P.out, `contact${suffix}_b.png`), { cols, tw: Math.round(tw * 4 / 3), th: Math.round(th * 4 / 3) });
    }
    // Phone-size proof: anything unreadable here is unreadable on a phone.
    ffmpeg(['-i', path.join(P.out, `contact${suffix}.png`), '-vf', 'scale=iw/3:-2:flags=area', path.join(P.out, `phone${suffix}.png`)]);
    log(`✓ ${rel(path.join(P.out, `contact${suffix}.png`))}  (+ phone${suffix}.png, contact${suffix}/bNNN.png = beat N)`);
    return;
  }
  if (a.at) {
    const times = String(a.at).split(',').map(Number).map(snap);
    const pngs = await captureAll(fmt, times, { blur: !a.noblur });
    const dir = mkdirp(path.join(P.out, 'stills'));
    pngs.forEach((b, i) => { const f = path.join(dir, `t${times[i].toFixed(3)}${suffix}.png`); fs.writeFileSync(f, b); log(`✓ ${rel(f)}`); });
    return;
  }
  if (a.strip) {
    const [s, e, n = 8] = String(a.strip).split(':').map(Number);
    const times = Array.from({ length: n }, (_, i) => snap(s + (e - s) * i / Math.max(1, n - 1)));
    const pngs = await captureAll(fmt, times, { blur: !a.noblur });
    const cols = Math.min(n, fmt === '9x16' ? 8 : 4);
    const name = `strip_${s}-${e}${suffix}.png`;
    tile(pngs, path.join(P.out, name), { cols, tw: thumb[1], th: thumb[2] });
    log(`✓ ${rel(path.join(P.out, name))}  (${times.map((t) => t.toFixed(2)).join(', ')})`);
    return;
  }
  if (a.poster !== undefined) {
    const t = snap(typeof a.poster === 'string' ? Number(a.poster) : (cfg.poster ?? cfg.duration * 0.87));
    const [png] = await captureAll(fmt, [t], { blur: false });
    const f = path.join(P.out, `poster${suffix}.png`);
    fs.writeFileSync(f, png); log(`✓ ${rel(f)} @ ${t.toFixed(3)}s`);
    return;
  }

  // Full video render.
  const n = Math.round(cfg.duration * fps);
  const times = Array.from({ length: n }, (_, i) => i / fps);
  const out = path.join(P.out, `video${suffix}.mp4`);
  log(`render ${fmt} ${w}x${h} @ ${fps} fps · ${n} frames · ${workers} workers · blur ${a.noblur || a.draft ? 'off' : 'on'}`);
  const enc = ffmpegStream(['-f', 'image2pipe', '-framerate', String(fps), '-c:v', 'png', '-i', '-',
    '-vf', 'scale=out_color_matrix=bt709:out_range=tv,format=yuv420p',
    '-c:v', 'libx264', '-preset', a.draft ? 'veryfast' : 'slow', '-crf', a.draft ? '22' : '16', '-profile:v', 'high',
    '-g', String(Math.round(fps / 2)), '-bf', '2',
    '-colorspace', 'bt709', '-color_primaries', 'bt709', '-color_trc', 'bt709', '-color_range', 'tv',
    '-r', String(fps), '-movflags', '+faststart', '-an', out]);
  const t0 = Date.now();
  await captureAll(fmt, times, { blur: !a.noblur && !a.draft, sink: enc.write, progress: true });
  await enc.end();
  log(`✓ ${rel(out)} in ${((Date.now() - t0) / 1000).toFixed(1)}s`);
}
