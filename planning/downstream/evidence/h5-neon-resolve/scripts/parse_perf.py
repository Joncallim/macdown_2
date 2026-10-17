#!/usr/bin/env python3
# Pools stage C2 benchmark logs: per (group, variant, fixture, KB): stall p50/p95/max (n) and settle median/max.
import re, sys, glob, os, math
L = sys.argv[1]
def pct(v, f):
    s = sorted(v); return s[min(len(s)-1, int(math.ceil((len(s)-1)*f)))] if s else 0
rows = {}
for path in sorted(glob.glob(os.path.join(L, '*-release-perf-*.log'))):
    name = os.path.basename(path)
    m = re.match(r'(\w+)-release-perf-(small|shipped|large|keys|alt-\w+|altkeys-\w+)-(\d+)?', name)
    if not m: m = re.match(r'(\w+)-release-perf-(altkeys-\w+)', name)
    variant, group = m.group(1), m.group(2)
    gkey = group
    if group.startswith('alt-') or group.startswith('altkeys-'):
        variant = group.split('-',1)[1].rsplit('-',1)[0] if group.startswith('alt-') else group.split('-',1)[1]
        gkey = 'alt' if group.startswith('alt-') else 'altkeys'
    text = open(path, errors='replace').read()
    for line in text.splitlines():
        b = re.search(r'H5-BUDGET-RAW fixture=(\w+) KB=(\d+) .*?mode=(\w+).* pos=(\w+) stall=\[([^\]]*)\]', line)
        if b:
            k = (gkey, b.group(1), int(b.group(2)), b.group(3), variant)
            r = rows.setdefault(k, {'stall': [], 'settle': []})
            r['stall'] += [float(x) for x in b.group(5).split(',') if x.strip()]
        s = re.search(r'H5-BUDGET fixture=(\w+) KB=(\d+) .*?mode=(\w+).* phase=edit pos=\w+ .*settle (\d+) ms', line)
        if s:
            k = (gkey, s.group(1), int(s.group(2)), s.group(3), variant)
            rows.setdefault(k, {'stall': [], 'settle': []})['settle'].append(float(s.group(4)))
        kb = re.search(r'H5-BENCH size=(\d+)KB mode=([\w-]+) ', line)
        if kb: cur = (gkey, 'stallFixture-' + kb.group(2), int(kb.group(1)), 'full', variant)
        kr = re.search(r'H5-BENCH per-edit stall ms: \[([^\]]*)\]', line)
        if kr:
            rows.setdefault(cur, {'stall': [], 'settle': []})['stall'] += [float(x) for x in kr.group(1).split(',') if x.strip()]
def fmt(r):
    v = r['stall']; st = r['settle']
    s = '%d/%d/%d (n=%d)' % (pct(v, .5), pct(v, .95), max(v) if v else 0, len(v))
    if st: s += ' settle %d/%d' % (pct(st, .5), max(st))
    return s
keys = sorted(set(k[:4] for k in rows))
for k in keys:
    variants = sorted(set(kk[4] for kk in rows if kk[:4] == k))
    print('| %s | %s | %d | %s | ' % (k[0], k[1], k[2], k[3]) + ' | '.join('%s: %s' % (v, fmt(rows[k + (v,)])) for v in variants) + ' |')
