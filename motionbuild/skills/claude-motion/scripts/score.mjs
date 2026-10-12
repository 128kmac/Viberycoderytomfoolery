#!/usr/bin/env node
// Synthesize a score that fits the film exactly, and write its beat grid.
// The grid is known by construction (offset 0, period 60/bpm), so it is exact.
//
// usage: node <skill>/scripts/score.mjs <film> [--bpm auto|120] [--key A] [--mode major|minor|dorian|mixolydian]
//          [--flavor pulse|lofi|cinematic|minimal] [--drop BAR] [--seed N] [--duration S]
// writes: <film>/audio/music.wav (48 kHz float stereo, −3 dBFS peak), <film>/beats.json
import path from 'node:path';
import { parseArgs, die, log, loadFilm, writeJSON, writeWav, normalizePeak, rel } from './lib/common.mjs';
import * as D from './lib/dsp.mjs';

const a = parseArgs();
const { P, cfg } = loadFilm(a._[0]);
const duration = Number(a.duration ?? cfg.duration);
const flavor = a.flavor ?? 'pulse';
const FLAVORS = ['pulse', 'lofi', 'cinematic', 'minimal'];
if (!FLAVORS.includes(flavor)) die(`--flavor must be one of ${FLAVORS.join(', ')}`);
const seed = Number(a.seed ?? 20261012);
const rng = D.mulberry32(seed);

// Tempo: pick the bpm nearest the flavour's home tempo that makes the duration whole bars.
const HOME = { pulse: 124, lofi: 86, cinematic: 100, minimal: 120 };
const RANGE = { pulse: [112, 136], lofi: [72, 96], cinematic: [84, 120], minimal: [108, 132] };
function autoBpm() {
  const [lo, hi] = RANGE[flavor]; let best = null;
  for (let b = lo; b <= hi; b += 0.5) {
    const bars = duration * b / 240;
    if (Math.abs(bars - Math.round(bars)) < 1e-6 && (!best || Math.abs(b - HOME[flavor]) < Math.abs(best - HOME[flavor]))) best = b;
  }
  return best ?? HOME[flavor];
}
const bpm = a.bpm && a.bpm !== 'auto' ? Number(a.bpm) : autoBpm();
const period = 60 / bpm;
const nBeats = Math.ceil(duration / period - 1e-6);
const bars = Math.ceil(nBeats / 4);
const lastBar = Math.max(0, Math.floor((duration - 0.01) / (4 * period)));
const drop = Number(a.drop ?? (bars <= 6 ? 1 : bars <= 10 ? 2 : 4));
const dropBeat = Math.min(drop, lastBar) * 4;
const endBeat = lastBar * 4;

// Harmony: 4-chord loop per mode, voiced around the key.
const MODES = {
  major: { scale: [0, 2, 4, 5, 7, 9, 11], loop: [0, 4, 5, 3] },      // I V vi IV
  minor: { scale: [0, 2, 3, 5, 7, 8, 10], loop: [0, 5, 2, 6] },      // i VI III VII
  dorian: { scale: [0, 2, 3, 5, 7, 9, 10], loop: [0, 3, 0, 6] },     // i IV i bVII
  mixolydian: { scale: [0, 2, 4, 5, 7, 9, 10], loop: [0, 6, 3, 0] }, // I bVII IV I
};
const mode = a.mode ?? (flavor === 'cinematic' ? 'minor' : flavor === 'lofi' ? 'dorian' : 'major');
if (!MODES[mode]) die(`--mode must be one of ${Object.keys(MODES).join(', ')}`);
const key = a.key ?? (flavor === 'lofi' ? 'D' : 'A');
const root = D.midi(`${key}3`);
const { scale, loop } = MODES[mode];
const deg = (d) => root + scale[((d % 7) + 7) % 7] + 12 * Math.floor(d / 7);
// Triad + octave; lofi swaps the octave for the diatonic 7th.
const chord = (d) => [deg(d), deg(d + 2), deg(d + 4), flavor === 'lofi' ? deg(d + 6) : deg(d + 7)];
const chordAt = (bar) => loop[bar % 4];

const music = new D.Bus(duration, { bpm });
const drums = new D.Bus(duration, { bpm });
const bassB = new D.Bus(duration, { bpm });
const kicks = [];
const swing = flavor === 'lofi' ? 0.08 : 0;  // in beats, on off-eighths
const sw = (b) => b + ((b * 2) % 2 === 1 ? swing : 0);

for (let b = 0; b < nBeats; b++) {
  const bar = Math.floor(b / 4), inBar = b % 4, intro = b < dropBeat, end = b >= endBeat;
  const c = chordAt(bar);
  // ---- drums
  if (flavor === 'pulse' || flavor === 'minimal') {
    if (!end || inBar === 0) { drums.beat(D.kick(rng, { soft: intro }), b, { gain: intro ? 0.6 : 0.95 }); kicks.push(b * period); }
    if (!intro && !end && inBar % 2 === 1) drums.beat(flavor === 'minimal' ? D.rim(rng) : D.clap(rng), b, { gain: flavor === 'minimal' ? 0.35 : 0.45 });
    drums.beat(D.hat(rng, { open: !intro && flavor === 'pulse' }), b + 0.5, { gain: intro ? 0.15 : 0.22, pan: 0.2 });
    if (!intro && flavor === 'pulse') for (const s of [0.25, 0.75]) drums.beat(D.hat(rng), b + s, { gain: 0.08, pan: -0.25 });
    if (flavor === 'minimal' && !intro) drums.beat(D.shaker(rng), b + 0.75, { gain: 0.12, pan: 0.4 });
  } else if (flavor === 'lofi') {
    if (inBar === 0 || (inBar === 2 && !intro)) drums.beat(D.kick(rng, { soft: true, pitch: 52 }), b, { gain: 0.8 });
    if (inBar === 1 || inBar === 3) drums.beat(D.clap(rng), b, { gain: intro ? 0.18 : 0.3 });
    for (const s of [0, 0.5]) drums.beat(D.hat(rng), sw(b + s), { gain: s ? 0.09 : 0.13, pan: 0.2 });
  } else if (flavor === 'cinematic') {
    if (!intro && inBar === 0) drums.beat(D.kick(rng, { pitch: 40, len: 0.9 }), b, { gain: 0.9 });
    if (!intro && inBar === 2) drums.beat(D.kick(rng, { pitch: 62, len: 0.5 }), b + 0.5, { gain: 0.45, pan: -0.3 });
    if (!intro && !end) drums.beat(D.shaker(rng), b + 0.5, { gain: 0.1, pan: 0.3 });
  }

  // ---- bass (eighths for pulse/minimal, roots for lofi/cinematic)
  if (!intro && !end) {
    const r = deg(c) - 12;
    if (flavor === 'pulse' || flavor === 'minimal') {
      bassB.beat(D.bass(r, period * 0.45), b + 0.5, { gain: 0.5 });
      if (flavor === 'pulse') bassB.beat(D.bass(r + 12, period * 0.2, { cutoff: 1400 }), b + 0.75, { gain: 0.22 });
    } else if (inBar === 0) bassB.beat(D.bass(r, period * 3.6, { cutoff: 500, drive: 1.2 }), b, { gain: 0.5 });
  }
  // ---- melodic voices
  if (flavor === 'pulse' && !intro && !end && inBar % 2 === 0) {
    const notes = chord(c); const n = notes[(b / 2 + bar) % 3 + 1] + 12;
    music.beat(D.pluck(n, period * 0.9), b + 0.5, { gain: 0.16, pan: (b % 4 ? 0.35 : -0.35) });
  }
  if (flavor === 'minimal' && !intro && !end) music.beat(D.bell(deg(c + [0, 4, 2, 7][inBar]) + 24, 0.6), b + 0.25, { gain: 0.05, pan: inBar % 2 ? 0.4 : -0.4 });
  if (flavor === 'lofi' && inBar === 0) chord(c).forEach((m, i) => music.beat(D.keys(m + 12, period * 3.8), sw(b + i * 0.03), { gain: 0.12 }));
}
// Pads per bar (all flavours but minimal's intro).
for (let bar = 0; bar <= lastBar; bar++) {
  const b = bar * 4, intro = b < dropBeat, end = b >= endBeat, c = end ? 0 : chordAt(bar);
  if (flavor === 'minimal' && intro) continue;
  const notes = end ? [deg(0), deg(4), deg(7), deg(3) + 12] : chord(c);
  const len = Math.min(4 * period, duration - b * period) + (end ? 1.5 : 0);
  const cutoff = intro ? [500, 1800] : end ? [4500, 1200] : flavor === 'cinematic' ? [1200, 3000] : 2400;
  music.beat(D.pad(notes, len, { cutoff, attack: intro ? 0.4 : 0.03, release: end ? 1.2 : 0.25, rng }), b, { gain: flavor === 'lofi' ? 0.06 : flavor === 'cinematic' ? 0.16 : 0.11 });
}
// Transitions: reversed crash into the drop, impact on it; resolve on the end bar.
if (dropBeat > 0) {
  const rc = D.reverse(D.crash(rng, { len: 1.6 }));
  music.add(rc, Math.max(0, dropBeat * period - 1.6), { gain: 0.3 });
  drums.beat(D.crash(rng), dropBeat, { gain: 0.32 });
  drums.beat(D.subDrop(), dropBeat, { gain: 0.5 });
}
if (endBeat > dropBeat) { drums.beat(D.crash(rng, { len: 2.4 }), endBeat, { gain: 0.3 }); drums.beat(D.subDrop(1.6), endBeat, { gain: 0.45 }); }
if (flavor === 'cinematic') for (let bar = Math.max(1, drop); bar < lastBar; bar += 2) music.beat(D.riser(rng, 4 * period * 0.9, { to: 4000 }), bar * 4 + 4 - 3.6, { gain: 0.06 });

// Glue: reverb on music, sidechain duck on kicks, sum.
music.reverb(flavor === 'cinematic' ? 0.5 : 0.3);
const kickTimes = kicks;
if (flavor === 'pulse' || flavor === 'minimal') { music.duck(kickTimes, 0.55); bassB.duck(kickTimes, 0.7, 0.12); }
const master = new D.Bus(duration, { bpm });
drums.mixInto(master); bassB.mixInto(master); music.mixInto(master);
master.trim(duration);
D.fadeOut(master.L, 0.35); D.fadeOut(master.R, 0.35);
normalizePeak([master.L, master.R], -3);
const wav = path.join(P.audio, 'music.wav');
writeWav(wav, [master.L, master.R]);

const beats = [];
for (let b = 0; b * period < duration + 0.25; b++) beats.push(+(b * period).toFixed(6));
const sections = { intro: [0, dropBeat], main: [dropBeat, endBeat], end: [endBeat, nBeats] };
writeJSON(P.beats, {
  bpm, period, offset: 0, beats, downbeats: beats.filter((_, i) => i % 4 === 0),
  sections, duration, beatsInFilm: nBeats, source: `synth:${flavor}:${mode}:${key}:seed${seed}`,
});
log(`✓ ${rel(wav)}  ${flavor} · ${key} ${mode} · ${bpm} bpm · ${nBeats} beats (${bars} bars) · drop bar ${drop}`);
log(`✓ ${rel(P.beats)}  sections: intro 0-${dropBeat} · main ${dropBeat}-${endBeat} · end ${endBeat}-${nBeats}`);
