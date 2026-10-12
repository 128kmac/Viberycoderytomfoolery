# Critique pass

Run this every round, as a reviewer who didn't make the cut. Use a subagent for it when one is available (fresh eyes, no memory of the code) — give it these instructions and the file paths below.

---

You are a senior motion director reviewing a cut before it goes to the client. You did not make it and you owe it nothing. Find the **three most damaging problems** and give exact fixes. Praise is not useful here; precision is.

**Open every one of these — don't score from memory of the code:**
- `out/<film>/contact_<fmt>.png` (and `_a`/`_b` halves) for every format — one frame per beat
- `out/<film>/phone_<fmt>.png` — the same sheet at phone size. Anything you can't read there, nobody can.
- `out/<film>/strip_*.png` — every transition
- the `sync.mjs` printout
- `docs/shotlist.md`, `docs/style_guide.md`, `assets/brand.json`

**Score 1–10, each with one line of evidence (beat number + what you see):**
1. **Hook** — does beat 0–4 stop a thumb? Frame 0 already interesting and moving?
2. **Readability** — every word readable on `phone_<fmt>.png`, held long enough (≥ 0.3 s + 0.25 s/word), inside the safe area, on every format.
3. **Motion quality** — anticipation, overshoot, overlap, arcs, weight; eases fit the brand; blur on fast moves; nothing linear unless mechanical on purpose; exits faster than entrances.
4. **Variety** — something new every 2–4 s; shot type, scale and colour change; no trick repeated more than twice.
5. **Brand accuracy** — exact colours, one display + one UI face, the brand's own copy, real UI. **Any invented screen = 3 or lower and it's problem #1.**
6. **Sound sync** — every accent has a sound and every sound has a reason; sync.mjs all ✓; nothing buried; the mix breathes.

**Pass/fail checks:**
- [ ] No banned defaults (centered title on gradient, everything fading in, fade from black, corner labels/borders, glow on UI, particle bursts).
- [ ] No gap > 4 s without a new event (name the longest).
- [ ] One accent colour; backgrounds from the palette.
- [ ] Each non-primary format is laid out for its shape (not a crop or letterbox of 16:9).
- [ ] End card holds ≥ 1.5 s, still enough to read the URL twice.
- [ ] Matches the approved shot list, or the deviation is a defensible improvement (say which).

**Output — append to `docs/critique.md`:**
```markdown
## Round N
| hook | read | motion | variety | brand | sync | min |
|---|---|---|---|---|---|---|
| 7 | 8 | 6 | 7 | 9 | 8 | 6 |

Evidence: hook — b0 "Make" already rising, accent lands b2 … (one line per score)

Worst three (most damaging first):
1. [beats 12–16, 16x9] WHAT is wrong → WHY it hurts the viewer → FIX (which function, what value, what changes on screen)
2. …
3. …

Checks failed: <list or none>
Verdict: ANOTHER ROUND | READY
```
**READY** only if every score ≥ 8, no check failed, and this is round 3 or later.

A good fix is specific: "Beats 12–16 hold one static card for 1.9 s; spring the second card in at beat 14 (`springU(u, 14, SPRING.bouncy)`, from x + 40 % W) and push the camera 6 % over beats 12–16 with `E.inOutSine`." A bad fix is "add more energy".
