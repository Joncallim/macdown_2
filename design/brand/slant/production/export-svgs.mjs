// Writes outlined production SVGs from geometry.json (run build-geometry.mjs first).
import fs from 'fs';
const G = JSON.parse(fs.readFileSync(new URL('./geometry.json', import.meta.url)));
const W = G.wm, L = G.lock, r = v => +v.toFixed(3);
const svg = (w, h, body) => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${r(w)} ${r(h)}" style="color:#11141A">${body}</svg>\n`;
const p = (d, x, y, s = 1) => `<path fill="currentColor" transform="translate(${r(x)} ${r(y)})${s !== 1 ? ` scale(${s})` : ''}" d="${d}"/>`;
const out = new URL('./out/', import.meta.url); fs.mkdirSync(out, { recursive: true });
fs.writeFileSync(new URL('mostlytext-wordmark.svg', out), svg(W.all.w, W.all.h, p(W.all.d, 0, 0)));
const lw = W.all.x + W.all.w - L.markX, lh = W.all.y + W.all.h - L.markY;
fs.writeFileSync(new URL('mostlytext-lockup.svg', out), svg(lw, lh, p(G.mark.master.d, 0, 0, L.markScale) + p(W.all.d, W.all.x - L.markX, W.all.y - L.markY)));
for (const k of ['master', 's32', 's16', 'i16']) { const m = G.mark[k];
  fs.writeFileSync(new URL(`slant-${k}-outline.svg`, out), `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${m.vb} ${m.vb}" style="color:#000">${k === 's16' || k === 'i16' ? '<!-- MICROGLYPH: for rendering at 17 px or smaller ONLY. Never enlarge. -->' : ''}${p(m.d, m.bb[0], m.bb[1])}</svg>\n`); }
console.log('exported to', out.pathname);
