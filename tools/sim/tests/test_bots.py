#!/usr/bin/env python3
"""Bot behaviour: nav graph build, A* paths, telegraph avoidance, and a bots-only match with stats.

    python3 tools/sim/tests/test_bots.py [seconds] [difficulty]
"""
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from sim import Sim  # noqa: E402

DRIVER = r'''
local S = require(find("ServerScriptService.Server.Core.S"))
local Match = S.Match
local out = {}
local t0 = os.clock()
while not S.Nav.ready do task.wait(0.1) end
out.navNodes = #S.Nav.nodes
local edges, jumps, drops = 0, 0, 0
for _, n in ipairs(S.Nav.nodes) do
	for _, e in ipairs(n.edges) do
		edges += 1
		if e.kind == "jump" then jumps += 1 elseif e.kind == "drop" then drops += 1 end
	end
end
out.navEdges, out.navJumps, out.navDrops = edges, jumps, drops
-- path across the arena
local sp = S.Arena.spawns
local p = S.Nav.path(sp[1].Position, sp[5].Position)
out.pathLen = p and #p or 0

-- telegraph avoidance: a bot standing in an enemy AoE must leave before impact
Match.settings.difficulty = "DIFF"
local a = Match.spawnBot("Fire")
local enemy = Match.spawnBot("Ice")
a.entrant.spar = false
enemy.entrant.spar = false
a.entrant.inMatch = true
enemy.entrant.inMatch = true
Match.state = "Fight"
Match.phaseEnd = S.now() + 1000
enemy.frozen = true
a.botDifficulty = "DIFF"
local c0 = Vector3.new(30, 0, 0)
a.model:PivotTo(CFrame.new(c0 + Vector3.new(0, 3.2, 0)))
enemy.model:PivotTo(CFrame.new(c0 + Vector3.new(0, 3.2, 40)))
task.wait(0.6)
local g = S.Hit.ground(a.root.Position)
S.Danger.add({ shape = "circle", pos = g, radius = 9, t1 = S.now() + 1.4, owner = enemy })
task.wait(1.4)
local d = (Vector3.new(a.root.Position.X, 0, a.root.Position.Z) - Vector3.new(g.X, 0, g.Z)).Magnitude
out.escapeDist = math.floor(d * 10) / 10
out.escaped = d > 9
S.Fighter.remove(a) a.model:Destroy()
S.Fighter.remove(enemy) enemy.model:Destroy()
for _, e in pairs(table.clone(Match.entrants)) do if e.isBot then Match.entrants[e.key] = nil if e.boardItem then e.boardItem:Destroy() end end end
Match.state = "Practice"

-- bots-only match
Match.settings.bots = 4
Match.settings.koTarget = 99
Match.settings.timeLimit = 600
Match.startMatch(nil)
local stats = { casts = 0, ults = 0, dodges = 0, guards = 0, basics = 0, kos = 0, oob = 0 }
S.on("cast", function(f, c) if f.isBot then stats.casts += 1 if c.slot == 5 then stats.ults += 1 end end end)
S.on("defeated", function(f) if f.isBot then stats.kos += 1 end end)
local oldDodge = S.Fighter.dodge
S.Fighter.dodge = function(f, ...) local r = oldDodge(f, ...) if r and f.isBot then stats.dodges += 1 end return r end
local oldOOB = S.Fighter.outOfBounds
S.Fighter.outOfBounds = function(f, ...) stats.oob += 1 return oldOOB(f, ...) end
local samples, idle, guarding = 0, 0, 0
local last = {}
local elapsed = 0
while elapsed < SECONDS do
	task.wait(0.5)
	elapsed += 0.5
	for _, f in pairs(S.fighters) do
		if f.isBot and S.alive(f) and Match.state == "Fight" then
			samples += 1
			local p = f.root.Position
			if last[f] and (p - last[f]).Magnitude < 0.5 and not S.Cast.isBusy(f) then idle += 1 end
			if f.guarding then guarding += 1 end
			last[f] = p
		end
	end
end
stats.idleFrac = samples > 0 and math.floor(idle / samples * 100) or -1
stats.guardFrac = samples > 0 and math.floor(guarding / samples * 100) or -1
local board = {}
for _, e in pairs(Match.entrants) do
	if e.isBot then table.insert(board, string.format("%s %s ko=%d d=%d dmg=%d", e.name, e.kit, e.kos, e.deaths, e.damage)) end
end
stats.board = board
stats.state = Match.state
out.match = stats
out.wall = os.clock() - t0
return out
'''


def main():
    secs = int(sys.argv[1]) if len(sys.argv) > 1 else 90
    diff = sys.argv[2] if len(sys.argv) > 2 else 'Normal'
    t = time.time()
    s = Sim(player=None)
    res = s.test(DRIVER.replace('SECONDS', str(secs)).replace('DIFF', diff), 'bots', timeout=secs + 120)
    print(json.dumps(res, indent=1, sort_keys=True))
    errs = s.errors()
    warns = [w for w in s.warnings() if w.startswith('[EB]')]
    for e in errs[:5] + warns[:8]:
        print('ERR', e[:600])
    print('errors', len(errs), 'warnings', len(warns), 'wall', round(time.time() - t, 1))
    m = res['match']
    ok = res['navNodes'] > 100 and res['pathLen'] > 3 and res['escaped'] and m['casts'] > 10 and m['kos'] > 0 and not errs
    print('PASS' if ok else 'FAIL')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
