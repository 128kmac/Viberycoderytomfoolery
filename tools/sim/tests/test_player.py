#!/usr/bin/env python3
"""Player end-to-end (harness): real input events -> client controls -> remotes -> server combat ->
cues -> client effects / audio / animation / HUD. Also movement, guard, dodge, basic attacks, death
and respawn of the local player.

    python3 tools/sim/tests/test_player.py [Kit]
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from sim import Sim  # noqa: E402

CLIENT = r'''
local p = game:GetService("Players").LocalPlayer
local RS = game:GetService("ReplicatedStorage")
local Client = p:WaitForChild("PlayerScripts"):WaitForChild("Client")
local Cam = require(Client.CameraRig)
local V = require(Client.VFX)
local Anim = require(Client.Animator)
local KitMenu = require(Client.KitMenu)
local out = {}
KitMenu.close()
RS.Remotes.Input:FireServer("selectKit", "KIT")
task.wait(0.8)
local ch = p.Character
local root = ch.HumanoidRootPart
local hum = ch:FindFirstChildOfClass("Humanoid")
out.kit = ch:GetAttribute("Kit")
out.rigs = Anim.count()
-- nearest dummy
local dummy, dd
for _, m in ipairs(workspace.Bots:GetChildren()) do
	if m:GetAttribute("IsDummy") and m:FindFirstChild("HumanoidRootPart") then
		local d = (m.HumanoidRootPart.Position - root.Position).Magnitude
		if not dd or d < dd then dummy, dd = m, d end
	end
end
out.dummyDist = math.floor(dd or -1)
local function aimAt(pos)
	local to = pos - (root.Position + Vector3.new(0, 1.9, 0))
	Cam.yaw = math.atan2(-to.X, -to.Z)
	Cam.pitch = math.asin(math.clamp(to.Unit.Y, -1, 1))
end
-- free walk: 1.2 s strafing right must cover ground
local start = root.Position
hum:Move(Vector3.new(1, 0, 0), false)
task.wait(1.2)
hum:Move(Vector3.zero, false)
out.walked = math.floor((root.Position - start).Magnitude)
-- approach the dummy until ~8 m away
for _ = 1, 60 do
	local to = dummy.HumanoidRootPart.Position - root.Position
	if Vector3.new(to.X, 0, to.Z).Magnitude < 24 then break end
	hum:Move(Vector3.new(to.X, 0, to.Z).Unit, false)
	task.wait(0.1)
end
hum:Move(Vector3.zero, false)
aimAt(dummy.HumanoidRootPart.Position)
task.wait(0.3)
local h0 = dummy:GetAttribute("Health")
local sounds0 = #R.soundPlays
local fx0 = V.stats().effects
-- cast move 1 with the real key
R.inputKey("Q", true)
task.wait(0.05)
R.inputKey("Q", false)
local maxProj, maxFx = 0, 0
local castPhase = {}
for _ = 1, 30 do
	task.wait(0.05)
	local st = V.stats()
	maxProj = math.max(maxProj, st.projectiles)
	maxFx = math.max(maxFx, st.effects)
	local ph = ch:GetAttribute("CastPhase")
	if ph and ph ~= "" then castPhase[ph] = true end
	if (ch:GetAttribute("CastActive") or 0) > 0 then castPhase.active = true end
end
local ph = {}
for k in pairs(castPhase) do table.insert(ph, k) end
table.sort(ph)
out.castPhases = table.concat(ph, ",")
out.maxProjectilesRendered = maxProj
out.maxEffects = maxFx
out.dummyDamage = h0 - (dummy:GetAttribute("Health") or h0)
out.soundsPlayed = #R.soundPlays - sounds0
-- basic attack: walk into melee
for _ = 1, 40 do
	local to = dummy.HumanoidRootPart.Position - root.Position
	if Vector3.new(to.X, 0, to.Z).Magnitude < 5.5 then break end
	hum:Move(Vector3.new(to.X, 0, to.Z).Unit, false)
	task.wait(0.1)
end
hum:Move(Vector3.zero, false)
aimAt(dummy.HumanoidRootPart.Position)
task.wait(0.2)
local h1 = dummy:GetAttribute("Health")
R.inputMouse("MouseButton1", true)
task.wait(0.9)
R.inputMouse("MouseButton1", false)
task.wait(0.3)
out.basicDamage = h1 - (dummy:GetAttribute("Health") or h1)
-- guard
R.inputMouse("MouseButton2", true)
task.wait(0.4)
out.guarding = ch:GetAttribute("Guarding") == true
R.inputMouse("MouseButton2", false)
task.wait(0.3)
out.guardReleased = ch:GetAttribute("Guarding") ~= true
-- dodge
local d0 = ch:GetAttribute("Dodge")
local pos0 = root.Position
hum:Move(Vector3.new(1, 0, 0), false)
R.inputKey("LeftShift", true)
task.wait(0.05)
R.inputKey("LeftShift", false)
task.wait(0.5)
hum:Move(Vector3.zero, false)
out.dodgeUsed = (d0 or 0) - (ch:GetAttribute("Dodge") or 0)
out.dodgeDist = math.floor((root.Position - pos0).Magnitude * 10) / 10
-- jump
local y0 = root.Position.Y
hum.Jump = true
local peak = y0
for _ = 1, 12 do task.wait(0.05) peak = math.max(peak, root.Position.Y) end
out.jumpHeight = math.floor((peak - y0) * 10) / 10
task.wait(1)
out.fxAfter = V.stats()
return out
'''

SERVER_DEATH = r'''
local S = require(find("ServerScriptService.Server.Core.S"))
local p = game:GetService("Players"):GetPlayers()[1]
local f = S.Fighter.forPlayer(p)
local out = {}
f.invulnUntil = 0
S.Combat.damage(nil, f, 5000, { kind = "true" })
task.wait(0.3)
out.dead = f.dead
out.deadAttr = f.model:GetAttribute("Dead")
task.wait(S.Config.RESPAWN_TIME + 0.6)
local f2 = S.Fighter.forPlayer(p)
out.respawned = f2 ~= nil and f2 ~= f and not f2.dead
out.newChar = p.Character ~= f.model
return out
'''

CLIENT_AFTER = r'''
local p = game:GetService("Players").LocalPlayer
local Client = p.PlayerScripts.Client
local Anim = require(Client.Animator)
local out = {}
out.rigs = Anim.count()
out.camType = tostring(workspace.CurrentCamera.CameraType)
out.charOk = p.Character ~= nil and p.Character:GetAttribute("Dead") == false
return out
'''


def main():
    kit = sys.argv[1] if len(sys.argv) > 1 else 'Fire'
    s = Sim()
    s.run(3)
    c = s.test(CLIENT.replace('KIT', kit), 'player', peer='client', timeout=120)
    d = s.test(SERVER_DEATH, 'death', timeout=60)
    a = s.test(CLIENT_AFTER, 'after', peer='client', timeout=30)
    res = {'client': c, 'death': d, 'after': a}
    print(json.dumps(res, indent=1, sort_keys=True))
    errs = s.errors()
    warns = [w for w in s.warnings() if '[EB' in w]
    for e in errs[:6] + warns[:6]:
        print('ERR', e[:700])
    checks = {
        'equipped': c['kit'] == kit,
        'walked': c['walked'] > 5,
        'castPhases': 'active' in c['castPhases'],
        'damage': c['dummyDamage'] > 0,
        'effects': c['maxEffects'] > 3,
        'sounds': c['soundsPlayed'] > 0,
        'basic': c['basicDamage'] > 0,
        'guard': c['guarding'] and c['guardReleased'],
        'dodge': c['dodgeUsed'] == 1 and c['dodgeDist'] > 6,
        'jump': c['jumpHeight'] > 3,
        'death': d['dead'] and d['deadAttr'],
        'respawn': d['respawned'] and d['newChar'] and a['charOk'],
        'noErrors': not errs and not warns,
    }
    for k, v in checks.items():
        print(('PASS ' if v else 'FAIL ') + k)
    return 0 if all(checks.values()) else 1


if __name__ == '__main__':
    sys.exit(main())
