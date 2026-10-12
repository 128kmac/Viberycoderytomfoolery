# Claude Pro: shot list
15 s · 96 bpm · 24 beats (0.625 s/beat) · formats: 16x9 (primary)
Music: synth lofi, F major, 96 bpm (intro b0–4 · main b4–20 · end b20–24) · VO: none

Look: ivory `#faf9f5` ground, ink `#141413`, one accent: clay `#d97757` (from brand.json / `--color-clay`).
Type: Anthropic Serif (display) + Anthropic Sans (UI), both gathered from claude.com, variable 300–800.
Motion: calm and editorial, matching the brand. Gentle and snappy springs, a little overshoot on landings only, no bounce on type. Camera moves are slow pushes and pans across the real card.

| # | beats | time | shot | on screen (asset) | motion | out (transition) | sound (hits) |
|---|---|---|---|---|---|---|---|
| 1 | 0–4 | 0.00–2.50 | **Hook** | "Hand Claude a task, / not just a question." (copy: claude.com/product/overview hero), serif, left-aligned; clay spark (`logo/spark.svg`) | Frame 0: spark already spinning in from large scale at left; words rise per half-beat (line 1 b0–1.5, line 2 b2–3.5), slight per-glyph stagger | headline slides up and out as the card rises under it (the card pushes it) | tok b0, b2 (soft); riser ending b4 |
| 2 | 4–8 | 2.50–5.00 | **The Pro card** | real Pro card crop (`shots/section_00_pricing.png`, 832×1526 @2x): pictogram, "Pro", "For everyday work", $17 block | card rises from below with a small tilt and lands on the drop (b4); slow 4 % push. b6: camera eases to the price block, clay underline draws under "$17" (the card's own text shows "$20 if billed monthly") | camera pans down the card into the feature list | impact b4 · tick+blip b6 |
| 3 | 8–16 | 5.00–10.00 | **What Pro adds** | the card's real rows, "Everything in Free, plus:": *Hand off and schedule tasks*, *Claude Code*, *Projects*, *Claude in Chrome and Microsoft 365* (row crops from the same screenshot) | card slides to the left third; on b8/10/12/14 each row lifts out of the card (its line gets a clay tint in the card) and lands large on the right, stacking; a clay check draws on each | stack slides up and off as the Ask bar comes in | whoosh (peak b8) · blip b8, b10, b12, b14 rising pitch |
| 4 | 16–20 | 10.00–12.50 | **Ask Claude** | real input bar crop (`shots/page_product-overview_full.png`): "How can I help you today?" + clay "Ask Claude ↑" button; headline above it in the brand's words "Don't know where to start? Ask Claude." | bar springs up from below at b16; cursor-free press on the button at b18 (scale 0.96 → 1); b19 the clay button grows to fill the frame (mask from its own rounded rect) | the clay field becomes the end card ground | whoosh b16 · click b18 · swell ending b20 |
| 5 | 20–24 | 12.50–15.00 | **End card** (holds 2.5 s) | ivory spark + Claude wordmark (`logo/wordmark`, recoloured ivory) + serif "Pro"; "For everyday work." (card copy); `claude.com/pricing` | wordmark lands b20; URL types on b21; still from b21.5 to 24 (1.9 s still) | music resolves | impact b20 · type b21 |

Formats:
- 16x9 only (primary). Safe area 96/60 px.

Longest gap without a new event: beats 21.5–24 (1.6 s, the end card hold). Mid-film the gap is ≤ 2 beats (1.25 s) throughout.

Accuracy notes: all UI is gathered from claude.com (Pro card, rows, input bar). The price is shown only as the real card text, which includes "$20 if billed monthly". No invented screens and no chat transcripts.
