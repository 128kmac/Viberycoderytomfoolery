#!/usr/bin/env python3
"""Smoke-test every power: cast moves 1-4 (normal, P60, modifier), recasts, kit action, ultimate and
unstable ultimate against a target fighter; report runtime errors and engine warnings per kit.

    python3 tools/sim/tests/test_kits_smoke.py            # all kits
    python3 tools/sim/tests/test_kits_smoke.py Fire Ice   # selected kits
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from sim import Sim  # noqa: E402

DRIVER = r'''
local kit = KIT
local S = require(find("ServerScriptService.Server.Core.S"))
local Cast, Match = S.Cast, S.Match
local f = Match.spawnBot(kit)
f.isBot = nil
f.isDummy = true
f.invulnUntil = 0
local t = Match.spawnBot("Normal")
t.isBot = nil
t.isDummy = true
t.invulnUntil = 0
t.noGuard = true
-- open test lane (override with S.Arena.testLane when the arena provides one)
local lane = S.Arena.testLane or { origin = Vector3.new(-15, 4, -10), dir = Vector3.new(1, 0, 0) }
local base = lane.origin
local FWD = lane.dir
f.model:PivotTo(CFrame.lookAt(base, base + FWD))
local tp = base + FWD * 21
t.model:PivotTo(CFrame.lookAt(tp, base))
task.wait(0.5)
local function aim()
	if not t.root or not f.root then return end
	f.aim = { origin = f.root.Position + Vector3.new(0, 1.5, 0), dir = (t.root.Position - f.root.Position).Unit, hit = t.root.Position, target = t.model }
end
local function prime(p, heat)
	f.energy = 100
	f.proxima = p
	f.heat = heat or 0
	f.rupturePending = false
	f.burnoutUntil = 0
	f.lockUntil = 0
	for i = 1, 5 do f.cooldowns[i] = 0 end
	f.action = nil
	if t.dead or not t.root then return end
	t.health = t.maxHealth
	t.shields = {}
end
local dealt = {}
local function place(slot)
	-- target at a distance that suits the move (a fraction of its listed range)
	local def = f.kitData and f.kitData.moves[slot]
	local r = def and def.range or 7
	if not r or r <= 0 then r = 4 end
	local dm = math.clamp(r * 0.55, 1.6, 10)
	if t.dead or not t.root then return end
	f.model:PivotTo(CFrame.lookAt(base, base + FWD))
	local tp2 = base + FWD * (dm * 3)
	t.model:PivotTo(CFrame.lookAt(tp2, base))
	t.root.AssemblyLinearVelocity = Vector3.zero
end
local function castSlot(slot, p, mod, unstable, rounds)
	place(slot)
	task.wait(0.1)
	prime(p, unstable and 65 or 0)
	aim()
	local h0 = t.health
	Cast.begin(f, slot, unstable, mod)
	for _ = 1, rounds do
		task.wait(0.6)
		aim()
		Cast.press(f, slot, true, false)
		Cast.press(f, slot, false, false)
	end
	task.wait(2.5)
	return math.floor(h0 - t.health + 0.5)
end
for slot = 1, 4 do
	dealt["s" .. slot] = castSlot(slot, 0, false, false, 3)
	dealt["p" .. slot] = castSlot(slot, 70, false, false, 2)
	castSlot(slot, 70, true, false, 2)
end
if f.kit.action then
	S.Cast.kitAction(f)
	task.wait(0.5)
end
dealt.ult = castSlot(5, 100, false, false, 6)
dealt.unstable = castSlot(5, 100, false, true, 6)
task.wait(2)
S.Fighter.remove(f)
f.model:Destroy()
S.Fighter.remove(t)
t.model:Destroy()
task.wait(0.5)
return dealt
'''


def main():
    kits = sys.argv[1:]
    s = Sim(player=None)
    if not kits:
        idx = s.test('local S = require(find("ServerScriptService.Server.Core.S")) local out = {} for i, e in ipairs(S.Kits.index) do out[i] = e.name end return out', 'index')
        kits = idx
    failed = 0
    report = {}
    for k in kits:
        s.clear_logs()
        try:
            dealt = s.test(DRIVER.replace('KIT', json.dumps(k)), f'smoke_{k}', timeout=400)
            errs = s.errors()
        except Exception as e:
            dealt, errs = {}, s.errors() + [f'DRIVER: {e}']
        warns = [w for w in s.warnings() if w.startswith('[EB]') or 'NaN' in w]
        report[k] = {'errors': errs, 'warnings': warns, 'dealt': dealt}
        bad = bool(errs or warns)
        failed += bad
        print(f'{"BAD" if bad else "OK "} {k:12s} {json.dumps(dealt, sort_keys=True)} errors={len(errs)} warns={len(warns)}', flush=True)
        for e in (errs + warns)[:2]:
            print('    ' + e.replace('\n', '\n    ')[:1200])
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'kits_report.json')
    json.dump(report, open(out, 'w'), indent=1)
    print(f'{len(kits) - failed}/{len(kits)} kits clean; report -> {out}')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
