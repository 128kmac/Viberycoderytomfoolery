#!/usr/bin/env node
// Delivery gate: verify every final_<fmt>.mp4 before handing it over.
// Checks container/stream specs, duration, loudness of the ENCODED audio,
// faststart, and pulls a frame from the encoded file to look at.
// usage: node <skill>/scripts/check.mjs <film>
import fs from 'node:fs';
import path from 'node:path';
import { FORMATS, parseArgs, die, log, loadFilm, probe, loudness, ffmpeg, rel } from './lib/common.mjs';

const a = parseArgs();
const { P, cfg } = loadFilm(a._[0]);
let failed = 0;
for (const fmt of cfg.formats) {
  const f = path.join(P.out, `final_${fmt}.mp4`);
  if (!fs.existsSync(f)) { log(`✗ ${rel(f)} missing`); failed++; continue; }
  const j = probe(f), v = j.streams.find((s) => s.codec_type === 'video'), au = j.streams.find((s) => s.codec_type === 'audio');
  const [num, den] = (v?.r_frame_rate ?? '0/1').split('/').map(Number);
  const dur = Number(j.format.duration), want = FORMATS[fmt];
  const head = fs.readFileSync(f).subarray(0, 64 * 1024).toString('latin1');
  const L = au ? loudness(f) : { I: NaN, TP: NaN };
  const checks = [
    ['h264 high', v?.codec_name === 'h264' && /High/.test(v?.profile ?? ''), `${v?.codec_name} ${v?.profile}`],
    ['size', v?.width === want.w && v?.height === want.h, `${v?.width}x${v?.height}`],
    ['fps', Math.abs(num / den - cfg.fps) < 0.01, `${(num / den).toFixed(2)}`],
    ['yuv420p', v?.pix_fmt === 'yuv420p', v?.pix_fmt],
    ['bt709', v?.color_space === 'bt709' && v?.color_primaries === 'bt709' && v?.color_transfer === 'bt709', `${v?.color_space}/${v?.color_primaries}/${v?.color_transfer}`],
    ['duration', Math.abs(dur - cfg.duration) <= 1.5 / cfg.fps + 0.03, `${dur.toFixed(3)}s`],
    ['audio aac 48k stereo', au?.codec_name === 'aac' && au?.sample_rate === '48000' && au?.channels === 2, au ? `${au.codec_name} ${au.sample_rate} ${au.channels}ch` : 'none'],
    ['loudness −14±1', Math.abs(L.I + 14) <= 1, `${L.I?.toFixed?.(1)} LUFS`],
    ['true peak ≤ −1 (aac)', L.TP <= -0.5, `${L.TP?.toFixed?.(1)} dBTP`],
    ['faststart', head.indexOf('moov') !== -1 && (head.indexOf('mdat') === -1 || head.indexOf('moov') < head.indexOf('mdat')), 'moov first'],
  ];
  const bad = checks.filter((c) => !c[1]);
  failed += bad.length;
  log(`${bad.length ? '✗' : '✓'} ${rel(f)}  ${(fs.statSync(f).size / 1e6).toFixed(1)} MB`);
  for (const [name, ok, val] of checks) log(`   ${ok ? '✓' : '✗'} ${name.padEnd(22)} ${val}`);
  // A frame from the ENCODED file (catches colour-matrix and encode problems the canvas can't show).
  const t = cfg.poster ?? cfg.duration * 0.87, still = path.join(P.out, `check_${fmt}.png`);
  ffmpeg(['-ss', String(t), '-i', f, '-frames:v', '1', '-update', '1', still]);
  log(`   → look at ${rel(still)} (decoded from the mp4 @ ${t}s)`);
}
if (failed) { log(`\n✗ ${failed} check(s) failed`); process.exitCode = 1; }
else log('\n✓ all deliverables pass');
