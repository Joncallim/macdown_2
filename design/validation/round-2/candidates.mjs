// Round-2 proposal geometry. NOT production artwork: nothing here replaces the canonical files in
// design/brand/slant/validation/ until the round-2 tests pass and a decision is recorded.
import { vSmall } from '../../brand/slant/validation/small.mjs';

// 1. Lean variants for the D-021 comparison. Identical construction to design/brand/slant/marks.mjs (wedge cut,
//    diagonals 15, stems 17), with only the angle changed and the same fit-to-86-units rule.
export const slantAt = (angle, key = `a${angle}`) => {
  const t = Math.tan(angle * Math.PI / 180), xmin = 8.5 - 88 * t, xmax = 97 - 16 * t;
  const cx = (xmin + xmax) / 2, s = Math.min(1, 86 / (xmax - xmin)), r = n => +n.toFixed(3);
  return `<defs><clipPath id="lc-${key}"><rect x="0" y="16" width="100" height="72"/></clipPath></defs>
      <g transform="translate(50 52) scale(${r(s)}) translate(${r(-cx)} -52) skewX(${-angle})">
      <g fill="none" stroke="#000" clip-path="url(#lc-${key})"><path stroke-width="17" d="M17 88V16"/><path stroke-width="15" d="M12 7L41 60L70 7" stroke-linejoin="miter"/></g>
      <path fill="#000" d="M57 16H74V88H57ZM34 16H97L89 33H34Z"/></g>`;
};

// 2. Small-size correction: derive the optical masters from the master's own proportions instead of lightening them.
//    Rule: take the master construction on its 100-unit grid (glyph 72 units tall, 16..88), scale it to the target glyph
//    height, snap the top, crossbar and baseline to whole pixel rows, make stems whole pixels, keep diagonals at the
//    master's 15/17 ratio, keep the V vertex at the master's depth (44/72) and keep the M and T joined (no gap).
//    The glyph is centred horizontally in its box (at master proportions it is ~1.44 × its height wide).
const T12 = Math.tan(12 * Math.PI / 180);
const derive = (W, h, top, stem, bar) => { const s = h / 72, m = x => +(x * s).toFixed(3);
  const left = m(17) - stem / 2, right = m(97) + h * T12, dx = +((W - (right - left)) / 2 - left).toFixed(3);
  return { top, base: top + h, leg: m(17), stemX: m(57), stem, bar, barX0: m(34), barX1: m(97), wedge: m(8),
    diag: +(stem * 15 / 17).toFixed(3), vx: m(41), vy: +(top + 44 * s).toFixed(3), dx }; };
export const R2_16 = derive(16, 11, 3, 3, 2);   // 16 px box, 11 px glyph (same box as slant-16.svg)
export const R2_32 = derive(32, 22, 5, 5, 4);   // 32 px box, 22 px glyph (same box as slant-32.svg)
export const r2glyph16 = (fg = '#000') => vSmall(R2_16, fg, fg, 'r2a');
export const r2glyph32 = (fg = '#000') => vSmall(R2_32, fg, fg, 'r2b');
