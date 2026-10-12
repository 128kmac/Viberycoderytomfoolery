#!/usr/bin/env node
// Gather REAL assets from a product URL: screenshots (desktop, mobile, sections),
// logo, the fonts the page actually uses, brand colours, CSS tokens and copy.
// usage: node <skill>/scripts/gather.mjs <url> <film> [--pages /pricing,/features] [--wait 1500]
// out:   <film>/assets/shots/*.png  logo/*  fonts/* + fonts.json  brand.json  copy.md
import fs from 'node:fs';
import path from 'node:path';
import { parseArgs, die, log, filmPaths, writeJSON, mkdirp, launch, rel } from './lib/common.mjs';

const a = parseArgs();
const [url, film] = a._;
if (!url || !film) die('usage: gather.mjs <url> <film> [--pages /a,/b]');
const P = filmPaths(film);
if (!fs.existsSync(P.dir)) die(`${rel(P.dir)} missing: scaffold it first`);
const shots = mkdirp(path.join(P.assets, 'shots')), logoDir = mkdirp(path.join(P.assets, 'logo')), fontDir = mkdirp(path.join(P.assets, 'fonts'));
const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36';
const slug = (s) => String(s).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 40) || 'x';
const wrote = [];
const note = (f, what) => wrote.push(`${rel(f).padEnd(56)} ${what}`);

async function settle(page) {
  // Scroll through once so lazy content and scroll reveals fire, then return to top.
  await page.evaluate(async () => {
    const step = innerHeight * 0.8;
    for (let y = 0; y < document.body.scrollHeight; y += step) { scrollTo(0, y); await new Promise((r) => setTimeout(r, 120)); }
    scrollTo(0, 0);
    await document.fonts.ready;
  });
  await page.waitForTimeout(Number(a.wait ?? 800));
}
const failedRes = new Map(); // resourceType -> count of failed stylesheet/font/image loads
async function open(ctx, u) {
  const page = await ctx.newPage();
  const fail = (type) => failedRes.set(type, (failedRes.get(type) ?? 0) + 1);
  page.on('requestfailed', (r) => { if (['stylesheet', 'font', 'image'].includes(r.resourceType())) fail(r.resourceType()); });
  page.on('response', (r) => { if (r.status() >= 400 && ['stylesheet', 'font'].includes(r.request().resourceType())) fail(r.request().resourceType()); });
  try { await page.goto(u, { waitUntil: 'networkidle', timeout: 30000 }); }
  catch { log(`  (networkidle timed out on ${u}; continuing with what loaded)`); }
  await settle(page);
  return page;
}
// Full-page screenshots longer than Chromium's 16k texture limit get clipped.
async function fullShot(page, file) {
  const h = await page.evaluate(() => document.documentElement.scrollHeight);
  const dpr = await page.evaluate(() => devicePixelRatio);
  const vw = page.viewportSize().width;
  if (h * dpr > 16000) await page.screenshot({ path: file, clip: { x: 0, y: 0, width: vw, height: Math.floor(16000 / dpr) } });
  else await page.screenshot({ path: file, fullPage: true });
}

const browser = await launch({ network: true });
try {
  // ---------------- desktop
  const dctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 2, userAgent: UA });
  const page = await open(dctx, url);
  const blocked = await page.evaluate(() => /captcha|verify you are human|access denied|log in to continue|sign in to continue/i.test(document.body.innerText.slice(0, 3000)));
  let f = path.join(shots, 'desktop_viewport.png'); await page.screenshot({ path: f }); note(f, 'desktop hero, 1440x900 @2x');
  f = path.join(shots, 'desktop_full.png'); await fullShot(page, f); note(f, 'desktop full page');

  // Sections: screenshot element handles directly (no index matching across queries).
  const handles = await page.$$('header, section, main > div, footer, [class*="hero" i]');
  const seen = new Set(); let k = 0;
  for (const hnd of handles) {
    if (k >= 18) break;
    const info = await hnd.evaluate((el) => {
      const r = el.getBoundingClientRect(), t = el.querySelector('h1,h2,h3');
      return { top: r.top + scrollY, w: r.width, h: r.height, label: (t?.innerText || el.tagName).trim().slice(0, 60) };
    }).catch(() => null);
    if (!info || info.h < 160 || info.w < 600 || info.h > 4000) continue;
    const key = Math.round(info.top / 40); if (seen.has(key)) continue; seen.add(key);
    const file = path.join(shots, `section_${String(k).padStart(2, '0')}_${slug(info.label)}.png`);
    try { await hnd.screenshot({ path: file }); note(file, `section "${info.label}"`); k++; } catch {}
  }

  // Brand extraction in-page.
  const brand = await page.evaluate(() => {
    const cv = document.createElement('canvas'); cv.width = cv.height = 1; const cx = cv.getContext('2d', { willReadFrequently: true });
    const hex = (c) => { if (!c || c === 'transparent') return null; cx.clearRect(0, 0, 1, 1); cx.fillStyle = '#000'; cx.fillStyle = c; cx.fillRect(0, 0, 1, 1); const d = cx.getImageData(0, 0, 1, 1).data; if (d[3] < 250) return null; return '#' + [d[0], d[1], d[2]].map((v) => v.toString(16).padStart(2, '0')).join(''); };
    const text = {}, bg = {}, fam = {}, wt = {};
    for (const el of document.querySelectorAll('body *')) {
      const cs = getComputedStyle(el);
      if (cs.display === 'none' || cs.visibility === 'hidden' || Number(cs.opacity) === 0) continue;
      const r = el.getBoundingClientRect(); if (!r.width || !r.height) continue;
      const own = [...el.childNodes].some((n) => n.nodeType === 3 && n.textContent.trim());
      if (own) {
        const c = hex(cs.color); if (c) text[c] = (text[c] || 0) + 1;
        const fm = cs.fontFamily.split(',')[0].replace(/["']/g, '').trim(); fam[fm] = (fam[fm] || 0) + 1;
        const w = `${fm} ${cs.fontWeight}`; wt[w] = (wt[w] || 0) + 1;
      }
      const b = hex(cs.backgroundColor); if (b) bg[b] = (bg[b] || 0) + Math.min(r.width * r.height, 2e5) / 1e4;
    }
    const bodyBg = hex(getComputedStyle(document.body).backgroundColor) || hex(getComputedStyle(document.documentElement).backgroundColor);
    if (bodyBg) bg[bodyBg] = (bg[bodyBg] || 0) + 1000;
    const top = (o, n) => Object.entries(o).sort((x, y) => y[1] - x[1]).slice(0, n).map(([k, v]) => [k, Math.round(v)]);
    const vars = {}, faces = [], xsheets = [];
    for (const sh of document.styleSheets) {
      let rules; try { rules = sh.cssRules; } catch { if (sh.href) xsheets.push(sh.href); continue; }
      for (const r of rules) {
        if (r.selectorText && /(^|,)\s*(:root|html)\b/.test(r.selectorText)) for (const p of r.style) if (p.startsWith('--')) vars[p] = r.style.getPropertyValue(p).trim();
        if (r.constructor.name === 'CSSFontFaceRule') {
          const src = r.style.getPropertyValue('src'), urls = [...src.matchAll(/url\(["']?([^"')]+)["']?\)/g)].map((m) => new URL(m[1], sh.href || location.href).href);
          faces.push({ family: r.style.getPropertyValue('font-family').replace(/["']/g, '').trim(), weight: r.style.getPropertyValue('font-weight') || '400', style: r.style.getPropertyValue('font-style') || 'normal', range: r.style.getPropertyValue('unicode-range'), urls });
        }
      }
    }
    // Computed values of tokens on :root (covers cross-origin & framework-injected sheets).
    const rs = getComputedStyle(document.documentElement);
    for (const p of rs) if (p.startsWith('--') && !(p in vars)) vars[p] = rs.getPropertyValue(p).trim();
    const q = (s, n) => [...document.querySelectorAll(s)].map((e) => e.innerText.trim().replace(/\s+/g, ' ')).filter((t) => t && t.length < 200).filter((t, i, arr) => arr.indexOf(t) === i).slice(0, n);
    const inTop = (el) => { const r = el.getBoundingClientRect(); return r.top < 160 && r.left < innerWidth / 2 && r.width > 30; };
    const svg = [...document.querySelectorAll('header svg, nav svg, a[href="/"] svg, [class*="logo" i] svg')].find(inTop);
    const img = [...document.querySelectorAll('header img, nav img, a[href="/"] img, img[class*="logo" i], img[alt*="logo" i]')].find(inTop);
    const home = document.querySelector('a[href="/"]'), hcs = home && getComputedStyle(home);
    return {
      title: document.title, description: document.querySelector('meta[name="description"]')?.content ?? '',
      themeColor: [...document.querySelectorAll('meta[name="theme-color"]')].map((m) => m.content),
      text_colors: top(text, 10), background_colors: top(bg, 10), font_families: top(fam, 6), font_weights: top(wt, 12), css_vars: vars,
      wordmark: home ? { text: home.innerText.trim().slice(0, 60), font: hcs.fontFamily, weight: hcs.fontWeight, tracking: hcs.letterSpacing } : null,
      faces, xsheets,
      logoSvg: svg ? svg.outerHTML : null, logoImg: img ? img.currentSrc || img.src : null,
      icons: [...document.querySelectorAll('link[rel*="icon"]')].map((l) => l.href),
      copy: { h1: q('h1', 10), h2: q('h2', 30), h3: q('h3', 30), buttons: q('button, a[class*="btn" i], a[class*="button" i], [role="button"]', 20), nav: q('nav a', 20) },
    };
  });

  // Fonts: fetch cross-origin CSS for @font-face, then download faces of families in use.
  for (const href of brand.xsheets) {
    try {
      const css = await (await fetch(href, { headers: { 'user-agent': UA, referer: url } })).text();
      for (const m of css.matchAll(/@font-face\s*{([^}]*)}/g)) {
        const b = m[1], get = (p) => (b.match(new RegExp(`${p}\\s*:\\s*([^;]+)`)) || [])[1]?.trim() ?? '';
        brand.faces.push({ family: get('font-family').replace(/["']/g, ''), weight: get('font-weight') || '400', style: get('font-style') || 'normal', range: get('unicode-range'), urls: [...get('src').matchAll(/url\(["']?([^"')]+)["']?\)/g)].map((x) => new URL(x[1], href).href) });
      }
    } catch {}
  }
  const used = new Set(brand.font_families.map(([f]) => f.toLowerCase()));
  const manifest = []; let idx = 0;
  for (const face of brand.faces) {
    if (!used.has(face.family.toLowerCase())) continue;
    const src = face.urls.find((u) => /\.woff2(\?|$)/.test(u)) ?? face.urls[0]; if (!src) continue;
    const subset = !face.range ? 'all' : /U\+0+-FF\b|U\+0000-00FF/i.test(face.range) ? 'latin' : /U\+0100/i.test(face.range) ? 'latin-ext' : 'other';
    if (subset === 'other') continue;
    const ext = (src.match(/\.(woff2|woff|ttf|otf)(\?|$)/) || [])[1] ?? 'woff2';
    const file = path.join(fontDir, `${slug(face.family)}-${slug(face.weight)}-${face.style}-${subset}-${idx++}.${ext}`);
    try {
      const r = await fetch(src, { headers: { 'user-agent': UA, referer: url } });
      if (!r.ok) continue;
      fs.writeFileSync(file, Buffer.from(await r.arrayBuffer()));
      manifest.push({ file: path.basename(file), family: face.family, weight: face.weight, style: face.style, subset });
    } catch {}
  }
  if (manifest.length) { writeJSON(path.join(fontDir, 'fonts.json'), manifest); note(path.join(fontDir, 'fonts.json'), `${manifest.length} font files for ${[...new Set(manifest.map((m) => m.family))].join(', ')}`); }

  // Logo + icons.
  if (brand.logoSvg) { f = path.join(logoDir, 'logo.svg'); fs.writeFileSync(f, brand.logoSvg.includes('xmlns') ? brand.logoSvg : brand.logoSvg.replace('<svg', '<svg xmlns="http://www.w3.org/2000/svg"')); note(f, 'inline SVG from header (check it is the logo, not an icon)'); }
  const EXT = { 'image/png': 'png', 'image/svg+xml': 'svg', 'image/jpeg': 'jpg', 'image/webp': 'webp', 'image/x-icon': 'ico', 'image/vnd.microsoft.icon': 'ico', 'image/gif': 'gif', 'image/avif': 'avif' };
  const grab = async (u, base) => {
    try {
      const r = await fetch(u, { headers: { 'user-agent': UA, referer: url } }); if (!r.ok) return;
      const ext = EXT[(r.headers.get('content-type') || '').split(';')[0]] ?? (u.match(/\.(png|svg|jpe?g|webp|ico|gif)(\?|$)/i)?.[1] ?? 'bin');
      const file = path.join(logoDir, `${base}.${ext}`); fs.writeFileSync(file, Buffer.from(await r.arrayBuffer())); note(file, base);
    } catch {}
  };
  if (brand.logoImg) await grab(brand.logoImg, 'logo_img');
  for (const [i, ic] of brand.icons.slice(0, 4).entries()) await grab(ic, `icon_${i}`);

  // brand.json + copy.md
  const { faces, xsheets, logoSvg, logoImg, icons, copy, ...rest } = brand;
  f = path.join(P.assets, 'brand.json'); writeJSON(f, { url, ...rest }); note(f, 'colours (text, bg by area), fonts, weights, CSS tokens, wordmark');
  const md = [`# Copy from ${url}`, '', `**Title:** ${brand.title}`, `**Description:** ${brand.description}`, '',
    '## Headlines (h1)', ...copy.h1.map((t) => `- ${t}`), '', '## Section heads (h2)', ...copy.h2.map((t) => `- ${t}`), '',
    '## Subheads (h3)', ...copy.h3.map((t) => `- ${t}`), '', '## Buttons / CTAs', ...copy.buttons.map((t) => `- ${t}`), '', '## Nav', ...copy.nav.map((t) => `- ${t}`), ''].join('\n');
  f = path.join(P.assets, 'copy.md'); fs.writeFileSync(f, md); note(f, "the brand's own words: use these, don't invent copy");

  // Extra pages.
  for (const pth of String(a.pages ?? '').split(',').filter(Boolean)) {
    const pg = await open(dctx, new URL(pth, url).href);
    f = path.join(shots, `page_${slug(pth)}_viewport.png`); await pg.screenshot({ path: f }); note(f, `${pth} viewport`);
    f = path.join(shots, `page_${slug(pth)}_full.png`); await fullShot(pg, f); note(f, `${pth} full`);
    await pg.close();
  }
  await dctx.close();

  // ---------------- mobile (the most useful real screen for 9x16)
  const mctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true, userAgent: UA.replace('Macintosh; Intel Mac OS X 14_0', 'iPhone; CPU iPhone OS 17_0 like Mac OS X') + ' Mobile' });
  const mp = await open(mctx, url);
  f = path.join(shots, 'mobile_viewport.png'); await mp.screenshot({ path: f }); note(f, 'mobile hero 390x844 @3x: best real screen for 9x16');
  f = path.join(shots, 'mobile_full.png'); await fullShot(mp, f); note(f, 'mobile full page');
  await mctx.close();

  log(`✓ gathered ${wrote.length} assets from ${url}\n  ${wrote.join('\n  ')}`);
  log(`\nPalette (text): ${brand.text_colors.map(([c]) => c).join(' ')}\nPalette (bg):   ${brand.background_colors.map(([c]) => c).join(' ')}\nFonts:          ${brand.font_families.map(([f]) => f).join(', ')}`);
  if (failedRes.size) {
    log(`\n! Failed loads: ${[...failedRes].map(([t, n]) => `${n} ${t}`).join(', ')}.`);
    if (failedRes.get('stylesheet')) log('! Stylesheets failed (network policy, CDN or bot block), so screenshots are UNSTYLED and the palette/fonts above are browser defaults. Do not build on them: fix network access or ask the user for screenshots + brand colours/fonts.');
  }
  if (blocked) log('\n! The page looks blocked (captcha / login wall). Do NOT invent UI: ask the user for screenshots.');
} finally {
  await browser.close();
}
