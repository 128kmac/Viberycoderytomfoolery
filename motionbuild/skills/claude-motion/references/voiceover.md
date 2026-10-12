# Voice-over and lip-sync (optional — default is no VO)

## Script

- ≈ 2.5 words/s for a clear read, ≈ 3 for an energetic one. 15 s holds about 30 words; leave the first beat and the end card's last 1.5 s free.
- Write it in `<film>/audio/script.txt`. A take that runs long is fixed by **rewriting**, never by speeding it past 1.1×.
- Every claim spoken should also be readable on screen (most social viewing is sound-off).
- Write in the language's native script; avoid sounds the chosen voice can't say well.

## Sources

1. **A recording the user supplies** — ask for a clean, dry take (no music, no reverb), WAV if possible; put it in `<film>/audio/vo/`.
2. **A TTS tool the user has connected** (an MCP server or CLI). Never ask for an API key in chat or write one to disk; if the user pastes one, point them to their tool's own config and suggest rotating it. Run every take back through transcription if available and check the brand name comes back right.
3. **Offline scratch VO for timing only** — ffmpeg's built-in flite:
   `ffmpeg -f lavfi -i "flite=textfile=<film>/audio/script.txt:voice=slt" -ar 48000 -ac 2 <film>/audio/vo/scratch.wav`
   Robotic: fine for locking the edit and lip-sync shapes, never for delivery. Better offline voices: Kokoro (Apache-2.0) or Piper (GPL — mind redistribution), if installed.

## Edit onto the grid

- Cut phrases at silences (≈ −35 dB for ≥ 150 ms) or in the closure before a plosive.
- Land each phrase's **speech onset on a beat** (detect the onset: first 5 ms window above −32 dB, minus 15 ms). A 3-3-2 syncopation (beats 0, 1.5, 3) suits a three-word slogan.
- Print the gaps between phrases and fix any overlap; keep ≥ 1 beat of air before the end card.
- A light VO chain helps intelligibility: `highpass=f=90, equalizer=f=3200:t=q:w=1:g=3, acompressor=threshold=-22dB:ratio=3:attack=4:release=80:makeup=4`.
- Assemble with ffmpeg `adelay`/`amix` (or a small Node script using `lib/dsp.mjs` `add()` + `writeWav`) into `<film>/audio/vo.wav`, exactly `duration` long.
- `mix.mjs` lifts VO +2 dB and ducks the music under it. If any word is hard to hear with the music under it, deepen the duck (`--music-db -3`) or lift the VO before touching anything else.
- Supers (on-screen words) are timed per phrase from the same onsets; put them in `hits.js` as silent accents so they show up in sync checks.

## Lip-sync for a talking character

```bash
node <skill>/scripts/lipsync.mjs <film> [--script audio/script.txt] [--phonetic]
```
Writes `<film>/lipsync.json`:
```json
{ "rate": 100, "open": [0..1 per 10 ms], "shapes": [[t0, t1, "A".."H"|"X"], …], "phrases": [[t0, t1], …] }
```
- `open` — 30 ms RMS every 10 ms, mapped `(dB − max + 40) / 34`, gated at −45 dB, fast attack / slower release. Always present.
- `shapes` — Rhubarb Lip Sync mouth cues if `rhubarb` is on PATH (A closed P/B/M · B slightly open, teeth · C open EH · D wide AA · E rounded AO · F puckered OO/W · G F/V · H L · X idle). `-d script.txt` improves accuracy; `--phonetic` for non-English.
- `phrases` — speech runs, for nods and super timing.

In `film.js`, load it in `init` (it's static data, so this is allowed) and look it up purely:
```js
let LS = null;
async function init() { LS = await (await fetch('lipsync.json')).json(); }   // pass init to M.film
const openAt = (t) => LS ? LS.open[Math.min(LS.open.length - 1, Math.max(0, Math.round(t * LS.rate)))] ?? 0 : 0;
const shapeAt = (t) => LS?.shapes.find(([a, b]) => t >= a && t < b)?.[2] ?? 'X';
```
`M.film` awaits `init`, so the data is loaded before frame 0 is painted.

Drawing: blend between drawn mouth shapes over ±40 ms (coarticulation), hold each shape ≥ 2 frames to avoid chatter, add a damped head nod after each phrase onset (`ring(u, phraseBeat, 2.4, 4.5)`), and jaw drop ∝ `open`. Keep the rig a pure function of t.
