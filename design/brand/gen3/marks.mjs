// MostlyText gen-3 marks: Ligature-derived M+T with added energy.
// 100x100 grid. "currentColor" = M part; "TC" = T part (mono → currentColor, two-tone → accent).
export const marks = {
  slant: {
    name: 'Slant', mech: 'Motion: the ligature leans forward like handwriting, and the crossbar ends in an angled cut',
    svg: `<defs><clipPath id="lc-slant"><rect x="0" y="16" width="100" height="72"/></clipPath></defs>
      <g transform="translate(50 52) scale(.86) translate(-50 -52) translate(8.3 0) skewX(-12)">
      <g fill="none" stroke="currentColor" stroke-width="17" clip-path="url(#lc-slant)"><path d="M17 88V16"/><path d="M12 7L41 58L70 7" stroke-linejoin="miter"/></g>
      <path fill="TC" d="M57 16H74V88H57ZM34 16H97L89 33H34Z"/></g>`
  },
  soft: {
    name: 'Soft', mech: 'Personality: one rounded stroke with 01 Fluid’s warmth, carried by the letters themselves',
    svg: `<g fill="none" stroke-width="18" stroke-linecap="round" stroke-linejoin="round">
      <path stroke="currentColor" d="M19 83V24L42 58L65 24"/><path stroke="TC" d="M65 24V83M42 22H88"/></g>`
  },
  contrast: {
    name: 'Contrast', mech: 'Typographic contrast: thick stems and hairline diagonals, like a display serif',
    svg: `<defs><clipPath id="lc-contrast"><rect x="0" y="14" width="100" height="86"/></clipPath></defs>
      <path fill="currentColor" d="M8 14H27V88H8Z"/>
      <path fill="none" stroke="currentColor" stroke-width="9" stroke-linejoin="miter" clip-path="url(#lc-contrast)" d="M18 8L43 68L68 8"/>
      <path fill="TC" d="M59 14H78V88H59ZM34 14H96V30H34Z"/>`
  },
  caret: {
    name: 'Caret', mech: 'Meaning: the shared stem is a text cursor (an I-beam), taller than the M',
    svg: `<defs><clipPath id="lc-caret"><rect x="10" y="27" width="90" height="73"/></clipPath></defs>
      <g fill="none" stroke="currentColor" stroke-width="16" clip-path="url(#lc-caret)"><path d="M18 86V27"/><path d="M14 20L42 64L70 20" stroke-linejoin="miter"/></g>
      <path fill="TC" d="M38 12H96V27H75V82H86V94H50V82H61V27H38Z"/>`
  },
};
export const svg = (k, fg = '#000') =>
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" style="color:${fg}">${marks[k].svg.replaceAll('"TC"', '"currentColor"')}</svg>`;
