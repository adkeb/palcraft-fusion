import {readFileSync,writeFileSync} from 'node:fs';
import {decompress as ooz} from '../../palworld-save-toolkit/docs/vendor/ooz-wasm/index.js';
import {decompressSav} from '../../palworld-save-toolkit/docs/js/sav.js';
import {GvasFile,FReader,PALWORLD_TYPE_HINTS} from '../../palworld-save-toolkit/docs/js/gvas.js';
const input=new Uint8Array(readFileSync('work/storage-organize/live-before/Level.sav'));
const {gvas}=await decompressSav(input,ooz), g=GvasFile.read(gvas,PALWORLD_TYPE_HINTS,{}),w=g.properties.worldSaveData.value;
const arr=v=>Array.isArray(v)?v:v?.values??[];
const rows=arr(w.MapObjectSaveData.value).map(o=>{const bytes=o.Model.value.RawData.value.values;const r=new FReader(bytes);const id=String(r.guid()),concrete=String(r.guid()),base=String(r.guid()),group=String(r.guid());const view=new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength);return {id,concrete,base,group,type:o.MapObjectId.value,x:view.getFloat64(104,true),y:view.getFloat64(112,true),z:view.getFloat64(120,true)};});
const base='00000000-0000-4000-8000-000000000011', origin={x:-283726.58202995476,y:198323.07178430783,z:-99.54437182594417};
const near=rows.filter(r=>Math.hypot(r.x-origin.x,r.y-origin.y)<4000);
const candidates=[];
for(let dx=-2400;dx<=2400;dx+=400)for(let dy=-2400;dy<=2400;dy+=400){if(Math.hypot(dx,dy)>2500||Math.hypot(dx,dy)<600)continue;const x=origin.x+dx,y=origin.y+dy;const d=near.map(r=>({...r,d:Math.hypot(r.x-x,r.y-y)})).sort((a,b)=>a.d-b.d);candidates.push({x,y,z:origin.z,nearest:d.slice(0,6),minDistance:d[0]?.d??Infinity});}
candidates.sort((a,b)=>b.minDistance-a.minDistance);
writeFileSync('work/palworld-live/research/agent-build-location.json',JSON.stringify({base,origin,near,candidates:candidates.slice(0,12),warning:'Object-center distance only. Runtime actor bounds and ground support must still be checked.'},null,2));
console.log(JSON.stringify({near:near.length,candidates:candidates.slice(0,3)},null,2));
