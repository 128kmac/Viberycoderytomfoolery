# Claude Pro: critique log

## Round 1
| hook | read | motion | variety | brand | sync | min |
|---|---|---|---|---|---|---|
| 5 | 6 | 7 | 7 | 9 | – | 5 |

Worst three:
1. [b0–2] Spark has mostly settled before frame 0 (spring started at −0.6 beat), and the headline is small and high. Frame 0 doesn't stop a thumb. → Start the spark spring at −0.12 beat from 1900 px, headline 132 → 150 px, baseline 470 → 500.
2. [b8–16] Row crops sit in white boxes on the ivory ground, and the original grey check peeks out left of the clay one. → Multiply-blend the crops (card white → ivory) and erase the grey check with ivory over x 1090–1156 source px.
3. [b17–19] "Don't know where to start? Ask Claude." runs past the right safe edge. → Fit the headline to the bar width with `fitSize`.

Checks failed: text outside the safe area (b17–19).
Verdict: ANOTHER ROUND

## Round 2
| hook | read | motion | variety | brand | sync | min |
|---|---|---|---|---|---|---|
| 8 | 8 | 8 | 8 | 9 | 7 | 7 |

Evidence: frame 0 is a 1900 px clay spark mid-turn; rows read cleanly at phone size; 13/15 hits within 20 ms.

Worst three:
1. [b21] URL typing sound is buried and starts 150–625 ms late (random first click). → Gain 0.25 → 0.5, layer `tick` on the beat (`tick+type`).
2. [all] SFX stem sits about 10 dB under the mix, so picture accents don't read. → `mix.mjs --sfx-db 3`.
3. [b0] sync.py reports +313 ms, but the tok is present in the stem at −22 dBFS. The detector has no pre-roll, so a hit at t = 0 can't register. Not a real offset; verified by stem RMS.

Checks failed: none.
Verdict: ANOTHER ROUND

## Round 3
| hook | read | motion | variety | brand | sync | min |
|---|---|---|---|---|---|---|
| 8 | 8 | 8 | 8 | 9 | 8 | 8 |

Evidence: strips at 2.0–2.9 s, 9.6–10.4 s and 11.6–12.8 s.

Worst three:
1. [b4–5] After the card lands, hook line 2 stays parked at the top while line 1 is half cut off by the frame edge. Reads as a crop accident. → The hook gets an exit spring at b4.1 (+520 px up) and clears by b5. Fixed and re-stripped (2.4–3.6 s): clean.
2. [b19.5–19.85] About 0.2 s of plain clay before the wordmark lands. Reads as a breath on the downbeat, so kept.
3. [b8–16] The context card on the left is too small to read at phone size. It's context only; the readable content is the lifted rows. Kept.

Checks: no banned defaults · longest gap 1.6 s (end-card hold) · one accent (clay) · end card holds 2.5 s · matches the approved shot list.
Verdict: READY
