import fs from 'fs'; import pc from 'polygon-clipping';
import {sources, pieces} from './mark.mjs'; import {build} from './wordmark.mjs'; import {flat} from './glyphs.mjs';
const r=v=>+v.toFixed(3);
const bboxP=P=>{const pts=P.flat(2);const xs=pts.map(p=>p[0]),ys=pts.map(p=>p[1]);return [Math.min(...xs),Math.min(...ys),Math.max(...xs),Math.max(...ys)];};
const toD=(P,ox,oy)=>P.map(pg=>pg.map(ring=>'M '+ring.map(p=>r(p[0]-ox)+' '+r(p[1]-oy)).join(' L ')+' Z').join(' ')).join(' ');
const rect=(x0,y0,x1,y1)=>[[[x0,y0],[x1,y0],[x1,y1],[x0,y1],[x0,y0]]];
const mark={};
for (const k of ['master','s32','s16','i16']) { const s=sources[k]; const all=pieces(k); const bb=bboxP(all);
  const closeR=P=>P.map(pg=>pg.map(ring=>[...ring,ring[0]])), strip=P=>P.map(pg=>pg.map(ring=>ring.slice(0,-1)));
  const tee=pc.union(rect(...s.tee),[[...s.bar,s.bar[0]]]).map(pg=>pg.map(ring=>ring.map(s.xf)));
  const m=strip(pc.difference(closeR(all),tee)), t=strip(tee);
  const part=P=>{const b=bboxP(P);return {d:toD(P,b[0],b[1]), ox:r(b[0]-bb[0]), oy:r(b[1]-bb[1])};};
  mark[k]={vb:s.vb, bb:bb.map(r), d:toD(all,bb[0],bb[1]), M:part(m), T:part(t)}; }
// Wordmark groups at FS=100, y-down, origin at text origin on the baseline.
const k=100/2048, CORR={yT:-60, xt:60};
const group=(G,from,to)=>{ const cs=G.glyphs.slice(from,to).flatMap(g=>g.cs); const pts=cs.flatMap(c=>flat([c],24)[0]).map(p=>[p[0]*k,-p[1]*k]);
  const b=[Math.min(...pts.map(p=>p[0])),Math.min(...pts.map(p=>p[1])),Math.max(...pts.map(p=>p[0])),Math.max(...pts.map(p=>p[1]))];
  const d=cs.map(c=>c.map(s=>(s.k==='M'?'M ':s.k==='L'?'L ':'Q ')+s.p.map(q=>r(q[0]*k-b[0])+' '+r(-q[1]*k-b[1])).join(' ')).join(' ')+' Z').join(' ');
  return {d, x:r(b[0]), y:r(b[1]), w:r(b[2]-b[0]), h:r(b[3]-b[1])}; };
const W=build(CORR), RAW=build({comp:false}), ITAL=build({comp:false, slant:false});
const wm={ mostly:group(W,0,6), text:group(W,6,10), all:group(W,0,10) };
const variants={ raw:group(RAW,0,10), italic:group(ITAL,0,10) };
const CAP=1490*k, H=1.15*CAP, mb=mark.master.bb, sc=H/(mb[3]-mb[1]), markW=(mb[2]-mb[0])*sc;
const lock={ cap:r(CAP), xh:r(1118*k), markScale:r(sc), markW:r(markW), markH:r(H), markX:r(-20-markW), markY:r(-H), crossbar:r((33-16)*0.828*sc) };
fs.writeFileSync('geometry.json', JSON.stringify({mark, wm, variants, lock, CORR}));
console.log(JSON.stringify({lock, wm:{mostly:[wm.mostly.x,wm.mostly.y,wm.mostly.w,wm.mostly.h],text:[wm.text.x,wm.text.y,wm.text.w,wm.text.h],all:[wm.all.x,wm.all.y,wm.all.w,wm.all.h]}, dl:{wm:wm.all.d.length, raw:variants.raw.d.length}, marks:Object.fromEntries(Object.entries(mark).map(([k,v])=>[k,{bb:v.bb,M:[v.M.ox,v.M.oy],T:[v.T.ox,v.T.oy]}]))}));
