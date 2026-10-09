import { chromium } from 'playwright-core'; import fs from 'fs'; import {pathOf} from './mark.mjs';
const SRC=new URL('../validation/', import.meta.url).pathname;
const files={master:'slant-master.svg', s32:'slant-32.svg', s16:'slant-16.svg', i16:'slant-icon-16-inner.svg'};
const vb={master:100,s32:32,s16:16,i16:16};
const b=await chromium.launch({executablePath:process.env.CHROMIUM_PATH||'/opt/pw-browsers/chromium-1194/chrome-linux/chrome'}); const pg=await b.newPage();
const out={};
for (const k of Object.keys(files)) { const src=fs.readFileSync(SRC+files[k],'utf8'); const mine=`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${vb[k]} ${vb[k]}"><path fill="#000" fill-rule="nonzero" d="${pathOf(k)}"/></svg>`;
  const sizes = k==='master' ? [64,128,512,1024] : [vb[k], vb[k]*4, 256];
  out[k] = await pg.evaluate(async ({src,mine,sizes})=>{ const load=s=>new Promise(r=>{const i=new Image(); i.onload=()=>r(i); i.src='data:image/svg+xml;charset=utf-8,'+encodeURIComponent(s);});
    const [a,bb]=[await load(src), await load(mine)]; const res=[];
    for(const W of sizes){ const px=img=>{const c=new OffscreenCanvas(W,W),x=c.getContext('2d');x.fillStyle='#fff';x.fillRect(0,0,W,W);x.drawImage(img,0,0,W,W);return x.getImageData(0,0,W,W).data;};
      const A=px(a),B=px(bb); let sum=0,max=0,n=0,cov=0; for(let i=0;i<A.length;i+=4){const d=Math.abs(A[i]-B[i]); sum+=d; max=Math.max(max,d); if(d>32) n++; cov+=255-A[i];}
      res.push({W, meanAbs:+(sum/(W*W)).toFixed(3), max, pxOver32:n, inkA:+(cov/255).toFixed(1)}); } return res; }, {src,mine,sizes}); }
console.log(JSON.stringify(out,null,1)); await b.close();
