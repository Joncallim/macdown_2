// Builds round-2 stimuli and the diagnosis sheet. Run: node build.mjs (Playwright + Chromium, as the other design builds).
import { writeFileSync, mkdirSync, readFileSync } from 'node:fs';
import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';
import { slantAt, r2glyph16, r2glyph32 } from './candidates.mjs';
import { vSmall, P16 } from '../../brand/slant/validation/small.mjs';
import { marks as g2 } from '../../brand/gen2/marks.mjs';
import { marks as g3 } from '../../brand/gen3/marks.mjs';
const mono = s => s.replaceAll('"TC"', '"#000"').replaceAll('currentColor', '#000');
mkdirSync('stimuli', { recursive: true });
const b = await chromium.launch(); const p = await b.newPage();
const rasterSVG = async (W, inner, vb = W) => Buffer.from(await p.evaluate(async ({ W, inner, vb }) => {
  const i = new Image(); i.src = 'data:image/svg+xml,' + encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${W}" viewBox="0 0 ${vb} ${vb}">${inner}</svg>`); await i.decode();
  const c = document.createElement('canvas'); c.width = c.height = W; const x = c.getContext('2d'); x.fillStyle = '#fff'; x.fillRect(0, 0, W, W); x.drawImage(i, 0, 0);
  return c.toDataURL('image/png').split(',')[1]; }, { W, inner, vb }), 'base64');
// Tranche A: lean comparison, first-exposure mark at 64 px, monochrome, one angle per panel.
for (const a of [8, 10, 12]) { writeFileSync(`stimuli/lean-${a}.png`, await rasterSVG(64, slantAt(a), 100)); writeFileSync(`stimuli/lean-${a}.svg`, `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">${slantAt(a)}</svg>\n`); }
// Tranche B: candidate small-size glyphs (12° version; rebuild at the winning angle if tranche A moves the lean).
writeFileSync('stimuli/glyph-R2-16.png', await rasterSVG(16, r2glyph16()));
writeFileSync('stimuli/glyph-R2-32.png', await rasterSVG(32, r2glyph32()));
writeFileSync('stimuli/glyph-R2-16.svg', `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">${r2glyph16()}</svg>\n`);
writeFileSync('stimuli/glyph-R2-32.svg', `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">${r2glyph32()}</svg>\n`);
// Decoys: reuse the round-1 16 px decoy rasters unchanged, so round 2 differs from round 1 only in the target.
for (const d of ['d1', 'd2', 'd3', 'd4']) writeFileSync(`stimuli/glyph-${d}.png`, readFileSync(`../read-test/stimuli/glyph-${d}.png`));
// 32 px decoys: the round-1 fitting rule (lean 12°, fit rendered bounds to the target's glyph box), doubled for the 32 px box.
const fit32 = async svg => Buffer.from(await p.evaluate(async svg => {
  const draw = async (W, inner, vb) => { const c = document.createElement('canvas'); c.width = c.height = W; const x = c.getContext('2d');
    const i = new Image(); i.src = 'data:image/svg+xml,' + encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${W}" viewBox="0 0 ${vb} ${vb}">${inner}</svg>`); await i.decode(); x.drawImage(i, 0, 0); return c; };
  const lean = `<g transform="translate(50 52) skewX(-12) translate(-50 -52)">${svg}</g>`;
  const big = await draw(400, `<g transform="translate(100 100)">${lean}</g>`, 300), d = big.getContext('2d').getImageData(0, 0, 400, 400).data;
  let x0 = 400, y0 = 400, x1 = 0, y1 = 0; for (let y = 0; y < 400; y++) for (let q = 0; q < 400; q++) if (d[(y * 400 + q) * 4 + 3] > 40) { x0 = Math.min(x0, q); x1 = Math.max(x1, q); y0 = Math.min(y0, y); y1 = Math.max(y1, y); }
  const u = 300 / 400, bx = x0 * u - 100, by = y0 * u - 100, bw = (x1 - x0 + 1) * u, bh = (y1 - y0 + 1) * u, k = Math.min(29.2 / bw, 22 / bh);
  const c = await draw(32, `<g transform="translate(${(32 - bw * k) / 2 - bx * k} ${5 + (22 - bh * k) / 2 - by * k}) scale(${k})">${lean}</g>`, 32);
  const o = document.createElement('canvas'); o.width = o.height = 32; const ox = o.getContext('2d'); ox.fillStyle = '#fff'; ox.fillRect(0, 0, 32, 32); ox.drawImage(c, 0, 0);
  return o.toDataURL('image/png').split(',')[1]; }, svg), 'base64');
const DECOYS = { d1: mono(g2.crown.svg), d2: mono(g2.gate.svg), d3: mono(g3.caret.svg), d4: mono(g3.soft.svg) };
for (const [k, s] of Object.entries(DECOYS)) writeFileSync(`stimuli/glyph-${k}-32.png`, await fit32(s));
await b.close();
// Facilitator page. Same line-up orders as round 1 (read-test/build.mjs), so only the target differs.
const ORDERS = {
  P1: ['d1', 'd2', 'T', 'd3', 'd4'], P2: ['T', 'd3', 'd4', 'd1', 'd2'], P3: ['d4', 'd1', 'd2', 'd3', 'T'], P4: ['d2', 'T', 'd1', 'd4', 'd3'],
  P5: ['d3', 'd4', 'd2', 'T', 'd1'], P6: ['d4', 'T', 'd3', 'd2', 'd1'], P7: ['d2', 'd1', 'd4', 'd3', 'T'], P8: ['T', 'd4', 'd1', 'd2', 'd3'] };
const src = (g, W) => g === 'T' ? `stimuli/glyph-R2-${W}.png` : `stimuli/glyph-${g}${W === 32 ? '-32' : ''}.png`;
const lineup = (pid, W) => `<div class="row">${ORDERS[pid].map((g, i) => `<figure><img src="${src(g, W)}" width="${W}" height="${W}" alt=""><figcaption>${'ABCDE'[i]}</figcaption></figure>`).join('')}</div>`;
const slides = [...[8, 10, 12].map(a => [`A-L${a}`, `<img src="stimuli/lean-${a}.png" width="64" height="64" alt="">`]),
  ['B-S1', `<img src="stimuli/lean-12.png" width="64" height="64" alt="">`],
  ...Object.keys(ORDERS).map(pid => [`B16-${pid}`, lineup(pid, 16)]), ...Object.keys(ORDERS).map(pid => [`B32-${pid}`, lineup(pid, 32)])];
writeFileSync('stimuli.html', `<!doctype html><meta charset="utf-8"><title>Stimuli</title>
<style>html,body{margin:0;height:100%;background:#fff;font:14px -apple-system,system-ui,sans-serif;color:#222}
.slide{position:fixed;inset:0;display:none;align-items:center;justify-content:center}.slide.on{display:flex}
.row{display:flex;gap:56px}.row figure{margin:0;display:grid;justify-items:center;gap:14px}.row img{image-rendering:pixelated}
.row figcaption{font-size:18px;color:#444}.menu{display:grid;gap:4px;font-size:13px;color:#999}</style>
<div class="slide on" id="menu"><div class="menu"><b>Facilitator menu (never show this screen to a participant)</b>
<span>Tranche A: press A then 8, 0 or 2 for the 8°, 10° or 12° mark (shown 5 s, then blank).</span>
<span>Tranche B: press S for the 64 px mark (5 s), then L and the participant number (1–8) for the 16 px line-up, or K and the number for the 32 px line-up.</span>
<span>Esc returns here.</span></div></div><div class="slide" id="blank"></div>
${slides.map(([c, h]) => `<div class="slide" id="${c}">${h}</div>`).join('\n')}
<script>let t,mode='';const show=id=>{clearTimeout(t);document.querySelectorAll('.slide').forEach(s=>s.classList.toggle('on',s.id===id))};const timed=id=>{show(id);t=setTimeout(()=>show('blank'),5000)};
addEventListener('keydown',e=>{const k=e.key.toLowerCase();if(k==='escape'){mode='';return show('menu')}
 if(k==='a'||k==='l'||k==='k'){mode=k;return}if(k==='s'){mode='';return timed('B-S1')}
 if(mode==='a'&&({'8':1,'0':1,'2':1})[k]){mode='';return timed({'8':'A-L8','0':'A-L10','2':'A-L12'}[k])}
 if((mode==='l'||mode==='k')&&/^[1-8]$/.test(k)){const id=(mode==='l'?'B16-P':'B32-P')+k;mode='';return show(id)}});</script>
`);
writeFileSync('lineup-key.json', JSON.stringify(Object.fromEntries(Object.entries(ORDERS).map(([k, v]) => [k, 'ABCDE'[v.indexOf('T')]])), null, 2) + '\n');
console.log('built round-2 stimuli');
