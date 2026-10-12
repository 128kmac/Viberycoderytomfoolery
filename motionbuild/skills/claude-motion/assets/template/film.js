// __TITLE__ — a pure function of time. Everything is timed in beats (u).
// Replace the brand tokens, copy and scenes; keep the structure:
// scene table -> per-scene draw functions -> M.film({...}).
import * as M from './lib/motion.js';
import { HITS } from './hits.js';
const { E, FORMAT: F, W, H } = M;

// Brand tokens: from assets/brand.json. ONE accent.
const C = {
  bg: '#0e0e10', ink: '#f4f1ea', mute: '#8a8780', accent: '#ff5a1f', panel: '#1b1b1f',
};
const COPY = {
  words: ['Make', 'it', 'move.'],
  features: ['Pure function of time', 'Frame-exact render', 'Mixed to −14 LUFS'],
  name: '__TITLE__',
  url: 'example.com',
  line: 'Motion, from code.',
};

// Scenes in beats. Frame 0 is a shot, not a lead-in.
const S = { open: [0, 8], card: [8, 24], end: [24, 999] };

// Layout per format, never a crop of 16x9.
const L = F.pick({
  '16x9': { head: 210, card: [0.56, 0.62], feat: 44, endName: 150 },
  '9x16': { head: 190, card: [0.86, 0.52], feat: 56, endName: 180 },
  '1x1': { head: 170, card: [0.8, 0.48], feat: 46, endName: 120 },
});

function opener(ctx, u) {
  const s = F.safe;
  // Never wider than the safe area: fit the longest line.
  const longest = F.portrait ? COPY.words.reduce((a, b) => (a.length > b.length ? a : b)) : COPY.words.join(' ');
  const size = Math.min(L.head, M.fitSize(ctx, longest, s.w * 0.92, { weight: 800, track: -0.03 }));
  const f = M.font(size, 800);
  // Words spring in on beats 0,1,2; the first starts 0.25 beat early so frame 0 is already moving.
  const lines = F.portrait ? COPY.words.map((w) => [w]) : [COPY.words];
  const lh = size * 1.02;
  const y0 = s.cy - (lines.length - 1) * lh / 2 + size * 0.35;
  let wi = 0;
  lines.forEach((line, li) => {
    const str = line.join(' ');
    const start = wi;
    M.glyphs(ctx, str, s.cx, y0 + li * lh, f, C.ink, (i, n, g) => {
      // which word is this glyph in?
      const word = start + str.slice(0, i + 1).split(' ').length - 1;
      const u0 = word - 0.25 + (i % 6) * 0.03;
      const p = M.springU(u, u0, M.SPRING.bouncy);
      const out = M.springU(u, S.open[1] - 0.5 + i * 0.02, M.SPRING.snappy);
      return { dy: (1 - p) * size * 0.9 - out * size * 1.4, alpha: M.clamp(p * 3) * M.clamp(1 - out), sy: 0.85 + 0.15 * p, color: word === COPY.words.length - 1 ? C.accent : C.ink };
    }, { align: 'center', track: -0.03 });
    wi += line.length;
  });
  // A rule that draws under the headline on beat 3 and carries into the card.
  const r = M.springU(u, 3, M.SPRING.gentle) * (1 - M.prog(u, 7.5, 8));
  ctx.fillStyle = C.accent;
  ctx.fillRect(s.cx - (s.w * 0.3) * r, y0 + (lines.length - 1) * lh + size * 0.35, s.w * 0.6 * r, 8);
}

function card(ctx, u, IMG) {
  const s = F.safe;
  const enter = M.springU(u, S.card[0], M.SPRING.bouncy);
  const push = M.springU(u, 20, M.SPRING.gentle);
  const exit = M.springU(u, S.card[1] - 0.5, M.SPRING.snappy);
  const [cwF, chF] = L.card;
  const cw = s.w * cwF, ch = s.h * chF;
  const cx = F.landscape ? s.x + cw / 2 + 20 : s.cx;
  const cy = F.landscape ? s.cy : s.y + ch / 2 + 40;
  ctx.save();
  ctx.translate(cx, cy + (1 - enter) * H * 0.6 - exit * H);
  M.zoomAbout(ctx, 0.92 + 0.08 * enter + 0.06 * push, 0, 0);
  ctx.rotate((1 - enter) * 0.08);
  M.shadow(ctx, 60, 30, 0.35);
  M.rrect(ctx, -cw / 2, -ch / 2, cw, ch, 28); ctx.fillStyle = C.panel; ctx.fill();
  ctx.shadowColor = 'transparent';
  // Real product shot if gathered (images.shot); otherwise pure type, never an invented UI.
  if (IMG.shot) M.cover(ctx, IMG.shot, -cw / 2, -ch / 2, cw, ch, { radius: 28, fy: 0, zoom: 1 + 0.1 * M.prog(u, 8, 24) });
  else M.text(ctx, COPY.name, 0, 30, M.font(Math.min(120, M.fitSize(ctx, COPY.name, cw * 0.8, { weight: 800 })), 800), C.ink, { align: 'center' });
  ctx.restore();
  // Features tick on beats 12/14/16 beside (16x9) or below (9x16, 1x1) the card.
  COPY.features.forEach((ft, i) => {
    const ub = 12 + i * 2, p = M.springU(u, ub, M.SPRING.snappy), o = M.clamp(1 - exit);
    if (p <= 0.001) return;
    const fx = F.landscape ? s.x + cw + 110 : s.x + 40;
    const fy = F.landscape ? s.cy - 90 + i * (L.feat * 2) : cy + ch / 2 + 110 + i * (L.feat * 1.9);
    ctx.save(); M.alpha(ctx, M.clamp(p * 2) * o); ctx.translate((1 - p) * 60, 0);
    ctx.fillStyle = C.accent; ctx.beginPath(); ctx.arc(fx, fy - L.feat * 0.33, 9 * (0.6 + 0.4 * p + 0.3 * M.ring(u, ub)), 0, M.TAU); ctx.fill();
    M.text(ctx, ft, fx + 34, fy, M.font(L.feat, 600, 'UI'), C.ink);
    ctx.restore();
  });
}

function endCard(ctx, u) {
  const s = F.safe;
  const p = M.springU(u, S.end[0], M.SPRING.bouncy);
  const size = Math.min(L.endName, M.fitSize(ctx, COPY.name, s.w * 0.9, { weight: 800 }));
  const y = s.cy;
  ctx.save(); ctx.translate(s.cx, y); M.zoomAbout(ctx, 0.8 + 0.2 * p, 0, 0); M.alpha(ctx, p * 2);
  M.text(ctx, COPY.name, 0, 0, M.font(size, 800), C.ink, { align: 'center', track: -0.02 });
  ctx.restore();
  // URL types on from beat 25, one glyph per 0.12 beat.
  const nChars = Math.floor(M.clamp((u - 25) / (COPY.url.length * 0.12)) * COPY.url.length);
  M.text(ctx, COPY.url.slice(0, nChars), s.cx, y + size * 0.75, M.font(Math.max(36, size * 0.36), 600, 'UI'), C.accent, { align: 'center' });
  const lp = M.springU(u, 26, M.SPRING.gentle);
  M.text(ctx, COPY.line, s.cx, y - size * 1.0, M.font(Math.max(34, size * 0.32), 500, 'UI'), M.mix(C.bg, C.mute, lp), { align: 'center' });
}

function draw(ctx, u, t, IMG) {
  // Background: brand bg with a slow accent wash that pulses on downbeats.
  M.fill(ctx, M.mix(C.bg, C.panel, 0.4 * M.prog(u, 8, 24) * (1 - M.prog(u, 23.5, 24.5))));
  const pulse = M.bump(u % 4, 0, 0.6) * 0.06;
  const g = ctx.createRadialGradient(W * 0.8, H * 0.15, 0, W * 0.8, H * 0.15, Math.max(W, H) * 0.7);
  g.addColorStop(0, M.rgba(C.accent, 0.10 + pulse)); g.addColorStop(1, M.rgba(C.accent, 0));
  ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);

  ctx.save(); M.shake(ctx, u, 8, 10); M.shake(ctx, u, 24, 8);
  if (u < S.open[1] + 0.5) opener(ctx, u);
  if (u >= S.card[0] - 0.1 && u < S.card[1] + 1) card(ctx, u, IMG);
  if (u >= S.end[0] - 0.1) endCard(ctx, u);
  ctx.restore();
}

M.film({
  draw,
  hits: HITS,
  fonts: [M.font(100, 800), M.font(40, 600, 'UI'), M.font(40, 500, 'UI')],
  images: {
    // shot: 'assets/shots/desktop_viewport.png',
  },
});
