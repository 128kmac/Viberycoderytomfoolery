# Viberycoderytomfoolery

## HERO: The Federation (`hero-federation/`)

A motion-graphics music video for Skillet's "Hero" (1:57 to the end, 69.8 s): a Federation state broadcast
"engraved in gold" for the Critical Point Federation. It glamorizes the military and the crown through
banknote guilloche, heraldry, art-deco propaganda posters and flat-shaded 3D (fleet, medal, crown). There is no
filmed footage, and no lyrics appear on screen. All emblems, figures and slogans are original. The crest,
motto and colours are placeholders that live in `lib/heraldry.js` (`PAL`, `crest()`).

The film is code: `film.js` is a pure function of time, rendered frame-exact at 60 fps by the motion-reel
renderer. It is timed in beats on the grid measured from the song, and driven by per-frame envelopes
(kick, snare, crash, loudness, vocal, pitch) from the analyzer.

- Plan: `hero-federation/docs/shotlist.md`. Review log: `docs/critique.md`.
- Preview: serve the repo root and open `hero-federation/index.html` (space plays it, click to scrub). The audio
  file isn't committed; recreate it with the analyzer's `--excerpt-wav`.

## Song analyzer (`tools/song-analyzer/`)

Beat grid, key/chords, loudness map, structure, drums, instrument layers, vocal phrases and melody (with an
optional neural vocal separation), plus per-frame animation cues and an interactive HTML report.
See `tools/song-analyzer/README.md`.

To rebuild the video's inputs (the song file is not committed):

```bash
uv run tools/song-analyzer/analyze.py media/hero.mp3 --out hero-federation/analysis --start 1:57 \
  --vocal-model UVR-MDX-NET-Voc_FT.onnx --excerpt-wav hero-federation/audio/music.wav --audio-src ../audio/music.wav
cp hero-federation/analysis/beats.json hero-federation/beats.json
```
