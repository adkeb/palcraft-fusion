import {readFileSync,writeFileSync} from 'node:fs';
import {loadSave} from './verify-lab-client-save.mjs';
import {FReader} from '../../palworld-save-toolkit/docs/js/gvas.js';
function modelHeader(e){const b=e.Model.value.RawData.value.values;if(b.length<128)throw Error('short model');const r=new FReader(b);const o={id:String(r.guid()),concrete_id:String(r.guid()),base_id:String(r.guid()),guild_id:String(r.guid()),type:e.MapObjectId.value};r.skip(8);o.rotation={x:r.f64(),y:r.f64(),z:r.f64(),w:r.f64()};o.location={x:r.f64(),y:r.f64(),z:r.f64()};return o;}
const input=process.argv[2]??'work/palworld-live/lab/client-acceptance-worker-Level.sav';
const output=process.argv[3]??'work/palworld-live/lab/client-manual-nearby-saved-buildings.json';
const {world:w,file_sha256}=await loadSave(input);const arr=v=>Array.isArray(v)?v:v?.values??[];
const p={x:-308391.0111896781,y:189594.97191406583,z:3330.341836222058},base='00000000-0000-4000-8000-000000000031',rows=[],failures=[];
for(const e of arr(w.MapObjectSaveData.value)){try{const m=modelHeader(e);if(m.base_id===base){const dx=m.location.x-p.x,dy=m.location.y-p.y,dz=m.location.z-p.z;rows.push({...m,distance_xy:Math.hypot(dx,dy),distance_3d:Math.hypot(dx,dy,dz),delta_z:dz});}}catch(e){failures.push(e.message);}}
rows.sort((a,b)=>a.distance_3d-b.distance_3d);
const r={lab_only:true,read_only:true,source_save_sha256:file_sha256,manual_location:p,base_id:base,saved_candidates_only:true,live_registration_verified:false,support_relationship_verified:false,
 warning:'Saved transform centers are candidate evidence only. Revalidate live manager registration before any native getter; proximity never proves physical support or terrain contact.',
 nearest_10:rows.filter(x=>!/^CommonDrop|^Damagable|^PickupItem/i.test(x.type)).slice(0,10),nearest_all_types_10:rows.slice(0,10),nearest_foundation_floor_10:rows.filter(x=>/foundation|floor/i.test(x.type)).slice(0,10),base_model_count:rows.length,undecoded_models:failures.length};
writeFileSync(output,JSON.stringify(r,null,2)+'\n');console.log(JSON.stringify(r,null,2));
