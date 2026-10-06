// Reads local evidence only. Does not write or serialize any game save.
import {readFileSync,writeFileSync,existsSync} from 'node:fs';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {loadSave,decodeMap} from './verify-lab-client-save.mjs';
import {FReader} from '../../palworld-save-toolkit/docs/js/gvas.js';
const dir=process.argv[2]??'work/palworld-live/lab/rebuild-crash-20261004';
const sourceSaveWrittenUTC=process.argv[3]??null;
const arr=v=>Array.isArray(v)?v:v?.values??[],zero='00000000-0000-0000-0000-000000000000';
const report=JSON.parse(readFileSync(dir+'/report.json')),intent=JSON.parse(readFileSync(dir+'/intent.json'));
assert(report.lab_only===true&&intent.lab_only===true);assert.equal(report.nonce,intent.nonce);assert.equal(report.native_call_attempts,1);
const input=dir+'/last-saved-Level.sav',saved=await loadSave(input),w=saved.world;
const hash=x=>createHash('sha256').update(readFileSync(x)).digest('hex');
const beforeSHA=hash(input),before=report.before.materials,after=report.materials_immediate_after;
assert(before.ok&&after.ok&&before.base_id===after.base_id&&before.guild_id===after.guild_id);
function normalize(s){if(!s||s.count===0)return{item:'None',count:0,dynamicGuid:zero,dynamicWorldGuid:zero};return{item:s.item,count:s.count,dynamicGuid:s.dynamicGuid,dynamicWorldGuid:s.dynamicWorldGuid};}
function same(a,b){return JSON.stringify(normalize(a))===JSON.stringify(normalize(b));}
function slotsOf(c){const slots=new Map(),capacity=c.value.SlotNum.value;assert(Number.isInteger(capacity)&&capacity>=0&&capacity<=1000);
 for(const x of arr(c.value.Slots.value)){const b=x.RawData.value.values;assert(b instanceof Uint8Array&&b.length>=12);const r=new FReader(b),index=r.i32(),count=r.i32();assert(index>=0&&index<capacity&&!slots.has(index)&&count>=0);const item=r.fstring();assert(r.pos+32<=b.length);const dynamicWorldGuid=String(r.guid()),dynamicGuid=String(r.guid());slots.set(index,{index,count,item,dynamicWorldGuid,dynamicGuid});}return{capacity,slots};}
const totals={saved:{Wood:0,Stone:0},before:before.totals,immediate_after:after.totals},ordinary={saved:{Wood:0,Stone:0},before:{Wood:0,Stone:0},immediate_after:{Wood:0,Stone:0}};
const scope=[];
for(const c of before.containers){const matches=arr(w.ItemContainerSaveData.value).filter(x=>String(x.key.ID.value)===c.id);assert.equal(matches.length,1,'unique expected container '+c.id);const s=slotsOf(matches[0]);assert.equal(s.capacity,c.capacity);const a=after.containers.find(x=>x.id===c.id);assert(a);const diffs=[];
 for(let i=0;i<c.capacity;i++){const savedSlot=normalize(s.slots.get(i)),b=normalize(c.slots.find(x=>x.index===i)),im=normalize(a.slots.find(x=>x.index===i));if(!same(savedSlot,b)||!same(savedSlot,im))diffs.push({index:i,saved:savedSlot,live_before:b,live_immediate_after:im,matches_before:same(savedSlot,b),matches_immediate_after:same(savedSlot,im)});
  if(savedSlot.item in totals.saved)totals.saved[savedSlot.item]+=savedSlot.count;
  if(c.kind==='ordinary_chest')for(const[k,v]of[['saved',savedSlot],['before',b],['immediate_after',im]])if(v.item in ordinary[k])ordinary[k][v.item]+=v.count;
 }
 scope.push({container_id:c.id,kind:c.kind,capacity:c.capacity,all_slots_equal_live_before:diffs.every(d=>d.matches_before),all_slots_equal_live_immediate_after:diffs.every(d=>d.matches_immediate_after),differences:diffs});
}
assert.equal(scope.filter(c=>c.kind==='ordinary_chest').length,13);
const source_slots=report.immediate_material_delta.changed_slots.map(d=>{const c=scope.find(c=>c.container_id===d.container_id),diff=c.differences.find(s=>s.index===d.index);assert(diff,'Expected debit slot differs from at least one live sample');return{container_id:d.container_id,index:d.index,...diff};});
const discovery=JSON.parse(readFileSync('work/palworld-live/lab/oldbase-after-manual-demolition.json'));
const known=new Set(discovery.chests.map(c=>c.model_instance_id_live));
const oldManual='00000000-0000-4000-8000-000000000030',target=report.before.fixed_request.location;
const chestModels=[],allWorldChestsNearAttempt=[],allModelIDs=new Set();
for(const e of arr(w.MapObjectSaveData.value)){const b=e.Model.value.RawData.value.values;assert(b instanceof Uint8Array&&b.length>=64);const r=new FReader(b),id=String(r.guid());assert(!allModelIDs.has(id),'duplicate map model');allModelIDs.add(id);r.guid();const base=String(r.guid());if(/^ItemChest(?:_|$)/.test(e.MapObjectId.value)){assert(b.length>=128);const mr=new FReader(b);mr.skip(104);const location={x:mr.f64(),y:mr.f64(),z:mr.f64()};const distance=Math.hypot(location.x-target.X,location.y-target.Y,location.z-target.Z);if(distance<=300)allWorldChestsNearAttempt.push({id,base_id:base,type:e.MapObjectId.value,location,distance_from_attempt_cm:distance});}if(base===before.base_id&&/^ItemChest(?:_|$)/.test(e.MapObjectId.value)){const m=decodeMap(e);const dist=Math.hypot(m.location.x-target.X,m.location.y-target.Y,m.location.z-target.Z);chestModels.push({...m,distance_from_attempt_cm:dist,known_after_manual_demolition:known.has(m.id)});}}
const submitted=report.submitted_unix*1000,sourceTime=sourceSaveWrittenUTC?Date.parse(sourceSaveWrittenUTC):null;assert(sourceTime===null||Number.isFinite(sourceTime));
const result={lab_only:true,read_only:true,save_parse_ok:true,input:{path:saved.path,sha256:saved.file_sha256,bytes:saved.bytes,local_file_mtime_utc:saved.mtime_utc,local_mtime_is_not_assumed_to_be_save_time:true,source_save_written_utc:sourceSaveWrittenUTC,source_timestamp_basis:sourceSaveWrittenUTC?'caller-supplied original server LastWriteTimeUtc':'not supplied',parser_warning_count:saved.parser_warning_count,parser_warnings:saved.parser_warnings},
 evidence:{nonce:report.nonce,submitted_unix:report.submitted_unix,submitted_utc:new Date(submitted).toISOString(),source_save_precedes_submission:sourceTime===null?null:sourceTime<submitted,seconds_submission_after_save:sourceTime===null?null:(submitted-sourceTime)/1000,native_call_returned:report.native_call_returned,immediate_recipe_cost_matches:report.immediate_material_delta.exact_recipe_cost,model_events:report.model_events,observations:report.observations},
 material_scope:{ordinary_chests:13,player_common_containers:1,world_wide_invariance_claimed:false,totals,ordinary_chest_totals:ordinary,source_slots,containers:scope,other_saved_vs_live_before_differences:scope.flatMap(c=>c.differences.filter(d=>!d.matches_before).map(d=>({container_id:c.container_id,kind:c.kind,...d})))},
 models:{old_manual_model_id:oldManual,old_manual_model_present:allModelIDs.has(oldManual),baseline_observed_utc:discovery.observed_utc,saved_base_chest_count:chestModels.length,wooden_itemchest_count:chestModels.filter(x=>x.type==='ItemChest').length,new_relative_to_demolition_discovery:chestModels.filter(x=>!x.known_after_manual_demolition),near_attempt_within_300cm:chestModels.filter(x=>x.distance_from_attempt_cm<=300),saved_base_chests:chestModels,all_world_chests_near_attempt_within_300cm:allWorldChestsNearAttempt},
 interpretation:{automatic_rebuild_success_proved:false,no_creation_before_crash_proved:false,
  explanation:'This report describes the last persisted snapshot only. If the save precedes submission, it cannot establish whether a new model existed transiently before the crash. The live immediate ledger independently records debit; saved pre-debit quantities do not mean the engine never deducted materials. No compensation or save modification was performed.'},verified_utc:new Date().toISOString()};
assert.equal(hash(input),beforeSHA,'Input SAV changed during verification');result.input_unchanged=true;
writeFileSync(dir+'/last-save-state-analysis.json',JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify({save_sha256:result.input.sha256,save_parse_ok:true,evidence:result.evidence,totals,source_slots,old_manual_present:result.models.old_manual_model_present,saved_base_chest_count:chestModels.length,new_chests:result.models.new_relative_to_demolition_discovery,near_attempt:result.models.near_attempt_within_300cm,all_13_chest_slots_equal_before:scope.filter(c=>c.kind==='ordinary_chest').every(c=>c.all_slots_equal_live_before)},null,2));
