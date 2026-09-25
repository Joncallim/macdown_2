// Deterministic scoring of the blind read test against D-019 and D-021 (rules in D-022 as amended by D-023).
// Usage: node score.mjs responses.csv
import { readFileSync } from 'node:fs';
const key = JSON.parse(readFileSync(new URL('./lineup-key.json', import.meta.url)));
const csv = readFileSync(process.argv[2] || 'responses.csv', 'utf8').trim().split(/\r?\n/);
const parse = line => { const out = []; let cur = '', q = false; for (const ch of line) { if (ch === '"') q = !q; else if (ch === ',' && !q) { out.push(cur); cur = ''; } else cur += ch; } out.push(cur); return out.map(s => s.trim()); };
const head = parse(csv[0]); const rows = csv.slice(1).filter(l => l.trim()).map(l => Object.fromEntries(parse(l).map((v, i) => [head[i], v])));
// "Names both M and T": letter answer contains M and T as letters or as an MT/TM pair. Words like "em"/"tee" also count.
const hasMT = s => { const t = ' ' + s.toUpperCase().replace(/[^A-Z]+/g, ' ') + ' ';
  return / MT | TM /.test(t) || ((/ M | EM /.test(t)) && (/ T | TEE /.test(t))); };
const AUTO = /\b(bmw|car|cars|auto|automotive|motor|motors|motorsport|motorsports|racing|race|racer|rally|formula|f1|sport|sports|sporty|speed|vehicle|garage|dealership|tyre|tire|engine)\b/i;
// Formal test: exactly 8 valid participants. Rows with valid = N (e.g. had seen the design work) are excluded.
const valid = rows.filter(r => (r.valid || 'Y').toUpperCase() !== 'N'), n = valid.length, N = 8, NEED = 6;
const res = valid.map(r => {
  const override = (r.letters_override || '').toUpperCase(); // Y/N only when the facilitator adjudicates a non-standard S1 answer
  const s1 = override ? override === 'Y' : hasMT(r.s1_letters || '');
  const all = [r.s1_reminds, r.s1_product, r.s2_reminds, r.s3_reminds, r.notes].join(' | ');
  return { id: r.participant_id, s1, s2: hasMT(r.s2_letters || ''), lineup: (r.lineup_choice || '').toUpperCase() === key[r.participant_id], auto: AUTO.test(all) };
});
const c = f => res.filter(f).length;
const logo = c(r => r.s1), s2 = c(r => r.s2), l16 = c(r => r.lineup), auto = c(r => r.auto);
console.log(`Valid participants: ${n} of ${rows.length} rows (the formal test needs exactly ${N})`);
for (const r of res) console.log(`${r.id}\tS1 M+T: ${r.s1 ? 'yes' : 'no '}\t16 px line-up: ${r.lineup ? 'correct' : 'wrong  '}\tautomotive: ${r.auto ? 'YES' : 'no'}`);
console.log(`\nGate 1, logo-scale reading (S1 only, 64 px mark, first exposure): ${logo}/${n}  (pass needs ${NEED}/${N}; target 7/${N})`);
console.log(`  Diagnostic only, never counted: S2 icon letters named ${s2}/${n}`);
console.log(`Gate 2, 16 px recognition (correct line-up pick): ${l16}/${n}  (pass needs ${NEED}/${N}; chance is 1 in 5)`);
console.log(`Trigger, automotive or motorsport association: ${auto} participant(s)  (3 or more means HOLD, D-021)`);
const core = logo >= NEED && l16 >= NEED;
const verdict = core ? (auto >= 3 ? 'HOLD (both gates pass, but the automotive trigger fired: run the 8°/10°/12° comparison, D-021)' : 'PASS')
  : 'FAIL (a D-019 gate was missed)' + (auto >= 3 ? '; the automotive trigger also fired' : '');
console.log(`\nRESULT: ${n !== N ? `INCOMPLETE (${n} valid participants; the formal test needs exactly ${N}). Provisional reading: ${verdict}` : verdict}`);
console.log('Review every verbatim association by hand as well; the keyword check only catches the automotive trigger.');
