// Shared helpers for every claude-motion script: CLI parsing, project paths,
// Playwright loading, ffmpeg spawning and WAV I/O. No dependencies beyond
// Node 18+, ffmpeg/ffprobe on PATH and Playwright (only where a browser is used).
import fs from 'node:fs';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const SKILL = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
export const ROOT = process.cwd();
export const SR = 48000;

export const FORMATS = {
  '16x9': { w: 1920, h: 1080 },
  '9x16': { w: 1080, h: 1920 },
  '1x1': { w: 1080, h: 1080 },
};

// --- CLI -------------------------------------------------------------------
// parseArgs(['a', '--x', '1', '--flag']) -> { _: ['a'], x: '1', flag: true }
export function parseArgs(argv = process.argv.slice(2)) {
  const out = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith('--')) {
      const eq = a.indexOf('=');
      if (eq > 0) { out[a.slice(2, eq)] = a.slice(eq + 1); continue; }
      const key = a.slice(2);
      const next = argv[i + 1];
      if (next !== undefined && !next.startsWith('--')) { out[key] = next; i++; }
      else out[key] = true;
    } else out._.push(a);
  }
  return out;
}

export function die(msg, code = 1) {
  console.error(`✗ ${msg}`);
  process.exit(code);
}

export const log = (...a) => console.log(...a);

// --- Project ---------------------------------------------------------------
export function filmPaths(film) {
  if (!film) die('missing <film> argument');
  const dir = path.resolve(ROOT, film);
  const name = path.basename(dir);
  const out = path.resolve(ROOT, 'out', name);
  return {
    name, dir, out,
    json: path.join(dir, 'film.json'),
    beats: path.join(dir, 'beats.json'),
    hits: path.join(dir, 'hits.js'),
    audio: path.join(dir, 'audio'),
    assets: path.join(dir, 'assets'),
    docs: path.join(dir, 'docs'),
  };
}

export function readJSON(p, fallback) {
  try { return JSON.parse(fs.readFileSync(p, 'utf8')); }
  catch (e) { if (fallback !== undefined) return fallback; die(`cannot read ${rel(p)}: ${e.message}`); }
}

export function writeJSON(p, obj) {
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, JSON.stringify(obj, null, 2) + '\n');
}

export function loadFilm(film) {
  const P = filmPaths(film);
  if (!fs.existsSync(P.dir)) die(`no film directory ${rel(P.dir)}`);
  const cfg = readJSON(P.json, {});
  cfg.duration = Number(cfg.duration ?? 15);
  cfg.fps = Number(cfg.fps ?? 60);
  cfg.formats = cfg.formats?.length ? cfg.formats : ['16x9'];
  return { P, cfg };
}

// Hits live in <film>/hits.js as pure data so Node and the browser share one source.
export async function loadHits(P) {
  if (!fs.existsSync(P.hits)) return [];
  const mod = await import(pathToFileURL(P.hits).href + `?v=${Date.now()}`);
  return mod.HITS ?? mod.default ?? [];
}

export const rel = (p) => path.relative(ROOT, p) || '.';

export function mkdirp(p) { fs.mkdirSync(p, { recursive: true }); return p; }

// --- Processes -------------------------------------------------------------
export function has(cmd, args = ['-version']) {
  try { return spawnSync(cmd, args, { stdio: 'ignore' }).status === 0; } catch { return false; }
}

// Run synchronously; returns { code, stdout, stderr }. Throws on failure unless allowFail.
export function run(cmd, args, { allowFail = false, input } = {}) {
  const r = spawnSync(cmd, args, { encoding: 'utf8', maxBuffer: 1 << 28, input });
  if (r.error) throw r.error;
  if (r.status !== 0 && !allowFail) {
    throw new Error(`${cmd} exited ${r.status}\n${(r.stderr || '').split('\n').slice(-25).join('\n')}`);
  }
  return { code: r.status, stdout: r.stdout, stderr: r.stderr };
}

export const ffmpeg = (args, opts) => run('ffmpeg', ['-hide_banner', '-y', '-loglevel', 'error', ...args], opts);

// Long-running ffmpeg with stdin streaming (used by the renderer).
export function ffmpegStream(args) {
  const p = spawn('ffmpeg', ['-hide_banner', '-y', '-loglevel', 'error', ...args], { stdio: ['pipe', 'inherit', 'pipe'] });
  let err = '';
  p.stderr.on('data', (d) => { err += d; });
  const done = new Promise((res, rej) => p.on('close', (c) => (c === 0 ? res() : rej(new Error(`ffmpeg exited ${c}\n${err}`)))));
  const write = (buf) => new Promise((res) => (p.stdin.write(buf) ? res() : p.stdin.once('drain', res)));
  return { proc: p, write, end: () => { p.stdin.end(); return done; } };
}

export function probe(file) {
  const r = run('ffprobe', ['-v', 'error', '-print_format', 'json', '-show_format', '-show_streams', file]);
  return JSON.parse(r.stdout);
}

// --- Playwright --------------------------------------------------------------
export async function loadChromium() {
  for (const base of [ROOT, SKILL]) {
    try {
      const req = createRequire(path.join(base, 'noop.js'));
      const m = await import(pathToFileURL(req.resolve('playwright')).href);
      return m.chromium ?? m.default.chromium;
    } catch {}
  }
  // Fall back to a global install (e.g. npm i -g playwright).
  try {
    const g = run('npm', ['root', '-g'], { allowFail: true }).stdout.trim();
    const m = await import(pathToFileURL(path.join(g, 'playwright', 'index.mjs')).href);
    return m.chromium ?? m.default.chromium;
  } catch {}
  die('Playwright not found. In the project folder run:\n  npm init -y && npm i -D playwright && npx playwright install chromium');
}

// { network: true } for pages on the internet (gather): honours HTTPS_PROXY.
// The renderer only talks to its own 127.0.0.1 server and must NOT use a proxy
// (Playwright sends loopback through it too).
export async function launch({ network = false } = {}) {
  const chromium = await loadChromium();
  const px = network && (process.env.HTTPS_PROXY || process.env.https_proxy || process.env.HTTP_PROXY || process.env.http_proxy);
  return chromium.launch({
    args: ['--font-render-hinting=none', '--disable-lcd-text', '--force-color-profile=srgb'],
    ...(px ? { proxy: { server: px } } : {}),
  });
}

// Minimal static server rooted at ROOT (for the renderer and preview).
export async function serve(root = ROOT) {
  const http = await import('node:http');
  const MIME = {
    '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.json': 'application/json',
    '.css': 'text/css', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp',
    '.gif': 'image/gif', '.svg': 'image/svg+xml', '.woff2': 'font/woff2', '.woff': 'font/woff', '.ttf': 'font/ttf',
    '.otf': 'font/otf', '.wav': 'audio/wav', '.mp3': 'audio/mpeg', '.mp4': 'video/mp4',
  };
  const base = path.resolve(root) + path.sep;
  const server = http.createServer((req, res) => {
    const url = decodeURIComponent(new URL(req.url, 'http://x').pathname);
    let file = path.resolve(base, '.' + url);
    if (!(file + path.sep).startsWith(base) && file + path.sep !== base) { res.writeHead(403).end(); return; }
    if (fs.existsSync(file) && fs.statSync(file).isDirectory()) file = path.join(file, 'index.html');
    fs.readFile(file, (e, buf) => {
      if (e) { res.writeHead(404).end(); return; }
      res.writeHead(200, { 'content-type': MIME[path.extname(file).toLowerCase()] ?? 'application/octet-stream', 'cache-control': 'no-store' });
      res.end(buf);
    });
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  return { url: `http://127.0.0.1:${server.address().port}`, close: () => server.close() };
}

// --- Audio I/O ---------------------------------------------------------------
// Decode any audio file to Float32 channel arrays at SR via ffmpeg.
export function decodeAudio(file, { channels = 2, sr = SR } = {}) {
  const r = spawnSync('ffmpeg', ['-v', 'error', '-i', file, '-f', 'f32le', '-ac', String(channels), '-ar', String(sr), '-'], { maxBuffer: 1 << 30 });
  if (r.status !== 0) die(`cannot decode ${rel(file)}: ${r.stderr}`);
  const all = new Float32Array(r.stdout.buffer, r.stdout.byteOffset, r.stdout.byteLength / 4);
  const n = all.length / channels;
  const out = Array.from({ length: channels }, () => new Float32Array(n));
  for (let i = 0; i < n; i++) for (let c = 0; c < channels; c++) out[c][i] = all[i * channels + c];
  return out;
}

// Write 32-bit float WAV (format tag 3). chans: Float32Array[].
export function writeWav(file, chans, sr = SR) {
  const nc = chans.length, n = chans[0].length;
  const buf = Buffer.alloc(44 + n * nc * 4);
  buf.write('RIFF', 0); buf.writeUInt32LE(36 + n * nc * 4, 4); buf.write('WAVE', 8);
  buf.write('fmt ', 12); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(3, 20); buf.writeUInt16LE(nc, 22);
  buf.writeUInt32LE(sr, 24); buf.writeUInt32LE(sr * nc * 4, 28); buf.writeUInt16LE(nc * 4, 32); buf.writeUInt16LE(32, 34);
  buf.write('data', 36); buf.writeUInt32LE(n * nc * 4, 40);
  let o = 44;
  for (let i = 0; i < n; i++) for (let c = 0; c < nc; c++) { buf.writeFloatLE(chans[c][i] || 0, o); o += 4; }
  mkdirp(path.dirname(file));
  fs.writeFileSync(file, buf);
}

export function peak(chans) {
  let p = 0;
  for (const c of chans) for (let i = 0; i < c.length; i++) { const a = Math.abs(c[i]); if (a > p) p = a; }
  return p;
}

export function normalizePeak(chans, dbfs = -3) {
  const p = peak(chans) || 1, g = 10 ** (dbfs / 20) / p;
  for (const c of chans) for (let i = 0; i < c.length; i++) c[i] *= g;
  return chans;
}

// Integrated loudness + true peak via ffmpeg ebur128.
export function loudness(file) {
  const r = run('ffmpeg', ['-hide_banner', '-nostats', '-i', file, '-af', 'ebur128=peak=true', '-f', 'null', '-'], { allowFail: true });
  const s = r.stderr.slice(r.stderr.lastIndexOf('Summary:'));
  const num = (re) => { const m = s.match(re); if (!m) return NaN; const v = m[1].trim(); return v === '-inf' ? -Infinity : Number(v); };
  return { I: num(/I:\s+(-?[\d.inf]+) LUFS/), LRA: num(/LRA:\s+(-?[\d.inf]+) LU/), TP: num(/Peak:\s+(-?[\d.inf]+) dBFS/) };
}

// Seeded PRNG used by every generator so audio and picture are reproducible.
export function mulberry32(a) {
  return () => {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
