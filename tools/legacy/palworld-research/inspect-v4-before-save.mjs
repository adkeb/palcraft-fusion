import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {loadSave,decodeMap} from './verify-lab-client-save.mjs';
import {FReader} from '../../palworld-save-toolkit/docs/js/gvas.js';
const path='work/palworld-live/lab/hook-free-rebuild-v4-before-Level.sav';
const save=await loadSave(path),w=save.world,arr=v=>Array.isArray(v)?v:v?.values??[];
assert.equal(save.file_sha256,'01e4c81ffb2b8511380e8ca645108d33d5cd5ba3b0ae921e6679f94bef9ec53d');
const expected=JSON.parse(readFileSync('work/palworld-live/lab/hook-free-rebuild-v4-before-expectations.json'));
const baseline=new Set(expected.chests.map(c=>c.model_id)),containers=new Set(expected.chests.map(c=>c.container_id));
const modelRows=[],near=[],allIds=new Set(),base='00000000-0000-4000-8000-000000000031',manual='00000000-0000-4000-8000-000000000030',pos={x:-308391.0111896781,y:189594.97191406583,z:3330.341836222058};
for(const e of arr(w.MapObjectSaveData.value)){const raw=e.Model.value.RawData.value.values;assert(raw.length>=128);const r=new FReader(raw),id=String(r.guid());allIds.add(id);r.guid();const baseId=String(r.guid());if(/^ItemChest(?:_|$)/.test(e.MapObjectId.value)){r.pos=104;const loc={x:r.f64(),y:r.f64(),z:r.f64()},distance=Math.hypot(loc.x-pos.x,loc.y-pos.y,loc.z-pos.z);if(distance<=300)near.push({id,type:e.MapObjectId.value,base_id:baseId,location:loc,distance_cm:distance});if(baseId===base)modelRows.push(decodeMap(e));}}
const totals={Wood:0,Stone:0},slots=[];
for(const e of arr(w.ItemContainerSaveData.value)){const container=String(e.key.ID.value);if(!containers.has(container))continue;for(const s of arr(e.value.Slots.value)){const r=new FReader(s.RawData.value.values),index=r.i32(),count=r.i32(),item=r.fstring();if(count>0&&(item==='Wood'||item==='Stone')){totals[item]+=count;slots.push({container_id:container,index,item,count});}}}
const verification=JSON.parse(readFileSync('work/palworld-live/lab/hook-free-rebuild-v4-before-save-verification.json'));
const result={lab_only:true,read_only:true,saved_sha256:save.file_sha256,old_base_chest_count:modelRows.length,old_original_chests_all_present:[...baseline].every(id=>modelRows.some(m=>m.id===id)),old_manual_model_present:allIds.has(manual),new_base_chests:modelRows.filter(m=>!baseline.has(m.id)),all_world_chests_within_300cm:near,ordinary_13_material_totals:totals,material_slots:slots,original_identity_chain_verification:verification.ok,zoe_fixed_saved:verification.workers[0].fixedWorkSaved,note:'Pre-v4 saved baseline only; v4 has not been submitted by this parser. Future post-save comparisons must retain this immutable input.',verified_utc:new Date().toISOString()};
writeFileSync('work/palworld-live/lab/hook-free-rebuild-v4-before-baseline.json',JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result,null,2));
