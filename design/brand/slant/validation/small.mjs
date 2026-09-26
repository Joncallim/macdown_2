// Small-size optical masters for the Slant mark, production lean D-027 (10°).
// Both sizes are derived mechanically from the master's own proportions (D-026/D-027's correction
// principle), not hand-lightened: scale the master construction to the target glyph height, snap the
// top/crossbar/baseline to whole pixel rows, make stems whole pixels, keep diagonals at the master's
// 15/17 ratio, keep the V vertex at the master's depth (44/72), and keep the M and T fused (no gap).
// This replaces the pre-D-027 hand-lightened P16/PI16/v32, which traded mass for an open V counter and
// drifted from the master (design/validation/round-2/DIAGNOSIS.md).
export const ANGLE = 10;
const slantRows = (rows, steps) => rows.map((r, i) => ' '.repeat(steps[i]) + r);
// Upright drawing ('#' ink, '+' 50% ink), then the lean is applied as whole-pixel row shifts.
// Shift per row = round((lastRow - row) * tan ANGLE). Historical/unused (D-014: 1-bit pixel grids rejected).
const lean = rows => slantRows(rows, rows.map((_, i) => Math.round((rows.length - 1 - i) * Math.tan(ANGLE * Math.PI / 180))));
export const px16 = lean([
  '###.#########',
  '############.',
  '##.#..###....',
  '##.##.###....',
  '##..#####....',
  '##..##.##....',
  '##..##.##....',
  '##..+..##....',
  '##.....##....',
  '##.....##....',
  '##.....##....',
]);
// Inside a 16 px app icon the mark gets ~11 px: drop the V counter, keep the peak notch and the wedge.
export const icon16 = lean([
  '##.#######',
  '#########.',
  '##.#.###..',
  '##.##.##..',
  '##.#..##..',
  '##....##..',
  '##....##..',
  '##....##..',
]);
export const gridSVG = (rows, { size = 16, x0 = 0, y0 = 0, fill = 'currentColor' } = {}) =>
  rows.flatMap((r, y) => [...r].map((ch, x) => ch === '#' || ch === '+'
    ? `<rect x="${x0 + x}" y="${y0 + y}" width="1" height="1" fill="${fill}"${ch === '+' ? ' fill-opacity=".5"' : ''}/>` : '')).join('');

// Small-size vector: derive the construction mechanically from the master (D-027), parameterised so each
// size snaps its horizontals to whole pixels. Lean is applied about the baseline, so top, crossbar and
// baseline edges stay on pixel rows.
export const vSmall = ({ top, base, leg, stemX, stem, bar, barX0, barX1, wedge, diag, vx, vy, dx = 0 }, tc = 'currentColor', m = 'currentColor', id = 'cs') => {
  const t = Math.tan(ANGLE * Math.PI / 180), h = base - top;
  return `<g transform="translate(${dx + base * t} 0) skewX(${-ANGLE})">
  <defs><clipPath id="${id}"><rect x="-10" y="${top}" width="80" height="${h}"/></clipPath></defs>
  <g clip-path="url(#${id})" fill="none" stroke="${m}"><path stroke-width="${stem}" d="M${leg} ${base}V${top}"/><path stroke-width="${diag}" stroke-linejoin="miter" d="M${leg - stem / 4} ${top - 3 * diag}L${vx} ${vy}L${stemX + stem / 2} ${top - 3 * diag}"/></g>
  <path fill="${tc}" d="M${stemX} ${top}H${stemX + stem}V${base}H${stemX}ZM${barX0} ${top}H${barX1}L${barX1 - wedge} ${top + bar}H${barX0}Z"/></g>`;
};

// Derive a small-size construction from the master's own proportions (D-026/D-027).
// W = glyph box (px), h = glyph height (px), top = box inset (px), stem = whole-pixel stem width,
// bar = whole-pixel crossbar band height. stem/bar are chosen as round(masterValue * h/72), matching the
// round-2 candidates validated in Icon Composer (design/evidence/2026-09-26/icon-art/README.md).
const T = Math.tan(ANGLE * Math.PI / 180);
const derive = (W, h, top, stem, bar) => { const s = h / 72, m = x => +(x * s).toFixed(3);
  const left = m(17) - stem / 2, right = m(97) + h * T, dx = +((W - (right - left)) / 2 - left).toFixed(3);
  return { top, base: top + h, leg: m(17), stemX: m(57), stem, bar, barX0: m(34), barX1: m(97), wedge: m(8),
    diag: +(stem * 15 / 17).toFixed(3), vx: m(41), vy: +(top + 44 * s).toFixed(3), dx }; };

// 16 px box, 11 px glyph — matches the round-2 R2_16 candidate validated 2026-09-26.
export const P16 = derive(16, 11, 3, 3, 2);
// 16 px box, 8 px glyph — the icon-16-inner detail layer, more inset than P16; same derivation, smaller
// glyph height, bar held at the same 2 px floor as P16 for visibility at this size.
export const PI16 = derive(16, 8, 4, 2, 2);
// 32 px box, 22 px glyph — matches the round-2 R2_32 candidate validated 2026-09-26.
export const P32 = derive(32, 22, 5, 5, 4);
export const v32 = (tc = 'currentColor', m = 'currentColor') => vSmall(P32, tc, m, 'v32');

export const px16b = lean([
  '###.#########',
  '###.########.',
  '##.#...##....',
  '##.#..###....',
  '##..#.###....',
  '##..##.##....',
  '##...#.##....',
  '##.....##....',
  '##.....##....',
  '##.....##....',
  '##.....##....',
]);
