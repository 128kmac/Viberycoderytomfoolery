#!/usr/bin/env python3
"""Render the HUD / menus at several viewport sizes to PNGs (tools/sim/out/hud_*.png)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from sim import Sim  # noqa: E402
from render_gui import render  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'out')
SIZES = [(1920, 1080), (1280, 720), (1024, 768), (844, 390)]


def snap(s, tag):
    for w, h in SIZES:
        s.set_viewport(w, h)
        s.run(0.2)
        items = s.export_gui()
        path = os.path.join(OUT, f'hud_{tag}_{w}x{h}.png')
        render(items, (w, h), out=path)
        print(path, len(items), 'items')


def main():
    os.makedirs(OUT, exist_ok=True)
    s = Sim()
    s.run(2)
    s.test('''
local Client = game:GetService("Players").LocalPlayer.PlayerScripts.Client
require(Client.KitMenu).close()
game:GetService("ReplicatedStorage").Remotes.Input:FireServer("selectKit", "Fire")
task.wait(1)
''', 'prep', peer='client')
    snap(s, 'play')
    s.test('''
local Client = game:GetService("Players").LocalPlayer.PlayerScripts.Client
require(Client.MatchUI).togglePanel(true)
''', 'panel', peer='client')
    snap(s, 'panel')
    s.test('''
local Client = game:GetService("Players").LocalPlayer.PlayerScripts.Client
require(Client.MatchUI).togglePanel(false)
require(Client.KitMenu).open()
''', 'menu', peer='client')
    snap(s, 'kitmenu')
    print('errors', s.errors()[:3])


if __name__ == '__main__':
    main()
