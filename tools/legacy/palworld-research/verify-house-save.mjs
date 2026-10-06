import {readFileSync,writeFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {loadSave,verifyWorld} from './verify-lab-client-save.mjs';
import {FReader} from '../../palworld-save-toolkit/docs/js/gvas.js';
const root=new URL('../lab/',import.meta.url), plan=JSON.parse(readFileSync(new URL('house-acceptance-evidence.json',root)));
const save=await loadSave(new URL('house-after-Level.sav',root).pathname),w=save.world,arr=v=>Array.isArray(v)?v:v?.values??[];
const models=arr(w.MapObjectSaveData.value),byId=new Map();
for(const e of models){const r=new FReader(e.Model.value.RawData.value.values);byId.set(String(r.guid()),e);}
const guidBytes=id=>{const parts=id.replaceAll('-','').match(/.{8}/g);const b=Buffer.alloc(16);parts.forEach((p,i)=>b.writeUInt32LE(parseInt(p,16),i*4));return b;};
const rows=[];
for(const p of plan.pieces){
 const e=byId.get(p.model_id);assert(e,'Missing '+p.part);assert.equal(e.MapObjectId.value,p.build_id);
 const r=new FReader(e.Model.value.RawData.value.values);const id=String(r.guid()),concrete_id=String(r.guid()),base_id=String(r.guid()),guild_id=String(r.guid());r.skip(8);
 const rotation={X:r.f64(),Y:r.f64(),Z:r.f64(),W:r.f64()},position={X:r.f64(),Y:r.f64(),Z:r.f64()};r.skip(24+16*3);const player_uid=String(r.guid());
 assert.equal(base_id,'00000000-0000-4000-8000-000000000031');assert.equal(guild_id,'00000000-0000-4000-8000-00000000001b');assert.equal(player_uid,'22222222-0000-0000-0000-000000000000');
 const delta=Math.hypot(...['X','Y','Z'].map(k=>position[k]-p.position[k]));assert(delta<2,'Saved position mismatch');
 assert(Math.min(Math.max(...['X','Y','Z','W'].map(k=>Math.abs(rotation[k]-p.rotation[k]))),Math.max(...['X','Y','Z','W'].map(k=>Math.abs(rotation[k]+p.rotation[k]))))<1e-5,'Saved rotation differs');
 const state=new FReader(e.Model.value.BuildProcess.value.RawData.value.values).byte();assert.equal(state,1,'Not completed');
 const connector=Buffer.from(e.Model.value.Connector.value.RawData.value.values),links=plan.pieces.filter(o=>o.model_id!==id&&connector.indexOf(guidBytes(o.model_id))>=0).map(o=>({part:o.part,model_id:o.model_id}));
 rows.push({part:p.part,id,build_id:p.build_id,base_id,guild_id,player_uid,completed:true,position,rotation,concrete_id,connector_bytes:connector.length,connector_guid_references:links});
}
const existing=verifyWorld(w,JSON.parse(readFileSync(new URL('serial-chest-save-expectations.json',root))));assert(existing.ok,'Previous chest/worker verification failed');
const result={ok:true,lab_only:true,save_sha256:save.file_sha256,pieces:rows,existing_chests_verified:existing.chests.length,fixed_worker_saved:existing.workers.every(w=>w.ok),connector_validation:'Exact other-piece GUID byte references in serialized Connector data; no connector or save mutation.',restart_verified:false};
writeFileSync(new URL('house-save-verification.json',root),JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result));
