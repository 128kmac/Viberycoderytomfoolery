import re, json, sys
src = open(sys.argv[1], encoding='utf-8').read()
lines = src.split('\n')
# find kit headings
kits = []
cur = None
sec = None
def clean(s):
    s = s.replace('\\', '')
    s = re.sub(r'\[([^\]]*)\]\{[^}]*\}', r'\1', s)
    s = re.sub(r'\*\*|\*', '', s)
    s = re.sub(r'\{#[^}]*\}', '', s)
    return s.strip()
for raw in lines:
    l = clean(raw)
    m = re.match(r'^# (\d{2,3}) (.+?)(?: advanced techniques)?$', l)
    if m and not l.startswith('# Power index'):
        num = int(m.group(1)); name = m.group(2).strip()
        if cur is None or cur['num'] != num:
            cur = {'num': num, 'name': name, 'body': [], 'sections': []}
            kits.append(cur)
        sec = None
        continue
    if cur is None: continue
    if l.startswith('# '):
        # end of kits section
        if not re.match(r'^# \d{2,3} ', l):
            cur = None; continue
    m = re.match(r'^## (.+)$', l)
    if m:
        sec = {'head': m.group(1).strip(), 'lines': []}
        cur['sections'].append(sec)
        continue
    if l == '': continue
    if re.match(r'^\d{2,3} .+ advanced techniques$', l): continue
    if sec is None: cur['body'].append(l)
    else: sec['lines'].append(l)
print(len(kits), file=sys.stderr)
out = []
for k in kits:
    d = {'num': k['num'], 'name': k['name']}
    d['tagline'] = k['body'][0] if k['body'] else ''
    d['identity'] = ' '.join(k['body'][1:])
    d['moves'] = []
    for s in k['sections']:
        h = s['head']; L = s['lines']
        if h.startswith('Passive '):
            d['passive'] = {'name': h[8:], 'text': ' '.join(L)}
        elif re.match(r'^[1-5] ', h):
            mv = {'slot': int(h[0]), 'name': h[2:].replace(' Ultimate','') if h[0]=='5' else h[2:]}
            stat = None; desc=[]; p60=None; counter=None; unstable=None
            for x in L:
                if x.startswith('CD '): stat = x
                elif x.startswith('P60.'): p60 = x[4:].strip()
                elif x.startswith('Counterplay.'): counter = x[12:].strip()
                elif x.startswith('Unstable mutation.'): unstable = x[18:].strip()
                else: desc.append(x)
            st = {}
            if stat:
                for part in stat.split('|'):
                    part = part.strip()
                    mm = re.match(r'^(CD|E|H|W|R|P)\s+(.+)$', part)
                    if mm: st[mm.group(1)] = mm.group(2)
            mv['statline'] = stat
            def num(v):
                if v is None: return None
                mm = re.match(r'^([\d.]+)', v)
                return float(mm.group(1)) if mm else None
            mv['cd'] = num(st.get('CD')); mv['energy'] = num(st.get('E')); mv['heat'] = num(st.get('H'))
            mv['windup'] = num(st.get('W'))
            r = st.get('R','')
            mv['rangeText'] = r
            mv['range'] = num(r) if r and r[0].isdigit() else 0
            mv['desc'] = ' '.join(desc); mv['p60'] = p60; mv['counterplay'] = counter
            if unstable: mv['unstable'] = unstable
            d['moves'].append(mv)
        elif h.startswith('Mutation rules '):
            d['mutation'] = {'name': h[15:], 'text': ' '.join(L)}
        elif h.startswith('Sequence and weakness'):
            d['sequence'] = ' '.join(L)
        elif h.startswith('Team interactions '):
            d['team'] = {'partners': h[18:], 'text': ' '.join(L)}
        else:
            d.setdefault('extra', []).append({'head': h, 'text': ' '.join(L)})
    out.append(d)
json.dump(out, open(sys.argv[2],'w'), indent=1, ensure_ascii=False)
