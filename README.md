# Viberycoderytomfoolery

## MURDERS: a paper theatre (`murders/`)

A 3:43 motion-graphics music video for Miracle Musical's "Murders" (the whole song, audio unchanged). Simon finds
the girl he loves dead in a night forest, and the owls, the mirrors and the town all decide he did it. It's staged as
a cut-paper toy theatre: paper-doll puppets on brass split pins, layered paper forests, owls as witnesses, gilded
frames, an owl court, a storm that tears the theatre apart, and snow. The red ribbon is the only colour that is never
paper-pale. No lyrics appear on screen, and every figure is an original drawing in code.

- What was made, how, what was checked and what's uncertain: `report.md`. Plan: `murders/docs/shotlist.md`.
- `film.js` is a pure function of time, timed to measured section times and events from `murders/analysis/`, drawn
  with `lib/paper.js`.
- Render: `node murders/tools/render_frames.mjs` (PNG frames to `out/murders/frames`), then the ffmpeg command in
  `report.md`. Check: `uv run murders/tools/verify.py final/music-video.mp4 murders/audio/Murders.mp3`.
- Preview: serve the repo root and open `murders/index.html` (space plays it, click to scrub). The song file and the
  video aren't committed: put the mp3 at `murders/audio/Murders.mp3`, re-run the analyzer (command in `report.md`),
  and copy `murders/audio/song.wav` to `murders/audio/music.wav`, which is the file the preview player plays.

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
