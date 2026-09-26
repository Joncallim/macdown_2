// Deterministic scoring for round 2. Thresholds are fixed before any round-2 data exists (see PROTOCOL.md).
// Usage: node score.mjs lean responses-lean.csv    |    node score.mjs small responses-small.csv
import { readFileSync } from 'node:fs';
const [mode, file] = process.argv.slice(2);
const csv = readFileSync(file, 'utf8').trim().split(/\r?\n/);
const parse = line => { const out = []; let cur = '', q = false; for (const ch of line) { if (ch === '"') q = !q; else if (ch === ',' && !q) { out.push(cur); cur = ''; } else cur += ch; } out.push(cur); return out.map(s => s.trim()); };
const head = parse(csv[0]); const rows = csv.slice(1).filter(l => l.trim()).map(l => Object.fromEntries(parse(l).map((v, i) => [head[i], v])));
// Copied unchanged from ../read-test/score.mjs so round 2 counts exactly as round 1 did.
const hasMT = s => { const t = ' ' + s.toUpperCase().replace(/[^A-Z]+/g, ' ') + ' ';
  return / MT | TM /.test(t) || ((/ M | EM /.test(t)) && (/ T | TEE /.test(t))); };
const AUTO = /\b(bmw|car|cars|auto|automotive|motor|motors|motorsport|motorsports|racing|race|racer|rally|formula|f1|sport|sports|sporty|speed|vehicle|garage|dealership|tyre|tire|engine)\b/i;
// Diagnostic only (never decides a gate): the narrower "cars or motorsport" reading of D-021, without sport/speed.
const CARS = /\b(bmw|car|cars|auto|automotive|motor|motors|motorsport|motorsports|racing|race|racer|rally|formula|f1|vehicle|garage|dealership|tyre|tire|engine)\b/i;
const N = 8, NEED = 6, TRIGGER = 3;
const valid = rows.filter(r => (r.valid || 'Y').toUpperCase() !== 'N');
const s1 = r => (r.letters_override || '').toUpperCase() ? r.letters_override.toUpperCase() === 'Y' : hasMT(r.s1_letters || '');
const assoc = r => [r.s1_reminds, r.s1_product, r.notes].join(' | ');
if (mode === 'lean') {
  const res = {};
  for (const a of ['8', '10', '12']) {
    const g = valid.filter(r => r.panel === a), n = g.length, mt = g.filter(s1).length, auto = g.filter(r => AUTO.test(assoc(r))).length, cars = g.filter(r => CARS.test(assoc(r))).length;
    const status = n !== N ? `INCOMPLETE (${n} valid; needs exactly ${N})` : mt < NEED ? 'FAIL (M+T reading)' : auto >= TRIGGER ? 'HOLD (automotive trigger)' : 'PASS';
    res[a] = status; console.log(`${a}°: valid ${n}/${N}  S1 M+T ${mt}/${n} (needs ${NEED})  automotive ${auto} (HOLD at ${TRIGGER})  [diagnostic, cars/motorsport only: ${cars}]  → ${status}`);
  }
  const done = Object.values(res).every(s => !s.startsWith('INCOMPLETE')), pass = ['12', '10', '8'].find(a => res[a] === 'PASS');
  console.log(`\nRESULT: ${!done ? 'INCOMPLETE' : pass ? `keep ${pass}° (the largest lean that passes, D-021)` : 'NO ANGLE PASSES: stop and report; do not choose an angle outside 8–12° without an owner decision'}`);
} else if (mode === 'small') {
  const key = JSON.parse(readFileSync(new URL('./lineup-key.json', import.meta.url))), n = valid.length;
  const c16 = valid.filter(r => (r.lineup16_choice || '').toUpperCase() === key[r.participant_id]).length, c32 = valid.filter(r => (r.lineup32_choice || '').toUpperCase() === key[r.participant_id]).length;
  console.log(`Valid participants: ${n} (needs exactly ${N})`);
  console.log(`16 px recognition: ${c16}/${n} (gate, needs ${NEED}; chance 1 in 5)`);
  console.log(`32 px recognition: ${c32}/${n} (needs ${NEED}; gate only if the owner approves it before the test, otherwise diagnostic)`);
  console.log(`S1 M+T (replication, diagnostic): ${valid.filter(s1).length}/${n}`);
  console.log(`\nRESULT: ${n !== N ? `INCOMPLETE (${n} valid)` : c16 >= NEED ? 'PASS (16 px)' : 'FAIL (16 px)'}`);
} else { console.error('mode must be lean or small'); process.exit(1); }
