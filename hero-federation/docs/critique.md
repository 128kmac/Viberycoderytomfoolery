# Critique log

Scored 1–10 on hook, readability at phone size, motion, variety, brand (palette / type / originality),
and sync. Sources: the per-scene stills and both beat contact sheets (`out/hero-federation/contact*.png`).

## Round 1 (first build, per-scene stills)
| hook | read | motion | variety | brand | sync | min |
|  6   |  5   |   7    |    6    |   8   |  8   |  5  |

Worst three:
1. [u32–40] The Legion (front): the soldiers were tiny and ink on an ink ground, so the shot read as an empty
   synthwave grid. **Fix:** backlit by a horizon sun, a reflective parade ground, larger rows, distance fog, and
   flag-bearers in the ranks.
2. [u48–60, u120–136] The ships were too small to read as warships (they looked like fish). **Fix:** the fleet now
   passes overhead at 5–6.5× scale, the armada uses a 32° telephoto, and the hulls are lighter steel.
3. [u98–110] Ascent: the slogans were ink on the ink arch and unreadable. **Fix:** crimson plates with gold Cinzel.
   Also fixed: the "LONG LIVE" / "THE CROWN" collision, the washed-out portrait face (features and hair engraving
   added), the oversized crowd flags, and insignia vanishing for a frame on each beat (0.12-beat pre-roll).

## Round 2 (beat contact sheets)
| hook | read | motion | variety | brand | sync | min |
|  7   |  8   |   8    |    7    |   9   |  9   |  7  |

Worst three:
1. [u80–88] The coronation held one composition for 8 beats. **Fix:** at u84 the camera pulls back and an honour
   guard raises sabres toward the crest, staggered on the beats.
2. [u120–136] The armada was one angle for 16 beats. **Fix:** at u128 it cuts to a low angle with the flagship
   silhouetted against the sun.
3. [u8–16] The sovereign shot was static, and the crash flash at u15 washed the frame for a whole beat. **Fix:** a
   12% push toward the face, and a tighter flash (±0.45 beat, 80%).

## Round 3 (spot checks: stills and the u79–81 strip)
| hook | read | motion | variety | brand | sync | min |
|  7   |  8   |   8    |    8    |   9   |  9   |  7  |

Remaining (next pass):
- Hook: frame 0 is a half-engraved rosette on navy. It is elegant but quiet. The song starts mid-bridge, so a
  harder open (the crest already glinting) would grab more.
- The 3D crown at u79.9 hands off to the much smaller 2D crown on the crest. It is hidden by the impact flash but
  not a true match cut.
- The balcony crowd is abstract confetti at full size. Rows of figures under the flags would sell "the people" better.

Sync (`sync.py` against the song): 21/30 hits are within 20 ms of an audio onset, with a median of 15.6 ms. Every
offset is picture-after-sound by about one frame, consistently: the analyzer times onsets at the peak of the dB
rise rather than the start of the attack. It's under a frame at 60 fps and doesn't drift. A next pass could shift the
grid 12 ms earlier. Flashes, pulses and glints come from the song's own kick / snare / crash envelopes.
