// HERO: The Federation. A state broadcast engraved in gold.
// Pure function of time: window.seek(t) paints frame t (see lib/motion.js). Timing is in beats (u)
// on the grid measured by tools/song-analyzer (beats.json: u = 0 is the first downbeat, 0.538 s
// into the excerpt; bar k starts at u = 4k). Audio-reactive values come from analysis/cues.json:
// per-frame envelopes precomputed from the song, so the film stays a pure function of t.
// docs/shotlist.md is the plan this file follows.

import * as M from './lib/motion.js';
import * as T from './lib/three-lite.js';
import * as Hd from './lib/heraldry.js';

const { W, H, E, TAU, clamp, lerp, prog, bump, springU, SPRING, kf, font, hash01, noise1 } = M;
const P = Hd.PAL;
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

// ---------------------------------------------------------------- visual hit list (for sync.py)
// [beat, label]: every planned accent on the grid. The song is the soundtrack, so no SFX.
const HITS = [
  [0, 'crest forge'], [4, 'crown lands'], [6, 'title stamp'], [8, 'sovereign'], [15, 'crash flash'], [16, 'bearer rises'],
  [20, 'STAND'], [24, 'SERVE'], [28, 'PREVAIL'], [32, 'the legion'], [40, 'side march'], [48, 'the fleet'], [57, 'broadside'],
  [60, 'the realm'], [64, 'dropout: memorial'], [68, 'impact: salute'], [72, 'WE ADVANCE'], [76, 'band out: crown'],
  [80, 'final chorus: coronation'], [88, 'balcony'], [98, 'ascent'], [100, 'ONE CROWN'], [104, 'ONE BANNER'],
  [108, 'ONE FEDERATION'], [110, 'enlist'], [120, 'armada'], [136, 'portrait: held note'], [140, 'insignia march'],
  [152, 'the seal'], [156, 'end card'],
];

// ---------------------------------------------------------------- 3D models (built once)
const GOLD = Hd.rgb(P.gold), GOLDHI = Hd.rgb(P.goldHi), CRIM = Hd.rgb(P.crimson), NAVY3 = Hd.rgb(P.navy3);
const STEEL = [0.34, 0.4, 0.55], STEEL_D = [0.2, 0.25, 0.38];

const STAR3D = T.starParts(8, 1.112, 0.418, 0.32, { c: GOLD, spec: 0.9, shin: 28, edge: P.goldHi });

const MEDAL = [
  ...T.starParts(8, 1.0, 0.46, 0.22, { c: GOLD, spec: 1.0, shin: 30, edge: P.goldHi }),
  T.extrude(Array.from({ length: 24 }, (_, i) => [Math.cos((i / 24) * TAU) * 0.42, Math.sin((i / 24) * TAU) * 0.42]), 0.3, { c: CRIM, spec: 0.6, shin: 40, edge: P.goldHi }),
];

function buildCrown() {
  const parts = [];
  parts.push(...T.lathe([[1.0, 0], [1.04, 0.04], [1.04, 0.3], [1.0, 0.34]], 28, { c: GOLD, spec: 0.9, shin: 26, twoSided: true, edge: P.goldLo }));
  parts.push(...T.lathe([[0.95, 0.3], [0.9, 0.62], [0.66, 0.86], [0.34, 0.98], [0.02, 1.02]], 18, { c: Hd.rgb(P.crimsonLo), spec: 0.15, shin: 8 }));
  for (let k = 0; k < 8; k++) {
    const a = (k / 8) * TAU, tall = k % 2 === 0 ? 0.82 : 0.56;
    const p = (ang, r, y) => [Math.cos(ang) * r, y, Math.sin(ang) * r];
    parts.push(T.part([p(a - 0.2, 1.03, 0.33), p(a + 0.2, 1.03, 0.33), p(a, 0.88, 0.33), p(a, 1.0, 0.33 + tall)],
      [[0, 1, 3], [1, 2, 3], [2, 0, 3], [0, 2, 1]], { c: GOLD, spec: 1.0, shin: 30, edge: P.goldHi }));
    const tip = p(a, 1.0, 0.33 + tall + 0.07), s = 0.06;
    parts.push(T.part([[tip[0] + s, tip[1], tip[2]], [tip[0] - s, tip[1], tip[2]], [tip[0], tip[1] + s, tip[2]], [tip[0], tip[1] - s, tip[2]], [tip[0], tip[1], tip[2] + s], [tip[0], tip[1], tip[2] - s]],
      [[0, 2, 4], [2, 1, 4], [1, 3, 4], [3, 0, 4], [2, 0, 5], [1, 2, 5], [3, 1, 5], [0, 3, 5]], { c: GOLDHI, spec: 1.2, shin: 40 }));
    const jw = p(a + Math.PI / 8, 1.05, 0.17);
    parts.push(T.box(0.12, 0.12, 0.05, { c: k % 2 ? CRIM : NAVY3, spec: 1.2, shin: 50 }, jw));
  }
  const top = [0, 1.18, 0], s = 0.11;
  parts.push(T.part([[s, 1.18, 0], [-s, 1.18, 0], [0, 1.18 + s * 1.6, 0], [0, 1.18 - s, 0], [0, 1.18, s], [0, 1.18, -s]],
    [[0, 2, 4], [2, 1, 4], [1, 3, 4], [3, 0, 4], [2, 0, 5], [1, 2, 5], [3, 1, 5], [0, 3, 5]], { c: GOLDHI, spec: 1.2, shin: 40 }));
  void top;
  return parts;
}
const CROWN3D = buildCrown();

function buildShip() {
  const parts = [];
  const sec = [[-0.36, 0], [-0.3, 0.16], [0.3, 0.16], [0.36, 0], [0.24, -0.2], [-0.24, -0.2]];
  const hull = { c: STEEL, spec: 0.35, shin: 20, edge: P.gold };
  parts.push(T.taper(sec, -1.0, -0.55, 0.92, 1.0, hull));
  parts.push(T.taper(sec, -0.55, 0.55, 1.0, 0.9, hull));
  parts.push(T.taper(sec, 0.55, 1.45, 0.9, 0.12, hull));
  const sup = { c: STEEL_D, spec: 0.3, shin: 20, edge: P.goldLo };
  parts.push(T.box(0.34, 0.3, 0.42, sup, [0, 0.3, -0.25]));
  parts.push(T.box(0.22, 0.2, 0.24, sup, [0, 0.54, -0.28]));
  parts.push(T.box(0.04, 0.42, 0.04, sup, [0, 0.82, -0.3]));
  for (const z of [0.4, 0.78, -0.72]) {
    parts.push(T.box(0.2, 0.09, 0.2, sup, [0, 0.21, z]));
    parts.push(T.box(0.03, 0.03, 0.32, { c: STEEL_D, spec: 0.2 }, [0.04, 0.23, z + (z > 0 ? 0.24 : -0.24)]));
    parts.push(T.box(0.03, 0.03, 0.32, { c: STEEL_D, spec: 0.2 }, [-0.04, 0.23, z + (z > 0 ? 0.24 : -0.24)]));
  }
  for (const sx of [-1, 1]) {
    parts.push(T.part([[sx * 0.3, 0.02, -0.2], [sx * 1.0, -0.02, -0.7], [sx * 1.0, -0.06, -0.95], [sx * 0.3, -0.04, -0.85],
      [sx * 0.3, 0.07, -0.2], [sx * 1.0, 0.03, -0.7], [sx * 1.0, -0.01, -0.95], [sx * 0.3, 0.01, -0.85]],
      [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]], { c: STEEL, spec: 0.4, shin: 20, edge: P.gold }));
  }
  const eng = { c: Hd.rgb('#FFB347'), spec: 0, emissive: 1.1 };
  for (const ex of [-0.17, 0.17]) parts.push(T.box(0.13, 0.13, 0.04, eng, [ex, -0.02, -1.01]));
  // crest plate on the bow (crimson)
  parts.push(T.box(0.5, 0.1, 0.02, { c: CRIM, spec: 0.5, emissive: 0.2 }, [0, 0.06, 1.0]));
  return parts;
}
const SHIP = buildShip();

// ---------------------------------------------------------------- precomputed 2D data
// Hex map of an invented continent; capital near the centre.
const HEXES = (() => {
  const out = [], R = 15;
  const shape = (x, y) => {
    const a = Math.atan2(y, x), d = Math.hypot(x / 1.35, y);
    const r = 330 * (1 + 0.22 * noise1(a * 2.3 + 4, 7) + 0.12 * noise1(a * 6.1, 9) + 0.06 * noise1(a * 13, 2));
    return d < r;
  };
  for (let row = -30; row <= 30; row++) {
    for (let col = -40; col <= 40; col++) {
      const x = col * R * 1.73 + (row % 2 ? R * 0.866 : 0), y = row * R * 1.5;
      if (shape(x, y)) out.push({ x, y, d: Math.hypot(x + 60, y - 20), h: hash01(row * 101 + col, 5) });
    }
  }
  return out;
})();
// Gold-leaf lozenges for the coronation burst.
const LEAVES = Array.from({ length: 140 }, (_, i) => ({
  a: hash01(i, 11) * TAU, v: 900 + 1500 * hash01(i, 12), spin: (hash01(i, 13) - 0.5) * 14,
  s: 10 + 22 * hash01(i, 14), c: hash01(i, 15) < 0.75 ? (hash01(i, 16) < 0.5 ? P.goldHi : P.gold) : P.crimson, d: hash01(i, 17) * 0.25,
}));
// Crowd flags for the balcony (world grid in front of the palace).
const CROWD = Array.from({ length: 2400 }, (_, i) => ({
  x: (hash01(i, 21) - 0.5) * 60, z: 4 + hash01(i, 22) * 46, ph: hash01(i, 23) * TAU, c: hash01(i, 24),
}));
const FLEET = Array.from({ length: 26 }, (_, i) => ({
  x: (hash01(i, 31) - 0.5) * 130, y: 6 + hash01(i, 32) * 26, z: 40 + hash01(i, 33) * 150, s: 2.2 + hash01(i, 34) * 1.6, ph: hash01(i, 35) * TAU,
}));

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
  gr.addColorStop(0, 'rgba(0,0,0,0)'); gr.addColorStop(1, 'rgba(0,0,0,0.62)');
  v.fillStyle = gr; v.fillRect(0, 0, W, H);
  // parchment: warm ivory with fibres (seeded)
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

// ---------------------------------------------------------------- type helpers

// Slam-in text: scale 1.9 -> 1 on a snappy spring from beat u0, optional exit at u1.
function slam(ctx, str, x, y, size, family, weight, color, u, u0, o = {}) {
  const k = springU(u, u0, o.spring || SPRING.snappy);
  if (k <= 0) return;
  let s = 1 + (o.from ?? 0.9) * (1 - k), a = clamp(k * 2.5);
  let dx = 0;
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

// Type-on: glyphs appear one per `rate` beats from u0, each dropping into place.
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
  ctx.save(); ctx.globalAlpha *= a;
  const g = ctx.createRadialGradient(x, y, 0, x, y, r);
  g.addColorStop(0, col); g.addColorStop(1, 'rgba(0,0,0,0)');
  ctx.globalCompositeOperation = 'lighter';
  ctx.fillStyle = g; ctx.fillRect(x - r, y - r, 2 * r, 2 * r);
  ctx.restore();
}

// Art-deco sun: disc with horizontal cut stripes toward the bottom.
function decoSun(ctx, x, y, r, col, cut) {
  ctx.save();
  ctx.beginPath(); ctx.arc(x, y, r, 0, TAU); ctx.clip();
  ctx.fillStyle = col; ctx.fillRect(x - r, y - r, 2 * r, 2 * r);
  ctx.fillStyle = cut;
  for (let i = 0; i < 7; i++) {
    const yy = y + r * (0.15 + i * 0.13), hh = r * (0.012 + i * 0.012);
    ctx.fillRect(x - r, yy, 2 * r, hh);
  }
  ctx.restore();
}

// ================================================================= SCENES

// S1-2 (u -1.3 .. 8): the engraver's line, then the crest is forged.
function sForge(ctx, u, t) {
  const kick = cue('kick', t);
  vgrad(ctx, [[0, P.navy], [0.55, P.navy2], [1, P.ink]]);
  const cx = W / 2, cy = 470;
  // rays ignite when the crown lands
  const ra = E.outCubic(prog(u, 3.8, 5.5));
  if (ra > 0) {
    ctx.save(); ctx.globalAlpha = ra * (0.22 + 0.25 * kick);
    Hd.rays(ctx, cx, cy, 36, u * 0.02, null, P.gold);
    ctx.restore();
  }
  // rosettes: the pickup engraves the first one; the downbeat blooms the second
  const g1 = u < 0 ? 0.55 + 0.45 * E.inCubic(prog(u, -1.3, 0)) : 1;
  Hd.guilloche(ctx, { cx, cy, R: 318, A: 22 + 18 * kick, B: 8, n: 14, m: 5, lines: 22, phase: u * 0.05, prog: g1, color: P.gold, width: 1.1, alpha: 0.75 });
  const g2 = E.outCubic(prog(u, 0, 2.2));
  Hd.guilloche(ctx, { cx, cy, R: 420 + 30 * E.outBack(prog(u, 0, 1)), A: 14 + 10 * kick, B: 5, n: 24, m: 7, lines: 16, phase: -u * 0.04, prog: g2, color: P.goldLo, width: 1, alpha: 0.7 });
  // engraver's needle head on the pickup
  if (u < 0) {
    const th = g1 * TAU + 0.15 * u * 0.05;
    const r = 318 + 22 * Math.sin(14 * th);
    glowDisc(ctx, cx + r * Math.cos(th), cy + r * Math.sin(th), 60, 'rgba(255,230,160,0.9)');
  }
  const S = 1.0 + 0.012 * kick;
  const pc = {
    sabers: E.outBack(prog(u, 1, 2.6), 1.4), laurel: E.outCubic(prog(u, 0.6, 3.2)), star: u >= 2 ? 1 : 0,
    crown: springU(u, 4, SPRING.bouncy), ribbon: E.outBack(prog(u, 5, 6), 1.2),
  };
  if (u >= 0) Hd.crest(ctx, cx, cy, S, pc, {});
  else return;
  // the star arrives in 3D, spinning out of depth, and lands on beat 2
  if (u < 2.05) {
    const k = E.outCubic(prog(u, 0, 2));
    const cam = T.camera({ pos: [0, 0, -10], target: [0, 0, 0], fov: 40, W, H });
    const z = lerp(26, 0, k);
    // disc behind the star, appearing with it
    ctx.save(); ctx.globalAlpha = k;
    ctx.beginPath(); ctx.arc(cx, cy, 150 * k, 0, TAU); ctx.fillStyle = P.navy2; ctx.fill(); ctx.lineWidth = 8; ctx.strokeStyle = P.gold; ctx.stroke();
    ctx.restore();
    T.draw3d(ctx, cam, [{ parts: STAR3D, pos: [0, 0.472, z], rot: [0.35 * (1 - k), (1 - k) * 5.2, 0] }],
      { dir: [-0.3, 0.6, -1], ambient: 0.45, diffuse: 0.7 });
  }
  if (u >= 2 && u < 2.6) glowDisc(ctx, cx, cy, 380, 'rgba(255,225,150,0.8)', 1 - prog(u, 2, 2.6));
  // the title stamps in, letter by letter
  const f = font(104, 800, DISPLAY);
  const L = M.layout(ctx, 'THE FEDERATION', f, 14);
  L.glyphs.forEach((gl, i) => {
    const k = springU(u, 6 + i * 0.09, SPRING.snappy);
    if (k <= 0) return;
    ctx.save(); ctx.globalAlpha = clamp(k * 3);
    const x = cx - L.width / 2 + gl.cx, y = 925;
    ctx.translate(x, y); ctx.scale(1 + (1 - k) * 1.2, 1 + (1 - k) * 1.2);
    ctx.font = f; ctx.textAlign = 'center';
    ctx.fillStyle = P.goldLo; ctx.fillText(gl.ch, 3, 4);
    ctx.fillStyle = P.goldHi; ctx.fillText(gl.ch, 0, 0);
    ctx.restore();
  });
}

// S3 (8..16): the Sovereign, engraved like a banknote.
function sSovereign(ctx, u, t) {
  const lu = u - 8;
  const kick = cue('kick', t);
  ctx.drawImage(PAPER, 0, 0);
  const z = 1 + 0.12 * E.inOutSine(prog(u, 8, 16));
  const settle = springU(u, 8, SPRING.gentle);
  ctx.save();
  M.zoomAbout(ctx, z, W / 2, 470);
  ctx.translate(W / 2, H / 2); ctx.rotate(-0.05 * (1 - settle)); ctx.translate(-W / 2, -H / 2 + (1 - settle) * 60);
  // banknote frame: rosettes either side, guilloche band around the oval
  const ox = W / 2, oy = 520;
  for (const s of [-1, 1]) {
    Hd.guilloche(ctx, { cx: ox + s * 640, cy: oy, R: 170, A: 26 + 10 * kick, B: 10, n: 12, m: 5, lines: 20, phase: s * u * 0.08, color: P.navy3, width: 1, alpha: 0.75 });
    Hd.guilloche(ctx, { cx: ox + s * 640, cy: oy, R: 90, A: 18, n: 9, m: 4, lines: 14, phase: -s * u * 0.1, color: P.crimson, width: 1, alpha: 0.6 });
    Hd.star8(ctx, ox + s * 640, oy, 46, 18, 0, P.gold, P.goldLo);
  }
  Hd.guilloche(ctx, { cx: ox, cy: oy, R: 360, A: 16 + 8 * kick, B: 6, n: 40, m: 9, lines: 18, phase: u * 0.03, color: P.navy2, width: 1, alpha: 0.85, squash: 1.08, steps: 900 });
  Hd.guilloche(ctx, { cx: ox, cy: oy, R: 330, A: 8, n: 60, m: 7, lines: 10, phase: -u * 0.05, color: P.gold, width: 1, alpha: 0.9, squash: 1.08, steps: 900 });
  // the oval portrait window
  ctx.save();
  ctx.beginPath(); ctx.ellipse(ox, oy, 300, 324, 0, 0, TAU); ctx.clip();
  ctx.fillStyle = P.ivory; ctx.fillRect(ox - 320, oy - 340, 640, 680);
  Hd.sovereign(ctx, ox - 300, oy - 300 + 30, 600, { ink: P.navy, light: '#F7EEDB', glow: 0.1 * cue('vocal', t) });
  ctx.restore();
  ctx.lineWidth = 6; ctx.strokeStyle = P.gold; ctx.beginPath(); ctx.ellipse(ox, oy, 302, 326, 0, 0, TAU); ctx.stroke();
  ctx.restore();
  // inscriptions
  typeOn(ctx, 'THE SOVEREIGN', W / 2, 120, 84, DISPLAY, 800, P.navy, u, 8.5, 0.12, 0.12);
  slam(ctx, 'BY CROWN AND COMMONWEALTH', W / 2, 1000, 34, UI, 500, P.crimson, u, 10, { track: 0.35, from: 0.4 });
  // crash at u15: gold flash out
  const fl = bump(u, 15.1, 0.45) * 0.8;
  if (fl > 0) { ctx.save(); ctx.globalAlpha = fl; ctx.fillStyle = P.goldHi; ctx.fillRect(0, 0, W, H); ctx.restore(); }
  void lu;
}

// S4-5 (16..32): the standard bearer rises; the belted line becomes the hero shot.
function sBearer(ctx, u, t) {
  const vocal = cue('vocal', t), pitch = Math.max(0, cue('pitch', t)), kick = cue('kick', t);
  const hero = u >= 20;
  // sky: crimson to gold, warming with the voice
  vgrad(ctx, [[0, P.crimsonLo], [0.45, P.crimson], [0.78, '#E07A3A'], [1, P.goldHi]]);
  const hx = hero ? 1160 : 1100, hy = hero ? 860 : 820;
  const lift = hero ? 0.25 + 0.75 * clamp(vocal * 0.6 + pitch * 0.5) : 0.15;
  ctx.save(); ctx.globalAlpha = 0.18 + 0.3 * lift + 0.15 * kick;
  Hd.rays(ctx, hx, hy, 28, u * 0.025, null, P.goldHi);
  ctx.restore();
  decoSun(ctx, hx, hy, hero ? 330 : 260, P.goldHi, P.crimson);
  glowDisc(ctx, hx, hy, 620, 'rgba(255,220,150,0.65)', 0.35 + 0.5 * lift);
  // camera: rising crane in the hero shot, follows the voice
  const crane = hero ? kf(u, [[20, 0], [32, 1]], E.inOutSine) * 90 + pitch * 26 : 0;
  ctx.save();
  ctx.translate(0, crane);
  if (hero) M.shake(ctx, u, Math.floor(u), 3 * cue('snare', t), 5);
  // ridge
  ctx.fillStyle = P.ink;
  ctx.beginPath(); ctx.moveTo(-50, H + 200);
  ctx.lineTo(-50, 930); ctx.quadraticCurveTo(500, hero ? 820 : 880, 900, hero ? 850 : 900); ctx.quadraticCurveTo(1400, 900, W + 50, 960); ctx.lineTo(W + 50, H + 200); ctx.closePath(); ctx.fill();
  // the bearer
  const rise = springU(u, 16, SPRING.gentle);
  const bx = hero ? 640 : 700, by = hero ? 862 + (1 - 1) * 0 : 900 + (1 - rise) * 700;
  const bh = hero ? 470 : 380;
  const top = Hd.bearer(ctx, bx, by, bh, P.ink, hero ? -0.04 : 0);
  Hd.flag(ctx, top[0], top[1] + 4, hero ? 780 : 560, hero ? 420 : 300, t, 0.85 + 0.15 * vocal, { speed: 0.9 });
  ctx.restore();
  // slogans on the belted line
  if (hero) {
    const words = [['STAND', 20], ['SERVE', 24], ['PREVAIL', 28]];
    words.forEach(([w, u0], i) => {
      slam(ctx, w, 1830, 330, 230, UI, 700, P.ivory, u, u0, { align: 'right', plate: P.ink, u1: u0 + 3.75, outLen: 0.25, outDir: 1, rot: 0.04, track: 0.02 });
      void i;
    });
  }
}

// S6 (32..40): the Legion marches toward camera, backlit by a gold sun on the horizon.
function sLegionFront(ctx, u, t) {
  const kick = cue('kick', t);
  const hz = 560, vx = W / 2;
  vgrad(ctx, [[0, P.ink], [0.3, P.navy2], [0.47, '#A8402F'], [0.52, P.goldHi], [0.53, P.ink], [1, P.ink]]);
  decoSun(ctx, vx, hz, 300 + 6 * kick, P.goldHi, '#A8402F');
  glowDisc(ctx, vx, hz, 700, 'rgba(246,222,154,0.55)', 0.8);
  // polished parade ground: reflects the sun, so the marching silhouettes read against it
  const gg = ctx.createLinearGradient(0, hz, 0, H);
  gg.addColorStop(0, P.goldHi); gg.addColorStop(0.12, '#C0603A'); gg.addColorStop(0.45, P.crimsonLo); gg.addColorStop(1, P.navy2);
  ctx.fillStyle = gg; ctx.fillRect(0, hz, W, H - hz);
  // ground lines converge on the sun
  ctx.strokeStyle = 'rgba(142,106,38,0.7)'; ctx.lineWidth = 1.5;
  for (let i = -18; i <= 18; i++) { ctx.beginPath(); ctx.moveTo(vx, hz); ctx.lineTo(vx + i * 240, H + 40); ctx.stroke(); }
  const march = (u - 32) * 0.5;
  const N = 8, near = 1.15;
  const rows = [];
  for (let k = 0; k < N; k++) rows.push(near + ((k - march) % N + N) % N);
  rows.sort((a, b) => b - a);
  const sky = Hd.rgb('#C0603A'), ink = Hd.rgb(P.ink);
  for (const z of rows) {
    const sc = 1 / z, y = hz + 520 * sc, h = 560 * sc;
    const fogT = clamp((z - 1.5) / 7) * 0.75;
    const col = `rgb(${[0, 1, 2].map((i) => Math.round((ink[i] + (sky[i] - ink[i]) * fogT) * 255)).join(',')})`;
    const fade = clamp((z - near) / 0.35) * clamp((near + N - 0.2 - z) / 0.8);
    ctx.globalAlpha = fade;
    for (let c = -6; c <= 6; c++) {
      const x = vx + c * 250 * sc;
      Hd.soldierFront(ctx, x, y, h, u / 2, col, col);
      if (c === -4 || c === 4) {
        const py = y - h * 1.35;
        ctx.strokeStyle = col; ctx.lineWidth = Math.max(1, 6 * sc); ctx.beginPath(); ctx.moveTo(x + h * 0.16, y - h * 0.5); ctx.lineTo(x + h * 0.16, py); ctx.stroke();
        Hd.flag(ctx, x + h * 0.16, py, h * 0.55, h * 0.3, t + c * 0.3 + z, 0.85, { nx: 10, ny: 4 });
      }
    }
    ctx.globalAlpha = 1;
  }
  slam(ctx, 'THE LEGION', W / 2, 170, 130, DISPLAY, 900, P.goldHi, u, 32, { track: 0.08, shadow: P.ink });
  slam(ctx, 'MARCHES AS ONE', W / 2, 245, 40, UI, 500, P.ivory, u, 34, { track: 0.4, from: 0.3 });
}

// S7 (40..48): side tracking shot, three parallax layers under a crimson sun.
function sLegionSide(ctx, u, t) {
  vgrad(ctx, [[0, P.gold], [0.7, P.goldHi], [1, P.goldHi]]);
  const scroll = (u - 40) * 40;
  decoSun(ctx, 1240 - scroll * 0.15, 560, 420, P.crimson, P.goldHi);
  // distant towers
  ctx.fillStyle = P.crimsonLo;
  for (let i = 0; i < 14; i++) {
    const x = ((i * 190 - scroll * 0.3) % 2600 + 2600) % 2600 - 300, h = 120 + 140 * hash01(i, 41);
    ctx.fillRect(x, 820 - h, 60, h); ctx.fillRect(x + 20, 820 - h - 40, 20, 40);
  }
  ctx.fillStyle = P.ink; ctx.fillRect(0, 818, W, 300);
  const layers = [[0.45, 0.25, P.crimsonLo, 860, 230], [0.7, 0.55, P.navy2, 930, 330], [1.0, 1.0, P.ink, 1060, 520]];
  for (const [sc, sp, col, gy, hh] of layers) {
    if (col === P.ink) { ctx.fillStyle = P.navy; ctx.fillRect(0, gy - 6, W, 400); }
    const gap = 230 * sc;
    const off = (scroll * sp * 0.6) % gap;
    for (let x = -gap + off - 40; x < W + gap; x += gap) {
      Hd.soldier(ctx, x, gy, hh, u / 2 + (x / gap) * 0.0, col, 'march', 1);
    }
  }
  slam(ctx, 'TEN THOUSAND STRONG', 120, 190, 110, UI, 700, P.ink, u, 40, { align: 'left', track: 0.02, from: 0.5 });
  slam(ctx, 'ONE STEP. ONE WILL.', 126, 260, 40, UI, 400, P.crimsonLo, u, 44, { align: 'left', track: 0.3, from: 0.3 });
}

// S8 (48..60): the fleet comes out of the clouds.
function sFleet(ctx, u, t) {
  const lu = u - 48;
  vgrad(ctx, [[0, P.ink], [0.5, P.navy2], [0.85, P.steel], [1, '#7A6A5A']]);
  // clouds: soft banks drifting toward camera
  for (let i = 0; i < 9; i++) {
    const y = 700 + i * 40 + Math.sin(i) * 20, x = ((i * 430 + lu * 30 * (1 + i * 0.1)) % 2600) - 340;
    ctx.fillStyle = `rgba(30,55,104,${0.35 + 0.05 * i})`;
    ctx.beginPath(); ctx.ellipse(x, y, 420, 70, 0, 0, TAU); ctx.fill();
  }
  const cam = T.camera({ pos: [0, 0, -6], target: [0, 5.5 + lu * 0.25, 20], fov: 54, W, H, roll: 0.04 * Math.sin(lu * 0.3) });
  const objs = [];
  const V = [[0, 0, 0], [-9, -1.5, -9], [9, -1.5, -9], [-18, -3, -18], [18, -3, -18], [-27, -4.5, -27], [27, -4.5, -27]];
  const adv = lu * 3.1;
  V.forEach(([x, y, z], i) => {
    const pos = [x, 9 + y + Math.sin(u * 0.4 + i) * 0.3, 42 + z - adv];
    objs.push({ parts: SHIP, pos, scale: i === 0 ? 6.5 : 5, rot: [0.08, Math.PI, 0.02 * Math.sin(u + i)] });
  });
  objs.sort((a, b) => b.pos[2] - a.pos[2]);
  // searchlights under each ship (behind the hulls)
  ctx.save(); ctx.globalCompositeOperation = 'lighter';
  for (const o of objs) {
    const pr = cam.project(T.add(o.pos, [0, -0.6 * o.scale, 0]));
    if (!pr) continue;
    const L = 900 * (1 - pr[2] / 120), sw = Math.sin(u * 0.5 + o.pos[0]) * 0.25;
    const g = ctx.createLinearGradient(pr[0], pr[1], pr[0] + sw * L, pr[1] + L);
    g.addColorStop(0, 'rgba(246,222,154,0.35)'); g.addColorStop(1, 'rgba(246,222,154,0)');
    ctx.fillStyle = g;
    ctx.beginPath(); ctx.moveTo(pr[0] - 6, pr[1]); ctx.lineTo(pr[0] + 6, pr[1]); ctx.lineTo(pr[0] + sw * L + L * 0.18, pr[1] + L); ctx.lineTo(pr[0] + sw * L - L * 0.18, pr[1] + L); ctx.closePath(); ctx.fill();
  }
  ctx.restore();
  T.draw3d(ctx, cam, objs, { dir: [0.3, 0.9, -0.4], ambient: 0.4, diffuse: 0.75, fog: Hd.rgb(P.navy2), fogNear: 30, fogFar: 110, edgeAlpha: 0.7 });
  // broadside on the crash at u57
  const bs = bump(u, 57.1, 0.7);
  if (bs > 0) {
    const lead = objs.find((o) => o.scale > 6);
    const pr = lead && cam.project(lead.pos);
    if (pr) for (let k = -2; k <= 2; k++) glowDisc(ctx, pr[0] + k * 70, pr[1] + 20, 160 * bs, 'rgba(255,200,120,1)', bs);
    ctx.save(); ctx.globalAlpha = bs * 0.35; ctx.fillStyle = P.goldHi; ctx.fillRect(0, 0, W, H); ctx.restore();
  }
  slam(ctx, 'THE FLEET ANSWERS', W / 2, 980, 92, DISPLAY, 800, P.goldHi, u, 52, { track: 0.1, shadow: P.ink });
}

// S9 (60..64): the realm lights up from the capital.
function sRealm(ctx, u, t) {
  vgrad(ctx, [[0, P.ink], [1, P.navy]]);
  const lu = u - 60;
  const fadeOut = 1 - prog(u, 63.4, 64);
  ctx.save();
  ctx.globalAlpha = fadeOut;
  ctx.translate(W / 2, 560); ctx.scale(1.12 + lu * 0.02, 0.78 + lu * 0.01); ctx.rotate(-0.06);
  const reach = 40 + lu * 140;
  for (const h of HEXES) {
    const lit = h.d < reach;
    ctx.beginPath();
    for (let k = 0; k < 6; k++) { const a = (k / 6) * TAU + Math.PI / 6; ctx.lineTo(h.x + Math.cos(a) * 14, h.y + Math.sin(a) * 14); }
    ctx.closePath();
    const edge = lit && h.d > reach - 50;
    ctx.fillStyle = lit ? (edge ? P.goldHi : (h.h < 0.15 ? P.crimson : P.gold)) : P.navy2;
    ctx.fill();
    ctx.strokeStyle = P.ink; ctx.lineWidth = 2; ctx.stroke();
  }
  // capital + rings per beat
  for (let k = 0; k < 4; k++) {
    const r = (prog(u, 60 + k, 61.4 + k)) * 600;
    if (r > 0 && r < 600) { ctx.strokeStyle = `rgba(246,222,154,${1 - r / 600})`; ctx.lineWidth = 3; ctx.beginPath(); ctx.arc(-60, 20, r, 0, TAU); ctx.stroke(); }
  }
  ctx.restore();
  ctx.save(); ctx.globalAlpha = fadeOut;
  Hd.crown2d(ctx, W / 2 - 67, 560 + 6, 70);
  slam(ctx, 'ONE REALM', W / 2, 140, 96, DISPLAY, 800, P.goldHi, u, 60, { track: 0.14 });
  ctx.restore();
}

// S10 (64..68): dropout. A memorial: the medal falls in one beam of light.
function sMemorial(ctx, u, t) {
  ctx.fillStyle = P.ink; ctx.fillRect(0, 0, W, H);
  const lu = u - 64;
  // light cone
  ctx.save(); ctx.globalCompositeOperation = 'lighter';
  const g = ctx.createLinearGradient(0, 0, 0, H);
  g.addColorStop(0, 'rgba(246,222,154,0.22)'); g.addColorStop(1, 'rgba(246,222,154,0.02)');
  ctx.fillStyle = g; ctx.beginPath(); ctx.moveTo(W / 2 - 60, -10); ctx.lineTo(W / 2 + 60, -10); ctx.lineTo(W / 2 + 330, H); ctx.lineTo(W / 2 - 330, H); ctx.closePath(); ctx.fill();
  ctx.restore();
  // dust motes in the beam (seeded)
  for (let i = 0; i < 60; i++) {
    const x = W / 2 + (hash01(i, 51) - 0.5) * 420 * (0.4 + hash01(i, 54)), y = ((hash01(i, 52) * H + lu * 25 * (0.5 + hash01(i, 53))) % H);
    ctx.fillStyle = `rgba(246,222,154,${0.15 + 0.3 * hash01(i, 55)})`; ctx.fillRect(x, y, 2, 2);
  }
  const fall = E.outCubic(prog(u, 64, 67.6));
  const y = lerp(-3.2, 0.2, fall);
  const cam = T.camera({ pos: [0, 0, -8], target: [0, 0, 0], fov: 40, W, H });
  // ribbon above the medal (2D), following the projected top point
  const top = cam.project([0, y + 1.0, 0]);
  if (top) {
    const sway = Math.sin(lu * 1.2) * 10;
    ctx.save(); ctx.translate(top[0], top[1]);
    const stripes = [P.navy3, P.crimson, P.goldHi, P.crimson, P.navy3];
    stripes.forEach((c, i) => { ctx.fillStyle = c; ctx.beginPath(); ctx.moveTo(-60 + i * 24, 0); ctx.lineTo(-60 + (i + 1) * 24, 0); ctx.lineTo(-60 + (i + 1) * 24 + sway, -260); ctx.lineTo(-60 + i * 24 + sway, -260); ctx.closePath(); ctx.fill(); });
    ctx.restore();
  }
  T.draw3d(ctx, cam, [{ parts: MEDAL, pos: [0, y, 0], rot: [0.12, lu * 0.75 + 0.4, 0.05 * Math.sin(lu)] }],
    { dir: [0.2, 1, -0.5], ambient: 0.28, diffuse: 0.9 });
  // glint on the crash at u67
  const gl = bump(u, 67.05, 0.6);
  const mp = cam.project([0.55, y + 0.5, -0.2]);
  if (gl > 0 && mp) {
    ctx.save(); ctx.globalCompositeOperation = 'lighter'; ctx.fillStyle = `rgba(255,245,210,${gl})`;
    ctx.beginPath(); ctx.moveTo(mp[0], mp[1] - 120 * gl); ctx.lineTo(mp[0] + 8, mp[1]); ctx.lineTo(mp[0], mp[1] + 120 * gl); ctx.lineTo(mp[0] - 8, mp[1]); ctx.closePath(); ctx.fill();
    ctx.beginPath(); ctx.moveTo(mp[0] - 120 * gl, mp[1]); ctx.lineTo(mp[0], mp[1] + 8); ctx.lineTo(mp[0] + 120 * gl, mp[1]); ctx.lineTo(mp[0], mp[1] - 8); ctx.closePath(); ctx.fill();
    ctx.restore();
  }
  spaced(ctx, 'FOR THOSE WHO GAVE ALL', W / 2, 960, 40, DISPLAY, 600, P.ivory, 0.45, 'center', 0.8 * E.outCubic(prog(u, 64.6, 66)));
}

// S11 (68..76): impact. Ranks salute before a crimson sun; banners rise.
function sSalute(ctx, u, t) {
  const lu = u - 68;
  vgrad(ctx, [[0, P.goldHi], [0.6, P.gold], [1, '#B07A2A']]);
  const sunR = 470 + 10 * cue('kick', t);
  decoSun(ctx, W / 2, 760, sunR, P.crimson, P.gold);
  ctx.save();
  M.shake(ctx, u, Math.floor(u), 5 * cue('snare', t), 7);
  ctx.fillStyle = P.ink; ctx.fillRect(-20, 850, W + 40, 300);
  // banners rising between the ranks
  for (let i = 0; i < 5; i++) {
    const x = 220 + i * 370, up = springU(u, 68.5 + i * 0.25, SPRING.gentle);
    const py = 860 - up * 470;
    ctx.strokeStyle = P.ink; ctx.lineWidth = 7; ctx.beginPath(); ctx.moveTo(x, 860); ctx.lineTo(x, py); ctx.stroke();
    if (up > 0.05) Hd.flag(ctx, x + 2, py + 4, 230, 130, t + i * 0.4, 0.8);
  }
  const marching = u >= 72;
  for (let i = 0; i < 22; i++) {
    const x = 40 + i * 88 + (marching ? (u - 72) * 18 : 0);
    Hd.soldier(ctx, x, 860, 260, marching ? u / 2 : 0, P.ink, marching ? 'march' : 'salute', 1);
  }
  ctx.restore();
  // shockwave from the medal's impact
  const sw = prog(u, 68, 69.4);
  if (sw > 0 && sw < 1) {
    ctx.save(); ctx.strokeStyle = `rgba(255,248,230,${1 - sw})`; ctx.lineWidth = 40 * (1 - sw);
    ctx.beginPath(); ctx.arc(W / 2, 640, 80 + sw * 1400, 0, TAU); ctx.stroke(); ctx.restore();
  }
  const fl = 1 - prog(u, 68, 68.6);
  if (fl > 0) { ctx.save(); ctx.globalAlpha = fl; ctx.fillStyle = P.ivory; ctx.fillRect(0, 0, W, H); ctx.restore(); }
  slam(ctx, 'WE REMEMBER', W / 2, 250, 170, UI, 700, P.ink, u, 68.5, { u1: 71.6, outLen: 0.35, outDir: -1, track: 0.03 });
  slam(ctx, 'WE ADVANCE', W / 2, 250, 170, UI, 700, P.crimsonLo, u, 72, { track: 0.03 });
  void lu;
}

// S12 (76..80): band out. The crown alone, turning, rising; light gathers.
function sCrownDark(ctx, u, t) {
  ctx.fillStyle = P.ink; ctx.fillRect(0, 0, W, H);
  const lu = u - 76;
  const gather = E.inCubic(prog(u, 76, 80));
  // converging light lines
  ctx.save(); ctx.globalCompositeOperation = 'lighter';
  for (let i = 0; i < 48; i++) {
    const a = (i / 48) * TAU + 0.1 * hash01(i, 61);
    const r0 = 1300 * (1 - gather) + 140, r1 = r0 + 300 + 200 * hash01(i, 62);
    ctx.strokeStyle = `rgba(246,222,154,${0.12 + 0.4 * gather})`; ctx.lineWidth = 1.5;
    ctx.beginPath(); ctx.moveTo(W / 2 + Math.cos(a) * r0, 470 + Math.sin(a) * r0); ctx.lineTo(W / 2 + Math.cos(a) * r1, 470 + Math.sin(a) * r1); ctx.stroke();
  }
  ctx.restore();
  glowDisc(ctx, W / 2, 470, 420, 'rgba(217,174,82,0.5)', 0.3 + 0.7 * gather);
  const cam = T.camera({ pos: [0, 1.3, -6.2], target: [0, 0.55, 0], fov: 40, W, H });
  const y = lerp(-1.2, 0.0, E.outCubic(prog(u, 76, 79.5)));
  T.draw3d(ctx, cam, [{ parts: CROWN3D, pos: [0, y, 0], rot: [0, lu * 0.55, 0] }],
    { dir: [0.5, 0.9, -0.6], ambient: 0.3, diffuse: 0.85, edgeAlpha: 0.5 });
  typeOn(ctx, 'LONG LIVE', W / 2, 930, 120, DISPLAY, 800, P.ivory, u, 76.4, 0.38, 0.14);
}

// S13 (80..88): final chorus. Coronation: crown lands, sunburst, gold leaf.
function sCoronation(ctx, u, t) {
  const loud = cue('loud', t), kick = cue('kick', t);
  const lu = u - 80;
  vgrad(ctx, [[0, P.crimsonLo], [0.5, P.crimson], [1, P.crimsonLo]]);
  ctx.save(); ctx.globalAlpha = 0.55 + 0.35 * loud;
  Hd.rays(ctx, W / 2, 470, 40, -u * 0.03, null, P.gold);
  ctx.restore();
  const boom = Math.exp(-lu * 1.6);
  Hd.guilloche(ctx, { cx: W / 2, cy: 470, R: 360 + 260 * (1 - boom), A: 30 + 70 * boom + 15 * kick, B: 10, n: 16, m: 6, lines: 22, phase: u * 0.06, color: P.goldHi, width: 1.4, alpha: 0.85 });
  Hd.guilloche(ctx, { cx: W / 2, cy: 470, R: 520 + 160 * (1 - boom), A: 20 + 50 * boom, B: 8, n: 28, m: 5, lines: 14, phase: -u * 0.05, color: P.gold, width: 1, alpha: 0.6 });
  const pull = 1.12 - 0.22 * E.inOutCubic(prog(u, 84, 86));
  ctx.save(); M.zoomAbout(ctx, pull + 0.015 * kick, W / 2, 470);
  M.shake(ctx, u, 80, 16, 9, 0.4);
  Hd.crest(ctx, W / 2, 455, 0.98, { crown: springU(u, 79.85, SPRING.snappy) }, {});
  ctx.restore();
  // u84: the camera pulls back to reveal an honour guard raising sabres toward the crest
  const hg = E.outCubic(prog(u, 84, 85.5));
  if (hg > 0) {
    ctx.save();
    for (const side of [-1, 1]) {
      for (let i = 0; i < 4; i++) {
        const x = W / 2 + side * (520 + i * 150), h = 330 - i * 30, y = H + 20 + (1 - hg) * 300;
        ctx.save(); ctx.translate(x, y); ctx.scale(-side, 1);
        Hd.soldier(ctx, 0, 0, h, 0, P.ink, 'saber', 1);
        ctx.restore();
        const raise = springU(u, 84.5 + i * 0.25, SPRING.bouncy);
        const hx = x - side * h * 0.15, hy = y - h * 0.9;
        const a = -Math.PI / 2 - side * lerp(0.2, 0.75, raise);
        Hd.saber(ctx, hx, hy, h * 1.05, a, P.ivory, P.gold);
      }
    }
    ctx.restore();
  }
  // gold leaf burst from the impact
  for (const L of LEAVES) {
    const tt = (u - 80 - L.d) * 0.42256;
    if (tt <= 0 || tt > 3) continue;
    const x = W / 2 + Math.cos(L.a) * L.v * tt * Math.exp(-tt * 0.6);
    const y = 470 + Math.sin(L.a) * L.v * tt * Math.exp(-tt * 0.6) + 260 * tt * tt;
    ctx.save(); ctx.translate(x, y); ctx.rotate(L.spin * tt); ctx.scale(1, Math.cos(L.spin * tt * 1.3));
    ctx.globalAlpha = clamp(3 - tt);
    ctx.fillStyle = L.c; ctx.beginPath(); ctx.moveTo(0, -L.s); ctx.lineTo(L.s * 0.55, 0); ctx.lineTo(0, L.s); ctx.lineTo(-L.s * 0.55, 0); ctx.closePath(); ctx.fill();
    ctx.restore();
  }
  const fl = Math.exp(-lu * 5);
  if (lu >= 0) { ctx.save(); ctx.globalAlpha = fl; ctx.fillStyle = P.goldHi; ctx.fillRect(0, 0, W, H); ctx.restore(); }
  spaced(ctx, 'LONG LIVE', W / 2, 838, 46, DISPLAY, 700, P.ivory, 0.5, 'center', 1);
  slam(ctx, 'THE CROWN', W / 2, 1000, 136, DISPLAY, 900, P.goldHi, u, 80.02, { track: 0.08, shadow: P.crimsonLo, from: 1.4 });
}

// S14 (88..98): the balcony. Palace, sovereign, a sea of flags, star fireworks.
function sBalcony(ctx, u, t) {
  const lu = u - 88;
  vgrad(ctx, [[0, P.ink], [0.5, P.navy2], [0.8, '#6B2A3A'], [1, '#C2563A']]);
  // fireworks: star-shaped bursts on the grid (behind the palace)
  const bursts = [[88.0, 520, 220, P.goldHi], [90.0, 1420, 190, P.ivory], [92.0, 760, 150, P.crimsonHi], [93.0, 1180, 240, P.goldHi], [94.0, 360, 260, P.gold], [96.0, 1580, 230, P.goldHi], [97.0, 960, 120, P.ivory]];
  ctx.save(); ctx.globalCompositeOperation = 'lighter';
  for (const [b0, bx, by, col] of bursts) {
    const tt = (u - b0) * 0.42256;
    if (tt < 0 || tt > 2.2) continue;
    const R = 260 * (1 - Math.exp(-tt * 3.2));
    for (let k = 0; k < 16; k++) {
      const a = (k / 16) * TAU, long = k % 2 === 0 ? 1 : 0.55;
      for (let j = 0; j < 6; j++) {
        const rr = R * long * (1 - j * 0.07), x = bx + Math.cos(a) * rr, y = by + Math.sin(a) * rr + 60 * tt * tt;
        ctx.globalAlpha = clamp(1.6 - tt) * (1 - j / 6);
        ctx.fillStyle = col; ctx.beginPath(); ctx.arc(x, y, 3.5 - j * 0.4, 0, TAU); ctx.fill();
      }
    }
  }
  ctx.restore();
  const z = 1.08 + 0.1 * E.inOutSine(prog(u, 88, 98));
  ctx.save(); M.zoomAbout(ctx, z, W / 2, 640);
  // palace: stepped deco tower and wings
  ctx.fillStyle = P.ink;
  const base = 760;
  ctx.fillRect(260, base - 260, 1400, 360);
  ctx.fillRect(560, base - 400, 800, 140);
  ctx.fillRect(760, base - 540, 400, 160);
  ctx.fillRect(880, base - 660, 160, 140);
  ctx.beginPath(); ctx.moveTo(900, base - 660); ctx.lineTo(960, base - 760); ctx.lineTo(1020, base - 660); ctx.closePath(); ctx.fill();
  ctx.fillStyle = P.goldLo;
  ctx.fillRect(260, base - 262, 1400, 5); ctx.fillRect(560, base - 402, 800, 5); ctx.fillRect(760, base - 542, 400, 5); ctx.fillRect(880, base - 662, 160, 5);
  for (let i = 0; i < 9; i++) ctx.fillRect(590 + i * 92, base - 395, 6, 130);
  // window lights
  for (let r = 0; r < 4; r++) for (let c = 0; c < 22; c++) {
    const x = 300 + c * 62, y = base - 230 + r * 60;
    if (x > 850 && x < 1070 && r < 2) continue;
    const on = hash01(r * 50 + c, 71) < 0.7;
    ctx.fillStyle = on ? `rgba(246,222,154,${0.55 + 0.3 * hash01(r * 50 + c, 72)})` : '#14203A';
    ctx.fillRect(x, y, 22, 34);
  }
  // giant hanging banners
  for (const bx of [640, 1280]) {
    const sw = Math.sin(t * 1.3 + bx) * 6;
    ctx.fillStyle = P.crimson;
    ctx.beginPath(); ctx.moveTo(bx - 70, base - 390); ctx.lineTo(bx + 70, base - 390); ctx.lineTo(bx + 70 + sw, base - 60); ctx.lineTo(bx + sw, base - 20); ctx.lineTo(bx - 70 + sw, base - 60); ctx.closePath(); ctx.fill();
    Hd.star8(ctx, bx + sw * 0.4, base - 250, 50, 19, 0, P.goldHi, P.gold);
    ctx.fillStyle = P.gold; ctx.fillRect(bx - 74, base - 396, 148, 10);
  }
  // balcony + sovereign
  ctx.fillStyle = '#1A0E10'; ctx.fillRect(850, base - 250, 220, 120);
  glowDisc(ctx, 960, base - 200, 220, 'rgba(255,220,150,0.7)', 0.8);
  ctx.fillStyle = P.ink;
  ctx.beginPath(); ctx.moveTo(925, base - 130); ctx.lineTo(940, base - 205); ctx.lineTo(980, base - 205); ctx.lineTo(995, base - 130); ctx.closePath(); ctx.fill();
  ctx.beginPath(); ctx.arc(960, base - 218, 14, 0, TAU); ctx.fill();
  ctx.fillStyle = P.crimsonLo; ctx.beginPath(); ctx.moveTo(938, base - 200); ctx.lineTo(905, base - 128); ctx.lineTo(1015, base - 128); ctx.lineTo(982, base - 200); ctx.closePath(); ctx.fill();
  Hd.crown2d(ctx, 960, base - 228, 30);
  // arm raised in greeting on the downbeats
  const wave = Math.sin((u - 88) * Math.PI / 2) * 0.3;
  ctx.strokeStyle = P.ink; ctx.lineWidth = 7; ctx.lineCap = 'round';
  ctx.beginPath(); ctx.moveTo(975, base - 198); ctx.lineTo(1000 + wave * 20, base - 240); ctx.stroke();
  ctx.fillStyle = '#2A1A1A'; ctx.fillRect(840, base - 140, 240, 16);
  ctx.restore();
  // the crowd: tiny flags in perspective, waving on the beat
  const cam = T.camera({ pos: [0, 4.2, -4], target: [0, 2.2, 30], fov: 55, W, H });
  const beatWave = 0.5 + 0.5 * Math.cos(u * Math.PI);
  for (let i = CROWD.length - 1; i >= 0; i--) {
    const c = CROWD[i];
    if (c.z < 11) continue;
    const pr = cam.project([c.x, 0.6, c.z]);
    if (!pr || pr[1] < 600) continue;
    const s = Math.min(34, 420 / pr[2]);
    const flick = Math.sin(t * 6 + c.ph) * 0.4 + beatWave * 0.6;
    ctx.fillStyle = c.c < 0.5 ? P.crimson : c.c < 0.8 ? P.navy3 : P.gold;
    ctx.beginPath(); ctx.moveTo(pr[0], pr[1] - s * (1.2 + 0.25 * flick)); ctx.lineTo(pr[0] + s * 1.0, pr[1] - s * (0.95 + 0.4 * flick)); ctx.lineTo(pr[0], pr[1] - s * 0.6); ctx.closePath(); ctx.fill();
    ctx.fillStyle = P.ink; ctx.fillRect(pr[0] - s * 0.35, pr[1] - s * 0.6, s * 0.7, s * 0.9);
  }
  slam(ctx, 'THE PEOPLE REJOICE', W / 2, 140, 64, UI, 600, P.goldHi, u, 90, { track: 0.4, from: 0.4 });
  void lu;
}

// S15 (98..110): the ascent up the triumphal arch, cranes with the belted peak.
function sAscent(ctx, u, t) {
  const pitch = Math.max(0, cue('pitch', t)), vocal = cue('vocal', t), kick = cue('kick', t);
  const lu = u - 98;
  const crane = E.inOutSine(prog(u, 98, 110)) * 900 + pitch * 40;
  vgrad(ctx, [[0, P.gold], [0.5, P.goldHi], [1, P.ivory]]);
  ctx.save(); ctx.globalAlpha = 0.35 + 0.3 * vocal + 0.2 * kick;
  Hd.rays(ctx, W / 2, 420, 44, u * 0.02, null, '#FFFFFF');
  ctx.restore();
  ctx.save(); ctx.translate(0, crane);
  // the arch (in world: grows upward off-frame)
  ctx.fillStyle = P.ink;
  const ax = W / 2, aw = 1500, top = -360, bot = H + 600;
  ctx.beginPath(); ctx.rect(ax - aw / 2, top, aw, bot - top);
  ctx.moveTo(ax + 300, bot); ctx.lineTo(ax + 300, 520); ctx.arc(ax, 520, 300, 0, Math.PI, true); ctx.lineTo(ax - 300, bot); ctx.closePath();
  ctx.fill('evenodd');
  // relief bands + columns
  ctx.fillStyle = P.goldLo;
  for (const x of [-640, -440, 440, 640]) ctx.fillRect(ax + x - 18, top + 260, 36, bot - top);
  ctx.fillStyle = P.gold; ctx.fillRect(ax - aw / 2, top + 220, aw, 16); ctx.fillRect(ax - aw / 2, top - 10, aw, 16);
  // crest relief at the top
  Hd.crest(ctx, ax, top + 40, 0.62, {}, { motto: false });
  // banners down the piers
  for (const bx of [-560, 560]) {
    ctx.fillStyle = P.crimson; ctx.fillRect(ax + bx - 50, top + 300, 100, 520);
    Hd.star8(ctx, ax + bx, top + 420, 38, 14, 0, P.goldHi, P.gold);
  }
  ctx.restore();
  const words = [['ONE CROWN', 100], ['ONE BANNER', 104], ['ONE FEDERATION', 108]];
  for (const [w, u0] of words) {
    slam(ctx, w, W / 2, 990, w.length > 10 ? 110 : 130, DISPLAY, 900, P.goldHi, u, u0, { u1: u0 === 108 ? undefined : u0 + 3.8, outLen: 0.2, outDir: u0 === 100 ? -1 : 1, track: 0.06, plate: P.crimson, shadow: P.crimsonLo });
  }
  void lu;
}

// S16 (110..120): enlistment posters flip in; push into the Fleet poster.
const POSTERS = [
  ['LEGION', P.crimson, P.ink, 'soldier'], ['FLEET', P.navy2, P.goldHi, 'ship'], ['AIR WING', P.gold, P.ink, 'plane'],
  ['ROYAL GUARD', P.navy2, P.goldHi, 'guard'], ['ENGINEERS', P.gold, P.ink, 'gear'], ['CITIZENS', P.crimson, P.ink, 'wheat'],
];
function poster(ctx, i, x, y, w, h, u, t) {
  const [label, bg, fg, icon] = POSTERS[i];
  ctx.save(); ctx.beginPath(); ctx.rect(x, y, w, h); ctx.clip();
  ctx.fillStyle = bg; ctx.fillRect(x, y, w, h);
  ctx.globalAlpha = 0.18; Hd.rays(ctx, x + w / 2, y + h * 0.55, 24, u * 0.03 * (i % 2 ? 1 : -1), null, fg === P.ink ? P.ivory : P.gold); ctx.globalAlpha = 1;
  const cx = x + w / 2, cy = y + h * 0.56;
  if (icon === 'soldier') Hd.soldier(ctx, cx - 10, cy + h * 0.3, h * 0.58, u / 2, fg, 'march');
  if (icon === 'ship') Hd.shipIcon(ctx, cx, cy + 20, w * 0.7, fg);
  if (icon === 'plane') Hd.planeIcon(ctx, cx, cy, h * 0.5, fg);
  if (icon === 'guard') Hd.guardIcon(ctx, cx, cy + h * 0.3, h * 0.5, fg);
  if (icon === 'gear') Hd.gearIcon(ctx, cx, cy, h * 0.22, fg, u * 0.3);
  if (icon === 'wheat') Hd.wheatIcon(ctx, cx, cy + h * 0.28, h * 0.48, fg);
  ctx.font = font(h * 0.14, 700, UI); ctx.letterSpacing = `${h * 0.012}px`; ctx.textAlign = 'center'; ctx.fillStyle = fg;
  ctx.fillText(label, cx, y + h * 0.2); ctx.letterSpacing = '0px';
  ctx.strokeStyle = fg; ctx.lineWidth = 6; ctx.strokeRect(x + 14, y + 14, w - 28, h - 28);
  ctx.restore();
}
function sEnlist(ctx, u, t) {
  ctx.fillStyle = P.ink; ctx.fillRect(0, 0, W, H);
  const pw = 560, ph = 430, gx = (W - pw * 3) / 4, gy = (H - ph * 2) / 3;
  const push = E.inCubic(prog(u, 118, 120));
  ctx.save();
  // push into the FLEET poster (index 1)
  const fx = gx * 2 + pw + pw / 2, fy = gy + ph / 2;
  const z = 1 + push * 2.6;
  ctx.translate(W / 2, H / 2); ctx.scale(z, z); ctx.translate(-lerp(W / 2, fx, push), -lerp(H / 2, fy, push));
  for (let i = 0; i < 6; i++) {
    const c = i % 3, r = Math.floor(i / 3);
    const x = gx + c * (pw + gx), y = gy + r * (ph + gy);
    const k = springU(u, 110 + i * 0.5, SPRING.snappy);
    if (k <= 0) continue;
    const pulse = 1 + 0.025 * cue('kick', t) * (u > 113 ? 1 : 0);
    ctx.save(); ctx.translate(x + pw / 2, y + ph / 2); ctx.scale(Math.min(1.05, k) * pulse, pulse); ctx.translate(-(x + pw / 2), -(y + ph / 2));
    poster(ctx, i, x, y, pw, ph, u, t);
    ctx.restore();
  }
  ctx.restore();
  // band across: ENLIST TODAY
  const b = E.outCubic(prog(u, 114, 114.6)) * (1 - push);
  if (b > 0) {
    ctx.save(); ctx.translate(W / 2, H / 2); ctx.rotate(-0.06);
    ctx.fillStyle = P.crimson; ctx.fillRect(-W * b, -80, W * 2 * b, 160);
    ctx.fillStyle = P.goldHi; ctx.fillRect(-W * b, -80, W * 2 * b, 6); ctx.fillRect(-W * b, 74, W * 2 * b, 6);
    ctx.restore();
    ctx.save(); ctx.translate(W / 2, H / 2); ctx.rotate(-0.06);
    slam(ctx, 'ENLIST TODAY', 0, 46, 130, UI, 700, P.ivory, u, 114.2, { track: 0.12, from: 0.6 });
    ctx.restore();
  }
}

// S17 (120..136): the armada at dusk; flagship close pass, salvos on the snares.
function sArmada(ctx, u, t) {
  const lu = u - 120;
  vgrad(ctx, [[0, P.navy], [0.45, P.navy3], [0.75, '#B4483A'], [1, P.goldHi]]);
  decoSun(ctx, 1500, 900, 230, P.goldHi, '#C86A3A');
  const second = u >= 128;
  const cam = second
    ? T.camera({ pos: [40 + (u - 128) * 1.2, 1.5, 0], target: [0, 9, 60], fov: 44, W, H, roll: 0.06 })
    : T.camera({ pos: [lu * 0.4, 3 + lu * 0.08, -10], target: [lu * 0.4 + 6, 8, 40], fov: 32, W, H, roll: -0.05 + 0.04 * Math.sin(lu * 0.25) });
  if (second) {
    vgrad(ctx, [[0, P.navy2], [0.5, '#8A3A3A'], [0.8, '#E07A3A'], [1, P.goldHi]]);
    decoSun(ctx, 640, 760, 360, P.goldHi, '#E07A3A');
    glowDisc(ctx, 640, 760, 700, 'rgba(255,220,150,0.6)', 0.7);
  }
  const objs = [];
  for (const f of FLEET) {
    const x = f.x + lu * 3.0, z = f.z;
    objs.push({ parts: SHIP, pos: [x, f.y * 0.8 + Math.sin(u * 0.3 + f.ph) * 0.4, z], scale: f.s * 1.25, rot: [0, Math.PI / 2 + 0.25, 0] });
  }
  // flagship close pass
  const fp = prog(u, 122, 135);
  const flag = { parts: SHIP, pos: [lerp(-26, 34, fp), 5.0, 30], scale: 7.5, rot: [0.02, Math.PI / 2 + 0.18, 0.03] };
  objs.push(flag);
  T.draw3d(ctx, cam, objs, second
    ? { dir: [0.2, -0.3, -1], ambient: 0.22, diffuse: 0.5, fog: Hd.rgb('#C86A4A'), fogNear: 60, fogFar: 260, edgeAlpha: 0.9 }
    : { dir: [0.6, 0.8, -0.3], ambient: 0.38, diffuse: 0.8, fog: Hd.rgb('#7A4A5A'), fogNear: 40, fogFar: 200, edgeAlpha: 0.75 });
  // salvos on the snare hits
  const sn = cue('snare', t);
  if (sn > 0.25) {
    for (const off of [-1.6, -0.4, 1.2]) {
      const pr = cam.project(T.add(flag.pos, [off * 3.2, 1.4, -2]));
      if (pr) glowDisc(ctx, pr[0], pr[1], 120 * sn, 'rgba(255,214,140,1)', sn);
    }
  }
  slam(ctx, 'UNBROKEN', 140, 220, 140, UI, 700, P.goldHi, u, 120, { align: 'left', track: 0.04, u1: 127.7, outLen: 0.3 });
  slam(ctx, 'UNBOWED', 140, 220, 140, UI, 700, P.goldHi, u, 128, { align: 'left', track: 0.04 });
  slam(ctx, 'THE FEDERATION FLEET', 146, 290, 40, UI, 400, P.ivory, u, 121, { align: 'left', track: 0.4, from: 0.3 });
  // dissolve to gold at the end (into the portrait)
  const g = E.inCubic(prog(u, 135, 136));
  if (g > 0) { ctx.save(); ctx.globalAlpha = g; ctx.fillStyle = P.gold; ctx.fillRect(0, 0, W, H); ctx.restore(); }
}

// S18 (136..140): dropout + held note. The portrait in gold light.
function sPortrait(ctx, u, t) {
  const vocal = cue('vocal', t);
  const lu = u - 136;
  vgrad(ctx, [[0, P.goldHi], [1, P.gold]]);
  const swell = clamp(lu / 4) * 0.6 + vocal * 0.4;
  ctx.save(); ctx.globalAlpha = 0.25 + 0.4 * swell;
  Hd.rays(ctx, 1050, 470, 60, u * 0.01, null, '#FFFFFF');
  ctx.restore();
  const z = 1 + 0.05 * lu / 4;
  ctx.save(); M.zoomAbout(ctx, z, 1000, 560);
  Hd.sovereign(ctx, 590, 150, 930, { ink: P.bronze, light: P.goldHi, glow: swell * 0.6, lineGap: 7 });
  ctx.restore();
  glowDisc(ctx, 1050, 420, 520, 'rgba(255,250,230,0.8)', swell * 0.45);
}

// S19 (140..152): return. Insignia stamp in on every beat.
const INSIG = ['wings', 'chevrons', 'anchor', 'tower', 'sabers', 'crown'];
function sInsignia(ctx, u, t) {
  const b = Math.max(0, Math.floor(u - 140 + 0.12));
  const lu = u - 140 - b;
  const bgs = [[P.crimson, P.crimsonLo], [P.navy2, P.navy], [P.gold, P.goldLo]];
  const [c0, c1] = bgs[b % 3];
  ctx.fillStyle = c1; ctx.fillRect(0, 0, W, H);
  Hd.rays(ctx, W / 2, 500, 32, u * 0.05 + b, null, c0);
  Hd.guilloche(ctx, { cx: W / 2, cy: 500, R: 380, A: 24 + 20 * cue('kick', t), B: 9, n: 18, m: 5, lines: 16, phase: u * 0.1, color: b % 3 === 2 ? P.navy : P.gold, width: 1.2, alpha: 0.6 });
  const k = springU(u, 140 + b - 0.12, SPRING.bouncy);
  const s = 1.6 - 0.6 * Math.min(1.1, k);
  const fg = b % 3 === 2 ? P.ink : P.goldHi, dk = b % 3 === 2 ? P.navy2 : P.gold;
  ctx.save(); ctx.globalAlpha = clamp(k * 3);
  Hd.insignia(ctx, INSIG[b % INSIG.length], W / 2, 500, 1.5 * s, fg, dk);
  ctx.restore();
  const words = [['VALOR', 140], ['DUTY', 144], ['GLORY', 148]];
  for (const [w, u0] of words) if (u >= u0 && u < u0 + 4) slam(ctx, w, W / 2, 1000, 120, UI, 700, b % 3 === 2 ? P.ink : P.ivory, u, u0, { track: 0.3, from: 0.5 });
  void lu;
}

// S20 (152..156): the last hit. The decree is sealed.
function sSeal(ctx, u, t) {
  ctx.drawImage(PAPER, 0, 0);
  Hd.guilloche(ctx, { cx: W / 2, cy: 440, R: 380, A: 18, B: 6, n: 20, m: 5, lines: 18, phase: u * 0.02, color: P.gold, width: 1, alpha: 0.7 });
  Hd.crest(ctx, W / 2, 430, 0.72, {}, {});
  // decree lines (abstract, unreadable)
  ctx.fillStyle = 'rgba(19,37,75,0.35)';
  for (let i = 0; i < 5; i++) { const w = 900 - (i === 4 ? 400 : 60 * hash01(i, 81)); ctx.fillRect(W / 2 - 450, 760 + i * 34, w, 10); }
  const k = springU(u, 151.85, SPRING.snappy);
  if (k > 0) {
    const sq = 0.18 * M.wobble(u - 152, 2.4, 5);
    const y = lerp(-300, 900, Math.min(1, k));
    Hd.waxSeal(ctx, 1380, y, 120, 4, sq);
    const r = prog(u, 152, 153.2);
    if (r > 0 && r < 1) { ctx.strokeStyle = `rgba(176,24,42,${1 - r})`; ctx.lineWidth = 10 * (1 - r); ctx.beginPath(); ctx.arc(1380, 900, 130 + r * 300, 0, TAU); ctx.stroke(); }
  }
  slam(ctx, 'SEALED BY THE CROWN', 1380, 1060, 30, UI, 500, P.crimson, u, 152.5, { track: 0.35, from: 0.3 });
}

// S21 (156..164): end card.
function sEnd(ctx, u, t) {
  vgrad(ctx, [[0, P.navy], [1, P.ink]]);
  Hd.guilloche(ctx, { cx: W / 2, cy: 400, R: 300, A: 20, B: 8, n: 14, m: 5, lines: 20, phase: u * 0.03, color: P.goldLo, width: 1, alpha: 0.6 });
  const k = E.outCubic(prog(u, 156, 157.5));
  ctx.save(); ctx.globalAlpha = k;
  Hd.crest(ctx, W / 2, 420, 0.62, {}, {});
  ctx.restore();
  typeOn(ctx, 'LONG LIVE THE FEDERATION', W / 2, 860, 76, DISPLAY, 800, P.goldHi, u, 156.3, 0.08, 0.1);
  spaced(ctx, 'MUSIC  ·  SKILLET  —  HERO', W / 2, 960, 24, UI, 400, P.ivory, 0.4, 'center', 0.7 * E.outCubic(prog(u, 158, 159)));
  const out = prog(u, 162.6, 163.9);
  if (out > 0) { ctx.save(); ctx.globalAlpha = out; ctx.fillStyle = '#000'; ctx.fillRect(0, 0, W, H); ctx.restore(); }
}

// ---------------------------------------------------------------- timeline
const SCENES = [
  [-99, 8, sForge], [8, 16, sSovereign], [16, 32, sBearer], [32, 40, sLegionFront], [40, 48, sLegionSide],
  [48, 60, sFleet], [60, 64, sRealm], [64, 68, sMemorial], [68, 76, sSalute], [76, 80, sCrownDark],
  [80, 88, sCoronation], [88, 98, sBalcony], [98, 110, sAscent], [110, 120, sEnlist], [120, 136, sArmada],
  [136, 140, sPortrait], [140, 152, sInsignia], [152, 156, sSeal], [156, 999, sEnd],
];

function post(ctx, u, t) {
  // crash cymbals flash gold (the song's own accents), kept gentle
  const cr = cue('crash', t);
  if (cr > 0.05 && !(u >= 64 && u < 68)) {
    ctx.save(); ctx.globalCompositeOperation = 'lighter'; ctx.globalAlpha = cr * 0.16;
    ctx.fillStyle = P.goldHi; ctx.fillRect(0, 0, W, H); ctx.restore();
  }
  ctx.drawImage(VIGNETTE, 0, 0);
  const g = GRAIN[Math.floor(t * 24) % GRAIN.length];
  ctx.save(); ctx.globalAlpha = 0.07; ctx.globalCompositeOperation = 'overlay';
  ctx.drawImage(g, 0, 0, W, H); ctx.restore();
}

M.film({
  fonts: [font(100, 800, DISPLAY), font(100, 900, DISPLAY), font(100, 600, DISPLAY), font(40, 700, UI), font(40, 500, UI), font(40, 400, UI)],
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
