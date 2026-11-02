#!/usr/bin/env python3
"""Build EBProxima.rbxlx (an XML Roblox place) from src/ without needing Rojo.

Mirrors Rojo's file conventions:
  name.server.luau -> Script, name.client.luau -> LocalScript, name.luau -> ModuleScript,
  folder/init.luau -> the folder becomes a ModuleScript, other folders -> Folder.
Open the generated file in Roblox Studio (File > Open from File) and press Play.
"""
import os, sys
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ref = [0]

def nref():
    ref[0] += 1
    return f'RBX{ref[0]:08X}'

def cdata(s):
    return '<![CDATA[' + s.replace(']]>', ']]]]><![CDATA[>') + ']]>'

def script_item(cls, name, source, children=''):
    return (f'<Item class="{cls}" referent="{nref()}"><Properties>'
            f'<string name="Name">{escape(name)}</string>'
            f'<ProtectedString name="Source">{cdata(source)}</ProtectedString>'
            f'</Properties>{children}</Item>')

def folder_item(name, children):
    return (f'<Item class="Folder" referent="{nref()}"><Properties>'
            f'<string name="Name">{escape(name)}</string></Properties>{children}</Item>')

def classify(fname):
    for suffix, cls in (('.server.luau', 'Script'), ('.client.luau', 'LocalScript'), ('.luau', 'ModuleScript'),
                        ('.server.lua', 'Script'), ('.client.lua', 'LocalScript'), ('.lua', 'ModuleScript')):
        if fname.endswith(suffix):
            return fname[: -len(suffix)], cls
    return None, None

def build_children(path):
    out = []
    for entry in sorted(os.listdir(path)):
        full = os.path.join(path, entry)
        if os.path.isdir(full):
            out.append(build_dir(entry, full))
        else:
            name, cls = classify(entry)
            if name and name != 'init':
                out.append(script_item(cls, name, open(full, encoding='utf-8').read()))
    return ''.join(out)

def build_dir(name, path):
    init = None
    for cand, cls in (('init.luau', 'ModuleScript'), ('init.server.luau', 'Script'), ('init.client.luau', 'LocalScript')):
        if os.path.exists(os.path.join(path, cand)):
            init = (cand, cls)
            break
    children = build_children(path)
    if init:
        return script_item(init[1], name, open(os.path.join(path, init[0]), encoding='utf-8').read(), children)
    return folder_item(name, children)

def service(cls, inner, props=''):
    return (f'<Item class="{cls}" referent="{nref()}"><Properties><string name="Name">{cls}</string>{props}'
            f'</Properties>{inner}</Item>')

def main():
    src = os.path.join(ROOT, 'src')
    out = os.path.join(ROOT, sys.argv[1] if len(sys.argv) > 1 else 'EBProxima.rbxlx')
    parts = ['<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
             'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
             'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">']
    parts.append(service('Workspace', '', '<bool name="StreamingEnabled">false</bool>'))
    parts.append(service('Lighting', ''))
    parts.append(service('ReplicatedStorage', build_dir('Shared', os.path.join(src, 'shared'))))
    parts.append(service('ServerScriptService', build_dir('Server', os.path.join(src, 'server'))))
    starter_player = (
        f'<Item class="StarterPlayerScripts" referent="{nref()}"><Properties><string name="Name">StarterPlayerScripts</string></Properties>'
        + build_dir('Client', os.path.join(src, 'client')) + '</Item>'
        + f'<Item class="StarterCharacterScripts" referent="{nref()}"><Properties><string name="Name">StarterCharacterScripts</string></Properties>'
        + build_children(os.path.join(src, 'character')) + '</Item>')
    parts.append(service('StarterPlayer', starter_player, '<bool name="EnableMouseLockOption">false</bool>'))
    parts.append(service('Players', '', '<bool name="CharacterAutoLoads">false</bool>'))
    parts.append('</roblox>')
    open(out, 'w', encoding='utf-8').write('\n'.join(parts))
    print(f'wrote {out} ({os.path.getsize(out)//1024} KB, {ref[0]} instances)')

if __name__ == '__main__':
    main()
