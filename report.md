# Murders: a paper-theatre music video

**Deliverable:** `final/music-video.mp4`. It is 1920x1080, 30 fps, H.264 (High profile, yuv420p) with AAC audio, and runs 3:43 (223.0 s), the length of the song file. The soundtrack is the song file you gave me, Miracle Musical's "Murders", re-encoded to AAC with no edits, filters or level changes.

The project lives in `murders/`. The older `hero-federation/` project is still in the repo, untouched; I scrapped it as you asked but didn't delete it.

## What I made

It's a 3:43 story video done entirely in motion graphics: a **toy paper theatre at night**. No footage, photos or downloaded artwork are used; every figure, tree and prop is drawn by code.

- **The look.** Simon and the girl are paper-doll puppets held together with brass split pins. The forest is layers of cut paper with soft drop shadows that slide past each other in parallax. A grain pass makes it read as paper.
- **The witnesses.** Owls watch from the branches. Their eyes open as Simon passes, glow with the kick drum, and snap open on the song's biggest hits.
- **One colour.** Everything is midnight blue, sepia or paper-white except **the red ribbon**, which ties the story together.
- **Text.** The only words on screen are six act cards, the title and the song credit. There are **no lyrics on screen**.
- **The death.** It is implied, not shown: she lies among white paper flowers with her eyes closed. There is no violence or blood, and the video never shows who did it.

### The idea

I searched the web for what the song is about. Nothing I found is an official statement from the band, so the reading below is built from fan and critical interpretations:

- On *Hawaii: Part II*, a young man, Simon, finds his lover dead in a forest.
- In "Murders" he panics and explains himself at a rapid pace, as if he already knows he'll be blamed. He explains himself again in the second verse.
- One lyrics site reads the song's forests, mirrors and owls as images of presence and absence.
- The song ends on a quieter, regretful note.

So the video is about **being watched and being framed**. Owls are the witnesses. Hanging mirrors multiply his panicking face. Gilded picture frames slam shut around him ("framed"). An owl court judges him. Then the theatre itself is torn apart and he becomes a marionette on red threads. The ending is snow, memory and one last dance with her ghost, before the curtains close.

Sources (search results; see the caveat under "What I'm unsure about"):
- [Hawaii Part II: a review of the soundtrack](https://discoursewrites.substack.com/p/hawaii-part-ii-a-review-of-the-soundtrack) (Discourse Writes)
- [Murders by Miracle Musical lyrics analysis](https://songmeaningsandfacts.com/?p=148240) (Song Meanings and Facts)
- [Hidden in the Sand wiki](https://wiki.hiddeninthesand.com/TME)
- [The Mind Electric by Miracle Musical](https://www.madinamerica.com/2026/10/the-mind-electric-by-miracle-musical/) (Mad in America)
- Fan pages [dsism.carrd.co](https://dsism.carrd.co/) and [voac.carrd.co](https://voac.carrd.co/)

### The story, and what in the music drives each part

Times are seconds into the song. Every boundary is a measured time from the analysis, not a guess.

| time | music (measured) | what you see |
|---|---|---|
| 0–6.8 | intro; voice enters at 3.9 | Red curtains with the title. The curtains open and the camera pushes through the arch; Simon walks in with a lantern. |
| 6.8–20.1 | quiet verse | **I · The Ribbon.** Red ribbons tied on branches lead him on. Owls open their eyes as he passes, and their glow pulses with the kick drum. |
| 20.1–25.1 | dropout 20.1, impact 21.8 | The trail ends at a clearing of white flowers. On the impact we see her lying there, and he kneels. |
| 25.1–38.5 | loud verse; impact 30.1; bar line 33.5 | Panic. Mirrors drop on threads every two beats, each showing his frightened face; on 30.1 they ring him; he runs. |
| 38.5–58.5 | stop-start: dropouts 43.5 / 48.5 / 53.5; impacts 45.1 / 50.1 / 55.1 / 56.8 | **II · The Witnesses.** Each impact is a hard cut to an owl snapping its eyes open. Each dropout is darkness with only eyes and his lantern. |
| 58.5–68.5 | interlude, no vocal 61.8–65.1; impact 65.1 | A sepia memory: the two of them dancing in the clearing by day. On 65.1 it burns away from the edges back into night. |
| 68.5–83.5 | loud verse 2 | **III · The Search Party.** Villagers' lanterns sweep the forest while Simon hides. From 76.8, clues fly onto an evidence board (ribbon, lantern, footprint, feather, mirror shard), and red thread ties each one to his portrait. |
| 83.5–103.5 | stop-start, loud; impacts 88.5 / 93.5, dropouts 86.8 / 91.8 / 96.8; held note 102.6 | **IV · Framed.** Gilded frames slam around him on the impacts, nested deeper each time, and the dropouts leave one spotlight. Then a gallery of portraits, all of him; the last frame's glass cracks on the held note at 102.6. |
| 103.5–120.1 | bridge: strings and voice forward, 85 snare hits | **V · The Court of Owls.** A wigged owl judge and a jury of owls turning their heads together on every bar. The gavel strikes every second bar; each strike is within 15 ms of a measured snare hit, the last on the boundary at 120.1. |
| 120.1–141.8 | rock instrumental: guitars, cymbals and snare at their highest of the song; crashes; high held note 139.3–143.7 | **The Storm.** Paper lightning on the crashes, scraps flying, and the forest flats fall backwards to reveal blank paper. Red threads bind him; on the high held note he is lifted off the ground. |
| 141.8–160.1 | instrumental | Pull back: it was a toy theatre on a table all along, with Simon hanging from red threads like a marionette. Three owls watch from the top of the box. |
| 160.1–161.8 | dropout | Black, with paper scraps hanging in the air. |
| 161.8–181.8 | the quietest part, about −15 LUFS, strings | **VI · Snow.** The clearing under snow: owls asleep, flowers buried, Simon sitting where she lay. There is a close-up from 171.8 to 176.8. |
| 181.8–190.1 | soft vocal | He finds her ribbon in the snow, and her sepia ghost stands behind him. |
| 190.1–199.7 | final chorus: a +9.8 LU jump, the loudest bars of the song (up to about −5.6 LUFS) | The ribbon unfurls across the whole stage, every mirror now shows her face, and for one chorus they dance. |
| 199.7–211.8 | instrumental; impact 205.1 | The vision falls away. The moon swells and the owls take flight across it. |
| 211.8–221.0 | soft outro | Back in the theatre: Simon alone in the snow with the ribbon. The curtains close and the owl on the crest shuts its eyes. |
| 221.0–223.0 | silence | Credit: MURDERS · MIRACLE MUSICAL. |

## How I made it

### 1. Measuring the song

I used the song analyzer from earlier in this repo (`tools/song-analyzer/analyze.py`) on the whole file. Command and output are in `murders/analysis_run.log`; the results are in `murders/analysis/`, with an interactive view in `report.html`.

```
uv run tools/song-analyzer/analyze.py murders/audio/Murders.mp3 --out murders/analysis --start 0 --fps 30 \
  --cache --vocal-model models/UVR-MDX-NET-Voc_FT.onnx --stems murders/audio/stems --excerpt-wav murders/audio/song.wav
```

What it measured:

- **Beats and bars:** 144.0 BPM, 535 beats, 134 bars. The beat grid fits well up to about 150 s and drifts after that (see below).
- **Key and chords:** B minor, 113 chord segments.
- **Loud and quiet parts:**
  - The whole song is −10.4 LUFS integrated, with a loudness range of 7.3 LU.
  - The bars split into 29 quiet, 46 medium, 38 loud and 21 peak.
  - Quietest stretch: the 161.8–181.8 strings section (−15.4 LUFS).
  - Loudest: the final chorus from 190.1 (bars up to −5.6 LUFS) and the 120.1 storm (−7.1).
  - 20 dropouts and 19 impacts.
- **Structure:** 15 sections.
- **Drum hits:** 421 kicks, 617 snares and 83 crashes, with times.
- **Instruments:** presence of kick, snare, cymbals, bass, guitars, strings/synth and vocals, per bar and per section.
- **Vocals:**
  - A neural network (MDX-Net) separated the vocal stem.
  - From it the tool measured 96 phrases, 43 lines and 431 notes, a range of E♭2 to G5, and 8 held notes.
- **Per-frame envelopes:** kick, snare, loudness and so on at 30 fps (`cues.json`).

**Lyrics:** the analyzer does not transcribe words; it has no speech recognition. It gives the *timing* of every sung phrase and line and their pitch and intensity, but not the text. I didn't transcribe them myself either, since I can't hear the audio. So the video doesn't use the lyrics' wording; it uses the measured vocal timing (for example, the memory scene sits in the measured gap with no vocals at 61.8–65.1). The story comes from the web research.

### 2. Building the film

- `murders/film.js` (about 900 lines) is the whole film. Each frame is drawn on an HTML canvas as a pure function of time, so any frame can be rendered on its own.
  - It loads the analysis at start-up.
  - Scene boundaries are the measured section times.
  - Accents come from the measured events: impacts, dropouts, crashes, kicks, snares and held notes.
  - Light and glow follow the loudness envelope.
  - I used measured seconds rather than the beat grid wherever timing matters, because the grid drifts late in the song.
- `murders/lib/paper.js` is the drawing library I wrote for this video:
  - the paper-cut shapes with drop shadows, and the forest layers;
  - Simon and the girl as jointed puppets with poses;
  - owls (perched, judge, jury, flying), mirrors, frames, the proscenium with curtains and footlights, the evidence board, the bench, snow and flowers.
- `murders/docs/shotlist.md` is the plan. `murders/assets/sheet.png` is the character and asset sheet.
- Motion blur: each frame is the average of 4 sub-frames.
- **Fonts:**
  - Cinzel (titles and cards), under the SIL Open Font License; the licence is in `murders/fonts/OFL-Cinzel.txt`. I copied it from this repo's earlier project, which got it from the Google Fonts repository.
  - Inter, from the system's `fonts-inter` package, under the OFL; the licence is in `murders/fonts/LICENSE-Inter.txt`. The page template declares and preloads it, but no text in the video uses it.

### 3. Rendering and encoding

- `murders/tools/render_frames.mjs` renders the 6,690 frames (223.0 s × 30) with four headless Chromium pages working in parallel. It saves each frame straight from the canvas as a lossless PNG.
- ffmpeg then encodes the frames together with the original mp3 as the audio source (`murders/tools/encode.sh`):

```
ffmpeg -framerate 30 -i out/murders/frames/%05d.png -i murders/audio/Murders.mp3 -map 0:v -map 1:a \
  -c:v libx264 -preset slow -crf 18 -profile:v high -pix_fmt yuv420p -vf scale=out_color_matrix=bt709:out_range=tv \
  -colorspace bt709 -color_primaries bt709 -color_trc bt709 -c:a aac -b:a 320k -movflags +faststart final/music-video.mp4
```

Every tool used was already installed: Node with Playwright and Chromium, ffmpeg, Python with uv, and the system fonts. No footage or artwork was downloaded, and no new software was installed for this video. The analyzer's Python packages and the vocal-separation model came from the local cache set up for the earlier project. uv did refresh its package index from PyPI when it started the scripts.

## What I checked

All of these ran on the delivered `final/music-video.mp4` with `murders/tools/verify.py`. The full output is reproduced by running `uv run murders/tools/verify.py final/music-video.mp4 murders/audio/Murders.mp3 murders/analysis/analysis.json`.

- **Format.**
  - Video: H.264 High profile, 1920x1080, 30 fps (constant), yuv420p, tagged BT.709. It is converted with the BT.709 matrix, and a colour spot check came back within one level of the rendered frame.
  - Audio: AAC-LC at 44.1 kHz stereo, about 303 kb/s.
  - Both streams start at 0.000 s. The file is 182 MB.
- **Length.** The video is 6,690 frames, which is 223.000 s. The audio is 222.991 s, which is exactly what the song file decodes to. The song's container reports 223.033 s because it includes the mp3's 0.025 s encoder delay, which decoders drop. The video is 9 ms longer than the audio, which is less than one frame; that is the closest a 30 fps video can get.
- **Plays to the end.** I ran a full decode of every video and audio packet with ffmpeg: no errors, and all 6,690 frames were read. I extracted the last frame (`murders/review/last-frame.png`); it is the end credit fading out, as intended. I also built a contact sheet decoded from the final mp4 (`murders/review/contact/final-mp4.jpg`) to confirm the encoded picture matches the render.
- **Music in sync with the song file.**
  - I decoded the video's audio with its timestamps honoured and cross-correlated it against a decode of your mp3 in 4-second windows at 5, 20, 45, 60, 90, 120, 150, 180, 200 and 215 s.
  - The offset is **0 samples at every window**, with correlation 0.9999–1.0000. AAC is lossy, so it isn't exactly 1.
  - The video's decoded audio runs 13 ms longer at the very end. That is the AAC encoder's padding (see below), not a shift.
  - The analysis was made from a decode that I had already checked lines up sample for sample with ffmpeg's decode of the mp3 (offset 0, correlation 1.0000). So the measured times in the film are times in your song file.
- **Picture on the music.**
  - I found the 25 biggest hard cuts in the delivered video and compared each to the measured events. **All 25 land within one frame** of one: 21 within 9 ms, the rest within 28 ms. The events are section starts, impacts, dropouts, crashes, bar lines and the start of the final silence.
  - The first version of this check found one cut 0.34 s ahead of its bar (the portrait gallery at 98.1 s). I moved it onto the bar line at 98.47 s, re-rendered that stretch and re-encoded.
- **No accidental flashes.** `murders/tools/flashcheck.py` scanned all 6,690 frames for 1–3 frame blips that jump away and back. It found two, and both are lightning strikes landing exactly on measured crashes (120.538 s and 126.368 s), which is intended.

I also reviewed the picture as still frames; I can look at stills but can't watch the video in motion. I checked contact sheets of the whole film (one frame every 2.5 s) and close-ups of individual shots, and fixed what I found:

- the girl's ribbon crossing her face;
- the clearing and the search party being too dark, with figures too small (I added push-ins and lifted the light);
- the snow close-up being off-centre;
- the paper forest layers showing a hard edge against the big moon;
- the flying owls reading as bats (I redrew them with round heads, gold eyes and rounded feathers);
- a two-frame flash of the forest just before three of the owl close-ups (45.1, 50.1 and 55.1 s). The darkness after each dropout ended 2 frames before the next impact; it now holds until the impact. I found this one by looking at consecutive frames, then wrote `murders/tools/flashcheck.py` to scan the whole film for similar blips (result above).

The contact sheets are in `murders/review/contact/` (`sheet0–2.jpg`); the other review stills stay local.

## What I'm unsure about

- **I can't hear the audio.** Everything about the music comes from the analyzer's measurements, not from listening. So I can't vouch for how the cuts *feel* against the song, only that they land on the measured times.
- **I haven't watched the video in motion.** I've only seen still frames, so judgements about pacing and smoothness are inferred from those and from the code.
- **The meaning of the song.** My reading rests on short search-result summaries of fan and critical interpretations. When I tried to open the pages themselves, the fetches failed (the hosts didn't resolve), so I couldn't read them in full. Nothing official from the band confirms the story; the theatre staging, owls, mirrors, frames and court are my own interpretation.
- **No lyrics.** As explained above, the words weren't transcribed, so no part of the video illustrates specific lines. If you give me a lyric sheet, the analyzer can align it to the measured phrases (`--lyrics`).
- **Tempo after about 150 s.** The 144 BPM grid matches the drums well (about 18 ms typical error) for most of the song but drifts by up to about 100 ms around 160 s. I timed the late scenes to measured events, not to the grid, so this shouldn't show.
- **Instrument labels are estimates.** The analyzer tells instruments apart by frequency band and rhythm, not by recognising them, so "guitars" versus "strings/synth" is approximate. One review mentions a piano at the end; the analyzer has no piano class and files it under strings/synth.
- **Section names** such as "verse/bridge" are the analyzer's generic labels. The boundaries are measured, but which part is a verse or a chorus is my reading of loudness and vocal activity.
- **Encoder padding.** Like every AAC file, the audio track ends with a few milliseconds of encoder padding. The MP4 marks the real length (222.991 s), and players trim to it. A decoder that ignores that mark, as ffmpeg does in the sync check above, plays about 13 ms of extra silence at the very end. The music itself is unchanged and starts at exactly 0.
- **AAC is lossy.** The spec asked for AAC, so the audio is a re-encode of your mp3 at 320 kb/s rather than a bit-for-bit copy. The timing and content are unchanged, and the correlation against the original is 0.9999–1.0000. But it is technically a second lossy generation; at that bitrate I'd expect the difference to be inaudible, though I can't confirm that by ear.
