#!/usr/bin/env python3
"""Headless harness that runs the real EB: Proxima scripts against a Roblox API emulator.

Usage from Python:
    from sim import Sim
    s = Sim()               # boots server scripts, joins one client player
    s.run(10)               # simulate 10 seconds of game time
    print(s.errors())       # runtime errors with tracebacks (Luau line numbers)

This is a behavioural emulator, not Roblox: physics is simplified, rendering is
exported as geometry for the snapshot renderers, and audio is logged, not played.
"""
import json
import os
import sys

from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
from luau2lua import transpile  # noqa: E402

EMU_FILES = ['datatypes.lua', 'enum.lua', 'core.lua', 'classes.lua', 'services.lua', 'physics.lua', 'gui.lua', 'boot.lua']


def to_py(v, depth=0):
    """Convert lupa tables recursively into Python lists/dicts."""
    if depth > 40:
        return None
    if lua54.lua_type(v) == 'table':
        keys = list(v.keys())
        if keys and all(isinstance(k, int) for k in keys):
            n = max(keys)
            if n == len(keys):
                return [to_py(v[i], depth + 1) for i in range(1, n + 1)]
        return {str(k): to_py(v[k], depth + 1) for k in keys}
    return v


class Sim:
    def __init__(self, root=ROOT, player='Tester', latency=0.03, viewport=(1280, 720), seed=1, start=True):
        self.root = root
        self.L = lua54.LuaRuntime(unpack_returned_tuples=True)
        self.R = self.L.table()
        self.R.transpile = lambda src, name: transpile(src, name)
        loader = self.L.eval('function(R, code, name) local f, e = load(code, "@" .. name) if not f then error(e) end return f(R) end')
        for f in EMU_FILES:
            loader(self.R, open(os.path.join(HERE, 'rbx', f), encoding='utf-8').read(), 'rbx/' + f)
        self.R.latency = latency
        self.set_viewport(*viewport)
        self.L.execute(f'math.randomseed({seed})')
        self._lua = self.L.eval
        self._load_project()
        if start:
            self.R.startServer()
            self.step_frames(2)
            if player:
                self.player = self.R.addPlayer(player, 1)
                self.step_frames(2)

    # project tree ---------------------------------------------------------
    def _new(self, cls, name, parent, source=None, path=None):
        R = self.R
        inst = R.new(cls)
        inst.Name = name
        if source is not None:
            inst.Source = source
            R.DATA[inst].path = path
        R.setParent(inst, R.DATA[inst], parent)
        return inst

    def _classify(self, fname):
        for suf, cls in (('.server.luau', 'Script'), ('.client.luau', 'LocalScript'), ('.luau', 'ModuleScript')):
            if fname.endswith(suf):
                return fname[: -len(suf)], cls
        return None, None

    def _load_dir(self, name, path, parent):
        init = None
        for cand, cls in (('init.luau', 'ModuleScript'), ('init.server.luau', 'Script'), ('init.client.luau', 'LocalScript')):
            if os.path.exists(os.path.join(path, cand)):
                init = (cand, cls)
                break
        if init:
            rel = os.path.relpath(os.path.join(path, init[0]), self.root)
            node = self._new(init[1], name, parent, open(os.path.join(path, init[0]), encoding='utf-8').read(), rel)
        else:
            node = self._new('Folder', name, parent)
        self._load_children(path, node)
        return node

    def _load_children(self, path, parent):
        for entry in sorted(os.listdir(path)):
            full = os.path.join(path, entry)
            if os.path.isdir(full):
                self._load_dir(entry, full, parent)
            else:
                nm, cls = self._classify(entry)
                if nm and nm != 'init':
                    rel = os.path.relpath(full, self.root)
                    self._new(cls, nm, parent, open(full, encoding='utf-8').read(), rel)

    def _load_project(self):
        R = self.R
        src = os.path.join(self.root, 'src')
        svc = R.services
        self._load_dir('Shared', os.path.join(src, 'shared'), svc.ReplicatedStorage)
        self._load_dir('Server', os.path.join(src, 'server'), svc.ServerScriptService)
        sp = svc.StarterPlayer
        self._load_dir('Client', os.path.join(src, 'client'), sp.StarterPlayerScripts)
        if os.path.isdir(os.path.join(src, 'character')):
            self._load_children(os.path.join(src, 'character'), sp.StarterCharacterScripts)
        # mirror place-file properties written by tools/build_place.py
        svc.Players.CharacterAutoLoads = False
        sp.EnableMouseLockOption = False
        place_props = os.path.join(self.root, 'src', 'place.json')
        if os.path.exists(place_props):
            cfg = json.load(open(place_props))
            for k, v in cfg.get('Lighting', {}).items():
                if isinstance(v, (int, float, bool, str)):
                    try:
                        svc.Lighting[k] = v
                    except Exception:
                        pass

    # stepping -------------------------------------------------------------
    def set_viewport(self, w, h):
        self.R.viewport = self.R.Vector2.new(w, h)

    def step_frames(self, n, dt=1 / 30):
        step = self.R.step
        for _ in range(n):
            step(dt)

    def run(self, seconds, dt=1 / 30, until=None, check_every=0.25):
        frames = int(round(seconds / dt))
        every = max(1, int(round(check_every / dt)))
        for i in range(frames):
            self.R.step(dt)
            if until and i % every == 0 and until():
                return True
        return False

    @property
    def now(self):
        return self.R.now

    # inspection -----------------------------------------------------------
    def errors(self):
        return [x['msg'] for x in (to_py(self.R.errors) or [])]

    def warnings(self):
        return [x['msg'] for x in (to_py(self.R.warnings) or [])]

    def output(self):
        return [x['msg'] for x in (to_py(self.R.output) or [])]

    def clear_logs(self):
        self.R.errors = self.L.table()
        self.R.warnings = self.L.table()
        self.R.output = self.L.table()

    def stats(self):
        return to_py(self.R.stats())

    def server(self, path):
        """require() a ModuleScript as the server, e.g. server('ServerScriptService.Server.Core.S')."""
        return self.R.require('server', self.find(path))

    def client(self, path):
        return self.R.require('client', self.find(path))

    def find(self, path):
        parts = path.split('.')
        obj = self.R.services[parts[0]]
        for p in parts[1:]:
            obj = obj.FindFirstChild(obj, p)
            if obj is None:
                raise KeyError(path)
        return obj

    def lua(self, code):
        return self.L.execute(code)

    def test(self, code, name='test', peer='server', timeout=600, dt=1 / 30):
        """Run a Lua test driver as a coroutine; step simulated time until it finishes."""
        st = self.R.runTest(code, name, peer)
        t = 0
        while not st.done and t < timeout:
            self.R.step(dt)
            t += dt
        if not st.done:
            raise TimeoutError(f'{name} did not finish within {timeout}s of simulated time')
        if not st.ok:
            raise RuntimeError(st.result)
        return to_py(st.result)

    # input ----------------------------------------------------------------
    def key(self, name, down=True):
        self.R.inputKey(name, down)

    def tap(self, name, hold=0.05):
        self.key(name, True)
        self.run(hold)
        self.key(name, False)

    def mouse(self, button='MouseButton1', down=True):
        self.R.inputMouse(button, down)

    def move(self, x, z, relative=True):
        """Drive the local character like the default ControlModule would."""
        ch = self.R.localPlayer.Character
        if ch is None:
            return
        hum = ch.FindFirstChildOfClass(ch, 'Humanoid')
        if hum is not None:
            hum.Move(hum, self.R.Vector3.new(x, 0, z), relative)

    # rendering ------------------------------------------------------------
    def export_scene(self, **opts):
        o = self.L.table()
        for k, v in opts.items():
            o[k] = v
        return to_py(self.R.exportScene(o))

    def export_gui(self):
        pg = self.R.localPlayer.FindFirstChild(self.R.localPlayer, 'PlayerGui')
        return to_py(self.R.exportGui(pg))


if __name__ == '__main__':
    s = Sim()
    s.run(float(sys.argv[1]) if len(sys.argv) > 1 else 5)
    errs = s.errors()
    for e in errs[:20]:
        print(e)
        print('-' * 60)
    print(len(errs), 'errors;', len(s.warnings()), 'warnings')
    print(json.dumps({k: v for k, v in s.stats().items() if k != 'counts'}))
