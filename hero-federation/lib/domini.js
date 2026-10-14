// domini.js: the Domini's characters and signs, drawn from the lore's descriptions and the user's
// reference of Emperyan, in this film's own illustrated style (not copies of any game model).
// Every function is pure: same arguments, same pixels.

import { TAU, clamp, lerp } from './motion.js';

export const DP = {
  void: '#000000', night: '#070A14', night2: '#0E1426', night3: '#1A2440',
  white: '#F4F5F8', cloth: '#E9EBF0', shade: '#B9BFCC', shade2: '#8A91A0',
  cobalt: '#2F5BD8', cobaltHi: '#5C86F2', cobaltLo: '#1A3488',
  gold: '#D9AE52', goldHi: '#F6DE9A', goldLo: '#8E6A26',
  ring: '#26272C', ringHi: '#9A9CA4', silver: '#D3D7E0', silverLo: '#7E8494',
  skin: '#EBDCC2', skinLo: '#CDB894', mouth: '#D3263B',
  frost: '#9ED8FF', frostLo: '#2B6CA8', ember: '#E2452B', emberLo: '#6E1209', emberHi: '#FFB15C',
  sun: '#FFE7A0', ivory: '#F1E6CF', ink: '#05070D', azure: '#59C8FF',
};
export const HOUSE = {
  frigidus: { cloth: '#DDEBF5', shade: '#8FB3CF', trim: DP.frost, tip: DP.frostLo, sigil: 'crystal' },
  infernus: { cloth: '#2A1416', shade: '#140809', trim: DP.ember, tip: DP.ember, sigil: 'flame' },
  empyerus: { cloth: DP.white, shade: DP.shade, trim: DP.gold, tip: DP.cobalt, sigil: 'sun' },
  plain: { cloth: '#1B2133', shade: '#0B0F1A', trim: DP.goldLo, tip: DP.cobaltLo, sigil: null },
};

const lin = (ctx, x0, y0, x1, y1, stops) => { const g = ctx.createLinearGradient(x0, y0, x1, y1); stops.forEach(([o, c]) => g.addColorStop(o, c)); return g; };
const rad = (ctx, x, y, r0, r1, stops, fx = x, fy = y) => { const g = ctx.createRadialGradient(fx, fy, r0, x, y, r1); stops.forEach(([o, c]) => g.addColorStop(o, c)); return g; };

// ------------------------------------------------------------------ parts

// Heavy dark shoulder ring (a torus seen nearly face-on).
export function ring(ctx, x, y, R, tilt = 0, col = DP.ring, hi = DP.ringHi) {
  ctx.save(); ctx.translate(x, y); ctx.rotate(tilt);
  ctx.beginPath(); ctx.ellipse(0, 0, R, R * 0.9, 0, 0, TAU); ctx.ellipse(R * 0.06, R * 0.04, R * 0.44, R * 0.4, 0, 0, TAU, true);
  ctx.fillStyle = rad(ctx, 0, 0, R * 0.3, R, [[0, '#4A4C54'], [0.55, col], [1, '#0E0F12']], -R * 0.35, -R * 0.4);
  ctx.fill('evenodd');
  ctx.lineWidth = R * 0.08; ctx.strokeStyle = hi; ctx.globalAlpha *= 0.55;
  ctx.beginPath(); ctx.ellipse(0, 0, R * 0.78, R * 0.7, 0, Math.PI * 1.05, Math.PI * 1.6); ctx.stroke();
  ctx.globalAlpha /= 0.55;
  ctx.beginPath(); ctx.ellipse(R * 0.06, R * 0.04, R * 0.44, R * 0.4, 0, 0, TAU); ctx.fillStyle = '#050507'; ctx.fill();
  ctx.beginPath(); ctx.ellipse(R * 0.1, R * 0.08, R * 0.26, R * 0.22, 0, 0, TAU); ctx.fillStyle = '#2E3038'; ctx.fill();
  ctx.restore();
}

// One wing of long white feathers with coloured tips. Root at (x, y); side -1 left, +1 right.
// spread 0..1 opens the fan; len in px.
export function wing(ctx, x, y, side, spread, len, o = {}) {
  const tip = o.tip || DP.cobalt, base = o.base || DP.white, sh = o.shade || DP.shade;
  const N = o.n || 11;
  ctx.save(); ctx.translate(x, y); ctx.scale(side, 1);
  const rows = [[1.0, 0], [0.62, 1]];
  for (const [lk, row] of rows) {
    for (let k = 0; k < N; k++) {
      const t = k / (N - 1);
      const a = -lerp(-0.32, 1.25, t) * (0.25 + 0.75 * spread) - 0.08;
      const L = len * lk * (0.62 + 0.38 * Math.sin(Math.PI * (0.25 + t * 0.6)));
      const w = len * 0.075 * (row ? 1.2 : 1);
      ctx.save(); ctx.rotate(a);
      ctx.beginPath();
      ctx.moveTo(0, -w * 0.5); ctx.quadraticCurveTo(L * 0.55, -w * 0.9, L, -w * 0.15); ctx.quadraticCurveTo(L * 1.02, w * 0.2, L * 0.92, w * 0.5);
      ctx.quadraticCurveTo(L * 0.5, w * 0.8, 0, w * 0.5); ctx.closePath();
      ctx.fillStyle = row ? lin(ctx, 0, 0, L, 0, [[0, sh], [0.5, base], [1, base]]) : lin(ctx, 0, 0, L, 0, [[0, sh], [0.55, base], [0.74, base], [0.86, tip], [1, tip]]);
      ctx.fill();
      ctx.strokeStyle = 'rgba(40,50,80,0.25)'; ctx.lineWidth = len * 0.004; ctx.stroke();
      ctx.restore();
    }
  }
  ctx.restore();
}

// The Lord of the Federation crown, front view. Base centre (cx, cy), band width w.
// Gold band with cobalt octagon gems, a tall cobalt four-point star, gold crescents.
export function lordCrown(ctx, cx, cy, w, o = {}) {
  const h = w * 0.17;
  ctx.save(); ctx.translate(cx, cy);
  const crescent = (x, y, r, rot) => {
    ctx.save(); ctx.translate(x, y); ctx.rotate(rot);
    ctx.beginPath(); ctx.arc(0, 0, r, 0, TAU); ctx.arc(r * 0.32, -r * 0.18, r * 0.78, 0, TAU, true);
    ctx.fillStyle = lin(ctx, -r, -r, r, r, [[0, DP.goldHi], [0.6, DP.gold], [1, DP.goldLo]]); ctx.fill('evenodd');
    ctx.restore();
  };
  crescent(w * 0.2, -h - w * 0.13, w * 0.12, -0.5);
  crescent(w * 0.36, -h - w * 0.06, w * 0.09, -0.2);
  crescent(-w * 0.3, -h - w * 0.08, w * 0.1, -0.9);
  // band (a shallow ellipse slice so it reads as round)
  ctx.beginPath();
  ctx.moveTo(-w / 2, -h); ctx.quadraticCurveTo(0, -h + w * 0.06, w / 2, -h);
  ctx.lineTo(w / 2, 0); ctx.quadraticCurveTo(0, w * 0.07, -w / 2, 0); ctx.closePath();
  ctx.fillStyle = lin(ctx, -w / 2, 0, w / 2, 0, [[0, DP.goldLo], [0.3, DP.goldHi], [0.55, DP.gold], [1, DP.goldLo]]); ctx.fill();
  ctx.strokeStyle = DP.goldLo; ctx.lineWidth = w * 0.008; ctx.stroke();
  // octagon gems
  for (let i = -3; i <= 3; i++) {
    if (i === 0) continue;
    const gx = i * w * 0.13, gy = -h / 2 + w * 0.025 * (1 - (i / 3) ** 2), r = w * (i % 2 ? 0.045 : 0.03);
    ctx.beginPath();
    for (let k = 0; k < 8; k++) { const a = (k / 8) * TAU + Math.PI / 8; ctx.lineTo(gx + Math.cos(a) * r * 1.25, gy + Math.sin(a) * r * 1.25); }
    ctx.closePath(); ctx.fillStyle = DP.gold; ctx.fill();
    ctx.beginPath();
    for (let k = 0; k < 8; k++) { const a = (k / 8) * TAU + Math.PI / 8; ctx.lineTo(gx + Math.cos(a) * r, gy + Math.sin(a) * r); }
    ctx.closePath(); ctx.fillStyle = rad(ctx, gx, gy, 0, r, [[0, DP.cobaltHi], [1, DP.cobaltLo]], gx - r * 0.3, gy - r * 0.3); ctx.fill();
  }
  // the four-point star, tall, rising from the band and dipping onto the brow
  const sx = -w * 0.06, sTop = -h - w * 0.78, sBot = o.starDip ?? w * 0.22, sw = w * 0.17, smid = -h - w * 0.08;
  ctx.beginPath();
  ctx.moveTo(sx, sTop); ctx.quadraticCurveTo(sx + sw * 0.22, smid - w * 0.1, sx + sw, smid);
  ctx.quadraticCurveTo(sx + sw * 0.22, smid + w * 0.1, sx, sBot);
  ctx.quadraticCurveTo(sx - sw * 0.22, smid + w * 0.1, sx - sw, smid);
  ctx.quadraticCurveTo(sx - sw * 0.22, smid - w * 0.1, sx, sTop); ctx.closePath();
  ctx.fillStyle = lin(ctx, sx - sw, 0, sx + sw, 0, [[0, DP.cobaltLo], [0.45, DP.cobaltHi], [0.55, DP.cobalt], [1, DP.cobaltLo]]); ctx.fill();
  ctx.lineWidth = w * 0.018; ctx.strokeStyle = DP.gold; ctx.stroke();
  ctx.beginPath(); ctx.moveTo(sx, sTop + w * 0.08); ctx.lineTo(sx, sBot - w * 0.05); ctx.strokeStyle = 'rgba(160,190,255,0.5)'; ctx.lineWidth = w * 0.008; ctx.stroke();
  ctx.restore();
}

// The Empyrean Sword, hilt (pommel) at (x, y), blade along angle ang, total length L.
export function empyreanSword(ctx, x, y, L, ang, o = {}) {
  ctx.save(); ctx.translate(x, y); ctx.rotate(ang);
  const glow = o.glow || 0;
  // blade
  const b0 = L * 0.33, bw = L * 0.055;
  ctx.beginPath();
  ctx.moveTo(b0, -bw); ctx.lineTo(L * 0.62, -bw * 1.12); ctx.lineTo(L * 0.66, -bw * 0.85); ctx.lineTo(L * 0.78, -bw * 0.95); ctx.lineTo(L * 0.82, -bw * 0.7);
  ctx.lineTo(L, 0);
  ctx.lineTo(L * 0.82, bw * 0.7); ctx.lineTo(L * 0.78, bw * 0.95); ctx.lineTo(L * 0.66, bw * 0.85); ctx.lineTo(L * 0.62, bw * 1.12); ctx.lineTo(b0, bw); ctx.closePath();
  ctx.fillStyle = lin(ctx, 0, -bw, 0, bw, [[0, '#FFFFFF'], [0.45, DP.silver], [0.55, '#A9AFBD'], [1, DP.silverLo]]); ctx.fill();
  ctx.strokeStyle = o.edge || 'rgba(60,66,80,0.6)'; ctx.lineWidth = Math.max(1, L * (o.edge ? 0.006 : 0.004)); ctx.stroke();
  ctx.beginPath(); ctx.moveTo(b0 + L * 0.02, 0); ctx.lineTo(L * 0.9, 0); ctx.strokeStyle = 'rgba(90,96,112,0.7)'; ctx.lineWidth = Math.max(1, L * 0.009); ctx.stroke();
  if (glow > 0) {
    ctx.save(); ctx.globalCompositeOperation = 'lighter'; ctx.globalAlpha *= glow;
    ctx.fillStyle = rad(ctx, L * 0.65, 0, 0, L * 0.45, [[0, 'rgba(255,240,200,0.9)'], [1, 'rgba(255,240,200,0)']]);
    ctx.fillRect(b0 - L * 0.1, -L * 0.3, L * 0.8, L * 0.6); ctx.restore();
  }
  // crystal-feather clusters at the guard ends (behind the guard)
  for (const s of [-1, 1]) {
    const kx = L * 0.3, ky = s * L * 0.12;
    for (let k = 0; k < 3; k++) {
      const a = s * (0.55 + k * 0.38) + Math.PI * 0.98;
      ctx.save(); ctx.translate(kx, ky); ctx.rotate(-a + Math.PI);
      ctx.beginPath(); ctx.moveTo(0, -L * 0.012); ctx.lineTo(L * 0.13, -L * 0.016); ctx.lineTo(L * 0.16, 0); ctx.lineTo(L * 0.13, L * 0.016); ctx.lineTo(0, L * 0.012); ctx.closePath();
      ctx.fillStyle = lin(ctx, 0, 0, L * 0.16, 0, [[0, '#AEB5C4'], [1, '#FFFFFF']]); ctx.fill();
      ctx.restore();
    }
    ctx.beginPath(); ctx.arc(kx, ky, L * 0.03, 0, TAU); ctx.fillStyle = DP.ring; ctx.fill();
    ctx.beginPath(); ctx.arc(kx, ky, L * 0.016, 0, TAU); ctx.fillStyle = '#4A4C54'; ctx.fill();
  }
  // guard arms + triangle with a dark gem
  ctx.fillStyle = DP.silver;
  ctx.fillRect(L * 0.29, -L * 0.12, L * 0.02, L * 0.24);
  ctx.beginPath(); ctx.moveTo(L * 0.28, -L * 0.065); ctx.lineTo(L * 0.39, 0); ctx.lineTo(L * 0.28, L * 0.065); ctx.closePath();
  ctx.fillStyle = lin(ctx, L * 0.28, 0, L * 0.39, 0, [[0, '#FFFFFF'], [1, DP.silverLo]]); ctx.fill();
  ctx.beginPath(); ctx.moveTo(L * 0.295, -L * 0.03); ctx.lineTo(L * 0.345, 0); ctx.lineTo(L * 0.295, L * 0.03); ctx.closePath(); ctx.fillStyle = '#3A2A33'; ctx.fill();
  // grip: segmented
  for (let i = 0; i < 6; i++) {
    const gx = L * (0.07 + i * 0.035);
    ctx.fillStyle = i % 2 ? '#C3C8D2' : '#E9ECF2';
    ctx.beginPath(); ctx.roundRect(gx, -L * 0.022, L * 0.033, L * 0.044, L * 0.008); ctx.fill();
  }
  ctx.fillStyle = '#222'; ctx.fillRect(L * 0.06, -L * 0.012, L * 0.22, L * 0.004);
  // ring pommel
  ctx.beginPath(); ctx.arc(L * 0.03, 0, L * 0.038, 0, TAU); ctx.arc(L * 0.03, 0, L * 0.02, 0, TAU, true); ctx.fillStyle = DP.silver; ctx.fill('evenodd');
  ctx.beginPath(); ctx.arc(L * 0.03, 0, L * 0.02, 0, TAU); ctx.fillStyle = '#5A4E58'; ctx.fill();
  ctx.restore();
}

// ------------------------------------------------------------------ characters

// The hood opening shape (unit coords around the void centre).
function voidPath(ctx) {
  ctx.moveTo(0, -0.62);
  ctx.bezierCurveTo(0.38, -0.62, 0.5, -0.15, 0.44, 0.2);
  ctx.bezierCurveTo(0.4, 0.45, 0.2, 0.52, 0, 0.52);
  ctx.bezierCurveTo(-0.2, 0.52, -0.4, 0.45, -0.44, 0.2);
  ctx.bezierCurveTo(-0.5, -0.15, -0.38, -0.62, 0, -0.62);
  ctx.closePath();
}

// A hooded dominus, front bust. (cx, cy) = centre of the hood's shadow, s = scale (hood ~2s tall).
// o: house, wings (0..1 spread, 0 = none), smile (0..1 glow), eyes ({col, angry}), rings, scarf, crownOnHood
export function hoodBust(ctx, cx, cy, s, o = {}) {
  const H = HOUSE[o.house || 'empyerus'];
  const cloth = o.cloth || H.cloth, shade = o.shade || H.shade;
  ctx.save(); ctx.translate(cx, cy); ctx.scale(s, s);
  if (o.wings) {
    wing(ctx, -0.55, 0.55, -1, o.wings, 2.4, { tip: o.tip || H.tip });
    wing(ctx, 0.55, 0.55, 1, o.wings, 2.4, { tip: o.tip || H.tip });
  }
  // cape / shoulders
  ctx.beginPath();
  ctx.moveTo(-1.1, 1.9); ctx.lineTo(-0.98, 0.78); ctx.quadraticCurveTo(-0.88, 0.45, -0.45, 0.38); ctx.lineTo(0.45, 0.38);
  ctx.quadraticCurveTo(0.88, 0.45, 0.98, 0.78); ctx.lineTo(1.1, 1.9); ctx.closePath();
  ctx.fillStyle = lin(ctx, -1, 0, 1, 0, [[0, shade], [0.4, cloth], [0.7, cloth], [1, shade]]); ctx.fill();
  // pattern band down the chest (the outfit's black-and-gold trim, simplified)
  if (o.trimBand !== false) {
    ctx.fillStyle = o.house === 'infernus' ? DP.emberLo : '#1C1E26';
    ctx.fillRect(-0.12, 0.6, 0.24, 1.3);
    ctx.strokeStyle = H.trim; ctx.lineWidth = 0.025;
    for (let y = 0.7; y < 1.9; y += 0.14) { ctx.beginPath(); ctx.moveTo(-0.1, y); ctx.lineTo(0, y + 0.06); ctx.lineTo(0.1, y); ctx.stroke(); }
  }
  // scarf
  if (o.scarf !== false) {
    ctx.fillStyle = cloth;
    ctx.beginPath(); ctx.ellipse(0, 0.6, 0.62, 0.17, 0, 0, TAU); ctx.fill();
    ctx.strokeStyle = shade; ctx.lineWidth = 0.025;
    for (let k = -2; k <= 2; k++) { ctx.beginPath(); ctx.moveTo(k * 0.2 - 0.08, 0.5); ctx.quadraticCurveTo(k * 0.2, 0.62, k * 0.2 + 0.1, 0.72); ctx.stroke(); }
  }
  // hood
  ctx.beginPath();
  ctx.moveTo(-0.66, 0.6); ctx.bezierCurveTo(-0.92, 0.2, -0.86, -0.82, -0.04, -1.02); ctx.bezierCurveTo(0.8, -0.86, 0.92, 0.2, 0.66, 0.6);
  ctx.quadraticCurveTo(0, 0.76, -0.66, 0.6); ctx.closePath();
  ctx.fillStyle = rad(ctx, -0.2, -0.45, 0.1, 1.2, [[0, cloth], [0.7, cloth], [1, shade]], -0.35, -0.6); ctx.fill();
  // folds
  ctx.strokeStyle = shade; ctx.lineWidth = 0.03; ctx.globalAlpha *= 0.7;
  ctx.beginPath(); ctx.moveTo(-0.62, 0.3); ctx.quadraticCurveTo(-0.7, -0.4, -0.25, -0.86); ctx.stroke();
  ctx.beginPath(); ctx.moveTo(0.6, 0.35); ctx.quadraticCurveTo(0.72, -0.35, 0.3, -0.84); ctx.stroke();
  ctx.globalAlpha /= 0.7;
  // rim fold around the opening
  ctx.save(); ctx.scale(1.17, 1.13); ctx.beginPath(); voidPath(ctx);
  ctx.fillStyle = lin(ctx, 0, -0.7, 0, 0.6, [[0, cloth], [1, shade]]); ctx.fill(); ctx.restore();
  if (o.trim) { ctx.save(); ctx.scale(1.08, 1.06); ctx.beginPath(); voidPath(ctx); ctx.lineWidth = 0.04; ctx.strokeStyle = H.trim; ctx.stroke(); ctx.restore(); }
  // the shadow inside: solid, nothing else
  ctx.beginPath(); voidPath(ctx); ctx.fillStyle = DP.void; ctx.fill();
  if (o.smile > 0) {
    const g = o.smile;
    ctx.save(); ctx.globalCompositeOperation = 'lighter'; ctx.globalAlpha *= 0.45 * g;
    ctx.fillStyle = rad(ctx, 0, 0.05, 0, 0.42, [[0, 'rgba(255,248,230,0.8)'], [1, 'rgba(255,248,230,0)']]);
    ctx.fillRect(-0.45, -0.4, 0.9, 0.9); ctx.restore();
    ctx.save(); ctx.globalAlpha *= clamp(g * 1.5);
    ctx.fillStyle = '#FFFFFF';
    ctx.beginPath(); ctx.ellipse(-0.15, -0.02, 0.042, 0.05, 0, 0, TAU); ctx.fill();
    ctx.beginPath(); ctx.ellipse(0.15, -0.02, 0.042, 0.05, 0, 0, TAU); ctx.fill();
    ctx.strokeStyle = '#FFFFFF'; ctx.lineWidth = 0.032; ctx.lineCap = 'round';
    ctx.beginPath(); ctx.moveTo(-0.085, 0.12); ctx.quadraticCurveTo(-0.045, 0.19, 0, 0.13); ctx.quadraticCurveTo(0.045, 0.19, 0.085, 0.12); ctx.stroke();
    ctx.restore();
  }
  if (o.eyes) {
    ctx.save(); ctx.globalCompositeOperation = 'lighter';
    ctx.fillStyle = rad(ctx, 0, 0, 0, 0.4, [[0, o.eyes.glow || 'rgba(255,60,60,0.35)'], [1, 'rgba(0,0,0,0)']]); ctx.fillRect(-0.4, -0.4, 0.8, 0.8);
    ctx.restore();
    ctx.fillStyle = o.eyes.col;
    for (const sx of [-1, 1]) { ctx.beginPath(); ctx.moveTo(sx * 0.07, -0.02); ctx.lineTo(sx * 0.27, -0.1); ctx.lineTo(sx * 0.24, 0.02); ctx.closePath(); ctx.fill(); }
  }
  if (o.rings !== false) {
    ring(ctx, -0.6, 0.78, 0.34, -0.2);
    ring(ctx, 0.6, 0.78, 0.34, 0.2);
  }
  ctx.restore();
}

// Emperyan with the hood down: sun-marked face, joyful smile, the Lord's crown. (cx, cy) = face centre.
export function emperyanFace(ctx, cx, cy, s, o = {}) {
  ctx.save(); ctx.translate(cx, cy); ctx.scale(s, s);
  if (o.wings) { wing(ctx, -0.6, 1.05, -1, o.wings, 2.5); wing(ctx, 0.6, 1.05, 1, o.wings, 2.5); }
  // shoulders + the fallen hood as a heavy white collar
  ctx.beginPath(); ctx.moveTo(-1.25, 2.3); ctx.lineTo(-1.15, 1.2); ctx.quadraticCurveTo(-1.0, 0.82, -0.5, 0.78); ctx.lineTo(0.5, 0.78); ctx.quadraticCurveTo(1.0, 0.82, 1.15, 1.2); ctx.lineTo(1.25, 2.3); ctx.closePath();
  ctx.fillStyle = lin(ctx, -1.2, 0, 1.2, 0, [[0, DP.shade], [0.4, DP.white], [1, DP.shade]]); ctx.fill();
  ctx.fillStyle = '#1C1E26'; ctx.fillRect(-0.13, 1.0, 0.26, 1.3);
  ctx.strokeStyle = DP.gold; ctx.lineWidth = 0.025;
  for (let y = 1.1; y < 2.3; y += 0.14) { ctx.beginPath(); ctx.moveTo(-0.11, y); ctx.lineTo(0, y + 0.06); ctx.lineTo(0.11, y); ctx.stroke(); }
  ctx.beginPath(); ctx.ellipse(0, 0.86, 0.85, 0.28, 0, 0, TAU);
  ctx.fillStyle = rad(ctx, 0, 0.8, 0.1, 0.9, [[0, DP.white], [1, DP.shade]]); ctx.fill();
  ctx.strokeStyle = DP.shade; ctx.lineWidth = 0.03;
  for (let k = -3; k <= 3; k++) { ctx.beginPath(); ctx.moveTo(k * 0.22 - 0.1, 0.7); ctx.quadraticCurveTo(k * 0.22, 0.86, k * 0.22 + 0.12, 1.02); ctx.stroke(); }
  // head
  ctx.beginPath(); ctx.roundRect(-0.62, -0.72, 1.24, 1.42, 0.26);
  ctx.fillStyle = lin(ctx, -0.62, 0, 0.62, 0, [[0, DP.skinLo], [0.25, DP.skin], [0.8, DP.skin], [1, DP.skinLo]]); ctx.fill();
  // the sun mark around his eye
  const ex = -0.2, ey = -0.12;
  ctx.strokeStyle = DP.ink; ctx.fillStyle = DP.ink; ctx.lineCap = 'round';
  ctx.lineWidth = 0.035;
  ctx.beginPath(); ctx.arc(ex + 0.04, ey - 0.06, 0.2, 0, TAU); ctx.stroke();
  for (let k = 0; k < 9; k++) {
    const a = -Math.PI * 0.95 + (k / 8) * Math.PI * 1.25;
    const r0 = 0.24, r1 = k % 2 ? 0.33 : 0.4;
    ctx.beginPath(); ctx.moveTo(ex + 0.04 + Math.cos(a) * r0, ey - 0.06 + Math.sin(a) * r0);
    ctx.lineTo(ex + 0.04 + Math.cos(a) * r1, ey - 0.06 + Math.sin(a) * r1); ctx.lineWidth = k % 2 ? 0.022 : 0.035; ctx.stroke();
  }
  ctx.lineWidth = 0.028;
  ctx.beginPath(); ctx.moveTo(ex + 0.22, ey + 0.02); ctx.bezierCurveTo(ex + 0.42, ey - 0.02, ex + 0.5, ey + 0.16, ex + 0.38, ey + 0.2); ctx.stroke();
  ctx.beginPath(); ctx.moveTo(ex + 0.2, ey + 0.1); ctx.bezierCurveTo(ex + 0.3, ey + 0.22, ex + 0.2, ey + 0.32, ex + 0.12, ey + 0.26); ctx.stroke();
  // eyes
  ctx.beginPath(); ctx.ellipse(ex - 0.06, ey + 0.04, 0.045, 0.06, 0, 0, TAU); ctx.fill();
  ctx.beginPath(); ctx.ellipse(0.33, ey + 0.1, 0.045, 0.06, 0, 0, TAU); ctx.fill();
  // joyful open smile
  ctx.beginPath(); ctx.moveTo(-0.16, 0.16); ctx.quadraticCurveTo(0.08, 0.2, 0.3, 0.13);
  ctx.bezierCurveTo(0.32, 0.5, -0.12, 0.55, -0.16, 0.16); ctx.closePath();
  ctx.fillStyle = DP.mouth; ctx.fill(); ctx.lineWidth = 0.035; ctx.strokeStyle = DP.ink; ctx.stroke();
  // crown
  lordCrown(ctx, 0.0, -0.58, 1.42, { starDip: 0.42 });
  if (o.rings !== false) { ring(ctx, -0.72, 1.18, 0.38, -0.2); ring(ctx, 0.72, 1.18, 0.38, 0.2); }
  ctx.restore();
}

// Atmos: grey great helm, calm blue eyes, ice-crystal plumes. (cx, cy) helm centre.
export function atmos(ctx, cx, cy, s, o = {}) {
  ctx.save(); ctx.translate(cx, cy); ctx.scale(s, s);
  // quill
  ctx.strokeStyle = '#C79A6A'; ctx.lineWidth = 0.09; ctx.lineCap = 'round';
  ctx.beginPath(); ctx.moveTo(0.05, -0.66); ctx.lineTo(-0.12, -1.35); ctx.stroke();
  ctx.strokeStyle = '#7A4A2A'; ctx.lineWidth = 0.1; ctx.beginPath(); ctx.moveTo(0.06, -0.66); ctx.lineTo(0.2, -0.72); ctx.stroke();
  // ice plumes, right side
  for (let k = 0; k < 6; k++) {
    const a = -0.9 + k * 0.32, L = 0.5 + 0.25 * Math.sin(k * 1.7);
    ctx.save(); ctx.translate(0.55, 0.2); ctx.rotate(a);
    ctx.beginPath(); ctx.moveTo(0, -0.06); ctx.lineTo(L, -0.04); ctx.lineTo(L + 0.12, 0); ctx.lineTo(L, 0.05); ctx.lineTo(0, 0.06); ctx.closePath();
    ctx.fillStyle = k === 5 ? DP.cobaltLo : lin(ctx, 0, 0, L, 0, [[0, '#7FC4F0'], [1, '#D9F2FF']]); ctx.fill();
    ctx.restore();
  }
  // helm: top face, front face
  ctx.beginPath(); ctx.moveTo(-0.62, -0.5); ctx.lineTo(-0.5, -0.7); ctx.lineTo(0.55, -0.72); ctx.lineTo(0.66, -0.5); ctx.closePath();
  ctx.fillStyle = '#A3A6AE'; ctx.fill();
  ctx.beginPath(); ctx.roundRect(-0.66, -0.52, 1.32, 1.08, 0.1);
  ctx.fillStyle = lin(ctx, -0.66, 0, 0.66, 0, [[0, '#6E7078'], [0.4, '#8D9098'], [1, '#55575E']]); ctx.fill();
  // brow ridge + visor
  ctx.fillStyle = '#5A5C63'; ctx.fillRect(-0.66, -0.12, 1.32, 0.06);
  ctx.fillStyle = '#4A4C53'; ctx.beginPath(); ctx.roundRect(-0.5, 0.18, 1.0, 0.3, 0.04); ctx.fill();
  ctx.fillStyle = '#1E1F23';
  for (let i = 0; i < 5; i++) ctx.fillRect(-0.36 + i * 0.16, 0.22, 0.05, 0.2);
  // calm blue eyes
  ctx.save(); ctx.globalCompositeOperation = 'lighter';
  ctx.fillStyle = rad(ctx, 0, 0.02, 0, 0.6, [[0, 'rgba(90,180,255,0.35)'], [1, 'rgba(0,0,0,0)']]); ctx.fillRect(-0.6, -0.5, 1.2, 1.0);
  ctx.restore();
  ctx.fillStyle = '#0F1218'; ctx.fillRect(-0.55, -0.05, 1.1, 0.2);
  ctx.fillStyle = '#7FD0FF';
  for (const sx of [-1, 1]) { ctx.beginPath(); ctx.moveTo(sx * 0.1, 0.0); ctx.quadraticCurveTo(sx * 0.25, -0.05, sx * 0.4, 0.02); ctx.quadraticCurveTo(sx * 0.25, 0.12, sx * 0.1, 0.06); ctx.closePath(); ctx.fill(); }
  if (o.rings !== false) { ring(ctx, -0.6, 0.62, 0.28, 0); ring(ctx, 0.6, 0.62, 0.28, 0); }
  ctx.restore();
}

// Judas: white mask-helm, black shadow band, red eyes, white crystal spikes. (cx, cy) centre.
export function judas(ctx, cx, cy, s, o = {}) {
  ctx.save(); ctx.translate(cx, cy); ctx.scale(s, s);
  for (let k = 0; k < 5; k++) {
    const a = -1.0 + k * 0.3, L = 0.55 + 0.2 * (k % 2);
    ctx.save(); ctx.translate(0.5, -0.05); ctx.rotate(a);
    ctx.beginPath(); ctx.moveTo(0, -0.07); ctx.lineTo(L, -0.03); ctx.lineTo(L + 0.14, 0); ctx.lineTo(L, 0.04); ctx.lineTo(0, 0.07); ctx.closePath();
    ctx.fillStyle = lin(ctx, 0, 0, L, 0, [[0, '#BFC4CE'], [1, '#FFFFFF']]); ctx.fill(); ctx.restore();
  }
  for (let k = 0; k < 2; k++) {
    ctx.save(); ctx.translate(-0.55, 0.1); ctx.rotate(Math.PI + 0.5 + k * 0.4);
    ctx.beginPath(); ctx.moveTo(0, -0.06); ctx.lineTo(0.45, -0.02); ctx.lineTo(0.55, 0); ctx.lineTo(0.45, 0.03); ctx.lineTo(0, 0.06); ctx.closePath();
    ctx.fillStyle = '#E4E7EE'; ctx.fill(); ctx.restore();
  }
  ctx.beginPath(); ctx.moveTo(-0.6, -0.5); ctx.lineTo(-0.48, -0.68); ctx.lineTo(0.5, -0.68); ctx.lineTo(0.62, -0.5); ctx.closePath(); ctx.fillStyle = '#FFFFFF'; ctx.fill();
  ctx.beginPath(); ctx.roundRect(-0.62, -0.52, 1.24, 1.06, 0.12);
  ctx.fillStyle = lin(ctx, -0.62, 0, 0.62, 0, [[0, '#C9CDD6'], [0.35, '#F5F6F9'], [1, '#B3B8C3']]); ctx.fill();
  // the black mask: two lobes with a peak between
  ctx.beginPath();
  ctx.moveTo(-0.5, 0.05); ctx.bezierCurveTo(-0.55, -0.35, -0.2, -0.42, 0, -0.2); ctx.bezierCurveTo(0.2, -0.42, 0.55, -0.35, 0.5, 0.05);
  ctx.bezierCurveTo(0.48, 0.38, 0.12, 0.45, 0, 0.3); ctx.bezierCurveTo(-0.12, 0.45, -0.48, 0.38, -0.5, 0.05); ctx.closePath();
  ctx.fillStyle = '#12101A'; ctx.fill();
  ctx.save(); ctx.globalCompositeOperation = 'lighter';
  ctx.fillStyle = rad(ctx, 0, 0.05, 0, 0.55, [[0, 'rgba(255,40,40,0.35)'], [1, 'rgba(0,0,0,0)']]); ctx.fillRect(-0.6, -0.5, 1.2, 1.0);
  ctx.restore();
  ctx.fillStyle = '#E3263A';
  for (const sx of [-1, 1]) { ctx.beginPath(); ctx.moveTo(sx * 0.08, 0.02); ctx.lineTo(sx * 0.38, -0.06); ctx.quadraticCurveTo(sx * 0.36, 0.2, sx * 0.14, 0.18); ctx.closePath(); ctx.fill(); }
  if (o.rings !== false) { ring(ctx, -0.6, 0.62, 0.28, 0, '#5A5C64', '#C9CCD3'); ring(ctx, 0.6, 0.62, 0.28, 0, '#5A5C64', '#C9CCD3'); }
  ctx.restore();
}

// Small full-body hooded dominus, front view (crowds). Feet at (x, y), height h.
export function dominusFront(ctx, x, y, h, phase, o = {}) {
  const col = o.col || '#151A28', vcol = o.void || DP.void;
  const s = TAU * phase;
  ctx.save(); ctx.translate(x, y - Math.abs(Math.sin(s)) * 0.012 * h); ctx.scale(h, h);
  ctx.fillStyle = col;
  if (o.wing) {
    for (const sd of [-1, 1]) for (let k = 0; k < 3; k++) {
      ctx.save(); ctx.translate(sd * 0.17, -0.72); ctx.rotate(sd * (-0.5 - k * 0.32)); ctx.scale(sd, 1);
      ctx.beginPath(); ctx.ellipse(0.17, 0, 0.17, 0.025, 0, 0, TAU); ctx.fillStyle = o.wing; ctx.fill(); ctx.restore();
    }
    ctx.fillStyle = col;
  }
  const l = Math.max(0, Math.sin(s)) * 0.06, r = Math.max(0, -Math.sin(s)) * 0.06;
  ctx.fillRect(-0.07, -0.2, 0.055, 0.2 - l); ctx.fillRect(0.015, -0.2, 0.055, 0.2 - r);
  ctx.beginPath(); ctx.moveTo(-0.17, -0.74); ctx.lineTo(0.17, -0.74); ctx.lineTo(0.25, -0.15); ctx.quadraticCurveTo(0, -0.1, -0.25, -0.15); ctx.closePath(); ctx.fill();
  ctx.beginPath(); ctx.moveTo(-0.15, -0.72); ctx.bezierCurveTo(-0.2, -0.86, -0.12, -1.0, 0, -1.02); ctx.bezierCurveTo(0.12, -1.0, 0.2, -0.86, 0.15, -0.72); ctx.closePath(); ctx.fill();
  ctx.beginPath(); ctx.ellipse(0, -0.835, 0.075, 0.09, 0, 0, TAU); ctx.fillStyle = vcol; ctx.fill();
  if (o.trim) { ctx.strokeStyle = o.trim; ctx.lineWidth = 0.012; ctx.stroke(); }
  if (o.rings !== false) {
    ctx.fillStyle = o.ringCol || '#0A0B0E';
    for (const sd of [-1, 1]) { ctx.beginPath(); ctx.arc(sd * 0.16, -0.66, 0.06, 0, TAU); ctx.arc(sd * 0.16, -0.66, 0.025, 0, TAU, true); ctx.fill('evenodd'); }
  }
  if (o.blade) { ctx.strokeStyle = o.blade; ctx.lineWidth = 0.02; ctx.beginPath(); ctx.moveTo(0.21, -0.45); ctx.lineTo(0.21, -1.2); ctx.stroke(); }
  if (o.torch) {
    ctx.strokeStyle = col; ctx.lineWidth = 0.02; ctx.beginPath(); ctx.moveTo(0.22, -0.45); ctx.lineTo(0.26, -1.1); ctx.stroke();
  }
  ctx.restore();
}

// Side-view hooded dominus marching (facing right). Feet at (x, y), height h.
export function dominusSide(ctx, x, y, h, phase, o = {}) {
  const col = o.col || '#151A28';
  const s = TAU * phase;
  ctx.save(); ctx.translate(x, y - Math.abs(Math.sin(s)) * 0.012 * h); ctx.scale(h, h);
  ctx.fillStyle = col; ctx.strokeStyle = col; ctx.lineCap = 'round';
  const hip = [0, -0.42];
  const leg = (a, bend) => {
    const knee = [hip[0] + Math.sin(a) * 0.21, hip[1] + Math.cos(a) * 0.21];
    const sa = a - bend, foot = [knee[0] + Math.sin(sa) * 0.21, knee[1] + Math.cos(sa) * 0.21];
    ctx.lineWidth = 0.07; ctx.beginPath(); ctx.moveTo(hip[0], hip[1]); ctx.lineTo(knee[0], knee[1]); ctx.lineTo(foot[0], foot[1]); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(foot[0] - 0.03, foot[1] - 0.03); ctx.lineTo(foot[0] + 0.07, foot[1] - 0.005); ctx.lineTo(foot[0] + 0.075, foot[1] + 0.02); ctx.lineTo(foot[0] - 0.035, foot[1] + 0.02); ctx.closePath(); ctx.fill();
  };
  const sw = 0.4;
  leg(-sw * Math.sin(s), Math.max(0, -Math.cos(s)) * 0.7);
  leg(sw * Math.sin(s), Math.max(0, Math.cos(s)) * 0.7);
  // wing (behind)
  if (o.wing) {
    for (let k = 0; k < 4; k++) {
      ctx.save(); ctx.translate(-0.02, -0.7); ctx.rotate(Math.PI + 0.35 + k * 0.28);
      ctx.beginPath(); ctx.ellipse(0.22 - k * 0.02, 0, 0.23 - k * 0.02, 0.028, 0, 0, TAU); ctx.fillStyle = o.wing; ctx.fill(); ctx.restore();
    }
    ctx.fillStyle = col;
  }
  // cloak streaming back
  const fl = Math.sin(s * 2) * 0.03;
  ctx.beginPath(); ctx.moveTo(-0.09, -0.76); ctx.lineTo(0.08, -0.76); ctx.lineTo(0.1, -0.3);
  ctx.quadraticCurveTo(-0.08, -0.22 + fl, -0.3, -0.26 + fl); ctx.quadraticCurveTo(-0.2, -0.5, -0.09, -0.76); ctx.closePath(); ctx.fill();
  // hood (side): rounded with a point at the back, open shadow at the front
  ctx.beginPath(); ctx.moveTo(-0.09, -0.74); ctx.bezierCurveTo(-0.16, -0.86, -0.12, -0.98, -0.02, -1.0); ctx.bezierCurveTo(0.1, -1.0, 0.14, -0.9, 0.12, -0.74); ctx.closePath(); ctx.fill();
  ctx.beginPath(); ctx.ellipse(0.075, -0.85, 0.045, 0.085, 0.15, 0, TAU); ctx.fillStyle = DP.void; ctx.fill();
  if (o.trim) { ctx.strokeStyle = o.trim; ctx.lineWidth = 0.012; ctx.stroke(); }
  ctx.fillStyle = o.ringCol || '#0A0B0E';
  ctx.beginPath(); ctx.arc(0.0, -0.68, 0.065, 0, TAU); ctx.arc(0.0, -0.68, 0.028, 0, TAU, true); ctx.fill('evenodd');
  // lance on the shoulder with a pennant
  ctx.strokeStyle = col; ctx.lineWidth = 0.022;
  ctx.beginPath(); ctx.moveTo(0.1, -0.55); ctx.lineTo(-0.1, -1.25); ctx.stroke();
  if (o.pennant) {
    ctx.fillStyle = o.pennant;
    ctx.beginPath(); ctx.moveTo(-0.09, -1.22); ctx.lineTo(-0.3, -1.18 + Math.sin(s * 2) * 0.02); ctx.lineTo(-0.075, -1.14); ctx.closePath(); ctx.fill();
  }
  ctx.restore();
}

// ------------------------------------------------------------------ signs

export function sigil(ctx, kind, x, y, S, col = DP.goldHi, dark = DP.gold) {
  ctx.save(); ctx.translate(x, y); ctx.scale(S, S);
  ctx.fillStyle = col; ctx.strokeStyle = col; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
  switch (kind) {
    case 'crystal': {
      ctx.lineWidth = 12;
      for (let k = 0; k < 6; k++) {
        ctx.save(); ctx.rotate((k / 6) * TAU);
        ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(0, -95); ctx.stroke();
        ctx.lineWidth = 9;
        for (const [d, l] of [[-45, 26], [-70, 18]]) { ctx.beginPath(); ctx.moveTo(0, d); ctx.lineTo(-l, d - l); ctx.moveTo(0, d); ctx.lineTo(l, d - l); ctx.stroke(); }
        ctx.lineWidth = 12; ctx.restore();
      }
      ctx.beginPath(); ctx.arc(0, 0, 18, 0, TAU); ctx.fill();
      break;
    }
    case 'flame': {
      ctx.beginPath();
      ctx.moveTo(0, 100); ctx.bezierCurveTo(-80, 90, -85, 10, -40, -30); ctx.bezierCurveTo(-35, 0, -20, 10, -15, 10);
      ctx.bezierCurveTo(-30, -40, -10, -80, 10, -105); ctx.bezierCurveTo(15, -60, 40, -50, 45, -20);
      ctx.bezierCurveTo(55, -35, 60, -50, 58, -60); ctx.bezierCurveTo(95, -10, 90, 90, 0, 100); ctx.closePath(); ctx.fill();
      ctx.fillStyle = dark;
      ctx.beginPath(); ctx.moveTo(0, 85); ctx.bezierCurveTo(-40, 80, -45, 30, -10, -10); ctx.bezierCurveTo(-5, 20, 15, 25, 20, 5); ctx.bezierCurveTo(45, 30, 40, 80, 0, 85); ctx.fill();
      break;
    }
    case 'sun': {
      for (let k = 0; k < 16; k++) {
        const a = (k / 16) * TAU, r1 = k % 2 ? 78 : 105;
        ctx.beginPath(); ctx.moveTo(Math.cos(a - 0.12) * 50, Math.sin(a - 0.12) * 50); ctx.lineTo(Math.cos(a) * r1, Math.sin(a) * r1); ctx.lineTo(Math.cos(a + 0.12) * 50, Math.sin(a + 0.12) * 50); ctx.closePath(); ctx.fill();
      }
      ctx.beginPath(); ctx.arc(0, 0, 52, 0, TAU); ctx.fill();
      ctx.fillStyle = dark; ctx.beginPath(); ctx.arc(0, 0, 36, 0, TAU); ctx.fill();
      break;
    }
    case 'key': {
      ctx.lineWidth = 16;
      ctx.beginPath(); ctx.arc(0, -55, 34, 0, TAU); ctx.stroke();
      ctx.beginPath(); ctx.moveTo(0, -20); ctx.lineTo(0, 100); ctx.stroke();
      ctx.fillRect(0, 55, 40, 14); ctx.fillRect(0, 82, 30, 14);
      break;
    }
    case 'hunt': {
      ctx.lineWidth = 12;
      ctx.beginPath(); ctx.arc(0, 0, 70, 0, TAU); ctx.stroke();
      ctx.beginPath(); ctx.arc(0, 0, 30, 0, TAU); ctx.stroke();
      for (const [dx, dy] of [[0, -1], [0, 1], [-1, 0], [1, 0]]) { ctx.beginPath(); ctx.moveTo(dx * 45, dy * 45); ctx.lineTo(dx * 105, dy * 105); ctx.stroke(); }
      ctx.beginPath(); ctx.arc(0, 0, 9, 0, TAU); ctx.fill();
      break;
    }
    case 'rex': {
      ctx.beginPath(); ctx.moveTo(-90, 50); ctx.lineTo(-95, -50); ctx.lineTo(-45, -5); ctx.lineTo(0, -75); ctx.lineTo(45, -5); ctx.lineTo(95, -50); ctx.lineTo(90, 50); ctx.closePath(); ctx.fill();
      ctx.fillRect(-92, 60, 184, 22);
      break;
    }
    case 'astra': {
      ctx.beginPath(); ctx.moveTo(0, -105); ctx.quadraticCurveTo(12, -12, 105, 0); ctx.quadraticCurveTo(12, 12, 0, 105); ctx.quadraticCurveTo(-12, 12, -105, 0); ctx.quadraticCurveTo(-12, -12, 0, -105); ctx.fill();
      ctx.fillStyle = dark; ctx.beginPath(); ctx.arc(0, 0, 16, 0, TAU); ctx.fill();
      break;
    }
    case 'eye': {
      ctx.beginPath(); ctx.moveTo(-105, 0); ctx.quadraticCurveTo(0, -85, 105, 0); ctx.quadraticCurveTo(0, 85, -105, 0); ctx.closePath(); ctx.fill();
      ctx.fillStyle = dark; ctx.beginPath(); ctx.arc(0, 0, 36, 0, TAU); ctx.fill();
      ctx.fillStyle = DP.void; ctx.beginPath(); ctx.arc(0, 0, 16, 0, TAU); ctx.fill();
      break;
    }
    case 'ticket': {
      ctx.beginPath(); ctx.moveTo(-100, -55); ctx.lineTo(100, -55); ctx.lineTo(100, -18); ctx.arc(100, 0, 18, -Math.PI / 2, Math.PI / 2, true); ctx.lineTo(100, 55);
      ctx.lineTo(-100, 55); ctx.lineTo(-100, 18); ctx.arc(-100, 0, 18, Math.PI / 2, -Math.PI / 2, true); ctx.closePath(); ctx.fill();
      ctx.strokeStyle = dark; ctx.lineWidth = 6; ctx.setLineDash([10, 9]); ctx.beginPath(); ctx.moveTo(45, -50); ctx.lineTo(45, 50); ctx.stroke(); ctx.setLineDash([]);
      break;
    }
    case 'bat': {
      ctx.beginPath(); ctx.moveTo(0, -30); ctx.lineTo(-14, -52); ctx.lineTo(-18, -25);
      ctx.bezierCurveTo(-60, -50, -100, -40, -112, -20); ctx.bezierCurveTo(-90, -10, -80, 10, -78, 25); ctx.bezierCurveTo(-60, 12, -45, 15, -38, 30);
      ctx.bezierCurveTo(-25, 20, -10, 25, 0, 45); ctx.bezierCurveTo(10, 25, 25, 20, 38, 30); ctx.bezierCurveTo(45, 15, 60, 12, 78, 25);
      ctx.bezierCurveTo(80, 10, 90, -10, 112, -20); ctx.bezierCurveTo(100, -40, 60, -50, 18, -25); ctx.lineTo(14, -52); ctx.closePath(); ctx.fill();
      break;
    }
    case 'sickle': {
      ctx.beginPath(); ctx.arc(10, -10, 85, -Math.PI * 0.95, Math.PI * 0.15); ctx.arc(30, -25, 62, Math.PI * 0.1, -Math.PI * 0.92, true); ctx.closePath(); ctx.fill();
      ctx.lineWidth = 18; ctx.beginPath(); ctx.moveTo(-40, 50); ctx.lineTo(-90, 105); ctx.stroke();
      break;
    }
    case 'coin': {
      ctx.beginPath(); ctx.arc(0, 0, 100, 0, TAU); ctx.fill();
      ctx.strokeStyle = dark; ctx.lineWidth = 8; ctx.beginPath(); ctx.arc(0, 0, 82, 0, TAU); ctx.stroke();
      ctx.font = '700 110px Display'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillStyle = dark; ctx.fillText('A', 0, 8);
      break;
    }
    case 'hood': {
      ctx.save(); ctx.scale(110, 110); ctx.translate(0, 0.1);
      ctx.beginPath(); ctx.moveTo(-0.66, 0.6); ctx.bezierCurveTo(-0.92, 0.2, -0.86, -0.82, -0.04, -1.02); ctx.bezierCurveTo(0.8, -0.86, 0.92, 0.2, 0.66, 0.6); ctx.quadraticCurveTo(0, 0.76, -0.66, 0.6); ctx.closePath(); ctx.fill();
      ctx.beginPath(); voidPath(ctx); ctx.fillStyle = DP.void; ctx.fill();
      ctx.restore();
      break;
    }
    default: break;
  }
  ctx.restore();
}

// The seal of the Domini: a hood in a gold ring, wings, the Lord's crown, the three houses beneath.
// p: per-part progress { ring, wings, crown, houses }.
export function emblem(ctx, cx, cy, S, p = {}, o = {}) {
  const g = (k) => clamp(p[k] ?? 1);
  ctx.save(); ctx.translate(cx, cy); ctx.scale(S, S);
  if (g('wings') > 0) {
    wing(ctx, -150, 30, -1, g('wings'), 360, { tip: DP.cobalt });
    wing(ctx, 150, 30, 1, g('wings'), 360, { tip: DP.cobalt });
  }
  if (g('ring') > 0) {
    const k = g('ring');
    ctx.save(); ctx.scale(k, k);
    ctx.beginPath(); ctx.arc(0, 0, 175, 0, TAU); ctx.fillStyle = DP.night2; ctx.fill();
    ctx.lineWidth = 14; ctx.strokeStyle = DP.gold; ctx.stroke();
    ctx.beginPath(); ctx.arc(0, 0, 155, 0, TAU); ctx.lineWidth = 3; ctx.strokeStyle = DP.goldLo; ctx.stroke();
    for (let i = 0; i < 48; i++) { const a = (i / 48) * TAU; ctx.beginPath(); ctx.arc(Math.cos(a) * 165, Math.sin(a) * 165, 2.5, 0, TAU); ctx.fillStyle = DP.goldHi; ctx.fill(); }
    hoodBust(ctx, 0, -10, 72, { house: 'empyerus', rings: false, scarf: false, trimBand: false, smile: o.smile || 0, trim: true });
    ctx.restore();
  }
  if (g('crown') > 0) {
    const k = g('crown');
    lordCrown(ctx, 0, -168 + (1 - k) * -260, 300, { starDip: 30 });
  }
  if (g('houses') > 0) {
    const k = g('houses');
    const items = [['crystal', DP.frost, DP.frostLo, -120], ['sun', DP.goldHi, DP.gold, 0], ['flame', DP.ember, DP.emberLo, 120]];
    items.forEach(([kind, c, d, x], i) => {
      const kk = clamp(k * 3 - i);
      if (kk <= 0) return;
      ctx.save(); ctx.translate(x, 228); ctx.scale(kk, kk);
      ctx.beginPath(); ctx.arc(0, 0, 46, 0, TAU); ctx.fillStyle = DP.night; ctx.fill(); ctx.lineWidth = 5; ctx.strokeStyle = DP.gold; ctx.stroke();
      sigil(ctx, kind, 0, 0, 0.34, c, d);
      ctx.restore();
    });
  }
  ctx.restore();
}

// A wanted notice for a scammer: parchment, a faceless suspect, the charge.
export function wanted(ctx, x, y, w, h, charge, o = {}) {
  ctx.save(); ctx.translate(x, y); ctx.rotate(o.rot || 0);
  ctx.fillStyle = '#E9DCC0'; ctx.fillRect(-w / 2, -h / 2, w, h);
  ctx.strokeStyle = '#5A4528'; ctx.lineWidth = 6; ctx.strokeRect(-w / 2 + 14, -h / 2 + 14, w - 28, h - 28);
  ctx.fillStyle = '#2A1E10'; ctx.textAlign = 'center';
  ctx.font = `700 ${Math.round(w * 0.2)}px UI`; ctx.letterSpacing = `${w * 0.01}px`; ctx.fillText('WANTED', 0, -h / 2 + w * 0.26); ctx.letterSpacing = '0px';
  // suspect: cap, collar, a face scrubbed out
  const sy = -h * 0.02, sr = w * 0.17;
  ctx.fillStyle = '#3A2C1A';
  ctx.beginPath(); ctx.moveTo(-w * 0.32, sy + w * 0.42); ctx.quadraticCurveTo(-w * 0.3, sy + sr * 0.9, 0, sy + sr * 0.85); ctx.quadraticCurveTo(w * 0.3, sy + sr * 0.9, w * 0.32, sy + w * 0.42); ctx.closePath(); ctx.fill();
  ctx.beginPath(); ctx.arc(0, sy, sr, 0, TAU); ctx.fill();
  ctx.beginPath(); ctx.ellipse(0, sy - sr * 0.55, sr * 1.05, sr * 0.45, 0, Math.PI, 0); ctx.fill(); ctx.fillRect(0, sy - sr * 0.62, sr * 1.5, sr * 0.16);
  ctx.fillStyle = '#C8231F'; ctx.font = `700 ${Math.round(sr * 1.3)}px UI`; ctx.textBaseline = 'middle'; ctx.fillText('?', 0, sy + sr * 0.1); ctx.textBaseline = 'alphabetic';
  ctx.fillStyle = '#2A1E10'; ctx.font = `700 ${Math.round(w * 0.105)}px UI`; ctx.fillText(charge, 0, h / 2 - w * 0.2);
  ctx.font = `500 ${Math.round(w * 0.045)}px UI`; ctx.letterSpacing = `${w * 0.01}px`; ctx.fillText('BY ORDER OF THE DOMINI', 0, h / 2 - w * 0.1); ctx.letterSpacing = '0px';
  ctx.restore();
}

// Stamp: a rubber-stamp word in a frame, rotated.
export function stamp(ctx, word, x, y, size, col, rot = -0.18, a = 1) {
  ctx.save(); ctx.translate(x, y); ctx.rotate(rot); ctx.globalAlpha *= a;
  ctx.font = `700 ${size}px UI`; ctx.letterSpacing = `${size * 0.08}px`; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
  const w = ctx.measureText(word).width + size * 0.6;
  ctx.strokeStyle = col; ctx.lineWidth = size * 0.09; ctx.strokeRect(-w / 2, -size * 0.65, w, size * 1.3);
  ctx.fillStyle = col; ctx.fillText(word, size * 0.04, size * 0.05);
  ctx.letterSpacing = '0px'; ctx.restore();
}

// The empty seat (a tall-backed chair), front view; base centre (x, y), height h.
export function emptySeat(ctx, x, y, h, col, edge) {
  ctx.save(); ctx.translate(x, y); ctx.scale(h, h);
  ctx.fillStyle = col;
  ctx.beginPath(); ctx.moveTo(-0.26, -0.45); ctx.lineTo(-0.24, -0.98); ctx.lineTo(0, -1.12); ctx.lineTo(0.24, -0.98); ctx.lineTo(0.26, -0.45); ctx.closePath(); ctx.fill();
  ctx.fillRect(-0.34, -0.48, 0.68, 0.1);
  ctx.fillRect(-0.32, -0.38, 0.06, 0.38); ctx.fillRect(0.26, -0.38, 0.06, 0.38);
  ctx.fillRect(-0.38, -0.62, 0.08, 0.16); ctx.fillRect(0.3, -0.62, 0.08, 0.16);
  if (edge) {
    ctx.strokeStyle = edge; ctx.lineWidth = 0.008;
    ctx.beginPath(); ctx.moveTo(-0.26, -0.45); ctx.lineTo(-0.24, -0.98); ctx.lineTo(0, -1.12); ctx.lineTo(0.24, -0.98); ctx.lineTo(0.26, -0.45); ctx.stroke();
    // the four-point star cut into the back
    ctx.beginPath(); ctx.moveTo(0, -0.95); ctx.quadraticCurveTo(0.02, -0.8, 0.09, -0.78); ctx.quadraticCurveTo(0.02, -0.76, 0, -0.6); ctx.quadraticCurveTo(-0.02, -0.76, -0.09, -0.78); ctx.quadraticCurveTo(-0.02, -0.8, 0, -0.95); ctx.fillStyle = edge; ctx.fill();
  }
  ctx.restore();
}

// A standing hunter, hood up, cloak in the wind, blade lowered. Feet at (x, y), height h.
// rim: the moonlit edge colour (left side), wind: seconds for the cloak's motion.
export function hunter(ctx, x, y, h, t, o = {}) {
  const col = o.col || '#090C16', rim = o.rim || '#6F8FB8';
  ctx.save(); ctx.translate(x, y); ctx.scale(h, h);
  const fill = lin(ctx, -0.35, 0, 0.1, 0, [[0, rim], [0.35, col], [1, col]]);
  // wings folded up behind the shoulders
  for (const sd of [-1, 1]) for (let k = 0; k < 5; k++) {
    ctx.save(); ctx.translate(sd * 0.16, -0.72); ctx.rotate(sd * (-0.25 - k * 0.2) - Math.PI / 2 * (sd > 0 ? 0 : 0)); ctx.scale(sd, 1);
    ctx.rotate(-1.1);
    ctx.beginPath(); ctx.ellipse(0.26 - k * 0.015, 0, 0.27 - k * 0.02, 0.03, 0, 0, TAU);
    ctx.fillStyle = lin(ctx, 0, 0, 0.5, 0, [[0, '#9AA2B4'], [0.7, '#E8ECF4'], [0.85, o.tip || DP.cobalt], [1, o.tip || DP.cobalt]]); ctx.fill();
    ctx.restore();
  }
  // legs apart on the ledge
  ctx.strokeStyle = col; ctx.lineCap = 'round'; ctx.lineWidth = 0.075;
  ctx.beginPath(); ctx.moveTo(-0.05, -0.42); ctx.lineTo(-0.13, -0.2); ctx.lineTo(-0.19, 0); ctx.stroke();
  ctx.beginPath(); ctx.moveTo(0.05, -0.42); ctx.lineTo(0.12, -0.2); ctx.lineTo(0.17, 0); ctx.stroke();
  // cloak streaming right
  const wv = (k) => Math.sin(t * 3.1 + k * 1.7) * 0.035;
  ctx.beginPath();
  ctx.moveTo(-0.17, -0.76); ctx.lineTo(0.17, -0.76);
  ctx.quadraticCurveTo(0.4, -0.55 + wv(1), 0.62, -0.42 + wv(2));
  ctx.quadraticCurveTo(0.5, -0.3 + wv(3), 0.58, -0.16 + wv(4));
  ctx.quadraticCurveTo(0.3, -0.18 + wv(5), 0.16, -0.12);
  ctx.lineTo(-0.2, -0.14); ctx.quadraticCurveTo(-0.24, -0.45, -0.17, -0.76); ctx.closePath();
  ctx.fillStyle = fill; ctx.fill();
  // hood
  ctx.beginPath(); ctx.moveTo(-0.15, -0.72); ctx.bezierCurveTo(-0.21, -0.88, -0.12, -1.02, 0.01, -1.04); ctx.bezierCurveTo(0.14, -1.0, 0.21, -0.86, 0.15, -0.72); ctx.closePath();
  ctx.fillStyle = fill; ctx.fill();
  ctx.beginPath(); ctx.ellipse(0.01, -0.85, 0.075, 0.095, 0, 0, TAU); ctx.fillStyle = DP.void; ctx.fill();
  ctx.lineWidth = 0.008; ctx.strokeStyle = rim; ctx.stroke();
  // rings
  for (const sd of [-1, 1]) { ctx.beginPath(); ctx.arc(sd * 0.17, -0.68, 0.065, 0, TAU); ctx.arc(sd * 0.17, -0.68, 0.027, 0, TAU, true); ctx.fillStyle = '#05060A'; ctx.fill('evenodd'); ctx.lineWidth = 0.008; ctx.strokeStyle = rim; ctx.stroke(); }
  // blade lowered in the right hand
  ctx.save(); ctx.translate(0.2, -0.46); ctx.rotate(1.05);
  ctx.fillStyle = lin(ctx, 0, -0.02, 0, 0.02, [[0, '#FFFFFF'], [1, '#8E94A4']]);
  ctx.beginPath(); ctx.moveTo(0.04, -0.018); ctx.lineTo(0.5, -0.014); ctx.lineTo(0.56, 0); ctx.lineTo(0.5, 0.014); ctx.lineTo(0.04, 0.018); ctx.closePath(); ctx.fill();
  ctx.fillStyle = DP.silver; ctx.fillRect(0.02, -0.05, 0.02, 0.1); ctx.fillStyle = col; ctx.fillRect(-0.06, -0.012, 0.08, 0.024);
  ctx.restore();
  ctx.restore();
}

// A kneeling hooded heir, side view, facing right; base at (x, y), height h (standing height).
export function kneeler(ctx, x, y, h, cloth, shade, bow = 0) {
  ctx.save(); ctx.translate(x, y); ctx.scale(h, h);
  ctx.fillStyle = lin(ctx, -0.4, 0, 0.3, 0, [[0, shade], [0.6, cloth], [1, shade]]);
  ctx.beginPath(); ctx.moveTo(-0.42, 0); ctx.quadraticCurveTo(-0.36, -0.42, -0.06, -0.52); ctx.lineTo(0.14, -0.5); ctx.quadraticCurveTo(0.26, -0.3, 0.3, -0.04); ctx.lineTo(0.3, 0); ctx.closePath(); ctx.fill();
  ctx.save(); ctx.translate(0.05, -0.52); ctx.rotate(0.35 + bow * 0.35);
  ctx.beginPath(); ctx.moveTo(-0.12, 0.02); ctx.bezierCurveTo(-0.16, -0.14, -0.06, -0.26, 0.04, -0.26); ctx.bezierCurveTo(0.14, -0.24, 0.17, -0.12, 0.13, 0.02); ctx.closePath(); ctx.fill();
  ctx.beginPath(); ctx.ellipse(0.075, -0.1, 0.04, 0.075, 0.15, 0, TAU); ctx.fillStyle = DP.void; ctx.fill();
  ctx.restore();
  ctx.beginPath(); ctx.arc(0.02, -0.46, 0.06, 0, TAU); ctx.arc(0.02, -0.46, 0.025, 0, TAU, true); ctx.fillStyle = '#0A0B0E'; ctx.fill('evenodd');
  ctx.restore();
}
