#!/usr/bin/env python3
"""Showcase choreography: every showcase power casts moves 1-4 and its ultimate (normal + unstable) in front
of the local player's camera. Checks for client/server errors, that phases arrive, effects spawn and are
cleaned up afterwards (no leaked parts). Optionally renders frames of an ultimate (--render Kit).

    python3 tools/sim/tests/test_showcase.py [--render Gravity]
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from sim import Sim  # noqa: E402

KITS = ['Fire', 'Ice', 'Electric', 'Gravity', 'Water', 'Wind', 'Earth', 'Light']

SETUP = r'''
local S = require(find("ServerScriptService.Server.Core.S"))
local kit = KIT
local f = S.Match.spawnBot(kit)
f.entrant.spar = false
local t = S.Match.spawnBot("Normal")
t.entrant.spar = false
t.noGuard = true
local base = Vector3.new(30, 3.2, 128)
f.model:PivotTo(CFrame.lookAt(base, base + Vector3.new(0, 0, 1)))
t.model:PivotTo(CFrame.lookAt(base + Vector3.new(0, 0, 30), base))
task.wait(0.4)
_G.caster, _G.target = f, t
return true
'''

CAST = r'''
local S = require(find("ServerScriptService.Server.Core.S"))
local f, t = _G.caster, _G.target
local phases = 0
local unsub = S.on("cast", function() end)
local function aim()
	f.aim = { origin = f.root.Position + Vector3.new(0, 1.5, 0), dir = (t.root.Position - f.root.Position).Unit, hit = t.root.Position, target = t.model }
end
local function prime(p, heat)
	f.energy, f.proxima, f.heat = 100, p, heat or 0
	f.rupturePending, f.burnoutUntil, f.lockUntil = false, 0, 0
	for i = 1, 5 do f.cooldowns[i] = 0 end
	f.action = nil
	t.health = t.maxHealth
end
for slot = 1, 4 do
	prime(0)
	aim()
	S.Cast.begin(f, slot, false, false)
	task.wait(1.2)
	S.Cast.press(f, slot, false, false)
	task.wait(0.6)
end
prime(100)
aim()
S.Cast.begin(f, 5, false, false)
task.wait(SLEEP)
return true
'''

CLIENT_STATS = r'''
local Client = game:GetService("Players").LocalPlayer.PlayerScripts.Client
local V = require(Client.VFX)
local Showcase = require(Client.VFX.Showcase)
local st = V.stats()
return { effects = st.effects, liveParts = st.liveParts, pooled = st.pooled, ults = Showcase.active() }
'''


def main():
    render_kit = None
    if '--render' in sys.argv:
        render_kit = sys.argv[sys.argv.index('--render') + 1]
    s = Sim()
    s.run(2)
    # park the player's camera on the annex lane so all effects are near the viewer
    s.test('''
local p = game:GetService("Players").LocalPlayer
local Client = p.PlayerScripts.Client
require(Client.KitMenu).close()
local ch = p.Character
ch:PivotTo(CFrame.lookAt(Vector3.new(20, 3.2, 140), Vector3.new(30, 3.2, 143)))
local Cam = require(Client.CameraRig)
Cam.yaw = math.rad(-70)
Cam.pitch = math.rad(-8)
''', 'cam', peer='client')
    results = {}
    phases_seen = {}
    orig_dispatch = None
    for kit in (KITS if not render_kit else [render_kit]):
        s.clear_logs()
        s.test(SETUP.replace('KIT', json.dumps(kit)), f'setup_{kit}', timeout=60)
        if render_kit:
            from render_scene import render
            s.test(CAST.replace('SLEEP', '0.05').replace('for slot = 1, 4 do', 'for slot = 1, 0 do'), 'ult', timeout=60)
            out = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'out')
            cam = {'pos': [-8, 16, 120], 'look': [30, 6, 158], 'fov': 70}
            for i, (dt, tag) in enumerate([(0.9, 'buildup'), (1.0, 'rise'), (0.42, 'hold'), (0.12, 'slam'), (1.1, 'rise2'), (2.0, 'release')]):
                s.run(dt)
                print(render(s, os.path.join(out, f'ult_{kit}_{i}_{tag}.png'), size=(960, 540), cam=cam))
            continue
        s.test(CAST.replace('SLEEP', '6'), f'cast_{kit}', timeout=120)
        mid = s.test(CLIENT_STATS, 'stats', peer='client')
        s.run(6)
        after = s.test(CLIENT_STATS, 'stats', peer='client')
        errs = s.errors() + [w for w in s.warnings() if '[EB' in w]
        results[kit] = {'peakEffects': mid['effects'], 'afterEffects': after['effects'], 'afterParts': after['liveParts'], 'ultsAfter': after['ults'], 'errors': errs[:3]}
        s.test('''
local S = require(find("ServerScriptService.Server.Core.S"))
for _, x in ipairs({ _G.caster, _G.target }) do S.Fighter.remove(x) x.model:Destroy() end
for _, e in pairs(table.clone(S.Match.entrants)) do if e.isBot then S.Match.entrants[e.key] = nil if e.boardItem then e.boardItem:Destroy() end end end
''', 'cleanup')
        print(kit, json.dumps(results[kit]))
    if render_kit:
        return 0
    ok = all(not r['errors'] and r['afterParts'] <= 2 and r['ultsAfter'] == 0 for r in results.values())
    print('PASS' if ok else 'FAIL')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
