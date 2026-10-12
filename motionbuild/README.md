# motionbuild — the `claude-motion` skill

A from-scratch rebuild of the Claude motion-graphics skill: Claude makes product reels, launch films, explainers and social cuts **as code**. A film is a canvas drawing that is a pure function of time. It is rendered frame-exact to H.264, scored with synthesized music and beat-locked SFX, mastered to −14 LUFS, and delivered in 16:9, 9:16 and 1:1.

```
motionbuild/
├── .claude-plugin/{plugin.json, marketplace.json}
└── skills/claude-motion/
    ├── SKILL.md                     the workflow Claude follows
    ├── references/                  motion-api · shotlist · style-guide · audio · voiceover · critique
    ├── assets/lib/motion.js         browser runtime (format, grid, easing, springs, type, images, blur, preview)
    ├── assets/template/             index.html · film.js · hits.js
    └── scripts/                     Node-only pipeline (no Python)
        ├── scaffold.mjs   new film + toolchain check
        ├── gather.mjs     real screenshots, logo, fonts, colours, copy from a URL
        ├── reference.mjs  cut detection + contact sheets of a style reference
        ├── score.mjs      synthesized score with an exact beat grid (pulse · minimal · lofi · cinematic)
        ├── beats.mjs      beat grid + downbeat-aligned excerpt from a supplied track
        ├── render.mjs     frame-exact renderer (video, contact sheets, strips, stills, posters)
        ├── sfx.mjs        18-sound synthesized SFX palette driven by hits.js
        ├── mix.mjs        stems → −14 LUFS / −1 dBTP master → muxed finals
        ├── sync.mjs       measures every hit's audio vs picture offset
        ├── check.mjs      delivery gate (codec, size, fps, colour, loudness, faststart)
        ├── lipsync.mjs    mouth data from a voice-over (+ Rhubarb visemes if installed)
        └── preview.mjs    local preview server
```

## Install

**As a plugin:**
```bash
claude plugin marketplace add ./motionbuild      # or <owner>/<repo> once pushed
claude plugin install claude-motion@motionbuild
```

**As a bare skill:** copy or symlink `skills/claude-motion` to `~/.claude/skills/claude-motion` (personal) or `.claude/skills/claude-motion` (project).

**Requirements:** Node 18+, ffmpeg + ffprobe on PATH, and Playwright Chromium in the project you make films in (`npm i -D playwright && npx playwright install chromium`). Nothing else: no Python, no API keys.

## Use

Ask Claude for a video: *"make a 15 s launch reel for https://example.com, 16:9 and 9:16"*. The skill:
1. gathers real assets;
2. reads an optional style reference;
3. builds the beat grid;
4. writes a shot list for you to approve;
5. builds the film;
6. runs at least 3 critique rounds on contact sheets;
7. renders, mixes and checks;
8. delivers `out/<film>/final.mp4` and the other formats.

Manual pipeline, run from your project folder:
```bash
S=path/to/motionbuild/skills/claude-motion
node $S/scripts/scaffold.mjs launch --title "Acme" --formats 16x9,9x16
node $S/scripts/gather.mjs https://acme.com launch
node $S/scripts/score.mjs launch --flavor pulse
# edit launch/film.js + launch/hits.js, then:
node $S/scripts/render.mjs launch --contact --all-formats
node $S/scripts/render.mjs launch --all-formats
node $S/scripts/sfx.mjs launch && node $S/scripts/mix.mjs launch
node $S/scripts/sync.mjs launch && node $S/scripts/check.mjs launch
```

## What changed from the previous motion skill

This is a clean-room rebuild. The pipeline came from three research passes: the previous skill's workflow, its code, and current practice in Remotion, HyperFrames, timecut, EBU R128 and Rhubarb.

| | before | now |
|---|---|---|
| Runtime | Node + Python (uv, librosa, scipy, matplotlib) | **Node only** |
| Frame capture | full-page PNG screenshot per frame, written to disk | canvas PNG via `window.capture`, **piped straight into ffmpeg** |
| Motion blur | 8-bit running average (bands), every frame | exact integer accumulation; **static frames skip blur** |
| Synth grid | measured back from the audio | **exact by construction** |
| Hit list | read by launching a browser | `hits.js` is plain data shared by browser and Node |
| Loudness | parse bug on `-inf`; sample-peak ceiling | fixed; 4× oversampled limiter at tp − 0.5 dB, verified on the encoded file |
| Sync check | Python + plot | `sync.mjs`, about 3 ms accuracy, plus a buried-SFX check |
| Delivery gate | manual ffprobe | `check.mjs` (codec, size, fps, yuv420p, bt709, duration, loudness, faststart, decoded frame) |
| gather | aborts on networkidle timeout; 16k px crash | tolerant; clipped full pages; proxy-aware; **warns when stylesheets fail** |
| Alpha | negative `globalAlpha` from spring overshoot silently ignored | clamped in helpers + `M.alpha()` |

Verified end to end in this repo's sandbox: the template film rendered for 15 s at 60 fps in 16:9, 9:16 and 1:1, taking about 4 min on 4 CPU cores.
- All 12 hits landed within 20 ms of the picture.
- The master measured −14.1 LUFS and −1.5 dBTP.
- Every delivery check passed.

`examples/` holds the 16:9 and 9:16 finals, the contact sheet and a 1:1 poster from that run. They're the bare template; a real film replaces its copy, colours and scenes.
