// Builds the blind read-test stimuli. Output: stimuli/*.png and stimuli.html (no product name anywhere).
// Run: node build.mjs   (needs Playwright + Chromium, as used by the other design builds)
import { writeFileSync, mkdirSync } from 'node:fs';
import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';
import { marks as slant } from '../../brand/slant/marks.mjs';
import { marks as g2 } from '../../brand/gen2/marks.mjs';
import { marks as g3 } from '../../brand/gen3/marks.mjs';
import { vSmall, P16 } from '../../brand/slant/validation/small.mjs';
const mono = s => s.replaceAll('"TC"', '"#000"').replaceAll('currentColor', '#000');
const TARGET = vSmall(P16, '#000', '#000', 'mg');
// Decoys: other two-letter MT constructions from the rejected exploration rounds, so the letters alone can't identify the target.
const DECOYS = { d1: mono(g2.crown.svg), d2: mono(g2.gate.svg), d3: mono(g3.caret.svg), d4: mono(g3.soft.svg) };
// Fixed line-up order per participant (positions A–E). Target position rotates so no position is favoured.
export const ORDERS = {
  P1: ['d1', 'd2', 'T', 'd3', 'd4'], P2: ['T', 'd3', 'd4', 'd1', 'd2'], P3: ['d4', 'd1', 'd2', 'd3', 'T'], P4: ['d2', 'T', 'd1', 'd4', 'd3'],
  P5: ['d3', 'd4', 'd2', 'T', 'd1'], P6: ['d4', 'T', 'd3', 'd2', 'd1'], P7: ['d2', 'd1', 'd4', 'd3', 'T'], P8: ['T', 'd4', 'd1', 'd2', 'd3'],
};
mkdirSync('stimuli', { recursive: true });
const b = await chromium.launch(); const p = await b.newPage(); await p.setContent('<canvas id=c></canvas><svg id=m width=100 height=100></svg>');
// Rasterise each glyph at true 16 px. Decoys get the same 12° lean as the target, so "the slanted one" can't identify it,
// and are fitted by their rendered pixel bounds to the target's glyph box (15 × 11 px), so size can't give it away either.
const raster = async (svg, fit) => Buffer.from(await p.evaluate(async ({ svg, fit }) => {
  const draw = async (W, inner, vb) => { const c = document.createElement('canvas'); c.width = c.height = W; const x = c.getContext('2d');
    const i = new Image(); i.src = 'data:image/svg+xml,' + encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${W}" viewBox="0 0 ${vb} ${vb}">${inner}</svg>`); await i.decode(); x.drawImage(i, 0, 0); return c; };
  let inner = svg, vb = 16;
  if (fit) {
    const lean = `<g transform="translate(50 52) skewX(-12) translate(-50 -52)">${svg}</g>`;
    const big = await draw(400, `<g transform="translate(100 100)">${lean}</g>`, 300), d = big.getContext('2d').getImageData(0, 0, 400, 400).data;
    let x0 = 400, y0 = 400, x1 = 0, y1 = 0; for (let y = 0; y < 400; y++) for (let q = 0; q < 400; q++) if (d[(y * 400 + q) * 4 + 3] > 40) { x0 = Math.min(x0, q); x1 = Math.max(x1, q); y0 = Math.min(y0, y); y1 = Math.max(y1, y); }
    const u = 300 / 400; const bx = x0 * u - 100, by = y0 * u - 100, bw = (x1 - x0 + 1) * u, bh = (y1 - y0 + 1) * u;
    const k = Math.min(15 / bw, 11 / bh); inner = `<g transform="translate(${(16 - bw * k) / 2 - bx * k} ${3 + (11 - bh * k) / 2 - by * k}) scale(${k})">${lean}</g>`;
  }
  const c = await draw(16, inner, vb), x = c.getContext('2d'), o = document.createElement('canvas'); o.width = o.height = 16; const ox = o.getContext('2d');
  ox.fillStyle = '#fff'; ox.fillRect(0, 0, 16, 16); ox.drawImage(c, 0, 0); return o.toDataURL('image/png').split(',')[1]; }, { svg, fit }), 'base64');
writeFileSync('stimuli/glyph-T.png', await raster(TARGET, false));
for (const [k, s] of Object.entries(DECOYS)) writeFileSync(`stimuli/glyph-${k}.png`, await raster(s, true));
await b.close();
const S1 = `<svg viewBox="0 0 100 100" width="64" height="64">${mono(slant.s12.svg)}</svg>`;
const S2 = `<svg viewBox="0 0 100 100" width="128" height="128"><defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#E7EBF3"/></linearGradient></defs>
 <rect x="4" y="4" width="92" height="92" rx="21" fill="url(#bg)" stroke="#000" stroke-opacity=".12" stroke-width=".5"/><g transform="translate(19 19) scale(.62)">${slant.s12.svg.replaceAll('"TC"', '"#2F5FE6"').replaceAll('currentColor', '#14171D')}</g></svg>`;
const S3 = `<div class="hdr"><svg viewBox="0 0 100 100" width="40" height="40">${mono(slant.s12.svg)}</svg><nav><span>Features</span><span>Help</span><span class="btn">Download</span></nav></div>`;
const lineup = pid => `<div class="row">${ORDERS[pid].map((g, i) => `<figure><img src="stimuli/glyph-${g}.png" width="16" height="16" alt=""><figcaption>${'ABCDE'[i]}</figcaption></figure>`).join('')}</div>`;
const slides = [['S1', S1, 5], ['S2', S2, 5], ['S3', S3, 5], ...Object.keys(ORDERS).map(pid => [`L-${pid}`, lineup(pid), 0])];
writeFileSync('stimuli.html', `<!doctype html><meta charset="utf-8"><title>Stimuli</title>
<style>html,body{margin:0;height:100%;background:#fff;font:14px -apple-system,system-ui,sans-serif;color:#222}
.slide{position:fixed;inset:0;display:none;align-items:center;justify-content:center}.slide.on{display:flex}
.code{position:fixed;right:10px;bottom:8px;font-size:11px;color:#bbb}
.hdr{display:flex;align-items:center;justify-content:space-between;width:min(900px,90vw);padding:14px 22px;border:1px solid #e3e6ec;border-radius:12px}
.hdr nav{display:flex;gap:22px;align-items:center}.btn{background:#111;color:#fff;padding:7px 14px;border-radius:8px}
.row{display:flex;gap:56px}.row figure{margin:0;display:grid;justify-items:center;gap:14px}.row img{image-rendering:pixelated}
.row figcaption{font-size:18px;color:#444}
.menu{display:grid;gap:6px;font-size:13px;color:#999;text-align:left}</style>
<div class="slide on" id="menu"><div class="menu"><b>Facilitator menu</b>${slides.map(([c], i) => `<span>${i + 1}. ${c}</span>`).join('')}<span>Press a number key 1–3 for S1–S3 (shown 5 s, then blank), or L then the participant number for a line-up. Esc returns here.</span></div></div>
<div class="slide" id="blank"></div>
${slides.map(([c, h]) => `<div class="slide" id="${c}">${h}</div>`).join('\n')}
<div class="code" id="code"></div>
<script>let t,wantL=false;const show=id=>{clearTimeout(t);document.querySelectorAll('.slide').forEach(s=>s.classList.toggle('on',s.id===id));document.getElementById('code').textContent=id==='menu'||id==='blank'?'':id};
addEventListener('keydown',e=>{if(e.key==='Escape'){wantL=false;return show('menu')}
 if(e.key==='l'||e.key==='L'){wantL=true;return}
 if(wantL&&/^[1-8]$/.test(e.key)){wantL=false;return show('L-P'+e.key)}
 const n={'1':'S1','2':'S2','3':'S3'}[e.key];if(n){show(n);t=setTimeout(()=>show('blank'),5000)}});</script>
`);
writeFileSync('lineup-key.json', JSON.stringify(Object.fromEntries(Object.entries(ORDERS).map(([k, v]) => [k, 'ABCDE'[v.indexOf('T')]])), null, 2) + '\n');
console.log('built read-test stimuli');
