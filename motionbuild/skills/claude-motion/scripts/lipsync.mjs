#!/usr/bin/env node
// Mouth data for a talking character from <film>/audio/vo.wav.
// Always writes an amplitude track; adds Rhubarb visemes when `rhubarb` is on PATH.
// usage: node <skill>/scripts/lipsync.mjs <film> [--script audio/script.txt] [--phonetic]
// out:   <film>/lipsync.json  { rate, open[0..1 per 10 ms], shapes[[t0,t1,'A'..'H'|'X']], phrases[[t0,t1]] }
// In film.js: fetch('lipsync.json') in init, then mouthAt(t) is a pure lookup.
import fs from 'node:fs';
import path from 'node:path';
import { parseArgs, die, log, loadFilm, writeJSON, decodeAudio, has, run, rel, readJSON } from './lib/common.mjs';
import * as D from './lib/dsp.mjs';

const a = parseArgs();
const { P } = loadFilm(a._[0]);
const vo = path.join(P.audio, 'vo.wav');
if (!fs.existsSync(vo)) die(`${rel(vo)} missing`);
const [L, R] = decodeAudio(vo);
const x = new Float32Array(L.length); for (let i = 0; i < x.length; i++) x[i] = (L[i] + R[i]) / 2;

// Amplitude: 30 ms RMS every 10 ms -> dB -> 0..1 against the take's max,
// fast attack / slower release, gate at -45 dBFS, hold shapes >= 2 frames downstream.
const hop = D.sec(0.01), win = D.sec(0.03), frames = Math.floor(x.length / hop);
const db = new Float32Array(frames);
for (let f = 0; f < frames; f++) { let s = 0; const i0 = f * hop; for (let j = 0; j < win && i0 + j < x.length; j++) s += x[i0 + j] ** 2; db[f] = 10 * Math.log10(s / win + 1e-12); }
const max = Math.max(...db);
const open = new Array(frames); let y = 0;
for (let f = 0; f < frames; f++) {
  const v = db[f] < -45 ? 0 : Math.min(1, Math.max(0, (db[f] - max + 40) / 34));
  y += (v - y) * (v > y ? 0.75 : 0.4);
  open[f] = +y.toFixed(3);
}
// Phrases: runs of sound separated by >= 150 ms below -35 dB relative.
const phrases = []; let st = -1, quiet = 0;
for (let f = 0; f < frames; f++) {
  const on = db[f] > max - 35;
  if (on) { if (st < 0) st = f; quiet = 0; } else if (st >= 0 && ++quiet >= 15) { phrases.push([st / 100, (f - quiet + 1) / 100]); st = -1; quiet = 0; }
}
if (st >= 0) phrases.push([st / 100, frames / 100]);

let shapes = [];
if (has('rhubarb', ['--version'])) {
  const tmp = path.join(P.audio, '_rhubarb.json');
  const args = ['-f', 'json', '--extendedShapes', 'GHX', vo, '-o', tmp];
  const script = a.script ? path.resolve(P.dir, a.script) : path.join(P.audio, 'script.txt');
  if (fs.existsSync(script)) args.unshift('-d', script);
  if (a.phonetic) args.unshift('-r', 'phonetic');
  try { run('rhubarb', args); shapes = readJSON(tmp).mouthCues.map((c) => [c.start, c.end, c.value]); fs.rmSync(tmp, { force: true }); }
  catch (e) { log(`! rhubarb failed, amplitude only: ${e.message.split('\n')[0]}`); }
}
writeJSON(path.join(P.dir, 'lipsync.json'), { rate: 100, open, shapes, phrases });
log(`✓ ${rel(path.join(P.dir, 'lipsync.json'))}  ${(frames / 100).toFixed(2)} s · ${phrases.length} phrases · ${shapes.length ? `${shapes.length} Rhubarb mouth cues` : 'amplitude only (install rhubarb for visemes)'}`);
log(`  phrases: ${phrases.map(([s, e]) => `${s.toFixed(2)}–${e.toFixed(2)}`).join('  ')}`);
