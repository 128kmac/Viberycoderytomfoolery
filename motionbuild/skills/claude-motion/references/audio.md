# Audio: score, grid, SFX, mix, sync

All audio is 48 kHz stereo. Three stems: `music.wav`, `sfx.wav`, optional `vo.wav`. `mix.mjs` masters their sum.

## Score (`score.mjs`) — synthesized, exact grid

```bash
node <skill>/scripts/score.mjs <film> [--flavor pulse|minimal|lofi|cinematic] [--bpm auto|N] [--key A] [--mode major|minor|dorian|mixolydian] [--drop BAR] [--seed N]
```

| flavour | tempo (auto) | feel | use for |
|---|---|---|---|
| `pulse` | 112–136, home 124 | four-on-the-floor kick, clap, 16th hats, eighth bass, plucks, pumping sidechain | launches, energetic product reels |
| `minimal` | 108–132, home 120 | kick, rim, shaker, sparse bells | dev tools, precise/technical brands |
| `lofi` | 72–96, home 86 | swung hats, soft kick, FM keys with 7ths | friendly, calm, explainer |
| `cinematic` | 84–120, home 100 | big pads, low hits on 1, risers every 2 bars | reveals, brand films, serious tone |

- `--bpm auto` picks the tempo nearest home that makes the duration whole bars, so the last bar resolves exactly at the end.
- Structure: `intro` (soft, filtered) → **drop** at `--drop` bar (default 1 for ≤ 6 bars, 2 for ≤ 10, else 4; reversed cymbal into it, crash + sub on it) → `main` → `end` (last bar: tonic chord, crash, sub, the resolve under the end card).
- Chord loops: major I–V–vi–IV, minor i–VI–III–VII, dorian i–IV–i–bVII, mixolydian I–bVII–IV–I.
- `--seed` changes the details (noise, voicing), never the timing. Same arguments → same file.
- The grid is written by construction: `offset 0`, `period 60/bpm`. Sections land in `beats.json.sections` as `{intro:[b0,b1], main:[…], end:[…]}` in beats.

Put the drop where the film's biggest change is (usually the product reveal), and the shot list's section starts on `sections`.

## Supplied track (`beats.mjs`) — measured grid

```bash
node <skill>/scripts/beats.mjs <film> --track song.mp3 [--start auto|SECONDS] [--bpm-hint 120]
```
Measures tempo (autocorrelation of spectral flux, 60–180 bpm), phase (kick-weighted comb), refines by least-squares on onsets (4 rounds of outlier rejection), finds the downbeat from the low band, then cuts a `duration`-long excerpt **starting on a downbeat** (the loudest window, or nearest `--start`). Writes `music.wav` (5 ms fade-in, ≤ 0.5 s squared fade-out, −3 dBFS peak) and `beats.json` with `fit_inliers` / `fit_residual_ms`.
A weak-fit warning (< 16 inliers or > 15 ms rms) means: try `--bpm-hint` at the felt tempo, half or double, and confirm by ear before building. Only use tracks the user has rights to.

## SFX (`hits.js` → `sfx.mjs`)

Every row of `hits.js` is `[beat, label, sfx, opts]`; `sfx` is a palette name, `'a+b'` layers, or `null` (silent accent — still listed). `node <skill>/scripts/sfx.mjs --list` prints the palette:

| name | gain | anchor | for |
|---|---|---|---|
| pop | .35 | start | word/element pops on (`pitch`, `to`) |
| click | .3 | start | cursor taps, toggles |
| tick | .22 | start | list items, counters |
| blip | .2 | start | checkmarks, badges (`pitch`) |
| thud | .45 | start | cards landing |
| tok | .35 | start | playful wooden UI (`pitch`) |
| bell | .3 | start | success, reveal (`pitch`, `len`) |
| coins | .3 | start | money, rewards (`n`, `spread`) |
| type | .2 | start | typing (`n`, `len`) |
| boing | .3 | start | cartoon overshoot |
| glitch | .25 | start | data, tech, errors |
| shutter | .3 | start | screenshots, snaps |
| whoosh | .3 | **peak** | moves and wipes — peaks ON the hit (`from`, `to`, `len`, `peak`) |
| riser | .35 | **end** | into a section change — ends ON the hit (`len`) |
| swell | .25 | **end** | reversed cymbal into a reveal — ends ON the hit |
| crash | .25 | start | section downbeat |
| sub | .6 | start | weight under a big moment |
| impact | .7 | start | sub+thud+crash: drop, scene change, end card — sparingly |

opts: `gain, pan (−1..1), pitch (Hz or 'D6'), to, from, len (s), peak (0..1), anchor (start|peak|end), verb (reverb send, default .15), n, spread`.

- **Risers and swells end ON the hit; whooshes peak on it.** Put the riser row on the same beat as the impact it leads into.
- The SFX stem sits at 0.4 of palette gain (≈ 2–3 LU under the bed). Rhythmic hits (pops on beats) can be quiet — the music already marks the beat; sounds that mark *picture* events (landings, clicks, typing) need to be heard.
- Don't wall-to-wall: if every beat has a sound, none of them reads. Leave the mix room to breathe between sections.
- Determinism: each hit's noise is seeded by its index, so the same hits.js renders the same sfx.wav.

## Mix and master (`mix.mjs`)

```bash
node <skill>/scripts/mix.mjs <film> [--music-db 0] [--sfx-db 0] [--vo-db 2] [--lufs -14] [--tp -1] [--no-mux]
```
1. Stems resampled to 48 k stereo, padded/trimmed to the duration, levelled; music ducks under VO (`sidechaincompress` threshold .03, ratio 6, 15/300 ms) when both exist; summed without normalisation; 0.3 s tail fade.
2. Mastered by gain → 4× oversampled look-ahead limiter at (tp − 0.5) dBFS → re-measure (EBU R128), iterating up to 6 times until within 0.1 LU. Written as 24-bit `mix.wav`.
3. Muxed into each `video_<fmt>.mp4` → `final_<fmt>.mp4` (video stream copied, AAC 320 k, +faststart); the primary format is also `final.mp4`.

Targets: **−14 LUFS integrated, ≤ −1 dBTP** — YouTube/Spotify reference, safe for Instagram/TikTok/X (which normalise anyway). If the user asks for a louder social master, `--lufs -12`. A note that the limiter needed > 12 dB gain means the stems are too quiet or too spiky: raise the bed, don't just squash.

## Sync (`sync.mjs`)

```bash
node <skill>/scripts/sync.mjs <film> [--tol 20]
```
Detects onsets in the SFX stem (spectral flux, ≈ 3 ms accuracy, 100 ms pre-roll so t = 0 is visible) and reports each hit's offset: start-anchored hits must be within ±20 ms, whoosh peaks within ±40 ms, risers/swells must be building into their end. It also flags hits that are buried (> 18 dB under the full mix around them). Exit code 2 when anything fails — fix before calling a round done.
