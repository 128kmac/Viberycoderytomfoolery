// MURDERS: a paper theatre. Music video for Miracle Musical's "Murders" (audio unchanged).
// Pure function of time: window.seek(t) paints frame t (lib/motion.js). Scenes are placed in seconds on
// the song's measured structure (analysis/excerpt.json); accents come from the measured drum hits,
// impacts and dropouts, and per-frame envelopes in analysis/cues.json. docs/shotlist.md is the plan.

import * as M from './lib/motion.js';
import * as P from './lib/paper.js';

const { W, H, E, TAU, clamp, lerp, prog, bump, springU, SPRING, font, hash01, noise1 } = M;
const C = P.C;
const DISPLAY = 'Display', UI = 'UI';

// ---------------------------------------------------------------- the song's data
let CUE = null, EX = null;
let IMPACTS = [], DROPS = [], CRASH = [], KICKS = [], SNARES = [];
function cue(name, t) {
  if (!CUE || !CUE[name]) return 0;
  const a = CUE[name], f = t * CUE.fps, i = Math.floor(f);
  if (i < 0) return a[0];
  if (i >= a.length - 1) return a[a.length - 1];
  return a[i] + (a[i + 1] - a[i]) * (f - i);
}
const within = (list, a, b) => list.filter((x) => x >= a && x < b);
// time since the most recent event in list at or before t (Infinity if none)
function since(list, t, a = -1e9) { let best = Infinity; for (const x of list) if (x <= t && x >= a) best = Math.min(best, t - x); return best; }

// Section boundaries measured by tools/song-analyzer (seconds).
const T = {
  s1: 6.81, s2: 20.14, find: 21.81, s3: 25.14, ring: 30.14, run: 33.48, s4: 38.48, s4peak: 56.81, s5: 58.48, burn: 65.14,
  s6: 68.47, board: 76.81, s7: 83.47, gallery: 98.14, crack: 102.61, s8: 103.47, s9: 120.14, lift: 139.25, s10: 141.81,
  s11: 160.14, s12: 161.81, s13: 181.81, s14: 190.14, s15: 199.72, moon: 205.14, s16: 211.81, end: 221.0,
};

// Scene accents are driven by measured events (IMPACTS, DROPS, CRASH, KICKS) rather than a beat list.
const HITS = [];

// ---------------------------------------------------------------- layers (pre-rendered, seeded)
const L = {};
let GRAIN = [], VIG = null, STARS = [];
function build() {
  L.far = P.forestLayer(3840, 820, 101, { color: '#283070', count: 30, minH: 240, maxH: 500, ground: 0.08, shadow: 0.25 });
  L.mid = P.forestLayer(3840, 920, 202, { color: '#1A1F4E', count: 22, minH: 380, maxH: 720, ground: 0.1 });
  L.near = P.forestLayer(3840, 1040, 303, { color: '#0F1230', count: 13, minH: 560, maxH: 980, ground: 0.1 });
  L.fg = P.forestLayer(3840, 1200, 404, { color: '#04040A', count: 5, minH: 1050, maxH: 1300, ground: 0.03, kind: 'bare', shadow: 0.6 });
  L.sfar = P.forestLayer(3840, 820, 505, { color: '#D2B285', count: 30, minH: 240, maxH: 500, ground: 0.08, shadow: 0.18, edge: 'rgba(255,245,220,0.35)' });
  L.smid = P.forestLayer(3840, 920, 606, { color: '#B38D60', count: 22, minH: 380, maxH: 720, ground: 0.1, shadow: 0.22, edge: 'rgba(255,240,210,0.3)' });
  L.snear = P.forestLayer(3840, 1040, 707, { color: '#7E5E3C', count: 13, minH: 560, maxH: 980, ground: 0.1, shadow: 0.3, edge: 'rgba(255,230,200,0.25)' });
  for (let g = 0; g < 3; g++) GRAIN.push(P.grainCanvas(640, 360, 900 + g));
  VIG = document.createElement('canvas'); VIG.width = W; VIG.height = H;
  const v = VIG.getContext('2d');
  const gr = v.createRadialGradient(W / 2, H / 2, H * 0.3, W / 2, H / 2, H * 1.0);
  gr.addColorStop(0, 'rgba(0,0,0,0)'); gr.addColorStop(1, 'rgba(0,0,0,0.7)');
  v.fillStyle = gr; v.fillRect(0, 0, W, H);
  for (let i = 0; i < 160; i++) STARS.push([hash01(i, 31) * W, hash01(i, 32) * H * 0.55, 0.4 + hash01(i, 33) * 1.4, hash01(i, 34)]);
}

// ---------------------------------------------------------------- drawing helpers
function vgrad(ctx, stops) { const g = ctx.createLinearGradient(0, 0, 0, H); stops.forEach(([o, c]) => g.addColorStop(o, c)); ctx.fillStyle = g; ctx.fillRect(-60, -60, W + 120, H + 120); }
function glow(ctx, x, y, r, col, a = 1) {
  if (a <= 0.003) return;
  ctx.save(); ctx.globalAlpha *= a; ctx.globalCompositeOperation = 'lighter';
  const g = ctx.createRadialGradient(x, y, 0, x, y, r); g.addColorStop(0, col); g.addColorStop(1, 'rgba(0,0,0,0)');
  ctx.fillStyle = g; ctx.fillRect(x - r, y - r, 2 * r, 2 * r); ctx.restore();
}
function dark(ctx, a, col = '#000') { if (a <= 0) return; ctx.save(); ctx.globalAlpha = clamp(a); ctx.fillStyle = col; ctx.fillRect(-60, -60, W + 120, H + 120); ctx.restore(); }
function sky(ctx, t, o = {}) {
  if (o.sepia) vgrad(ctx, [[0, '#F3E3C4'], [0.6, '#E7CDA2'], [1, '#C9A47A']]);
  else vgrad(ctx, [[0, '#05060F'], [0.55, C.indigo], [1, C.dusk]]);
  if (!o.sepia) for (const [x, y, r, ph] of STARS) { ctx.globalAlpha = 0.35 + 0.35 * Math.sin(t * 1.3 + ph * 20); ctx.fillStyle = '#E8EEFF'; ctx.beginPath(); ctx.arc(x, y, r, 0, TAU); ctx.fill(); }
  ctx.globalAlpha = 1;
  const mx = o.moonX ?? 1450, my = o.moonY ?? 230, mr = o.moonR ?? 95;
  glow(ctx, mx, my, mr * 3.2, o.sepia ? 'rgba(255,240,200,0.7)' : 'rgba(170,200,255,0.5)', 1);
  const disc = new Path2D(); disc.arc(mx, my, mr, 0, TAU);
  P.cut(ctx, disc, o.sepia ? '#FFF6E0' : C.moon, { depth: 6, shadow: 0.25, blur: false, edge: 'rgba(255,255,255,0.4)' });
  if (!o.sepia) { ctx.fillStyle = 'rgba(140,160,200,0.25)'; for (const [dx, dy, rr] of [[-0.3, 0.1, 0.2], [0.25, -0.25, 0.12], [0.15, 0.35, 0.1]]) { ctx.beginPath(); ctx.arc(mx + dx * mr, my + dy * mr, rr * mr, 0, TAU); ctx.fill(); } }
}
function layer(ctx, cv, camX, k, y, sc = 1) {
  const w = cv.width * sc;
  let x = -(((camX * k) % w) + w) % w;
  const top = (cv.top || 0) * sc;
  for (; x < W; x += w) ctx.drawImage(cv, x, y - top, w, cv.height * sc);
}
// The forest at night (or in sepia memory). between(i) lets a scene insert owls/props between layers.
function forest(ctx, t, camX, o = {}) {
  sky(ctx, t, o);
  const s = o.sepia;
  layer(ctx, s ? L.sfar : L.far, camX, 0.2, H - 820 + 60);
  if (o.between) o.between(1);
  layer(ctx, s ? L.smid : L.mid, camX, 0.45, H - 920 + 60);
  if (o.between) o.between(2);
  layer(ctx, s ? L.snear : L.near, camX, 0.75, H - 1040 + 40);
  if (o.between) o.between(3);
}
function foreground(ctx, camX, k = 1.25) { layer(ctx, L.fg, camX, k, H - 1200 + 80); }

// Snow caps on the ground and falling snow.
function snowGround(ctx, amt, t) {
  if (amt <= 0) return;
  ctx.save(); ctx.fillStyle = C.snow; ctx.globalAlpha = 0.95;
  ctx.beginPath(); ctx.moveTo(-20, H + 20);
  for (let x = -20; x <= W + 20; x += 30) ctx.lineTo(x, H - 90 * amt - 20 * amt * Math.sin(x * 0.01) - 10 * noise1(x * 0.02, 5) * amt);
  ctx.lineTo(W + 20, H + 20); ctx.closePath(); ctx.fill();
  ctx.restore();
}

function frameZoom(ctx, z, x, y) { ctx.translate(x, y); ctx.scale(z, z); ctx.translate(-x, -y); }

function actCard(ctx, t, t0, num, title) {
  const a = clamp((t - t0) / 0.5) * clamp((t0 + 3.6 - t) / 0.7);
  if (a <= 0) return;
  ctx.save(); ctx.globalAlpha = a;
  const y = 980 - (1 - clamp((t - t0) / 0.6)) * 20;
  ctx.font = font(30, 700, DISPLAY); ctx.letterSpacing = '10px'; ctx.textAlign = 'center';
  ctx.fillStyle = 'rgba(0,0,0,0.5)'; ctx.fillText(`${num} · ${title}`, W / 2 + 2, y + 2);
  ctx.fillStyle = C.paper; ctx.fillText(`${num} · ${title}`, W / 2, y);
  ctx.strokeStyle = C.red; ctx.lineWidth = 2; ctx.beginPath(); ctx.moveTo(W / 2 - 60, y + 20); ctx.lineTo(W / 2 + 60, y + 20); ctx.stroke();
  ctx.letterSpacing = '0px'; ctx.restore();
}

// ---------------------------------------------------------------- poses
function walkPose(ph, run = 0, lantern = false) {
  const s = Math.sin(ph * TAU), c = Math.cos(ph * TAU), amp = 0.42 + 0.38 * run;
  return {
    lean: 0.04 + 0.18 * run, head: -0.03 * run,
    legF: [-amp * s, 0.12 + Math.max(0, c) * (0.6 + 0.6 * run)], legB: [amp * s, 0.12 + Math.max(0, -c) * (0.6 + 0.6 * run)],
    armF: lantern ? [-0.55 + 0.08 * s, -0.35] : [0.6 * amp * s - 0.2 * run, -0.3 - 0.9 * run], armB: [-0.6 * amp * s + 0.2 * run, -0.3 - 0.9 * run],
    scarf: 0.3 + 0.9 * run + 0.1 * s, mouth: run > 0.5 ? 'O' : 'line', brows: run > 0.5 ? 1.5 : 0,
  };
}
const PANIC = { armF: [-2.75, -0.75], armB: [2.75, 0.75], mouth: 'O', brows: 2, scarf: 0.5 };
const KNEEL = { legF: [-1.45, 2.65], legB: [0.25, 1.5], armF: [-0.9, -0.2], armB: [-0.5, -0.4], lean: 0.25, head: 0.25, mouth: 'down', brows: 1.5 };
const SIT = { legF: [-1.6, 1.4], legB: [-1.4, 1.5], armF: [-0.4, -1.4], armB: [-0.3, -1.3], lean: 0.32, head: 0.42, mouth: 'down', brows: 1.2 };
function kneelY(h, k) { return h * 0.2 * k; }

// Her face for mirrors and memory: long hair, ribbon, gentle smile.
function herFace(ctx, x, y, r, o = {}) {
  ctx.save(); ctx.translate(x, y); ctx.scale(r / 10, r / 10);
  const hair = new Path2D(); hair.ellipse(0, 1, 11, 13, 0, 0, TAU); hair.rect(-11, 0, 22, 16);
  P.cut(ctx, hair, o.sepia ? '#5A3A22' : C.hair, { depth: 0.8, shadow: 0.3, blur: false });
  P.ribbonBow(ctx, -6, -9, 0.9, 0.2);
  const head = new Path2D(); head.ellipse(0, 0, 8, 9.6, 0, 0, TAU); P.cut(ctx, head, o.sepia ? '#F2D9B0' : C.skin, { depth: 0.8, shadow: 0.3, blur: false });
  const fr = new Path2D(); fr.moveTo(-8, -1); fr.quadraticCurveTo(-3, -13, 8, -3); fr.quadraticCurveTo(1, -7, -8, -1); fr.closePath(); P.cut(ctx, fr, o.sepia ? '#5A3A22' : C.hair, { depth: 0.5, shadow: 0.2, blur: false });
  ctx.fillStyle = '#1B1412'; ctx.strokeStyle = '#1B1412'; ctx.lineWidth = 0.6; ctx.lineCap = 'round';
  ctx.beginPath(); ctx.arc(-3, 0.5, 0.9, 0, TAU); ctx.arc(3, 0.5, 0.9, 0, TAU); ctx.fill();
  ctx.beginPath(); ctx.arc(0, 4.5, 2, 0.25, Math.PI - 0.25); ctx.stroke();
  ctx.fillStyle = 'rgba(220,120,110,0.4)'; ctx.beginPath(); ctx.arc(-5, 3, 1.4, 0, TAU); ctx.arc(5, 3, 1.4, 0, TAU); ctx.fill();
  ctx.restore();
}

// A flying owl seen from below: wings spread, flapping.
// An owl in flight, seen from below: round head with a pale facial disc and gold eyes, broad wings with rounded
// primary feathers (not the pointed, scalloped wings of a bat), a short fanned tail.
function owlFly(ctx, x, y, s, flap, col = '#241B14') {
  ctx.save(); ctx.translate(x, y); ctx.scale(s, s);
  const a = Math.sin(flap * TAU) * 0.55, fold = 0.75 + 0.25 * Math.cos(flap * TAU);
  ctx.fillStyle = col;
  for (const sd of [-1, 1]) {
    ctx.save(); ctx.scale(sd, 1); ctx.translate(6, -6); ctx.rotate(-a); ctx.scale(fold, 1);
    ctx.beginPath(); ctx.moveTo(0, -4); ctx.quadraticCurveTo(30, -30, 62, -12);
    ctx.quadraticCurveTo(74, -10, 68, -3); ctx.quadraticCurveTo(75, 2, 64, 5);
    ctx.quadraticCurveTo(68, 11, 55, 11); ctx.quadraticCurveTo(55, 17, 43, 15);
    ctx.quadraticCurveTo(22, 22, 0, 14); ctx.closePath(); ctx.fill();
    ctx.restore();
  }
  ctx.beginPath(); ctx.moveTo(-7, 18); ctx.lineTo(7, 18); ctx.lineTo(11, 31); ctx.quadraticCurveTo(0, 36, -11, 31); ctx.closePath(); ctx.fill();
  ctx.beginPath(); ctx.ellipse(0, 4, 13, 19, 0, 0, TAU); ctx.fill();
  ctx.beginPath(); ctx.arc(0, -15, 13, 0, TAU); ctx.fill();
  ctx.fillStyle = '#6B5440';
  for (const sd of [-1, 1]) { ctx.beginPath(); ctx.arc(sd * 5, -15, 6.5, 0, TAU); ctx.fill(); }
  ctx.fillStyle = C.owlEye;
  for (const sd of [-1, 1]) { ctx.beginPath(); ctx.arc(sd * 5, -15, 2.8, 0, TAU); ctx.fill(); }
  ctx.fillStyle = '#C9A15A'; ctx.beginPath(); ctx.moveTo(-2, -11); ctx.lineTo(2, -11); ctx.lineTo(0, -6); ctx.closePath(); ctx.fill();
  ctx.restore();
}

function lightning(ctx, x0, y0, x1, y1, seed, a) {
  if (a <= 0) return;
  ctx.save(); ctx.globalAlpha = a;
  const r = M.mulberry32(seed), pts = [[x0, y0]];
  for (let i = 1; i < 9; i++) { const k = i / 9; pts.push([lerp(x0, x1, k) + (r() - 0.5) * 140, lerp(y0, y1, k)]); }
  pts.push([x1, y1]);
  const p = new Path2D(); p.moveTo(pts[0][0] - 12, pts[0][1]);
  pts.forEach(([x, y], i) => p.lineTo(x - 12 + i * 1.2, y)); for (let i = pts.length - 1; i >= 0; i--) p.lineTo(pts[i][0] + 12 - i * 1.2, pts[i][1] + 10);
  p.closePath();
  glow(ctx, x1, (y0 + y1) / 2, 600, 'rgba(200,220,255,0.6)', 1);
  P.cut(ctx, p, '#FFF6D8', { depth: 8, shadow: 0.4, blur: false, edge: '#FFFFFF' });
  ctx.restore();
}

// Paper scraps blown by the storm. Pure: position from (t - t0) and seed.
function scraps(ctx, t, t0, n, wind, a = 1, freeze = null) {
  if (a <= 0) return;
  const cols = [C.paper, C.paperLo, '#283070', '#1A1F4E', C.red, C.gold];
  for (let i = 0; i < n; i++) {
    const tt = freeze ?? (t - t0);
    const sp = 300 + 500 * hash01(i, 61);
    const x = ((hash01(i, 62) * (W + 400) + tt * sp * wind) % (W + 400) + (W + 400)) % (W + 400) - 200;
    const y = ((hash01(i, 63) * (H + 300) + tt * (80 + 160 * hash01(i, 64)) + Math.sin(tt * 2 + i) * 40) % (H + 300)) - 150;
    const sz = 8 + 26 * hash01(i, 65), rot = tt * (3 + 6 * hash01(i, 66)) + i;
    ctx.save(); ctx.globalAlpha = a; ctx.translate(x, y); ctx.rotate(rot); ctx.scale(1, Math.cos(rot * 1.7));
    ctx.fillStyle = cols[i % cols.length];
    ctx.beginPath(); ctx.moveTo(-sz, -sz * 0.6); ctx.lineTo(sz * 0.8, -sz * 0.4); ctx.lineTo(sz, sz * 0.5); ctx.lineTo(-sz * 0.7, sz * 0.6); ctx.closePath(); ctx.fill();
    ctx.restore();
  }
}

// A great red ribbon sweeping through the frame (the final chorus). k grows it from 0..1.
function bigRibbon(ctx, t, k, cx = W / 2, cy = H / 2) {
  if (k <= 0) return;
  const N = 140, pts = [];
  for (let i = 0; i <= N; i++) {
    const s = i / N; if (s > k) break;
    const a = s * TAU * 1.3 + t * 0.6;
    const x = cx - 1100 + s * 2300 + Math.sin(a) * 160;
    const y = cy + Math.sin(s * 5.2 + t * 1.2) * 280 * Math.sin(s * Math.PI) - 60;
    const tw = Math.cos(s * 9 + t * 2.2);
    pts.push([x, y, tw]);
  }
  for (let i = 0; i < pts.length - 1; i++) {
    const [x0, y0, w0] = pts[i], [x1, y1, w1] = pts[i + 1];
    const wd = 46;
    ctx.fillStyle = w0 > 0 ? C.red : C.redLo;
    ctx.beginPath(); ctx.moveTo(x0, y0 - wd * w0); ctx.lineTo(x1, y1 - wd * w1); ctx.lineTo(x1, y1 + wd * w1); ctx.lineTo(x0, y0 + wd * w0); ctx.closePath(); ctx.fill();
  }
}

// ---------------------------------------------------------------- owls in the trees
// [layer, worldX, y, height, seed]
const PERCH = [
  [2, 300, 470, 110, 1], [3, 900, 380, 150, 2], [2, 1500, 430, 120, 3], [3, 2100, 330, 160, 4], [2, 2700, 410, 115, 5],
  [3, 3300, 360, 150, 6], [2, 3900, 450, 110, 7], [3, 4500, 340, 150, 8], [2, 5200, 420, 120, 9], [3, 5900, 370, 155, 10],
];
const KF = [0, 0, 0.45, 0.75];
function perchedOwls(ctx, t, camX, which, eyesFn, o = {}) {
  for (const [ly, wx, y, h, seed] of PERCH) {
    if (ly !== which) continue;
    const span = 3840 / KF[ly] * 0 + 7000;
    const x = ((wx - camX * KF[ly]) % span + span) % span - 300;
    if (x < -200 || x > W + 200) continue;
    const blink = (Math.sin(t * 0.9 + seed * 7) > 0.985) ? 0.1 : 1;
    const e = eyesFn ? eyesFn(x, seed) : 1;
    // a branch to sit on
    ctx.fillStyle = ly === 3 ? '#0F1230' : '#1A1F4E';
    ctx.beginPath(); ctx.moveTo(x - h * 0.9, y + 4); ctx.lineTo(x + h * 0.7, y - 6); ctx.lineTo(x + h * 0.7, y + 6); ctx.lineTo(x - h * 0.9, y + 14); ctx.closePath(); ctx.fill();
    P.owl(ctx, x, y + 2, h, e * blink, o.look ? o.look(x) : 0, { glow: e > 0.5 && o.glow, col: o.col, belly: o.belly, face: o.face, wing: o.wing });
    if (o.snowcap) { ctx.fillStyle = C.snow; ctx.beginPath(); ctx.ellipse(x, y + 2 - h * 0.98, h * 0.28, h * 0.07, 0, Math.PI, 0); ctx.fill(); }
  }
}

// ================================================================= SCENES

// 0: the toy theatre opens; Simon walks in with his lantern.
function sOpen(ctx, t) {
  ctx.fillStyle = '#040308'; ctx.fillRect(0, 0, W, H);
  const camX = t * 40;
  forest(ctx, t, camX, { between: (i) => { if (i === 3) perchedOwls(ctx, t, camX, 3, () => 0.15); } });
  if (t > 3.6) {
    const k = prog(t, 3.6, 6.81);
    P.simon(ctx, lerp(-120, 640, k), 1010, 330, walkPose(t * 1.2, 0, true), { lantern: true });
  }
  const open = E.inOutCubic(prog(t, 1.81, 4.9));
  const inset = lerp(1, 2.1, E.inCubic(prog(t, 4.2, 6.81)));
  P.proscenium(ctx, W, H, open, { t, inset, lights: 0.4 + 0.6 * prog(t, 0, 1.6), crestEyes: prog(t, 0.6, 1.4) });
  // title on the curtain
  const ta = clamp(1 - open * 1.6) * clamp(t / 0.8);
  if (ta > 0) {
    ctx.save(); ctx.globalAlpha = ta;
    ctx.font = font(150, 800, DISPLAY); ctx.letterSpacing = '24px'; ctx.textAlign = 'center';
    ctx.fillStyle = 'rgba(0,0,0,0.5)'; ctx.fillText('MURDERS', W / 2 + 4, 560 + 5);
    ctx.fillStyle = C.goldHi; ctx.fillText('MURDERS', W / 2, 560);
    ctx.font = font(30, 600, DISPLAY); ctx.letterSpacing = '14px'; ctx.fillStyle = C.paper; ctx.fillText('MIRACLE MUSICAL', W / 2, 640);
    ctx.letterSpacing = '0px'; ctx.restore();
  }
}

// 1: the ribbon trail. Ribbons on branches lead him on; owls wake as he passes.
const RIBBONS = [1200, 1850, 2500, 3150, 3800, 4450, 5100];
function sTrail(ctx, t) {
  const lt = t - T.s1;
  const camX = 220 + lt * 150;
  const simX = 640 + Math.sin(lt * 0.3) * 30;
  const simWorld = camX * 0.75 + simX;
  const zk = E.inOutCubic(prog(t, 13.3, 14.3));
  ctx.save(); frameZoom(ctx, lerp(1, 1.5, zk), simX + 40, 760);
  forest(ctx, t, camX, {
    between: (i) => {
      if (i === 2 || i === 3) perchedOwls(ctx, t, camX, i, (x) => clamp((simX + 260 - x) / 220) * 0.9 + 0.1 * cue('kick', t), { glow: true, look: (x) => clamp((simX - x) / 300, -1, 1) });
      if (i === 3) {
        for (const [j, wx] of RIBBONS.entries()) {
          const x = wx - camX * 0.75, y = 470 + 60 * Math.sin(j * 2.1);
          if (x < -80 || x > W + 80) continue;
          ctx.strokeStyle = '#0F1230'; ctx.lineWidth = 10; ctx.beginPath(); ctx.moveTo(x - 140, y - 30); ctx.lineTo(x + 120, y + 10); ctx.stroke();
          P.ribbonBow(ctx, x, y - 6, 4.2, Math.sin(t * 3 + j));
        }
      }
    },
  });
  P.simon(ctx, simX, 1010, 340, walkPose(t * 1.2, 0, true), { lantern: true, lanternSwing: 0.15 * Math.sin(t * 2.4) });
  glow(ctx, simX + 60, 900, 380, 'rgba(255,180,90,0.35)', 1);
  foreground(ctx, camX);
  ctx.restore();
  actCard(ctx, t, T.s1 + 0.4, 'I', 'THE RIBBON');
  void simWorld;
}

// 2: the clearing. He stops (dropout); the moon finds her among white flowers (impact); he kneels.
function sClearing(ctx, t) {
  const camX = 220 + (T.s2 - T.s1) * 150 + Math.min(t - T.s2, 1.2) * 60;
  const reveal = E.outCubic(prog(t, T.find, T.find + 1.2));
  ctx.save(); frameZoom(ctx, lerp(1, 1.5, E.inOutCubic(prog(t, T.find, T.find + 2.6))), 1060, 960);
  forest(ctx, t, camX, { moonX: 1250, between: (i) => { if (i === 3) perchedOwls(ctx, t, camX, 3, () => 0.2 + 0.8 * reveal, { glow: true }); } });
  dark(ctx, 0.5 * (1 - reveal) + 0.05);
  // moonbeam on the clearing
  ctx.save(); ctx.globalCompositeOperation = 'lighter'; ctx.globalAlpha = 0.6 * reveal;
  const g = ctx.createLinearGradient(0, 0, 0, H); g.addColorStop(0, 'rgba(190,210,255,0.35)'); g.addColorStop(1, 'rgba(190,210,255,0.05)');
  ctx.fillStyle = g; ctx.beginPath(); ctx.moveTo(1130, -20); ctx.lineTo(1290, -20); ctx.lineTo(1560, 1080); ctx.lineTo(900, 1080); ctx.closePath(); ctx.fill(); ctx.restore();
  // flowers + her
  for (let i = 0; i < 26; i++) P.flower(ctx, 980 + hash01(i, 71) * 520, 990 + hash01(i, 72) * 60, 12 + 8 * hash01(i, 73), '#F6F2EA', '#E8C35A', hash01(i, 74) * 3);
  ctx.save(); ctx.globalAlpha = 0.25 + 0.75 * reveal;
  P.her(ctx, 1150, 1015, 330, { armF: [-0.4, -0.2], armB: [0.3, 0.2] }, { lying: true, eyesClosed: true });
  ctx.restore();
  for (let i = 0; i < 14; i++) P.flower(ctx, 1000 + hash01(i, 81) * 480, 1040 + hash01(i, 82) * 30, 14, '#FFFFFF', '#E8C35A', hash01(i, 83) * 3);
  // Simon: stops, then walks to her and kneels
  const walk = prog(t, T.find + 0.6, T.find + 2.2), kn = E.inOutCubic(prog(t, T.find + 2.1, T.find + 3.0));
  const sx = lerp(560, 860, E.inOutSine(walk));
  const pose = kn > 0 ? { ...KNEEL } : (walk > 0 && walk < 1 ? walkPose(t * 1.1, 0, true) : { armF: [-0.55, -0.35], head: 0.1, brows: 1, mouth: reveal > 0.5 ? 'O' : 'line' });
  P.simon(ctx, sx, 1010 + kneelY(340, kn), 340, pose, { lantern: true, lanternGlow: 1 });
  glow(ctx, sx + 60, 920, 360, 'rgba(255,180,90,0.32)', 1);
  foreground(ctx, camX);
  ctx.restore();
}

// 3: panic. The lantern drops; mirrors descend on threads and ring him; he runs.
const MIRRORS = [[380, 300], [1540, 330], [720, 220], [1250, 200], [200, 520], [1720, 560], [1000, 160]];
function mirrorsAt(ctx, t, t0, cx, cy, ringK, o = {}) {
  MIRRORS.forEach(([mx, my], i) => {
    const drop = springU(M.U(t), M.U(t0 + i * 0.84), SPRING.bouncy);
    if (drop <= 0) return;
    const ang = (i / MIRRORS.length) * TAU + t * 0.35;
    const rx = cx + Math.cos(ang) * 620, ry = cy - 200 + Math.sin(ang) * 210;
    const x = lerp(mx, rx, ringK), y = lerp(my, ry, ringK) - (1 - drop) * 700;
    const sw = Math.sin(t * 1.4 + i) * 0.08;
    const crack = o.crackAt ? clamp((t - o.crackAt[i % o.crackAt.length]) * 3) : 0;
    P.mirror(ctx, x, y, 130, 180, { swing: sw, thread: 900, crack, seed: i + 3 }, (c, w, h) => {
      if (o.her) herFace(c, 0, 4, 62, { sepia: true });
      else P.face(c, Math.sin(t * 2 + i) * 6, 6, 58, 'fear', { stretch: 1 + 0.25 * Math.sin(t * 1.7 + i * 2), tilt: 0.15 * Math.sin(t + i) });
    });
  });
}
function sPanic(ctx, t) {
  const lt = t - T.s3;
  const run = prog(t, T.run, T.run + 0.8);
  const camX = 220 + (T.s2 - T.s1) * 150 + 72 + Math.max(0, t - T.run) * 520;
  ctx.save();
  const rot = 0.04 * Math.sin(lt * 0.9) * (1 - run * 0.5);
  ctx.translate(W / 2, H / 2); ctx.rotate(rot); ctx.scale(1.06, 1.06); ctx.translate(-W / 2, -H / 2);
  forest(ctx, t, camX, { moonX: 1250, between: (i) => { if (i === 3) perchedOwls(ctx, t, camX, 3, () => 1, { glow: true, look: (x) => clamp((900 - x) / 300, -1, 1) }); } });
  dark(ctx, 0.25);
  // the clearing slides away as he runs
  const off = -Math.max(0, t - T.run) * 520 * 0.75;
  ctx.save(); ctx.translate(off, 0);
  for (let i = 0; i < 26; i++) P.flower(ctx, 980 + hash01(i, 71) * 520, 990 + hash01(i, 72) * 60, 12 + 8 * hash01(i, 73), '#F6F2EA', '#E8C35A', hash01(i, 74) * 3);
  P.her(ctx, 1150, 1015, 300, { armF: [-0.4, -0.2], armB: [0.3, 0.2] }, { lying: true, eyesClosed: true });
  // the dropped lantern, rolling on the ground
  const fall = E.outBounce(prog(t, T.s3, T.s3 + 0.9));
  ctx.save(); ctx.translate(lerp(960, 1010, fall), lerp(880, 1000, fall)); ctx.rotate(fall * 1.7);
  P.lanternAt(ctx, 0, -20, 3, 0.7 * (1 - prog(t, T.s3 + 2, T.s3 + 6)));
  ctx.restore();
  ctx.restore();
  // mirrors
  const ringK = E.inOutCubic(prog(t, T.ring, T.ring + 1.4)) * (1 - prog(t, T.run, T.run + 1.5));
  mirrorsAt(ctx, t, T.s3 + 0.6, 900, 700, ringK);
  // Simon
  const st = E.outCubic(prog(t, T.s3, T.s3 + 0.5));
  const sx = run > 0 ? lerp(860, 760, run) : 860;
  const pose = run > 0 ? walkPose(t * 2.2, 1, false) : { ...PANIC, armF: [lerp(-0.9, PANIC.armF[0], st), PANIC.armF[1]], armB: [lerp(-0.5, PANIC.armB[0], st), PANIC.armB[1]], head: 0.15 * Math.sin(lt * 4) };
  P.simon(ctx, sx, 1010 + kneelY(340, 1 - st), 340, pose, { facing: run > 0 ? 1 : (Math.sin(lt * 1.3) > 0 ? 1 : -1) });
  foreground(ctx, camX, 1.4);
  ctx.restore();
  dark(ctx, bump(t, T.s3, 0.25) * 0.8, '#FFF6E0');
}

// 4: the witnesses. Impacts cut to owls snapping their eyes open; dropouts leave only eyes and his lantern.
function sWitness(ctx, t) {
  const camX = 4000 + (t - T.s4) * 20;
  const imp = within(IMPACTS, T.s4, T.s5), drp = within(DROPS, T.s4 - 0.05, T.s5);
  const sImp = since(imp, t), sDrp = since(drp, t);
  const peak = t >= T.s4peak;
  if (peak) {
    // every eye in the forest opens
    vgrad(ctx, [[0, '#020208'], [1, '#0A0B1C']]);
    layer(ctx, L.mid, camX, 0.45, H - 920 + 60); dark(ctx, 0.5);
    const k = prog(t, T.s4peak, T.s4peak + 1.2);
    for (let i = 0; i < 160; i++) {
      const x = hash01(i, 91) * W, y = hash01(i, 92) * H * 0.85, s = 0.6 + hash01(i, 93) * 1.6;
      const open = clamp((k - hash01(i, 94) * 0.8) * 5);
      if (open <= 0) continue;
      for (const sd of [-1, 1]) { ctx.fillStyle = C.owlEye; ctx.beginPath(); ctx.ellipse(x + sd * 12 * s, y, 7 * s, 7 * s * open, 0, 0, TAU); ctx.fill(); ctx.fillStyle = '#000'; ctx.beginPath(); ctx.arc(x + sd * 12 * s, y, 3 * s * open, 0, TAU); ctx.fill(); }
      glow(ctx, x, y, 40 * s, 'rgba(255,190,80,0.35)', open);
    }
    P.simon(ctx, 960, 1060, 300, { ...PANIC, armF: [-1.2, -1.6], armB: [1.2, 1.6], head: 0.2, mouth: 'O' }, { lantern: false });
    glow(ctx, 960, 960, 300, 'rgba(255,180,90,0.25)', 1);
    return;
  }
  if (sImp < 1.25) {
    // close-up: one owl, eyes snapping open
    const k = imp.indexOf(imp.filter((x) => x <= t).pop());
    vgrad(ctx, [[0, '#06081A'], [1, '#141838']]);
    glow(ctx, W / 2, 380, 700, 'rgba(150,180,255,0.25)', 1);
    const open = E.outBack(clamp(sImp / 0.12), 2);
    ctx.fillStyle = '#0F1230'; ctx.fillRect(0, 900, W, 60);
    P.owl(ctx, W / 2 + (k % 2 ? 260 : -260), 930, 760, open, (k % 2 ? -1 : 1) * 0.8, { glow: true, stern: 1 });
    dark(ctx, Math.max(0, 0.6 - sImp * 3), '#000');
    return;
  }
  // a dropout's darkness holds until the impact that follows it (1.66 s later here), so nothing flashes between
  const lastDrp = t - sDrp, nextImp = imp.find((x) => x > lastDrp);
  if (sDrp < 1.6 || (nextImp !== undefined && nextImp - lastDrp < 2.2 && t < nextImp)) {
    // darkness: only eyes, and his lantern
    ctx.fillStyle = '#010104'; ctx.fillRect(0, 0, W, H);
    for (let i = 0; i < 14; i++) {
      const x = 200 + hash01(i, 95) * 1500, y = 150 + hash01(i, 96) * 500;
      const open = clamp((sDrp - hash01(i, 97) * 0.6) * 4);
      for (const sd of [-1, 1]) { ctx.fillStyle = C.owlEye; ctx.beginPath(); ctx.ellipse(x + sd * 16, y, 9, 9 * open, 0, 0, TAU); ctx.fill(); ctx.fillStyle = '#000'; ctx.beginPath(); ctx.arc(x + sd * 16 + 3, y, 4 * open, 0, TAU); ctx.fill(); }
    }
    glow(ctx, 900, 930, 260, 'rgba(255,170,80,0.55)', 0.8 + 0.2 * Math.sin(t * 9));
    return;
  }
  // between hits: Simon hides behind a trunk; owls on every branch watch
  forest(ctx, t, camX, { moonX: 400, between: (i) => { if (i >= 2) perchedOwls(ctx, t, camX, i, () => 0.6 + 0.4 * cue('kick', t), { glow: true, look: () => 0.8 }); } });
  dark(ctx, 0.35);
  const peek = Math.sin((t - T.s4) * 1.6) * 0.5 + 0.5;
  P.simon(ctx, 1050 + peek * 60, 1010, 340, { armF: [-1.6, -1.2], armB: [-0.6, -0.8], head: -0.2, mouth: 'O', brows: 2, lean: -0.08 }, { facing: 1 });
  const trunk = new Path2D(); trunk.rect(1120, -20, 210, 1120); P.cut(ctx, trunk, '#05050C', { depth: 12, shadow: 0.6, blur: false });
  foreground(ctx, camX, 1.3);
  actCard(ctx, t, T.s4 + 0.3, 'II', 'THE WITNESSES');
}

// 5: memory, in sepia. The two of them dance in the clearing by day; then it burns back into night.
function memoryScene(ctx, t) {
  const lt = t - T.s5;
  const camX = 900 + lt * 25;
  forest(ctx, t, camX, { sepia: true, moonX: 1500, moonY: 220, moonR: 110 });
  for (let i = 0; i < 40; i++) P.flower(ctx, 500 + hash01(i, 101) * 900, 980 + hash01(i, 102) * 80, 12 + 8 * hash01(i, 103), '#FFF8EC', '#E8B04A', hash01(i, 104) * 3);
  // the dance: they circle each other holding hands
  const a = lt * 1.25;
  const r = 120, cx = 960;
  const hx = cx + Math.cos(a) * r, sxx = cx - Math.cos(a) * r;
  const front = Math.sin(a) > 0;
  const drawHer = () => P.her(ctx, hx, 1010 + Math.sin(a) * 10, 300, { armF: [-1.3 - 0.2 * Math.sin(a * 2), -0.3], armB: [0.4, 0.2], legF: [-0.15 * Math.sin(a * 3), 0], legB: [0.15 * Math.sin(a * 3), 0], lean: -0.05 * Math.cos(a) }, { facing: Math.cos(a) > 0 ? -1 : 1, sepia: true });
  const drawHim = () => P.simon(ctx, sxx, 1010 - Math.sin(a) * 10, 330, { armF: [-1.3, -0.3], armB: [0.3, -0.2], legF: [-0.25 * Math.sin(a * 3), 0.2], legB: [0.25 * Math.sin(a * 3), 0.2], mouth: 'line', scarf: 0.6 }, { facing: Math.cos(a) > 0 ? 1 : -1, coat: '#5A4632', coatLo: '#3E3022' });
  if (front) { drawHim(); drawHer(); } else { drawHer(); drawHim(); }
  // petals drifting
  for (let i = 0; i < 30; i++) {
    const x = (hash01(i, 111) * W + lt * 60) % W, y = (hash01(i, 112) * H + lt * 40 + Math.sin(lt + i) * 20) % H;
    ctx.save(); ctx.translate(x, y); ctx.rotate(lt + i); ctx.fillStyle = 'rgba(255,248,236,0.8)'; ctx.beginPath(); ctx.ellipse(0, 0, 6, 3, 0, 0, TAU); ctx.fill(); ctx.restore();
  }
}
function sMemory(ctx, t) {
  const burn = prog(t, T.burn, T.s6 - 0.05);
  if (burn <= 0) { memoryScene(ctx, t); dark(ctx, 1 - prog(t, T.s5, T.s5 + 0.5), '#FFF2D8'); return; }
  // night underneath: the empty clearing
  forest(ctx, t, 2900, { moonX: 1250 });
  dark(ctx, 0.3);
  for (let i = 0; i < 26; i++) P.flower(ctx, 980 + hash01(i, 71) * 520, 990 + hash01(i, 72) * 60, 12 + 8 * hash01(i, 73), '#F6F2EA', '#E8C35A', hash01(i, 74) * 3);
  // the memory, burning from the edges inward
  const R = lerp(1300, 0, E.inQuad(burn));
  const shape = new Path2D();
  for (let i = 0; i <= 90; i++) {
    const a = (i / 90) * TAU, rr = R * (1 + 0.18 * noise1(a * 3 + t * 0.6, 7) + 0.08 * noise1(a * 11, 9));
    const x = W / 2 + Math.cos(a) * rr * 1.25, y = H / 2 + Math.sin(a) * rr * 0.8;
    if (i === 0) shape.moveTo(x, y); else shape.lineTo(x, y);
  }
  shape.closePath();
  ctx.save(); ctx.clip(shape); memoryScene(ctx, t); ctx.restore();
  ctx.save(); ctx.lineJoin = 'round';
  ctx.strokeStyle = 'rgba(40,20,10,0.9)'; ctx.lineWidth = 26; ctx.stroke(shape);
  ctx.strokeStyle = 'rgba(255,140,40,0.95)'; ctx.lineWidth = 7; ctx.stroke(shape);
  ctx.globalCompositeOperation = 'lighter'; ctx.strokeStyle = 'rgba(255,190,90,0.5)'; ctx.lineWidth = 22; ctx.stroke(shape);
  ctx.restore();
}

// 6: the search party; then clues fly onto an evidence board and red thread ties them to him.
const CLUES = [
  { x: 420, y: 330, w: 240, h: 190, rot: -0.08, label: 'ribbon' }, { x: 1500, y: 300, w: 230, h: 200, rot: 0.07, label: 'lantern' },
  { x: 360, y: 780, w: 250, h: 190, rot: 0.05, label: 'footprint' }, { x: 1560, y: 790, w: 240, h: 190, rot: -0.06, label: 'feather' },
  { x: 960, y: 170, w: 220, h: 170, rot: 0.03, label: 'shard' },
];
function clueArt(ctx, kind, w, h) {
  ctx.save();
  if (kind === 'ribbon') P.ribbonBow(ctx, 0, -10, 7, 0.4);
  if (kind === 'lantern') P.lanternAt(ctx, 0, -70, 5, 0.3);
  if (kind === 'footprint') { ctx.fillStyle = '#2A2014'; ctx.save(); ctx.rotate(0.3); ctx.beginPath(); ctx.ellipse(0, -20, 26, 44, 0, 0, TAU); ctx.fill(); ctx.beginPath(); ctx.ellipse(0, 46, 20, 24, 0, 0, TAU); ctx.fill(); ctx.restore(); }
  if (kind === 'feather') { ctx.save(); ctx.rotate(-0.6); ctx.fillStyle = '#6A5640'; ctx.beginPath(); ctx.ellipse(0, 0, 18, 70, 0, 0, TAU); ctx.fill(); ctx.strokeStyle = '#2A2014'; ctx.lineWidth = 2; ctx.beginPath(); ctx.moveTo(0, -70); ctx.lineTo(0, 90); ctx.stroke(); for (let k = -5; k <= 5; k++) { ctx.beginPath(); ctx.moveTo(0, k * 12); ctx.lineTo(16, k * 12 - 10); ctx.moveTo(0, k * 12); ctx.lineTo(-16, k * 12 - 10); ctx.stroke(); } ctx.restore(); }
  if (kind === 'shard') { const g = ctx.createLinearGradient(-60, -50, 60, 50); g.addColorStop(0, '#C8D6F0'); g.addColorStop(1, '#3B4A72'); ctx.fillStyle = g; ctx.beginPath(); ctx.moveTo(-50, -40); ctx.lineTo(60, -20); ctx.lineTo(-10, 55); ctx.closePath(); ctx.fill(); }
  ctx.restore();
}
function sSearch(ctx, t) {
  if (t >= T.board) {
    // the evidence board
    vgrad(ctx, [[0, '#2A1A12'], [1, '#160D08']]);
    ctx.fillStyle = 'rgba(0,0,0,0.25)'; for (let i = 0; i < 300; i++) ctx.fillRect(hash01(i, 121) * W, hash01(i, 122) * H, 2, 2);
    const lt = t - T.board;
    const items = CLUES.map((c, i) => {
      const k = springU(M.U(t), M.U(T.board + i * 1.1), SPRING.bouncy);
      return { ...c, s: k, draw: (cx, w, h) => clueArt(cx, c.label, w, h) };
    }).filter((c) => c.s > 0);
    const thread = clamp((lt - 1.2) / 5);
    P.evidence(ctx, items, [960, 560], thread, t);
    // his portrait at the centre
    const pk = springU(M.U(t), M.U(T.board + 0.3), SPRING.snappy);
    if (pk > 0) {
      ctx.save(); ctx.translate(960, 560); ctx.scale(pk, pk);
      const card = new Path2D(); card.rect(-150, -180, 300, 360); P.cut(ctx, card, C.paper, { depth: 8, shadow: 0.5, blur: false });
      P.face(ctx, 0, -10, 120, 'fear');
      ctx.fillStyle = '#2A1E10'; ctx.font = font(26, 700, DISPLAY); ctx.textAlign = 'center'; ctx.letterSpacing = '6px'; ctx.fillText('SIMON', 0, 150); ctx.letterSpacing = '0px';
      P.pin(ctx, 0, -160, 9);
      ctx.restore();
    }
    glow(ctx, 960, 400, 900, 'rgba(255,200,120,0.25)', 1);
    return;
  }
  // the search party combs the forest
  const lt = t - T.s6;
  const camX = 5200 - lt * 60;
  forest(ctx, t, camX, {
    moonX: 380,
    between: (i) => {
      if (i === 2) {
        for (let k = 0; k < 7; k++) {
          const x = ((W + 300) - ((lt * 90 + k * 330) % (W + 600))), y = 930;
          P.villager(ctx, x, y, 230, lt * 1.1 + k * 0.3, '#0A0B18', 1.4, k);
          // lantern beams sweeping
          const a = -Math.PI / 2 + 0.9 * Math.sin(lt * 0.8 + k * 1.7) - 0.3;
          ctx.save(); ctx.globalCompositeOperation = 'lighter';
          const bx = x + 51, by = y - 87, Lb = 1100;
          const g = ctx.createLinearGradient(bx, by, bx + Math.cos(a) * Lb, by + Math.sin(a) * Lb);
          g.addColorStop(0, 'rgba(255,200,120,0.5)'); g.addColorStop(1, 'rgba(255,200,120,0)');
          ctx.fillStyle = g; ctx.beginPath(); ctx.moveTo(bx, by); ctx.lineTo(bx + Math.cos(a - 0.12) * Lb, by + Math.sin(a - 0.12) * Lb); ctx.lineTo(bx + Math.cos(a + 0.12) * Lb, by + Math.sin(a + 0.12) * Lb); ctx.closePath(); ctx.fill();
          ctx.restore();
        }
      }
      if (i === 3) perchedOwls(ctx, t, camX, 3, () => 1, { glow: true, look: () => -0.6 });
    },
  });
  dark(ctx, 0.08);
  // Simon hidden behind a near trunk; a beam finds him on the impact
  const hit = since(within(IMPACTS, T.s6, T.board), t);
  const found = hit < 2.5 ? Math.exp(-hit * 1.5) : 0;
  P.simon(ctx, 1490, 1010, 340, { armF: [-1.0, -1.6], armB: [0.2, -1.2], head: 0.3, mouth: found > 0.2 ? 'O' : 'line', brows: 2, lean: 0.1 }, { facing: -1 });
  const trunk = new Path2D(); trunk.rect(1240, -20, 190, 1120); P.cut(ctx, trunk, '#05050C', { depth: 12, shadow: 0.6, blur: false });
  if (found > 0) { glow(ctx, 1500, 800, 500, 'rgba(255,210,140,0.8)', found); }
  foreground(ctx, camX, 1.3);
  actCard(ctx, t, T.s6 + 0.3, 'III', 'THE SEARCH PARTY');
}

// 7: framed. Gilded frames slam around him; the dropouts leave one spotlight; a gallery, all of him.
function sFramed(ctx, t) {
  const drp = within(DROPS, T.s7 - 0.05, T.s8), imp = within(IMPACTS, T.s7, T.s8);
  const slams = [T.s7 + 0.05, ...imp, T.s7 + 3.34, T.s7 + 8.34, T.s7 + 13.34].filter((x) => x < T.gallery).sort((a, b) => a - b);
  const sDrp = since(drp, t);
  const dim = sDrp < 1.5 ? 1 - sDrp / 1.5 : 0;
  vgrad(ctx, [[0, '#14101C'], [1, '#08060C']]);
  // wallpaper damask (paper)
  ctx.fillStyle = 'rgba(201,162,74,0.06)';
  for (let y = 0; y < H; y += 120) for (let x = (y / 120 % 2) * 60; x < W; x += 120) { ctx.beginPath(); ctx.ellipse(x, y, 18, 34, 0, 0, TAU); ctx.fill(); }
  if (t < T.gallery) {
    const n = slams.filter((x) => x <= t).length;
    const zoom = lerp(1, 0.55, clamp((n - 1) / 6));
    ctx.save(); ctx.translate(W / 2, H / 2); ctx.scale(zoom, zoom); ctx.translate(-W / 2, -H / 2);
    // Simon pounding on the glass
    const pound = Math.abs(Math.sin(t * 6));
    P.simon(ctx, W / 2, 790, 380, { armF: [-1.9 + pound * 0.3, -0.3], armB: [-1.7 - pound * 0.3, -0.4], mouth: 'O', brows: 2, lean: -0.05 }, { facing: 1 });
    slams.forEach((s0, i) => {
      if (t < s0) return;
      const k = springU(M.U(t), M.U(s0), SPRING.snappy);
      const sc = lerp(2.6, 1, Math.min(1.05, k));
      const w0 = 560 + i * 240, h0 = 640 + i * 200;
      ctx.save(); ctx.translate(W / 2, 540); ctx.scale(sc, sc);
      P.frame(ctx, -w0 / 2, -h0 / 2, w0, h0, 46 + i * 6, { label: i === 0 ? 'SIMON' : null });
      ctx.restore();
    });
    ctx.restore();
    // spotlight in the dropouts
    if (dim > 0) {
      ctx.save(); ctx.globalAlpha = 0.85 * dim; ctx.fillStyle = '#000';
      const sp = new Path2D(); sp.rect(0, 0, W, H); sp.ellipse(W / 2, 600, 300, 420, 0, 0, TAU); ctx.fill(sp, 'evenodd'); ctx.restore();
    }
    M.shake(ctx, M.U(t), M.U(slams.filter((x) => x <= t).pop() ?? 0), 10, 4, 0.25);
  } else {
    // the gallery: a wall of portraits, all of him
    const lt = t - T.gallery;
    const z = lerp(1.6, 1, E.outCubic(clamp(lt / 2)));
    ctx.save(); ctx.translate(W / 2, H / 2); ctx.scale(z, z); ctx.translate(-W / 2, -H / 2);
    for (let r = -1; r <= 3; r++) for (let c = -1; c <= 5; c++) {
      const w = 260, h = 300, x = 120 + c * 330 + (r % 2) * 40, y = 60 + r * 360;
      if (x > W + 100 || y > H + 100) continue;
      const main = r === 1 && c === 2;
      const fw = main ? w + 80 : w, fh = main ? h + 90 : h, fx = main ? x - 40 : x, fy = main ? y - 45 : y;
      ctx.fillStyle = '#1A1420'; ctx.fillRect(fx + 30, fy + 30, fw - 60, fh - 60);
      const expr = ['fear', 'grief', 'fear', 'calm'][(r * 7 + c * 3 + 20) % 4];
      P.face(ctx, fx + fw / 2, fy + fh / 2 + 6, main ? 95 : 70, expr, { tilt: (hash01(r * 9 + c, 131) - 0.5) * 0.3 });
      if (!main && hash01(r * 9 + c, 132) < 0.25) { ctx.fillStyle = C.owlEye; for (const sd of [-1, 1]) { ctx.beginPath(); ctx.arc(fx + fw / 2 + sd * 30, fy + fh * 0.45, 12, 0, TAU); ctx.fill(); } }
      P.frame(ctx, fx, fy, fw, fh, main ? 40 : 30, { label: main ? 'SIMON' : null });
      if (main && t >= T.crack) {
        const ck = clamp((t - T.crack) * 4);
        ctx.strokeStyle = `rgba(255,255,255,${0.85 * ck})`; ctx.lineWidth = 2.5;
        const r2 = M.mulberry32(77);
        for (let k = 0; k < 10; k++) { ctx.beginPath(); let px = fx + fw / 2, py = fy + fh / 2; ctx.moveTo(px, py); const a = (k / 10) * TAU + r2(); for (let j = 0; j < 4; j++) { px += Math.cos(a + (r2() - 0.5)) * 40 * ck; py += Math.sin(a + (r2() - 0.5)) * 40 * ck; ctx.lineTo(px, py); } ctx.stroke(); }
      }
    }
    ctx.restore();
    // a sweeping spotlight
    ctx.save(); ctx.globalAlpha = 0.6; ctx.fillStyle = '#000';
    const sx = W / 2 + Math.sin(lt * 1.3) * 500;
    const sp = new Path2D(); sp.rect(0, 0, W, H); sp.ellipse(lt > 3.5 ? W / 2 : sx, 520, 420, 380, 0, 0, TAU); ctx.fill(sp, 'evenodd'); ctx.restore();
  }
  actCard(ctx, t, T.s7 + 0.3, 'IV', 'FRAMED');
}

// 8: the court of owls. Gavel on the snare peaks; the jury turns its heads together.
function sCourt(ctx, t) {
  const lt = t - T.s8;
  vgrad(ctx, [[0, '#120C10'], [1, '#2A1A18']]);
  // tall moonlit windows
  for (let k = 0; k < 4; k++) {
    const x = 220 + k * 460;
    ctx.fillStyle = '#0A0812'; ctx.fillRect(x, 80, 220, 520);
    const g = ctx.createLinearGradient(x, 80, x, 600); g.addColorStop(0, 'rgba(160,190,255,0.35)'); g.addColorStop(1, 'rgba(160,190,255,0.08)');
    ctx.fillStyle = g; ctx.fillRect(x + 10, 90, 200, 500);
    ctx.fillStyle = '#120C10'; ctx.fillRect(x + 105, 90, 10, 500); ctx.fillRect(x + 10, 330, 200, 10);
    ctx.beginPath(); ctx.arc(x + 110, 80, 110, Math.PI, 0); ctx.fillStyle = '#0A0812'; ctx.fill();
  }
  ctx.fillStyle = '#1E1210'; ctx.fillRect(0, 900, W, 180);
  const shot = t < T.s8 + 5 ? 0 : t < T.s8 + 8.34 ? 1 : t < T.s8 + 11.67 ? 2 : 0;
  const z = [1 + 0.06 * E.inOutSine(clamp(lt / 16.7)), 2.1, 2.3][shot];
  const fc = [[W / 2, 600], [960, 330], [1650, 760]][shot];
  ctx.save(); frameZoom(ctx, z, fc[0], fc[1]);
  // the judge
  const strikes = [T.s8 + 3.33, T.s8 + 6.67, T.s8 + 10.0, T.s8 + 13.34, T.s9 - 0.02];
  const sS = since(strikes, t);
  const raise = sS < 0.6 ? Math.exp(-sS * 10) : clamp((sS - 0.6) / 2.2);
  P.owl(ctx, 960, 470, 380, 1, 0, { wig: true, stern: 1 });
  P.bench(ctx, 960, 900, 760, 430);
  // gavel
  ctx.save(); ctx.translate(1240, 470); ctx.rotate(-0.4 - raise * 1.1);
  ctx.fillStyle = '#5A3A22'; ctx.fillRect(-6, -150, 12, 150);
  const head = new Path2D(); head.roundRect(-46, -190, 92, 46, 10); P.cut(ctx, head, '#7A4E2C', { depth: 4, shadow: 0.4, blur: false });
  ctx.restore();
  if (sS < 0.3) glow(ctx, 1200, 470, 300, 'rgba(255,230,170,0.7)', 1 - sS / 0.3);
  // jury of owls, two rows, heads turning together on the beats
  const look = Math.sin(Math.floor(M.U(t) / 2) * Math.PI / 2 + 0.5) > 0 ? 1 : -1;
  for (let r = 0; r < 2; r++) for (let c = 0; c < 6; c++) {
    const x = 70 + c * 82 + r * 40, y = 760 + r * 130;
    ctx.fillStyle = '#2A1810'; ctx.fillRect(x - 50, y, 100, 30);
    P.owl(ctx, x, y + 4, 120, 1, look, { tilt: look * 0.12 });
  }
  // the dock
  ctx.fillStyle = '#3A2418'; ctx.fillRect(1500, 760, 300, 200);
  P.simon(ctx, 1650, 930, 300, { armF: [-1.3, -0.4], armB: [-1.2, -0.5], mouth: 'O', brows: 2, head: -0.15 }, { facing: -1 });
  ctx.fillStyle = '#4A2E1E'; ctx.fillRect(1490, 820, 320, 140);
  ctx.restore();
  // testimony fluttering down
  for (let i = 0; i < 26; i++) {
    const x = (hash01(i, 141) * W + Math.sin(lt * 0.8 + i) * 80), y = ((hash01(i, 142) * H + lt * (60 + 60 * hash01(i, 143))) % (H + 200)) - 100;
    ctx.save(); ctx.translate(x, y); ctx.rotate(Math.sin(lt * 1.5 + i) * 0.6); ctx.scale(1, Math.abs(Math.cos(lt * 1.2 + i)) * 0.8 + 0.2);
    ctx.fillStyle = C.paper; ctx.fillRect(-30, -40, 60, 80); ctx.fillStyle = 'rgba(40,30,20,0.4)'; for (let k = 0; k < 6; k++) ctx.fillRect(-22, -30 + k * 11, 30 + (k % 3) * 6, 3);
    ctx.restore();
  }
  actCard(ctx, t, T.s8 + 0.3, 'V', 'THE COURT OF OWLS');
}

// 9: the storm. The theatre tears apart; red threads bind him; on the high note he is lifted.
function sStorm(ctx, t) {
  const lt = t - T.s9;
  const crashes = within(CRASH, T.s9, T.s10);
  const sC = since(crashes, t);
  vgrad(ctx, [[0, '#050410'], [1, '#14102A']]);
  // the blank paper behind the scenery, revealed as the flats fall
  const fallK = E.inCubic(clamp(lt / 14));
  ctx.save(); ctx.globalAlpha = fallK; ctx.fillStyle = '#E9E0CC'; ctx.fillRect(0, 0, W, H);
  ctx.strokeStyle = 'rgba(120,100,70,0.3)'; for (let i = 0; i < 30; i++) { ctx.beginPath(); ctx.moveTo(0, i * 40 + 10); ctx.lineTo(W, i * 40 + 10 + Math.sin(i) * 6); ctx.stroke(); }
  ctx.restore();
  const camX = 3000 + lt * 200;
  // flats fall backwards about their base
  const flat = (cv, k, y, ang) => {
    ctx.save(); ctx.translate(0, H); ctx.transform(1, 0, 0, Math.cos(ang), 0, 0); ctx.translate(0, -H);
    layer(ctx, cv, camX, k, y); ctx.restore();
  };
  flat(L.far, 0.2, H - 820 + 60, clamp(lt / 5) * 1.5);
  flat(L.mid, 0.45, H - 920 + 60, clamp((lt - 3) / 6) * 1.5);
  flat(L.near, 0.75, H - 1040 + 40, clamp((lt - 7) / 7) * 1.5);
  // lightning on the crashes
  if (sC < 0.35) { const k = crashes.filter((x) => x <= t).length; lightning(ctx, 300 + (k * 397) % 1300, -20, 500 + (k * 211) % 1100, 760, k + 5, 1 - sC / 0.35); }
  scraps(ctx, t, T.s9, 120, -1, 0.95);
  // Simon runs, then is caught and lifted by the threads
  const lift = E.inOutCubic(prog(t, T.lift, T.lift + 2.4));
  const sx = 900 + Math.sin(lt * 0.7) * 120, sy = 1010 - lift * 420;
  const threadN = Math.floor(clamp(lt / 18) * 10) + 2;
  ctx.strokeStyle = C.red; ctx.lineWidth = 3;
  for (let i = 0; i < threadN; i++) {
    const ax = hash01(i, 151) * W, ay = hash01(i, 152) < 0.6 ? -20 : (hash01(i, 153) < 0.5 ? -20 : H * hash01(i, 154));
    const sxa = hash01(i, 152) < 0.6 ? ax : (hash01(i, 153) < 0.5 ? -20 : W + 20);
    const tx = sx + (hash01(i, 155) - 0.5) * 80, ty = sy - 120 - hash01(i, 156) * 140;
    ctx.beginPath(); ctx.moveTo(sxa, ay); ctx.quadraticCurveTo((sxa + tx) / 2, (ay + ty) / 2 + 80 * Math.sin(t * 2 + i), tx, ty); ctx.stroke();
  }
  const pose = lift > 0 ? { armF: [-2.4, -0.3], armB: [2.4, 0.3], legF: [0.2, 0.4], legB: [-0.2, 0.5], mouth: 'O', brows: 2, head: -0.2 } : walkPose(t * 2.3, 1, false);
  P.simon(ctx, sx, sy, 340, pose, { facing: -1 });
  // threads wrapped around him
  for (let k = 0; k < Math.min(6, threadN); k++) { ctx.strokeStyle = C.red; ctx.lineWidth = 3; ctx.beginPath(); ctx.ellipse(sx, sy - 160 + k * 26, 50, 10, 0.2 * Math.sin(k), 0, TAU); ctx.stroke(); }
  // a mirror falls and shatters on each crash
  crashes.forEach((c0, i) => {
    const tt = t - c0; if (tt < 0 || tt > 1.4) return;
    const x = 300 + (i * 523) % 1300;
    if (tt < 0.5) P.mirror(ctx, x, lerp(-200, 900, E.inQuad(tt / 0.5)), 110, 150, { thread: 0, crack: 0 });
    else for (let s = 0; s < 9; s++) {
      const a = (s / 9) * TAU, d = (tt - 0.5) * 600;
      ctx.save(); ctx.translate(x + Math.cos(a) * d, 900 - Math.abs(Math.sin(a)) * d * 0.8 + (tt - 0.5) ** 2 * 900); ctx.rotate(tt * 8 + s);
      ctx.fillStyle = 'rgba(190,210,240,0.9)'; ctx.beginPath(); ctx.moveTo(-14, -10); ctx.lineTo(16, -6); ctx.lineTo(0, 16); ctx.closePath(); ctx.fill(); ctx.restore();
    }
  });
  if (lift > 0) glow(ctx, sx, sy - 180, 700, 'rgba(255,240,220,0.7)', bump(t, T.lift + 0.6, 1.2));
  dark(ctx, sC < 0.12 ? 0.5 * (1 - sC / 0.12) : 0, '#FFFFFF');
}

// 10: pull back: a toy theatre on a table; Simon hangs over the stage like a marionette.
function sTable(ctx, t) {
  const lt = t - T.s10;
  const pull = E.inOutCubic(clamp(lt / 8));
  // the room
  vgrad(ctx, [[0, '#07050A'], [0.75, '#120C0C'], [1, '#2A1A12']]);
  const inset = lerp(1.9, 0.5, pull);
  const flicker = t > T.s11 - 3 ? (Math.sin(t * 37) > 0.2 ? 1 : 0.25) * clamp((T.s11 - t) / 3) : 1;
  // table top
  ctx.save(); ctx.globalAlpha = pull;
  ctx.fillStyle = '#3A2414'; ctx.beginPath(); ctx.moveTo(0, 820); ctx.lineTo(W, 820); ctx.lineTo(W, H); ctx.lineTo(0, H); ctx.closePath(); ctx.fill();
  ctx.fillStyle = '#4C3020'; ctx.fillRect(0, 815, W, 10);
  for (const [cx, cy] of [[260, 780], [1660, 760]]) {
    ctx.fillStyle = '#EDE3CC'; ctx.fillRect(cx - 18, cy - 120, 36, 120);
    const fl = 0.85 + 0.15 * Math.sin(t * 11 + cx);
    glow(ctx, cx, cy - 150, 380, 'rgba(255,180,90,0.55)', fl);
    ctx.fillStyle = '#FFE3A0'; ctx.beginPath(); ctx.ellipse(cx, cy - 140, 8, 20 * fl, 0, 0, TAU); ctx.fill();
  }
  ctx.restore();
  // the stage, inside the arch
  ctx.save();
  ctx.translate(W / 2, H / 2); ctx.scale(inset, inset); ctx.translate(-W / 2, -H / 2);
  ctx.beginPath(); ctx.rect(210, 90, W - 420, H - 200); ctx.clip();
  ctx.fillStyle = '#E9E0CC'; ctx.fillRect(0, 0, W, H);
  ctx.globalAlpha = flicker;
  scraps(ctx, t, T.s9, 60, -1, 0.9);
  const sw = Math.sin(lt * 1.1) * 0.12;
  ctx.save(); ctx.translate(960, 100); ctx.rotate(sw); ctx.translate(-960, -100);
  ctx.strokeStyle = C.red; ctx.lineWidth = 3;
  for (const [ax, hx, hy] of [[760, 860, 560], [1160, 1060, 560], [960, 960, 420], [880, 930, 760], [1040, 990, 760]]) { ctx.beginPath(); ctx.moveTo(ax, -400); ctx.lineTo(hx, hy); ctx.stroke(); }
  P.simon(ctx, 960, 930, 360, { armF: [-2.5, -0.4], armB: [2.5, 0.4], legF: [0.1, 0.5], legB: [-0.15, 0.6], head: 0.4, mouth: 'down', brows: 1 }, {});
  ctx.restore();
  ctx.restore();
  ctx.globalAlpha = 1;
  P.proscenium(ctx, W, H, 1, { t, inset, lights: flicker });
  // owls perched on the theatre roof
  if (pull > 0.6) for (let k = 0; k < 3; k++) P.owl(ctx, W / 2 + (k - 1) * 170 * inset * 2, H / 2 - 520 * inset, 120 * inset * 2, 0.7 + 0.3 * Math.sin(t + k), 0, {});
  dark(ctx, 1 - prog(t, T.s10, T.s10 + 0.4), '#FFFFFF');
}

// 11: the dropout. Black; scraps of paper hang still.
function sStill(ctx, t) {
  ctx.fillStyle = '#000'; ctx.fillRect(0, 0, W, H);
  ctx.save(); ctx.globalAlpha = 0.5; scraps(ctx, t, T.s9, 60, -1, 1, T.s11 - T.s9); ctx.restore();
}

// 12-13: snow. The clearing buried, owls asleep; he sits where she lay, finds the ribbon; her ghost.
function sSnow(ctx, t, o = {}) {
  const lt = t - T.s12;
  const camX = 2900 + lt * 4;
  forest(ctx, t, camX, { moonX: 1300, between: (i) => { if (i >= 2) perchedOwls(ctx, t, camX, i, () => o.eyes ?? 0.04, { snowcap: true, glow: o.eyes > 0.5 }); } });
  ctx.save(); ctx.globalCompositeOperation = 'lighter'; ctx.fillStyle = 'rgba(120,150,210,0.10)'; ctx.fillRect(0, 0, W, H); ctx.restore();
  const amt = 0.4 + 0.6 * clamp(lt / 20);
  snowGround(ctx, amt, t);
  for (let i = 0; i < 12; i++) P.flower(ctx, 820 + hash01(i, 71) * 520, 1080 - 90 * amt - 10, 10, '#FFFFFF', '#E8C35A', hash01(i, 74) * 3);
  const close = !o.pick && t > T.s12 + 10 && t < T.s12 + 15 ? 1 : 0;
  const z = close ? 2.3 + 0.12 * (t - T.s12 - 10) / 5 : 1 + 0.08 * E.inOutSine(clamp((t - T.s12) / 28));
  ctx.save(); frameZoom(ctx, z, close ? 900 : W / 2, close ? 900 : 900);
  // her ghost (sepia paper, translucent)
  const ghost = o.ghost ?? 0;
  if (ghost > 0) { ctx.save(); ctx.globalAlpha = ghost * 0.7; P.her(ctx, 1110, 1000, 320, { armF: [-1.1, -0.6], armB: [0.3, 0.1] }, { facing: -1, sepia: true }); ctx.restore(); glow(ctx, 1110, 840, 360, 'rgba(255,230,180,0.5)', ghost); }
  const pick = o.pick ?? 0;
  const pose = pick > 0 ? { ...KNEEL, armF: [lerp(-0.9, -2.0, pick), lerp(-0.2, -1.2, pick)], head: lerp(0.25, -0.15, pick) } : { ...SIT };
  P.simon(ctx, 920, 1010 - 90 * amt + 70 + kneelY(340, pick > 0 ? 1 : 0.6), 340, pose, { facing: 1, lantern: false });
  // the ribbon: half-buried, then lifted to his hand
  const rx = lerp(1060, 990, pick), ry = lerp(1080 - 90 * amt - 4, 760, E.inOutCubic(pick));
  P.ribbonBow(ctx, rx, ry, 4.5, Math.sin(t * 2) * pick);
  // lantern low
  P.lanternAt(ctx, 800, 1080 - 90 * amt - 64, 2.6, 0.35 + 0.1 * Math.sin(t * 5));
  ctx.restore();
  P.snow(ctx, W, H, t, 260, 1);
  if (!o.noCard) actCard(ctx, t, T.s12 + 0.5, 'VI', 'SNOW');
}
function sFind(ctx, t) {
  sSnow(ctx, t, { pick: E.inOutCubic(prog(t, T.s13 + 0.5, T.s13 + 3.2)), ghost: E.inOutCubic(prog(t, T.s13 + 3.0, T.s14 - 0.3)), noCard: true });
}

// 14: the final chorus. The ribbon unfurls across the stage; every mirror shows her; they dance.
function sChorus(ctx, t) {
  const lt = t - T.s14;
  const camX = 2900 + lt * 30;
  forest(ctx, t, camX, { moonX: 1300, between: (i) => { if (i >= 2) perchedOwls(ctx, t, camX, i, () => 1, { glow: true, snowcap: true }); } });
  ctx.save(); ctx.globalCompositeOperation = 'lighter'; ctx.fillStyle = `rgba(255,200,140,${0.12 + 0.12 * cue('loud', t)})`; ctx.fillRect(0, 0, W, H); ctx.restore();
  snowGround(ctx, 1, t);
  mirrorsAt(ctx, t, T.s14 - 0.3, 960, 760, 1, { her: true });
  bigRibbon(ctx, t, E.outCubic(prog(t, T.s14, T.s14 + 2.2)), W / 2, 560);
  // the dance (him real, her paper-ghost warm)
  const a = lt * 1.6, r = 130, cx = 960;
  const hx = cx + Math.cos(a) * r, sx = cx - Math.cos(a) * r;
  const drawHer = () => { ctx.save(); ctx.globalAlpha = 0.85; P.her(ctx, hx, 1000, 320, { armF: [-1.4, -0.3], armB: [0.5, 0.2], legF: [-0.2 * Math.sin(a * 3), 0], legB: [0.2 * Math.sin(a * 3), 0] }, { facing: Math.cos(a) > 0 ? -1 : 1, sepia: true }); ctx.restore(); };
  const drawHim = () => P.simon(ctx, sx, 1000, 340, { armF: [-1.4, -0.3], armB: [0.3, -0.2], legF: [-0.25 * Math.sin(a * 3), 0.2], legB: [0.25 * Math.sin(a * 3), 0.2], scarf: 0.8 }, { facing: Math.cos(a) > 0 ? 1 : -1 });
  if (Math.sin(a) > 0) { drawHim(); drawHer(); } else { drawHer(); drawHim(); }
  glow(ctx, cx, 820, 520, 'rgba(255,220,170,0.45)', 0.7 + 0.3 * cue('loud', t));
  // snow swirls upward
  ctx.save(); ctx.fillStyle = C.snow;
  for (let i = 0; i < 200; i++) {
    const z = 0.3 + hash01(i, 161) * 0.7, x = (hash01(i, 162) * W + Math.sin(lt * 1.2 + i) * 80) % W, y = ((hash01(i, 163) * H - lt * (90 + 140 * z)) % H + H) % H;
    ctx.globalAlpha = 0.4 + 0.5 * z; ctx.beginPath(); ctx.arc(x, y, 1.5 + 2.5 * z, 0, TAU); ctx.fill();
  }
  ctx.restore();
  dark(ctx, Math.exp(-lt * 4) * 0.9, '#FFF8E8');
}

// 15: the vision tears away; the owls fly across the moon.
function sFlight(ctx, t) {
  const lt = t - T.s15;
  const moonK = E.inOutCubic(prog(t, T.moon - 1.2, T.moon + 1.5));
  const camX = 2900 + 300 + lt * 10;
  forest(ctx, t, camX, { moonX: lerp(1300, W / 2, moonK), moonY: lerp(230, 430, moonK), moonR: lerp(95, 380, moonK), between: (i) => { if (i >= 2 && t < T.moon) perchedOwls(ctx, t, camX, i, () => 1, { snowcap: true }); } });
  snowGround(ctx, 1, t);
  // the vision collapsing: mirrors fall away, ribbon sinks
  const fall = prog(t, T.s15, T.s15 + 2.5);
  if (fall < 1) {
    ctx.save(); ctx.translate(0, E.inQuad(fall) * 900); ctx.globalAlpha = 1 - fall;
    mirrorsAt(ctx, t, T.s14 - 0.3, 960, 760, 1, { her: true }); bigRibbon(ctx, t, 1, W / 2, 560); ctx.restore();
  }
  // owls in flight across the moon
  if (t >= T.moon - 0.5) {
    const ROWS = [400, 210, 320, 130, 260, 450];
    for (let i = 0; i < ROWS.length; i++) {
      const k = (t - T.moon + 0.5 - i * 0.5) / 4.6;
      if (k < 0 || k > 1) continue;
      const x = lerp(-200, W + 200, k) + Math.sin(i * 2.3) * 90, y = ROWS[i] + 60 - Math.sin(k * Math.PI) * 110;
      owlFly(ctx, x, y, 1.15 + (i % 3) * 0.22, t * 1.6 + i * 0.37);
    }
  }
  P.simon(ctx, 960, 1080 - 90 + 70 + kneelY(340, 0.6), 340, { ...SIT, head: lerp(0.42, -0.35, prog(t, T.moon - 1, T.moon + 1)) }, { facing: 1 });
  P.ribbonBow(ctx, 1000, 930, 4.5, 0);
  P.snow(ctx, W, H, t, 200, 1);
}

// 16: back in the theatre; he sits alone with the ribbon; the curtains close; the crest owl shuts its eyes.
function sOutro(ctx, t) {
  const lt = t - T.s16;
  ctx.fillStyle = '#040308'; ctx.fillRect(0, 0, W, H);
  const camX = 3200;
  forest(ctx, t, camX, { moonX: 1300, between: (i) => { if (i >= 2) perchedOwls(ctx, t, camX, i, () => 0.05, { snowcap: true }); } });
  snowGround(ctx, 1, t);
  P.simon(ctx, 960, 1080 - 90 + 70 + kneelY(340, 0.6), 340, { ...SIT }, { facing: 1 });
  P.ribbonBow(ctx, 1000, 930, 4.5, 0);
  P.snow(ctx, W, H, t, 200, 1);
  const inset = lerp(2.1, 1, E.outCubic(clamp(lt / 3)));
  const open = 1 - E.inOutCubic(prog(t, T.s16 + 2.6, T.end - 1.4));
  P.proscenium(ctx, W, H, open, { t, inset, lights: 1 - prog(t, T.end - 2.5, T.end), crestEyes: 1 - prog(t, T.end - 1.6, T.end - 0.8) });
}

// 17: credit.
function sCredit(ctx, t) {
  ctx.fillStyle = '#000'; ctx.fillRect(0, 0, W, H);
  const a = clamp((t - T.end - 0.1) / 0.5) * clamp((222.99 - t) / 0.45);
  if (a <= 0) return;
  ctx.save(); ctx.globalAlpha = a; ctx.textAlign = 'center';
  ctx.font = font(64, 700, DISPLAY); ctx.letterSpacing = '16px'; ctx.fillStyle = C.paper; ctx.fillText('MURDERS', W / 2 + 8, 530);
  ctx.font = font(24, 600, DISPLAY); ctx.letterSpacing = '10px'; ctx.fillStyle = C.goldHi; ctx.fillText('MIRACLE MUSICAL', W / 2 + 5, 590);
  ctx.strokeStyle = C.red; ctx.lineWidth = 2; ctx.beginPath(); ctx.moveTo(W / 2 - 50, 620); ctx.lineTo(W / 2 + 50, 620); ctx.stroke();
  ctx.letterSpacing = '0px'; ctx.restore();
}

// ---------------------------------------------------------------- timeline
const SCENES = [
  [0, T.s1, sOpen], [T.s1, T.s2, sTrail], [T.s2, T.s3, sClearing], [T.s3, T.s4, sPanic], [T.s4, T.s5, sWitness],
  [T.s5, T.s6, sMemory], [T.s6, T.s7, sSearch], [T.s7, T.s8, sFramed], [T.s8, T.s9, sCourt], [T.s9, T.s10, sStorm],
  [T.s10, T.s11, sTable], [T.s11, T.s12, sStill], [T.s12, T.s13, sSnow], [T.s13, T.s14, sFind], [T.s14, T.s15, sChorus],
  [T.s15, T.s16, sFlight], [T.s16, T.end, sOutro], [T.end, 999, sCredit],
];

function post(ctx, t) {
  ctx.drawImage(VIG, 0, 0);
  const g = GRAIN[Math.floor(t * 12) % GRAIN.length];
  ctx.save(); ctx.globalAlpha = 0.09; ctx.globalCompositeOperation = 'overlay'; ctx.drawImage(g, 0, 0, W, H); ctx.restore();
}

M.film({
  fonts: [font(100, 800, DISPLAY), font(100, 700, DISPLAY), font(100, 600, DISPLAY), font(30, 400, UI)],
  hits: HITS,
  samples: 4,
  async init() {
    [CUE, EX] = await Promise.all([fetch('analysis/cues.json').then((r) => r.json()), fetch('analysis/excerpt.json').then((r) => r.json())]);
    IMPACTS = EX.events.filter((e) => e.type === 'impact').map((e) => e.t);
    DROPS = EX.events.filter((e) => e.type === 'dropout').map((e) => e.t);
    CRASH = EX.drums.crash.map((c) => c.t);
    KICKS = EX.drums.kick.map((c) => c.t);
    SNARES = EX.drums.snare.map((c) => c.t);
    build();
  },
  draw(ctx, u, t) {
    const sc = SCENES.find(([a, b]) => t >= a && t < b) || SCENES[SCENES.length - 1];
    ctx.save(); sc[2](ctx, t); ctx.restore();
    post(ctx, t);
  },
});
