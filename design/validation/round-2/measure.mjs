// Measures how closely each small glyph matches the master rendered at the same size, and writes diagnosis.png.
// Run: node measure.mjs   (after node build.mjs)
import { readFileSync, writeFileSync } from 'node:fs';
import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';
import { slantAt } from './candidates.mjs';
const V = '../../brand/slant/validation/', inner = f => readFileSync(V + f, 'utf8').replace(/^<svg[^>]*>/, '').replace(/<\/svg>\s*$/, '');
const b64 = f => readFileSync(f).toString('base64');
const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1180, height: 700 } });
const gray = (src, W) => p.evaluate(async ({ src, W }) => { const i = new Image(); i.src = src; await i.decode(); const c = document.createElement('canvas'); c.width = c.height = W;
  const x = c.getContext('2d'); x.fillStyle = '#fff'; x.fillRect(0, 0, W, W); x.drawImage(i, 0, 0, W, W); return Array.from(x.getImageData(0, 0, W, W).data).filter((_, j) => j % 4 === 0).map(v => 1 - v / 255); }, { src, W });
const svgSrc = (W, s, vb = W) => 'data:image/svg+xml,' + encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${W}" viewBox="0 0 ${vb} ${vb}">${s}</svg>`);
const png = f => 'data:image/png;base64,' + b64(f);
const corr = (a, c) => { const ma = a.reduce((s, v) => s + v) / a.length, mc = c.reduce((s, v) => s + v) / c.length; let n = 0, da = 0, dc = 0; a.forEach((v, i) => { n += (v - ma) * (c[i] - mc); da += (v - ma) ** 2; dc += (c[i] - mc) ** 2; }); return n / Math.sqrt(da * dc); };
const blur = (a, W) => a.map((_, i) => { const x = i % W, y = (i / W) | 0; let s = 0, n = 0; for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) { const X = x + dx, Y = y + dy; if (X >= 0 && X < W && Y >= 0 && Y < W) { s += a[Y * W + X]; n++; } } return s / n; });
const fitMaster = (h, top, left) => { const k = h / 59.616; return `<g transform="translate(${left - 7.025 * k} ${top - 22.192 * k}) scale(${k})" style="color:#000">${inner('slant-master.svg')}</g>`; };
const out = [];
for (const [W, h, top, left, rows] of [
  [16, 11, 3, 0.4, [['Round-1 target (slant-16.svg)', png('../read-test/stimuli/glyph-T.png')], ['d1 Crown', png('stimuli/glyph-d1.png')], ['d2 Gate', png('stimuli/glyph-d2.png')], ['d3 Caret', png('stimuli/glyph-d3.png')], ['d4 Soft', png('stimuli/glyph-d4.png')], ['Round-2 candidate R2-16', png('stimuli/glyph-R2-16.png')]]],
  [32, 22, 5, 2, [['Current slant-32.svg', svgSrc(32, `<g style="color:#000">${inner('slant-32.svg')}</g>`)], ['d4 Soft', png('stimuli/glyph-d4-32.png')], ['Round-2 candidate R2-32', png('stimuli/glyph-R2-32.png')]]]]) {
  // Reference: the master at the same glyph height, rendered at sub-pixel offsets; each glyph is scored at its best alignment.
  const refs = []; for (let ox = -2; ox <= 2; ox += 0.25) for (let oy = -1; oy <= 1; oy += 0.25) refs.push(await gray(svgSrc(W, fitMaster(h, top + oy, left + ox)), W));
  const inkM = refs[0].reduce((s, v) => s + v);
  out.push(`\n${W} px (reference: master at the same ${h} px glyph height, best of ${refs.length} sub-pixel alignments; ink ${inkM.toFixed(0)} px)`);
  for (const [n, src] of rows) { const g = await gray(src, W), gb = blur(g, W);
    const m1 = Math.max(...refs.map(M => corr(g, M))), m2 = Math.max(...refs.map(M => corr(gb, blur(M, W))));
    out.push(`  ${n.padEnd(32)} ink ${(100 * g.reduce((s, v) => s + v) / inkM).toFixed(0).padStart(3)}%  match ${m1.toFixed(3)}  match at viewing blur ${m2.toFixed(3)}`); }
}
// Sanity: the 12° lean stimulus must be pixel-identical to the production master.
const L12 = await gray(svgSrc(256, slantAt(12), 100), 256), P = await gray(svgSrc(256, `<g style="color:#000">${inner('slant-master.svg')}</g>`, 100), 256);
out.push(`\nlean-12 stimulus vs slant-master.svg at 256 px: max pixel difference ${Math.round(255 * Math.max(...L12.map((v, i) => Math.abs(v - P[i]))))}/255`);
writeFileSync('measurements.txt', out.join('\n').trim() + '\n'); console.log(out.join('\n'));
// Diagnosis sheet
const z = (src, W, S) => `<img src="${src}" width="${S}" height="${S}" style="image-rendering:pixelated;border:1px solid #ddd;background:#fff">`;
const fig = (img, cap) => `<figure style="margin:0;display:grid;gap:4px;justify-items:center;font:12px system-ui">${img}<figcaption style="max-width:150px;text-align:center">${cap}</figcaption></figure>`;
await p.setContent(`<body style="margin:14px;display:grid;gap:18px;font:13px system-ui;color:#222">
<b>Round-1 16 px line-up, true pixels ×8 — and the large mark it had to match</b>
<div style="display:flex;gap:14px;align-items:end">${fig(`<img src="${svgSrc(128, `<g style="color:#000">${inner('slant-master.svg')}</g>`, 100)}" width=128>`, 'S1 mark (seen first)')}${fig(z(png('../read-test/stimuli/glyph-T.png'), 16, 128), 'Target: slant-16.svg (0/8)')}${fig(z(png('stimuli/glyph-d4.png'), 16, 128), 'd4 Soft (8/8 chose it)')}${fig(z(svgSrc(16, fitMaster(11, 3, 0.4)), 16, 128), 'Master scaled to 16 (reference)')}${fig(z(png('stimuli/glyph-R2-16.png'), 16, 128), 'Round-2 candidate R2-16')}</div>
<b>32 px (the 16 pt Retina size), ×4</b>
<div style="display:flex;gap:14px;align-items:end">${fig(z(svgSrc(32, `<g style="color:#000">${inner('slant-32.svg')}</g>`), 32, 128), 'Current slant-32.svg')}${fig(z(svgSrc(32, fitMaster(22, 5, 2)), 32, 128), 'Master scaled to 32')}${fig(z(png('stimuli/glyph-R2-32.png'), 32, 128), 'Round-2 candidate R2-32')}${fig(z(png('stimuli/glyph-d4-32.png'), 32, 128), 'd4 Soft at 32')}</div>
<b>Lean comparison stimuli (64 px, one angle per panel)</b>
<div style="display:flex;gap:24px;align-items:end">${[8, 10, 12].map(a => fig(`<img src="${png(`stimuli/lean-${a}.png`)}" width=64 height=64>`, `${a}°`)).join('')}${[8, 10, 12].map(a => fig(`<img src="data:image/svg+xml;base64,${b64(`stimuli/lean-${a}.svg`)}" width=160>`, `${a}° enlarged`)).join('')}</div></body>`);
await p.screenshot({ path: 'diagnosis.png', fullPage: true }); await b.close();
