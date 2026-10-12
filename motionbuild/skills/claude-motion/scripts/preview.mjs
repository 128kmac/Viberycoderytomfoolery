#!/usr/bin/env node
// Serve the project for live preview in a browser (space play · ←/→ step · click scrub · M mute).
// usage: node <skill>/scripts/preview.mjs <film> [--format 9x16]
import path from 'node:path';
import { parseArgs, loadFilm, serve, ROOT, log } from './lib/common.mjs';

const a = parseArgs();
const { P, cfg } = loadFilm(a._[0]);
const s = await serve(ROOT);
const rel = path.relative(ROOT, P.dir).split(path.sep).map(encodeURIComponent).join('/');
for (const f of a.format ? [a.format] : cfg.formats) log(`${s.url}/${rel}/index.html?format=${f}`);
log('Ctrl-C to stop.');
