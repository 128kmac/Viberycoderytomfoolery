// heraldry.js: the Federation's 2D visual language. Every drawing is a pure function of its
// arguments (no state, no randomness beyond seeded hashes). All designs here are original.

import { TAU, clamp, lerp, hash01, noise1 } from './motion.js';

export const PAL = {
  ink: '#050A16', navy: '#0A1630', navy2: '#13254B', navy3: '#1E3768', steel: '#3A5280',
  gold: '#D9AE52', goldHi: '#F6DE9A', goldLo: '#8E6A26', bronze: '#5E4318',
  ivory: '#F1E6CF', crimson: '#B0182A', crimsonHi: '#E0384A', crimsonLo: '#5C0A14',
};
export const rgb = (h) => { const n = parseInt(h.slice(1), 16); return [(n >> 16) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255]; };

// Smooth closed/open path through points (Catmull-Rom as cubic Beziers).
export function spline(ctx, pts, closed = true, tension = 0.5) {
  const n = pts.length;
  const P = (i) => pts[closed ? (i + n) % n : Math.max(0, Math.min(n - 1, i))];
  ctx.moveTo(pts[0][0], pts[0][1]);
  const last = closed ? n : n - 1;
  for (let i = 0; i < last; i++) {
    const p0 = P(i - 1), p1 = P(i), p2 = P(i + 1), p3 = P(i + 2);
    const k = tension / 3;
    ctx.bezierCurveTo(p1[0] + (p2[0] - p0[0]) * k, p1[1] + (p2[1] - p0[1]) * k,
      p2[0] - (p3[0] - p1[0]) * k, p2[1] - (p3[1] - p1[1]) * k, p2[0], p2[1]);
  }
  if (closed) ctx.closePath();
}

// ------------------------------------------------------------------ guilloche + rays

// A banknote rosette: `lines` phase-shifted curves r(θ) = R + A sin(nθ + φ) + B sin(mθ - 2φ).
// prog (0..1) engraves it on; pulse scales the modulation (kick-driven).
export function guilloche(ctx, { cx, cy, R, A, B = 0, n = 12, m = 5, lines = 18, phase = 0, prog = 1,
  color = PAL.gold, width = 1.2, alpha = 1, steps = 520, squash = 1 }) {
  if (prog <= 0) return;
  ctx.save();
  ctx.globalAlpha *= alpha;
  ctx.strokeStyle = color; ctx.lineWidth = width;
  const N = Math.max(2, Math.floor(steps * prog));
  for (let j = 0; j < lines; j++) {
    const ph = phase + (j / lines) * TAU;
    ctx.beginPath();
    for (let i = 0; i <= N; i++) {
      const th = (i / steps) * TAU + ph * 0.15;
      const r = R + A * Math.sin(n * th + ph) + B * Math.sin(m * th - 2 * ph);
      const x = cx + r * Math.cos(th), y = cy + r * Math.sin(th) * squash;
      if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
    }
    ctx.stroke();
  }
  ctx.restore();
}

// Sunburst: alternating wedges out to R.
export function rays(ctx, cx, cy, n, rot, colA, colB, R = 3000, alphaB = 1) {
  ctx.save();
  if (colA) { ctx.fillStyle = colA; ctx.fillRect(-10, -10, ctx.canvas.width + 20, ctx.canvas.height + 20); }
  ctx.globalAlpha *= alphaB;
  ctx.fillStyle = colB;
  ctx.beginPath();
  for (let i = 0; i < n; i++) {
    const a0 = rot + (i / n) * TAU, a1 = a0 + TAU / n / 2;
    ctx.moveTo(cx, cy);
    ctx.lineTo(cx + Math.cos(a0) * R, cy + Math.sin(a0) * R);
    ctx.lineTo(cx + Math.cos(a1) * R, cy + Math.sin(a1) * R);
    ctx.closePath();
  }
  ctx.fill();
  ctx.restore();
}

// ------------------------------------------------------------------ crest parts

// Faceted eight-point star (bevelled: each point split light / dark).
export function star8(ctx, cx, cy, R, r, rot = 0, light = PAL.goldHi, dark = PAL.gold, points = 8) {
  const N = points * 2;
  const P = (i) => { const a = rot - Math.PI / 2 + (i / N) * TAU; const rr = i % 2 === 0 ? R : r; return [cx + Math.cos(a) * rr, cy + Math.sin(a) * rr]; };
  for (let i = 0; i < N; i++) {
    const p0 = P(i), p1 = P(i + 1);
    ctx.beginPath(); ctx.moveTo(cx, cy); ctx.lineTo(p0[0], p0[1]); ctx.lineTo(p1[0], p1[1]); ctx.closePath();
    ctx.fillStyle = i % 2 === 0 ? light : dark; ctx.fill();
    ctx.strokeStyle = i % 2 === 0 ? light : dark; ctx.lineWidth = 0.8; ctx.stroke();
  }
}

export function starPath(ctx, cx, cy, R, r, rot = 0, points = 8) {
  const N = points * 2;
  for (let i = 0; i < N; i++) {
    const a = rot - Math.PI / 2 + (i / N) * TAU; const rr = i % 2 === 0 ? R : r;
    const x = cx + Math.cos(a) * rr, y = cy + Math.sin(a) * rr;
    if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
  }
  ctx.closePath();
}

// One laurel branch curving from the bottom up one side (side = -1 left, +1 right).
export function laurel(ctx, cx, cy, R, side, prog = 1, col = PAL.gold, colDark = PAL.goldLo, size = 1) {
  const leaves = 13;
  const a0 = Math.PI / 2 + side * 0.25, a1 = Math.PI / 2 + side * 2.55;
  ctx.save();
  // stem
  const shown = clamp(prog) * leaves;
  ctx.strokeStyle = colDark; ctx.lineWidth = 5 * size; ctx.lineCap = 'round';
  ctx.beginPath();
  const steps = 40;
  for (let i = 0; i <= steps * clamp(prog); i++) {
    const a = lerp(a0, a1, i / steps);
    const x = cx + Math.cos(a) * R, y = cy + Math.sin(a) * R;
    if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
  }
  ctx.stroke();
  for (let k = 0; k < leaves; k++) {
    const g = clamp(shown - k);
    if (g <= 0) break;
    const tt = k / (leaves - 1);
    const a = lerp(a0, a1, tt);
    const x = cx + Math.cos(a) * R, y = cy + Math.sin(a) * R;
    const tang = a + side * Math.PI / 2;
    const L = (34 - 12 * tt) * size * g, Wd = (11 - 3 * tt) * size * g;
    for (const out of [1, -1]) {
      const ang = tang + side * out * 0.55;
      ctx.save(); ctx.translate(x + Math.cos(a) * out * 6 * size, y + Math.sin(a) * out * 6 * size); ctx.rotate(ang);
      ctx.beginPath(); ctx.ellipse(L * 0.5, 0, L * 0.5, Wd * 0.5, 0, 0, TAU);
      ctx.fillStyle = out > 0 ? col : colDark; ctx.fill();
      ctx.strokeStyle = PAL.bronze; ctx.lineWidth = 1; ctx.beginPath(); ctx.moveTo(2, 0); ctx.lineTo(L * 0.9, 0); ctx.stroke();
      ctx.restore();
    }
  }
  // berry at the tip
  ctx.restore();
}

// A sabre: blade from the hilt at (x, y) along angle ang.
export function saber(ctx, x, y, L, ang, col = PAL.ivory, hilt = PAL.gold) {
  ctx.save(); ctx.translate(x, y); ctx.rotate(ang);
  // blade (slight curve)
  ctx.beginPath();
  ctx.moveTo(0, -5); ctx.quadraticCurveTo(L * 0.55, -12, L, -2); ctx.lineTo(L - 22, 6); ctx.quadraticCurveTo(L * 0.5, 4, 0, 5);
  ctx.closePath();
  const g = ctx.createLinearGradient(0, -8, 0, 8); g.addColorStop(0, '#FFFFFF'); g.addColorStop(0.5, col); g.addColorStop(1, '#8D93A6');
  ctx.fillStyle = g; ctx.fill();
  // fuller line
  ctx.strokeStyle = 'rgba(80,90,120,0.6)'; ctx.lineWidth = 1.5; ctx.beginPath(); ctx.moveTo(10, -1); ctx.quadraticCurveTo(L * 0.5, -6, L - 40, -1); ctx.stroke();
  // guard + grip + pommel
  ctx.fillStyle = hilt;
  ctx.beginPath(); ctx.ellipse(0, 0, 8, 26, 0, 0, TAU); ctx.fill();
  ctx.fillStyle = PAL.crimsonLo; ctx.fillRect(-60, -6, 58, 12);
  ctx.strokeStyle = hilt; ctx.lineWidth = 2;
  for (let i = -56; i < -4; i += 7) { ctx.beginPath(); ctx.moveTo(i, -6); ctx.lineTo(i + 5, 6); ctx.stroke(); }
  ctx.fillStyle = hilt; ctx.beginPath(); ctx.arc(-64, 0, 9, 0, TAU); ctx.fill();
  ctx.restore();
}

// Crown seen from the front, base centre at (cx, cy), width w.
export function crown2d(ctx, cx, cy, w, gold = PAL.gold, hi = PAL.goldHi, dark = PAL.goldLo, jewel = PAL.crimson) {
  const h = w * 0.78;
  ctx.save(); ctx.translate(cx, cy);
  // arches (behind)
  ctx.strokeStyle = dark; ctx.lineWidth = w * 0.05;
  ctx.beginPath(); ctx.moveTo(-w * 0.42, -h * 0.35); ctx.quadraticCurveTo(-w * 0.2, -h * 1.02, 0, -h * 0.9); ctx.quadraticCurveTo(w * 0.2, -h * 1.02, w * 0.42, -h * 0.35); ctx.stroke();
  // cap (velvet)
  ctx.fillStyle = PAL.crimsonLo;
  ctx.beginPath(); ctx.moveTo(-w * 0.4, -h * 0.25); ctx.quadraticCurveTo(0, -h * 1.05, w * 0.4, -h * 0.25); ctx.closePath(); ctx.fill();
  // points: five, centre tallest
  const pts = [[-0.5, 0.62], [-0.25, 0.8], [0, 0.98], [0.25, 0.8], [0.5, 0.62]];
  ctx.beginPath();
  ctx.moveTo(-w * 0.5, -h * 0.22);
  for (let i = 0; i < pts.length; i++) {
    const [px, ph] = pts[i];
    ctx.lineTo(px * w * 0.92, -h * ph);
    if (i < pts.length - 1) {
      const nx = (px + pts[i + 1][0]) / 2;
      ctx.lineTo(nx * w * 0.92, -h * 0.36);
    }
  }
  ctx.lineTo(w * 0.5, -h * 0.22); ctx.closePath();
  const g = ctx.createLinearGradient(-w / 2, 0, w / 2, 0);
  g.addColorStop(0, dark); g.addColorStop(0.35, hi); g.addColorStop(0.55, gold); g.addColorStop(1, dark);
  ctx.fillStyle = g; ctx.fill();
  // orbs on points
  for (const [px, ph] of pts) {
    ctx.beginPath(); ctx.arc(px * w * 0.92, -h * ph - w * 0.035, w * 0.04, 0, TAU); ctx.fillStyle = hi; ctx.fill();
  }
  // top star
  star8(ctx, 0, -h * 1.1, w * 0.09, w * 0.035, 0, hi, gold);
  // band
  ctx.fillStyle = g;
  ctx.beginPath(); ctx.roundRect(-w * 0.52, -h * 0.26, w * 1.04, h * 0.26, w * 0.03); ctx.fill();
  ctx.strokeStyle = dark; ctx.lineWidth = Math.max(1, w * 0.012);
  ctx.beginPath(); ctx.moveTo(-w * 0.5, -h * 0.2); ctx.lineTo(w * 0.5, -h * 0.2); ctx.moveTo(-w * 0.5, -h * 0.05); ctx.lineTo(w * 0.5, -h * 0.05); ctx.stroke();
  // jewels
  for (let i = -2; i <= 2; i++) {
    const jx = i * w * 0.2;
    ctx.fillStyle = i % 2 === 0 ? jewel : PAL.navy3;
    ctx.beginPath(); ctx.ellipse(jx, -h * 0.125, w * 0.045, w * 0.055, 0, 0, TAU); ctx.fill();
    ctx.fillStyle = 'rgba(255,255,255,0.55)'; ctx.beginPath(); ctx.arc(jx - w * 0.012, -h * 0.14, w * 0.012, 0, TAU); ctx.fill();
  }
  ctx.restore();
}

// Banner ribbon with folded tails; text centred on it.
export function ribbon(ctx, cx, cy, w, h, text, fontStr, col = PAL.crimson, dark = PAL.crimsonLo, txt = PAL.ivory, prog = 1) {
  if (prog <= 0) return;
  ctx.save(); ctx.translate(cx, cy); ctx.scale(clamp(prog), 1);
  const sag = h * 0.35;
  // tails
  ctx.fillStyle = dark;
  for (const s of [-1, 1]) {
    ctx.beginPath();
    ctx.moveTo(s * (w / 2 - 10), -h / 2 + sag + 10); ctx.lineTo(s * (w / 2 + h * 0.9), -h / 2 + sag + 22);
    ctx.lineTo(s * (w / 2 + h * 0.55), sag * 0.6 + 10 + h * 0.15); ctx.lineTo(s * (w / 2 + h * 0.9), h / 2 + sag + 22);
    ctx.lineTo(s * (w / 2 - 10), h / 2 + sag + 10); ctx.closePath(); ctx.fill();
  }
  // body (sagging arc)
  ctx.fillStyle = col;
  ctx.beginPath();
  ctx.moveTo(-w / 2, -h / 2 + sag); ctx.quadraticCurveTo(0, -h / 2 - sag * 0.4, w / 2, -h / 2 + sag);
  ctx.lineTo(w / 2, h / 2 + sag); ctx.quadraticCurveTo(0, h / 2 - sag * 0.4, -w / 2, h / 2 + sag); ctx.closePath(); ctx.fill();
  ctx.strokeStyle = PAL.gold; ctx.lineWidth = 2.5; ctx.stroke();
  // text along the arc, glyph by glyph
  ctx.font = fontStr; ctx.fillStyle = txt; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
  const chars = [...text];
  const tw = ctx.measureText(text).width;
  let x = -tw / 2;
  for (const ch of chars) {
    const cw = ctx.measureText(ch).width;
    const xm = x + cw / 2;
    const k = xm / (w / 2);
    const y = sag * 0.3 * (k * k) - sag * 0.2;
    ctx.save(); ctx.translate(xm, y + 2); ctx.rotate(k * 0.12); ctx.fillText(ch, 0, 0); ctx.restore();
    x += cw;
  }
  ctx.restore();
}

// The full crest. p: per-part progress {rays, sabers, laurel, star, crown, ribbon} each 0..1
// (missing = 1). S = scale (1 = about 600 px tall). starRot spins the star.
export function crest(ctx, cx, cy, S, p = {}, opts = {}) {
  const g = (k) => clamp(p[k] ?? 1);
  ctx.save(); ctx.translate(cx, cy); ctx.scale(S, S);
  if (g('sabers') > 0) {
    const k = g('sabers');
    const a = lerp(1.25, Math.PI / 4, k);
    const hx = lerp(-120, -265, k), hy = lerp(330, 265, k);
    saber(ctx, hx, hy, 760, -a, PAL.ivory, PAL.gold);
    ctx.save(); ctx.scale(-1, 1); saber(ctx, hx, hy, 760, -a, PAL.ivory, PAL.gold); ctx.restore();
  }
  if (g('laurel') > 0) {
    laurel(ctx, 0, 0, 205, -1, g('laurel'), PAL.gold, PAL.goldLo, 1.15);
    laurel(ctx, 0, 0, 205, 1, g('laurel'), PAL.gold, PAL.goldLo, 1.15);
  }
  if (g('star') > 0 && !opts.noStar) {
    const k = g('star');
    ctx.save(); ctx.scale(k, k);
    // navy disc with gold rim, star on top
    ctx.beginPath(); ctx.arc(0, 0, 150, 0, TAU); ctx.fillStyle = PAL.navy2; ctx.fill();
    ctx.lineWidth = 8; ctx.strokeStyle = PAL.gold; ctx.stroke();
    ctx.beginPath(); ctx.arc(0, 0, 134, 0, TAU); ctx.lineWidth = 2; ctx.strokeStyle = PAL.goldLo; ctx.stroke();
    star8(ctx, 0, 0, 165, 62, opts.starRot || 0, PAL.goldHi, PAL.gold);
    ctx.beginPath(); ctx.arc(0, 0, 38, 0, TAU); ctx.fillStyle = PAL.crimson; ctx.fill();
    ctx.lineWidth = 4; ctx.strokeStyle = PAL.goldHi; ctx.stroke();
    star8(ctx, 0, 0, 26, 11, Math.PI / 8, PAL.goldHi, PAL.gold);
    ctx.restore();
  }
  if (g('crown') > 0) {
    const k = g('crown');
    const drop = (1 - k) * -260;
    crown2d(ctx, 0, -172 + drop, 190);
  }
  if (g('ribbon') > 0 && opts.motto !== false) {
    ribbon(ctx, 0, 228, 560, 58, opts.motto || 'IN UNITATE FORTITUDO', `700 26px Display`, PAL.crimson, PAL.crimsonLo, PAL.ivory, g('ribbon'));
  }
  ctx.restore();
}

// ------------------------------------------------------------------ cloth

// Waving flag hung from (px, py) to the right. Federation flag: crimson field, navy hoist band,
// gold star, gold trim. t in seconds, wind 0..1.
export function flag(ctx, px, py, fw, fh, t, wind = 1, opts = {}) {
  const NX = opts.nx || 28, NY = opts.ny || 10;
  const dir = opts.dir || 1;
  const pos = (u, v) => {
    const ph = u * 7.5 - t * 6.2 * (opts.speed || 1) + v * 1.3;
    const w = Math.sin(ph) * wind * u;
    const sag = (1 - wind) * u * u * fh * 0.5;
    return [px + dir * (u * fw * (1 - 0.08 * wind * u)), py + v * fh + w * fh * 0.22 + sag + u * fh * 0.05 * Math.sin(ph * 0.5), Math.cos(ph) * wind];
  };
  const P = [];
  for (let j = 0; j <= NY; j++) { const row = []; for (let i = 0; i <= NX; i++) row.push(pos(i / NX, j / NY)); P.push(row); }
  const field = rgb(opts.field || PAL.crimson), band = rgb(opts.band || PAL.navy2), trim = rgb(PAL.gold);
  for (let j = 0; j < NY; j++) {
    for (let i = 0; i < NX; i++) {
      const u = (i + 0.5) / NX, v = (j + 0.5) / NY;
      const a = P[j][i], b = P[j][i + 1], c = P[j + 1][i + 1], d = P[j + 1][i];
      const shade = 0.72 + 0.32 * ((a[2] + b[2]) / 2);
      let col = u < 0.3 ? band : field;
      if (v < 0.09 || v > 0.91) col = trim;
      const s = (x) => Math.round(Math.min(255, x * shade * 255));
      ctx.fillStyle = `rgb(${s(col[0])},${s(col[1])},${s(col[2])})`;
      ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); ctx.lineTo(c[0], c[1]); ctx.lineTo(d[0], d[1]); ctx.closePath();
      ctx.fill(); ctx.strokeStyle = ctx.fillStyle; ctx.lineWidth = 1; ctx.stroke();
    }
  }
  // the star, carried by the cloth
  const sc = pos(0.15, 0.5);
  const sh = 0.75 + 0.3 * sc[2];
  ctx.save(); ctx.translate(sc[0], sc[1]); ctx.scale(0.75 + 0.25 * Math.abs(sc[2]) * 0 + 0.25, 1);
  ctx.globalAlpha *= 0.95;
  star8(ctx, 0, 0, fh * 0.3, fh * 0.12, 0, sh > 0.9 ? PAL.goldHi : PAL.gold, PAL.goldLo);
  ctx.restore();
  return P;
}

// ------------------------------------------------------------------ figures (original silhouettes)

// Side-view soldier facing right, feet at (x, y), height h. phase in strides (one step per 0.5).
// pose: 'march' | 'salute' | 'stand'
export function soldier(ctx, x, y, h, phase, col, pose = 'march', facing = 1) {
  ctx.save(); ctx.translate(x, y); ctx.scale(facing * h, h);
  ctx.fillStyle = col; ctx.strokeStyle = col; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
  const s = TAU * phase;
  const swing = pose === 'march' ? 0.42 : 0;
  const bob = pose === 'march' ? Math.abs(Math.sin(s)) * 0.012 : 0;
  ctx.translate(0, -bob);
  const hip = [0, -0.47];
  const leg = (a, bend) => {
    const knee = [hip[0] + Math.sin(a) * 0.235, hip[1] + Math.cos(a) * 0.235];
    const sa = a - bend;
    const foot = [knee[0] + Math.sin(sa) * 0.235, knee[1] + Math.cos(sa) * 0.235];
    ctx.lineWidth = 0.075;
    ctx.beginPath(); ctx.moveTo(hip[0], hip[1]); ctx.lineTo(knee[0], knee[1]); ctx.lineTo(foot[0], foot[1]); ctx.stroke();
    // boot
    ctx.beginPath(); ctx.moveTo(foot[0] - 0.035, foot[1] - 0.03); ctx.lineTo(foot[0] + 0.075, foot[1] - 0.005); ctx.lineTo(foot[0] + 0.08, foot[1] + 0.02); ctx.lineTo(foot[0] - 0.04, foot[1] + 0.02); ctx.closePath(); ctx.fill();
  };
  const a1 = swing * Math.sin(s), a2 = -swing * Math.sin(s);
  leg(a2, Math.max(0, -Math.cos(s)) * 0.7 * (swing ? 1 : 0));
  leg(a1, Math.max(0, Math.cos(s)) * 0.7 * (swing ? 1 : 0));
  // greatcoat torso
  ctx.beginPath();
  ctx.moveTo(-0.075, -0.8); ctx.lineTo(0.08, -0.8); ctx.lineTo(0.105, -0.62); ctx.lineTo(0.1, -0.44); ctx.lineTo(0.13, -0.33);
  ctx.lineTo(-0.12, -0.33); ctx.lineTo(-0.095, -0.46); ctx.lineTo(-0.1, -0.64); ctx.closePath(); ctx.fill();
  // pack
  ctx.fillRect(-0.175, -0.78, 0.09, 0.2);
  // neck + head + helmet
  ctx.fillRect(-0.02, -0.86, 0.045, 0.07);
  ctx.beginPath(); ctx.arc(0.012, -0.895, 0.052, 0, TAU); ctx.fill();
  ctx.beginPath(); ctx.arc(0.0, -0.915, 0.07, Math.PI, 0); ctx.lineTo(0.1, -0.905); ctx.lineTo(0.1, -0.895); ctx.lineTo(-0.1, -0.895); ctx.lineTo(-0.1, -0.905); ctx.closePath(); ctx.fill();
  // crest spike on helmet (Federation pattern)
  ctx.beginPath(); ctx.moveTo(-0.01, -0.98); ctx.lineTo(0.0, -1.03); ctx.lineTo(0.012, -0.98); ctx.closePath(); ctx.fill();
  if (pose === 'saber') {
    // arm raised forward holding a sabre (the blade is drawn by the caller from the hand)
    ctx.lineWidth = 0.06;
    ctx.beginPath(); ctx.moveTo(0.03, -0.78); ctx.lineTo(0.1, -0.86); ctx.lineTo(0.15, -0.9); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(-0.04, -0.77); ctx.lineTo(-0.05, -0.58); ctx.lineTo(-0.03, -0.45); ctx.stroke();
  } else if (pose === 'salute') {
    ctx.lineWidth = 0.06;
    ctx.beginPath(); ctx.moveTo(0.04, -0.78); ctx.lineTo(0.16, -0.86); ctx.lineTo(0.07, -0.93); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(-0.04, -0.77); ctx.lineTo(-0.06, -0.58); ctx.lineTo(-0.05, -0.45); ctx.stroke();
    // rifle grounded at the side
    ctx.lineWidth = 0.022; ctx.beginPath(); ctx.moveTo(-0.11, 0.0); ctx.lineTo(-0.11, -0.78); ctx.stroke();
  } else {
    // rifle on the shoulder, held by the near arm
    ctx.lineWidth = 0.025;
    ctx.beginPath(); ctx.moveTo(0.075, -0.62); ctx.lineTo(-0.09, -1.18); ctx.stroke();
    ctx.lineWidth = 0.05;
    ctx.beginPath(); ctx.moveTo(0.04, -0.78); ctx.lineTo(0.1, -0.68); ctx.lineTo(0.07, -0.62); ctx.stroke();
    // far arm swings
    const sw = pose === 'march' ? 0.5 * Math.sin(s) : 0;
    ctx.beginPath(); ctx.moveTo(-0.03, -0.77); ctx.lineTo(-0.03 + Math.sin(sw) * 0.2, -0.77 + Math.cos(sw) * 0.2);
    ctx.lineTo(-0.03 + Math.sin(sw * 1.4) * 0.36, -0.77 + Math.cos(sw * 1.4) * 0.35); ctx.stroke();
  }
  ctx.restore();
}

// Front-view soldier for the parade (toward camera). phase in strides.
export function soldierFront(ctx, x, y, h, phase, col, face = PAL.ink) {
  const s = TAU * phase;
  ctx.save(); ctx.translate(x, y - Math.abs(Math.sin(s)) * 0.015 * h); ctx.scale(h, h);
  ctx.fillStyle = col; ctx.strokeStyle = col;
  // legs and boots below the greatcoat, the lifted one shorter
  const l = Math.max(0, Math.sin(s)) * 0.07, r = Math.max(0, -Math.sin(s)) * 0.07;
  ctx.fillRect(-0.068, -0.32, 0.052, 0.32 - l); ctx.fillRect(0.016, -0.32, 0.052, 0.32 - r);
  ctx.fillRect(-0.078, -0.035 - l, 0.07, 0.035); ctx.fillRect(0.008, -0.035 - r, 0.07, 0.035);
  // greatcoat: square shoulders, belted waist, flared skirt
  ctx.beginPath();
  ctx.moveTo(-0.15, -0.765); ctx.quadraticCurveTo(-0.15, -0.8, -0.11, -0.8); ctx.lineTo(0.11, -0.8); ctx.quadraticCurveTo(0.15, -0.8, 0.15, -0.765);
  ctx.lineTo(0.112, -0.55); ctx.lineTo(0.165, -0.29); ctx.lineTo(-0.165, -0.29); ctx.lineTo(-0.112, -0.55); ctx.closePath(); ctx.fill();
  // sleeves to the hands at the sides
  ctx.beginPath(); ctx.moveTo(-0.15, -0.77); ctx.lineTo(-0.195, -0.5); ctx.lineTo(-0.155, -0.48); ctx.lineTo(-0.12, -0.7); ctx.closePath(); ctx.fill();
  ctx.beginPath(); ctx.moveTo(0.15, -0.77); ctx.lineTo(0.18, -0.6); ctx.lineTo(0.14, -0.58); ctx.lineTo(0.12, -0.7); ctx.closePath(); ctx.fill();
  // epaulettes, collar, head
  ctx.fillRect(-0.165, -0.8, 0.06, 0.022); ctx.fillRect(0.105, -0.8, 0.06, 0.022);
  ctx.fillRect(-0.03, -0.85, 0.06, 0.07);
  ctx.beginPath(); ctx.ellipse(0, -0.89, 0.048, 0.058, 0, 0, TAU); ctx.fillStyle = face; ctx.fill();
  ctx.fillStyle = col;
  // helmet: dome, brim, crest spike
  ctx.beginPath(); ctx.ellipse(0, -0.925, 0.078, 0.07, 0, Math.PI, 0); ctx.fill();
  ctx.beginPath(); ctx.ellipse(0, -0.922, 0.1, 0.014, 0, 0, TAU); ctx.fill();
  ctx.beginPath(); ctx.moveTo(-0.012, -0.99); ctx.lineTo(0, -1.04); ctx.lineTo(0.012, -0.99); ctx.closePath(); ctx.fill();
  // rifle at the shoulder, bayonet fixed
  ctx.lineWidth = 0.026; ctx.beginPath(); ctx.moveTo(0.16, -0.58); ctx.lineTo(0.16, -1.12); ctx.stroke();
  ctx.lineWidth = 0.01; ctx.beginPath(); ctx.moveTo(0.16, -1.12); ctx.lineTo(0.16, -1.26); ctx.stroke();
  ctx.restore();
}

// Heroic standard bearer, three-quarter low angle, feet at (x, y), height h; returns the pole top.
export function bearer(ctx, x, y, h, col, lean = 0) {
  ctx.save(); ctx.translate(x, y); ctx.scale(h, h); ctx.rotate(lean);
  ctx.fillStyle = col; ctx.strokeStyle = col; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
  // legs apart, boots
  ctx.lineWidth = 0.085;
  ctx.beginPath(); ctx.moveTo(-0.02, -0.47); ctx.lineTo(-0.16, -0.24); ctx.lineTo(-0.2, 0); ctx.stroke();
  ctx.beginPath(); ctx.moveTo(0.03, -0.47); ctx.lineTo(0.12, -0.22); ctx.lineTo(0.22, -0.02); ctx.stroke();
  ctx.fillRect(-0.27, -0.03, 0.13, 0.04); ctx.fillRect(0.17, -0.05, 0.13, 0.04);
  // greatcoat with flaring tails
  ctx.beginPath();
  ctx.moveTo(-0.1, -0.82); ctx.lineTo(0.11, -0.82); ctx.lineTo(0.13, -0.6); ctx.lineTo(0.2, -0.3); ctx.lineTo(0.3, -0.22);
  ctx.lineTo(0.1, -0.32); ctx.lineTo(-0.05, -0.36); ctx.lineTo(-0.28, -0.25); ctx.lineTo(-0.15, -0.42); ctx.lineTo(-0.13, -0.62); ctx.closePath(); ctx.fill();
  // epaulettes
  ctx.fillRect(-0.15, -0.83, 0.07, 0.03); ctx.fillRect(0.09, -0.83, 0.07, 0.03);
  // head, peaked cap
  ctx.fillRect(-0.025, -0.9, 0.05, 0.08);
  ctx.beginPath(); ctx.arc(0.005, -0.93, 0.055, 0, TAU); ctx.fill();
  ctx.beginPath(); ctx.moveTo(-0.075, -0.965); ctx.lineTo(0.09, -0.985); ctx.lineTo(0.07, -1.03); ctx.lineTo(-0.06, -1.03); ctx.closePath(); ctx.fill();
  ctx.beginPath(); ctx.moveTo(0.02, -0.96); ctx.lineTo(0.13, -0.95); ctx.lineTo(0.05, -0.975); ctx.closePath(); ctx.fill();
  // arms raising the pole
  ctx.lineWidth = 0.055;
  ctx.beginPath(); ctx.moveTo(0.09, -0.8); ctx.lineTo(0.2, -0.95); ctx.lineTo(0.27, -1.12); ctx.stroke();
  ctx.beginPath(); ctx.moveTo(-0.08, -0.8); ctx.lineTo(0.03, -0.68); ctx.lineTo(0.15, -0.7); ctx.stroke();
  // pole
  ctx.lineWidth = 0.022;
  ctx.beginPath(); ctx.moveTo(0.06, -0.48); ctx.lineTo(0.42, -1.9); ctx.stroke();
  ctx.beginPath(); ctx.arc(0.425, -1.92, 0.025, 0, TAU); ctx.fill();
  ctx.restore();
  // pole top in canvas space
  const px = 0.42, py = -1.9;
  const c = Math.cos(lean), s = Math.sin(lean);
  return [x + (px * c - py * s) * h, y + (px * s + py * c) * h];
}

// The Sovereign in profile (facing left), bust inside a w x w box at (x, y) top-left.
// Path in a 100-unit box. Filled with engraving lines (banknote style) when engraved = true.
const SOV = [[38, 25], [36.6, 30.5], [35.6, 34.6], [37.2, 37.4], [34.8, 41.8], [32.2, 45.8], [35.2, 47.4], [35.6, 49.4],
  [34.6, 51], [36.2, 52.3], [35.1, 53.8], [36.6, 55.6], [35.7, 58.4], [38.2, 61.2], [44.5, 63.2], [47.5, 64.6], [47.4, 67.6],
  [44, 68.6], [43.2, 75.5], [36, 79.6], [25, 85.5], [15, 99.5], [93, 99.5], [87, 84], [73, 76.5], [64.5, 71.5], [63.5, 66.5],
  [60.5, 62.5], [66.5, 52.5], [67.6, 42.5], [64.6, 31], [61, 25.5]];
export function sovereignPath(ctx, x, y, w) {
  const pts = SOV.map(([px, py]) => [x + (px / 100) * w, y + (py / 100) * w]);
  ctx.beginPath(); spline(ctx, pts, true, 0.42);
}
export function sovereign(ctx, x, y, w, { ink = PAL.navy, light = PAL.goldHi, engraved = true, glow = 0, lineGap = 6 } = {}) {
  const X = (v) => x + (v / 100) * w, Y = (v) => y + (v / 100) * w;
  ctx.save();
  sovereignPath(ctx, x, y, w);
  ctx.save(); ctx.clip();
  if (engraved) {
    ctx.fillStyle = light; ctx.fillRect(x, y, w, w);
    // engraving: horizontal lines whose thickness follows a light falloff from the face
    ctx.fillStyle = ink;
    const gap = lineGap * w / 600;
    for (let yy = y; yy < y + w; yy += gap) {
      const v = (yy - y) / w * 100;
      for (let xx = x; xx < x + w; xx += gap * 2) {
        const u = (xx - x) / w * 100;
        const dFace = Math.hypot(u - 40, (v - 45) * 0.9);
        let dark = clamp((dFace - 6) / 30) * 0.7 + 0.32 + 0.12 * Math.sin(v * 0.9 + u * 0.15);
        if (v > 70) dark = Math.max(dark, 0.55 + 0.25 * Math.sin(u * 0.4));
        dark = clamp(dark - glow * 0.35);
        const th = gap * dark;
        ctx.fillRect(xx, yy + (gap - th) / 2, gap * 2 + 0.5, th);
      }
    }
  } else {
    ctx.fillStyle = ink; ctx.fillRect(x, y, w, w);
  }
  ctx.restore();
  // details: ear, eye, sash, epaulette fringe, medals
  ctx.lineWidth = Math.max(1, w * 0.004); ctx.strokeStyle = engraved ? ink : light;
  ctx.beginPath(); ctx.ellipse(X(56.5), Y(46), w * 0.03, w * 0.05, 0.1, -1.2, 2.4); ctx.stroke();
  // hair: engraved arcs over the back of the head
  ctx.save(); sovereignPath(ctx, x, y, w); ctx.clip();
  ctx.lineWidth = Math.max(1, w * 0.0035); ctx.strokeStyle = ink;
  for (let k = 0; k < 9; k++) {
    ctx.beginPath(); ctx.ellipse(X(60), Y(40), w * (0.06 + k * 0.012), w * (0.13 + k * 0.012), 0.25, Math.PI * 0.95, Math.PI * 1.95); ctx.stroke();
  }
  ctx.restore();
  // eye, brow, lips, jaw line
  ctx.lineWidth = Math.max(1.2, w * 0.006); ctx.lineCap = 'round';
  ctx.beginPath(); ctx.moveTo(X(37.6), Y(39.4)); ctx.quadraticCurveTo(X(39.8), Y(38.2), X(42.2), Y(39.6)); ctx.quadraticCurveTo(X(39.8), Y(40.6), X(37.6), Y(39.4)); ctx.stroke();
  ctx.beginPath(); ctx.moveTo(X(36.6), Y(35.6)); ctx.quadraticCurveTo(X(40), Y(34.2), X(44), Y(35.8)); ctx.stroke();
  ctx.beginPath(); ctx.moveTo(X(36.4), Y(52.3)); ctx.lineTo(X(39.5), Y(52.6)); ctx.stroke();
  ctx.beginPath(); ctx.moveTo(X(36.2), Y(47.9)); ctx.quadraticCurveTo(X(37.6), Y(49.2), X(39.4), Y(47.8)); ctx.stroke();
  ctx.beginPath(); ctx.moveTo(X(41), Y(60.5)); ctx.quadraticCurveTo(X(48), Y(58), X(55), Y(50)); ctx.stroke();
  ctx.fillStyle = PAL.crimson;
  ctx.beginPath(); ctx.moveTo(X(40), Y(78)); ctx.lineTo(X(48), Y(75)); ctx.lineTo(X(82), Y(99.5)); ctx.lineTo(X(66), Y(99.5)); ctx.closePath(); ctx.fill();
  ctx.strokeStyle = PAL.gold; ctx.lineWidth = Math.max(1, w * 0.005);
  for (let i = 0; i < 9; i++) { const fx = 76 + i * 1.6; ctx.beginPath(); ctx.moveTo(X(fx), Y(79 + i * 0.6)); ctx.lineTo(X(fx + 0.8), Y(86 + i * 0.6)); ctx.stroke(); }
  ctx.fillStyle = PAL.gold; ctx.beginPath(); ctx.ellipse(X(80), Y(79.5), w * 0.08, w * 0.022, -0.35, 0, TAU); ctx.fill();
  star8(ctx, X(30), Y(90), w * 0.035, w * 0.013, 0, PAL.goldHi, PAL.gold);
  star8(ctx, X(39), Y(91.5), w * 0.028, w * 0.011, 0, PAL.goldHi, PAL.gold);
  // crown on the head (tilted to the brow line)
  ctx.save(); ctx.translate(X(49.5), Y(25.2)); ctx.rotate(0.05);
  crown2d(ctx, 0, 0, w * 0.27);
  ctx.restore();
  ctx.restore();
}

// ------------------------------------------------------------------ poster icons

export function shipIcon(ctx, x, y, w, col) {
  ctx.save(); ctx.translate(x, y); ctx.scale(w / 100, w / 100); ctx.fillStyle = col;
  ctx.beginPath(); ctx.moveTo(-50, 0); ctx.lineTo(50, -6); ctx.lineTo(42, 8); ctx.lineTo(-44, 10); ctx.closePath(); ctx.fill();
  ctx.fillRect(-20, -18, 30, 14); ctx.fillRect(-10, -30, 12, 14); ctx.fillRect(-2, -42, 3, 14);
  ctx.fillRect(16, -10, 22, 6); ctx.fillRect(-40, -8, 18, 5);
  ctx.restore();
}
export function planeIcon(ctx, x, y, w, col) {
  ctx.save(); ctx.translate(x, y); ctx.scale(w / 100, w / 100); ctx.fillStyle = col;
  ctx.beginPath(); ctx.moveTo(0, -50); ctx.lineTo(6, -20); ctx.lineTo(48, 10); ctx.lineTo(48, 18); ctx.lineTo(6, 6); ctx.lineTo(5, 30);
  ctx.lineTo(18, 42); ctx.lineTo(18, 48); ctx.lineTo(0, 42); ctx.lineTo(-18, 48); ctx.lineTo(-18, 42); ctx.lineTo(-5, 30); ctx.lineTo(-6, 6);
  ctx.lineTo(-48, 18); ctx.lineTo(-48, 10); ctx.lineTo(-6, -20); ctx.closePath(); ctx.fill();
  ctx.restore();
}
export function guardIcon(ctx, x, y, h, col) {
  ctx.save(); ctx.translate(x, y); ctx.scale(h, h); ctx.fillStyle = col;
  ctx.beginPath(); ctx.ellipse(0, -0.86, 0.1, 0.16, 0, 0, TAU); ctx.fill();
  ctx.fillRect(-0.03, -0.72, 0.06, 0.06);
  ctx.beginPath(); ctx.moveTo(-0.13, -0.66); ctx.lineTo(0.13, -0.66); ctx.lineTo(0.11, -0.4); ctx.lineTo(-0.11, -0.4); ctx.closePath(); ctx.fill();
  ctx.fillRect(-0.09, -0.4, 0.07, 0.4); ctx.fillRect(0.02, -0.4, 0.07, 0.4);
  ctx.fillRect(-0.17, -0.66, 0.05, 0.3); ctx.fillRect(0.12, -0.66, 0.05, 0.3);
  ctx.lineWidth = 0.02; ctx.strokeStyle = col; ctx.beginPath(); ctx.moveTo(0.2, -0.3); ctx.lineTo(0.2, -1.05); ctx.stroke();
  ctx.beginPath(); ctx.moveTo(0.2, -1.12); ctx.lineTo(0.215, -1.05); ctx.lineTo(0.185, -1.05); ctx.closePath(); ctx.fill();
  ctx.restore();
}
export function gearIcon(ctx, x, y, R, col, rot = 0) {
  ctx.save(); ctx.translate(x, y); ctx.rotate(rot); ctx.fillStyle = col;
  ctx.beginPath();
  for (let i = 0; i < 24; i++) {
    const a = (i / 24) * TAU; const r = i % 2 === 0 ? R : R * 0.82;
    ctx.lineTo(Math.cos(a) * r, Math.sin(a) * r); ctx.lineTo(Math.cos(a + TAU / 48) * r, Math.sin(a + TAU / 48) * r);
  }
  ctx.closePath(); ctx.arc(0, 0, R * 0.38, 0, TAU, true); ctx.fill('evenodd');
  ctx.restore();
}
export function wheatIcon(ctx, x, y, h, col) {
  ctx.save(); ctx.translate(x, y); ctx.scale(h, h); ctx.fillStyle = col; ctx.strokeStyle = col; ctx.lineWidth = 0.02;
  for (const s of [-1, 0, 1]) {
    ctx.save(); ctx.rotate(s * 0.25);
    ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(0, -0.95); ctx.stroke();
    for (let k = 0; k < 7; k++) for (const side of [-1, 1]) {
      ctx.save(); ctx.translate(0, -0.5 - k * 0.07); ctx.rotate(side * 0.6);
      ctx.beginPath(); ctx.ellipse(0, -0.04, 0.022, 0.05, 0, 0, TAU); ctx.fill(); ctx.restore();
    }
    ctx.restore();
  }
  ctx.restore();
}
// Wings + star insignia, chevrons, anchor-star, tower: the branch insignia
export function insignia(ctx, kind, x, y, S, col = PAL.goldHi, dark = PAL.gold) {
  ctx.save(); ctx.translate(x, y); ctx.scale(S, S);
  ctx.fillStyle = col; ctx.strokeStyle = col;
  if (kind === 'wings') {
    for (const s of [-1, 1]) {
      ctx.save(); ctx.scale(s, 1);
      for (let i = 0; i < 6; i++) {
        ctx.beginPath(); ctx.moveTo(30, -10 + i * 6); ctx.quadraticCurveTo(120 - i * 10, -40 + i * 10, 170 - i * 18, -20 + i * 12);
        ctx.lineTo(160 - i * 18, -8 + i * 12); ctx.quadraticCurveTo(110 - i * 10, -18 + i * 10, 30, 2 + i * 6); ctx.closePath();
        ctx.fillStyle = i % 2 ? dark : col; ctx.fill();
      }
      ctx.restore();
    }
    star8(ctx, 0, 0, 52, 20, 0, col, dark);
  } else if (kind === 'chevrons') {
    for (let i = 0; i < 3; i++) {
      ctx.beginPath(); const yy = -50 + i * 42;
      ctx.moveTo(-110, yy + 40); ctx.lineTo(0, yy - 20); ctx.lineTo(110, yy + 40); ctx.lineTo(110, yy + 70); ctx.lineTo(0, yy + 10); ctx.lineTo(-110, yy + 70); ctx.closePath();
      ctx.fillStyle = i === 1 ? dark : col; ctx.fill();
    }
    star8(ctx, 0, -110, 40, 15, 0, col, dark);
  } else if (kind === 'anchor') {
    ctx.lineWidth = 16; ctx.lineCap = 'round';
    ctx.beginPath(); ctx.moveTo(0, -90); ctx.lineTo(0, 100); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(-50, -60); ctx.lineTo(50, -60); ctx.stroke();
    ctx.beginPath(); ctx.arc(0, 30, 90, 0.15 * Math.PI, 0.85 * Math.PI); ctx.stroke();
    ctx.beginPath(); ctx.arc(0, -110, 22, 0, TAU); ctx.lineWidth = 10; ctx.stroke();
    star8(ctx, 0, 10, 30, 12, 0, col, dark);
  } else if (kind === 'tower') {
    ctx.fillRect(-60, -40, 120, 140); ctx.fillStyle = dark;
    for (let i = -60; i < 60; i += 30) ctx.fillRect(i, -70, 18, 32);
    ctx.fillStyle = col; for (let i = -60; i < 60; i += 30) ctx.fillRect(i, -68, 16, 30);
    ctx.fillStyle = PAL.navy; ctx.beginPath(); ctx.arc(0, 100, 28, Math.PI, 0); ctx.lineTo(28, 100); ctx.fill(); ctx.fillRect(-28, 100 - 1, 56, 1);
    ctx.fillRect(-40, 0, 14, 30); ctx.fillRect(26, 0, 14, 30);
  } else if (kind === 'sabers') {
    saber(ctx, -100, 90, 240, -0.85, PAL.ivory, col);
    ctx.save(); ctx.scale(-1, 1); saber(ctx, -100, 90, 240, -0.85, PAL.ivory, col); ctx.restore();
    crown2d(ctx, 0, -40, 90);
  } else if (kind === 'crown') {
    crown2d(ctx, 0, 60, 230);
  }
  ctx.restore();
}

// Crimson wax seal with an embossed star; seed shapes the rim.
export function waxSeal(ctx, cx, cy, R, seed = 4, squash = 0) {
  ctx.save(); ctx.translate(cx, cy); ctx.scale(1 + squash, 1 - squash * 0.6);
  ctx.beginPath();
  for (let i = 0; i <= 64; i++) {
    const a = (i / 64) * TAU;
    const r = R * (1 + 0.06 * noise1(a * 2.2, seed) + 0.03 * noise1(a * 7, seed + 3));
    ctx.lineTo(Math.cos(a) * r, Math.sin(a) * r);
  }
  ctx.closePath();
  const g = ctx.createRadialGradient(-R * 0.3, -R * 0.35, R * 0.1, 0, 0, R * 1.05);
  g.addColorStop(0, PAL.crimsonHi); g.addColorStop(0.6, PAL.crimson); g.addColorStop(1, PAL.crimsonLo);
  ctx.fillStyle = g; ctx.fill();
  ctx.lineWidth = R * 0.06; ctx.strokeStyle = 'rgba(60,0,10,0.45)'; ctx.stroke();
  ctx.beginPath(); ctx.arc(0, 0, R * 0.72, 0, TAU); ctx.lineWidth = R * 0.03; ctx.strokeStyle = 'rgba(255,140,140,0.35)'; ctx.stroke();
  ctx.beginPath(); ctx.arc(0, 0, R * 0.7, 0, TAU); ctx.lineWidth = R * 0.03; ctx.strokeStyle = 'rgba(40,0,6,0.5)'; ctx.stroke();
  star8(ctx, 2, 3, R * 0.55, R * 0.22, 0, 'rgba(50,0,8,0.55)', 'rgba(50,0,8,0.55)');
  star8(ctx, -1, -1, R * 0.55, R * 0.22, 0, '#E86070', PAL.crimson);
  ctx.restore();
}

export function hashPick(i, n, seed) { return Math.floor(hash01(i, seed) * n); }
