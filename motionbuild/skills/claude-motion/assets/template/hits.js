// Single source of truth for sync. Every accent on screen gets a row here;
// film.js reads it for picture, sfx.mjs reads it for sound.
// [beat, label, sfx ('a+b' layers, or null for silent), opts]
// opts: gain, pan (-1..1), pitch (Hz or 'D6'), to, from, len (s), anchor (start|peak|end), verb, n, spread
// Run `node <skill>/scripts/sfx.mjs --list` for the palette.
export const HITS = [
  [0, 'word 1 (frame 0 is already moving)', 'pop+sub', { pitch: 'A5' }],
  [1, 'word 2', 'pop', { pitch: 'C#6' }],
  [2, 'word 3', 'pop', { pitch: 'E6' }],
  [8, 'riser into scene 2 (ends on the cut)', 'riser', { len: 1.6, gain: 0.5 }],
  [8, 'scene 2: product card lands', 'impact'],
  [12, 'feature 1', 'tick+blip', { pan: -0.3, gain: 0.35 }],
  [14, 'feature 2', 'tick+blip', { pan: 0, pitch: 'E6', gain: 0.35 }],
  [16, 'feature 3', 'tick+blip', { pan: 0.3, pitch: 'A6', gain: 0.35 }],
  [20, 'card push-in', 'whoosh', { pan: 0.25, gain: 0.8 }],
  [24, 'swell into end card (ends on the cut)', 'swell', { len: 1.0, gain: 0.5 }],
  [24, 'end card', 'impact'],
  [25, 'url types on', 'type', { n: 10, len: 0.6 }],
];
