#!/usr/bin/env python3
"""Arena checks: navigation reachability of every area, spawn safety, boundary containment, shot
interaction with cover vs decoration, and no hidden collision at body height inside the play space.

    python3 tools/sim/tests/test_arena.py
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from sim import Sim  # noqa: E402

DRIVER = r'''
local S = require(find("ServerScriptService.Server.Core.S"))
while not S.Nav.ready do task.wait(0.1) end
local out = { reach = {}, spawns = {}, hidden = {} }
local function polar(r, deg, y)
	local a = math.rad(deg)
	return Vector3.new(math.cos(a) * r, y or 0, math.sin(a) * r)
end
local spire = polar(64, 225)
local targets = {
	spireTop = spire + Vector3.new(0, 10, 0),
	galeLanding = Vector3.new(-4, 10, spire.Z),
	terraceTop = polar(74, 125, 8),
	terraceMid = polar(59, 128, 4),
	cisternRim = polar(63, 45) + polar(20, 0, 5),
	cisternPool = polar(63, 45),
	forgeHallA = polar(56, 330),
	forgeHallB = polar(62, 296),
	daisTop = Vector3.new(0, 2, 18),
	annex = Vector3.new(0, 0, 150),
}
for i, sp in ipairs(S.Arena.spawns) do
	targets["alcove" .. i] = sp.Position
end
local start = Vector3.new(0, 2, 20)
local reached, total = 0, 0
for name, p in pairs(targets) do
	total += 1
	local n = S.Nav.nearest(p, 12)
	local path = n and S.Nav.path(start, n.pos, nil, 5000)
	local ok = path ~= nil and math.abs(n.pos.Y - p.Y) < 3
	out.reach[name] = ok and #path or (n and ("nopath y=" .. math.floor(n.pos.Y)) or "nonode")
	if ok then reached += 1 end
end
out.reached = reached .. "/" .. total
-- spawns: standing space free and ground beneath
for i, sp in ipairs(S.Arena.spawns) do
	local stand = sp.Position + Vector3.new(0, 3.2, 0)
	out.spawns[i] = S.Hit.spaceFree(stand) and S.Hit.ground(stand, 6) ~= nil
end
-- hidden collision: invisible collidable parts inside the island at body height (barriers excluded)
for _, p in ipairs(workspace.Arena:GetDescendants()) do
	if p:IsA("BasePart") and p.CanCollide and p.Transparency > 0.9 and p.Name ~= "Barrier" then
		local q = p.Position
		if Vector3.new(q.X, 0, q.Z).Magnitude < 98 and q.Y < 12 then
			table.insert(out.hidden, p.Name)
		end
	end
end
-- shots: avenue wall blocks; canopy / banner / rings do not
local function blocked(a, b)
	return S.Hit.raycast(a, b - a) ~= nil
end
local w = polar(63, 0, 1.5)
out.wallBlocks = blocked(w + Vector3.new(-6, 0, 0), w + Vector3.new(6, 0, 0))
local tree = polar(73, 136, 8)
out.canopyPasses = not blocked(tree + Vector3.new(-12, 20, 0), tree + Vector3.new(12, 20, 0))
out.ringPasses = not blocked(Vector3.new(-30, 42, 0), Vector3.new(30, 42, 0))
local f = S.Match.spawnBot("Fire")
f.entrant.spar = false -- inert: no AI in practice
local hum = f.humanoid
-- traversal: ramp to the spire top
f.model:PivotTo(CFrame.new(Vector3.new(spire.X - 11, 3.2, spire.Z + 37)))
task.wait(0.3)
local peak = 0
for _ = 1, 24 do
	hum:Move(Vector3.new(0, 0, -1), false)
	task.wait(0.1)
	peak = math.max(peak, f.root.Position.Y)
end
out.spireClimbY = math.floor(peak * 10) / 10
-- containment: walk a bot straight off the east edge for 3 s
f.model:PivotTo(CFrame.new(polar(92, 10, 3.2)))
task.wait(0.3)
for _ = 1, 30 do
	hum:Move(Vector3.new(1, 0, 0.17), false)
	task.wait(0.1)
end
local p = f.root.Position
out.edgeRadius = math.floor(Vector3.new(p.X, 0, p.Z).Magnitude * 10) / 10
out.edgeY = math.floor(p.Y * 10) / 10
return out
'''


def main():
    s = Sim(player=None)
    r = s.test(DRIVER, 'arena', timeout=200)
    print(json.dumps(r, indent=1, sort_keys=True))
    errs = s.errors() + [w for w in s.warnings() if '[EB' in w]
    for e in errs[:5]:
        print('ERR', e[:500])
    reached, total = map(int, r['reached'].split('/'))
    checks = {
        'reachability': reached == total,
        'spawnsSafe': all(r['spawns'].values() if isinstance(r['spawns'], dict) else r['spawns']),
        'noHiddenCollision': len(r['hidden']) == 0,
        'coverBlocksShots': r['wallBlocks'],
        'decorPassesShots': r['canopyPasses'] and r['ringPasses'],
        'contained': r['edgeRadius'] < 101 and r['edgeY'] > 0,
        'spireClimb': r['spireClimbY'] > 11,
        'noErrors': not errs,
    }
    for k, v in checks.items():
        print(('PASS ' if v else 'FAIL ') + k)
    return 0 if all(checks.values()) else 1


if __name__ == '__main__':
    sys.exit(main())
