// MostlyText gen-2 M+T marks. 100x100 design grid, single colour (currentColor).
export const marks = {
  arch: {
    name: 'Arch', mech: 'Shared strokes — T crossbar is the shoulders of an m',
    svg: `<g fill="none" stroke="currentColor" stroke-width="17" stroke-linejoin="round">
      <path d="M24 62V37a12 12 0 0 1 12-12h28a12 12 0 0 1 12 12v25"/><path d="M50 25v63"/></g>`
  },
  crown: {
    name: 'Crown', mech: 'Negative space — a capital M crown cut into a T',
    svg: `<path fill="currentColor" stroke="currentColor" stroke-width="4" stroke-linejoin="round"
      d="M12 14H34L50 30L66 14H88V60H72V44H59V88H41V44H28V60H12Z"/>`
  },
  ligature: {
    name: 'Ligature', mech: 'Shared stem — M’s right leg is the T’s stem',
    svg: `<defs><clipPath id="lc"><rect x="10" y="14" width="84" height="74"/></clipPath></defs>
      <g fill="none" stroke="currentColor" stroke-width="16" clip-path="url(#lc)">
      <path d="M18 88V14"/><path d="M14 8L42 56L70 8" stroke-linejoin="miter"/><path d="M66 14V88"/><path d="M38 22H94"/></g>`
  },
  gate: {
    name: 'Gate', mech: 'Outer structure — an M built from a T’s frame',
    svg: `<g fill="currentColor"><path d="M12 14H88V88H72V30H28V88H12Z"/><path d="M42 30H58V68L50 78L42 68Z"/></g>`
  },
};
export const svg = (k, fg = '#000') =>
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" style="color:${fg}">${marks[k].svg}</svg>`;
