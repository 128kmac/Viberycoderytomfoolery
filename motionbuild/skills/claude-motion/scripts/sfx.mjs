#!/usr/bin/env node
// Render <film>/hits.js into <film>/audio/sfx.wav on the beat grid, and write
// out/<film>/hits.json (resolved times) for sync checks.
// usage: node <skill>/scripts/sfx.mjs <film>     |     node <skill>/scripts/sfx.mjs --list
import path from 'node:path';
import { parseArgs, die, log, loadFilm, loadHits, readJSON, writeJSON, writeWav, rel } from './lib/common.mjs';
import * as D from './lib/dsp.mjs';

const STEM = 0.4; // sits the SFX stem ~2-3 LU under the music bed before mixing

// anchor: where the hit time lands inside the sound. start = attack on the beat,
// peak = loudest point on the beat (whoosh), end = sound finishes on the beat (riser, swell).
const PALETTE = {
  pop:    { gain: 0.35, anchor: 'start', doc: 'bubbly pitch drop; word/element pops on', make: (r, o) => { const n = D.sec(o.len ?? 0.12), f0 = D.hz(o.pitch ?? 700), f1 = o.to ? D.hz(o.to) : f0 * 0.55; const y = D.mul(D.osc(n, (t) => f0 * (f1 / f0) ** Math.min(1, t / (n / D.SR * 0.25))), D.expDecay(n, 0.03)); return D.add(y, D.mul(D.filt(D.noise(D.sec(0.004), r), 'hp', 3000), D.expDecay(D.sec(0.004), 0.001)), 0, 0.3); } },
  click:  { gain: 0.3, anchor: 'start', doc: 'UI click; cursor taps, toggles', make: (r) => { const n = D.sec(0.025), y = D.filt(D.filt(D.noise(n, r), 'hp', 2500), 'lp', 9000); D.add(y, D.osc(n, 1800), 0, 0.4); return D.mul(y, D.expDecay(n, 0.004)); } },
  tick:   { gain: 0.22, anchor: 'start', doc: 'tiny high tick; list items, counters', make: (r, o) => D.mul(D.osc(D.sec(0.03), D.hz(o.pitch ?? 2400)), D.expDecay(D.sec(0.03), 0.005)) },
  blip:   { gain: 0.2, anchor: 'start', doc: 'soft sine blip with pitch; checkmarks, badges', make: (r, o) => { const n = D.sec(0.14), f = D.hz(o.pitch ?? 'C6'); return D.mul(D.osc(n, (t) => f * (1 + 0.5 * Math.exp(-t / 0.01))), D.adsr(n, 0.002, 0.04, 0.3, 0.06)); } },
  thud:   { gain: 0.45, anchor: 'start', doc: 'low body thump; cards landing', make: (r) => { const n = D.sec(0.3), y = D.osc(n, (t) => 50 + 100 * Math.exp(-t / 0.04)); D.add(y, D.filt(D.noise(n, r), 'bp', 300, 1.5), 0, 0.3); return D.sat(D.mul(y, D.expDecay(n, 0.08)), 2); } },
  tok:    { gain: 0.35, anchor: 'start', doc: 'wooden FM mallet; playful UI', make: (r, o) => { const n = D.sec(0.18), f = D.hz(o.pitch ?? 'G5'); const y = new Float32Array(n); for (let i = 0; i < n; i++) { const t = i / D.SR; y[i] = Math.sin(D.TAU * f * t + 3 * Math.exp(-t / 0.01) * Math.sin(D.TAU * f * 2.4 * t)); } return D.mul(y, D.expDecay(n, 0.035)); } },
  bell:   { gain: 0.3, anchor: 'start', doc: 'inharmonic bell; success, reveal', make: (r, o) => D.bell(o.pitch ?? 'E6', o.len ?? 1.2) },
  coins:  { gain: 0.3, anchor: 'start', doc: 'n bells scattered over spread s; money, rewards', make: (r, o) => { const n = o.n ?? 5, sp = o.spread ?? 0.25, y = new Float32Array(D.sec(sp + 1)); for (let i = 0; i < n; i++) D.add(y, D.bell(D.mtof(84 + Math.floor(r() * 10)), 0.6), D.sec(r() * sp), 0.5); return y; } },
  type:   { gain: 0.2, anchor: 'start', doc: 'n key clicks over len s; typing text', make: (r, o) => { const n = o.n ?? 8, len = o.len ?? 0.6, y = new Float32Array(D.sec(len + 0.05)); for (let i = 0; i < n; i++) { const c = D.filt(D.noise(D.sec(0.02), r), 'bp', 2500 + r() * 2500, 2); D.add(y, D.mul(c, D.expDecay(c.length, 0.004)), D.sec((i / n) * len + (i ? r() * 0.015 : 0)), i ? 0.6 + r() * 0.3 : 1); } return y; } },
  boing:  { gain: 0.3, anchor: 'start', doc: 'cartoon spring; bouncy overshoot', make: (r, o) => { const n = D.sec(0.5), f = D.hz(o.pitch ?? 220); return D.mul(D.sweep(D.osc(n, (t) => f * (1 + 0.6 * Math.exp(-t / 0.08)) * (1 + 0.05 * Math.sin(D.TAU * 14 * t)), 'saw'), 'lp', (p) => 3000 * (1 - p) + 300), D.expDecay(n, 0.15)); } },
  whoosh: { gain: 0.3, anchor: 'peak', doc: 'band-pass noise swish, PEAKS on the hit; moves, wipes', peak: (o) => (o.len ?? 0.6) * (o.peak ?? 0.7), make: (r, o) => D.whoosh(r, o.len ?? 0.6, { from: o.from ?? 400, to: o.to ?? 3200, peak: o.peak ?? 0.7 }) },
  riser:  { gain: 0.35, anchor: 'end', doc: 'noise + tone rise, ENDS on the hit; into a section change', make: (r, o) => D.riser(r, o.len ?? 1.5, { from: o.from ?? 300, to: o.to ?? 6000 }) },
  swell:  { gain: 0.25, anchor: 'end', doc: 'reversed cymbal, ENDS on the hit; into a reveal', make: (r, o) => { const y = D.reverse(D.crash(r, { len: o.len ?? 1.2 })); y.fill(0, y.length - D.sec(0.01)); return y; } },
  crash:  { gain: 0.25, anchor: 'start', doc: 'cymbal; section downbeat', make: (r, o) => D.crash(r, { len: o.len ?? 2 }) },
  sub:    { gain: 0.6, anchor: 'start', doc: 'sub drop; weight under a big moment', make: (r, o) => D.subDrop(o.len ?? 1.2) },
  impact: { gain: 0.7, anchor: 'start', doc: 'sub + thud + crash; drops, scene changes, end card (use sparingly)', make: (r, o) => { const y = new Float32Array(D.sec(2)); D.add(y, D.subDrop(1.2), 0, 0.7); D.add(y, PALETTE.thud.make(r, o), 0, 0.8); D.add(y, D.crash(r, { len: 1.8 }), 0, 0.35); return y; } },
  glitch: { gain: 0.25, anchor: 'start', doc: 'digital stutter; data, tech, errors', make: (r, o) => { const n = D.sec(o.len ?? 0.18), y = new Float32Array(n); let v = 0; for (let i = 0; i < n; i++) { if (i % 240 === 0) v = r() < 0.5 ? (r() * 2 - 1) : 0; y[i] = v * (r() < 0.9 ? 1 : 0); } return D.filt(y, 'hp', 400); } },
  shutter:{ gain: 0.3, anchor: 'start', doc: 'camera shutter; screenshots, snaps', make: (r) => { const y = new Float32Array(D.sec(0.12)); for (const off of [0, 0.06]) { const c = D.filt(D.noise(D.sec(0.03), r), 'bp', 3500, 1.5); D.add(y, D.mul(c, D.expDecay(c.length, 0.006)), D.sec(off)); } return y; } },
};

const a = parseArgs();
if (a.list) {
  log('SFX palette  (name · default gain · anchor — use)');
  for (const [k, v] of Object.entries(PALETTE)) log(`  ${k.padEnd(8)} ${String(v.gain).padEnd(5)} ${v.anchor.padEnd(5)} — ${v.doc}`);
  log('\nopts: gain, pan(-1..1), pitch(Hz|note), to, from, len(s), peak(0..1), anchor, verb(reverb send, default .15), n, spread');
  log("layer with '+': 'tick+blip'. null sfx = silent accent (still listed for sync).");
  process.exit(0);
}

const { P, cfg } = loadFilm(a._[0]);
const beats = readJSON(P.beats);
const hits = await loadHits(P);
if (!hits.length) die(`${rel(P.hits)} has no HITS`);
const dur = cfg.duration;
const L = new Float32Array(D.sec(dur + 3)), R = new Float32Array(L.length), send = new Float32Array(L.length);
const resolved = [], silent = [];
hits.forEach(([beat, label, sfx, opts = {}], k) => {
  const t = beats.offset + beat * beats.period;
  resolved.push({ beat, t: +t.toFixed(4), label, sfx: sfx ?? null, opts });
  if (!sfx) { silent.push(`${beat} ${label}`); return; }
  sfx.split('+').forEach((name, j) => {
    const def = PALETTE[name.trim()];
    if (!def) die(`unknown sfx "${name}" at beat ${beat} (${label}). See --list.`);
    const rng = D.mulberry32(k * 7919 + j * 104729 + 1);
    const y = def.make(rng, opts);
    const anchor = opts.anchor ?? def.anchor, len = y.length / D.SR;
    const lead = anchor === 'end' ? len : anchor === 'peak' ? (def.peak?.(opts) ?? len / 2) : 0;
    const g = (opts.gain ?? def.gain) * STEM, pan = opts.pan ?? 0, ang = (pan + 1) * Math.PI / 4;
    const at = Math.round((t - lead) * D.SR);
    D.add(L, y, at, g * Math.cos(ang) * Math.SQRT2);
    D.add(R, y, at, g * Math.sin(ang) * Math.SQRT2);
    D.add(send, y, at, g * (opts.verb ?? 0.15));
  });
});
const [rl, rr] = D.freeverb(send, { room: 0.8, damp: 0.35, tail: 0 });
D.add(L, rl); D.add(R, rr);
const n = D.sec(dur);
const out = path.join(P.audio, 'sfx.wav');
writeWav(out, [L.slice(0, n), R.slice(0, n)]);
writeJSON(path.join(P.out, 'hits.json'), resolved);
log(`✓ ${rel(out)}  ${hits.length - silent.length} sounding hits`);
if (silent.length) log(`  silent accents: ${silent.join(' · ')}`);
