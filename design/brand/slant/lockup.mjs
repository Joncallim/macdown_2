// Builds lockup.html: Slant mark (12°) + leaning MostlyText wordmark options.
import { writeFileSync } from 'node:fs';
import { marks } from './marks.mjs';
let n = 0;
const mark = (tc) => { n++; return `<svg class="m" viewBox="0 0 100 100" aria-hidden="true">${marks.s12.svg
  .replaceAll('lc-s12', `lc-s12-${n}`).replaceAll('"TC"', `"${tc}"`)}</svg>`; };
const variants = [
  ['a', 'Bold, 12° oblique', 'Weight 700, slanted to the mark’s exact angle.', 'wm w7 ob', false],
  ['b', 'Extra bold, 12° oblique', 'Weight 800, closer to the mark’s heavy strokes.', 'wm w8 ob', false],
  ['c', 'Bold, 12° oblique, two-tone', '“Text” takes the accent, echoing the coloured T in the mark.', 'wm w7 ob', true],
  ['u', 'Upright (reference)', 'The previous recommendation, for comparison.', 'wm w7', false],
];
const lock = (cls, two, theme) => {
  const ink = theme === 'dk' ? '#F4F6FA' : '#11141A', acc = theme === 'dk' ? '#7EA4FF' : '#2F5FE6';
  return `<span class="lk" style="color:${ink}">${mark(acc)}<span class="${cls}">Mostly${two ? `<span style="color:${acc}">Text</span>` : 'Text'}</span></span>`;
};
const row = ([id, name, desc, cls, two]) => `<section class="v" id="${id}">
 <header><h2>${name}</h2><p>${desc}</p></header>
 <div class="stage lt big">${lock(cls, two, 'lt')}</div>
 <div class="stage dk big">${lock(cls, two, 'dk')}</div>
 <div class="smalls"><div class="stage lt s24">${lock(cls, two, 'lt')}</div><div class="stage lt s14">${lock(cls, two, 'lt')}</div>
  <div class="stage dk s24">${lock(cls, two, 'dk')}</div><div class="stage dk s14">${lock(cls, two, 'dk')}</div></div>
</section>`;
const tpl = (await import('node:fs')).readFileSync('lockup.tpl.html', 'utf8');
writeFileSync('lockup.html', tpl.replace('{{ROWS}}', variants.map(row).join('')).replaceAll('{{MARK}}', mark('#2F5FE6')));
console.log('built lockup');
