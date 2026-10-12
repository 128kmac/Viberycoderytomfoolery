# Shot list

Write `<film>/docs/shotlist.md` after the grid exists (you need the bpm and beat count), then **stop and get the user's OK**.

## Rules

- **Units are beats.** Seconds are derived (`t = offset + beat × period`) and shown for the reader.
- **Frame 0 is a shot.** The hook lands in beats 0–4 (≈ first 2 s). No fade from black, no logo sting first.
- **Something new every 2–4 s** (4–8 beats at 120–130 bpm), each marked with a hit.
- Big changes on downbeats and section starts (`beats.json.sections`); small accents may syncopate (the "and" of a beat).
- **Every shot names its asset file** (`assets/shots/section_03_pricing.png`, `copy.md › h1`) or says "type only" / "shape only". No asset → no shot.
- Copy comes from `copy.md` or the user. Never invent claims, numbers or quotes.
- **Plan each format.** One line per shot for what changes in 9:16 and 1:1.
- **End card holds ≥ 1.5 s**: name or logo, URL, one line in the brand's own words.
- **Transitions are motivated:** say what carries over.
- A typical arc: hook (0–2 s) → problem or promise → product reveal → 2–3 feature beats → proof → name + URL. Fewer, clearer beats beat more, rushed ones.

## Template

```markdown
# <Title>: shot list
<duration> s · <bpm> bpm · <N> beats · formats: 16x9 (primary), 9x16
Music: <score flavour, key, mode / track + excerpt> · VO: <none / audio/script.txt>

| # | beats | time | shot | on screen (asset) | motion | out → (transition) | sound (hits) |
|---|---|---|---|---|---|---|---|
| 1 | 0–8 | 0.00–3.75 | Hook | "Ship it faster." (copy.md › h1), type only | words spring up per beat, accent on last word | rule under headline extends into card edge | pop ×3 on 0,1,2 |
| 2 | 8–16 | 3.75–7.50 | Product reveal | desktop_viewport.png, cover, fy 0 | card lands bouncy, 6 % push over 8 beats | push into the "Deploy" button | riser→impact on 8 |
| … | | | | | | | |

Formats:
- 9x16: shot 2 uses mobile_viewport.png full-bleed; feature list stacks below; headline 3 lines.
- 1x1: …

Longest gap without a new event: beats a–b (x.x s).
```

## Worked example (excerpt, 15 s, 128 bpm, 32 beats)

| # | beats | shot | on screen | motion | out | sound |
|---|---|---|---|---|---|---|
| 1 | 0–4 | Hook | "Run JavaScript Everywhere" (copy.md › h1) | words rise on 0/1/2, "Everywhere" in accent green | headline shrinks to top-left as the code panel enters | pop A5, C#6, E6 |
| 2 | 4–8 | Code | crop of desktop_viewport.png code block (2880 px source, 1:1) | lines type on, 0.12 beat each | camera pushes 5 % toward `listen(3000)` | type n=14 |
| 3 | 8–14 | Drop | "Get Node.js®" button crop | button springs to centre on the drop | button click → whip to next | riser→impact 8, click 12 |
| … | | | | | | |

Longest gap: beats 20–26 (2.8 s).
