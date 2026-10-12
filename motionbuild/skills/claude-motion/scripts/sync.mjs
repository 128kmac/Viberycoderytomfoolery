#!/usr/bin/env node
// Check that every sounding hit is audible where the picture says it is.
// Detects onsets in the SFX stem (and the full mix for audibility) and reports
// the offset of each start-anchored hit. Peak/end-anchored sounds (whoosh,
// riser, swell) are checked by envelope peak / end instead of onset.
// usage: node <skill>/scripts/sync.mjs <film> [--tol 20]
// needs: out/<film>/hits.json (from sfx.mjs), <film>/audio/sfx.wav, optionally mix.wav
import fs from 'node:fs';
import path from 'node:path';
import { parseArgs, die, log, loadFilm, readJSON, decodeAudio, rel } from './lib/common.mjs';
import * as D from './lib/dsp.mjs';

const a = parseArgs();
const { P, cfg } = loadFilm(a._[0]);
const tol = Number(a.tol ?? 20) / 1000;
const hitsFile = path.join(P.out, 'hits.json');
if (!fs.existsSync(hitsFile)) die(`${rel(hitsFile)} missing: run sfx.mjs first`);
const sfxWav = path.join(P.audio, 'sfx.wav');
if (!fs.existsSync(sfxWav)) die(`${rel(sfxWav)} missing: run sfx.mjs first`);
const hits = readJSON(hitsFile).filter((h) => h.sfx);
const fps = cfg.fps;

const mono = (ch) => { const m = new Float32Array(ch[0].length); for (let i = 0; i < m.length; i++) m[i] = (ch[0][i] + ch[1][i]) / 2; return m; };
const sfx = mono(decodeAudio(sfxWav));
// 100 ms of silent pre-roll so a hit at t = 0 is detectable.
const PRE = 0.1, padded = new Float32Array(D.sec(PRE) + sfx.length); padded.set(sfx, D.sec(PRE));
const env = D.onsetEnvelope(padded, { hop: 128, size: 512 });
const onsets = D.pickOnsets(env, { delta: 0.03, wait: 0.03 }).map((t) => t - PRE);
// RMS envelope (5 ms) for peak/end checks.
const win = D.sec(0.005), rms = new Float32Array(Math.floor(sfx.length / win));
for (let i = 0; i < rms.length; i++) { let s = 0; for (let j = 0; j < win; j++) s += sfx[i * win + j] ** 2; rms[i] = Math.sqrt(s / win); }

const ANCHOR = { whoosh: 'peak', riser: 'end', swell: 'end' };
const nearest = (t) => onsets.reduce((b, o) => (Math.abs(o - t) < Math.abs(b - t) ? o : b), Infinity);
let pass = 0, checked = 0;
const rows = [];
for (const h of hits) {
  const names = h.sfx.split('+');
  const anchor = h.opts?.anchor ?? ANCHOR[names[0]] ?? 'start';
  let found, how;
  if (anchor === 'start') { found = nearest(h.t); how = 'onset'; }
  else if (anchor === 'peak') {
    // loudest 5 ms window within ±150 ms
    const i0 = Math.max(0, Math.floor((h.t - 0.15) / 0.005)), i1 = Math.min(rms.length - 1, Math.ceil((h.t + 0.15) / 0.005));
    let pi = i0; for (let i = i0; i <= i1; i++) if (rms[i] > rms[pi]) pi = i;
    found = pi * 0.005; how = 'peak';
  } else {
    // End-anchored sounds are placed by construction (sfx.mjs offsets them by
    // their length); another hit usually starts on the same beat and masks the
    // cut-off, so only confirm the sound is building in the 250 ms before.
    const i1 = Math.floor(h.t / 0.005), i0 = Math.max(0, i1 - 50);
    found = rms[Math.max(0, i1 - 4)] > rms[i0] ? h.t : NaN; how = 'end, rising';
  }
  const off = Number.isNaN(found) ? Infinity : found - h.t, ok = Math.abs(off) <= (anchor === 'start' ? tol : 0.04);
  const frame = Math.round(h.t * fps), frameErr = (h.t - frame / fps) * 1000;
  checked++; if (ok) pass++;
  rows.push(`${ok ? '✓' : '✗'} beat ${String(h.beat).padStart(5)}  ${h.t.toFixed(3)}s  ${Number.isFinite(off) ? (off * 1000 >= 0 ? '+' : '') + (off * 1000).toFixed(0).padStart(4) + ' ms' : 'not found'} (${how})  frame ${frame}${Math.abs(frameErr) > 1 ? ` (${frameErr.toFixed(1)} ms off grid)` : ''}  ${h.sfx}  — ${h.label}`);
}
log(rows.join('\n'));
log(`\n${pass}/${checked} hits within ${tol * 1000} ms (onset) / 40 ms (peak, end). + = sound after picture.`);

// Audibility in the full mix: sfx stem level vs mix around each hit.
const mixWav = path.join(P.audio, 'mix.wav');
if (fs.existsSync(mixWav)) {
  const mix = mono(decodeAudio(mixWav));
  const quiet = [];
  for (const h of hits) {
    const anchor = h.opts?.anchor ?? ANCHOR[h.sfx.split('+')[0]] ?? 'start';
    // measure where the sound actually is: after a start, around a peak, before an end
    const [w0, w1] = anchor === 'start' ? [0, 0.08] : anchor === 'peak' ? [-0.06, 0.06] : [-0.3, -0.02];
    const i = Math.max(0, D.sec(h.t + w0)), n = D.sec(w1 - w0); let s = 0, m = 0;
    for (let j = 0; j < n && i + j < sfx.length; j++) { s += sfx[i + j] ** 2; m += mix[i + j] ** 2; }
    const ratio = 10 * Math.log10((s + 1e-12) / (m + 1e-12));
    if (ratio < -18) quiet.push(`beat ${h.beat} (${h.sfx}, ${ratio.toFixed(0)} dB under the mix)`);
  }
  if (quiet.length) log(`! possibly buried: ${quiet.join(' · ')}  → raise opts.gain or --sfx-db`);
  else log('✓ every hit sits within 18 dB of the mix around it');
}
if (pass < checked) process.exitCode = 2;
