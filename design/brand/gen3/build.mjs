import { writeFileSync } from 'node:fs';
import { marks } from './marks.mjs';
let n=0; const uid = s => { n++; return s.replace(/id="(lc[^"]*)"/g, `id="$1-${n}"`).replace(/url\(#(lc[^)]*)\)/g, `url(#$1-${n})`); };
const mono = k => marks[k].svg.replaceAll('"TC"','"currentColor"');
import { criteria, review, order } from './review.mjs';
const m = (k, cls = '', fill = 'currentColor') =>
  `<svg class="${cls}" viewBox="0 0 100 100" aria-hidden="true" style="color:${fill}">${uid(mono(k))}</svg>`;
// macOS-style icon: squircle approximated by rx=22.5%; mark at 58% of the tile.
const icon = (k, v, cls) => `<svg class="${cls}" viewBox="0 0 100 100" role="img" aria-label="${marks[k].name} ${v} app icon">
  <defs><linearGradient id="bg-${v}-${k}-${cls}" x1="0" y1="0" x2="0" y2="1">${{light:'<stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#E9EDF5"/>',dark:'<stop offset="0" stop-color="#23272F"/><stop offset="1" stop-color="#0D0F13"/>',tint:'<stop offset="0" stop-color="#5E6572"/><stop offset="1" stop-color="#3A3F48"/>'}[v]}</linearGradient>
  <linearGradient id="m-${v}-${k}-${cls}" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="0" y2="100">${{light:'<stop stop-color="#1A1D24"/>',dark:'<stop stop-color="#F4F6FA"/>',tint:'<stop stop-color="#F2F4F8"/>'}[v]}</linearGradient>
  <linearGradient id="fg-${v}-${k}-${cls}" gradientUnits="userSpaceOnUse" x1="10" y1="10" x2="90" y2="90">${{light:'<stop offset="0" stop-color="#2F6BFF"/><stop offset="1" stop-color="#4B4FE6"/>',dark:'<stop offset="0" stop-color="#7EA4FF"/><stop offset="1" stop-color="#9A8CFF"/>',tint:'<stop offset="0" stop-color="#F2F4F8"/><stop offset="1" stop-color="#DADFE7"/>'}[v]}</linearGradient></defs>
  <rect x="4" y="4" width="92" height="92" rx="21" fill="url(#bg-${v}-${k}-${cls})"/>
  ${v==='light'?'<rect x="4.25" y="4.25" width="91.5" height="91.5" rx="20.8" fill="none" stroke="#000" stroke-opacity=".08" stroke-width=".5"/>':''}
  <g transform="translate(21 21) scale(.58)" style="color:url(#fg-${v}-${k}-${cls})">${uid(marks[k].svg).replaceAll('currentColor', `url(#m-${v}-${k}-${cls})`).replaceAll('"TC"', `"url(#fg-${v}-${k}-${cls})"`)}</g></svg>`;
const chip = r => `<span class="rt ${r}">${{g:'Passes',o:'Marginal',w:'Fails'}[r]}</span>`;
const card = k => { const R = review[k]; const fin = R.verdict === 'Finalist';
return `<section class="concept${fin?' fin':''}" id="${k}">
 <header><h2>${marks[k].name}</h2><span class="verdict ${fin?'is-fin':''}">${R.verdict}</span></header>
 <p class="mech">${marks[k].mech}</p>
 <div class="primary"><figure class="tile pos">${m(k,'mk')}<figcaption>Black on white</figcaption></figure>
  <figure class="tile neg">${m(k,'mk','#fff')}<figcaption>White on black</figcaption></figure>
  <figure class="tile icons">${icon(k,'light','ic-lg')}<figcaption>macOS icon, colour</figcaption></figure></div>
 <div class="scales">
  <figure>${icon(k,'light','ic-64')}${icon(k,'dark','ic-64')}${icon(k,'tint','ic-64')}<figcaption>Dock 64 · light / dark / tinted</figcaption></figure>
  <figure><span class="tb">${m(k,'mk20')}<span>Untitled.md</span></span><span class="tb dk">${m(k,'mk20','#fff')}<span>Untitled.md</span></span><figcaption>Toolbar / sidebar 20</figcaption></figure>
  <figure class="px"><canvas data-k="${k}" data-s="32" data-fg="#000" data-bg="#fff" width="32" height="32"></canvas><canvas data-k="${k}" data-s="16" data-fg="#000" data-bg="#fff" width="16" height="16"></canvas><canvas data-k="${k}" data-s="16" data-fg="#fff" data-bg="#000" width="16" height="16"></canvas><figcaption>32 / 16 / 16 inverted, true pixels, enlarged</figcaption></figure>
  <figure class="actual">${m(k,'a32')}${m(k,'a16')}${icon(k,'light','a32')}${icon(k,'light','a16')}<figcaption>Actual size: mark 32 / 16, icon 32 / 16</figcaption></figure>
 </div>
 <div class="lockup">${m(k,'mk28')}<span>MostlyText</span></div>
 <p class="note">${R.note}</p>
</section>`; };
const table = `<div class="tw"><table><thead><tr><th scope="col">Test</th>${order.map(k=>`<th scope="col">${marks[k].name}</th>`).join('')}</tr></thead><tbody>
${criteria.map(([c,l])=>`<tr><th scope="row">${l}</th>${order.map(k=>`<td>${chip(review[k].r[c])}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`;
const tpl = (await import('node:fs')).readFileSync('board.tpl.html','utf8');
writeFileSync('board.html', tpl
  .replace('{{CARDS}}', order.map(card).join(''))
  .replace('{{TABLE}}', table)
  .replace('{{CROWN}}', icon('caret','light','fin')).replace('{{LIGATURE}}', icon('slant','light','fin'))
  .replace('{{MARKS}}', JSON.stringify(Object.fromEntries(Object.keys(marks).map(k=>[k,marks[k].svg.replaceAll('"TC"','"currentColor"')])))));
for (const k of Object.keys(marks)) writeFileSync(`${k}.svg`, `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" style="color:#000">${mono(k)}</svg>\n`);
console.log('built');
