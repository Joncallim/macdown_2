#!/usr/bin/env python3
"""fold.py tp.xml out.folded [t0_ms t1_ms]
Converts an `xctrace export` time-profile table into folded stacks (root;...;leaf weight_us)
for the Main Thread only. Optional time window (ms since recording start)."""
import sys
import xml.etree.ElementTree as ET

src, dst = sys.argv[1], sys.argv[2]
t0 = float(sys.argv[3]) * 1e6 if len(sys.argv) > 3 else None
t1 = float(sys.argv[4]) * 1e6 if len(sys.argv) > 4 else None
frames, bts, threads, weights, times = {}, {}, {}, {}, {}
agg = {}
nsamples = 0


def frame_name(el):
    if el.get('ref'):
        return frames[el.get('ref')]
    n = el.get('name') or el.get('addr') or '?'
    frames[el.get('id')] = n
    return n


def backtrace(el):
    if el.get('ref'):
        return bts[el.get('ref')]
    names = [frame_name(f) for f in el.findall('frame')]
    bts[el.get('id')] = names
    return names


for ev, el in ET.iterparse(src, events=('end',)):
    if el.tag != 'row':
        continue
    st = el.find('sample-time')
    if st.get('ref'):
        t = times[st.get('ref')]
    else:
        t = int(st.text); times[st.get('id')] = t
    th = el.find('thread')
    if th.get('ref'):
        tn = threads[th.get('ref')]
    else:
        tn = th.get('fmt'); threads[th.get('id')] = tn
    # register nested ids even for non-main rows
    w = el.find('weight')
    if w.get('ref'):
        wv = weights[w.get('ref')]
    else:
        wv = int(w.text); weights[w.get('id')] = wv
    tb = el.find('tagged-backtrace')
    if tb is None:
        tb = el.find('backtrace')
    if tb is not None and tb.tag == 'tagged-backtrace':
        if tb.get('ref'):
            names = bts[tb.get('ref')]
        else:
            names = backtrace(tb.find('backtrace'))
            bts[tb.get('id')] = names
    elif tb is not None:
        names = backtrace(tb)
    else:
        names = ['<no backtrace>']
    el.clear()
    if not tn.startswith('Main Thread'):
        continue
    if t0 is not None and not (t0 <= t <= t1):
        continue
    key = ';'.join(n.replace(';', ':') for n in reversed(names))
    agg[key] = agg.get(key, 0) + wv // 1000
    nsamples += 1

with open(dst, 'w') as f:
    for k, v in sorted(agg.items(), key=lambda kv: -kv[1]):
        f.write(f'{k} {v}\n')
print(f'main-thread samples={nsamples} total_us={sum(agg.values())}')
