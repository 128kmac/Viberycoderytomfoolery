# EB: Proxima

A Roblox arena fighter built from the **EB: Proxima Complete Ability Compendium**: an Elemental
Battlegrounds-style fangame. All **100 powers** are playable, each with a passive, four moves with
**P60** upgrades, an ultimate and its **unstable** variant. They all run on one server-authoritative
combat engine with 1000 health, Energy, Heat, Proxima, Guard, Dodge, shields, heal caps, the control
budget, Rupture and Burnout.

You fight in the **Proxima Observatory**, a floating observatory under a red-dwarf star. There is a
practice annex, full matches against bots or friends, and client-rendered elemental effects with
procedural animation and layered sound.

## Play it

**Option A: the place file (no tools needed)**

1. Download `EBProxima.rbxlx`.
2. In Roblox Studio, choose **File → Open from File…** and open it.
3. Press **Play**. For multiplayer, use **Test → Clients and Servers**.

**Option B: Rojo**

```
rojo serve                   # connect from the Rojo Studio plugin
rojo build -o EBProxima.rbxlx
```

To rebuild the place file without Rojo, run `python3 tools/build_place.py`. The place file sets
`Lighting.Technology = Future`, which scripts can't set at runtime.

## How a session flows

1. **Training Annex (practice).** You spawn on the range south of the island, with dummies at 5, 8,
   11 and 15 m. Press **TAB** to pick a power. Press **P** for the panel: dummy behaviour
   (Idle / Guard / Strafe / Shoot), free cast, fill Proxima and Heat to try ultimates, and add a
   sparring bot. You can also walk across the bridge and explore the arena.
2. **Start Match** (P → Match). Choose bots (0–7), difficulty (Easy / Normal / Hard), KOs to win,
   time limit, and Teams (Sun vs Moon) or free-for-all.
3. **Countdown.** Everyone is placed in a spawn alcove and frozen for 3-2-1, then **FIGHT**.
4. **Fight.** First to N knockouts wins, or the most KOs when time runs out. KOs credit the last
   damager. You respawn after 4 s with 2.5 s of spawn protection, which ends early if you cast.
5. **Results.** Standings (KOs, deaths, damage, best hit), MVP, then **Rematch** or **Return to
   Practice**. With no input, it returns to practice after 15 s.

## Controls

| Action | Keyboard / mouse | Gamepad |
|---|---|---|
| Move / jump | WASD / Space | Left stick / A |
| Aim | Mouse (crosshair is camera-locked) | Right stick |
| Basic attack (hold to chain) | Left mouse | R2 |
| Guard (tap just before a hit = **Perfect Guard**) | Right mouse | L2 |
| Dodge (2 charges, brief invulnerability) | Shift | L1 |
| Moves 1–4 | Q E R F (or 1–4) | X / Y / B / D-up |
| Ultimate (100 Proxima; **hold** at 60+ Heat for Unstable) | G (or 5) | R1 |
| Move modifier (alternate version) | hold Ctrl while casting | L3 |
| Kit action | V | R3 |
| Powers menu / match & settings panel | TAB / P | Select / Start |
| Free cursor · swap shoulder · zoom | Z · C · mouse wheel | — |

On touch devices, on-screen buttons appear. Drag the right half of the screen to look around.

## The arena: Proxima Observatory

- **Central Orrery Plaza.** A raised dais with a ring of cover walls (open on the diagonals) around
  the Orrery pillar and its burning core. Orbital rings turn slowly overhead; they are decorative
  and don't block anything.
- **Ember Forge (NE).** Open-roofed forge halls, narrow alleys, anvils, and a lava trench under
  walkable grating. Close-range space.
- **Tidal Cistern (SE).** A wading pool with arches. A raised rim walkway and two bridges give you
  a high path above the low one.
- **Verdant Terraces (SW).** Three stepped levels (ramps, plus 4-stud lips you can jump),
  hedge-line cover and the great tree.
- **Storm Spire (NW).** A 10-stud platform with tesla coils, reached by a ramp or a jump route.
  The **Gale Bridge** runs from it over the north avenue and comes down near the Forge.
- **Avenues and outer ring.** Colonnades and mid-avenue walls break up the four long sightlines,
  and the ring walkway gives you flanking routes. Eight recessed **spawn alcoves** have front
  cover (Sun team: south half, Moon team: north half).
- **Boundaries.** A balustrade plus an invisible barrier, with out-of-bounds recovery as a backstop.

The visual rules are strict. Anything solid at body height collides and stops shots; purely
decorative pieces (rings, banners, canopy, distant isles) never collide or block. Each district
has its own floor, materials and accent colour for wayfinding. Environmental motion is client-side
and restrained: rings turn, banners and canopy sway, lanterns bob, firelight flickers, tesla
coils arc now and then.

## Powers and presentation

Every power belongs to one of ten **element families**: flame, frost, storm, tide, gale, stone,
gravity, radiant, verdant and eldritch. The family sets how its effects look and move:

- projectile body shape and motion
- materials, particles and light
- impact type (blast, shatter, arc, splash, gust, quake, implode, flare, bloom, glyph)
- sound set

Each power's own colours tint its family's effects. Impacts are layered by result. A body hit,
a guarded hit, a **Perfect Guard**, a shield absorb, an evade, a heal, damage-over-time ticks,
terrain hits and out-of-range fizzles all look and sound different.

**Showcase powers (★ in the powers menu)** have bespoke choreography for every move:
Fire, Ice, Electric, Gravity, Water, Wind, Earth and Light. Their ultimates are staged as
buildup → escalation → climax → release, synced to the server's actual damage moments. The
signature is Gravity's **The Falling Kingdom**: the floor inside the field tears loose and a
black crown with lensing rings forms overhead. The debris rises and hangs trembling, then
slams down twice. Finally the crown implodes.

The other 92 powers use their family's full effect language. Their gameplay is complete; they
just don't have per-move bespoke choreography.

**Animation** is procedural, for every fighter. It covers:

- idle stance and breathing
- a directional run cycle with foot plants
- jump, fall and landing squash
- guard pose
- cast anticipation → release (the casting hand reaches the same point the server spawns
  projectiles from) → follow-through → recovery
- alternating basic-attack jabs and dash lean
- hit flinches, death collapse with a dissolve, and the spawn rise

**Readability.** Hostile warnings use spiked, pulsing outlines that fill up until impact. Allied
warnings are thin dashed outlines, and your own are thin solid lines. Warnings always show the
exact affected shape. Enemy nameplates show **✕** and a notched bar; allies show **◆**.

## Settings (P → Settings)

- **Volumes:** master, effects, ambience and interface, each separate. *No music is included.*
- **Effect quality:** Low / Medium / High. Controls particle density, lights and the effect budget.
- **Reduced flashing:** caps flashes, tints and screen grading, and stops strobing arcs.
- **Reduced motion:** turns off camera shake, kicks and FOV pulses, and stills environmental sway.
- **Camera:** shake scale, sensitivity and field of view. Damage numbers can be toggled.

## Architecture (src/)

- `server/Core`
  - `S` registry
  - `Fighter`, `Combat`, `Status`, `Cast`: the rules engine
  - `Hit` for geometry
  - `Proj`, `Zones`, `Objects`, `Summons`
  - `K`: the kit helper library
  - `FX`: visual cues
  - `Match`: match flow
  - `Bots`: AI, with `Nav` (auto-built nav graph + A*) and `Danger` (telegraph registry)
  - `Arena`: the level
- `server/Kits`: the 100 power implementations.
- `shared`
  - `Config`: rules values
  - `KitData`: generated from the compendium
  - `Styles`: the element families
  - `Poses`: shared hand emission points
- `client`
  - `VFX/` (core, family renderers, showcase choreography)
  - `Animator`, `CameraRig`, `Audio`, `Ambient`, `Nameplates`
  - `HUD`, `MatchUI`, `KitMenu`, `Controls`, `Settings`

The server sends what happened as batched **cues** carrying element context. Each client
decides how it looks. Projectiles are simulated on the server and rendered and extrapolated on
clients, with corrections.

## Testing (tools/sim): what was and wasn't verified

No Roblox Studio was available while building this. Instead, `tools/sim` contains a headless
harness:

- a Luau → Lua 5.4 transpiler
- a Roblox API emulator: typed instances, signals, a scheduler, simplified humanoid physics,
  raycasts and overlaps, GUI layout, client/server peers with simulated latency
- a three.js renderer for scenes and a PIL renderer for GUI snapshots

The test suites run the real game scripts:

| Suite | Checks |
|---|---|
| `tests/test_kits_smoke.py` | every power: all moves (normal, P60, modifier), recasts, kit action, ultimate and unstable ultimate, with errors and damage reported |
| `tests/test_match.py` | practice → countdown freeze → fight → KOs → results → rematch ×3 → practice; respawn; flat instance counts |
| `tests/test_player.py` | real input events → casting, damage, effects, sounds, basic attacks, guard, dodge, jump, death, respawn |
| `tests/test_bots.py` | nav graph, A*, telegraph escape, bots-only match statistics |
| `tests/test_arena.py` | reachability of every area, spawn safety, hidden collision, cover vs decoration, edge containment, spire climb |
| `tests/test_showcase.py` | the 8 showcase powers incl. ultimates: no errors, effects fully cleaned up |
| `tests/test_stress.py` | 8 fighters with overlapping ultimates: effect, voice and Highlight budgets; cleanup across matches |
| `tests/test_pacing.py` | bot duels: time-to-kill and ultimates per minute |
| `tests/snap_hud.py`, `tests/snap_poses.py`, `render_scene.py` | visual snapshots (HUD at 4 screen sizes, poses, arena, effects) |

**Not verifiable here:**

- How the game actually renders, animates and sounds inside the Roblox client.
- Real network latency and ownership behaviour.
- Physics feel.
- Performance on real devices.

The emulator approximates Roblox, so treat it as strong evidence, not proof. Run a Studio
playtest before publishing.

## Known limitations and deviations

- **Pacing tune.** Proxima decay is softer than the compendium (contest window 6 s instead of 4,
  decay grace 5 s instead of 3, decay rate 3/s instead of 6) so sustained fights reliably reach
  ultimates. The original values are noted in `shared/Config.luau`.
- **Audio uses placeholders.** All sound comes from Roblox's built-in engine samples, layered and
  pitch-shifted per family. Swap the entries in `client/Audio.luau` for real assets. There is no
  music.
- **Built-in textures.** Particle textures use built-in `rbxasset://textures/particles/...`
  paths. If one is missing in a given client, those particles simply don't draw.
- **Character appearance.** Player avatars load through `GetHumanoidDescriptionFromUserId`. Bots
  and failed loads get a stylised body tinted by their power.
- **Non-showcase powers** use family visuals rather than bespoke per-move choreography.
- **Damage table caveat.** The smoke test places targets at a fixed fraction of each move's range,
  so 0-damage entries in its report often reflect placement, not bugs. Self-buffs, forms and
  traps legitimately deal no direct damage.
