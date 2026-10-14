// HERO: The Domini. A Federation recruitment broadcast for the Domini (see docs/shotlist.md).
// Pure function of time: window.seek(t) paints frame t (lib/motion.js). Timing is in beats (u) on
// the grid measured by tools/song-analyzer (beats.json: u = 0 is the first downbeat of the excerpt;
// bar k starts at u = 4k). Audio-reactive values come from analysis/cues.json, per-frame envelopes
// precomputed from the song, so every frame stays a pure function of t.

import * as M from './lib/motion.js';
import * as T from './lib/three-lite.js';
import * as Hd from './lib/heraldry.js';
import * as D from './lib/domini.js';

const { W, H, E, TAU, clamp, lerp, prog, bump, springU, SPRING, kf, font, hash01 } = M;
const P = D.DP;
const DISPLAY = 'Display', UI = 'UI';

// ---------------------------------------------------------------- cues (song envelopes)
let CUE = null;
function cue(name, t) {
  if (!CUE || !CUE[name]) return 0;
  const a = CUE[name], f = t * CUE.fps;
  const i = Math.floor(f);
  if (i < 0) return a[0];
  if (i >= a.length - 1) return a[a.length - 1];
  return a[i] + (a[i + 1] - a[i]) * (f - i);
}

// Every planned accent on the grid: [beat, label]. The song is the soundtrack (no SFX).
const HITS = [
  [0, 'into the hood: the seal'], [4, 'crown lands'], [6, 'THE DOMINI'], [8, 'the order'], [15, 'crash flash'],
  [16, 'wanted: beamers'], [17, 'wanted: fake giveaways'], [18, 'wanted: exploiters'], [19, 'captured'],
  [20, 'WE HUNT'], [24, 'WE CAPTURE'], [28, 'WE RESTORE'], [32, 'ladder: claves'], [33, 'venari'], [34, 'four branches'],
  [36, 'vespertilio'], [37, 'messor + aureus'], [38, 'the houses'], [40, 'FROM SEA TO SEA'], [44, 'SEIZE THE NIGHT'],
  [48, 'the raid'], [52, 'NO SCAMMER HIDES'], [57, 'beams lock: captured'], [60, 'restitution'], [62, 'RETURNED'],
  [64, 'dropout: the empty seat'], [68, 'impact: three houses'], [72, 'ONE LORD'], [76, 'band out: the crown'],
  [80, 'final chorus: Lord Emperyan'], [84, 'honour guard'], [88, 'the court'], [98, 'the sword'], [100, 'ONE ORDER'],
  [104, 'ONE CROWN'], [108, 'ONE LORD'], [110, 'earn your rank'], [120, 'the host'], [128, 'THE HOOD IS WATCHING'],
  [136, 'held note: the smile'], [140, 'insignia'], [152, 'the seal'], [156, 'end card'],
];

// ---------------------------------------------------------------- 3D models (built once)
const rgb = Hd.rgb;
const GOLD = rgb(P.gold), GOLDHI = rgb(P.goldHi), COBALT = rgb(P.cobalt);

function tube(path, widths, opts) {
  // square-section prisms between consecutive points (each part convex)
  const parts = [];
  for (let i = 0; i < path.length - 1; i++) {
    const a = path[i], b = path[i + 1], wa = widths[i], wb = widths[i + 1];
    const d = T.norm(T.sub(b, a));
    let n1 = T.norm(T.cross(d, [0, 0, 1]));
    if (T.len(T.cross(d, [0, 0, 1])) < 1e-3) n1 = [1, 0, 0];
    const n2 = T.norm(T.cross(d, n1));
    const sq = (c, w) => [[1, 1], [-1, 1], [-1, -1], [1, -1]].map(([p, q]) => T.add(c, T.add(T.mul(n1, p * w), T.mul(n2, q * w))));
    const v = [...sq(a, wa), ...sq(b, wb)];
    parts.push(T.part(v, [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]], opts));
  }
  return parts;
}

function buildLordCrown() {
  const parts = [];
  parts.push(...T.lathe([[1.0, 0], [1.04, 0.03], [1.04, 0.29], [1.0, 0.32]], 32, { c: GOLD, spec: 0.9, shin: 26, twoSided: true, edge: P.goldLo }));
  for (let k = 0; k < 12; k++) {
    const a = (k / 12) * TAU;
    parts.push(T.box(0.14, 0.14, 0.05, { c: COBALT, spec: 1.2, shin: 50 }, [Math.cos(a) * 1.06, 0.16, Math.sin(a) * 1.06]));
  }
  // tall four-point star at the front (z = -1), cobalt, top point long
  const star = T.starParts(4, 1, 0.24, 0.16, { c: COBALT, spec: 1.1, shin: 36, edge: P.gold });
  for (const p of star) {
    p.v = p.v.map(([x, y, z]) => [x * 0.42, 0.5 - (y < 0 ? y * 1.25 : y * 0.45), -1.08 + z]);
  }
  parts.push(...star);
  // three gold crescents standing on the band
  for (const [th, r] of [[-Math.PI / 2 + 0.62, 0.22], [-Math.PI / 2 + 1.05, 0.16], [-Math.PI / 2 - 0.7, 0.18]]) {
    const t = [-Math.sin(th), 0, Math.cos(th)], cen = [Math.cos(th) * 1.02, 0.32 + r * 0.95, Math.sin(th) * 1.02];
    const pts = [], ws = [];
    const N = 10;
    for (let i = 0; i <= N; i++) {
      const a = -0.25 * Math.PI + (i / N) * 1.45 * Math.PI;
      pts.push(T.add(cen, T.add(T.mul(t, Math.cos(a) * r), [0, Math.sin(a) * r, 0])));
      ws.push(0.012 + 0.05 * Math.sin(Math.PI * i / N));
    }
    parts.push(...tube(pts, ws, { c: GOLDHI, spec: 1.0, shin: 30 }));
  }
  return parts;
}
const LORD3D = buildLordCrown();

// Night city for the raid: block towers on a grid, one marked as the target.
const TOWERS = [];
for (let gx = -9; gx <= 9; gx++) {
  for (let gz = 0; gz < 34; gz++) {
    if (gx === 0 || Math.abs(gx) === 5) continue; // avenues
    const h = hash01(gx * 131 + gz, 3);
    if (h < 0.18) continue;
    const ht = 2 + 9 * h * h + (hash01(gx * 7 + gz * 3, 5) < 0.08 ? 8 : 0);
    TOWERS.push({ x: gx * 3.2, z: gz * 3.4, w: 2.2 + hash01(gx + gz * 17, 6) * 0.6, h: ht, roof: hash01(gx * 13 + gz, 8) });
  }
}
const TARGET = TOWERS.reduce((best, t) => (Math.abs(t.x - 3.2) + Math.abs(t.z - 64) < Math.abs(best.x - 3.2) + Math.abs(best.z - 64) ? t : best), TOWERS[0]);
const CITY = TOWERS.map((t) => ({ t, parts: [T.box(t.w, t.h, t.w, { c: t === TARGET ? [0.32, 0.1, 0.12] : [0.12, 0.15, 0.27], spec: 0.15, shin: 10, edge: t === TARGET ? '#FF5A4A' : P.goldLo }, [0, t.h / 2, 0])] }));

// ---------------------------------------------------------------- precomputed 2D data
const LEAVES = Array.from({ length: 140 }, (_, i) => ({
  a: hash01(i, 11) * TAU, v: 900 + 1500 * hash01(i, 12), spin: (hash01(i, 13) - 0.5) * 14,
  s: 10 + 22 * hash01(i, 14), c: hash01(i, 15) < 0.7 ? (hash01(i, 16) < 0.5 ? P.goldHi : P.gold) : P.cobaltHi, d: hash01(i, 17) * 0.25,
}));
const ITEMS = Array.from({ length: 36 }, (_, i) => ({ k: Math.floor(hash01(i, 41) * 3), d: hash01(i, 42) * 3.2, y: hash01(i, 43), arc: 0.5 + hash01(i, 44), to: Math.floor(hash01(i, 45) * 5) }));

// ---------------------------------------------------------------- textures (seeded, built in init)
let GRAIN = [], VIGNETTE = null, PAPER = null;
function buildTextures() {
  for (let g = 0; g < 4; g++) {
    const cv = document.createElement('canvas'); cv.width = 640; cv.height = 360;
    const c = cv.getContext('2d'); const img = c.createImageData(640, 360);
    const rnd = M.mulberry32(1000 + g * 77);
    for (let i = 0; i < img.data.length; i += 4) { const v = 128 + (rnd() - 0.5) * 255; img.data[i] = img.data[i + 1] = img.data[i + 2] = v; img.data[i + 3] = 255; }
    c.putImageData(img, 0, 0); GRAIN.push(cv);
  }
  VIGNETTE = document.createElement('canvas'); VIGNETTE.width = W; VIGNETTE.height = H;
  const v = VIGNETTE.getContext('2d');
  const gr = v.createRadialGradient(W / 2, H / 2, H * 0.35, W / 2, H / 2, H * 1.05);
  gr.addColorStop(0, 'rgba(0,0,0,0)'); gr.addColorStop(1, 'rgba(0,0,0,0.6)');
  v.fillStyle = gr; v.fillRect(0, 0, W, H);
  PAPER = document.createElement('canvas'); PAPER.width = W; PAPER.height = H;
  const p = PAPER.getContext('2d');
  p.fillStyle = P.ivory; p.fillRect(0, 0, W, H);
  const rnd = M.mulberry32(42);
  for (let i = 0; i < 2600; i++) {
    p.strokeStyle = `rgba(120,90,40,${0.03 + rnd() * 0.05})`; p.lineWidth = 0.6 + rnd();
    const x = rnd() * W, y = rnd() * H, a = rnd() * TAU, l = 4 + rnd() * 18;
    p.beginPath(); p.moveTo(x, y); p.lineTo(x + Math.cos(a) * l, y + Math.sin(a) * l); p.stroke();
  }
  const pg = p.createRadialGradient(W / 2, H / 2, H * 0.2, W / 2, H / 2, H);
  pg.addColorStop(0, 'rgba(255,250,235,0)'); pg.addColorStop(1, 'rgba(150,110,50,0.28)');
  p.fillStyle = pg; p.fillRect(0, 0, W, H);
}

// ---------------------------------------------------------------- helpers

function slam(ctx, str, x, y, size, family, weight, color, u, u0, o = {}) {
  const k = springU(u, u0, o.spring || SPRING.snappy);
  if (k <= 0) return;
  const s = 1 + (o.from ?? 0.9) * (1 - k);
  let a = clamp(k * 2.5), dx = 0;
  if (o.u1 !== undefined) {
    const e = E.inBack(prog(u, o.u1, o.u1 + (o.outLen || 0.5)), 1.6);
    if (e >= 1) return;
    dx = (o.outDir ?? -1) * e * (W * 0.9); a *= 1 - e * 0.3;
  }
  ctx.save();
  ctx.translate(x + dx, y); ctx.scale(s, s); ctx.rotate((o.rot || 0) * (1 - Math.min(1, k)));
  ctx.globalAlpha *= a;
  ctx.font = font(size, weight, family);
  ctx.letterSpacing = `${(o.track || 0) * size}px`;
  ctx.textAlign = o.align || 'center'; ctx.textBaseline = 'alphabetic';
  if (o.plate) {
    const w = ctx.measureText(str).width;
    const px = o.align === 'left' ? -size * 0.25 : o.align === 'right' ? -w - size * 0.25 : -w / 2 - size * 0.25;
    ctx.fillStyle = o.plate; ctx.fillRect(px, -size * 0.92, w + size * 0.5, size * 1.12);
  }
  if (o.shadow) { ctx.fillStyle = o.shadow; ctx.fillText(str, size * 0.04, size * 0.04); }
  ctx.fillStyle = color; ctx.fillText(str, 0, 0);
  ctx.letterSpacing = '0px';
  ctx.restore();
}

function typeOn(ctx, str, x, y, size, family, weight, color, u, u0, rate = 0.25, track = 0.08) {
  const f = font(size, weight, family);
  const L = M.layout(ctx, str, f, track * size);
  const x0 = x - L.width / 2;
  L.glyphs.forEach((g, i) => {
    const k = springU(u, u0 + i * rate, SPRING.snappy);
    if (k <= 0) return;
    ctx.save(); ctx.globalAlpha *= clamp(k * 3);
    M.glyph(ctx, g.ch, x0 + g.cx, y - (1 - k) * size * 0.4, f, color);
    ctx.restore();
  });
}

function spaced(ctx, str, x, y, size, family, weight, color, track = 0.3, align = 'center', alpha = 1) {
  if (alpha <= 0) return;
  ctx.save(); ctx.globalAlpha *= alpha;
  ctx.font = font(size, weight, family); ctx.letterSpacing = `${track * size}px`;
  ctx.textAlign = align; ctx.fillStyle = color; ctx.fillText(str, x + (align === 'center' ? track * size / 2 : 0), y);
  ctx.letterSpacing = '0px'; ctx.restore();
}

function vgrad(ctx, stops, y0 = 0, y1 = H) {
  const g = ctx.createLinearGradient(0, y0, 0, y1);
  stops.forEach(([o, c]) => g.addColorStop(o, c));
  ctx.fillStyle = g; ctx.fillRect(-50, -50, W + 100, H + 100);
}

function glowDisc(ctx, x, y, r, col, a = 1) {
  if (a <= 0) return;
  ctx.save(); ctx.globalAlpha *= a;
  const g = ctx.createRadialGradient(x, y, 0, x, y, r);
  g.addColorStop(0, col); g.addColorStop(1, 'rgba(0,0,0,0)');
  ctx.globalCompositeOperation = 'lighter';
  ctx.fillStyle = g; ctx.fillRect(x - r, y - r, 2 * r, 2 * r);
  ctx.restore();
}

function moon(ctx, x, y, r, a = 1) {
  glowDisc(ctx, x, y, r * 2.6, 'rgba(160,200,255,0.55)', a);
  ctx.save(); ctx.globalAlpha *= a;
  ctx.beginPath(); ctx.arc(x, y, r, 0, TAU);
  const g = ctx.createRadialGradient(x - r * 0.3, y - r * 0.3, r * 0.1, x, y, r);
  g.addColorStop(0, '#FFFFFF'); g.addColorStop(1, '#BFD4EE'); ctx.fillStyle = g; ctx.fill();
  ctx.fillStyle = 'rgba(120,150,190,0.25)';
  for (const [dx, dy, rr] of [[-0.3, 0.1, 0.18], [0.25, -0.2, 0.12], [0.1, 0.35, 0.1], [0.4, 0.25, 0.07]]) { ctx.beginPath(); ctx.arc(x + dx * r, y + dy * r, rr * r, 0, TAU); ctx.fill(); }
  ctx.restore();
}

function flash(ctx, a, col = P.goldHi) {
  if (a <= 0) return;
  ctx.save(); ctx.globalAlpha = clamp(a); ctx.fillStyle = col; ctx.fillRect(0, 0, W, H); ctx.restore();
}

function skyline(ctx, base, col, seed, scroll = 0, scale = 1) {
  ctx.fillStyle = col;
  ctx.beginPath(); ctx.moveTo(-10, H + 10);
  let x = -40 - (scroll % 120);
  let i = Math.floor(scroll / 120);
  while (x < W + 120) {
    const h = (60 + 220 * hash01(i, seed)) * scale, w = (50 + 80 * hash01(i, seed + 1)) * scale;
    ctx.lineTo(x, base - h); ctx.lineTo(x + w, base - h);
    if (hash01(i, seed + 2) < 0.3) { ctx.lineTo(x + w * 0.5, base - h - 40 * scale); }
    x += w; i++;
  }
  ctx.lineTo(W + 10, H + 10); ctx.closePath(); ctx.fill();
}

// ================================================================= SCENES

// S1-2 (u -1.3 .. 8): push into the hood's shadow, then the seal of the Domini forms.
function sSeal(ctx, u, t) {
  const kick = cue('kick', t);
  vgrad(ctx, [[0, P.night], [0.55, P.night2], [1, '#000']]);
  if (u < 0) {
    const k = prog(u, -1.3, 0);
    Hd.guilloche(ctx, { cx: W / 2, cy: H / 2, R: 470, A: 22, B: 8, n: 16, m: 5, lines: 20, phase: u * 0.05, prog: 0.4 + 0.6 * k, color: P.gold, width: 1.1, alpha: 0.6 });
    const s = 250 * Math.pow(14, E.inCubic(k));
    D.hoodBust(ctx, W / 2, H / 2, s, { house: 'empyerus', trim: true, rings: true, wings: 0.7 });
    return;
  }
  const cx = W / 2, cy = 470;
  const ra = E.outCubic(prog(u, 3.8, 5.5));
  if (ra > 0) { ctx.save(); ctx.globalAlpha = ra * (0.2 + 0.25 * kick); Hd.rays(ctx, cx, cy, 36, u * 0.02, null, P.cobalt); ctx.restore(); }
  Hd.guilloche(ctx, { cx, cy, R: 210, A: 14 + 10 * kick, B: 5, n: 22, m: 7, lines: 16, phase: -u * 0.05, prog: E.outCubic(prog(u, 0, 2)), color: P.goldLo, width: 1, alpha: 0.7 });
  const S = 0.95 + 0.012 * kick;
  D.emblem(ctx, cx, cy, S, {
    ring: springU(u, 0, SPRING.snappy), wings: E.outBack(prog(u, 1, 3), 1.2), crown: springU(u, 4, SPRING.bouncy), houses: prog(u, 5, 6.2),
  });
  if (u < 0.4) flash(ctx, 1 - prog(u, 0, 0.4), '#000');
  const f = font(110, 800, DISPLAY);
  const L = M.layout(ctx, 'THE DOMINI', f, 22);
  L.glyphs.forEach((gl, i) => {
    const k = springU(u, 6 + i * 0.09, SPRING.snappy);
    if (k <= 0) return;
    ctx.save(); ctx.globalAlpha = clamp(k * 3);
    ctx.translate(cx - L.width / 2 + gl.cx, 900); ctx.scale(1 + (1 - k) * 1.2, 1 + (1 - k) * 1.2);
    ctx.font = f; ctx.textAlign = 'center';
    ctx.fillStyle = P.goldLo; ctx.fillText(gl.ch, 3, 4); ctx.fillStyle = P.goldHi; ctx.fillText(gl.ch, 0, 0);
    ctx.restore();
  });
  spaced(ctx, 'THE FEDERATION', cx, 965, 34, UI, 500, P.white, 0.6, 'center', E.outCubic(prog(u, 7, 7.8)));
}

// S3 (8..16): the order. Ranks of faceless hoods, utterly still, backlit by a misty moonlit field.
function crowdRows(ctx, hz, rows, spread, hBase, o = {}) {
  for (let r = rows; r >= 1; r--) {
    const zz = 0.75 + r * 0.55 - (o.march || 0) % 0.55;
    const sc = 1 / zz, y = hz + spread * sc, h = hBase * sc;
    const fog = clamp((zz - 1) / (rows * 0.55)) * 0.85;
    const col = `rgb(${Math.round(lerp(3, 96, fog))},${Math.round(lerp(5, 116, fog))},${Math.round(lerp(10, 160, fog))})`;
    const sp = 140 * sc, n = Math.ceil(W / 2 / sp) + 1;
    for (let c = -n; c <= n; c++) {
      const x = W / 2 + c * sp + (r % 2) * sp / 2;
      D.dominusFront(ctx, x, y, h, 0, { col, rings: r < 7, trim: r < 6 ? P.goldLo : null, torch: o.torches && (c + r) % 3 === 0 });
      if (o.torches && (c + r) % 3 === 0) {
        const fx = x + h * 0.26, fy = y - h * 1.12, fl = 0.8 + 0.2 * Math.sin(o.t * 13 + c * 3 + r);
        glowDisc(ctx, fx, fy, 120 * sc, 'rgba(255,170,80,0.9)', fl * (1 - fog * 0.7));
        ctx.fillStyle = '#FFD27A'; ctx.beginPath(); ctx.ellipse(fx, fy, 14 * sc, 28 * sc * fl, 0, 0, TAU); ctx.fill();
      }
    }
  }
}
function sOrder(ctx, u, t) {
  vgrad(ctx, [[0, '#04060E'], [0.5, P.night3], [0.66, '#8094C4'], [0.7, '#5A70A0'], [1, '#1A2440']]);
  moon(ctx, 1600, 330, 110);
  if (u < 12) {
    const z = 1 + 0.1 * E.inOutSine(prog(u, 8, 12));
    ctx.save(); M.zoomAbout(ctx, z, W / 2, 640);
    crowdRows(ctx, 720, 9, 230, 330);
    ctx.restore();
  } else {
    // u12: cut in close; three faceless hoods, moonlit, perfectly still
    const z = 1 + 0.06 * E.inOutSine(prog(u, 12, 16));
    ctx.save(); M.zoomAbout(ctx, z, W / 2, 600);
    crowdRows(ctx, 700, 6, 200, 300);
    for (const [x, s] of [[470, 190], [960, 215], [1450, 190]]) D.hoodBust(ctx, x, 690, s, { house: 'plain', rings: true, scarf: false, trim: true });
    ctx.restore();
  }
  typeOn(ctx, 'CRUSADERS FOR HIRE', W / 2, 160, 92, DISPLAY, 800, P.goldHi, u, 8.4, 0.09, 0.08);
  slam(ctx, 'CENTURIES OF JUSTICE', W / 2, 232, 38, UI, 500, P.white, u, 12, { track: 0.45, from: 0.3 });
  flash(ctx, bump(u, 15.1, 0.45) * 0.75, P.goldHi);
}

// S4 (16..20): the hunted. Wanted notices slam onto the wall, one per beat; then CAPTURED.
function sHunted(ctx, u, t) {
  vgrad(ctx, [[0, '#1A1410'], [1, '#0B0806']]);
  ctx.strokeStyle = 'rgba(0,0,0,0.45)'; ctx.lineWidth = 3;
  for (let y = 0; y < H; y += 54) { ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(W, y); ctx.stroke(); for (let x = (y / 54) % 2 ? 0 : 60; x < W; x += 120) { ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x, y + 54); ctx.stroke(); } }
  glowDisc(ctx, W / 2, 120, 900, 'rgba(255,190,110,0.35)', 1);
  M.shake(ctx, u, Math.floor(u), 4 * cue('snare', t), 5);
  const posters = [['BEAMERS', 420, 540, -0.06, 16], ['FAKE GIVEAWAYS', 960, 520, 0.03, 17], ['EXPLOITERS', 1500, 545, -0.02, 18]];
  for (const [ch, x, y, rot, u0] of posters) {
    const k = springU(u, u0 - 0.06, SPRING.bouncy);
    if (k <= 0) continue;
    ctx.save(); ctx.translate(x, y); ctx.scale(1 + (1 - k) * 0.8, 1 + (1 - k) * 0.8); ctx.rotate((1 - k) * 0.4);
    D.wanted(ctx, 0, 0, 430, 600, ch, { rot });
    const st = springU(u, 19 + (x - 420) / 1080 * 0.3, SPRING.snappy);
    if (st > 0) D.stamp(ctx, 'CAPTURED', 0, 40, 64 * (1 + (1 - Math.min(1, st)) * 1.2), '#C8231F', -0.2 + rot, clamp(st * 3));
    ctx.restore();
  }
}

// S5 (20..32): the hunter on the rooftop under the moon. WE HUNT / WE CAPTURE / WE RESTORE.
function sHunter(ctx, u, t) {
  const vocal = cue('vocal', t), pitch = Math.max(0, cue('pitch', t));
  const lift = clamp(vocal * 0.6 + pitch * 0.5);
  vgrad(ctx, [[0, '#04060E'], [0.6, P.night3], [1, '#2C3C66']]);
  const crane = kf(u, [[20, 0], [32, 1]], E.inOutSine) * 70 + pitch * 20;
  moon(ctx, 1240, 360 + crane * 0.3, 260 + 10 * lift, 0.85 + 0.15 * lift);
  const fi = u < 24 ? 0 : u < 28 ? 1 : 2;
  const fz = [1, 1.45, 1.15][fi], fx = [960, 640, 820][fi], fy = [540, 520, 760][fi];
  ctx.save(); M.zoomAbout(ctx, fz, fx, fy); ctx.translate(0, crane);
  skyline(ctx, 1000, '#0C1222', 91, (u - 20) * 6, 1.2);
  skyline(ctx, 1080, '#070A14', 93, (u - 20) * 12, 1.6);
  ctx.fillStyle = '#05070D';
  ctx.beginPath(); ctx.moveTo(-20, H + 200); ctx.lineTo(-20, 880); ctx.lineTo(980, 880); ctx.lineTo(1000, 900); ctx.lineTo(1000, H + 200); ctx.closePath(); ctx.fill();
  ctx.fillStyle = '#1A2238'; ctx.fillRect(-20, 876, 1000, 6);
  D.hunter(ctx, 600, 880, 640, t, { rim: '#7FA4D6' });
  ctx.restore();
  for (const [w, u0] of [['WE HUNT', 20], ['WE CAPTURE', 24], ['WE RESTORE', 28]]) {
    slam(ctx, w, 1840, 300, 190, UI, 700, P.white, u, u0, { align: 'right', plate: P.cobaltLo, u1: u0 + 3.75, outLen: 0.25, outDir: 1, rot: 0.04, track: 0.02 });
  }
}

// S6 (32..40): the ladder. One rank lights per beat, climbing; the houses wait above, sealed.
const RANKS = [
  // [name, role, sigil, x, row, beat, parent index]
  ['CLAVES', 'Private', 'key', 0, 0, 32, -1],
  ['VENARI', 'Sergeant', 'hunt', 0, 1, 33, 0],
  ['REX', 'Platoon command', 'rex', -690, 2, 34, 1],
  ['PRAEFECTUS', 'Lesser overseer', 'eye', -230, 2, 34.25, 1],
  ['PITTACIUM', 'Lesser aurum', 'ticket', 230, 2, 34.5, 1],
  ['ASTRA', 'Stealth', 'astra', 690, 2, 34.75, 1],
  ['VESPERTILIO', 'Vice overseer', 'bat', -230, 3, 36, 3],
  ['MESSOR', 'Greater overseer', 'sickle', -230, 4, 37, 6],
  ['AUREUS', 'Treasury', 'coin', 230, 4, 37.25, 4],
];
function sLadder(ctx, u, t) {
  vgrad(ctx, [[0, '#03050B'], [1, P.night2]]);
  const ROWH = 250;
  const camRow = kf(u, [[32, 0], [33, 0.6], [34, 1.6], [36, 2.6], [37, 3.4], [38.5, 4.6], [40, 4.8]], E.inOutCubic);
  const yOf = (row) => 580 - (row - camRow) * ROWH;
  const hy = yOf(5.4);
  const hk = E.outCubic(prog(u, 38, 39));
  ctx.save(); ctx.globalAlpha = 0.25 + 0.75 * hk;
  ctx.strokeStyle = P.gold; ctx.lineWidth = 4; ctx.beginPath(); ctx.moveTo(220, hy + 120); ctx.lineTo(W - 220, hy + 120); ctx.stroke();
  for (let x = 240; x < W - 220; x += 40) { ctx.beginPath(); ctx.moveTo(x, hy + 120); ctx.lineTo(x, hy + 150); ctx.stroke(); }
  const houses = [['FRIGIDUS', 'crystal', P.frost, P.frostLo, -500], ['EMPYERUS', 'sun', P.goldHi, P.gold, 0], ['INFERNUS', 'flame', P.ember, P.emberLo, 500]];
  for (const [n, sg, c, d, x] of houses) {
    D.sigil(ctx, sg, W / 2 + x, hy - 20, 0.42, c, d);
    spaced(ctx, n, W / 2 + x, hy + 80, 34, DISPLAY, 700, c, 0.2);
  }
  ctx.restore();
  for (const r of RANKS) {
    if (r[6] < 0) continue;
    const p = RANKS[r[6]];
    const k = prog(u, r[5] - 0.4, r[5]);
    if (k <= 0) continue;
    const x0 = W / 2 + p[3], y0 = yOf(p[4]) - 70, x1 = W / 2 + r[3], y1 = yOf(r[4]) + 70;
    ctx.strokeStyle = P.gold; ctx.lineWidth = 3;
    ctx.beginPath(); ctx.moveTo(x0, y0); const ym = (y0 + y1) / 2;
    ctx.lineTo(x0, lerp(y0, ym, clamp(k * 2))); if (k > 0.5) { ctx.lineTo(lerp(x0, x1, clamp(k * 2 - 1)), ym); } if (k >= 1) ctx.lineTo(x1, y1);
    ctx.stroke();
  }
  for (const [name, role, sg, x, row, b] of RANKS) {
    const k = springU(u, b, SPRING.snappy);
    const lit = clamp(k * 1.5);
    const px = W / 2 + x, py = yOf(row);
    if (py < -200 || py > H + 200) continue;
    ctx.save(); ctx.translate(px, py); ctx.scale(0.85 + 0.15 * Math.min(1.1, k), 0.85 + 0.15 * Math.min(1.1, k));
    ctx.fillStyle = lit > 0 ? P.night3 : '#0B0F1C'; ctx.fillRect(-200, -70, 400, 140);
    ctx.lineWidth = 4; ctx.strokeStyle = lit > 0 ? P.gold : '#2A3248'; ctx.strokeRect(-200, -70, 400, 140);
    ctx.globalAlpha = 0.35 + 0.65 * lit;
    D.sigil(ctx, sg, -140, 0, 0.42, P.goldHi, P.gold);
    ctx.font = font(name.length > 9 ? 40 : 48, 700, DISPLAY); ctx.textAlign = 'left'; ctx.fillStyle = P.goldHi; ctx.fillText(name, -80, 4);
    ctx.font = font(26, 400, UI); ctx.letterSpacing = '3px'; ctx.fillStyle = P.white; ctx.fillText(role.toUpperCase(), -80, 44); ctx.letterSpacing = '0px';
    ctx.restore();
    if (k > 0 && u - b < 0.6) glowDisc(ctx, px, py, 300, 'rgba(246,222,154,0.5)', 1 - (u - b) / 0.6);
  }
  slam(ctx, 'ANYONE CAN CLIMB', W / 2, 1050, 64, UI, 700, P.white, u, 32.5, { track: 0.08, plate: P.cobaltLo, u1: 37.6, outLen: 0.3 });
  slam(ctx, 'ONLY BIRTH REACHES THE HOUSES', W / 2, 130, 54, DISPLAY, 700, P.goldHi, u, 38.1, { track: 0.12, from: 0.4 });
}

// S7 (40..48): the ranks march under the moon on three parallax layers.
function sMarch(ctx, u, t) {
  vgrad(ctx, [[0, '#050814'], [0.7, P.night3], [1, '#33456E']]);
  const scroll = (u - 40) * 40;
  moon(ctx, 1300 - scroll * 0.1, 420, 300, 1);
  skyline(ctx, 820, '#0E1528', 61, scroll * 0.3, 1.0);
  ctx.fillStyle = '#05070D'; ctx.fillRect(0, 818, W, 300);
  const mz = u < 44 ? 1 : 1.3;
  ctx.save(); M.zoomAbout(ctx, mz, W / 2, 1000);
  const layers = [[0.45, 0.25, '#1E2A48', 860, 230, P.frostLo], [0.7, 0.55, '#121A30', 930, 330, P.emberLo], [1.0, 1.0, '#05070D', 1060, 520, P.cobalt]];
  for (const [sc, sp, col, gy, hh, pen] of layers) {
    const gap = 230 * sc, off = (scroll * sp * 0.6) % gap;
    for (let x = -gap + off - 40; x < W + gap; x += gap) D.dominusSide(ctx, x, gy, hh, u / 2, { col, wing: sc > 0.6 ? '#D9DEE8' : '#7E8AA6', pennant: pen });
  }
  ctx.restore();
  slam(ctx, 'FROM SEA TO SEA', 120, 200, 120, UI, 700, P.white, u, 40, { align: 'left', track: 0.02, from: 0.5, u1: 43.7, outLen: 0.3 });
  spaced(ctx, '— REX', 128, 260, 30, DISPLAY, 700, P.goldHi, 0.3, 'left', clamp((u - 40.5) * 3) * (u < 43.8 ? 1 : 0));
  slam(ctx, 'SEIZE THE NIGHT!', 120, 200, 120, UI, 700, P.white, u, 44, { align: 'left', track: 0.02, from: 0.5 });
  spaced(ctx, '— ASTRA', 128, 260, 30, DISPLAY, 700, P.goldHi, 0.3, 'left', clamp((u - 44.5) * 3));
}

// S8 (48..60): the raid. Flying over a night city; searchlights; the beams lock on the crash.
function sRaid(ctx, u, t) {
  const lu = u - 48;
  vgrad(ctx, [[0, '#050814'], [0.55, '#1E2C50'], [1, '#3A4E80']]);
  moon(ctx, 1500, 160, 90, 0.9);
  const cz = -6 + lu * 3.0;
  const cam = T.camera({ pos: [1.6 + Math.sin(lu * 0.2) * 2, 16 - lu * 0.3, cz], target: [2.4, 2, cz + 30], fov: 55, W, H, roll: 0.05 * Math.sin(lu * 0.25) });
  const objs = [];
  for (const c of CITY) { if (c.t.z > cz - 4 && c.t.z < cz + 95) objs.push({ parts: c.parts, pos: [c.t.x, 0, c.t.z] }); }
  const lock = prog(u, 56.3, 57.1);
  ctx.save(); ctx.globalCompositeOperation = 'lighter';
  const tp = cam.project([TARGET.x, TARGET.h, TARGET.z]);
  for (const c of CITY) {
    if (c.t.roof > 0.12 || c.t.z < cz + 6 || c.t.z > cz + 80) continue;
    const pr = cam.project([c.t.x, c.t.h, c.t.z]);
    if (!pr) continue;
    let a = -Math.PI / 2 + Math.sin(u * 0.6 + c.t.roof * 40) * 0.6;
    if (tp && lock > 0) a = lerp(a, Math.atan2(tp[1] - pr[1], tp[0] - pr[0]), lock);
    const L = 1400, wd = 0.05;
    const g = ctx.createLinearGradient(pr[0], pr[1], pr[0] + Math.cos(a) * L, pr[1] + Math.sin(a) * L);
    g.addColorStop(0, 'rgba(220,235,255,0.5)'); g.addColorStop(1, 'rgba(220,235,255,0)');
    ctx.fillStyle = g; ctx.beginPath(); ctx.moveTo(pr[0], pr[1]);
    ctx.lineTo(pr[0] + Math.cos(a - wd) * L, pr[1] + Math.sin(a - wd) * L); ctx.lineTo(pr[0] + Math.cos(a + wd) * L, pr[1] + Math.sin(a + wd) * L); ctx.closePath(); ctx.fill();
  }
  ctx.restore();
  T.draw3d(ctx, cam, objs, { dir: [0.3, 0.8, -0.5], ambient: 0.75, diffuse: 0.7, fog: rgb('#33456E'), fogNear: 25, fogFar: 90, edgeAlpha: 0.95 });
  for (const c of CITY) {
    if (c.t.roof < 0.85 || c.t.z < cz + 4 || c.t.z > cz + 50) continue;
    const pr = cam.project([c.t.x, c.t.h, c.t.z]);
    if (!pr) continue;
    const hpx = cam.focal * 2.2 / pr[2];
    D.dominusFront(ctx, pr[0], pr[1], hpx, 0, { col: '#03050A', wing: '#C9D0DE', trim: '#6F8FB8' });
  }
  if (tp && lock > 0) glowDisc(ctx, tp[0], tp[1], 300, 'rgba(255,80,60,0.8)', lock);
  slam(ctx, 'NO SCAMMER HIDES', W / 2, 980, 110, DISPLAY, 900, P.white, u, 52, { track: 0.06, shadow: '#000', u1: 56.6, outLen: 0.3 });
  flash(ctx, bump(u, 57.05, 0.35) * 0.8, '#FFFFFF');
  if (u >= 57) D.stamp(ctx, 'CAPTURED', W / 2, 520, 150 * (1 + 0.5 * Math.exp(-(u - 57) * 8)), '#E23A2E', -0.12, 1);
}

// S9 (60..64): restitution. What was stolen streams back from the seized chest to its owners.
function sRestitution(ctx, u, t) {
  ctx.drawImage(PAPER, 0, 0);
  ctx.strokeStyle = 'rgba(40,60,120,0.18)'; ctx.lineWidth = 2;
  for (let y = 120; y < H; y += 46) { ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(W, y); ctx.stroke(); }
  ctx.strokeStyle = 'rgba(176,24,42,0.3)'; ctx.beginPath(); ctx.moveTo(240, 0); ctx.lineTo(240, H); ctx.stroke();
  D.sigil(ctx, 'coin', 1700, 180, 0.6, P.gold, P.goldLo);
  const cx = 380, cy = 760;
  ctx.fillStyle = '#4A2E18'; ctx.fillRect(cx - 150, cy - 70, 300, 150);
  ctx.fillStyle = '#6A4426'; ctx.save(); ctx.translate(cx - 150, cy - 70); ctx.rotate(-0.5); ctx.fillRect(0, -100, 300, 100); ctx.restore();
  ctx.fillStyle = P.gold; ctx.fillRect(cx - 150, cy - 10, 300, 14); ctx.fillRect(cx - 18, cy - 70, 36, 60);
  glowDisc(ctx, cx, cy - 70, 260, 'rgba(255,220,140,0.7)', 0.8);
  for (let i = 0; i < 5; i++) {
    const x = 1060 + i * 170, y = 1080;
    ctx.fillStyle = '#1C2236';
    ctx.beginPath(); ctx.arc(x, y - 330, 46, 0, TAU); ctx.fill();
    ctx.fillRect(x - 70, y - 280, 140, 300);
    ctx.save(); ctx.translate(x + 50, y - 260); ctx.rotate(-0.7); ctx.fillRect(0, -16, 150, 32); ctx.restore();
  }
  for (const it of ITEMS) {
    const tt = (u - 60 - it.d * 0.6) / 1.4;
    if (tt <= 0 || tt >= 1) continue;
    const tx = 1060 + it.to * 170 + 120, ty = 760;
    const e = E.inOutCubic(tt);
    const x = lerp(cx, tx, e), y = lerp(cy - 80, ty, e) - Math.sin(Math.PI * e) * 360 * it.arc;
    ctx.save(); ctx.translate(x, y); ctx.rotate(tt * 6);
    if (it.k === 0) D.sigil(ctx, 'coin', 0, 0, 0.22, P.gold, P.goldLo);
    else if (it.k === 1) { ctx.beginPath(); for (let k = 0; k < 8; k++) { const a = (k / 8) * TAU + Math.PI / 8; ctx.lineTo(Math.cos(a) * 26, Math.sin(a) * 26); } ctx.closePath(); ctx.fillStyle = P.cobalt; ctx.fill(); ctx.lineWidth = 4; ctx.strokeStyle = P.gold; ctx.stroke(); }
    else { ctx.fillStyle = '#16161C'; ctx.fillRect(-26, -40, 52, 46); ctx.fillRect(-42, 4, 84, 10); ctx.fillStyle = P.cobalt; ctx.fillRect(-26, -6, 52, 8); }
    ctx.restore();
  }
  slam(ctx, 'WHAT WAS STOLEN IS RETURNED', W / 2, 150, 72, DISPLAY, 800, P.night2, u, 60, { track: 0.06, from: 0.4 });
  if (u >= 61.9) D.stamp(ctx, 'RETURNED', 1400, 470, 120 * (1 + 0.6 * Math.exp(-(u - 61.9) * 8)), '#1F7A3A', -0.15, 1);
  flash(ctx, prog(u, 63.4, 64), '#000');
}

// S10 (64..68): dropout. The Azurelight's seat stands empty in azure light.
function sEmptySeat(ctx, u, t) {
  ctx.fillStyle = '#010206'; ctx.fillRect(0, 0, W, H);
  const lu = u - 64;
  for (let i = 0; i < 6; i++) {
    const z = 1 + i * 0.7, s = 1 / z;
    for (const sd of [-1, 1]) {
      const x = W / 2 + sd * (700 * s + 60), w = 90 * s;
      ctx.fillStyle = `rgba(20,40,70,${0.6 * s})`; ctx.fillRect(x - w / 2, 300 - 500 * s, w, 1200 * s);
    }
  }
  ctx.save(); ctx.globalCompositeOperation = 'lighter';
  const g = ctx.createLinearGradient(0, 0, 0, H);
  g.addColorStop(0, 'rgba(89,200,255,0.28)'); g.addColorStop(1, 'rgba(89,200,255,0.03)');
  ctx.fillStyle = g; ctx.beginPath(); ctx.moveTo(W / 2 - 50, -10); ctx.lineTo(W / 2 + 50, -10); ctx.lineTo(W / 2 + 360, 900); ctx.lineTo(W / 2 - 360, 900); ctx.closePath(); ctx.fill();
  ctx.restore();
  for (let i = 0; i < 70; i++) {
    const x = W / 2 + (hash01(i, 51) - 0.5) * 520 * (0.4 + hash01(i, 54)), y = ((hash01(i, 52) * H + lu * 22 * (0.5 + hash01(i, 53))) % 900);
    ctx.fillStyle = `rgba(150,220,255,${0.15 + 0.35 * hash01(i, 55)})`; ctx.fillRect(x, y, 2, 2);
  }
  ctx.fillStyle = 'rgba(89,200,255,0.12)'; ctx.beginPath(); ctx.ellipse(W / 2, 880, 420, 50, 0, 0, TAU); ctx.fill();
  const z = 1 + 0.05 * E.inOutSine(clamp(lu / 4));
  ctx.save(); M.zoomAbout(ctx, z, W / 2, 700);
  D.emptySeat(ctx, W / 2, 880, 620, '#0A1830', P.azure);
  ctx.restore();
  const gl = bump(u, 67.05, 0.6);
  if (gl > 0) glowDisc(ctx, W / 2, 880 - 620 * 0.78, 180, 'rgba(160,230,255,1)', gl);
  spaced(ctx, 'THE AZURELIGHT', W / 2, 160, 76, DISPLAY, 700, P.azure, 0.3, 'center', E.outCubic(prog(u, 64.5, 65.6)));
  spaced(ctx, 'ONE SEAT STANDS EMPTY', W / 2, 1000, 32, UI, 400, '#BFE6FF', 0.5, 'center', 0.85 * E.outCubic(prog(u, 65.4, 66.4)));
}

// S11 (68..76): impact. The three houses' banners drop; the heirs kneel.
function sHouses(ctx, u, t) {
  vgrad(ctx, [[0, P.night], [1, '#05060C']]);
  ctx.save(); ctx.globalAlpha = 0.25 + 0.2 * cue('kick', t); Hd.rays(ctx, W / 2, 1100, 40, u * 0.02, null, P.goldLo); ctx.restore();
  M.shake(ctx, u, Math.floor(u), 5 * cue('snare', t), 7);
  const H3 = [['FRIGIDUS', 'crystal', '#2B6CA8', '#123A66', P.frost, -560, 68.25], ['EMPYERUS', 'sun', '#E9ECF2', '#9AA2B4', P.gold, 0, 68], ['INFERNUS', 'flame', '#8A1A12', '#3C0806', P.ember, 560, 68.5]];
  for (const [name, sg, c, d, acc, x, u0] of H3) {
    const k = springU(u, u0, SPRING.bouncy);
    const bx = W / 2 + x, len = 760 * Math.min(1.05, k);
    if (k <= 0) continue;
    const sway = Math.sin(t * 1.4 + x) * 6;
    ctx.fillStyle = P.gold; ctx.fillRect(bx - 170, 40, 340, 14);
    ctx.fillStyle = name === 'EMPYERUS' ? P.white : c;
    ctx.beginPath(); ctx.moveTo(bx - 150, 54); ctx.lineTo(bx + 150, 54); ctx.lineTo(bx + 150 + sway, 54 + len); ctx.lineTo(bx + sway, 54 + len - 70); ctx.lineTo(bx - 150 + sway, 54 + len); ctx.closePath(); ctx.fill();
    ctx.strokeStyle = acc; ctx.lineWidth = 8; ctx.stroke();
    if (k > 0.5) {
      D.sigil(ctx, sg, bx + sway * 0.4, 54 + len * 0.36, 0.9, name === 'EMPYERUS' ? P.gold : acc, name === 'EMPYERUS' ? P.cobalt : d);
      spaced(ctx, name, bx + sway * 0.5, 54 + len * 0.66, 40, DISPLAY, 800, name === 'EMPYERUS' ? P.cobaltLo : P.white, 0.15);
    }
  }
  ctx.fillStyle = '#020307'; ctx.fillRect(0, 960, W, 140);
  const bow = E.outCubic(prog(u, 69, 70));
  D.kneeler(ctx, 560, 990, 300, '#BFD8EC', '#5A86AE', bow);
  ctx.save(); ctx.translate(1360, 0); ctx.scale(-1, 1); D.kneeler(ctx, 0, 990, 300, '#5A1612', '#200605', bow); ctx.restore();
  const sw = prog(u, 68, 69.4);
  if (sw > 0 && sw < 1) { ctx.save(); ctx.strokeStyle = `rgba(255,248,230,${1 - sw})`; ctx.lineWidth = 40 * (1 - sw); ctx.beginPath(); ctx.arc(W / 2, 600, 80 + sw * 1400, 0, TAU); ctx.stroke(); ctx.restore(); }
  flash(ctx, 1 - prog(u, 68, 68.5), P.white);
  slam(ctx, 'THREE HOUSES', W / 2, 1050, 84, UI, 700, P.white, u, 68.5, { track: 0.1, u1: 71.6, outLen: 0.35 });
  slam(ctx, 'ONE LORD', W / 2, 1050, 96, DISPLAY, 900, P.goldHi, u, 72, { track: 0.12 });
}

// S12 (76..80): band out. The Lord of the Federation crown turns in the dark; light gathers.
function sCrownDark(ctx, u, t) {
  ctx.fillStyle = '#010205'; ctx.fillRect(0, 0, W, H);
  const lu = u - 76;
  const gather = E.inCubic(prog(u, 76, 80));
  ctx.save(); ctx.globalCompositeOperation = 'lighter';
  for (let i = 0; i < 48; i++) {
    const a = (i / 48) * TAU + 0.1 * hash01(i, 61);
    const r0 = 1300 * (1 - gather) + 140, r1 = r0 + 300 + 200 * hash01(i, 62);
    ctx.strokeStyle = i % 3 ? `rgba(246,222,154,${0.12 + 0.4 * gather})` : `rgba(92,134,242,${0.15 + 0.4 * gather})`; ctx.lineWidth = 1.5;
    ctx.beginPath(); ctx.moveTo(W / 2 + Math.cos(a) * r0, 450 + Math.sin(a) * r0); ctx.lineTo(W / 2 + Math.cos(a) * r1, 450 + Math.sin(a) * r1); ctx.stroke();
  }
  ctx.restore();
  glowDisc(ctx, W / 2, 450, 420, 'rgba(92,134,242,0.45)', 0.3 + 0.7 * gather);
  const rise = E.outCubic(prog(u, 76, 79.5));
  const turn = Math.cos(lu * 0.9);
  ctx.save(); ctx.translate(W / 2, lerp(900, 640, rise)); ctx.scale(0.8 + 0.2 * Math.abs(turn), 1);
  D.lordCrown(ctx, 0, 0, 640, { starDip: 70 });
  ctx.restore();
  for (let i = 0; i < 6; i++) {
    const ph = (lu * 1.3 + i * 0.37) % 1, sx = W / 2 + (hash01(i, 71) - 0.5) * 560, sy = lerp(900, 640, rise) - 40 - hash01(i, 72) * 420;
    const g = Math.sin(ph * Math.PI) ** 6;
    if (g > 0.02) { ctx.save(); ctx.globalCompositeOperation = 'lighter'; ctx.fillStyle = `rgba(230,240,255,${g})`;
      ctx.beginPath(); ctx.moveTo(sx, sy - 40 * g); ctx.lineTo(sx + 5, sy); ctx.lineTo(sx, sy + 40 * g); ctx.lineTo(sx - 5, sy); ctx.closePath(); ctx.fill();
      ctx.beginPath(); ctx.moveTo(sx - 40 * g, sy); ctx.lineTo(sx, sy + 5); ctx.lineTo(sx + 40 * g, sy); ctx.lineTo(sx, sy - 5); ctx.closePath(); ctx.fill(); ctx.restore(); }
  }
  typeOn(ctx, 'LONG LIVE', W / 2, 940, 120, DISPLAY, 800, P.white, u, 76.4, 0.38, 0.14);
}

// S13 (80..88): final chorus. Lord Emperyan, hood down, crowned; the honour guard raises blades.
function sLord(ctx, u, t) {
  const loud = cue('loud', t), kick = cue('kick', t);
  const lu = u - 80;
  vgrad(ctx, [[0, '#DCE6F7'], [0.6, '#9DB4E6'], [1, P.cobaltLo]]);
  ctx.save(); ctx.globalAlpha = 0.3 + 0.25 * loud; Hd.rays(ctx, W / 2, 380, 40, -u * 0.03, null, '#FFFFFF'); ctx.restore();
  const boom = Math.exp(-lu * 1.6);
  Hd.guilloche(ctx, { cx: W / 2, cy: 380, R: 470 + 220 * (1 - boom), A: 30 + 70 * boom + 15 * kick, B: 10, n: 16, m: 6, lines: 22, phase: u * 0.06, color: P.gold, width: 1.4, alpha: 0.55 });
  const pull = 1.1 - 0.18 * E.inOutCubic(prog(u, 84, 86));
  ctx.save(); M.zoomAbout(ctx, pull + 0.015 * kick, W / 2, 470);
  M.shake(ctx, u, 80, 16, 9, 0.4);
  D.emperyanFace(ctx, W / 2, 360, 205, { wings: 0.4 + 0.6 * E.outBack(prog(u, 80, 81.5), 1.3) });
  ctx.restore();
  const hg = E.outCubic(prog(u, 84, 85.5));
  if (hg > 0) {
    for (const side of [-1, 1]) for (let i = 0; i < 4; i++) {
      const x = W / 2 + side * (560 + i * 140), h = 380 - i * 30, y = H + 40 + (1 - hg) * 300;
      D.dominusFront(ctx, x, y, h, 0, { col: '#0A0E1C', wing: '#E9ECF2', trim: P.gold });
      const raise = springU(u, 84.5 + i * 0.25, SPRING.bouncy);
      D.empyreanSword(ctx, x - side * h * 0.2, y - h * 0.5, h * 0.95, -Math.PI / 2 - side * lerp(0.15, 0.7, raise));
    }
  }
  for (const L of LEAVES) {
    const tt = (u - 80 - L.d) * 0.42256;
    if (tt <= 0 || tt > 3) continue;
    const x = W / 2 + Math.cos(L.a) * L.v * tt * Math.exp(-tt * 0.6);
    const y = 420 + Math.sin(L.a) * L.v * tt * Math.exp(-tt * 0.6) + 260 * tt * tt;
    ctx.save(); ctx.translate(x, y); ctx.rotate(L.spin * tt); ctx.scale(1, Math.cos(L.spin * tt * 1.3));
    ctx.globalAlpha = clamp(3 - tt);
    ctx.fillStyle = L.c; ctx.beginPath(); ctx.moveTo(0, -L.s); ctx.lineTo(L.s * 0.55, 0); ctx.lineTo(0, L.s); ctx.lineTo(-L.s * 0.55, 0); ctx.closePath(); ctx.fill();
    ctx.restore();
  }
  if (lu >= 0) flash(ctx, Math.exp(-lu * 5), '#FFFFFF');
  slam(ctx, 'LORD EMPERYAN', W / 2, 1010, 112, DISPLAY, 900, P.goldHi, u, 80.02, { track: 0.06, plate: P.cobaltLo, from: 1.4 });
  spaced(ctx, 'LONG LIVE', W / 2, 890, 44, DISPLAY, 800, P.white, 0.5, 'center', 1);
}

// S14 (88..98): the court. Emperyan enthroned, hood up; Atmos and Judas beside him; heirs kneel.
function sCourt(ctx, u, t) {
  if (u >= 93) return sAdvisor(ctx, u, t, u < 95.5 ? 'atmos' : 'judas');
  return sCourtWide(ctx, u, t);
}
function sAdvisor(ctx, u, t, who) {
  const atm = who === 'atmos';
  const u0 = atm ? 93 : 95.5;
  vgrad(ctx, atm ? [[0, '#0A1A2E'], [1, '#02060C']] : [[0, '#1E0A10'], [1, '#050204']]);
  glowDisc(ctx, W * 0.36, 520, 700, atm ? 'rgba(110,190,255,0.45)' : 'rgba(255,70,70,0.4)', 0.9);
  const k = springU(u, u0, SPRING.gentle);
  const z = 1 + 0.05 * (u - u0) / 2.5;
  ctx.save(); M.zoomAbout(ctx, z, W * 0.36, 540);
  if (atm) D.atmos(ctx, W * 0.36, 520 + (1 - k) * 80, 330); else D.judas(ctx, W * 0.36, 520 + (1 - k) * 80, 330);
  ctx.restore();
  slam(ctx, atm ? 'ATMOS' : 'JUDAS', 1180, 470, 130, DISPLAY, 900, atm ? '#9ED8FF' : '#FF6B6B', u, u0 + 0.1, { align: 'left', track: 0.08 });
  slam(ctx, atm ? 'ADVISOR · THE VOICE OF MERCY' : 'ADVISOR · THE OLD WAYS', 1186, 540, 32, UI, 500, P.white, u, u0 + 0.4, { align: 'left', track: 0.3, from: 0.3 });
}
function sCourtWide(ctx, u, t) {
  const lu = u - 88;
  vgrad(ctx, [[0, '#060914'], [0.6, P.night2], [1, '#03040A']]);
  const z = 1 + 0.08 * E.inOutSine(prog(u, 88, 98));
  ctx.save(); M.zoomAbout(ctx, z, W / 2, 520);
  for (const [x, c, sg, a] of [[560, '#2B6CA8', 'crystal', P.frost], [960, '#E9ECF2', 'sun', P.gold], [1360, '#8A1A12', 'flame', P.ember]]) {
    const sw = Math.sin(t * 1.2 + x) * 5;
    ctx.fillStyle = c; ctx.beginPath(); ctx.moveTo(x - 90, -10); ctx.lineTo(x + 90, -10); ctx.lineTo(x + 90 + sw, 440); ctx.lineTo(x + sw, 400); ctx.lineTo(x - 90 + sw, 440); ctx.closePath(); ctx.fill();
    D.sigil(ctx, sg, x + sw * 0.5, 220, 0.5, a, x === 960 ? P.cobalt : '#000');
  }
  glowDisc(ctx, W / 2, 470, 650, 'rgba(246,222,154,0.5)', 0.9);
  ctx.fillStyle = '#0B1020'; for (let i = 0; i < 4; i++) ctx.fillRect(W / 2 - 520 + i * 60, 860 + i * 40, 1040 - i * 120, 40);
  ctx.fillStyle = '#0E1426'; ctx.beginPath(); ctx.moveTo(W / 2 - 230, 860); ctx.lineTo(W / 2 - 200, 140); ctx.lineTo(W / 2, 60); ctx.lineTo(W / 2 + 200, 140); ctx.lineTo(W / 2 + 230, 860); ctx.closePath(); ctx.fill();
  ctx.strokeStyle = P.gold; ctx.lineWidth = 5; ctx.stroke();
  D.hoodBust(ctx, W / 2, 420, 150, { house: 'empyerus', wings: 0.55 + 0.1 * Math.sin(lu * 0.8), smile: 0.8 + 0.2 * cue('vocal', t), trim: true });
  D.atmos(ctx, 360, 560, 130);
  D.judas(ctx, 1560, 560, 130);
  ctx.restore();
  spaced(ctx, 'ATMOS', 360, 800, 30, DISPLAY, 700, '#9ED8FF', 0.4, 'center', clamp((u - 89) * 2));
  spaced(ctx, 'JUDAS', 1560, 800, 30, DISPLAY, 700, '#FF6B6B', 0.4, 'center', clamp((u - 89.5) * 2));
  const bow = Math.max(E.outCubic(prog(u, 88, 89)), E.outCubic(prog(u, 92, 93)) * 0.6 + 0.4 * (u > 92 ? 1 : 0));
  D.kneeler(ctx, 380, 1080, 300, '#BFD8EC', '#5A86AE', bow);
  ctx.save(); ctx.translate(1540, 0); ctx.scale(-1, 1); D.kneeler(ctx, 0, 1080, 300, '#5A1612', '#200605', bow); ctx.restore();
  slam(ctx, 'THE AGE OF MERCY', W / 2, 1010, 80, DISPLAY, 800, P.goldHi, u, 90, { track: 0.08, shadow: '#000' });
  spaced(ctx, 'UNDER LORD EMPERYAN', W / 2, 1060, 28, UI, 400, P.white, 0.5, 'center', clamp((u - 92) * 2));
}

// S15 (98..110): the Empyrean Sword rises into the highest heaven; ONE ORDER / ONE CROWN / ONE LORD.
function sSword(ctx, u, t) {
  const pitch = Math.max(0, cue('pitch', t)), vocal = cue('vocal', t), kick = cue('kick', t);
  const k = E.inOutSine(prog(u, 98, 110));
  vgrad(ctx, [[0, '#3E62C8'], [0.55, P.cobalt], [1, P.cobaltLo]]);
  ctx.save(); ctx.globalAlpha = 0.18 + 0.15 * vocal + 0.12 * kick; Hd.rays(ctx, W / 2, 120 - k * 200, 48, u * 0.02, null, '#FFFFFF'); ctx.restore();
  glowDisc(ctx, W / 2, 0, 600, 'rgba(255,250,235,0.8)', 0.25 + 0.25 * k + 0.15 * pitch);
  for (let i = 0; i < 8; i++) {
    const side = i % 2 ? 1 : -1, y = 600 + i * 70 - k * 500;
    ctx.fillStyle = `rgba(220,232,255,${0.25 + 0.05 * i})`;
    ctx.beginPath(); ctx.ellipse(W / 2 + side * (520 + k * 500 + i * 30), y, 480, 80, 0, 0, TAU); ctx.fill();
  }
  const L = 1500;
  const by = lerp(1500, 980, k) + pitch * 10;
  D.empyreanSword(ctx, W / 2, by, L, -Math.PI / 2, { glow: 0.15 + 0.3 * vocal, edge: '#0B1640' });
  for (const [w, u0] of [['ONE ORDER', 100], ['ONE CROWN', 104], ['ONE LORD', 108]]) {
    slam(ctx, w, W / 2, 230, 150, DISPLAY, 900, P.goldHi, u, u0, { u1: u0 === 108 ? undefined : u0 + 3.8, outLen: 0.2, outDir: u0 === 100 ? -1 : 1, track: 0.06, plate: '#0B1640' });
  }
}

// S16 (110..120): earn your rank. Six posters flip in; push into VENARI.
const POSTERS = [
  ['CLAVES', 'PRIVATE', P.cobaltLo, P.white, 'key'], ['VENARI', 'SERGEANT', P.night3, P.goldHi, 'hunt'], ['REX', 'PLATOON COMMAND', P.gold, P.night, 'rex'],
  ['ASTRA', 'STEALTH', P.night, P.frost, 'astra'], ['PRAEFECTUS', 'LESSER OVERSEER', '#E9ECF2', P.cobaltLo, 'eye'], ['PITTACIUM', 'LESSER AURUM', P.cobalt, P.goldHi, 'ticket'],
];
function poster(ctx, i, x, y, w, h, u, t) {
  const [label, role, bg, fg, sg] = POSTERS[i];
  ctx.save(); ctx.beginPath(); ctx.rect(x, y, w, h); ctx.clip();
  ctx.fillStyle = bg; ctx.fillRect(x, y, w, h);
  ctx.globalAlpha = 0.16; Hd.rays(ctx, x + w / 2, y + h * 0.6, 24, u * 0.03 * (i % 2 ? 1 : -1), null, fg); ctx.globalAlpha = 1;
  D.dominusFront(ctx, x + w * 0.3, y + h * 0.95, h * 0.62, 0, { col: fg === P.night ? '#0A0D18' : 'rgba(5,7,13,0.9)', wing: fg, trim: fg });
  D.sigil(ctx, sg, x + w * 0.7, y + h * 0.58, h * 0.0016 * 0.9 * 1.4, fg, bg);
  ctx.font = font(h * 0.13, 700, UI); ctx.letterSpacing = `${h * 0.01}px`; ctx.textAlign = 'center'; ctx.fillStyle = fg;
  ctx.fillText(label, x + w / 2, y + h * 0.19); ctx.letterSpacing = '0px';
  ctx.font = font(h * 0.055, 400, UI); ctx.letterSpacing = `${h * 0.008}px`; ctx.fillText(role, x + w / 2, y + h * 0.27); ctx.letterSpacing = '0px';
  ctx.strokeStyle = fg; ctx.lineWidth = 6; ctx.strokeRect(x + 14, y + 14, w - 28, h - 28);
  ctx.restore();
}
function sEnlist(ctx, u, t) {
  ctx.fillStyle = '#03040A'; ctx.fillRect(0, 0, W, H);
  const pw = 560, ph = 430, gx = (W - pw * 3) / 4, gy = (H - ph * 2) / 3;
  const push = E.inCubic(prog(u, 118, 120));
  ctx.save();
  const fx = gx * 2 + pw + pw / 2, fy = gy + ph / 2, z = 1 + push * 2.6;
  ctx.translate(W / 2, H / 2); ctx.scale(z, z); ctx.translate(-lerp(W / 2, fx, push), -lerp(H / 2, fy, push));
  for (let i = 0; i < 6; i++) {
    const c = i % 3, r = Math.floor(i / 3);
    const x = gx + c * (pw + gx), y = gy + r * (ph + gy);
    const k = springU(u, 110 + i * 0.5 - 0.1, SPRING.snappy);
    if (k <= 0) continue;
    const pulse = 1 + 0.025 * cue('kick', t) * (u > 113 ? 1 : 0);
    ctx.save(); ctx.translate(x + pw / 2, y + ph / 2); ctx.scale(Math.min(1.05, k) * pulse, pulse); ctx.translate(-(x + pw / 2), -(y + ph / 2));
    poster(ctx, i, x, y, pw, ph, u, t);
    ctx.restore();
  }
  ctx.restore();
  const b = E.outCubic(prog(u, 114, 114.6)) * (1 - push);
  if (b > 0) {
    ctx.save(); ctx.translate(W / 2, H / 2); ctx.rotate(-0.06);
    ctx.fillStyle = P.cobalt; ctx.fillRect(-W * b, -80, W * 2 * b, 160);
    ctx.fillStyle = P.goldHi; ctx.fillRect(-W * b, -80, W * 2 * b, 6); ctx.fillRect(-W * b, 74, W * 2 * b, 6);
    slam(ctx, 'EARN YOUR RANK', 0, 46, 124, UI, 700, P.white, u, 114.2, { track: 0.12, from: 0.6 });
    ctx.restore();
  }
}

// S17 (120..136): the host. Thousands of hoods with torches under the house banners.
function sHost(ctx, u, t) {
  const second = u >= 128;
  vgrad(ctx, [[0, '#03050C'], [0.48, P.night3], [0.58, '#8094C4'], [0.62, '#5A70A0'], [1, '#1A2440']]);
  moon(ctx, second ? 640 : 1500, second ? 300 : 210, second ? 240 : 110, 1);
  if (!second) glowDisc(ctx, W / 2, 610, 1000, 'rgba(150,180,230,0.4)', 1);
  if (!second) {
    crowdRows(ctx, 640, 14, 380, 360, { torches: true, t, march: (u - 120) * 0.12 });
    for (const [x, c, sg, a] of [[420, '#2B6CA8', 'crystal', P.frost], [960, '#E9ECF2', 'sun', P.gold], [1500, '#8A1A12', 'flame', P.ember]]) {
      Hd.flag(ctx, x - 200, 70, 400, 240, t + x, 0.9, { field: c, band: c, nx: 18, ny: 7 });
      D.sigil(ctx, sg, x, 190, 0.6, a, x === 960 ? P.cobalt : '#000');
    }
    slam(ctx, 'SCAMMERS, BEWARE', W / 2, 1010, 120, UI, 700, P.white, u, 120, { track: 0.06, plate: '#000' });
  } else {
    const lu = u - 128;
    ctx.save(); M.zoomAbout(ctx, 1 + 0.05 * lu / 8, W / 2, H);
    for (const [x, s, house] of [[180, 230, 'plain'], [620, 270, 'frigidus'], [1080, 300, 'empyerus'], [1560, 260, 'infernus'], [1900, 220, 'plain']]) {
      D.hoodBust(ctx, x, 820 - s * 0.2, s, { house, rings: true, trim: true, scarf: false, wings: house === 'empyerus' ? 0.5 : 0 });
    }
    ctx.restore();
    slam(ctx, 'THE HOOD IS WATCHING', W / 2, 170, 100, DISPLAY, 900, P.white, u, 128, { track: 0.06, shadow: '#000' });
  }
  flash(ctx, E.inCubic(prog(u, 135.2, 136)), '#000');
}

// S18 (136..140): dropout + held note. Emperyan, hood up: only the small glowing smile.
function sSmile(ctx, u, t) {
  const vocal = cue('vocal', t);
  const lu = u - 136;
  ctx.fillStyle = '#000'; ctx.fillRect(0, 0, W, H);
  const swell = clamp(lu / 4) * 0.6 + vocal * 0.4;
  ctx.save(); ctx.globalAlpha = 0.15 + 0.35 * swell; Hd.rays(ctx, W / 2, 470, 60, u * 0.01, null, P.goldHi); ctx.restore();
  glowDisc(ctx, W / 2, 470, 900, 'rgba(246,222,154,0.5)', swell);
  const s = 300 + 40 * lu / 4;
  D.hoodBust(ctx, W / 2, 470, s, { house: 'empyerus', wings: 0.3 + 0.5 * swell, smile: 0.4 + 0.6 * swell, trim: true });
}

// S19 (140..152): return. Rank and house sigils stamp in on every beat.
const INSIG = [['key', 'CLAVES'], ['hunt', 'VENARI'], ['rex', 'REX'], ['astra', 'ASTRA'], ['eye', 'PRAEFECTUS'], ['ticket', 'PITTACIUM'],
  ['bat', 'VESPERTILIO'], ['sickle', 'MESSOR'], ['coin', 'AUREUS'], ['crystal', 'FRIGIDUS'], ['flame', 'INFERNUS'], ['sun', 'EMPYERUS']];
function sInsignia(ctx, u, t) {
  const b = Math.min(11, Math.max(0, Math.floor(u - 140 + 0.12)));
  const bgs = [[P.cobalt, P.cobaltLo], [P.night3, P.night], [P.gold, P.goldLo]];
  const [c0, c1] = bgs[b % 3];
  ctx.fillStyle = c1; ctx.fillRect(0, 0, W, H);
  Hd.rays(ctx, W / 2, 470, 32, u * 0.05 + b, null, c0);
  Hd.guilloche(ctx, { cx: W / 2, cy: 470, R: 360, A: 24 + 20 * cue('kick', t), B: 9, n: 18, m: 5, lines: 16, phase: u * 0.1, color: b % 3 === 2 ? P.night : P.gold, width: 1.2, alpha: 0.6 });
  const k = springU(u, 140 + b - 0.12, SPRING.bouncy);
  const s = 1.6 - 0.6 * Math.min(1.1, k);
  const fg = b % 3 === 2 ? P.night : P.goldHi, dk = b % 3 === 2 ? P.night3 : P.gold;
  const [sg, name] = INSIG[b];
  ctx.save(); ctx.globalAlpha = clamp(k * 3);
  D.sigil(ctx, sg, W / 2, 470, 1.55 * s, fg, dk);
  ctx.restore();
  spaced(ctx, name, W / 2, 790, 44, DISPLAY, 700, fg, 0.3, 'center', clamp(k * 3));
  for (const [w, u0] of [['EARNED', 140], ['SWORN', 144], ['ETERNAL', 148]]) if (u >= u0 - 0.2 && u < u0 + 4) slam(ctx, w, W / 2, 1000, 120, UI, 700, b % 3 === 2 ? P.night : P.white, u, u0, { track: 0.3, from: 0.5 });
}

// S20 (152..156): the last hit. The decree is sealed.
function sDecree(ctx, u, t) {
  ctx.drawImage(PAPER, 0, 0);
  Hd.guilloche(ctx, { cx: W / 2, cy: 400, R: 360, A: 18, B: 6, n: 20, m: 5, lines: 18, phase: u * 0.02, color: P.gold, width: 1, alpha: 0.6 });
  D.emblem(ctx, W / 2, 420, 0.62, {}, {});
  ctx.fillStyle = 'rgba(19,37,75,0.35)';
  for (let i = 0; i < 5; i++) { const w = 900 - (i === 4 ? 400 : 60 * hash01(i, 81)); ctx.fillRect(W / 2 - 450, 760 + i * 34, w, 10); }
  const k = springU(u, 151.85, SPRING.snappy);
  if (k > 0) {
    const sq = 0.18 * M.wobble(u - 152, 2.4, 5);
    Hd.waxSeal(ctx, 1380, lerp(-300, 900, Math.min(1, k)), 120, 4, sq, { hi: P.cobaltHi, mid: P.cobalt, lo: P.cobaltLo, emb: '#8FB0FF' });
    const r = prog(u, 152, 153.2);
    if (r > 0 && r < 1) { ctx.strokeStyle = `rgba(47,91,216,${1 - r})`; ctx.lineWidth = 10 * (1 - r); ctx.beginPath(); ctx.arc(1380, 900, 130 + r * 300, 0, TAU); ctx.stroke(); }
  }
  slam(ctx, 'BY ORDER OF THE EMPYERUS', 1380, 1060, 30, UI, 500, P.cobaltLo, u, 152.5, { track: 0.35, from: 0.3 });
}

// S21 (156..164): end card.
function sEnd(ctx, u, t) {
  vgrad(ctx, [[0, P.night2], [1, '#000']]);
  Hd.guilloche(ctx, { cx: W / 2, cy: 400, R: 330, A: 20, B: 8, n: 14, m: 5, lines: 20, phase: u * 0.03, color: P.goldLo, width: 1, alpha: 0.5 });
  const k = E.outCubic(prog(u, 156, 157.5));
  ctx.save(); ctx.globalAlpha = k; D.emblem(ctx, W / 2, 420, 0.7, {}, {}); ctx.restore();
  typeOn(ctx, 'THE DOMINI FEDERATION', W / 2, 850, 72, DISPLAY, 800, P.goldHi, u, 156.3, 0.08, 0.1);
  spaced(ctx, 'DO NOT TAKE AS GOLD ALL THAT SHINES LIKE GOLD', W / 2, 920, 26, DISPLAY, 600, P.white, 0.25, 'center', 0.85 * E.outCubic(prog(u, 157.5, 158.5)));
  spaced(ctx, 'MUSIC  ·  SKILLET  —  HERO', W / 2, 1010, 20, UI, 400, P.white, 0.4, 'center', 0.55 * E.outCubic(prog(u, 158.5, 159.5)));
  flash(ctx, prog(u, 162.6, 163.9), '#000');
}

// ---------------------------------------------------------------- timeline
const SCENES = [
  [-99, 8, sSeal], [8, 16, sOrder], [16, 20, sHunted], [20, 32, sHunter], [32, 40, sLadder], [40, 48, sMarch],
  [48, 60, sRaid], [60, 64, sRestitution], [64, 68, sEmptySeat], [68, 76, sHouses], [76, 80, sCrownDark],
  [80, 88, sLord], [88, 98, sCourt], [98, 110, sSword], [110, 120, sEnlist], [120, 136, sHost],
  [136, 140, sSmile], [140, 152, sInsignia], [152, 156, sDecree], [156, 999, sEnd],
];

function post(ctx, u, t) {
  const cr = cue('crash', t);
  if (cr > 0.05 && !(u >= 64 && u < 68) && !(u >= 136 && u < 140)) {
    ctx.save(); ctx.globalCompositeOperation = 'lighter'; ctx.globalAlpha = cr * 0.14;
    ctx.fillStyle = P.goldHi; ctx.fillRect(0, 0, W, H); ctx.restore();
  }
  ctx.drawImage(VIGNETTE, 0, 0);
  const g = GRAIN[Math.floor(t * 24) % GRAIN.length];
  ctx.save(); ctx.globalAlpha = 0.07; ctx.globalCompositeOperation = 'overlay';
  ctx.drawImage(g, 0, 0, W, H); ctx.restore();
}

M.film({
  fonts: [font(100, 800, DISPLAY), font(100, 900, DISPLAY), font(100, 700, DISPLAY), font(100, 600, DISPLAY), font(40, 700, UI), font(40, 500, UI), font(40, 400, UI)],
  hits: HITS,
  samples: 6,
  async init() {
    CUE = await fetch('analysis/cues.json').then((r) => r.json());
    buildTextures();
  },
  draw(ctx, u, t) {
    const sc = SCENES.find(([a, b]) => u >= a && u < b) || SCENES[SCENES.length - 1];
    ctx.save();
    sc[2](ctx, u, t);
    ctx.restore();
    post(ctx, u, t);
  },
});
