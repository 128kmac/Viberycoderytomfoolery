#!/usr/bin/env python3
"""Match loop: practice spawn -> start -> countdown freeze -> fight -> KOs -> results -> rematch -> practice.
Repeats several rounds and checks that instance / connection counts stay flat (no leaks across matches).

    python3 tools/sim/tests/test_match.py
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from sim import Sim  # noqa: E402

DRIVER = r'''
local S = require(find("ServerScriptService.Server.Core.S"))
local Match, Combat = S.Match, S.Combat
local Players = game:GetService("Players")
local player = Players:GetPlayers()[1]
local out = { rounds = {} }
local function me() return S.Fighter.forPlayer(player) end
task.wait(1)
local f = me()
out.practiceSpawn = f ~= nil and f.root.Position.Z > 50
out.state0 = Match.state
Match.setting(player, "bots", 2)
Match.setting(player, "koTarget", 2)
local function count()
	local n = 0
	for _, x in ipairs(workspace:GetDescendants()) do n += 1 end
	return n
end
for round = 1, 3 do
	local r = {}
	if round == 1 then Match.setting(player, "start") else Match.setting(player, "rematch") end
	task.wait(0.5)
	r.countdown = Match.state
	f = me()
	r.frozen = f and f.frozen == true
	r.fighters = 0
	for _, x in pairs(S.fighters) do if not x.isDummy and not x.isSummon then r.fighters += 1 end end
	task.wait(4)
	r.fight = Match.state
	f = me()
	r.unfrozen = f and not f.frozen
	-- KO two bots
	local kos = 0
	for _ = 1, 2 do
		for _, x in pairs(S.fighters) do
			if x.isBot and S.alive(x) and x.entrant and x.entrant.inMatch then
				x.invulnUntil = 0
				Combat.damage(me(), x, 5000, { kind = "true" })
				kos += 1
				break
			end
		end
		task.wait(0.3)
	end
	task.wait(1.2)
	r.results = Match.state
	r.winner = workspace:GetAttribute("Winner")
	local e = Match.entrantFor(player)
	r.kos = e and e.kos
	r.instances = count()
	r.conns = R.connCount or 0
	table.insert(out.rounds, r)
	if round < 3 then task.wait(1) end
end
Match.setting(player, "practice")
task.wait(1.5)
out.final = Match.state
local bots = 0
for _, x in pairs(S.fighters) do if x.isBot then bots += 1 end end
out.botsAfter = bots
f = me()
out.practiceRespawn = f ~= nil and f.root.Position.Z > 50
-- player death + respawn in practice
f.invulnUntil = 0
Combat.damage(nil, f, 5000, { kind = "true" })
task.wait(0.2)
out.dead = f.dead
task.wait(S.Config.RESPAWN_TIME + 0.5)
local f2 = me()
out.respawned = f2 ~= nil and f2 ~= f and not f2.dead
return out
'''


def main():
    s = Sim()
    s.run(2)
    res = s.test(DRIVER, 'match', timeout=120)
    print(json.dumps(res, indent=1, sort_keys=True))
    errs = s.errors()
    warns = [w for w in s.warnings() if w.startswith('[EB]')]
    for e in errs[:5] + warns[:5]:
        print('ERR', e[:800])
    ok = (res['practiceSpawn'] and res['final'] == 'Practice' and res['botsAfter'] == 0 and res['respawned']
          and all(r['countdown'] == 'Countdown' and r['frozen'] and r['fight'] == 'Fight' and r['unfrozen']
                  and r['results'] == 'Results' and r['kos'] == 2 for r in res['rounds'])
          and not errs and not warns)
    inst = [r['instances'] for r in res['rounds']]
    print('instances per round', inst)
    print('PASS' if ok else 'FAIL')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
