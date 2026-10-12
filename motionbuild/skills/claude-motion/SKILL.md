---
name: claude-motion
description: Make motion-graphics videos from code — product launch films, showreels, promos, animated explainers, motion ads, kinetic type and social cuts (16:9, 9:16, 1:1) — as a canvas film that is a pure function of time, rendered frame-exact to H.264 with a synthesized score, beat-locked SFX and a −14 LUFS master. Use whenever the user asks for a video, reel, promo, launch video, explainer, animated ad, "a video about <product/URL>", or social clip, even if they never say "motion graphics". Covers real-asset gathering from a URL, style guide from a reference, beat grid, a shot list the user signs off, the build, a contact-sheet critique loop, render, SFX, optional voice-over with lip-sync, mix and multi-format delivery.
---

# Claude Motion

A film here is **code**: `film.js` draws frame *t* onto a canvas, `hits.js` lists every accent, `beats.json` is the grid both picture and sound are locked to. Scripts render it frame-exact, synthesize its sound, and prove sync and loudness before delivery.

`<skill>` below means this skill's directory. Run every command **from the project folder** (the folder that will hold `<film>/` and `out/`). If the project's CLAUDE.md sets other rules, the project wins.

## The contract (never break these)

1. **Pure function of time.** `window.seek(t)` paints frame t and nothing else. No CSS animation, `setTimeout`, `requestAnimationFrame` (in render mode), `Date`, `Math.random`, or state carried between frames. Seeded noise only (`M.hash01`, `M.noise1`, `M.mulberry32`). The renderer seeks frames out of order across parallel pages; hidden state = frames that disagree.
2. **Time in beats.** Write motion in beats `u` (`t = offset + u·period`). Big changes land on downbeats; accents on beats. `hits.js` is the single source of truth: if it moves on screen with emphasis, it has a row there, and the sound comes from the same row.
3. **Real product only.** Every screen is a gathered screenshot or pure type/shape. Never invent UI, logos, metrics or testimonials. If a shot needs a screen that doesn't exist, change the shot.
4. **Each format is designed, not cropped.** 9:16 and 1:1 get their own layout via `FORMAT.pick`. Never letterbox. Keep type inside `FORMAT.safe` (9:16 clears the social UI: 250 px top, 430 px bottom, 150 px right).
5. **Look before you show.** Never hand over anything you haven't looked at as an image: contact sheets, strips, the decoded check frame.

## Intake

Collect in **one** AskUserQuestion round, only what's missing:
product + URL · duration · formats · reference (video/images, optional) · music (synthesize / supplied track) · voice-over (default none) · must-say copy.
Defaults: **15 s · 16:9 · 60 fps · synthesized score · no VO**. Colours and fonts come from the site; ask only whether to override.

## Pipeline

| # | Stage | Command | Output | Gate |
|---|---|---|---|---|
| 0 | Setup | `npm init -y && npm i -D playwright && npx playwright install chromium` (if `scaffold` warns) | node_modules | ffmpeg, ffprobe, Node 18+ |
| 1 | Scaffold | `node <skill>/scripts/scaffold.mjs <slug> --title "…" --duration 15 --formats 16x9,9x16` | `<slug>/` | refuses to overwrite |
| 2 | Gather | `node <skill>/scripts/gather.mjs <url> <film> [--pages /pricing]` | `assets/shots, logo, fonts, brand.json, copy.md` | **look at the shots**; warnings about blocked/unstyled pages are fatal |
| 3 | Reference | `node <skill>/scripts/reference.mjs <video\|img\|dir> <film>` | `docs/reference/*` → you write `docs/style_guide.md` | skip if no reference |
| 4 | Music + grid | `node <skill>/scripts/score.mjs <film> --flavor pulse` or `node <skill>/scripts/beats.mjs <film> --track song.mp3` | `audio/music.wav`, `beats.json` | track: fit warning = stop |
| 5 | Shot list | write `docs/shotlist.md` | — | **STOP: user signs off** |
| 6 | Build | edit `film.js`, `hits.js`, fonts, images | — | page has no console errors |
| 7 | Critique loop | contact → strips → sfx → mix → sync → critique | `docs/critique.md` | ≥ 3 rounds, all scores ≥ 8 |
| 8 | Render + mix | `render.mjs <film> --all-formats` → `sfx.mjs` → `mix.mjs` | `out/<film>/final*.mp4` | — |
| 9 | Check + deliver | `check.mjs <film>`, `render.mjs <film> --poster --all-formats` | posters, check frames | all checks ✓, look at check frames |

### 1–2. Scaffold and gather real assets

After `gather`, open `desktop_viewport.png`, `mobile_viewport.png` and a few `section_*.png`. Read `brand.json` (text colours, backgrounds weighted by area, font families in use, CSS tokens) and `copy.md` (the brand's own words — use them).
- Pick **one display face + one UI face** from `assets/fonts/fonts.json`; copy them to `<film>/fonts/display.woff2` and `ui.woff2` (`.ttf`/`.otf` also load). Confirm the palette and the two faces with the user in one line.
- `logo.svg` may be an icon — check it.
- If gather warns the page is blocked or **unstyled** (stylesheets failed), don't build on it: ask for screenshots and brand colours/fonts.
- `mobile_viewport.png` is usually the best real screen for 9:16.

### 3. Style guide from a reference

Read `shots.png`, `seconds.png`, `cuts.json` and write `docs/style_guide.md` per `references/style-guide.md`. Measurements, not adjectives: "moves resolve in 6–8 frames with ~10 % overshoot" is buildable; "snappy" is not. **Take the reference's motion and composition; the brand keeps its colours and type.**

### 4. Music and the beat grid

- **Synthesized (default):** `score.mjs` picks a tempo where the duration is whole bars, writes `music.wav` and an **exact** grid (it built the music, so nothing is estimated). Flavours: `pulse` (four-on-the-floor, 112–136 bpm), `minimal` (rim/shaker/bells, techy), `lofi` (swung, keys, 72–96), `cinematic` (pads, low hits, risers, 84–120). Options `--key A --mode major|minor|dorian|mixolydian --drop BAR --seed N --bpm 120`. Sections land in `beats.json.sections` (`intro`, `main`, `end` — end is the last bar, the resolve under the end card).
- **Supplied track:** `beats.mjs --track` measures tempo, phase (kick-weighted) and downbeat, cuts the loudest (or `--start`) window starting on a downbeat. A weak-fit warning means check `--bpm-hint` (half/double tempo) before building.
- More in `references/audio.md`. If there's a VO, read `references/voiceover.md` now — the VO edit is placed on this grid.

### 5. Shot list → STOP

Write `docs/shotlist.md` per `references/shotlist.md`: units are beats, frame 0 is a shot, something new every 2–4 s, every shot names its asset file, each format planned. **Show it and wait for the user's OK.** Changing a table is cheap; re-animating a scene is not.

### 6. Build

Start from the template `film.js` (scene table → per-scene functions → `M.film({...})`). API, timing numbers and idioms: `references/motion-api.md`. Rules of thumb:
- Entrances ease-out or spring (`M.springU` with `SPRING.snappy|bouncy|gentle|wobbly`), exits ease-in and faster than entrances, on-screen moves ease-in-out. Linear only for constant drifts.
- Overlap: stagger glyphs/items by 0.03–0.08 beat; start the first move ~0.25 beat before frame 0 so frame 0 is already alive.
- Hierarchy: one focal point per beat. Scale contrast ≥ 3:1 between headline and support.
- **Alpha from springs must be clamped** — `M.alpha(ctx, a)` or `M.clamp`. Canvas silently ignores negative `globalAlpha` and keeps the old value, so `1 - spring` overshooting to −0.02 makes an exiting element snap back to fully opaque.
- Preview: `node <skill>/scripts/preview.mjs <film>` prints a local URL per format (space play, ←/→ frame step, click scrub, M mute). It plays `audio/mix.wav`, falling back to `music.wav`.

### 7. Critique loop (minimum 3 rounds)

Each round, for **every** format:
```bash
node <skill>/scripts/render.mjs <film> --contact --all-formats     # one frame per beat + phone-size sheet
node <skill>/scripts/render.mjs <film> --strip 7.5:8.5:8           # every transition (seconds a:b:n)
node <skill>/scripts/render.mjs <film> --at 0,3.75                 # detail stills
node <skill>/scripts/sfx.mjs <film> && node <skill>/scripts/mix.mjs <film> --no-mux
node <skill>/scripts/sync.mjs <film>                               # every hit within 20 ms, nothing buried
```
Then run the critique in `references/critique.md` against the images (open them; don't score from memory of the code), append the round to `docs/critique.md`, fix the worst three. **Stop only when every score ≥ 8, no check fails, and ≥ 3 rounds are done.** `contact_<fmt>/bNNN.png` is beat NNN at full size.

### 8. Render and mix

```bash
node <skill>/scripts/render.mjs <film> --all-formats    # out/<film>/video_<fmt>.mp4 (≈ 8–30 fps; blur costs most)
node <skill>/scripts/sfx.mjs <film>
node <skill>/scripts/mix.mjs <film>                     # mix.wav at −14 LUFS / ≤ −1 dBTP, muxed → final_<fmt>.mp4, final.mp4
```
`--draft` renders without blur at CRF 22 for quick watch-throughs; never deliver a draft. Mix levels: `--music-db`, `--sfx-db`, `--vo-db` (default +2); music ducks under VO automatically.

### 9. Check and deliver

```bash
node <skill>/scripts/check.mjs <film>                   # codec, size, fps, yuv420p, bt709, duration, loudness, faststart
node <skill>/scripts/render.mjs <film> --poster --all-formats
```
Look at `out/<film>/check_<fmt>.png` — decoded from the mp4, it catches encode/colour problems the canvas can't. Deliver: paths to `final.mp4` and each `final_<fmt>.mp4`, posters, contact sheet, the last critique scores, and **what you'd fix next** — the critique's remaining issues named concretely, not a wishlist.

## Banned defaults

Centered title on a gradient · everything fading in · fade from black at frame 0 · corner labels and frame borders · glow on UI chrome · generic particle bursts · stock "tech" lines/grids with no meaning · more than one accent colour · a third typeface · invented UI · text outside the safe area · a static hold > 4 s without a new event (end card excepted, which holds ≥ 1.5 s, still enough to read the URL twice).

## Project layout

```
<film>/film.json  index.html  film.js  hits.js  lib/motion.js  beats.json  [lipsync.json]
<film>/fonts/display.* ui.*
<film>/assets/shots/ logo/ fonts/(fonts.json) brand.json copy.md
<film>/docs/style_guide.md shotlist.md critique.md reference/
<film>/audio/music.wav sfx.wav [vo.wav script.txt] mix.wav
out/<film>/contact_<fmt>.png (+_a/_b, phone_<fmt>.png, contact_<fmt>/bNNN.png) strip_*.png stills/
out/<film>/hits.json video_<fmt>.mp4 final_<fmt>.mp4 final.mp4 poster_<fmt>.png check_<fmt>.png
```
`film.json`: `{ title, duration, fps, formats: [primary, …], poster }`.

## References (read when the stage needs them)

- `references/motion-api.md` — motion.js API, film.js contract, timing/easing numbers, idioms
- `references/shotlist.md` — shot-list rules, template, worked example
- `references/style-guide.md` — reading a reference, style guide template
- `references/audio.md` — score flavours, grids, SFX palette and opts, mix targets, sync
- `references/voiceover.md` — script length, sources, editing onto the grid, ducking, lip-sync
- `references/critique.md` — the critique pass (rubric, checks, output shape)

## Gotchas

- Fonts: missing files log `font not loaded … (falling back)` in the renderer output — fix before critique, fallbacks change every measurement.
- A 404 on an image logs `[http 404]`; the image is left out of `IMG` and `M.cover` draws nothing.
- Hit times are snapped to the frame grid only for picture; `sync.mjs` flags hits > 1 ms off a frame boundary — usually harmless at 60 fps.
- `gather` behind a proxy: Chromium uses `HTTPS_PROXY`; Node fetch (fonts, logo) needs `NODE_USE_ENV_PROXY=1` on Node ≥ 22.21.
- Renders are CPU-bound; `--workers` defaults to 4. Static frames skip the blur pass automatically.
