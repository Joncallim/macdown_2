// Builds validation.html: pre-freeze validation of the 12° Slant mark and canonical lockup.
import { writeFileSync, readFileSync } from 'node:fs';
import { marks } from '../marks.mjs';
import { vSmall, P16, PI16, v32 } from './small.mjs';
let n = 0; const u = s => { n++; return s.replace(/id="([^"]+)"/g, `id="$1-${n}"`).replace(/url\(#([^)]+)\)/g, `url(#$1-${n})`); };
const M = (tc = 'currentColor') => marks.s12.svg.replaceAll('"TC"', `"${tc}"`);
// Size-appropriate artwork: ≤17 px uses the 16 px microglyph (never enlarged), 18–40 px the 32 optical master, above that the vector master.
// Metrics (fractions of the box): glyph height, glyph bottom, left and right side bearings.
const MET = { 16: { h: 11 / 16, bot: 14 / 16, l: .4 / 16, r: .66 / 16 }, 32: { h: 22 / 32, bot: 27 / 32, l: 2 / 32, r: .8 / 32 }, 100: { h: .596, bot: .818, l: .07, r: .07 } };
const which = px => px <= 17 ? 16 : px <= 40 ? 32 : 100;
const mark = (px, tc = 'currentColor', cls = '') => {
  const w = which(px), inner = w === 16 ? vSmall(P16, tc, 'currentColor') : w === 32 ? v32(tc, 'currentColor') : M(tc);
  return `<svg viewBox="0 0 ${w} ${w}" width="${px}" height="${px}" class="${cls}" aria-hidden="true">${u(inner)}</svg>`;
};
// App icon: light/dark squircle, ink M, accent T (two-tone applies to the icon only; the lockup is single colour).
const icon = (px, v = 'light') => {
  const bg = v === 'light' ? ['#FFFFFF', '#E7EBF3'] : ['#262A33', '#0D0F13'], m = v === 'light' ? '#14171D' : '#F3F5F9', t = v === 'light' ? '#2F5FE6' : '#7EA4FF';
  const inner = px <= 17 ? `<g transform="translate(0 0)">${u(vSmall(PI16, t, m, 'ci'))}</g>` : px <= 40 ? `<g transform="translate(5.5 5.5) scale(.66)">${u(v32(t, m))}</g>` : `<g transform="translate(19 19) scale(.62)">${u(M(t)).replaceAll('currentColor', m)}</g>`;
  const vb = px <= 17 ? 16 : px <= 40 ? 32 : 100, r = vb * .225, i = vb / 100 * 4;
  return `<svg class="ic" viewBox="0 0 ${vb} ${vb}" width="${px}" height="${px}" role="img" aria-label="MostlyText app icon"><defs><linearGradient id="g${++n}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${bg[0]}"/><stop offset="1" stop-color="${bg[1]}"/></linearGradient></defs>
  <rect x="${i}" y="${i}" width="${vb - 2 * i}" height="${vb - 2 * i}" rx="${r}" fill="url(#g${n})"${v === 'light' ? ` stroke="#000" stroke-opacity=".12" stroke-width="${vb / 200}"` : ''}/>${inner}</svg>`;
};
// Canonical lockup: mark glyph = k × cap height, glyph bottom on the text baseline, gap 0.2 em (see §4).
const CAP = 0.7367; // Inter Tight cap height, measured
const lock = (fs, { style = 'hy', two = false, dark = false, align = 'base', k = 1.15, gap = .2 } = {}) => {
  const want = k * CAP * fs; let w = which(Math.round(want / .6)), m = MET[w];
  const H = k * CAP / m.h, px = Math.round(H * fs); w = which(px); m = MET[w];
  const Hs = k * CAP / m.h, below = (1 - m.bot) * Hs, va = align === 'base' ? -below : -below - (k - 1) * CAP / 2;
  const acc = dark ? '#7EA4FF' : '#2F5FE6';
  const tx = { mech: 'font-style:normal;transform:skewX(-12deg)', it: 'font-style:italic', hy: 'font-style:italic;transform:skewX(-2.63deg)' }[style];
  return `<span class="lk" style="font-size:${fs}px"><span style="display:inline-block;width:${Hs}em;height:${Hs}em;vertical-align:${va}em;margin:0 ${gap - m.r * Hs}em 0 ${-m.l * Hs}em">${mark(Math.round(Hs * fs), 'currentColor', 'fill')}</span><span class="wm" style="${tx}">Mostly${two ? `<span style="color:${acc}">Text</span>` : 'Text'}</span></span>`;
};
const zoom = (id, W, svg, cap) => `<figure class="zf"><canvas class="zc" data-w="${W}" data-svg='${encodeURIComponent(svg)}' width="${W}" height="${W}"></canvas><figcaption>${cap}</figcaption></figure>`;
const master = (W, k, gx) => `<g transform="translate(${gx - 7 * k} ${(W - 59.6 * k) / 2 - 22.2 * k}) scale(${k})">${M('#000').replaceAll('currentColor', '#000')}</g>`;
const tpl = readFileSync('validation.tpl.html', 'utf8');
const html = tpl.replace(/\{\{(\w+)(?::([^}]*))?\}\}/g, (_, key, arg) => {
  const a = arg ? arg.split(',') : [];
  switch (key) {
    case 'MARK': return mark(+a[0], a[1] || 'currentColor');
    case 'ICON': return icon(+a[0], a[1] || 'light');
    case 'LOCK': return lock(+a[0], { style: a[1] || 'hy', two: a[2] === 'two', dark: a[3] === 'dk', align: a[4] || 'base', k: a[5] ? +a[5] : 1.15 });
    case 'Z16M': return zoom(0, 16, master(16, 15 / 86, .5), '16 px, master scaled');
    case 'Z16O': return zoom(0, 16, vSmall(P16, '#000', '#000'), '16 px microglyph');
    case 'Z32M': return zoom(0, 32, master(32, 30 / 86, 1), '32 px, master scaled');
    case 'Z32O': return zoom(0, 32, v32('#000', '#000'), '32 px, optical master');
    case 'ZI16M': return zoom(0, 16, `<rect x=".5" y=".5" width="15" height="15" rx="3.6" fill="#EEF1F6" stroke="#0003"/>` + master(16, 11 / 86, 2.5), 'Icon 16, master scaled');
    case 'ZI16O': return zoom(0, 16, `<rect x=".5" y=".5" width="15" height="15" rx="3.6" fill="#EEF1F6" stroke="#0003"/>` + vSmall(PI16, '#000', '#000'), 'Icon 16 microglyph');
  }
});
writeFileSync('validation.html', html);
// Export production masters.
const MICRO = '<!-- MostlyText Slant microglyph. For rendering at 17 px or smaller ONLY. It is a deliberate simplification of the mark: never enlarge it or use it as general artwork. Use slant-32.svg for 18–40 px and slant-master.svg above that. -->';
const file = (vb, body, note = '') => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${vb} ${vb}" style="color:#000">${note}${body}</svg>\n`;
writeFileSync('slant-16.svg', file(16, vSmall(P16), MICRO));
writeFileSync('slant-32.svg', file(32, v32()));
writeFileSync('slant-icon-16-inner.svg', file(16, vSmall(PI16), MICRO));
writeFileSync('slant-master.svg', file(100, M()));
console.log('built validation', html.length);
