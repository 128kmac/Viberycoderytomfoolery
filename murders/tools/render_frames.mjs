// Frame renderer for the Murders film: captures the film canvas directly (lossless PNG via
// canvas.toDataURL), which is ~3x faster than a page screenshot. The film is a pure function of
// time, so frames are rendered out of order across parallel pages.
//
//   node murders/tools/render_frames.mjs --out out/murders/frames --fps 30 [--from 0 --to 222.99] [--step 1]
//        [--workers 4] [--blur 1] [--at 12.5,30,208.8]
// Writes <out>/%05d.png where the index is the frame number (round(t * fps)).

import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const req = createRequire(path.join(process.cwd(), 'noop.js'));
const pw = await import(req.resolve('playwright'));
const chromium = pw.chromium || pw.default.chromium;

const args = process.argv.slice(2);
const opt = (n, d) => { const i = args.indexOf(`--${n}`); return i >= 0 ? args[i + 1] : d; };
const ROOT = process.cwd();
const FILM = opt('film', 'murders');
const OUT = path.resolve(opt('out', 'out/murders/frames'));
const FPS = Number(opt('fps', 30));
const cfg = JSON.parse(fs.readFileSync(path.join(ROOT, FILM, 'film.json'), 'utf8'));
const DUR = Number(cfg.duration);
const FROM = Number(opt('from', 0)), TO = Number(opt('to', DUR));
const STEP = Number(opt('step', 1 / FPS));
const WORKERS = Number(opt('workers', 4));
const BLUR = opt('blur', '1');
fs.mkdirSync(OUT, { recursive: true });

const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json', '.ttf': 'font/ttf', '.otf': 'font/otf', '.png': 'image/png' };
const srv = http.createServer((q, r) => {
  const p = path.join(ROOT, decodeURIComponent(new URL(q.url, 'http://x').pathname));
  if (!p.startsWith(ROOT) || !fs.existsSync(p) || fs.statSync(p).isDirectory()) { r.writeHead(404); r.end(); return; }
  r.writeHead(200, { 'Content-Type': MIME[path.extname(p)] || 'application/octet-stream' });
  fs.createReadStream(p).pipe(r);
});
await new Promise((res) => srv.listen(0, '127.0.0.1', res));
const url = `http://127.0.0.1:${srv.address().port}/${FILM}/index.html?render=1&blur=${BLUR}&fps=${FPS}&format=16x9&w=1920&h=1080`;

// jobs: frame indices
const jobs = [];
const nFrames = Math.round(DUR * FPS);
const AT = opt('at', null);
if (AT) { for (const t of AT.split(',')) jobs.push(Math.round(Number(t) * FPS)); }
else if (STEP === 1 / FPS) { for (let f = Math.round(FROM * FPS); f < Math.min(nFrames, Math.round(TO * FPS)); f++) jobs.push(f); }
else { for (let t = FROM; t < TO; t += STEP) jobs.push(Math.round(t * FPS)); }
const todo = jobs.filter((f) => !fs.existsSync(path.join(OUT, `${String(f).padStart(5, '0')}.png`)));
console.log(`${todo.length}/${jobs.length} frames to render -> ${path.relative(ROOT, OUT)} (${WORKERS} workers, blur ${BLUR})`);

const browser = await chromium.launch({ args: ['--font-render-hinting=none', '--disable-lcd-text'] });
let next = 0, done = 0;
const t0 = Date.now();
await Promise.all(Array.from({ length: WORKERS }, async () => {
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
  page.on('pageerror', (e) => console.error('[page]', e.message));
  await page.goto(url);
  await page.waitForFunction(() => window.filmReady === true, null, { timeout: 120000 });
  while (next < todo.length) {
    const f = todo[next++];
    const data = await page.evaluate((t) => { window.seek(t); return document.getElementById('film').toDataURL('image/png'); }, f / FPS);
    fs.writeFileSync(path.join(OUT, `${String(f).padStart(5, '0')}.png`), Buffer.from(data.slice(data.indexOf(',') + 1), 'base64'));
    done++;
    if (done % 120 === 0) {
      const rate = done / ((Date.now() - t0) / 1000);
      console.log(`  ${done}/${todo.length}  ${rate.toFixed(2)} fps  eta ${((todo.length - done) / rate / 60).toFixed(1)} min`);
    }
  }
  await page.close();
}));
await browser.close(); srv.close();
console.log(`done in ${((Date.now() - t0) / 60000).toFixed(1)} min`);
