// Claude Pro: pure function of time. window.seek(t) paints frame t (see lib/motion.js).
// Timing is in beats (u) on the 96 bpm grid (0.625 s/beat, 24 beats); docs/shotlist.md is the plan.
import * as M from './lib/motion.js';

const { W, H, FORMAT, E, clamp, lerp, prog, springU, springKeys, SPRING, font, layout, glyph, text, fill, rrect, crop, mix } = M;

// Brand tokens (assets/brand.json, css vars). One accent: clay.
const C = {
  ivory: '#faf9f5', ink: '#141413', muted: '#5e5d59', line: '#f0eee6',
  clay: '#d97757', clayDeep: '#c6613f', white: '#ffffff',
};
const DISPLAY = 'Display', UI = 'UI';
const alpha = (ctx, a) => { ctx.globalAlpha = clamp(a); };   // springs overshoot; canvas ignores alpha < 0

// Every accent: [beat, label, sfx, opts]. sfx.mjs voices these, so sound can't drift from picture.
const HITS = [
  [0, 'hook line 1 lands, spark settling', 'tok', { pitch: 'F5', gain: 0.35 }],
  [2, 'hook line 2', 'tok', { pitch: 'C6', gain: 0.3 }],
  [4, 'riser into the card (ends on the drop)', 'riser', { len: 1.4, gain: 0.22 }],
  [4, 'Pro card lands', 'impact', { gain: 0.45 }],
  [6, '$17 underline', 'tick+blip', { pitch: 'A5', gain: 0.3 }],
  [8, 'pan into features', 'whoosh', { len: 0.5, from: 500, to: 2200, pan: 0.3, gain: 0.25 }],
  [8, 'row: Hand off and schedule tasks', 'blip', { pitch: 'F5', pan: 0.2, gain: 0.3 }],
  [10, 'row: Claude Code', 'blip', { pitch: 'A5', pan: 0.25, gain: 0.3 }],
  [12, 'row: Projects', 'blip', { pitch: 'C6', pan: 0.3, gain: 0.3 }],
  [14, 'row: Claude in Chrome and Microsoft 365', 'blip', { pitch: 'F6', pan: 0.35, gain: 0.3 }],
  [16, 'Ask bar rises', 'whoosh', { len: 0.45, from: 2200, to: 600, gain: 0.25 }],
  [18, 'Ask Claude pressed', 'click', { gain: 0.45 }],
  [20, 'swell into end card (ends on the cut)', 'swell', { len: 0.9, gain: 0.3 }],
  [20, 'end card', 'impact', { gain: 0.4 }],
  [21, 'url types on', 'tick+type', { n: 18, len: 0.9, gain: 0.5 }],
];

// ---------------------------------------------------------------- sources (gathered, @2x)
const CARD = [1024, 930, 834, 1528];                      // the real Pro card in section_00_pricing.png
const ROW_Y = (i) => 1872 + 65.7 * i;                     // row centres in the card ("More usage*" = 0)
const ROWS = [1, 3, 5, 7];                                // Hand off… · Claude Code · Projects · Chrome & M365
const ROW_SRC = (i) => [1080, ROW_Y(i) - 33, 720, 66];
const HEAD_SRC = [1080, 1770, 600, 56];                   // "Everything in Free, plus:"
const PRICE_UL = [1088, 1410, 76];                        // under "$17": x, y, width (source px)
const BAR = [880, 16082, 1120, 108];                      // the real Ask Claude input bar
const BTN = [1713, 16100, 269, 72];                       // its clay button
// The full-page screenshots are huge, so the film loads small crops of them; coordinates above stay
// in full-page space and these origins map them into the crops.
const O = { pricing: [1000, 900], overview: [860, 16060] };
const cropAt = (ctx, img, key, [sx, sy, sw, sh], x, y, w, h) => crop(ctx, img, [sx - O[key][0], sy - O[key][1], sw, sh], x, y, w, h);

// ---------------------------------------------------------------- S1 hook  (u 0..4)
const HOOK = [['Hand', 'Claude', 'a', 'task,'], ['not', 'just', 'a', 'question.']];
function hook(ctx, u, IMG, push) {
  const s = FORMAT.safe;
  const size = 150, f = font(size, 500, DISPLAY), lineH = size * 1.12;
  const x0 = s.x + 230, y0 = 500 - push;
  // spark: fills the frame on frame 0, spinning, then settles left of the headline by beat 1.5
  const k = springU(u, -0.12, { stiffness: 70, damping: 15 });   // frame 0: still huge and turning
  const sz = lerp(1900, 168, k), rot = (1 - k) * 2.4 + 0.15 * M.ring(u * 0.625 - 1.0, 1.6, 4);
  const sx = lerp(W / 2, s.x + 70, k), sy = lerp(H / 2, y0 - size * 0.36, k);
  if (IMG.spark) {
    ctx.save(); ctx.translate(sx, sy); ctx.rotate(rot);
    ctx.drawImage(IMG.spark, -sz / 2, -sz / 2, sz, sz); ctx.restore();
  }
  HOOK.forEach((words, li) => {
    let x = x0;
    const base = y0 + li * lineH;
    words.forEach((w, wi) => {
      const L = layout(ctx, w, f, -0.01 * size);
      const u0 = li * 2 + wi * 0.5 - (li === 0 && wi === 0 ? 0.25 : 0);
      ctx.save(); ctx.beginPath(); ctx.rect(0, base - size * 1.05, W, size * 1.4); ctx.clip();   // rise from the baseline
      L.glyphs.forEach((g, j) => {
        const p = springU(u, u0 + j * 0.025, { stiffness: 210, damping: 22 });
        if (p <= 0.001) return;
        glyph(ctx, g.ch, x + g.cx, base + (1 - p) * size * 1.1, f, li ? C.muted : C.ink);
      });
      ctx.restore();
      x += L.width + size * 0.26;
    });
  });
}

// ---------------------------------------------------------------- camera on the card  (u 3.4..17)
// view = [zoom, card-space cx, cy, screen ax, ay]: card point (cx,cy) lands at screen (ax,ay)
function cardView(u) {
  return springKeys(u, [
    [0, [0.9, 1440, 1250, 960, 540 + 1100]],
    [3.35, [0.9, 1440, 1250, 960, 540], { stiffness: 150, damping: 17 }],      // rises, lands on the drop with a little overshoot
    [5.6, [1.32, 1290, 1385, 900, 520], SPRING.gentle],                        // ease to the price
    [7.6, [0.62, 1440, 1694, 400, 540], { stiffness: 120, damping: 19 }],       // whole card, left third
    [15.6, [0.62, 1440, 1694, -420, 540], { stiffness: 140, damping: 20 }],     // leaves left as the bar comes in
  ], SPRING.gentle);
}
const toScreen = ([z, cx, cy, ax, ay], x, y) => [ax + (x - cx) * z, ay + (y - cy) * z];

function card(ctx, u, IMG) {
  const v = cardView(u), [z] = v;
  const [x, y] = toScreen(v, CARD[0], CARD[1]);
  const w = CARD[2] * z, h = CARD[3] * z;
  const tilt = (1 - springU(u, 3.35, { stiffness: 150, damping: 17 })) * -0.06;
  ctx.save();
  ctx.translate(x + w / 2, y + h / 2); ctx.rotate(tilt); ctx.translate(-(x + w / 2), -(y + h / 2));
  // soft contact shadow, no glow
  ctx.save(); ctx.shadowColor = 'rgba(20,20,19,0.10)'; ctx.shadowBlur = 60 * z; ctx.shadowOffsetY = 24 * z;
  rrect(ctx, x + 2 * z, y + 2 * z, w - 4 * z, h - 4 * z, 46 * z); ctx.fillStyle = C.white; ctx.fill(); ctx.restore();
  ctx.save(); rrect(ctx, x, y, w, h, 48 * z); ctx.clip();
  if (IMG.pricing) cropAt(ctx, IMG.pricing, 'pricing', CARD, x, y, w, h);
  // $17 underline draws on beat 6
  const ul = E.outCubic(prog(u, 6, 6.6));
  if (ul > 0) {
    const [ux, uy] = toScreen(v, PRICE_UL[0], PRICE_UL[1]);
    ctx.fillStyle = C.clay; ctx.fillRect(ux, uy, PRICE_UL[2] * z * ul, 6 * z);
  }
  // the rows that leave get a clay tint in the card as they go
  ROWS.forEach((ri, k) => {
    const a = prog(u, 8 + 2 * k - 0.1, 8 + 2 * k + 0.3) * 0.16;
    if (a <= 0) return;
    const [rx, ry] = toScreen(v, 1060, ROW_Y(ri) - 30);
    ctx.save(); ctx.globalCompositeOperation = 'multiply'; ctx.fillStyle = C.clay; alpha(ctx, a);
    rrect(ctx, rx, ry, 760 * z, 60 * z, 10 * z); ctx.fill(); ctx.restore();
  });
  ctx.restore(); ctx.restore();
  return v;
}

// ---------------------------------------------------------------- S3 rows stack  (u 8..16.5)
const STACK = { x: 790, y: 300, pitch: 142, s: 1.45 };
function rows(ctx, u, IMG, v) {
  if (!IMG.pricing) return;
  const out = springU(u, 15.7, { stiffness: 160, damping: 20 });       // stack leaves upward
  const dy = -out * (H * 0.9);
  // header line, real crop
  const hp = springU(u, 7.8, { stiffness: 170, damping: 20 });
  if (hp > 0.001) {
    ctx.save(); alpha(ctx, hp * 1.5); ctx.globalCompositeOperation = 'multiply';   // card white -> ivory ground
    const s = 1.25;
    cropAt(ctx, IMG.pricing, 'pricing', HEAD_SRC, STACK.x + 24, STACK.y - 120 + (1 - hp) * 40 + dy, HEAD_SRC[2] * s, HEAD_SRC[3] * s);
    ctx.restore();
  }
  ROWS.forEach((ri, k) => {
    const b = 8 + 2 * k;
    const p = springU(u, b - 0.2, { stiffness: 190, damping: 18 });   // ~8 % overshoot, lands on the beat
    if (p <= 0.001) return;
    const src = ROW_SRC(ri);
    const [fx, fy] = toScreen(v, src[0], src[1]);
    const tx = STACK.x, ty = STACK.y + k * STACK.pitch + dy;
    const sc = lerp(v[0], STACK.s, p);
    const x = lerp(fx, tx, p), y = lerp(fy, ty, p);
    const w = src[2] * sc, h = src[3] * sc;
    ctx.save();
    ctx.globalCompositeOperation = 'multiply';                 // card white -> ivory ground
    cropAt(ctx, IMG.pricing, 'pricing', src, x, y, w, h);
    ctx.globalCompositeOperation = 'source-over';
    // replace the grey check with a clay one that draws on after landing
    const cx = x + (1108 - src[0]) * sc, cw = 46 * sc;
    ctx.fillStyle = C.ivory; ctx.fillRect(x + (1090 - src[0]) * sc, y + 2 * sc, (1156 - 1090) * sc, h - 4 * sc);
    const d = E.outCubic(prog(u, b + 0.05, b + 0.55));
    if (d > 0) {
      ctx.strokeStyle = C.clay; ctx.lineWidth = 4.2 * sc; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
      const pts = [[cx + 8 * sc, y + 34 * sc], [cx + 20 * sc, y + 46 * sc], [cx + 40 * sc, y + 20 * sc]];
      const l1 = Math.hypot(12, 12), l2 = Math.hypot(20, 26), tot = l1 + l2, along = d * tot;
      ctx.beginPath(); ctx.moveTo(...pts[0]);
      if (along <= l1) ctx.lineTo(lerp(pts[0][0], pts[1][0], along / l1), lerp(pts[0][1], pts[1][1], along / l1));
      else { ctx.lineTo(...pts[1]); const q = (along - l1) / l2; ctx.lineTo(lerp(pts[1][0], pts[2][0], q), lerp(pts[1][1], pts[2][1], q)); }
      ctx.stroke();
    }
    ctx.restore();
  });
}

// ---------------------------------------------------------------- S4 Ask Claude  (u 15.8..20)
const ASK = { x: 176, y: 560, s: 1.4 };
function ask(ctx, u, IMG) {
  const s = FORMAT.safe;
  const rise = springU(u, 15.85, { stiffness: 170, damping: 19 });
  const lift = (1 - rise) * (H * 0.75);
  // headline in the brand's own words (claude.com/product/overview), left-aligned on the bar
  const line = 'Don’t know where to start? Ask Claude.';
  const size = Math.min(96, M.fitSize(ctx, line, 500, DISPLAY, BAR[2] * ASK.s * 0.96, 96, -0.01)), f = font(size, 500, DISPLAY);
  let x = ASK.x;
  line.split(' ').forEach((w, wi) => {
    const L = layout(ctx, w, f, -0.01 * size);
    const base = ASK.y - 120 + lift * 0.6;
    ctx.save(); ctx.beginPath(); ctx.rect(0, base - size, W, size * 1.35); ctx.clip();
    const p = springU(u, 16 + wi * 0.18, { stiffness: 200, damping: 22 });
    if (p > 0.001) L.glyphs.forEach((g) => glyph(ctx, g.ch, x + g.cx, base + (1 - p) * size * 1.1, f, wi >= 5 ? C.clay : C.ink));
    ctx.restore();
    x += L.width + size * 0.25;
  });
  if (!IMG.overview) return;
  // the real bar; the button presses on beat 18
  const press = M.bump(u, 18.12, 0.28);
  const bw = BAR[2] * ASK.s, bh = BAR[3] * ASK.s, by = ASK.y + lift;
  ctx.save();
  ctx.translate(ASK.x + bw / 2, by + bh / 2); ctx.scale(1 - press * 0.012, 1 - press * 0.012); ctx.translate(-(ASK.x + bw / 2), -(by + bh / 2));
  rrect(ctx, ASK.x, by, bw, bh, 26 * ASK.s); ctx.save(); ctx.clip();
  cropAt(ctx, IMG.overview, 'overview', BAR, ASK.x, by, bw, bh);
  ctx.restore();
  if (press > 0) {   // button darkens a touch while pressed
    const [bx0, by0] = [ASK.x + (BTN[0] - BAR[0]) * ASK.s, by + (BTN[1] - BAR[1]) * ASK.s];
    ctx.save(); ctx.globalCompositeOperation = 'multiply'; alpha(ctx, press * 0.25); ctx.fillStyle = C.clayDeep;
    rrect(ctx, bx0, by0, BTN[2] * ASK.s, BTN[3] * ASK.s, 16 * ASK.s); ctx.fill(); ctx.restore();
  }
  ctx.restore();
}

// the button grows into the end card's clay field (beat 19 → 20)
function expand(ctx, u) {
  const p = springU(u, 18.95, { stiffness: 120, damping: 20 });
  if (p <= 0.001) return;
  const bx0 = ASK.x + (BTN[0] - BAR[0]) * ASK.s, by0 = ASK.y + (BTN[1] - BAR[1]) * ASK.s;
  const bw = BTN[2] * ASK.s, bh = BTN[3] * ASK.s;
  const q = clamp(p);
  const x = lerp(bx0, -40, q), y = lerp(by0, -40, q), w = lerp(bw, W + 80, q), h = lerp(bh, H + 80, q);
  rrect(ctx, x, y, w, h, lerp(16 * ASK.s, 0, q));
  ctx.fillStyle = mix(C.clayDeep, C.clay, prog(u, 19.6, 20.4)); ctx.fill();
}

// ---------------------------------------------------------------- S5 end card  (u 20..24)
function endCard(ctx, u, IMG) {
  fill(ctx, mix(C.clayDeep, C.clay, prog(u, 19.6, 20.4)));
  const p = springU(u, 19.85, { stiffness: 170, damping: 17 });
  const wmH = 112, wmW = wmH * (424 / 97);
  const proF = font(132, 500, DISPLAY), proL = layout(ctx, 'Pro', proF, -1);
  const gap = 34, spark = 118;
  const total = spark + 30 + wmW + gap + proL.width;
  const x0 = (W - total) / 2, base = 500;
  ctx.save(); alpha(ctx, p * 2); ctx.translate(0, (1 - p) * 40);
  if (IMG.sparkIvory) {
    const r = (1 - p) * -1.2;
    ctx.save(); ctx.translate(x0 + spark / 2, base - wmH * 0.45); ctx.rotate(r);
    ctx.drawImage(IMG.sparkIvory, -spark / 2, -spark / 2, spark, spark); ctx.restore();
  }
  if (IMG.wordIvory) ctx.drawImage(IMG.wordIvory, x0 + spark + 30, base - wmH * 0.93, wmW, wmH);
  ctx.restore();
  // "Pro" in the display serif, lands half a beat later
  const pp = springU(u, 20.35, { stiffness: 200, damping: 18 });
  if (pp > 0.001) {
    ctx.save(); ctx.beginPath(); ctx.rect(0, base - 150, W, 190); ctx.clip();
    text(ctx, 'Pro', x0 + spark + 30 + wmW + gap, base + 6 + (1 - pp) * 150, proF, C.ivory);
    ctx.restore();
  }
  // card copy, then the URL types on from beat 21
  const lp = springU(u, 20.7, SPRING.gentle);
  if (lp > 0.001) {
    ctx.save(); alpha(ctx, lp); text(ctx, 'For everyday work.', W / 2, base + 120 + (1 - lp) * 20, font(56, 400, UI), C.ivory, 'center'); ctx.restore();
  }
  const url = 'claude.com/pricing', n = Math.floor(clamp((u - 21) / 0.9) * url.length + 1e-6);
  if (n > 0) text(ctx, url.slice(0, n), W / 2, base + 228, font(58, 500, UI), C.ink, 'center');
}

M.film({
  fonts: [font(132, 500, DISPLAY), font(96, 500, DISPLAY), font(56, 400, UI), font(58, 500, UI)],
  images: {
    spark: 'assets/logo/spark.svg', sparkIvory: 'assets/logo/spark_ivory.svg', wordIvory: 'assets/logo/wordmark_ivory.svg',
    pricing: 'assets/shots/pro_card_src.png', overview: 'assets/shots/ask_bar_src.png',
  },
  hits: HITS,
  draw(ctx, u, t, IMG) {
    if (u >= 20) { endCard(ctx, u, IMG); return; }
    fill(ctx, C.ivory);
    // the card pushes the hook up as it rises (beats 3.4–4.2)
    const v = cardView(u);
    const cardTop = toScreen(v, CARD[0], CARD[1])[1];
    // the card pushes the hook up as it rises, then the hook clears the frame entirely by beat 5
    const push = Math.max(0, 760 - cardTop) + springU(u, 4.1, { stiffness: 160, damping: 20 }) * 520;
    if (u < 5.6) hook(ctx, u, IMG, push);
    let view = v;
    if (u >= 3.2 && u < 17.2) view = card(ctx, u, IMG);
    if (u >= 7.7 && u < 17.2) rows(ctx, u, IMG, view);
    if (u >= 15.8) ask(ctx, u, IMG);
    if (u >= 18.9) expand(ctx, u);
  },
});
