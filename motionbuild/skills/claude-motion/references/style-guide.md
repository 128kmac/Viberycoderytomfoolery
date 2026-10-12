# Style guide from a reference

Run `reference.mjs` on the user's reference (video, still, or folder) and read what it writes in `<film>/docs/reference/`:

- `shots.png` — the middle frame of every shot (hard cuts only; up to 40, evenly sampled beyond that)
- `seconds.png` — one frame per second for the first 60 s: read motion *between* cuts, match cuts, morphs, wipes
- `cuts.json` — shot count, median/mean shot length, cuts per 10 s, cut times
- `sheet.png` — for still references

Then write `<film>/docs/style_guide.md`. **Describe what you can see and measure, not adjectives.** "Snappy" is useless; "moves resolve in 6–8 frames with ~10 % overshoot" is buildable. Map every observation to something in motion.js.

**The reference gives motion and composition. The brand keeps its colours, type and copy.**

## Template

```markdown
# Style guide — from <reference name>

## Rhythm
- Median shot <x.x> s, <n> cuts / 10 s. Cuts land on <downbeats | every beat | off-grid>.
- Holds: <where the reference lets a frame breathe, and for how long>.
- → For us at <bpm>: a new event every <n> beats; cuts on downbeats; holds only at <…>.

## Motion vocabulary
- Entrances: <slide from below 8 % of H, scale 0.9→1, per-word stagger ~2 frames>  → `springU` bouncy, stagger 0.05 beat
- Exits: <fast scale-down + blur, ~5 frames>  → snappy, 0.3 beat
- Easing character: <hard overshoot | critically damped | linear mechanical>  → SPRING.<preset>
- Camera: <constant slow push 3 %/s | static | whip pans between scenes>
- Signature move: <the one thing you'd recognise it by>  → how we'll do it

## Composition
- Grid / margins: <12-col, 6 % margins | centred stack>
- Alignment: <left-aligned headlines, ragged right>
- Scale contrast: <headline ≈ 5× body>; negative space: <~40 % empty>
- How UI is framed: <floating cards with 24 px radius, soft shadow | full-bleed crops | device frames>

## Colour + texture (mapped onto brand.json)
- Reference uses <dark bg, one hot accent, grain>.
- Ours: bg <brand bg>, ink <brand text>, accent <one brand colour>, texture <none | 3 % grain>.

## Type in motion
- Animated per <glyph | word | line>; size <…>; tracking <-0.02 em on display>; weight <800 display / 500 UI>.

## Do / don't
- Do: <3 concrete, measurable>
- Don't: <3 concrete>
```
