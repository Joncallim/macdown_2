// Flattens the four Slant source SVGs into single filled outlines (strokes expanded, clip applied, transforms baked).
// Production lean D-027: 10°. s32/s16/i16 are derived mechanically from the master (D-026/D-027's correction
// principle, matching design/brand/slant/validation/small.mjs), not hand-lightened.
import pc from 'polygon-clipping';
const ANGLE = 10;
const T10 = Math.tan(ANGLE * Math.PI / 180);
const rect=(x0,y0,x1,y1)=>[[[x0,y0],[x1,y0],[x1,y1],[x0,y1],[x0,y0]]];
// Stroked 3-point polyline with miter join and butt caps (miter ratio < 4 in all sources, so SVG draws a full miter).
const vStroke=(A,B,C,w)=>{ const off=(P,Q,s)=>{const dx=Q[0]-P[0],dy=Q[1]-P[1],L=Math.hypot(dx,dy);return [-dy/L*w/2*s,dx/L*w/2*s];};
  const add=(p,o)=>[p[0]+o[0],p[1]+o[1]]; const inter=(p1,p2,q1,q2)=>{const d=(p2[0]-p1[0])*(q2[1]-q1[1])-(p2[1]-p1[1])*(q2[0]-q1[0]);const t=((q1[0]-p1[0])*(q2[1]-q1[1])-(q1[1]-p1[1])*(q2[0]-q1[0]))/d;return [p1[0]+t*(p2[0]-p1[0]),p1[1]+t*(p2[1]-p1[1])];};
  const side=s=>{ const o1=off(A,B,s), o2=off(B,C,s); return [add(A,o1), inter(add(A,o1),add(B,o1),add(B,o2),add(C,o2)), add(C,o2)]; };
  const L=side(1), R=side(-1); return [[...L, ...R.reverse(), L[0]]]; };
const poly=pts=>[[...pts,pts[0]]];
// Generic construction shared by all four sources.
const build=({stem, stemW, v, vW, clip, tee, bar, xf})=>{
  const V=pc.intersection(vStroke(...v,vW), rect(-1000,clip[0],1000,clip[1]));
  const S=pc.intersection(rect(stem[0]-stemW/2,stem[2],stem[0]+stemW/2,stem[1]), rect(-1000,clip[0],1000,clip[1]));
  const U=pc.union(V,S,rect(...tee),poly(bar));
  return U.map(pg=>pg.map(ring=>ring.slice(0,-1).map(xf)));
};
const sk=(x,y)=>[x-T10*y,y];
// Master centring/scale, reproducing design/brand/slant/marks.mjs's slant() at ANGLE=10 (wedge cut):
// xmin = 8.5 - 88*tan(ANGLE), xmax = 97 - 16*tan(ANGLE), cx = midpoint, s = min(1, 86/(xmax-xmin)).
const MCX = 43.58099700315982, MS = 0.8498398030294638;
export const sources={
  master:{ vb:100, xf:([x,y])=>{const [a,b]=sk(x,y);return [50+MS*(a-MCX), 52+MS*(b-52)];},
    stem:[17,88,16], stemW:17, v:[[12,7],[41,60],[70,7]], vW:15, clip:[16,88], tee:[57,16,74,88], bar:[[34,16],[97,16],[89,33],[34,33]] },
  // Derived from the master (design/validation/round-2/candidates.mjs derive(), 32px box, 22px glyph — matches
  // the R2_32 candidate validated in Icon Composer 2026-09-26).
  s32:{ vb:32, xf:([x,y])=>{const [a,b]=sk(x,y);return [a+2.654828479128555,b];},
    stem:[5.194,27,5], stemW:5, v:[[3.944,-8.236],[12.528,18.444],[19.917,-8.236]], vW:4.412, clip:[5,27], tee:[17.417,5,22.417,27], bar:[[10.389,5],[29.639,5],[27.195,9],[10.389,9]] },
  // Derived from the master, 16px box, 11px glyph — matches the R2_16 candidate validated 2026-09-26.
  s16:{ vb:16, xf:([x,y])=>{const [a,b]=sk(x,y);return [a+1.5405777299185095,b];},
    stem:[2.597,14,3], stemW:3, v:[[1.847,-4.941],[6.264,9.722],[10.208,-4.941]], vW:2.647, clip:[3,14], tee:[8.708,3,11.708,14], bar:[[5.194,3],[14.819,3],[13.597,5],[5.194,5]] },
  // Derived from the master, 16px box, 8px glyph (the icon-16-inner detail layer): same derivation, smaller
  // glyph height, bar held at the same 2px floor as s16 for visibility at this size.
  i16:{ vb:16, xf:([x,y])=>{const [a,b]=sk(x,y);return [a+3.5769237685015796,b];},
    stem:[1.889,12,4], stemW:2, v:[[1.389,-1.295],[4.556,8.889],[7.333,-1.295]], vW:1.765, clip:[4,12], tee:[6.333,4,8.333,12], bar:[[3.778,4],[10.778,4],[9.889,6],[3.778,6]] },
};
const r=v=>+v.toFixed(4);
export const pathOf=k=>{ const s=sources[k]; return build(s).map(pg=>pg.map(ring=>'M'+ring.map(p=>r(p[0])+' '+r(p[1])).join(' L ')+' Z').join(' ')).join(' '); };
export const pieces=k=>{ const s=sources[k]; return build(s); };
