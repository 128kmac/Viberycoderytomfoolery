// paper.js: a toy theatre made of cut paper. Every drawing is a pure function of its arguments
// (seeded randomness only). The figures are paper-doll puppets with brass split-pin joints.

import { TAU, clamp, lerp, hash01, noise1, mulberry32 } from './motion.js';

export const C = {
  ink: '#06050C', night: '#0D0E22', indigo: '#16183A', dusk: '#232A5C', moon: '#D8E6FF', moonDim: '#8FA3CF',
  paper: '#EFE6D2', paperLo: '#CDBF9F', paperDk: '#8E8068', lantern: '#FFB547', lanternHi: '#FFE1A0',
  red: '#C8102E', redLo: '#6E0718', gold: '#C9A24A', goldHi: '#F1D488', goldLo: '#7A5C1E', brass: '#B88A3A',
  owl: '#5B4A3A', owlLo: '#3A2E24', owlEye: '#F2C14E', frost: '#A9C7E8', snow: '#F4F7FF',
  coat: '#1E2236', coatLo: '#121524', skin: '#F2E3CC', dress: '#F4F0E6', dressLo: '#C9C2B4', hair: '#2A1E1A',
  sepia: '#E7C9A0', sepiaLo: '#9C7650',
};

// ------------------------------------------------------------------ paper primitives

// Fill a path as a sheet of paper: a soft drop shadow (the sheet stands off the one behind it),
// the fill, and a thin lighter edge where the cut catches the light.
export function cut(ctx, path, fill, o = {}) {
  const d = o.depth ?? 6, sh = o.shadow ?? 0.45;
  if (sh > 0) {
    ctx.save(); ctx.translate(d * 0.6, d); ctx.fillStyle = `rgba(0,0,0,${sh})`;
    if (o.blur !== false) ctx.filter = `blur(${Math.max(1, d * 0.6)}px)`;
    ctx.fill(path); ctx.restore();
  }
  ctx.fillStyle = fill; ctx.fill(path);
  if (o.edge !== false) { ctx.strokeStyle = o.edge || 'rgba(255,255,255,0.10)'; ctx.lineWidth = o.edgeW || 1.2; ctx.stroke(path); }
}

// A brass split pin (paper fastener) at a joint.
export function pin(ctx, x, y, r = 5) {
  const g = ctx.createRadialGradient(x - r * 0.35, y - r * 0.35, r * 0.1, x, y, r);
  g.addColorStop(0, '#FFF0B8'); g.addColorStop(0.5, C.brass); g.addColorStop(1, '#5A3E14');
  ctx.fillStyle = g; ctx.beginPath(); ctx.arc(x, y, r, 0, TAU); ctx.fill();
}

// Paper grain canvas (seeded), drawn over everything with low alpha.
export function grainCanvas(w, h, seed) {
  const cv = document.createElement('canvas'); cv.width = w; cv.height = h;
  const c = cv.getContext('2d'); const img = c.createImageData(w, h);
  const r = mulberry32(seed);
  for (let i = 0; i < img.data.length; i += 4) { const v = 128 + (r() - 0.5) * 200; img.data[i] = img.data[i + 1] = img.data[i + 2] = v; img.data[i + 3] = 255; }
  c.putImageData(img, 0, 0);
  // fibres
  c.globalAlpha = 0.25;
  for (let i = 0; i < 900; i++) {
    c.strokeStyle = r() < 0.5 ? '#000' : '#fff'; c.lineWidth = 0.5;
    const x = r() * w, y = r() * h, a = r() * TAU, l = 3 + r() * 10;
    c.beginPath(); c.moveTo(x, y); c.lineTo(x + Math.cos(a) * l, y + Math.sin(a) * l); c.stroke();
  }
  return cv;
}

// ------------------------------------------------------------------ forest (pre-rendered layers)

// A cut-paper tree: trunk with forking branches, seeded. Returns a Path2D in local coords (base at 0,0).
export function treePath(seed, h, kind = 'bare') {
  const p = new Path2D();
  const r = mulberry32(seed);
  if (kind === 'pine') {
    const w = h * (0.28 + r() * 0.08), tiers = 5 + Math.floor(r() * 3);
    p.rect(-h * 0.02, -h * 0.12, h * 0.04, h * 0.14);
    for (let i = 0; i < tiers; i++) {
      const t0 = i / tiers, y = -h * (0.1 + t0 * 0.85), tw = w * (1 - t0 * 0.8) * (0.9 + r() * 0.2);
      p.moveTo(-tw, y); p.lineTo(0, y - h * 0.24); p.lineTo(tw, y);
      p.quadraticCurveTo(0, y - h * 0.03, -tw, y); p.closePath();
    }
    return p;
  }
  // bare tree: recursive branches as tapered quads
  const branch = (x, y, ang, len, wid, depth) => {
    const x2 = x + Math.cos(ang) * len, y2 = y + Math.sin(ang) * len;
    const nx = -Math.sin(ang), ny = Math.cos(ang);
    p.moveTo(x + nx * wid, y + ny * wid); p.lineTo(x2 + nx * wid * 0.6, y2 + ny * wid * 0.6);
    p.lineTo(x2 - nx * wid * 0.6, y2 - ny * wid * 0.6); p.lineTo(x - nx * wid, y - ny * wid); p.closePath();
    if (depth <= 0 || wid < 1.2) return;
    const n = 2 + (r() < 0.35 ? 1 : 0);
    for (let k = 0; k < n; k++) {
      const da = (k - (n - 1) / 2) * (0.5 + r() * 0.35) + (r() - 0.5) * 0.3;
      branch(x2, y2, ang + da, len * (0.62 + r() * 0.2), wid * 0.62, depth - 1);
    }
  };
  branch(0, 0, -Math.PI / 2 + (r() - 0.5) * 0.12, h * 0.38, h * 0.035, 6);
  // root flare
  p.moveTo(-h * 0.06, 0); p.quadraticCurveTo(0, -h * 0.08, h * 0.06, 0); p.closePath();
  return p;
}

// Pre-render one forest layer into a wide canvas: a row of trees + a ground strip.
// The canvas gets `top` px of headroom above h (cv.top) so tall trees and their shadows aren't clipped at the
// layer's top edge, and the trees are drawn wrapped at x±w so the tile repeats without a seam.
export function forestLayer(w, h, seed, { count = 14, minH = 300, maxH = 700, color = C.indigo, ground = 0.12, kind = 'mix', shadow = 0.4, edge, top = 360 } = {}) {
  const cv = document.createElement('canvas'); cv.width = w; cv.height = h + top; cv.top = top;
  const c = cv.getContext('2d'); c.translate(0, top);
  const r = mulberry32(seed);
  const gy = h * (1 - ground);
  const all = new Path2D();
  for (let i = 0; i < count; i++) {
    const x = (i + 0.2 + r() * 0.6) / count * w;
    const th = lerp(minH, maxH, r());
    const k = kind === 'mix' ? (r() < 0.45 ? 'pine' : 'bare') : kind;
    const tp = treePath(Math.floor(r() * 1e6), th, k);
    const m = new DOMMatrix().translate(x, gy + 4).scale(r() < 0.5 ? -1 : 1, 1);
    for (const dx of [-w, 0, w]) all.addPath(tp, new DOMMatrix().translate(dx, 0).multiply(m));
  }
  // ground with a wavy cut edge
  all.moveTo(0, h + 10); all.lineTo(0, gy);
  for (let x = 0; x <= w; x += 40) all.lineTo(x, gy + Math.sin(x * 0.013 + seed) * 10 + noise1(x * 0.01, seed) * 8);
  all.lineTo(w, h + 10); all.closePath();
  cut(c, all, color, { depth: 8, shadow, edge: edge || 'rgba(200,215,255,0.12)' });
  return cv;
}

// ------------------------------------------------------------------ puppets

// Simon: a paper doll in a long dark coat and scarf. Pose = joint angles (radians).
// (x, y) = feet on the ground, h = height. facing 1 right, -1 left.
// pose: { lean, armF: [shoulder, elbow], armB: [...], legF: [hip, knee], legB: [...], head, scarf, lantern, mouth, brows }
export function simon(ctx, x, y, h, pose = {}, o = {}) {
  const s = h / 100;
  ctx.save(); ctx.translate(x, y); ctx.scale((o.facing || 1) * s, s);
  const p = { lean: 0, head: 0, armF: [0.15, -0.2], armB: [-0.15, -0.1], legF: [0.1, 0.05], legB: [-0.1, 0.05], scarf: 0, mouth: 'line', brows: 0, ...pose };
  const coat = o.coat || C.coat, coatLo = o.coatLo || C.coatLo;
  const sh = { depth: 3, shadow: 0.35, blur: false };
  // hip at (0,-46), shoulder at (0,-78)
  ctx.save(); ctx.rotate(p.lean);
  const limb = (px, py, a1, a2, L1, L2, w1, w2, col, foot) => {
    ctx.save(); ctx.translate(px, py); ctx.rotate(a1);
    const up = new Path2D(); up.roundRect(-w1 / 2, -2, w1, L1 + 4, w1 / 2); cut(ctx, up, col, sh);
    ctx.translate(0, L1); ctx.rotate(a2);
    const lo = new Path2D(); lo.roundRect(-w2 / 2, -2, w2, L2 + 3, w2 / 2); cut(ctx, lo, col, sh);
    if (foot) { const f = new Path2D(); f.roundRect(-w2 * 0.6, L2 - 2, w2 * 2.1, 5, 2.5); cut(ctx, f, '#0A0B12', sh); }
    else { const hd = new Path2D(); hd.arc(0, L2 + 2, w2 * 0.55, 0, TAU); cut(ctx, hd, o.skin || C.skin, sh); }
    pin(ctx, 0, 0, 1.6);
    ctx.restore();
    pin(ctx, px, py, 1.8);
  };
  // back limbs
  limb(-1, -78, p.armB[0], p.armB[1], 15, 14, 6, 5, coatLo, false);
  limb(-2, -46, p.legB[0], p.legB[1], 22, 22, 7, 6, '#151826', true);
  // coat body: long to the knees, flaring
  const body = new Path2D();
  body.moveTo(-8, -82); body.lineTo(8, -82); body.lineTo(11, -60); body.lineTo(16 + p.scarf * 2, -30); body.lineTo(-14 - p.scarf * 4, -30); body.lineTo(-10, -60); body.closePath();
  cut(ctx, body, coat, { depth: 4, shadow: 0.4, blur: false });
  ctx.strokeStyle = 'rgba(255,255,255,0.08)'; ctx.lineWidth = 0.8; ctx.beginPath(); ctx.moveTo(2, -78); ctx.lineTo(3, -32); ctx.stroke();
  for (let i = 0; i < 3; i++) pin(ctx, 4.5, -72 + i * 9, 0.9);
  // front leg + arm
  limb(2, -46, p.legF[0], p.legF[1], 22, 22, 7, 6, '#1A1D2C', true);
  // scarf: tail streams back with speed
  const sc = new Path2D();
  sc.moveTo(-7, -83); sc.lineTo(7, -83); sc.lineTo(6, -78); sc.lineTo(-7, -78); sc.closePath();
  const tail = Math.max(0, p.scarf);
  sc.moveTo(-6, -81); sc.quadraticCurveTo(-14 - tail * 10, -80 + Math.sin(tail * 7) * 3, -20 - tail * 22, -74 + tail * 2);
  sc.lineTo(-18 - tail * 22, -70 + tail * 2); sc.quadraticCurveTo(-12 - tail * 8, -75, -5, -77); sc.closePath();
  cut(ctx, sc, C.red, { depth: 2, shadow: 0.3, blur: false });
  // head
  ctx.save(); ctx.translate(0, -84); ctx.rotate(p.head);
  const head = new Path2D(); head.ellipse(1, -9, 8.5, 10, 0, 0, TAU); cut(ctx, head, o.skin || C.skin, { depth: 3, shadow: 0.35, blur: false });
  const hair = new Path2D();
  hair.moveTo(-9, -8); hair.lineTo(-10, -15); hair.lineTo(-6, -14); hair.lineTo(-7, -20); hair.lineTo(-2, -17); hair.lineTo(0, -22);
  hair.lineTo(3, -17); hair.lineTo(8, -20); hair.lineTo(7, -15); hair.lineTo(11, -14); hair.lineTo(9, -10); hair.quadraticCurveTo(1, -15, -9, -8); hair.closePath();
  cut(ctx, hair, '#1B1412', { depth: 2, shadow: 0.3, blur: false });
  // face (always seen in 3/4 toward the facing direction)
  ctx.fillStyle = '#1B1412';
  ctx.beginPath(); ctx.ellipse(4, -9, 1.1, 1.5 + (p.mouth === 'O' ? 0.6 : 0), 0, 0, TAU); ctx.fill();
  ctx.beginPath(); ctx.ellipse(-1.5, -9, 1.0, 1.4 + (p.mouth === 'O' ? 0.6 : 0), 0, 0, TAU); ctx.fill();
  ctx.strokeStyle = '#1B1412'; ctx.lineWidth = 0.8; ctx.lineCap = 'round';
  ctx.beginPath(); ctx.moveTo(-3, -12 - p.brows); ctx.lineTo(0, -12.2 + p.brows * 0.6); ctx.moveTo(2.6, -12.2 + p.brows * 0.6); ctx.lineTo(5.6, -12 - p.brows); ctx.stroke();
  if (p.mouth === 'O') { ctx.beginPath(); ctx.ellipse(2, -3.5, 1.5, 2, 0, 0, TAU); ctx.fill(); }
  else if (p.mouth === 'down') { ctx.beginPath(); ctx.arc(2, -1.5, 2, Math.PI * 1.15, Math.PI * 1.85); ctx.stroke(); }
  else { ctx.beginPath(); ctx.moveTo(0.5, -3.5); ctx.lineTo(3.5, -3.6); ctx.stroke(); }
  ctx.fillStyle = 'rgba(220,120,110,0.35)'; ctx.beginPath(); ctx.arc(6, -6, 1.6, 0, TAU); ctx.fill();
  ctx.restore();
  pin(ctx, 0, -84, 1.6);
  limb(1, -78, p.armF[0], p.armF[1], 15, 14, 6, 5, coat, false);
  // lantern in the front hand
  if (o.lantern) {
    // hand position: follow the arm chain
    const a1 = p.armF[0], a2 = p.armF[1];
    const hx = 1 + Math.sin(-a1) * 15 + Math.sin(-(a1 + a2)) * 16, hy = -78 + Math.cos(a1) * 15 + Math.cos(a1 + a2) * 16;
    lanternAt(ctx, hx, hy, 1, o.lanternGlow ?? 1, o.lanternSwing || 0);
  }
  ctx.restore();
  ctx.restore();
}

// A small paper lantern hanging from (x, y) (local puppet units).
export function lanternAt(ctx, x, y, sc = 1, glow = 1, swing = 0) {
  ctx.save(); ctx.translate(x, y); ctx.rotate(swing); ctx.scale(sc, sc);
  ctx.strokeStyle = '#2A2A2A'; ctx.lineWidth = 0.8; ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(0, 5); ctx.stroke();
  if (glow > 0) {
    ctx.save(); ctx.globalCompositeOperation = 'lighter';
    const g = ctx.createRadialGradient(0, 12, 0, 0, 12, 60);
    g.addColorStop(0, `rgba(255,190,90,${0.55 * glow})`); g.addColorStop(1, 'rgba(255,190,90,0)');
    ctx.fillStyle = g; ctx.fillRect(-60, -48, 120, 120); ctx.restore();
  }
  const body = new Path2D(); body.roundRect(-4.5, 5, 9, 13, 3);
  ctx.fillStyle = '#2B2418'; ctx.fillRect(-5.5, 4, 11, 2.2); ctx.fillRect(-5.5, 17, 11, 2.2);
  ctx.fillStyle = glow > 0 ? C.lanternHi : '#5A4A30'; ctx.fill(body);
  ctx.strokeStyle = '#2B2418'; ctx.lineWidth = 0.7; ctx.beginPath(); ctx.moveTo(0, 6); ctx.lineTo(0, 18); ctx.stroke();
  ctx.restore();
}

// Her: a paper doll in a white dress with a red ribbon. pose as Simon (fewer joints shown).
// lying: true lays her down (rotated, eyes closed).
export function her(ctx, x, y, h, pose = {}, o = {}) {
  const s = h / 100;
  ctx.save(); ctx.translate(x, y); ctx.scale((o.facing || 1) * s, s);
  if (o.lying) ctx.rotate(-Math.PI / 2 * 0.98);
  const p = { lean: 0, head: 0, armF: [0.2, -0.3], armB: [-0.2, -0.2], legF: [0.05, 0], legB: [-0.05, 0], ...pose };
  const sh = { depth: 3, shadow: o.lying ? 0.15 : 0.35, blur: false };
  const tone = o.sepia ? C.sepia : C.dress, toneLo = o.sepia ? C.sepiaLo : C.dressLo;
  ctx.save(); ctx.rotate(p.lean);
  const arm = (px, py, a1, a2, col) => {
    ctx.save(); ctx.translate(px, py); ctx.rotate(a1);
    const up = new Path2D(); up.roundRect(-2.4, -2, 4.8, 16, 2.4); cut(ctx, up, col, sh);
    ctx.translate(0, 14); ctx.rotate(a2);
    const lo = new Path2D(); lo.roundRect(-2.1, -1, 4.2, 14, 2.1); cut(ctx, lo, C.skin, sh);
    pin(ctx, 0, 0, 1.3); ctx.restore(); pin(ctx, px, py, 1.4);
  };
  arm(-1, -76, p.armB[0], p.armB[1], toneLo);
  // legs under the dress
  for (const [lx, a] of [[-3, p.legB[0]], [3, p.legF[0]]]) {
    ctx.save(); ctx.translate(lx, -36); ctx.rotate(a);
    const lg = new Path2D(); lg.roundRect(-2.3, 0, 4.6, 36, 2.3); cut(ctx, lg, C.skin, sh);
    const sh2 = new Path2D(); sh2.roundRect(-2.6, 33, 8, 4, 2); cut(ctx, sh2, '#5A1A22', sh);
    ctx.restore();
  }
  // dress: fitted bodice, bell skirt
  const dr = new Path2D();
  dr.moveTo(-7, -80); dr.lineTo(7, -80); dr.lineTo(6, -62); dr.quadraticCurveTo(14, -48, 20, -32); dr.quadraticCurveTo(0, -27, -20, -32); dr.quadraticCurveTo(-14, -48, -6, -62); dr.closePath();
  cut(ctx, dr, tone, { depth: 4, shadow: sh.shadow, blur: false });
  ctx.strokeStyle = toneLo; ctx.lineWidth = 0.7;
  for (let k = -2; k <= 2; k++) { ctx.beginPath(); ctx.moveTo(k * 2, -60); ctx.lineTo(k * 6.5, -32); ctx.stroke(); }
  // head + long hair + the red ribbon
  ctx.save(); ctx.translate(0, -82); ctx.rotate(p.head);
  const hairBack = new Path2D(); hairBack.ellipse(-2, -6, 10, 13, 0.1, 0, TAU); hairBack.rect(-11, -6, 13, 24);
  cut(ctx, hairBack, C.hair, { depth: 2, shadow: 0.3, blur: false });
  if (o.ribbon !== false) ribbonBow(ctx, -6, -18, 1, 0);
  const head = new Path2D(); head.ellipse(1, -9, 7.6, 9.2, 0, 0, TAU); cut(ctx, head, C.skin, { depth: 2, shadow: 0.3, blur: false });
  const fringe = new Path2D(); fringe.moveTo(-7, -10); fringe.quadraticCurveTo(-2, -22, 9, -12); fringe.quadraticCurveTo(2, -16, -7, -10); fringe.closePath();
  cut(ctx, fringe, C.hair, { depth: 1, shadow: 0.2, blur: false });
  ctx.fillStyle = '#1B1412'; ctx.strokeStyle = '#1B1412'; ctx.lineWidth = 0.8; ctx.lineCap = 'round';
  if (o.eyesClosed) {
    ctx.beginPath(); ctx.arc(-0.5, -9, 1.4, 0.1, Math.PI - 0.1); ctx.moveTo(5.4, -9); ctx.arc(4, -9, 1.4, 0.1, Math.PI - 0.1); ctx.stroke();
  } else { ctx.beginPath(); ctx.arc(-0.5, -9, 1, 0, TAU); ctx.arc(4, -9, 1, 0, TAU); ctx.fill(); }
  ctx.beginPath(); ctx.arc(2, -4.5, 1.6, 0.2, Math.PI - 0.2); ctx.stroke();
  ctx.fillStyle = 'rgba(220,120,110,0.4)'; ctx.beginPath(); ctx.arc(5.5, -6, 1.5, 0, TAU); ctx.fill();
  ctx.restore();
  arm(1, -76, p.armF[0], p.armF[1], tone);
  ctx.restore();
  ctx.restore();
}

// The red ribbon bow (local units ~ 10 wide). flutter in radians.
export function ribbonBow(ctx, x, y, sc = 1, flutter = 0) {
  ctx.save(); ctx.translate(x, y); ctx.scale(sc, sc); ctx.rotate(flutter * 0.2);
  const b = new Path2D();
  b.moveTo(0, 0); b.bezierCurveTo(-6, -5, -9, -1, -7, 3); b.closePath();
  b.moveTo(0, 0); b.bezierCurveTo(6, -5, 9, -1, 7, 3); b.closePath();
  b.moveTo(0, 0); b.quadraticCurveTo(-3 + flutter * 2, 6, -4 + flutter * 3, 11); b.lineTo(-2 + flutter * 3, 11); b.quadraticCurveTo(-1, 6, 0, 1); b.closePath();
  b.moveTo(0, 0); b.quadraticCurveTo(3 + flutter * 2, 6, 4 + flutter * 3, 10); b.lineTo(6 + flutter * 3, 10); b.quadraticCurveTo(2, 5, 0, 1); b.closePath();
  cut(ctx, b, C.red, { depth: 1.5, shadow: 0.3, blur: false, edge: 'rgba(255,160,160,0.3)', edgeW: 0.5 });
  ctx.fillStyle = C.redLo; ctx.beginPath(); ctx.arc(0, 0.5, 1.4, 0, TAU); ctx.fill();
  ctx.restore();
}

// A paper owl. (x, y) = feet, h = height. eyes 0 (shut) .. 1 (wide). look: pupil offset -1..1.
export function owl(ctx, x, y, h, eyes = 1, look = 0, o = {}) {
  const s = h / 100;
  ctx.save(); ctx.translate(x, y); ctx.scale(s, s); ctx.rotate(o.tilt || 0);
  const body = new Path2D();
  body.moveTo(-30, -10); body.bezierCurveTo(-42, -60, -34, -92, -26, -100); body.lineTo(-14, -86);
  body.quadraticCurveTo(0, -92, 14, -86); body.lineTo(26, -100); body.bezierCurveTo(34, -92, 42, -60, 30, -10);
  body.quadraticCurveTo(0, 6, -30, -10); body.closePath();
  cut(ctx, body, o.col || C.owl, { depth: 4, shadow: 0.45, blur: false, edge: 'rgba(255,230,200,0.15)' });
  // breast scallops
  ctx.fillStyle = o.belly || '#7A6650';
  const belly = new Path2D(); belly.ellipse(0, -30, 20, 26, 0, 0, TAU); ctx.fill(belly);
  ctx.strokeStyle = o.col || C.owl; ctx.lineWidth = 1.6;
  for (let r = 0; r < 4; r++) for (let c = -2; c <= 2; c++) {
    const cx = c * 7 + (r % 2) * 3.5, cy = -46 + r * 10;
    if (Math.hypot(cx / 20, (cy + 30) / 26) > 0.92) continue;
    ctx.beginPath(); ctx.arc(cx, cy, 3.2, 0.1, Math.PI - 0.1); ctx.stroke();
  }
  // wings
  for (const sd of [-1, 1]) {
    const w = new Path2D(); w.moveTo(sd * 28, -70); w.quadraticCurveTo(sd * 40, -40, sd * 26, -6); w.quadraticCurveTo(sd * 22, -40, sd * 28, -70); w.closePath();
    cut(ctx, w, o.wing || C.owlLo, { depth: 2, shadow: 0.3, blur: false });
  }
  // face disc + eyes
  for (const sd of [-1, 1]) {
    const disc = new Path2D(); disc.arc(sd * 12, -68, 13, 0, TAU); cut(ctx, disc, o.face || '#8A7458', { depth: 1.5, shadow: 0.25, blur: false });
    const open = clamp(eyes);
    ctx.save(); ctx.beginPath(); ctx.ellipse(sd * 12, -68, 9, 9 * open + 0.01, 0, 0, TAU); ctx.clip();
    if (o.glow) {
      ctx.save(); ctx.globalCompositeOperation = 'lighter';
      const g = ctx.createRadialGradient(sd * 12, -68, 0, sd * 12, -68, 30); g.addColorStop(0, 'rgba(255,200,80,0.6)'); g.addColorStop(1, 'rgba(255,200,80,0)');
      ctx.fillStyle = g; ctx.fillRect(sd * 12 - 30, -98, 60, 60); ctx.restore();
    }
    ctx.fillStyle = o.eye || C.owlEye; ctx.fillRect(sd * 12 - 10, -78, 20, 20);
    ctx.fillStyle = '#0A0806'; ctx.beginPath(); ctx.arc(sd * 12 + look * 3.5, -68, 4.6, 0, TAU); ctx.fill();
    ctx.fillStyle = '#FFF6D0'; ctx.beginPath(); ctx.arc(sd * 12 + look * 3.5 - 1.6, -70, 1.3, 0, TAU); ctx.fill();
    ctx.restore();
    if (open < 0.98) { ctx.strokeStyle = '#2A2018'; ctx.lineWidth = 1.4; ctx.beginPath(); ctx.ellipse(sd * 12, -68, 9, 9 * open + 0.01, 0, 0, Math.PI); ctx.stroke(); }
  }
  // beak + brows
  ctx.fillStyle = '#E0A33A'; ctx.beginPath(); ctx.moveTo(-3, -62); ctx.lineTo(3, -62); ctx.lineTo(0, -54); ctx.closePath(); ctx.fill();
  ctx.strokeStyle = o.col || C.owl; ctx.lineWidth = 3; ctx.beginPath(); ctx.moveTo(-24, -84 + (o.stern || 0) * 3); ctx.lineTo(-4, -78); ctx.moveTo(24, -84 + (o.stern || 0) * 3); ctx.lineTo(4, -78); ctx.stroke();
  // feet
  ctx.fillStyle = '#C08A30'; for (const sd of [-1, 1]) for (let k = -1; k <= 1; k++) { ctx.beginPath(); ctx.ellipse(sd * 10 + k * 3, -2, 1.6, 4, 0, 0, TAU); ctx.fill(); }
  if (o.wig) {
    // a magistrate's curled wig for the owl judge
    ctx.fillStyle = '#E9E4DA';
    for (const sd of [-1, 1]) for (let k = 0; k < 4; k++) { ctx.beginPath(); ctx.ellipse(sd * (30 + k * 1.5), -80 + k * 13, 8, 6.5, 0, 0, TAU); ctx.fill(); ctx.strokeStyle = '#B8B2A6'; ctx.lineWidth = 1; ctx.stroke(); }
    ctx.beginPath(); ctx.ellipse(0, -96, 28, 9, 0, Math.PI, 0); ctx.fill();
  }
  ctx.restore();
}

// A hand mirror hanging from a thread: oval glass, ornate rim. reflect(ctx, rx, ry) draws inside.
export function mirror(ctx, x, y, w, h, o = {}, reflect = null) {
  ctx.save(); ctx.translate(x, y); ctx.rotate(o.swing || 0);
  ctx.strokeStyle = 'rgba(220,220,230,0.6)'; ctx.lineWidth = 1; ctx.beginPath(); ctx.moveTo(0, -(o.thread ?? 400)); ctx.lineTo(0, -h / 2 - 6); ctx.stroke();
  const rim = new Path2D(); rim.ellipse(0, 0, w / 2 + 10, h / 2 + 10, 0, 0, TAU);
  cut(ctx, rim, C.gold, { depth: 5, shadow: 0.45, blur: false, edge: C.goldHi });
  ctx.save(); ctx.beginPath(); ctx.ellipse(0, 0, w / 2, h / 2, 0, 0, TAU); ctx.clip();
  const g = ctx.createLinearGradient(-w / 2, -h / 2, w / 2, h / 2);
  g.addColorStop(0, '#9FB3D6'); g.addColorStop(0.5, '#3B4A72'); g.addColorStop(1, '#141A33');
  ctx.fillStyle = g; ctx.fillRect(-w / 2, -h / 2, w, h);
  if (reflect) reflect(ctx, w, h);
  ctx.fillStyle = 'rgba(255,255,255,0.18)'; ctx.beginPath(); ctx.moveTo(-w * 0.45, -h * 0.1); ctx.lineTo(-w * 0.1, -h * 0.5); ctx.lineTo(w * 0.05, -h * 0.5); ctx.lineTo(-w * 0.4, h * 0.05); ctx.closePath(); ctx.fill();
  if (o.crack > 0) {
    ctx.strokeStyle = `rgba(255,255,255,${0.8 * o.crack})`; ctx.lineWidth = 1.5;
    const r = mulberry32(o.seed || 3);
    for (let k = 0; k < 9; k++) {
      ctx.beginPath(); let cx = w * 0.1, cy = -h * 0.05; ctx.moveTo(cx, cy);
      const a = (k / 9) * TAU + r(); for (let j = 0; j < 4; j++) { cx += Math.cos(a + (r() - 0.5)) * w * 0.14 * o.crack; cy += Math.sin(a + (r() - 0.5)) * h * 0.14 * o.crack; ctx.lineTo(cx, cy); }
      ctx.stroke();
    }
  }
  ctx.restore();
  ctx.restore();
}

// Simon's face, large, for reflections and close-ups. expr: 'calm' | 'fear' | 'grief'
export function face(ctx, x, y, r, expr = 'fear', o = {}) {
  ctx.save(); ctx.translate(x, y); ctx.scale(r / 10, r / 10); ctx.rotate(o.tilt || 0);
  if (o.stretch) ctx.scale(1, o.stretch);
  const head = new Path2D(); head.ellipse(0, 0, 8.5, 10, 0, 0, TAU);
  cut(ctx, head, o.skin || C.skin, { depth: 1.2, shadow: 0.35, blur: false });
  const hair = new Path2D();
  hair.moveTo(-9, 1); hair.lineTo(-10, -6); hair.lineTo(-6, -5); hair.lineTo(-7, -11); hair.lineTo(-2, -8); hair.lineTo(0, -13);
  hair.lineTo(3, -8); hair.lineTo(8, -11); hair.lineTo(7, -6); hair.lineTo(10, -5); hair.lineTo(9, 0); hair.quadraticCurveTo(1, -6, -9, 1); hair.closePath();
  cut(ctx, hair, '#1B1412', { depth: 0.8, shadow: 0.3, blur: false });
  ctx.fillStyle = '#1B1412'; ctx.strokeStyle = '#1B1412'; ctx.lineCap = 'round'; ctx.lineWidth = 0.6;
  const wide = expr === 'fear' ? 1.6 : 1;
  ctx.beginPath(); ctx.ellipse(-3, 0, 0.9, 1.2 * wide, 0, 0, TAU); ctx.ellipse(3, 0, 0.9, 1.2 * wide, 0, 0, TAU); ctx.fill();
  if (expr === 'grief') { ctx.beginPath(); ctx.moveTo(-5, -3); ctx.lineTo(-1.5, -2); ctx.moveTo(5, -3); ctx.lineTo(1.5, -2); ctx.stroke(); ctx.beginPath(); ctx.arc(0, 6.5, 2.2, Math.PI * 1.15, Math.PI * 1.85); ctx.stroke(); }
  else if (expr === 'fear') { ctx.beginPath(); ctx.moveTo(-5, -4.2); ctx.lineTo(-1.6, -3); ctx.moveTo(5, -4.2); ctx.lineTo(1.6, -3); ctx.stroke(); ctx.beginPath(); ctx.ellipse(0, 5, 1.6, 2.2, 0, 0, TAU); ctx.fill(); }
  else { ctx.beginPath(); ctx.moveTo(-1.5, 5); ctx.lineTo(1.5, 5); ctx.stroke(); }
  if (o.tear) { ctx.fillStyle = 'rgba(180,210,255,0.9)'; ctx.beginPath(); ctx.ellipse(-3.4, 2.5 + o.tear * 4, 0.6, 0.9, 0, 0, TAU); ctx.fill(); }
  ctx.restore();
}

// Ornate gilded picture frame (outer rect x, y, w, h; border b). It frames whatever is behind.
export function frame(ctx, x, y, w, h, b, o = {}) {
  ctx.save();
  const outer = new Path2D(); outer.rect(x, y, w, h); outer.rect(x + b, y + b, w - 2 * b, h - 2 * b);
  ctx.save(); ctx.translate(6, 9); ctx.fillStyle = 'rgba(0,0,0,0.45)'; ctx.fill(outer, 'evenodd'); ctx.restore();
  const g = ctx.createLinearGradient(x, y, x + w, y + h);
  g.addColorStop(0, C.goldHi); g.addColorStop(0.3, C.gold); g.addColorStop(0.6, C.goldLo); g.addColorStop(1, C.gold);
  ctx.fillStyle = g; ctx.fill(outer, 'evenodd');
  // moulding lines
  ctx.strokeStyle = 'rgba(60,40,10,0.6)'; ctx.lineWidth = Math.max(1, b * 0.05);
  for (const k of [0.25, 0.55, 0.8]) { const d = b * k; ctx.strokeRect(x + d, y + d, w - 2 * d, h - 2 * d); }
  // corner rosettes
  for (const [cx, cy] of [[x + b / 2, y + b / 2], [x + w - b / 2, y + b / 2], [x + b / 2, y + h - b / 2], [x + w - b / 2, y + h - b / 2]]) {
    ctx.fillStyle = C.goldHi; ctx.beginPath();
    for (let k = 0; k < 10; k++) { const a = (k / 10) * TAU, rr = (k % 2 ? 0.22 : 0.42) * b; ctx.lineTo(cx + Math.cos(a) * rr, cy + Math.sin(a) * rr); }
    ctx.closePath(); ctx.fill(); ctx.fillStyle = C.goldLo; ctx.beginPath(); ctx.arc(cx, cy, b * 0.12, 0, TAU); ctx.fill();
  }
  if (o.label) {
    const lw = Math.min(w * 0.5, 280), lh = b * 0.55;
    ctx.fillStyle = C.goldHi; ctx.fillRect(x + w / 2 - lw / 2, y + h - b / 2 - lh / 2, lw, lh);
    ctx.fillStyle = '#3A2A0A'; ctx.font = `600 ${Math.round(lh * 0.55)}px Display`; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.fillText(o.label, x + w / 2, y + h - b / 2 + 1); ctx.textBaseline = 'alphabetic';
  }
  ctx.restore();
}

// A villager silhouette with a lantern (search party). (x, y) feet; h height; phase walk.
export function villager(ctx, x, y, h, phase, col = '#090A14', glow = 1, seed = 1) {
  const s = h / 100, sw = Math.sin(phase * TAU) * 0.3;
  ctx.save(); ctx.translate(x, y); ctx.scale(s, s);
  ctx.fillStyle = col;
  ctx.beginPath(); ctx.moveTo(-14, -78); ctx.lineTo(14, -78); ctx.lineTo(20, -10); ctx.lineTo(-20, -10); ctx.closePath(); ctx.fill();
  ctx.save(); ctx.translate(-5, -12); ctx.rotate(sw); ctx.fillRect(-4, 0, 8, 12); ctx.restore();
  ctx.save(); ctx.translate(5, -12); ctx.rotate(-sw); ctx.fillRect(-4, 0, 8, 12); ctx.restore();
  ctx.beginPath(); ctx.arc(0, -88, 10, 0, TAU); ctx.fill();
  if (hash01(seed, 9) < 0.5) { ctx.fillRect(-16, -98, 32, 4); ctx.fillRect(-9, -112, 18, 15); } // hat
  ctx.save(); ctx.translate(16, -62); ctx.rotate(-0.4 + sw * 0.3); ctx.fillRect(-3, 0, 6, 26); ctx.restore();
  ctx.restore();
  lanternAt(ctx, x + 22 * s, y - 38 * s, s * 2, glow, sw * 0.2);
}

// Falling snow (seeded flakes), t in seconds.
export function snow(ctx, W, H, t, n = 220, amt = 1, seed = 5) {
  if (amt <= 0) return;
  ctx.save(); ctx.fillStyle = C.snow;
  for (let i = 0; i < n * amt; i++) {
    const z = 0.3 + hash01(i, seed) * 0.7, sp = 40 + 70 * z;
    const x = (hash01(i, seed + 1) * W + Math.sin(t * 0.7 + i) * 30 * z + t * 12) % (W + 40) - 20;
    const y = (hash01(i, seed + 2) * H + t * sp) % (H + 40) - 20;
    ctx.globalAlpha = 0.35 + 0.6 * z; ctx.beginPath(); ctx.arc(x, y, 1.2 + 2.6 * z, 0, TAU); ctx.fill();
  }
  ctx.restore();
}

// Paper flowers (white, five petals) for the clearing.
export function flower(ctx, x, y, r, col = '#F6F2EA', centre = '#E8C35A', rot = 0) {
  ctx.save(); ctx.translate(x, y); ctx.rotate(rot);
  for (let k = 0; k < 5; k++) { ctx.save(); ctx.rotate((k / 5) * TAU); ctx.fillStyle = col; ctx.beginPath(); ctx.ellipse(0, -r * 0.55, r * 0.32, r * 0.55, 0, 0, TAU); ctx.fill(); ctx.restore(); }
  ctx.fillStyle = centre; ctx.beginPath(); ctx.arc(0, 0, r * 0.22, 0, TAU); ctx.fill();
  ctx.restore();
}

// ------------------------------------------------------------------ the theatre

// Proscenium of a toy theatre, drawn over the scene. open 0 (curtains shut) .. 1 (fully open).
export function proscenium(ctx, W, H, open, o = {}) {
  const inset = o.inset ?? 1;   // 1 = full theatre visible, larger values push the arch off-screen
  ctx.save();
  ctx.translate(W / 2, H / 2); ctx.scale(inset, inset); ctx.translate(-W / 2, -H / 2);
  const ax = 210, ay = 120, aw = W - 420, ah = H - 230;
  // curtains (velvet as pleated paper)
  const half = (aw / 2) * (1 - clamp(open) * 0.92);
  for (const side of [-1, 1]) {
    const x0 = side < 0 ? ax : ax + aw - half;
    const pleats = 9;
    for (let k = 0; k < pleats; k++) {
      const px = x0 + (k / pleats) * half, pw = half / pleats + 1;
      const sway = Math.sin((o.t || 0) * 0.8 + k) * 2;
      const g = ctx.createLinearGradient(px, 0, px + pw, 0);
      g.addColorStop(0, '#5A0613'); g.addColorStop(0.5, '#A3122A'); g.addColorStop(1, '#4A0410');
      ctx.fillStyle = g; ctx.fillRect(px + sway, ay, pw, ah);
    }
    // tie-back swag when open
  }
  // valance with scallops
  ctx.fillStyle = '#8E0F24';
  ctx.beginPath(); ctx.moveTo(ax, ay - 10); ctx.lineTo(ax + aw, ay - 10); ctx.lineTo(ax + aw, ay + 60);
  for (let k = 12; k >= 0; k--) { const x = ax + (k / 12) * aw; ctx.quadraticCurveTo(x + aw / 24, ay + 95, x, ay + 60); }
  ctx.closePath(); ctx.fill();
  ctx.strokeStyle = C.gold; ctx.lineWidth = 4; ctx.stroke();
  // the arch frame (cut card, gold)
  const fr = new Path2D();
  fr.rect(-50, -50, W + 100, H + 100);
  fr.moveTo(ax, ay + ah); fr.lineTo(ax, ay + 80); fr.quadraticCurveTo(ax, ay - 20, ax + 140, ay - 30); fr.lineTo(ax + aw - 140, ay - 30);
  fr.quadraticCurveTo(ax + aw, ay - 20, ax + aw, ay + 80); fr.lineTo(ax + aw, ay + ah); fr.closePath();
  ctx.save(); ctx.fillStyle = '#100A10'; ctx.fill(fr, 'evenodd'); ctx.restore();
  ctx.strokeStyle = C.gold; ctx.lineWidth = 10;
  ctx.beginPath(); ctx.moveTo(ax - 6, ay + ah); ctx.lineTo(ax - 6, ay + 80); ctx.quadraticCurveTo(ax - 6, ay - 26, ax + 140, ay - 36); ctx.lineTo(ax + aw - 140, ay - 36);
  ctx.quadraticCurveTo(ax + aw + 6, ay - 26, ax + aw + 6, ay + 80); ctx.lineTo(ax + aw + 6, ay + ah); ctx.stroke();
  // crest: an owl medallion
  ctx.save(); ctx.translate(W / 2, ay - 58);
  ctx.fillStyle = C.goldLo; ctx.beginPath(); ctx.arc(0, 0, 52, 0, TAU); ctx.fill();
  ctx.fillStyle = C.gold; ctx.beginPath(); ctx.arc(0, 0, 44, 0, TAU); ctx.fill();
  owl(ctx, 0, 34, 70, o.crestEyes ?? 1, 0, { col: C.goldLo, belly: C.goldHi, face: C.goldHi, wing: C.goldLo, eye: '#2A1A06' });
  ctx.restore();
  // stage floor + footlights
  ctx.fillStyle = '#2A1A10'; ctx.fillRect(ax - 30, ay + ah, aw + 60, 40);
  ctx.fillStyle = '#4A3020'; for (let x = ax - 30; x < ax + aw + 30; x += 60) ctx.fillRect(x, ay + ah, 2, 40);
  for (let k = 0; k < 9; k++) {
    const fx = ax + 60 + k * (aw - 120) / 8, fy = ay + ah + 12;
    ctx.save(); ctx.globalCompositeOperation = 'lighter';
    const g = ctx.createRadialGradient(fx, fy, 0, fx, fy, 90); g.addColorStop(0, `rgba(255,200,120,${0.45 * (o.lights ?? 1)})`); g.addColorStop(1, 'rgba(255,200,120,0)');
    ctx.fillStyle = g; ctx.fillRect(fx - 90, fy - 90, 180, 180); ctx.restore();
    ctx.fillStyle = '#FFE7B0'; ctx.beginPath(); ctx.ellipse(fx, fy, 14, 6, 0, Math.PI, 0); ctx.fill();
  }
  if (o.title) {
    ctx.fillStyle = C.goldHi; ctx.font = '700 30px Display'; ctx.textAlign = 'center'; ctx.letterSpacing = '8px';
    ctx.fillText(o.title, W / 2 + 4, ay + ah + 32); ctx.letterSpacing = '0px';
  }
  ctx.restore();
}

// The evidence board: dark card, pinned paper clues, red thread to a centre card.
// items: [{x, y, w, h, rot, draw(ctx, w, h)}]; centre: [x, y]; thread 0..1 strung.
export function evidence(ctx, items, centre, thread, t = 0) {
  for (const it of items) {
    ctx.save(); ctx.translate(it.x, it.y); ctx.rotate(it.rot || 0); ctx.scale(it.s ?? 1, it.s ?? 1);
    const card = new Path2D(); card.rect(-it.w / 2, -it.h / 2, it.w, it.h);
    cut(ctx, card, it.bg || C.paper, { depth: 6, shadow: 0.5, blur: false, edge: 'rgba(0,0,0,0.2)' });
    if (it.draw) it.draw(ctx, it.w, it.h);
    ctx.restore();
  }
  // threads from each item to the centre
  ctx.save(); ctx.strokeStyle = C.red; ctx.lineWidth = 3; ctx.lineCap = 'round';
  items.forEach((it, i) => {
    const k = clamp(thread * items.length - i);
    if (k <= 0) return;
    const sx = it.x, sy = it.y - (it.h / 2) * (it.s ?? 1) + 14;
    const ex = lerp(sx, centre[0], k), ey = lerp(sy, centre[1], k);
    const sag = 30 * Math.sin(Math.PI * k);
    ctx.beginPath(); ctx.moveTo(sx, sy); ctx.quadraticCurveTo((sx + ex) / 2, (sy + ey) / 2 + sag, ex, ey); ctx.stroke();
    pin(ctx, sx, sy, 7);
  });
  ctx.restore();
}

// The owl court's bench: a tall stacked-paper desk with a carved front. (x, y) = floor centre.
export function bench(ctx, x, y, w, h) {
  const b = new Path2D(); b.rect(x - w / 2, y - h, w, h);
  cut(ctx, b, '#3A2418', { depth: 10, shadow: 0.5, blur: false, edge: 'rgba(255,200,150,0.15)' });
  ctx.fillStyle = '#4C3020'; ctx.fillRect(x - w / 2 - 20, y - h - 24, w + 40, 26);
  ctx.strokeStyle = '#2A180E'; ctx.lineWidth = 4;
  for (let k = 1; k < 4; k++) ctx.strokeRect(x - w / 2 + k * w / 4 - w / 10, y - h + 40, w / 5, h - 80);
  // scales of justice inlay
  ctx.save(); ctx.translate(x, y - h * 0.55); ctx.strokeStyle = C.gold; ctx.lineWidth = 4;
  ctx.beginPath(); ctx.moveTo(0, -60); ctx.lineTo(0, 40); ctx.moveTo(-60, -40); ctx.lineTo(60, -40); ctx.stroke();
  for (const sd of [-1, 1]) { ctx.beginPath(); ctx.moveTo(sd * 60, -40); ctx.lineTo(sd * 45, 0); ctx.lineTo(sd * 75, 0); ctx.closePath(); ctx.stroke(); ctx.beginPath(); ctx.arc(sd * 60, 0, 16, 0, Math.PI); ctx.stroke(); }
  ctx.restore();
}
