#!/usr/bin/env node
// Use a SUPPLIED music track: measure its beat grid, pick the best excerpt that
// fits the film starting on a downbeat, cut it, and write beats.json.
// The grid is measured, never assumed. (For synthesized music use score.mjs.)
// usage: node <skill>/scripts/beats.mjs <film> --track song.mp3 [--start auto|SECONDS] [--bpm-hint 120] [--duration S]
// out:   <film>/audio/music.wav (excerpt, −3 dBFS peak), <film>/beats.json
import path from 'node:path';
import { parseArgs, die, log, loadFilm, writeJSON, writeWav, decodeAudio, normalizePeak, rel } from './lib/common.mjs';
import * as D from './lib/dsp.mjs';

const a = parseArgs();
const { P, cfg } = loadFilm(a._[0]);
if (!a.track) die('usage: beats.mjs <film> --track song.mp3 [--start auto|SECONDS]');
const duration = Number(a.duration ?? cfg.duration);
const [L, R] = decodeAudio(a.track);
const n = L.length, total = n / D.SR;
if (total < duration) die(`track is ${total.toFixed(1)} s, film needs ${duration} s`);
const mono = new Float32Array(n); for (let i = 0; i < n; i++) mono[i] = (L[i] + R[i]) / 2;

// 1. Onset envelopes: full band (beat) and low band (kick, for downbeat phase).
const O = D.onsetEnvelope(mono, { hop: 256, size: 1024 });
const low = D.onsetEnvelope(D.filt(D.filt(mono, 'lp', 150), 'lp', 150), { hop: 256, size: 1024 });
const env = O.env, rate = O.rate;
const norm = (x) => { let m = 0; for (const v of x) m += v; m /= x.length || 1; return x.map((v) => Math.max(0, v - m)); };
const e = norm(env), el = norm(low.env);

// 2. Tempo: autocorrelation over 60–180 bpm, weighted toward a hint (log-gaussian).
const hint = Number(a['bpm-hint'] ?? 120);
let best = { score: -1, lag: 0 };
for (let bpm = 60; bpm <= 180; bpm += 0.25) {
  const lag = (60 / bpm) * rate;
  let s = 0, cnt = 0;
  for (let i = 0; i + lag * 4 < e.length; i++) { const j = i + lag; const f = j - Math.floor(j); s += e[i] * ((1 - f) * e[Math.floor(j)] + f * e[Math.floor(j) + 1]); cnt++; }
  s = (s / Math.max(1, cnt)) * Math.exp(-0.5 * (Math.log2(bpm / hint) / 0.9) ** 2);
  if (s > best.score) best = { score: s, bpm, lag };
}
let period = 60 / best.bpm;

// 3. Phase: comb the envelope; pick the offset with most onset energy on the grid.
// Kicks mark the beat; wideband hats (often off-beat) dominate log flux, so the
// low band is weighted in. Both envelopes are normalised to their max first.
const mx = (x) => x.reduce((m, v) => Math.max(m, v), 1e-9);
const me = mx(e), mel = mx(el), en = e.map((v) => v / me), eln = el.map((v) => v / mel);
const ph = en.map((v, i) => v + 2 * (eln[i] ?? 0));
const combScore = (off, per, x) => { let s = 0; for (let t = off; t < total; t += per) { const i = Math.round(t * rate); s += (x[i] ?? 0) + 0.5 * ((x[i - 1] ?? 0) + (x[i + 1] ?? 0)); } return s; };
let offset = 0, bs = -1;
for (let k = 0; k < 200; k++) { const off = (k / 200) * period, s = combScore(off, period, ph); if (s > bs) { bs = s; offset = off; } }

// 4. Refine: snap grid beats to detected onsets within 40 ms, least-squares fit, reject outliers.
const onsets = D.pickOnsets(O, { delta: 0.05, wait: 0.08 });
let fit = { inliers: 0, rms: 0 };
for (let round = 0; round < 4; round++) {
  const pts = [];
  for (const o of onsets) { const k = Math.round((o - offset) / period), g = offset + k * period; if (Math.abs(o - g) < 0.04) pts.push([k, o]); }
  if (pts.length < 8) break;
  const mk = pts.reduce((s, p) => s + p[0], 0) / pts.length, mt = pts.reduce((s, p) => s + p[1], 0) / pts.length;
  let num = 0, den = 0; for (const [k, t] of pts) { num += (k - mk) * (t - mt); den += (k - mk) ** 2; }
  const per = num / den, off = mt - per * mk;
  const res = pts.map(([k, t]) => t - (off + per * k)), med = [...res].map(Math.abs).sort((x, y) => x - y)[Math.floor(res.length / 2)];
  const keep = pts.filter((_, i) => Math.abs(res[i]) < Math.max(0.006, 2.5 * med));
  period = per; offset = off;
  fit = { inliers: keep.length, rms: Math.sqrt(res.reduce((s, r) => s + r * r, 0) / res.length) * 1000 };
}
offset = ((offset % period) + period) % period;
const bpm = 60 / period;

// 5. Downbeat: of the 4 beat phases, the one with the most low-band (kick) energy.
let dphase = 0, ds = -1;
for (let p = 0; p < 4; p++) { const s = combScore(offset + p * period, period * 4, el); if (s > ds) { ds = s; dphase = p; } }
const firstDown = offset + dphase * period;

// 6. Choose the excerpt start: on a downbeat, either nearest --start or the loudest window.
const downs = []; for (let t = firstDown; t + duration <= total + 1e-6; t += period * 4) downs.push(t);
if (!downs.length) die('no downbeat leaves room for the film');
let start;
if (a.start && a.start !== 'auto') start = downs.reduce((b, t) => (Math.abs(t - Number(a.start)) < Math.abs(b - Number(a.start)) ? t : b), downs[0]);
else {
  const rms = (s0) => { let s = 0; const i0 = Math.round(s0 * D.SR), i1 = i0 + Math.round(duration * D.SR); for (let i = i0; i < i1; i += 64) s += mono[i] ** 2; return s; };
  start = downs.reduce((b, t) => (rms(t) > rms(b) ? t : b), downs[0]);
}
// Start 5 ms before the downbeat so the transient isn't clipped; the grid accounts for it.
const pre = 0.005, s0 = Math.max(0, Math.round((start - pre) * D.SR)), len = Math.round(duration * D.SR);
const cut = [L.slice(s0, s0 + len), R.slice(s0, s0 + len)];
for (const c of cut) { D.fadeIn(c, 0.005); D.fadeOut(c, Math.min(0.5, duration / 4), 2); }
normalizePeak(cut, -3);
const wav = path.join(P.audio, 'music.wav');
writeWav(wav, cut);

const off = start - s0 / D.SR; // seconds into the excerpt where beat 0 (a downbeat) lands
const beats = []; for (let t = off; t < duration + 0.25; t += period) beats.push(+t.toFixed(6));
writeJSON(P.beats, {
  bpm: +bpm.toFixed(3), period, offset: off, beats, downbeats: beats.filter((_, i) => i % 4 === 0),
  sections: {}, duration, beatsInFilm: Math.floor((duration - off) / period) + 1,
  source: `track:${path.basename(a.track)}@${start.toFixed(3)}s`, fit_inliers: fit.inliers, fit_residual_ms: +fit.rms.toFixed(2),
});
log(`✓ ${rel(wav)}  excerpt ${start.toFixed(2)}–${(start + duration).toFixed(2)} s of ${path.basename(a.track)} (starts on a downbeat)`);
log(`✓ ${rel(P.beats)}  ${bpm.toFixed(2)} bpm · offset ${(off * 1000).toFixed(1)} ms · fit ${fit.inliers} onsets, ${fit.rms.toFixed(1)} ms rms`);
if (fit.inliers < 16 || fit.rms > 15) log('! weak grid fit: check bpm (try --bpm-hint at the felt tempo, or half/double) and listen to a click track before building on it.');
