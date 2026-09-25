// MostlyText Slant refinement. One parameterised construction on a 100-unit grid.
// angle = forward lean (deg); cut = 'parallel' (crossbar end follows the lean) or 'wedge' (gen-3 cut);
// diag = diagonal stroke weight (stems are 17). "TC" marks the T part (two-tone accent).
const slant = (key, { angle, cut, diag }) => {
  const t = Math.tan(angle * Math.PI / 180);
  const barEnd = cut === 'parallel' ? 'H96V33H34Z' : 'H97L89 33H34Z';
  const xmin = 8.5 - 88 * t, xmax = (cut === 'parallel' ? 96 : 97) - 16 * t;
  const cx = (xmin + xmax) / 2, s = Math.min(1, 86 / (xmax - xmin));
  const r = n => +n.toFixed(3);
  return `<defs><clipPath id="lc-${key}"><rect x="0" y="16" width="100" height="72"/></clipPath></defs>
      <g transform="translate(50 52) scale(${r(s)}) translate(${r(-cx)} -52) skewX(${-angle})">
      <g fill="none" stroke="currentColor" clip-path="url(#lc-${key})"><path stroke-width="17" d="M17 88V16"/><path stroke-width="${diag}" d="M12 7L41 60L70 7" stroke-linejoin="miter"/></g>
      <path fill="TC" d="M57 16H74V88H57ZM34 16${barEnd}"/></g>`;
};
const v = (key, name, mech, p) => [key, { name, mech, p, svg: slant(key, p) }];
export const marks = Object.fromEntries([
  v('s8',  'Slant 8°',  '8° lean · wedge cut · diagonals 15', { angle: 8,  cut: 'wedge', diag: 15 }),
  v('s12', 'Slant 12°', '12° lean · wedge cut · diagonals 15', { angle: 12, cut: 'wedge', diag: 15 }),
  v('s15', 'Slant 15°', '15° lean · wedge cut · diagonals 15', { angle: 15, cut: 'wedge', diag: 15 }),
  v('p12', 'Slant 12°, parallel cut', '12° lean · cut parallel to the lean · diagonals 15', { angle: 12, cut: 'parallel', diag: 15 }),
]);
export const svg = (k, fg = '#000') =>
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" style="color:${fg}">${marks[k].svg.replaceAll('"TC"', '"currentColor"')}</svg>`;
