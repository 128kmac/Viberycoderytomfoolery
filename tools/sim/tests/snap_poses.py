#!/usr/bin/env python3
"""Render a fighter in each procedural animation state (idle, run, windup, release, guard, dash,
jump, death) to tools/sim/out/pose_*.png and a contact sheet, to eyeball the animator's poses."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from sim import Sim  # noqa: E402
from render_scene import render  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'out')

STATES = {
    'idle': 'm:SetAttribute("CastPhase", "")',
    'run': 'move = true',
    'windup': 'm:SetAttribute("CastPhase", "windup") m:SetAttribute("CastHand", "right") m:SetAttribute("CastStart", now - 0.4) m:SetAttribute("CastEnd", now + 0.2)',
    'release': 'm:SetAttribute("CastPhase", "active") m:SetAttribute("CastHand", "right") m:SetAttribute("CastActive", now)',
    'ultbuild': 'm:SetAttribute("CastPhase", "windup") m:SetAttribute("CastUlt", true) m:SetAttribute("CastHand", "both") m:SetAttribute("CastStart", now - 1) m:SetAttribute("CastEnd", now + 0.4)',
    'guard': 'm:SetAttribute("Guarding", true)',
    'jump': 'hum.Jump = true',
    'death': 'm:SetAttribute("Dead", true) m:SetAttribute("DiedAt", now - 1.2)',
}


def main():
    s = Sim()
    s.run(2)
    s.test('''
local S = require(find("ServerScriptService.Server.Core.S"))
local f = S.Match.spawnBot("Fire")
f.entrant.spar = false
f.model:PivotTo(CFrame.lookAt(Vector3.new(30, 3.2, 140), Vector3.new(20, 3.2, 140)))
_G.poseBot = f
''', 'spawn')
    files = []
    for name, code in STATES.items():
        s.test('''
local f = _G.poseBot
local m, hum = f.model, f.humanoid
for _, k in ipairs({ "CastPhase", "CastUlt", "Guarding", "Dead" }) do m:SetAttribute(k, nil) end
m:SetAttribute("CastPhase", "")
m:SetAttribute("Dead", false)
f.root.CFrame = CFrame.lookAt(Vector3.new(30, 3.2, 140), Vector3.new(20, 3.2, 140))
task.wait(0.4)
local now = workspace:GetServerTimeNow()
local move = false
''' + code + '''
if move then hum:Move(Vector3.new(-1, 0, 0), false) end
task.wait(name == "jump" and 0.18 or 0.3)
hum:Move(Vector3.zero, false)
'''.replace('name == "jump"', 'true' if name == 'jump' else 'false'), 'pose_' + name)
        p = os.path.join(OUT, f'pose_{name}.png')
        bot_x = s.test('return _G.poseBot.root.Position.X', 'x')
        render(s, p, size=(480, 540), cam={'pos': [bot_x - 7, 5.5, 132], 'look': [bot_x - 1, 2.6, 140], 'fov': 50})
        files.append(p)
        print(p)
    from PIL import Image
    ims = [Image.open(f) for f in files]
    w, h = ims[0].size
    sheet = Image.new('RGB', (w * 4, h * 2))
    for i, im in enumerate(ims):
        sheet.paste(im, ((i % 4) * w, (i // 4) * h))
    sheet = sheet.resize((w * 2, h))
    sheet.save(os.path.join(OUT, 'poses_sheet.png'))
    print('errors', s.errors()[:3])


if __name__ == '__main__':
    main()
