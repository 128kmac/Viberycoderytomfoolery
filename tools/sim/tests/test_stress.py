#!/usr/bin/env python3
"""Overlapping-effects stress + cleanup over repeated matches.
7 Hard bots + the player fight while every fighter's Proxima is topped up so ultimates overlap.
Samples client effect counts, live/pooled parts, projectiles and audio voices; after each round returns
to practice and checks that effects, sounds, server FX instances and instance totals drain back.

    python3 tools/sim/tests/test_stress.py [seconds_per_round] [rounds]
"""
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from sim import Sim  # noqa: E402

START = r'''
local S = require(find("ServerScriptService.Server.Core.S"))
local Match = S.Match
local p = game:GetService("Players"):GetPlayers()[1]
Match.setting(p, "bots", 7)
Match.setting(p, "difficulty", "Hard")
Match.setting(p, "koTarget", 50)
Match.setting(p, "timeLimit", 600)
Match.setting(p, "start")
task.wait(4.5)
return Match.state
'''

TICK = r'''
local S = require(find("ServerScriptService.Server.Core.S"))
local n = 0
for _, f in pairs(S.fighters) do
	if f.isBot and S.alive(f) then
		f.proxima = 100
		f.heat = 70
		n += 1
	end
end
return n
'''

CLIENT = r'''
local Client = game:GetService("Players").LocalPlayer.PlayerScripts.Client
local V = require(Client.VFX)
local A = require(Client.Audio)
local st = V.stats()
local a = A.stats()
local hl = 0
for _, x in ipairs(workspace:GetDescendants()) do if x:IsA("Highlight") then hl += 1 end end
return { effects = st.effects, live = st.liveParts, pooled = st.pooled, proj = st.projectiles, voices = a.active, highlights = hl }
'''

SERVER = r'''
local S = require(find("ServerScriptService.Server.Core.S"))
local n = 0
for _ in ipairs(workspace:GetDescendants()) do n += 1 end
local fx = #S.folders.FX:GetChildren()
local projs = 0
for _ in pairs(S.Proj.list) do projs += 1 end
local zones = 0
for _ in pairs(S.Zones.list) do zones += 1 end
return { instances = n, serverFx = fx, serverProj = projs, zones = zones, state = S.Match.state }
'''

END = r'''
local S = require(find("ServerScriptService.Server.Core.S"))
local p = game:GetService("Players"):GetPlayers()[1]
S.Match.setting(p, "practice")
task.wait(8)
return S.Match.state
'''


def main():
    secs = int(sys.argv[1]) if len(sys.argv) > 1 else 40
    rounds = int(sys.argv[2]) if len(sys.argv) > 2 else 2
    s = Sim()
    s.run(3)
    s.test('require(game:GetService("Players").LocalPlayer.PlayerScripts.Client.KitMenu).close()', 'km', peer='client')
    base = s.test(SERVER, 'base')
    print('baseline', base)
    report = []
    for r in range(rounds):
        s.test(START, 'start', timeout=30)
        peak = {}
        wall0 = time.time()
        sim0 = s.now
        for i in range(secs * 2):
            if i % 6 == 0:
                s.test(TICK, 'tick')
            s.run(0.5)
            c = s.test(CLIENT, 'c', peer='client')
            for k, v in c.items():
                peak[k] = max(peak.get(k, 0), v)
        wall = time.time() - wall0
        sv = s.test(SERVER, 'mid')
        s.test(END, 'end', timeout=30)
        s.run(3)
        after_c = s.test(CLIENT, 'c2', peer='client')
        after_s = s.test(SERVER, 'after')
        row = {'round': r + 1, 'peakClient': peak, 'serverDuring': sv, 'afterClient': after_c, 'afterServer': after_s, 'wallPerSimSec': round(wall / max(1e-6, s.now - sim0), 2)}
        report.append(row)
        print(json.dumps(row))
    errs = s.errors() + [w for w in s.warnings() if '[EB' in w]
    for e in errs[:6]:
        print('ERR', e[:400])
    last = report[-1]
    checks = {
        'noErrors': not errs,
        'effectsDrain': last['afterClient']['effects'] <= 6,
        'voicesDrain': last['afterClient']['voices'] <= 4,
        'serverFxDrain': last['afterServer']['serverFx'] <= 2 and last['afterServer']['serverProj'] == 0,
        'highlightsUnder31': max(r['peakClient']['highlights'] for r in report) <= 31,
        'flatAcrossRounds': abs(report[-1]['afterServer']['instances'] - report[0]['afterServer']['instances']) <= 40,
    }
    for k, v in checks.items():
        print(('PASS ' if v else 'FAIL ') + k)
    return 0 if all(checks.values()) else 1


if __name__ == '__main__':
    sys.exit(main())
