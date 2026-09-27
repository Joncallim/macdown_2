import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';
import { marks, svg } from './marks.mjs';
const out = process.argv[2] || 'proof.png';
// 16/32 are rasterised at true pixel size, then shown enlarged (pixelated) to judge real legibility.
const row = k => `<div class=r><div class=big>${svg(k)}</div><div class="big inv">${svg(k,'#fff')}</div>
 ${[16,32].map(s=>`<canvas data-k=${k} data-s=${s} data-fg=#000 data-bg=#fff></canvas><canvas data-k=${k} data-s=${s} data-fg=#fff data-bg=#000></canvas>`).join('')}
 <div class=true>${svg(k)}</div><div class="true s32">${svg(k)}</div><b>${marks[k].name}</b></div>`;
const html = `<style>body{margin:12px;font:14px system-ui;background:#fff}.r{display:flex;gap:14px;align-items:center;margin-bottom:12px}
.big{width:160px;height:160px;background:#fff;border:1px solid #ddd}.inv{background:#000}
canvas{width:96px;height:96px;image-rendering:pixelated;border:1px solid #ddd}.true{width:16px;height:16px}.s32{width:32px;height:32px}</style>
${Object.keys(marks).map(row).join('')}
<script>const S=${JSON.stringify(Object.fromEntries(Object.keys(marks).map(k=>[k,marks[k].svg])))};
Promise.all([...document.querySelectorAll('canvas')].map(c=>new Promise(r=>{const s=+c.dataset.s;c.width=c.height=s;const x=c.getContext('2d');
x.fillStyle=c.dataset.bg;x.fillRect(0,0,s,s);const i=new Image();i.onload=()=>{x.drawImage(i,s*.1,s*.1,s*.8,s*.8);r()};
i.src='data:image/svg+xml,'+encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" style="color:'+c.dataset.fg+'">'+S[c.dataset.k]+'</svg>')}))).then(()=>document.title='done')</script>`;
const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1000, height: 800 } });
await p.setContent(html); await p.waitForFunction(() => document.title === 'done');
await p.screenshot({ path: out, fullPage: true }); await b.close();
