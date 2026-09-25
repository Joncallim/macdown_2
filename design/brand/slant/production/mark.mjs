// Flattens the four Slant source SVGs into single filled outlines (strokes expanded, clip applied, transforms baked).
import pc from 'polygon-clipping';
const T12=Math.tan(12*Math.PI/180);
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
const sk=(x,y)=>[x-T12*y,y];
export const sources={
  master:{ vb:100, xf:([x,y])=>{const [a,b]=sk(x,y);return [50+0.828*(a-41.697), 52+0.828*(b-52)];},
    stem:[17,88,16], stemW:17, v:[[12,7],[41,60],[70,7]], vW:15, clip:[16,88], tee:[57,16,74,88], bar:[[34,16],[97,16],[89,33],[34,33]] },
  s32:{ vb:32, xf:([x,y])=>{const [a,b]=sk(x,y);return [a+4.739027165090596,b];},
    stem:[5,27,5], stemW:4, v:[[4,2],[11.5,19],[19,2]], vW:3.4, clip:[5,27], tee:[15,5,19,27], bar:[[10.5,5],[27.5,5],[25.5,9],[10.5,9]] },
  s16:{ vb:16, xf:([x,y])=>{const [a,b]=sk(x,y);return [a+1.7757918633803096,b];},
    stem:[2.6,14,3], stemW:2, v:[[2.1,-0.6],[6.2,11.3],[9,-0.6]], vW:1.2, clip:[3,14], tee:[8,3,10,14], bar:[[5.6,3],[14.2,3],[13.1,5],[5.6,5]] },
  i16:{ vb:16, xf:([x,y])=>{const [a,b]=sk(x,y);return [a+1.950678740040265,b];},
    stem:[3.5,12,4], stemW:2, v:[[3,0.1],[5.9,9.2],[8.5,0.1]], vW:1.3, clip:[4,12], tee:[7.5,4,9.5,12], bar:[[5.8,4],[12.6,4],[11.7,6],[5.8,6]] },
};
const r=v=>+v.toFixed(4);
export const pathOf=k=>{ const s=sources[k]; return build(s).map(pg=>pg.map(ring=>'M'+ring.map(p=>r(p[0])+' '+r(p[1])).join(' L ')+' Z').join(' ')).join(' '); };
export const pieces=k=>{ const s=sources[k]; return build(s); };
