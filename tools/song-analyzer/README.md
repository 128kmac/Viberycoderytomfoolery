# song-analyzer

Measures a song so a music video can be cut against it: beat grid, tune, loud and quiet sections,
structure, drums, instrument layers and the vocal line. It outputs data files, per-frame animation
cues and an interactive HTML timeline.

```bash
uv run tools/song-analyzer/analyze.py SONG.mp3 --out OUT_DIR --start 1:57 \
    [--end 3:06] [--fps 60] [--vocal-model UVR-MDX-NET-Voc_FT.onnx] [--stems DIR] \
    [--excerpt-wav OUT_DIR/excerpt.wav] [--audio-src ../audio/excerpt.wav] [--lyrics my_lines.txt] [--cache]
```

`uv` installs the dependencies (librosa, numpy, scipy, soundfile, scikit-learn, onnxruntime) from the
script header. No torch is needed.

## What it measures

| | how |
|---|---|
| **Beat** | Drum onsets are measured as dB rises in the percussive layer: the kick in 35–120 Hz, the snare where the 160–320 Hz body and 1.5–5 kHz crack rise together. Tempo comes from phase coherence of those onsets on the **8th-note grid**, where on-beats and syncopated off-beats both line up. The beat phase comes from the snare backbeat, and bars from kick-on-1 / snare-on-2-and-4 / harmonic change, checked in sliding 8-bar windows. Per-window drift is reported, and if the band strays from a click it falls back to tracked beats. |
| **Tune** | Key from Krumhansl–Kessler profiles on harmonic CQT chroma. Chords per beat (major / minor / power) by template matching plus Viterbi smoothing, with roman numerals. Vocal melody as notes (pYIN). |
| **Loud / quiet** | BS.1770 K-weighted momentary (400 ms) and short-term (3 s) loudness, integrated loudness and LRA. Each bar is classed quiet / medium / loud / peak. Events: **impacts** (loudness or band jumps), **dropouts** (the band or the level falls away), **builds**, **stops**, crashes. |
| **Structure** | Foote novelty on beat-synchronous chroma + MFCC + loudness + vocal presence, snapped to bars, clustered into repeats (A/B/C…) and given heuristic names. |
| **Vocals** | Best with `--vocal-model`: a pre-trained MDX-Net network separates the vocal stem, then phrases (breath gaps of 12 dB+ under the running peak), lines, syllable onsets, pitch range, intensity and held notes are measured. Without the model a DSP estimate is used (centre-panning mask + REPET-SIM), which is much weaker on dense rock mixes. **Words are not transcribed.** If you supply your own lyric sheet (`--lyrics`, one sung line per line), it is aligned to the detected phrases by syllable count. |
| **Instruments** | Per-bar presence of kick, snare, cymbals, bass, wide distorted guitars, a clean sustained layer (strings / synth / keys) and vocals. These are measured on the instrumental when a vocal stem exists. They are DSP estimates, so treat the guitar vs. strings split as approximate. |

## Outputs (in `--out`)

- `analysis.json`: the whole song in absolute song time (beats, downbeats, bars with dynamics,
  presence and chords, sections, drum hits, vocal phrases / lines / notes, events, loudness curves).
- `excerpt.json`: the same, cut to `--start`/`--end`, with times relative to the start.
- `cues.json`: per-video-frame envelopes (0..1) for animation: `loud`, `loud_st`, `kick`, `snare`,
  `crash`, `bright`, `vocal`, `bass`, `guitars`, `strings_synth`, `cymbals`, `pitch` (−1 when nobody sings).
  Precomputed, so a frame-exact renderer stays a pure function of time.
- `beats.json`: the grid in the motion-reel format (u = 0 on the first downbeat of the excerpt).
- `report.html`: an interactive timeline. Hover for values, click to seek. It plays audio if `--audio-src` is given.

`--excerpt-wav` writes the excerpt decoded by the same decoder the analysis used, so audio and analysis
stay sample-exact (mp3 encoder delay included).

## The vocal model

Download `UVR-MDX-NET-Voc_FT.onnx` (66 MB) from the public UVR model repository:
`https://github.com/TRvlvr/model_repo/releases/download/all_public_uvr_models/UVR-MDX-NET-Voc_FT.onnx`.
`separate.py` runs it with onnxruntime (STFT 7680 / hop 1024, 3072 bins, 256-frame chunks, with
sign-symmetric denoising). A 3-minute song takes about 4 minutes on 4 CPU cores. `--cache` keeps the
stem in `OUT_DIR/.vocal_stem.npy` so re-runs are quick.

## Results on "Hero" (1:57 to the end)

142.0 BPM, constant (8-second windows stay within ±10 ms, rms 3.3 ms). Key E♭ minor. −6.0 LUFS
integrated, LRA 2.5 LU (a very compressed master). In the excerpt: the bridge runs from 0.54 s; a
dropout at 27.6 s; an impact at 29.3 s; a band-out bar at 32.7 s; the final chorus lands at 34.3 s;
belted peaks at about 42–47 s (up to F♯5) and at 57.7–59.9 s (E5, over a dropout); the last hit is at
64.8 s and the music ends at about 66.3 s.
