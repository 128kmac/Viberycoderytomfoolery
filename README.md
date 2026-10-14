# Viberycoderytomfoolery

## HERO: The Domini (`hero-federation/`)

A motion-graphics music video for Skillet's "Hero" (1:57 to the end, 69.8 s). It's a recruitment broadcast for
**the Domini**, the Federation of the Critical Point story (from *The Domini: Federation Lore*). The order of hooded,
faceless crusaders hunts scammers, beamers and exploiters, climbs an earned rank ladder (Claves to Messor and Aureus)
beneath three hereditary houses (Frigidus, Infernus, Empyerus), and serves Lord Emperyan. Atmos, Judas, the Empyrean
Sword, the Lord of the Federation crown and the Azurelight's empty seat all appear.

It's all motion graphics (2D illustration plus flat-shaded 3D) and contains no filmed footage and no lyrics. Characters
are drawn in the film's own style from the lore and the user's reference images: `lib/domini.js` holds the figures,
crown, sword, sigils and emblem, and `lib/heraldry.js` the guilloche, rays and flags.

`film.js` is a pure function of time, rendered frame-exact at 60 fps by the motion-reel renderer. It's timed in
beats on the grid measured from the song, and driven by per-frame envelopes (kick, snare, crash, loudness, vocal,
pitch) from the analyzer.

- Plan: `hero-federation/docs/shotlist.md`. Review log: `docs/critique.md`. Asset sheet: `assets/sheet.html`.
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
