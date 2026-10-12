# motion.js API and the film.js contract

`film.js` imports `./lib/motion.js` as `M` and `./hits.js`, then calls `M.film({...})` once. It exports nothing; the renderer talks to the page through `window.seek(t)`, `window.capture(t)`, `window.filmReady`, `window.HITS`, `window.DURATION`, `window.FPS`.

```js
import * as M from './lib/motion.js';
import { HITS } from './hits.js';
const { E, FORMAT: F, W, H } = M;

function draw(ctx, u, t, IMG) { /* pure: paint beat u (seconds t) */ }

M.film({
  draw,                       // (ctx, u, t, IMG) — required
  init,                       // (ctx, IMG) — optional, once, for caches (never time-dependent state)
  hits: HITS,
  fonts: [M.font(100, 800), M.font(40, 600, 'UI')],     // every face+weight you draw with
  images: { hero: 'assets/shots/desktop_viewport.png' }, // decoded before frame 0 → IMG.hero
  samples: 8, shutter: 0.5,   // motion blur: sub-frames per frame, shutter as fraction of a frame
});
```

The harness resets transform, alpha, composite, shadow and filter before every `draw`, so a scene can't leak state into the next frame. Text baseline is `alphabetic`.

## Format and layout

| export | meaning |
|---|---|
| `W`, `H` | canvas size: 1920×1080 (16x9), 1080×1920 (9x16), 1080×1080 (1x1) |
| `FORMAT.name` | `'16x9' \| '9x16' \| '1x1'`; flags `.landscape .portrait .square` |
| `FORMAT.safe` | `{x, y, w, h, cx, cy}` — insets 16x9 `96/60/96/60`, 9x16 `72/250/150/430` (L/T/R/B), 1x1 `72` all round |
| `FORMAT.pick({'16x9': a, '9x16': b, '1x1': c})` | per-format value (falls back to 16x9) |
| `RENDER` | true when rendering (`?render=1`) |

Lay out per format with `FORMAT.pick` for whole layout objects (sizes, positions, which shots), not scale factors on a 16:9 layout. 9:16 usually stacks what 16:9 places side by side, and uses `mobile_viewport.png` for UI.

## Time

| export | meaning |
|---|---|
| `GRID` | `beats.json`: `bpm, period, offset, beats[], downbeats[], sections{}` |
| `CFG` | `film.json`: `duration, fps, title, …` |
| `U(t)`, `T(u)` | seconds ↔ beats |
| `clamp(x,a=0,b=1)`, `lerp`, `remap(x,a,b,c,d)` | |
| `prog(u, a, b)` | 0→1 across beats a..b, clamped |
| `bump(u, c, w)` | cos² pulse centred on c, half-width w (beats) — downbeat pulses |

## Easing and keys

`E.linear inQuad outQuad inCubic outCubic inOutCubic outQuart outQuint inExpo outExpo inOutExpo inOutSine outBack(t,s) inBack(t,s) standard decel accel bezier(x1,y1,x2,y2)`
(`standard` = Material 0.2,0,0,1; `decel` = 0.05,0.7,0.1,1 for entrances; `accel` = 0.3,0,0.8,0.15 for exits.)

`kf(u, [[u0, v0], [u1, v1, ease?], …], defaultEase)` — keyframes in beats, numbers or arrays; a key's ease shapes the segment ending at it.

## Springs (closed form, pure)

`spring(tSec, {stiffness, damping, mass, velocity})` → 0..1 step response.
`SPRING` presets (measured peaks): `snappy` 380/30 (2 % overshoot, settles ≈ 0.25 s) · `bouncy` 260/13 (25 %) · `gentle` 120/20 (none, soft) · `wobbly` 180/8 (37 %, cartoon).
`springU(u, u0, cfg)` — spring starting at beat u0; time is measured in seconds so feel doesn't change with tempo.
`springKeys(u, [[u0, v0], [u1, v1, cfg?], …], cfg)` — chained targets; deltas superpose, so a move interrupted mid-flight stays physical.
`wobble(u, u0, freq=2.2, damp=5)` / `ring(…)` — damped cos/sin after u0 for secondary motion (a dot that rings when it lands).

**Springs overshoot → `1 - spring` goes negative.** Use `M.alpha(ctx, a)` or `M.clamp` for anything that becomes `globalAlpha`; `text`, `glyphs` and `cover` clamp for you.

## Noise and camera

`mulberry32(seed)`, `hash01(i, seed)`, `noise1(x, seed)` (smooth value noise −1..1), `shake(ctx, u, u0, amp=12, seed, decay=0.25 s)` — translates ctx, decays after u0; call inside `save/restore`.

## Colour

`hexRgb`, `rgbHex`, `mix(hexA, hexB, t)` → hex, `rgba(hex, a)`.

## Type

Faces are `Display` and `UI` (from `<film>/fonts/display.*`, `ui.*`).

| export | |
|---|---|
| `font(size, weight=700, family='Display')` | CSS font string |
| `layout(ctx, str, font, track=0)` | per-glyph layout with kerning; **tracking in em**; cached → `{glyphs[{ch,x,adv,cx}], width, asc, desc, size}` |
| `fitSize(ctx, str, maxW, {weight, family, max, min, track})` | largest size that fits |
| `text(ctx, str, x, y, font, color, {align, track, alpha})` | static text |
| `glyphs(ctx, str, x, y, font, color, (i, n, g) => ({dx, dy, sx, sy, rot, alpha, color}), {align, track})` | per-glyph animation — the workhorse for kinetic type |
| `wrap(ctx, str, font, maxW, track)` | → lines |

## Shapes and images

`fill(ctx, color)` (full frame, ignores transform) · `rrect(ctx, x, y, w, h, r)` (path only; then `fill()`/`clip()`) · `zoomAbout(ctx, s, x, y)` · `cover(ctx, img, x, y, w, h, {fx, fy, zoom, radius, alpha})` (cover-fit with focal point — the way to show screenshots) · `crop(ctx, img, [sx,sy,sw,sh], x, y, w, h)` (a UI detail at full res) · `shadow(ctx, blur, y, a)` (subtle; no glows).

Screenshots from `gather` are @2x (desktop) or @3x (mobile): a 1440-wide page is 2880 px, so `crop` to a region and draw it ≥ 1:1 for crisp UI close-ups. Push-ins: animate `zoom` in `cover`, or `zoomAbout` on a crop.

## Timing numbers that work

| move | duration | ease |
|---|---|---|
| UI element entrance | 0.4–0.6 beat (≈ 200–300 ms at 120 bpm) | `springU` snappy, or `E.decel` |
| Headline word/glyph | spring bouncy, stagger 0.03–0.08 beat | |
| Card / panel landing | spring bouncy + `ring` on a detail | `thud`/`impact` on the hit |
| Exit | 60–70 % of the entrance | snappy spring or `E.accel` |
| Camera push | 4–8 beats, 4–8 % scale | `E.inOutSine` or gentle spring |
| Hold to read | ≥ 0.3 s + 0.25 s per word on screen | |
| End card | ≥ 1.5 s still-ish, read the URL twice | |
| New event | every 2–4 s (4–8 beats at 120–130 bpm) | |

Hook: the first 2 s (≈ 4 beats) decide whether a thumb stops. Frame 0 must already contain the subject in motion — never a fade from black or an empty frame.

## Idioms

- **Scene table in beats** (`const S = { open: [0, 8], … }`) and `if (u in range) scene(ctx, u)`. Draw neighbouring scenes during overlaps so transitions carry something across (a rule becomes a card edge, a word becomes a button).
- **Motivated transitions:** match cut on a shape, push through a UI element, whip with blur, mask wipe on an edge from the outgoing shot. Say in the shot list what carries over.
- **Hits drive picture too:** `HITS.filter(h => h[1].startsWith('feature'))` keeps the visuals and SFX on the same beats.
- **Use `init` only for caches** (offscreen pre-renders, layout). Never store anything that depends on t.
- **Big images:** pre-crop in `init` to an `OffscreenCanvas` if you draw the same region every frame.
