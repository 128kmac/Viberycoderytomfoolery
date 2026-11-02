# EB: Proxima

A Roblox arena fighting game: an Elemental Battlegrounds fangame built from the
**EB: Proxima Complete Ability Compendium**. All **100 powers** are implemented. Each one has
its passive, four normal moves with their **P60** enhancements, an ultimate, and the
ultimate's **unstable mutation**. They all run on one shared combat engine that follows the
compendium's rules: 1000 health, Energy, Heat, Proxima, Guard, Dodge, shields, healing caps,
the control budget, Rupture and Burnout.

## Play it

**Option A — open the place file (no tools needed)**

1. Download `EBProxima.rbxlx` from this repository.
2. In Roblox Studio choose **File → Open from File…** and pick it.
3. Press **Play** (or **Start** with several players under *Test → Clients and Servers*).

**Option B — Rojo**

```
rojo serve            # then connect from the Rojo Studio plugin
rojo build -o EBProxima.rbxlx
```

`default.project.json` maps `src/` into the DataModel the same way as Option A.
To rebuild the place file without Rojo, run `python3 tools/build_place.py`.

> To publish: open the place in Studio, then **File → Publish to Roblox**. The game is server-authoritative
> and needs no API services, DataStores or external assets.

## Controls

| Action | Keyboard / mouse | Gamepad | Touch |
|---|---|---|---|
| Moves 1–4 | **Q E R F** (or 1–4) | X / Y / B / D-pad up | on-screen 1–4 |
| Ultimate | **G** (or 5). At 60+ Heat, **hold 1 s** for the Unstable mutation; release early for the normal ultimate | R1 | ULT |
| Basic attack | Left mouse (hold to repeat) | R2 | Hit |
| Guard | Right mouse (hold) | L2 | Guard |
| Dodge | Left Shift (in the movement direction) | L1 | Dodge |
| Optional-spend modifier | hold **Left Ctrl** while casting | L3 | Mod |
| Kit action (reagent, companion, bond…) | **V** | R3 | Kit |
| Power compendium / settings | **Tab** or **M** | Select | — |
| Toggle aim camera | **Z** or Left Alt | — | — |

- **Recasts:** many moves open a recast window. The slot glows green; press the same key again.
- **Hold moves:** charged shots (Kinetic Pellet, Ion Needle, Pinpoint Round…) fire on key release.
- The modifier key picks a move's optional mode where the compendium offers one, for example
  spending Stride, Ember, Coins, Creases, Flow or Ticks, or choosing a P60 option.

## The compendium menu (Tab)

- Browse and search all 100 powers: identity, passive, every move's stat line, P60, counterplay,
  unstable mutation, mutation rules, sequence and team interactions.
- **Equip selected power.** It swaps immediately when you're out of combat, otherwise on respawn.
- **Synergy Mode** toggle, **Teams** toggle (Sun vs Moon, otherwise free-for-all), **Bots −/+**
  (up to 8 AI fighters) and **Spawn bot with it**, which spawns a bot using the selected power.
- A training lane of four dummies sits at the arena edge. They count as real opponents for Proxima
  so you can practise P60 and ultimates alone.

## HUD

Health with a shield overlay, Energy, Guard, Proxima (60 and 100 markers), Heat (60 unstable and 70
stress markers), dodge pips, Burnout/Rupture/CC-immune state, a cast bar, and five ability slots.
Each slot shows its cooldown sweep, Energy cost, a **P60** badge, recast timers and ultimate
readiness. Hovering a slot (with the aim camera off) shows the full move text. Each kit's own
resources (Stride, Reagent, Marrow, Coins, Phase…) appear above the bars. Every fighter's nameplate
shows health, shield, kit and active statuses.

## Combat rules implemented (from the compendium)

- 1000 health; Energy 100 regenerating 12/s after 1.25 s; run speed 6 m/s; 2 m jump (1 m = 3 studs).
- Basic attack: 2.5 m, 60 damage, every 0.65 s. Dodge: 2 charges, 5 m over 0.3 s, 0.12 s invulnerability, 5 s sequential recharge.
- Guard: 100, a 120° frontal arc, 70% reduction, drain 4/s plus 20% of blocked damage, break at 0 (0.7 s), recovery 20/s.
  A perfect guard within 0.2 s gives 90% reduction and +5 Proxima. Guard plus damage reduction is capped at 85%.
- Commitment rules: costs and cooldown are paid at windup start, interruption keeps the cooldown, default 0.35 s / 0.25 s recovery,
  and an ultimate interrupted before its first effect refunds 50 P and half its Energy with a 20 s cooldown.
- **Proxima:** contested proximity (+2/s within 12 m, +4/s within 6 m), +3 for the first ability hit per cast,
  +5 on perfect guard, +3 for supporting a contesting ally, capped at 10/s. Decays 6/s after 3 s without a contest.
- **P60:** a cast committed at 60+ Proxima gets its P60 property and +6 Heat.
- **Heat:** cools 8/s after 1.25 s. At 100, **Rupture** is queued: when the current action or ultimate form ends,
  Proxima resets to 0 and you get 3 s of **Burnout** (no abilities), ending at 40 Heat. **Unstable** ultimates cost an extra 40 Heat.
- Shields: 400 cap, earliest-expiring consumed first, same-name shields replace rather than stack.
  Healing is capped at 250 per rolling second. Constructs have durability and up to two reinforcement layers (100 max).
- Control budget: stun, root, sleep, lift and guard-break share 2 s per rolling 6 s, then grant 2 s of visible immunity.
  Slows use only the strongest (max 40%); speed bonuses add up to +25%.
- Projectiles default to 24 m/s and 0.3 m wide, stop at the first solid collision, and can be reflected only once.
- Out of bounds returns you to your last legal ground position with a 150 penalty and a 1 s lock.

## Project layout

```
src/shared/            ReplicatedStorage.Shared
  Config.luau          every numeric rule above
  KitIndex.luau        roster (auto-generated)
  KitData/*.luau       all compendium text and stat lines per power (auto-generated)
src/server/            ServerScriptService.Server
  Main.server.luau     bootstrap, remotes, main tick
  Core/                engine: S (registry), Combat, Status, Cast, Fighter, Hit, Proj, Zones,
                       Objects, Summons, FX, K (kit API), Arena, Match, Bots
  Kits/*.luau          one behaviour module per power (100 files)
src/client/            StarterPlayerScripts.Client: Controls, HUD, KitMenu, Popups, Theme
src/character/         StarterCharacterScripts (disables default health regen)
tools/                 checkers, generators, place builder
```

### Writing or tuning a power

Each `src/server/Kits/<Power>.luau` returns a table:

```lua
local Kit = { passive = { init = fn, tick = fn, dealt = fn, beforeTake = fn, ... } }
Kit.requires = { [4] = function(c) return ok, reason end }   -- invalid target = no cost
Kit[1] = function(c) ... end   -- c.p60, c.unstable, c.mod, c:dir(), c:aimPoint(m), c:target(m), c:recast(...)
...
Kit[5] = function(c) ... end   -- the ultimate; c.unstable selects the mutation
return Kit
```

Moves are written with the metre-based `K` toolkit (`Core/K.luau`): `K.proj`, `K.lob`, `K.beam`,
`K.melee`, `K.cone`, `K.circle`, `K.line`, `K.zone`, `K.wall`, `K.object`, `K.summon`, `K.dash`,
`K.blink`, `K.leap`, `K.hover`, `K.dmg`, `K.heal`, `K.shield`, `K.slow`, `K.root`, `K.stun`, `K.lift`,
`K.knock`, `K.pull`, `K.mark`, `K.reveal`, `K.res` (HUD resource), and more. Stats such as cooldown,
Energy, Heat, windup and range come from `KitData`, so balance numbers live in one place.

### Tooling

```
python3 tools/luaucheck.py src        # Luau syntax + undefined globals + std-lib member check
python3 tools/check_kits.py           # verifies kits only use real K/S/ctx APIs; lints common Lua traps
python3 tools/gen_kitdata.py          # regenerate KitData from tools/data/kits.json
python3 tools/build_place.py          # rebuild EBProxima.rbxlx
```

`tools/parse_compendium.py` turns the compendium (converted with
`pandoc compendium.docx -t markdown --wrap=none`) into `tools/data/kits.json`.

## Status and known limitations

- **Not yet play-tested in Roblox Studio.** The build environment had no Roblox runtime. All 227 Luau files
  pass the bundled syntax/scope checker and the kit-API checker, but expect a round of in-Studio fixes
  (feel, timings, the odd runtime error) before it's ready for players. Errors inside a single move are
  caught and logged without breaking the server. A kit that fails to load falls back to a simple
  placeholder so the rest of the game keeps running.
- Values are the compendium's prototype numbers. The compendium itself says they need playtesting.
- Some mechanics are approximated with Roblox-friendly equivalents:
  - wall-running, climbing and gliding use scripted paths or hover constraints;
  - "concealment", "reveal" and "target-lock denial" use transparency, highlights and an untargetable flag
    for auto-aim (manual aim is never blocked);
  - audio-only effects such as Sound's Quiet Pocket are marked visually;
  - Copy runs the stored move with Copy's budgets and falls back to a generic echo if that move needs the
    source kit's own resources.
- **Synergy Mode** implements about 30 of the 100 team interactions as real mechanics:
  Acid+Steel, Agility+Wind, Alchemist+Mud/Gold, Angel+Sound, Light through Angel's Wing, Bone+Steel,
  Candy+Ice, Chaos+Glitch, Circus+Music, Creation+Steel, Dark+Light, Destruction+Rock, Dragon+Lava/Wind,
  Earth+Plant, Electric+Water, Energy+Engine, Engine+Ice, Fire+Ash/Wind, Flower+Water, Insect+Poison,
  Lunar+Water, Mud+Water, Music+Sound, Snow+Ice, Storm+Cloud and Weapon+Steel. Element counters also work:
  Fire weakens Ice walls, Water douses Fire patches and erodes Ink/Paper, and Light fields suppress Shadow
  anchors. The other team interactions appear as text in the compendium menu but aren't mechanics yet.
- Visual effects are simple neon shapes, rings and beams. Swapping in particles, animations and sounds is the
  natural next polish pass (see `Core/FX.luau`).
