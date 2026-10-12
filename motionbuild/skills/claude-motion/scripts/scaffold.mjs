#!/usr/bin/env node
// Create a new film directory from the template and check the toolchain.
// usage: node <skill>/scripts/scaffold.mjs <slug> [--title "Name"] [--duration 15] [--formats 16x9,9x16,1x1] [--fps 60]
import fs from 'node:fs';
import path from 'node:path';
import { SKILL, ROOT, FORMATS, parseArgs, die, log, has, writeJSON, mkdirp, loadChromium } from './lib/common.mjs';

const a = parseArgs();
const slug = a._[0];
if (!slug || !/^[a-z0-9][a-z0-9-]*$/.test(slug)) die('usage: scaffold.mjs <slug> (lowercase, digits, dashes)');
const dir = path.resolve(ROOT, slug);
if (fs.existsSync(dir)) die(`${slug}/ already exists. Never overwrite another film's directory; pick a new slug.`);

const title = typeof a.title === 'string' ? a.title : slug;
const duration = Number(a.duration ?? 15);
const fps = Number(a.fps ?? 60);
const formats = String(a.formats ?? '16x9').split(',').map((s) => s.trim());
for (const f of formats) if (!FORMATS[f]) die(`unknown format ${f} (use ${Object.keys(FORMATS).join(', ')})`);
if (!(duration > 0)) die('--duration must be > 0');

const T = path.join(SKILL, 'assets');
for (const d of ['lib', 'assets/shots', 'assets/logo', 'assets/fonts', 'docs', 'audio', 'fonts']) mkdirp(path.join(dir, d));
for (const f of ['index.html', 'film.js', 'hits.js']) {
  fs.writeFileSync(path.join(dir, f), fs.readFileSync(path.join(T, 'template', f), 'utf8').replaceAll('__TITLE__', title));
}
fs.copyFileSync(path.join(T, 'lib', 'motion.js'), path.join(dir, 'lib', 'motion.js'));
writeJSON(path.join(dir, 'film.json'), { title, duration, fps, formats, poster: Math.round(duration * 0.87 * 100) / 100 });

log(`✓ ${slug}/ created (${duration}s, ${fps} fps, ${formats.join(', ')})`);
log('  film.json  index.html  film.js  hits.js  lib/motion.js  assets/  docs/  audio/  fonts/');

// Toolchain check: warn, don't fail.
const warn = [];
if (!has('ffmpeg')) warn.push('ffmpeg not on PATH (needed for render, audio, reference)');
if (!has('ffprobe')) warn.push('ffprobe not on PATH');
const v = Number(process.versions.node.split('.')[0]);
if (v < 18) warn.push(`Node ${process.versions.node} is too old; need 18+`);
const origExit = process.exit;
process.exit = () => { throw new Error('noplaywright'); };
try { await loadChromium(); } catch { warn.push('Playwright not found: npm init -y && npm i -D playwright && npx playwright install chromium'); }
process.exit = origExit;
if (warn.length) { log('\nToolchain warnings:'); for (const w of warn) log('  ! ' + w); }
else log('✓ toolchain: node, ffmpeg, ffprobe, playwright');
log(`\nNext: node ${path.relative(ROOT, SKILL)}/scripts/gather.mjs <url> ${slug}`);
