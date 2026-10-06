import {loadSave} from './verify-lab-client-save.mjs';
import {writeFileSync} from 'node:fs';
import {FReader} from '../../palworld-save-toolkit/docs/js/gvas.js';
function decodeHeader(e){const r=new FReader(e.Model.value.RawData.value.values);const m={id:String(r.guid()),concrete_id:String(r.guid()),base_id:String(r.guid()),guild_id:String(r.guid()),type:e.MapObjectId.value};r.skip(8);m.rotation={x:r.f64(),y:r.f64(),z:r.f64(),w:r.f64()};m.location={x:r.f64(),y:r.f64(),z:r.f64()};return m;}
const input='work/palworld-live/lab/hook-free-rebuild-v4-before-Level.sav';
const s=await loadSave(input),v=s.world.MapObjectSaveData.value,all=Array.isArray(v)?v:v.values;
const types={},examples={},oldBase=[];
for(const e of all){const t=e.MapObjectId.value;if(!/wooden|door/i.test(t))continue;types[t]=(types[t]??0)+1;const m=decodeHeader(e);examples[t]??=m;if(m.base_id==='00000000-0000-4000-8000-000000000031')oldBase.push(m);}
const out={source:input,sha256:s.file_sha256,read_only:true,types,examples,old_base_pieces:oldBase,limitations:'SAV identifiers and transforms, not recipes or current runtime registration.'};
writeFileSync('work/palworld-live/research/house-pieces-from-save.json',JSON.stringify(out,null,2)+'\n');
console.log(JSON.stringify({types,old_base_pieces:oldBase.map(({id,type,location,rotation})=>({id,type,location,rotation}))},null,2));
