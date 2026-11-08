#!/usr/bin/env python3
"""Gameplay composite: a live match rendered from the player's own camera with the HUD overlaid."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from sim import Sim  # noqa: E402
from render_scene import render  # noqa: E402
from render_gui import render as render_gui  # noqa: E402
from PIL import Image  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'out')
KIT = sys.argv[1] if len(sys.argv) > 1 else 'Gravity'


def main():
    s = Sim()
    s.run(2)
    s.test('''
local p = game:GetService("Players").LocalPlayer
require(p.PlayerScripts.Client.KitMenu).close()
game:GetService("ReplicatedStorage").Remotes.Input:FireServer("selectKit", "%s")
''' % KIT, 'kit', peer='client')
    s.test('''
local S = require(find("ServerScriptService.Server.Core.S"))
local p = game:GetService("Players"):GetPlayers()[1]
S.Match.setting(p, "bots", 3)
S.Match.setting(p, "koTarget", 10)
S.Match.setting(p, "start")
task.wait(5)
''', 'start', timeout=30)
    # let the fight develop, then stage the player's ultimate at the nearest bot
    s.run(10)
    s.test('''
local S = require(find("ServerScriptService.Server.Core.S"))
local p = game:GetService("Players"):GetPlayers()[1]
local me = S.Fighter.forPlayer(p)
local best, bd
for _, f in pairs(S.fighters) do
	if f.isBot and S.alive(f) then
		local d = (f.root.Position - me.root.Position).Magnitude
		if not bd or d < bd then best, bd = f, d end
	end
end
if best then
	best.model:PivotTo(CFrame.new(me.root.Position + me.root.CFrame.LookVector * 40 + Vector3.new(0, 0.5, 0)))
	best.frozen = true
	me.proxima = 100
	me.aim = { origin = me.root.Position, dir = (best.root.Position - me.root.Position).Unit, hit = best.root.Position, target = best.model }
	S.Cast.begin(me, 5, false, false)
end
''', 'ult', timeout=10)
    for i, dt in enumerate([1.0, 1.1, 1.25]):
        s.run(dt)
        size = (1280, 720)
        scene_png = os.path.join(OUT, f'_gp_scene_{i}.png')
        render(s, scene_png, size=size)
        items = s.export_gui()
        comp = render_gui(items, size, background=Image.open(scene_png))
        out = os.path.join(OUT, f'gameplay_{KIT}_{i}.png')
        comp.convert('RGB').save(out)
        print(out)
    print('errors', s.errors()[:3])


if __name__ == '__main__':
    main()
