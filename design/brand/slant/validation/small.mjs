// Small-size optical masters for the 12° Slant mark.
// 16 px: hand-drawn pixel grid. 32 px: vector redrawn on a 32-unit grid with pixel-aligned horizontals.
const slantRows = (rows, steps) => rows.map((r, i) => ' '.repeat(steps[i]) + r);
// Upright drawing ('#' ink, '+' 50% ink), then the 12° lean is applied as whole-pixel row shifts.
// Shift per row = round((lastRow - row) * tan 12°).
const lean = rows => slantRows(rows, rows.map((_, i) => Math.round((rows.length - 1 - i) * Math.tan(12 * Math.PI / 180))));
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
// 32-unit master: stems and crossbar 4 units, diagonals 3.4, top at y=5, baseline y=27, lean about the baseline.
export const v32 = (tc = 'currentColor', m = 'currentColor') => `<g transform="translate(${27 * Math.tan(12 * Math.PI / 180) - 1} 0) skewX(-12)">
  <defs><clipPath id="c32"><rect x="-10" y="5" width="60" height="22"/></clipPath></defs>
  <g clip-path="url(#c32)" fill="none" stroke="${m}"><path stroke-width="4" d="M5 27V5"/><path stroke-width="3.4" stroke-linejoin="miter" d="M4 2L11.5 19L19 2"/></g>
  <path fill="${tc}" d="M15 5H19V27H15ZM10.5 5H27.5L25.5 9H10.5Z"/></g>`;

// Small-size vector: same construction as v32, parameterised so each size snaps its horizontals to whole pixels.
// Lean is applied about the baseline, so top, crossbar and baseline edges stay on pixel rows.
export const vSmall = ({ top, base, leg, stemX, stem, bar, barX0, barX1, wedge, diag, vx, vy, dx = 0 }, tc = 'currentColor', m = 'currentColor', id = 'cs') => {
  const t = Math.tan(12 * Math.PI / 180), h = base - top;
  return `<g transform="translate(${dx + base * t} 0) skewX(-12)">
  <defs><clipPath id="${id}"><rect x="-10" y="${top}" width="80" height="${h}"/></clipPath></defs>
  <g clip-path="url(#${id})" fill="none" stroke="${m}"><path stroke-width="${stem}" d="M${leg} ${base}V${top}"/><path stroke-width="${diag}" stroke-linejoin="miter" d="M${leg - stem / 4} ${top - 3 * diag}L${vx} ${vy}L${stemX + stem / 2} ${top - 3 * diag}"/></g>
  <path fill="${tc}" d="M${stemX} ${top}H${stemX + stem}V${base}H${stemX}ZM${barX0} ${top}H${barX1}L${barX1 - wedge} ${top + bar}H${barX0}Z"/></g>`;
};
export const P16 = { top: 3, base: 14, leg: 2.6, stemX: 8, stem: 2, bar: 2, barX0: 5.6, barX1: 14.2, wedge: 1.1, diag: 1.2, vx: 6.2, vy: 11.3, dx: -1.2 };
export const PI16 = { top: 4, base: 12, leg: 3.5, stemX: 7.5, stem: 2, bar: 2, barX0: 5.8, barX1: 12.6, wedge: .9, diag: 1.3, vx: 5.9, vy: 9.2, dx: -.6 };
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
