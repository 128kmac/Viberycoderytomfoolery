#!/usr/bin/env node
// Mix stems, master to −14 LUFS integrated / ≤ −1 dBTP, mux into every rendered video.
// usage: node <skill>/scripts/mix.mjs <film> [--music-db 0] [--sfx-db 0] [--vo-db 2] [--lufs -14] [--tp -1] [--no-mux]
// in:  <film>/audio/{music,sfx,vo}.wav (whichever exist), out/<film>/video_<fmt>.mp4
// out: <film>/audio/mix.wav (24-bit 48 kHz), out/<film>/final_<fmt>.mp4, out/<film>/final.mp4 (primary format)
import fs from 'node:fs';
import path from 'node:path';
import { parseArgs, die, log, loadFilm, ffmpeg, loudness, rel } from './lib/common.mjs';

const a = parseArgs();
const { P, cfg } = loadFilm(a._[0]);
const DUR = cfg.duration;
const target = Number(a.lufs ?? -14), tp = Number(a.tp ?? -1);
const ceiling = tp - 0.5; // sample-peak ceiling at 4x oversampling leaves margin for true peak
const stems = ['music', 'sfx', 'vo'].map((s) => ({ s, f: path.join(P.audio, `${s}.wav`) })).filter((x) => fs.existsSync(x.f));
if (!stems.length) die(`no stems in ${rel(P.audio)} (expected music.wav, sfx.wav, vo.wav)`);
const db = { music: Number(a['music-db'] ?? 0), sfx: Number(a['sfx-db'] ?? 0), vo: Number(a['vo-db'] ?? 2) };

// 1. Premaster: align stems, apply levels, duck music under VO, sum, tail fade.
const inputs = stems.flatMap((x) => ['-i', x.f]);
const chains = stems.map((x, i) => `[${i}:a]aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo,apad=whole_dur=${DUR},atrim=0:${DUR},volume=${db[x.s]}dB[${x.s}]`);
let labels = stems.map((x) => `[${x.s}]`);
const hasVo = stems.some((x) => x.s === 'vo'), hasMusic = stems.some((x) => x.s === 'music');
if (hasVo && hasMusic) {
  chains.push('[vo]asplit=2[vo][vokey]', '[music][vokey]sidechaincompress=threshold=0.03:ratio=6:attack=15:release=300:makeup=1[music]');
}
labels = stems.map((x) => `[${x.s}]`);
const fc = [...chains, `${labels.join('')}amix=inputs=${stems.length}:normalize=0:duration=longest,afade=t=out:st=${Math.max(0, DUR - 0.3)}:d=0.3[out]`].join(';');
const pre = path.join(P.audio, '_premaster.wav');
ffmpeg([...inputs, '-filter_complex', fc, '-map', '[out]', '-c:a', 'pcm_f32le', '-t', String(DUR), pre]);

// 2. Master: gain -> 4x oversampled look-ahead limiter, iterate gain until within 0.1 LU.
const m0 = loudness(pre);
if (!Number.isFinite(m0.I)) die('premaster is silent');
const mixWav = path.join(P.audio, 'mix.wav');
let g = target - m0.I, m;
for (let pass = 1; pass <= 6; pass++) {
  ffmpeg(['-i', pre, '-af', `volume=${g.toFixed(3)}dB,aresample=192000,alimiter=limit=${10 ** (ceiling / 20)}:attack=1:release=60:level=0:asc=1:latency=1,aresample=48000`, '-c:a', 'pcm_s24le', mixWav]);
  m = loudness(mixWav);
  if (Math.abs(m.I - target) <= 0.1) break;
  g += target - m.I;
}
fs.rmSync(pre, { force: true });
const ok = Math.abs(m.I - target) <= 0.3 && m.TP <= tp;
log(`${ok ? '✓' : '!'} ${rel(mixWav)}  ${m.I.toFixed(1)} LUFS · ${m.TP.toFixed(1)} dBTP · LRA ${m.LRA.toFixed(1)} · stems: ${stems.map((x) => x.s).join('+')} (premaster ${m0.I.toFixed(1)} LUFS, gain ${g >= 0 ? '+' : ''}${g.toFixed(1)} dB)`);
if (!ok) log(`  WARNING: off target (want ${target} LUFS, ≤ ${tp} dBTP). Lower the loudest stem or raise --tp margin.`);
if (g > 12) log('  NOTE: needed >12 dB of gain; the limiter is working hard. Consider a denser score or louder stems.');

// 3. Mux into each rendered video (video stream copied, AAC 320k, faststart).
if (a['no-mux']) process.exit(0);
let muxed = 0;
for (const fmt of cfg.formats) {
  const v = path.join(P.out, `video_${fmt}.mp4`);
  if (!fs.existsSync(v)) { log(`  (no ${rel(v)} yet; render it, then re-run mix)`); continue; }
  const out = path.join(P.out, `final_${fmt}.mp4`);
  ffmpeg(['-i', v, '-i', mixWav, '-map', '0:v', '-map', '1:a', '-c:v', 'copy', '-c:a', 'aac', '-b:a', '320k', '-ar', '48000', '-t', String(DUR), '-movflags', '+faststart', out]);
  if (fmt === cfg.formats[0]) fs.copyFileSync(out, path.join(P.out, 'final.mp4'));
  log(`✓ ${rel(out)}${fmt === cfg.formats[0] ? '  (= final.mp4, primary)' : ''}`);
  muxed++;
}
if (muxed) log(`Next: node <skill>/scripts/check.mjs ${a._[0]}`);
