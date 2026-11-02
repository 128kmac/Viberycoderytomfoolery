#!/usr/bin/env python3
"""Verify kit modules only use members that exist on K, c (cast context), S and K.* sub-modules."""
import os, re, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
core = os.path.join(ROOT, 'src', 'server', 'Core')

def members(path, prefix):
    s = open(path, encoding='utf-8').read()
    out = set(re.findall(r'function ' + prefix + r'[.:](\w+)', s))
    out |= set(re.findall(r'^' + prefix + r'\.(\w+)\s*=', s, re.M))
    return out

K = members(os.path.join(core, 'K.luau'), 'K')
CTX = members(os.path.join(core, 'Cast.luau'), 'Ctx')
CTX_FIELDS = {'f', 'slot', 'def', 'isUlt', 'p60', 'unstable', 'mod', 'interrupted', 'active', 'phase', 'startTime',
              'data', 'recovery', 'pGranted', 'endChannel', 'parent', 'isRecast', 'lockedDir', 'uninterruptible',
              'halfSpeed', 'energyPaid', 'moveFree', 'interruptReason'}
SUB = {
    'K.FX': members(os.path.join(core, 'FX.luau'), 'FX'),
    'K.Status': members(os.path.join(core, 'Status.luau'), 'Status'),
    'K.Combat': members(os.path.join(core, 'Combat.luau'), 'Combat'),
    'K.Hit': members(os.path.join(core, 'Hit.luau'), 'Hit'),
    'S.Objects': members(os.path.join(core, 'Objects.luau'), 'Objects'),
    'S.Proj': members(os.path.join(core, 'Proj.luau'), 'Proj'),
    'S.Summons': members(os.path.join(core, 'Summons.luau'), 'Summons'),
    'S.Fighter': members(os.path.join(core, 'Fighter.luau'), 'Fighter'),
    'S.Cast': members(os.path.join(core, 'Cast.luau'), 'Cast'),
    'S.Zones': members(os.path.join(core, 'Zones.luau'), 'Zones'),
    'S.Status': members(os.path.join(core, 'Status.luau'), 'Status'),
    'K.S.Status': members(os.path.join(core, 'Status.luau'), 'Status'),
    'K.S.Objects': members(os.path.join(core, 'Objects.luau'), 'Objects'),
}
S_MEMBERS = members(os.path.join(core, 'S.luau'), 'S') | {'Objects', 'Proj', 'Summons', 'Fighter', 'Cast', 'Zones',
    'Status', 'Combat', 'Hit', 'FX', 'K', 'Kits', 'Match', 'Arena', 'Bots', 'fighters', 'byModel', 'synergy',
    'folders', 'Config', 'Util', 'Shared', 'arenaBounds', 'listeners', 'nextId'}
ZONE = members(os.path.join(core, 'Zones.luau'), 'Zone')
problems = 0
kits_dir = os.path.join(ROOT, 'src', 'server', 'Kits')
for fn in sorted(os.listdir(kits_dir)):
    if not fn.endswith('.luau') or fn == 'init.luau':
        continue
    src = open(os.path.join(kits_dir, fn), encoding='utf-8').read()
    code = re.sub(r'--[^\n]*', '', src)
    code = re.sub(r'"(?:\\.|[^"\\])*"', '""', code)
    for m in re.finditer(r'(?<![\w.])K\.(\w+)(?:\.(\w+))?', code):
        name, sub = m.group(1), m.group(2)
        if name not in K and name not in ('S', 'M', 'FX', 'Status', 'Combat', 'Hit', 'Config'):
            print(f'{fn}: unknown K.{name}'); problems += 1
        if sub and f'K.{name}' in SUB and sub not in SUB[f'K.{name}']:
            print(f'{fn}: unknown K.{name}.{sub}'); problems += 1
    for m in re.finditer(r'(?<![\w.])K\.S\.(\w+)(?:\.(\w+))?', code):
        name, sub = m.group(1), m.group(2)
        if name not in S_MEMBERS:
            print(f'{fn}: unknown K.S.{name}'); problems += 1
        if sub and f'S.{name}' in SUB and sub not in SUB[f'S.{name}']:
            print(f'{fn}: unknown K.S.{name}.{sub}'); problems += 1
    for m in re.finditer(r'(?<![\w.])S\.(\w+)(?:\.(\w+))?', code):
        name, sub = m.group(1), m.group(2)
        if name not in S_MEMBERS:
            print(f'{fn}: unknown S.{name}'); problems += 1
        if sub and f'S.{name}' in SUB and sub not in SUB[f'S.{name}']:
            print(f'{fn}: unknown S.{name}.{sub}'); problems += 1
    for m in re.finditer(r'(?<![\w.])(c2?|cc|rc|parent):(\w+)\(', code):
        if m.group(2) not in CTX:
            print(f'{fn}: unknown ctx method {m.group(1)}:{m.group(2)}'); problems += 1
    for m in re.finditer(r'(?<![\w.])(z|zone|zz|bank):(\w+)\(', code):
        if m.group(2) not in ZONE:
            print(f'{fn}: unknown zone method :{m.group(2)}'); problems += 1
print(f'kit API check: {problems} problem(s)')
sys.exit(1 if problems else 0)
