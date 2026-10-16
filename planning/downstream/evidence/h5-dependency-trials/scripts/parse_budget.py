#!/usr/bin/env python3
"""Pools H5-BUDGET-RAW per-edit stalls (all positions, all passes) per variant/fixture/KB and
prints p50/p95/max and n, plus settle (median/max over the phase lines) and open."""
import re, sys, glob, os, statistics
T = os.path.dirname(os.path.abspath(__file__))
raw = {}; settle = {}; opens = {}
pat_raw = re.compile(r"H5-BUDGET-RAW fixture=(\w+) KB=(\d+) utf8=\d+ utf16=(\d+) mode=full pos=(\w+) stall=\[([^\]]*)\]")
pat_edit = re.compile(r"H5-BUDGET fixture=(\w+) KB=(\d+) .* phase=edit pos=(\w+) .*settle (\d+) ms")
pat_open = re.compile(r"H5-BUDGET fixture=(\w+) KB=(\d+) .* phase=open stall p50 ([\d.]+) .*settle (\d+) ms")
units = {}
for path in sorted(glob.glob(f"{T}/logs/bench-budget-*.log")):
    v = re.search(r"bench-budget-(?:small|1m)-(\w+?)(?:-p\d)?\.log", path).group(1)
    for line in open(path, errors="replace"):
        if m := pat_raw.search(line):
            f, kb, u, pos, vals = m.groups(); units[(f, int(kb))] = int(u)
            raw.setdefault((v, f, int(kb)), []).extend(float(x) for x in vals.split(",") if x.strip())
        elif m := pat_edit.search(line):
            f, kb, pos, s = m.groups(); settle.setdefault((v, f, int(kb)), []).append(float(s))
        elif m := pat_open.search(line):
            f, kb, st, s = m.groups(); opens.setdefault((v, f, int(kb)), []).append((float(st), float(s)))
def pct(xs, q):
    s = sorted(xs); import math; return s[min(len(s)-1, math.ceil((len(s)-1)*q))]
variants = ["stock", "A", "B", "AB"]
print("| fixture | KB (UTF-16 units) | variant | stall p50 | p95 | max | n | edit settle median / max | open stall / settle |")
print("|---|---|---|---|---|---|---|---|---|")
for f, kb in sorted({(k[1], k[2]) for k in raw}, key=lambda x: (x[0], x[1])):
    for v in variants:
        xs = raw.get((v, f, kb))
        if not xs: continue
        st = settle.get((v, f, kb), [0]); op = opens.get((v, f, kb), [])
        o = " / ".join(f"{a:.0f}/{b:.0f}" for a, b in op)
        print(f"| {f} | {kb} ({units[(f,kb)]}) | {v} | {pct(xs,.5):.1f} | {pct(xs,.95):.1f} | {max(xs):.1f} | {len(xs)} | {statistics.median(st):.0f} / {max(st):.0f} | {o} |")
