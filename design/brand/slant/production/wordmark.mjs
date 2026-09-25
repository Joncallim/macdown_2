// Builds the outlined MostlyText wordmark: Inter Tight Bold Italic (9.4°) + 2.6° synthetic slant = 12°,
// with stroke-weight compensation for the synthetic slant and a measured yT correction.
import {font, shape, parse, mapC, toD, flat} from './glyphs.mjs';
const K = Math.tan(2.6*Math.PI/180), UPM=2048, TRACK=-0.025*UPM, W=300;
const f = (dx,dy)=>{ const L=Math.hypot(dx,dy); dx/=L; dy/=L; return 1/Math.hypot(dx+K*dy, dy); }; // thickness factor of an edge under shear
// Offset every edge along its left normal (away from ink for TrueType winding) by w/2*(1/f-1): restores the drawn stroke weight.
const compensate = cs => cs.map(c => { const pts=[]; // flatten structure into point list with on/off flags
  for(const s of c){ if(s.k==='M'||s.k==='L') pts.push({p:s.p[0],on:true}); else if(s.k==='Q'){pts.push({p:s.p[0],on:false});pts.push({p:s.p[1],on:true});} }
  if(pts.length>1 && Math.hypot(pts[0].p[0]-pts.at(-1).p[0],pts[0].p[1]-pts.at(-1).p[1])<1e-6) pts.pop();
  const n=pts.length, line=(a,b)=>{const dx=b[0]-a[0],dy=b[1]-a[1],L=Math.hypot(dx,dy)||1; const nx=-dy/L, ny=dx/L; const d=W/2*(1/f(dx,dy)-1); return {a:[a[0]+nx*d,a[1]+ny*d], v:[dx,dy]};};
  const inter=(l1,l2,fb)=>{ const den=l1.v[0]*l2.v[1]-l1.v[1]*l2.v[0]; if(Math.abs(den)<1e-6*Math.hypot(...l1.v)*Math.hypot(...l2.v)) return fb; const t=((l2.a[0]-l1.a[0])*l2.v[1]-(l2.a[1]-l1.a[1])*l2.v[0])/den; return [l1.a[0]+t*l1.v[0], l1.a[1]+t*l1.v[1]]; };
  const out=pts.map((q,i)=>{ const pr=pts[(i-1+n)%n].p, nx=pts[(i+1)%n].p; const l1=line(pr,q.p), l2=line(q.p,nx);
    const fb=[(l1.a[0]+l2.a[0])/2 + (q.p[0]-pr[0]) , 0]; // unused fallback shape
    const avg=[q.p[0]+(l1.a[0]-pr[0]+l2.a[0]-q.p[0])/2, q.p[1]+(l1.a[1]-pr[1]+l2.a[1]-q.p[1])/2];
    return {p: inter(l1,l2,avg), on:q.on}; });
  const segs=[{k:'M',p:[out[0].p]}]; for(let i=1;i<=n;i++){ const q=out[i%n]; if(!q.on) { segs.push({k:'Q',p:[q.p,out[(i+1)%n].p]}); i++; } else segs.push({k:'L',p:[q.p]}); }
  return segs; });
const shear = cs => mapC(cs, ([x,y])=>[x+K*y, y]);
export const build = ({ comp=true, yT=0, xt=0, slant=true } = {}) => {
  const gl = shape('MostlyText'); let x=0; const out=[];
  gl.forEach((g,i)=>{ let cs=parse(font.glyphToPath(g.gid)); if(comp) cs=compensate(cs); if(slant) cs=shear(cs);
    out.push({ch:g.ch, x, cs: mapC(cs,([a,b])=>[a+x,b])}); x += g.adv + TRACK + (g.ch==='y'?yT:0) + (g.ch==='x'?xt:0); });
  return { glyphs: out, width: x - TRACK };
};
// Whitespace between neighbours: area between facing profiles in the x-height band, depth clamped (letterspacing by equal area).
export const gaps = (glyphs, y0=0, y1=1118, clamp=260) => glyphs.slice(0,-1).map((g,i)=>{ const h=glyphs[i+1];
  const P1=flat(g.cs,24), P2=flat(h.cs,24); let area=0, minG=1e9;
  for(let y=y0+5;y<y1;y+=10){ const xs=(P,side)=>{ let v=side>0?-1e9:1e9; for(const poly of P) for(let k=0;k<poly.length;k++){ const [ax,ay]=poly[k],[bx,by]=poly[(k+1)%poly.length]; if((ay<=y)!==(by<=y)){ const xx=ax+(y-ay)/(by-ay)*(bx-ax); v= side>0?Math.max(v,xx):Math.min(v,xx);} } return v; };
    const r=xs(P1,1), l=xs(P2,-1); if(r<-1e8||l>1e8) { area+=clamp*10; continue; } const gg=l-r; minG=Math.min(minG,gg); area+=Math.min(Math.max(gg,0),clamp)*10; }
  return {pair:g.ch+h.ch, area:Math.round(area/1000), minGap:Math.round(minG)}; });
