#!/usr/bin/env python3
"""Pacing probe: bot duels (1v1) report time-to-kill, KOs, peak Proxima and ultimates per minute.

    python3 tools/sim/tests/test_pacing.py [seconds] [kitA] [kitB] [difficulty]
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from sim import Sim  # noqa: E402

DRIVER = r'''
local S = require(find("ServerScriptService.Server.Core.S"))
local Match = S.Match
while not S.Nav.ready do task.wait(0.1) end
Match.settings.bots = 0
Match.settings.koTarget = 99
Match.settings.timeLimit = 900
Match.settings.difficulty = "DIFF"
local stats = { kos = 0, ults = 0, peakP = 0, firstKO = -1, casts = 0, dmg = 0 }
local t0 = S.now()
S.on("defeated", function(f) if f.isBot then stats.kos += 1 if stats.firstKO < 0 then stats.firstKO = math.floor(S.now() - t0) end end end)
S.on("cast", function(f, c) if f.isBot then stats.casts += 1 if c.slot == 5 then stats.ults += 1 end end end)
S.on("damaged", function(t, info) if t.isBot then stats.dmg += (info.final or 0) end end)
local kits = { "KITA", "KITB" }
local bots = {}
for i = 1, 2 do
	local f = Match.spawnBot(kits[i])
	f.entrant.spar = false
	f.entrant.inMatch = true
	f.botDifficulty = "DIFF"
	f.frozen = false
	bots[i] = f
end
bots[1].model:PivotTo(CFrame.new(-20, 3.2, -60))
bots[2].model:PivotTo(CFrame.new(20, 3.2, -60))
Match.state = "Fight"
Match.phaseEnd = S.now() + 900
local el = 0
while el < SECONDS do
	task.wait(0.5)
	el += 0.5
	for _, e in pairs(Match.entrants) do
		local f = e.fighter
		if f and S.alive(f) then stats.peakP = math.max(stats.peakP, f.proxima) end
	end
end
stats.dps = math.floor(stats.dmg / SECONDS * 10) / 10
stats.ultsPerMin = math.floor(stats.ults / SECONDS * 600) / 10
return stats
'''


def main():
    secs = int(sys.argv[1]) if len(sys.argv) > 1 else 150
    a = sys.argv[2] if len(sys.argv) > 2 else 'Fire'
    b = sys.argv[3] if len(sys.argv) > 3 else 'Ice'
    diff = sys.argv[4] if len(sys.argv) > 4 else 'Normal'
    s = Sim(player=None)
    r = s.test(DRIVER.replace('SECONDS', str(secs)).replace('KITA', a).replace('KITB', b).replace('DIFF', diff), 'pace', timeout=secs + 120)
    print(a, 'vs', b, diff, json.dumps(r))
    errs = s.errors() + [w for w in s.warnings() if '[EB' in w]
    for e in errs[:4]:
        print('ERR', e[:300])


if __name__ == '__main__':
    main()
