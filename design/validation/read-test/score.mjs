// Deterministic scoring of the blind read test against D-019 and D-021 (thresholds operationalised in D-022).
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
const n = rows.length, need = Math.ceil(0.75 * n);
const res = rows.map(r => {
  const override = (r.letters_override || '').toUpperCase(); // Y/N only when the facilitator adjudicates a non-standard answer
  const mtS1 = hasMT(r.s1_letters || ''), mtAny = override ? override === 'Y' : mtS1 || hasMT(r.s2_letters || '');
  const all = [r.s1_reminds, r.s1_product, r.s2_reminds, r.s3_reminds, r.notes].join(' | ');
  return { id: r.participant_id, mtS1, mtAny, lineup: (r.lineup_choice || '').toUpperCase() === key[r.participant_id], auto: AUTO.test(all), assoc: all };
});
const c = f => res.filter(f).length;
const logo = c(r => r.mtAny), s1 = c(r => r.mtS1), l16 = c(r => r.lineup), auto = c(r => r.auto);
console.log(`Participants: ${n} (protocol expects 6–8)`);
for (const r of res) console.log(`${r.id}\tM+T logo scale: ${r.mtAny ? 'yes' : 'no '}\t16 px line-up: ${r.lineup ? 'correct' : 'wrong  '}\tautomotive: ${r.auto ? 'YES' : 'no'}`);
console.log(`\nLogo scale, both letters named unprompted (S1 or S2): ${logo}/${n}  (pass needs ${need}; 7 of 8 is the target)  [S1 only: ${s1}/${n}]`);
console.log(`16 px recognition, correct line-up pick: ${l16}/${n}  (pass needs ${need}; chance is 1 in 5)`);
console.log(`Automotive or motorsport associations: ${auto} participant(s)  (3 or more triggers the 8°/10°/12° comparison, D-021)`);
const core = logo >= need && l16 >= need;
const result = n < 6 ? 'INCOMPLETE (fewer than 6 participants)'
  : !core ? 'FAIL (a D-019 threshold was missed)' + (auto >= 3 ? '; the automotive trigger also fired' : '')
  : auto >= 3 ? 'HOLD (letters and recognition pass, but the automotive trigger fired: run the 8°/10°/12° comparison, D-021)' : 'PASS';
console.log(`\nRESULT: ${result}`);
console.log('Review every verbatim association by hand as well; the keyword check only catches the automotive trigger.');
