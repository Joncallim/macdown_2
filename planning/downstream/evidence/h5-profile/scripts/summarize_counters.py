#!/usr/bin/env python3
"""summarize_counters.py run.log... : medians of H5TS / H5LL lines after the workload starts
(the `H5PROF open` line), grouped by grammar (syms=203 block, syms=149 inline)."""
import sys, re, statistics as st

GRAMMAR = {'203': 'block', '149': 'inline'}
for path in sys.argv[1:]:
    lines = open(path).read().splitlines()
    try:
        i = next(k for k, l in enumerate(lines) if l.startswith('H5PROF open'))
    except StopIteration:
        print(path, 'no open line'); continue
    ts, ll = {}, {}
    for l in lines[i + 1:]:
        if l.startswith('H5TS '):
            d = dict(kv.split('=', 1) for kv in l[5:].split())
            ts.setdefault(GRAMMAR.get(d['syms'], d['syms']), []).append(d)
        elif l.startswith('H5LL '):
            d = dict(kv.split('=', 1) for kv in l[5:].split())
            key = d['op'] + ':' + d['lang']
            ll.setdefault(key, []).append(d)
    print(f'== {path}')
    for g, rows in ts.items():
        keys = ['ms', 'ranges', 'advance', 'noreuse', 'reuse_bytes', 'bytes', 'select_children', 'compare', 'compare_nodes', 'ptr_skips', 'lexer_goto', 'goto_iters', 'vc1']
        med = {k: st.median(float(r.get(k, 0)) for r in rows) for k in keys}
        print(f'  TS {g:6s} n={len(rows)} ' + ' '.join(f'{k}={med[k]:.6g}' for k in keys))
    for k, rows in ll.items():
        f = 'parse_ms' if 'parse_ms' in rows[0] else 'ms'
        vals = [float(r[f]) for r in rows]
        extra = ''
        if 'changedSet_ms' in rows[0]:
            extra = f' changedSet_ms_med={st.median(float(r["changedSet_ms"]) for r in rows):.3f}'
        if 'injections' in rows[0]:
            extra = f' injections_med={st.median(int(r["injections"]) for r in rows)} set_med={st.median(int(r["set"]) for r in rows)}'
        if 'total' in rows[0]:
            extra = f' new_med={st.median(int(r["new"]) for r in rows)} total_med={st.median(int(r["total"]) for r in rows)}'
        print(f'  LL {k:28s} n={len(rows)} {f}: med={st.median(vals):.3f} sum={sum(vals):.1f}{extra}')
