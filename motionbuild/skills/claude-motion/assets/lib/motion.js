// claude-motion runtime. A film is a pure function of time: window.seek(t)
// paints frame t, nothing else. No timers, no rAF in render mode, no state
// carried between frames, seeded noise only. The renderer seeks frames out of
// order across parallel pages, so hidden state makes frames disagree.

export const TAU = Math.PI * 2;
const Q = new URLSearchParams(location.search);
export const RENDER = Q.get('render') === '1';

// ---------------------------------------------------------------- format ---
const SIZES = { '16x9': [1920, 1080], '9x16': [1080, 1920], '1x1': [1080, 1080] };
// Safe insets [left, top, right, bottom] in px. 9x16 keeps clear of the
// TikTok/Reels/Shorts chrome (caption + handle at the bottom, action rail right).
const SAFE = { '16x9': [96, 60, 96, 60], '9x16': [72, 250, 150, 430], '1x1': [72, 72, 72, 72] };
const fmtName = SIZES[Q.get('format')] ? Q.get('format') : '16x9';
export const W = Number(Q.get('w')) || SIZES[fmtName][0];
export const H = Number(Q.get('h')) || SIZES[fmtName][1];
const [sl, st, sr, sb] = SAFE[fmtName];
export const FORMAT = {
  name: fmtName, w: W, h: H,
  portrait: fmtName === '9x16', square: fmtName === '1x1', landscape: fmtName === '16x9',
  safe: { x: sl, y: st, w: W - sl - sr, h: H - st - sb, cx: sl + (W - sl - sr) / 2, cy: st + (H - st - sb) / 2 },
  // FORMAT.pick({ '16x9': a, '9x16': b, '1x1': c }) — falls back to 16x9.
  pick: (o) => (fmtName in o ? o[fmtName] : o['16x9']),
};

// ------------------------------------------------------------------ grid ---
// Filled from beats.json before draw is ever called. t = offset + u * period.
export const GRID = { bpm: 120, period: 0.5, offset: 0, beats: [], downbeats: [], sections: {} };
export const CFG = { duration: 15, fps: 60, title: '' };
export const U = (t) => (t - GRID.offset) / GRID.period;   // seconds -> beats
export const T = (u) => GRID.offset + u * GRID.period;     // beats -> seconds

// ------------------------------------------------------------------ math ---
export const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
export const lerp = (a, b, t) => a + (b - a) * t;
export const prog = (u, a, b) => clamp((u - a) / (b - a));           // 0..1 over [a,b]
export const bump = (u, c, w) => { const x = (u - c) / w; return Math.abs(x) >= 1 ? 0 : Math.cos(x * Math.PI / 2) ** 2; };
export const remap = (x, a, b, c, d) => c + (d - c) * clamp((x - a) / (b - a));

// ---------------------------------------------------------------- easing ---
function bezier(x1, y1, x2, y2) {
  const bx = (t) => 3 * x1 * t * (1 - t) ** 2 + 3 * x2 * t * t * (1 - t) + t ** 3;
  const by = (t) => 3 * y1 * t * (1 - t) ** 2 + 3 * y2 * t * t * (1 - t) + t ** 3;
  return (x) => {
    if (x <= 0) return 0; if (x >= 1) return 1;
    let lo = 0, hi = 1;
    for (let i = 0; i < 28; i++) { const m = (lo + hi) / 2; if (bx(m) < x) lo = m; else hi = m; }
    return by((lo + hi) / 2);
  };
}
export const E = {
  linear: (t) => t,
  inQuad: (t) => t * t, outQuad: (t) => 1 - (1 - t) ** 2,
  inCubic: (t) => t ** 3, outCubic: (t) => 1 - (1 - t) ** 3,
  inOutCubic: (t) => (t < 0.5 ? 4 * t ** 3 : 1 - (-2 * t + 2) ** 3 / 2),
  outQuart: (t) => 1 - (1 - t) ** 4, outQuint: (t) => 1 - (1 - t) ** 5,
  inExpo: (t) => (t <= 0 ? 0 : 2 ** (10 * t - 10)),
  outExpo: (t) => (t >= 1 ? 1 : 1 - 2 ** (-10 * t)),
  inOutExpo: (t) => (t <= 0 ? 0 : t >= 1 ? 1 : t < 0.5 ? 2 ** (20 * t - 10) / 2 : (2 - 2 ** (-20 * t + 10)) / 2),
  inOutSine: (t) => -(Math.cos(Math.PI * t) - 1) / 2,
  outBack: (t, s = 1.70158) => 1 + (s + 1) * (t - 1) ** 3 + s * (t - 1) ** 2,
  inBack: (t, s = 1.70158) => (s + 1) * t ** 3 - s * t * t,
  // Material "standard" and "emphasized decelerate" curves.
  standard: bezier(0.2, 0, 0, 1),
  decel: bezier(0.05, 0.7, 0.1, 1),
  accel: bezier(0.3, 0, 0.8, 0.15),
  bezier,
};

// Keyframes in beats: kf(u, [[u0, v0], [u1, v1, ease?], ...]) — numbers or arrays.
// The ease on a key shapes the segment that ENDS at that key.
export function kf(u, keys, ease = E.inOutCubic) {
  if (u <= keys[0][0]) return keys[0][1];
  for (let i = 1; i < keys.length; i++) {
    const [u1, v1, e1] = keys[i];
    if (u <= u1) {
      const [u0, v0] = keys[i - 1];
      const p = (e1 ?? ease)((u - u0) / (u1 - u0 || 1));
      return Array.isArray(v0) ? v0.map((a, j) => lerp(a, v1[j], p)) : lerp(v0, v1, p);
    }
  }
  return keys[keys.length - 1][1];
}

// --------------------------------------------------------------- springs ---
// Closed-form damped spring step response (0 -> 1), t in seconds. Pure.
export function spring(t, { stiffness = 170, damping = 18, mass = 1, velocity = 0 } = {}) {
  if (t <= 0) return 0;
  const w0 = Math.sqrt(stiffness / mass), z = damping / (2 * Math.sqrt(stiffness * mass)), v = velocity;
  if (z < 1) {
    const wd = w0 * Math.sqrt(1 - z * z);
    return 1 - Math.exp(-z * w0 * t) * (Math.cos(wd * t) + ((z * w0 - v) / wd) * Math.sin(wd * t));
  }
  if (z === 1) return 1 - Math.exp(-w0 * t) * (1 + (w0 - v) * t);
  const s = w0 * Math.sqrt(z * z - 1), r1 = -z * w0 + s, r2 = -z * w0 - s;
  const c2 = (v + r1) / (r2 - r1), c1 = -1 - c2;
  return 1 + c1 * Math.exp(r1 * t) + c2 * Math.exp(r2 * t);
}
// Presets (measured peak): snappy 2% overshoot, settles ~0.25 s; bouncy 25%;
// gentle no overshoot, slow and soft; wobbly 37%, cartoon.
export const SPRING = {
  snappy: { stiffness: 380, damping: 30 },
  bouncy: { stiffness: 260, damping: 13 },
  gentle: { stiffness: 120, damping: 20 },
  wobbly: { stiffness: 180, damping: 8 },
};
// Spring from beat u0 (time measured in seconds so feel is tempo-independent).
export const springU = (u, u0, cfg = SPRING.snappy) => spring((u - u0) * GRID.period, cfg);
// Chained targets: springKeys(u, [[0, 0], [4, 100], [8, 40]]). Each step's
// delta is superposed, so an interrupted move stays physical.
export function springKeys(u, keys, cfg = SPRING.snappy) {
  let v = keys[0][1];
  const arr = Array.isArray(v);
  v = arr ? [...v] : v;
  for (let i = 1; i < keys.length; i++) {
    const [ui, vi, c] = keys[i], [, vp] = keys[i - 1], s = springU(u, ui, c ?? cfg);
    if (arr) v = v.map((a, j) => a + (vi[j] - vp[j]) * s); else v += (vi - vp) * s;
  }
  return v;
}
// Damped oscillations after beat u0 (u in beats), for secondary motion.
export const wobble = (u, u0, freq = 2.2, damp = 5) => (u < u0 ? 0 : Math.cos(TAU * freq * (u - u0) * GRID.period) * Math.exp(-damp * (u - u0) * GRID.period));
export const ring = (u, u0, freq = 2.2, damp = 5) => (u < u0 ? 0 : Math.sin(TAU * freq * (u - u0) * GRID.period) * Math.exp(-damp * (u - u0) * GRID.period));

// ----------------------------------------------------------------- noise ---
export function mulberry32(a) {
  return () => {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
export const hash01 = (i, seed = 1) => mulberry32((i * 374761393 + seed * 668265263) | 0)();
export function noise1(x, seed = 1) {
  const i = Math.floor(x), f = x - i, s = f * f * (3 - 2 * f);
  return lerp(hash01(i, seed), hash01(i + 1, seed), s) * 2 - 1;
}
// Camera shake that decays after beat u0. Translates ctx.
export function shake(ctx, u, u0, amp = 12, seed = 3, decay = 0.25) {
  if (u < u0) return;
  const d = (u - u0) * GRID.period, k = amp * Math.exp(-d / decay);
  if (k < 0.05) return;
  ctx.translate(noise1(d * 30, seed) * k, noise1(d * 30, seed + 9) * k);
}

// ---------------------------------------------------------------- colour ---
export function hexRgb(h) {
  h = h.replace('#', '');
  if (h.length === 3) h = [...h].map((c) => c + c).join('');
  const n = parseInt(h.slice(0, 6), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}
export const rgbHex = (r, g, b) => '#' + [r, g, b].map((v) => Math.round(clamp(v, 0, 255)).toString(16).padStart(2, '0')).join('');
export const mix = (a, b, t) => { const A = hexRgb(a), B = hexRgb(b); return rgbHex(...A.map((v, i) => lerp(v, B[i], clamp(t)))); };
export const rgba = (hex, a) => { const [r, g, b] = hexRgb(hex); return `rgba(${r},${g},${b},${clamp(a)})`; };

// ------------------------------------------------------------------ type ---
// Fonts are named 'Display' and 'UI' by index.html @font-face rules.
export const font = (size, weight = 700, family = 'Display') => `${weight} ${size}px ${family}, system-ui, sans-serif`;
const layoutCache = new Map();
// Per-glyph layout with kerning (prefix measurement) and tracking in em.
export function layout(ctx, str, f, track = 0) {
  const key = `${f}|${track}|${str}`;
  if (layoutCache.has(key)) return layoutCache.get(key);
  ctx.save(); ctx.font = f; ctx.letterSpacing = '0px';
  const size = parseFloat(f.match(/(\d+(?:\.\d+)?)px/)?.[1] ?? 16), tp = track * size;
  const glyphs = []; let prev = 0;
  for (let i = 0; i < str.length; i++) {
    const w = ctx.measureText(str.slice(0, i + 1)).width, adv = w - prev;
    glyphs.push({ ch: str[i], x: prev + i * tp, adv, cx: prev + i * tp + adv / 2 });
    prev = w;
  }
  const m = ctx.measureText(str);
  const out = { glyphs, width: prev + Math.max(0, str.length - 1) * tp, asc: m.actualBoundingBoxAscent, desc: m.actualBoundingBoxDescent, size };
  ctx.restore();
  layoutCache.set(key, out);
  return out;
}
// Largest size <= max such that str fits maxW (tracking in em).
export function fitSize(ctx, str, maxW, { weight = 700, family = 'Display', max = 400, min = 8, track = 0 } = {}) {
  let lo = min, hi = max;
  for (let i = 0; i < 18; i++) { const m = (lo + hi) / 2; if (layout(ctx, str, font(m, weight, family), track).width <= maxW) lo = m; else hi = m; }
  return Math.floor(lo);
}
export function text(ctx, str, x, y, f, color, { align = 'left', track = 0, alpha = 1 } = {}) {
  const L = layout(ctx, str, f, track);
  const x0 = align === 'center' ? x - L.width / 2 : align === 'right' ? x - L.width : x;
  ctx.save(); ctx.font = f; ctx.fillStyle = color; ctx.globalAlpha *= clamp(alpha); ctx.textAlign = 'left';
  for (const g of L.glyphs) ctx.fillText(g.ch, x0 + g.x, y);
  ctx.restore();
  return L;
}
// Animated per-glyph text. fn(i, n) -> {dx, dy, sx, sy, rot, alpha, color}.
export function glyphs(ctx, str, x, y, f, color, fn, { align = 'left', track = 0 } = {}) {
  const L = layout(ctx, str, f, track), n = L.glyphs.length;
  const x0 = align === 'center' ? x - L.width / 2 : align === 'right' ? x - L.width : x;
  ctx.save(); ctx.font = f; ctx.textAlign = 'center';
  L.glyphs.forEach((g, i) => {
    const o = fn(i, n, g) ?? {};
    const a = o.alpha ?? 1; if (a <= 0) return;
    ctx.save();
    ctx.translate(x0 + g.cx + (o.dx ?? 0), y + (o.dy ?? 0));
    if (o.rot) ctx.rotate(o.rot);
    ctx.scale(o.sx ?? 1, o.sy ?? 1);
    ctx.globalAlpha *= clamp(a); ctx.fillStyle = o.color ?? color;
    ctx.fillText(g.ch, 0, 0);
    ctx.restore();
  });
  ctx.restore();
  return L;
}
// Word-wrap to maxW; returns lines.
export function wrap(ctx, str, f, maxW, track = 0) {
  const words = str.split(/\s+/), lines = []; let cur = '';
  for (const w of words) {
    const t = cur ? cur + ' ' + w : w;
    if (layout(ctx, t, f, track).width > maxW && cur) { lines.push(cur); cur = w; } else cur = t;
  }
  if (cur) lines.push(cur);
  return lines;
}

// -------------------------------------------------------- shapes & images ---
export const fill = (ctx, color) => { ctx.save(); ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.fillStyle = color; ctx.fillRect(0, 0, W, H); ctx.restore(); };
export function rrect(ctx, x, y, w, h, r) {
  r = Math.max(0, Math.min(r, w / 2, h / 2));
  ctx.beginPath(); ctx.roundRect(x, y, w, h, r);
}
export function zoomAbout(ctx, s, x, y) { ctx.translate(x, y); ctx.scale(s, s); ctx.translate(-x, -y); }
// Cover-fit img into box, focal point (fx, fy) in 0..1, optional zoom and radius.
export function cover(ctx, img, x, y, w, h, { fx = 0.5, fy = 0.5, zoom = 1, radius = 0, alpha = 1 } = {}) {
  if (!img) return;
  const iw = img.naturalWidth ?? img.width, ih = img.naturalHeight ?? img.height;
  const s = Math.max(w / iw, h / ih) * zoom, dw = iw * s, dh = ih * s;
  const dx = x + (w - dw) * fx, dy = y + (h - dh) * fy;
  ctx.save(); ctx.globalAlpha *= clamp(alpha);
  if (radius) { rrect(ctx, x, y, w, h, radius); ctx.clip(); } else { ctx.beginPath(); ctx.rect(x, y, w, h); ctx.clip(); }
  ctx.drawImage(img, dx, dy, dw, dh);
  ctx.restore();
}
export function crop(ctx, img, [sx, sy, sw, sh], x, y, w, h) { if (img) ctx.drawImage(img, sx, sy, sw, sh, x, y, w, h); }
// Soft drop shadow helper (keep it subtle: banned default is glow on UI chrome).
export function shadow(ctx, blur = 40, y = 18, a = 0.25) { ctx.shadowColor = `rgba(0,0,0,${a})`; ctx.shadowBlur = blur; ctx.shadowOffsetY = y; }

// Canvas silently IGNORES a negative globalAlpha (keeps the old value), and
// springs overshoot, so `1 - spring` can dip below 0. Always set alpha via this.
export const alpha = (ctx, a) => { ctx.globalAlpha = clamp(a); };

// --------------------------------------------------------------- harness ---
// film({ draw(ctx, u, t, IMG), init?, fonts: [cssFont], images: {key: url}, hits, samples, shutter })
export async function film({ draw, init, fonts = [], images = {}, hits = [], samples = 8, shutter = 0.5 }) {
  samples = Math.min(256, Math.max(1, Number(Q.get('samples')) || samples)); // 16-bit lane headroom: 256 * 255 < 65536
  const canvas = document.getElementById('film');
  canvas.width = W; canvas.height = H;
  document.documentElement.style.setProperty('--aspect', `${W}/${H}`);
  if (RENDER) document.body.classList.add('render');

  const fetchJSON = (u) => fetch(u, { cache: 'no-store' }).then((r) => (r.ok ? r.json() : null)).catch(() => null);
  const [beats, cfg] = await Promise.all([fetchJSON('beats.json'), fetchJSON('film.json')]);
  if (!beats) console.error('beats.json missing: run score.mjs first');
  Object.assign(GRID, beats ?? {});
  Object.assign(CFG, cfg ?? {});
  const fps = Number(Q.get('fps')) || CFG.fps || 60;

  await Promise.all(fonts.map((f) => document.fonts.load(f, 'AaBb0123').catch((e) => console.error('font', f, e))));
  for (const f of fonts) if (!document.fonts.check(f)) console.error(`font not loaded: ${f} (falling back)`);
  const IMG = {};
  await Promise.all(Object.entries(images).map(async ([k, src]) => {
    const im = new Image(); im.src = src;
    try { await im.decode(); IMG[k] = im; } catch { console.error('image failed', src); }
  }));

  const ctx = canvas.getContext('2d', { alpha: false });
  const buf = new OffscreenCanvas(W, H), bctx = buf.getContext('2d', { alpha: false });
  const paint = (c, t) => {
    c.setTransform(1, 0, 0, 1, 0, 0); c.globalAlpha = 1; c.globalCompositeOperation = 'source-over';
    c.textBaseline = 'alphabetic'; c.shadowColor = 'transparent'; c.filter = 'none';
    draw(c, U(t), t, IMG);
  };
  await init?.(ctx, IMG); // may be async (e.g. fetch lipsync.json); frame 0 waits for it

  const blur = RENDER && Q.get('blur') !== '0' && samples > 1;
  // Motion blur: frame t shows the shutter interval [t, t + shutter/fps].
  // First and last samples are compared on a tiny proxy; a frame that doesn't
  // move is painted once (exact, fast). Moving frames sum `samples` sub-frames
  // exactly in integers (two 16-bit lanes per 32-bit add), so no 8-bit banding.
  const pw = 96, ph = Math.max(1, Math.round(96 * H / W));
  const probe = new OffscreenCanvas(pw, ph), pctx = probe.getContext('2d', { willReadFrequently: true });
  const proxy = (c) => { pctx.drawImage(c, 0, 0, pw, ph); return pctx.getImageData(0, 0, pw, ph).data; };
  let accRB = null, accGA = null;
  const out = blur ? new ImageData(W, H) : null;
  window.seek = (t) => {
    if (!blur) { paint(ctx, t); return; }
    const span = shutter / fps, st = (k) => t + ((k + 0.5) / samples) * span;
    paint(bctx, st(0)); const a = proxy(buf);
    paint(bctx, st(samples - 1)); const b = proxy(buf);
    let diff = 0;
    for (let i = 0; i < a.length; i += 4) diff = Math.max(diff, Math.abs(a[i] - b[i]), Math.abs(a[i + 1] - b[i + 1]), Math.abs(a[i + 2] - b[i + 2]));
    if (diff <= 2) { paint(ctx, t + span / 2); return; }
    const n = W * H;
    accRB ??= new Uint32Array(n); accGA ??= new Uint32Array(n);
    accRB.fill(0); accGA.fill(0);
    for (let k = samples - 1; k >= 0; k--) {
      if (k !== samples - 1) paint(bctx, st(k)); // the last sample is already in buf
      const px = new Uint32Array(bctx.getImageData(0, 0, W, H).data.buffer);
      for (let i = 0; i < n; i++) { const v = px[i]; accRB[i] += v & 0x00ff00ff; accGA[i] += (v >>> 8) & 0x00ff00ff; }
    }
    const o = new Uint32Array(out.data.buffer), half = samples >> 1;
    for (let i = 0; i < n; i++) {
      const rb = accRB[i], ga = accGA[i];
      const r = ((rb & 0xffff) + half) / samples, bl = ((rb >>> 16) + half) / samples, g = ((ga & 0xffff) + half) / samples;
      o[i] = (255 << 24) | ((bl & 255) << 16) | ((g & 255) << 8) | (r & 255);
    }
    ctx.putImageData(out, 0, 0);
  };
  // Lossless capture for the renderer.
  window.capture = async (t) => { window.seek(t); return canvas.toDataURL('image/png'); };
  window.HITS = hits;
  window.DURATION = CFG.duration;
  window.FPS = fps;
  window.seek(0);
  window.filmReady = true;
  if (!RENDER) preview(canvas, fps);
}

// Preview player: space play/pause, ←/→ frame step, click to scrub, M mute.
function preview(canvas, fps) {
  const hud = document.getElementById('hud');
  const audio = new Audio();
  audio.src = 'audio/mix.wav';
  audio.onerror = () => { if (!audio.src.endsWith('music.wav')) audio.src = 'audio/music.wav'; };
  let t = 0, playing = false, t0 = 0, a0 = 0;
  const dur = CFG.duration;
  const show = () => { window.seek(t); if (hud) hud.textContent = `${t.toFixed(2)}s · beat ${U(t).toFixed(2)} · ${FORMAT.name} · space play · ←/→ step · click scrub`; };
  const loop = (now) => {
    if (!playing) return;
    t = audio.readyState >= 2 && !audio.paused ? audio.currentTime : (a0 + (now - t0) / 1000);
    if (t >= dur) { t = 0; audio.currentTime = 0; a0 = 0; t0 = now; }
    show(); requestAnimationFrame(loop);
  };
  const toggle = () => {
    playing = !playing;
    if (playing) { a0 = t; t0 = performance.now(); audio.currentTime = t; audio.play().catch(() => {}); requestAnimationFrame(loop); }
    else audio.pause();
  };
  addEventListener('keydown', (e) => {
    if (e.code === 'Space') { e.preventDefault(); toggle(); }
    if (e.code === 'ArrowRight') { t = Math.min(dur, t + 1 / fps); show(); }
    if (e.code === 'ArrowLeft') { t = Math.max(0, t - 1 / fps); show(); }
    if (e.code === 'KeyM') audio.muted = !audio.muted;
  });
  canvas.addEventListener('click', (e) => {
    const r = canvas.getBoundingClientRect();
    t = ((e.clientX - r.left) / r.width) * dur; audio.currentTime = t; a0 = t; t0 = performance.now(); show();
  });
  show();
}
