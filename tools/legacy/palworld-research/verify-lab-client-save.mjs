// Read-only offline verifier. Never writes or reserializes a .sav file.
import {readFileSync,writeFileSync,statSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
import {decompress as ooz} from '../../palworld-save-toolkit/docs/vendor/ooz-wasm/index.js';
import {decompressSav} from '../../palworld-save-toolkit/docs/js/sav.js';
import {GvasFile,FReader,PALWORLD_TYPE_HINTS} from '../../palworld-save-toolkit/docs/js/gvas.js';
import {LEVEL_CUSTOM_PROPERTIES} from '../../palworld-save-toolkit/docs/js/paldata.js';
const ZERO='00000000-0000-0000-0000-000000000000';
const arr=v=>Array.isArray(v)?v:v?.values??[];
const sha=b=>createHash('sha256').update(b).digest('hex');
const raw=v=>{assert(v instanceof Uint8Array,'Opaque raw bytes required');return v;};
const rd=(b,n)=>{raw(b);assert(b.length>=n,'Truncated raw record');return new FReader(b);};
const one=(a,label)=>{assert(a.length===1,`${label}: expected unique record, found ${a.length}`);return a[0];};
function uuid(v){const s=String(v);assert(/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/.test(s),'Invalid GUID');return s;}
function propSummary(v){if(v instanceof Uint8Array)return{bytes:v.length,sha256:sha(v)};if(typeof v==='bigint')return v.toString();if(v?.rawBytes instanceof Uint8Array)return uuid(v);if(Array.isArray(v))return v.map(propSummary);if(v&&typeof v==='object')return Object.fromEntries(Object.entries(v).map(([k,x])=>[k,propSummary(x)]));return v;}
export function decodeMap(e){
 const b=raw(e.Model.value.RawData.value.values),r=rd(b,245);
 const o={id:uuid(r.guid()),concrete_id:uuid(r.guid()),base_id:uuid(r.guid()),guild_id:uuid(r.guid()),type:e.MapObjectId.value};
 o.hp={current:r.i32(),max:r.i32()};
 o.rotation={x:r.f64(),y:r.f64(),z:r.f64(),w:r.f64()};o.location={x:r.f64(),y:r.f64(),z:r.f64()};r.skip(24+16*3);
 o.build_player_uid=uuid(r.guid());o.raw_sha256=sha(b);
 const cr=rd(raw(e.ConcreteModel.value.RawData.value.values),32);
 o.concrete_id_reverse=uuid(cr.guid());o.model_id_reverse=uuid(cr.guid());
 const br=rd(raw(e.Model.value.BuildProcess.value.RawData.value.values),17);
 o.build_process={state_enum:br.byte(),process_id:uuid(br.guid())};o.completed=o.build_process.state_enum===1;
 const modules=arr(e.ConcreteModel.value.ModuleMap.value);o.modules={};
 for(const kind of ['ItemContainer','Workee']){
  const matches=modules.filter(m=>m.key==='EPalMapObjectConcreteModelModuleType::'+kind);
  if(matches.length){const mr=rd(raw(one(matches,kind).value.RawData.value.values),16);o.modules[kind]=uuid(mr.guid());}
 }
 return o;
}
export function decodeWorkAssignment(b){
 const r=rd(b,58);const o={id:uuid(r.guid()),location_index:r.i32(),assign_type:r.byte(),player_uid:uuid(r.guid()),individual_id:uuid(r.guid()),state_enum:r.byte()};
 const fixed=r.u32();assert(fixed===0||fixed===1,'Unknown serialized assignment bool');o.fixed=fixed===1;
 o.trailing_bytes=b.length-r.pos;o.raw_sha256=sha(b);return o;
}
export function decodeWork(e){
 const b=raw(e.RawData.value.values),r=rd(b,176);const id=uuid(r.guid());
 // Known PalWorkBase header: location24 + quaternion32 + bounds(24+24+8).
 r.skip(112);const o={id,type:e.WorkableType.value.value,base_id:uuid(r.guid()),model_id:uuid(r.guid()),concrete_id:uuid(r.guid()),raw_sha256:sha(b)};
 o.assignments=arr(e.WorkAssignMap.value).map(x=>({...decodeWorkAssignment(raw(x.value.RawData.value.values)),map_key:x.key}));return o;
}
export async function loadSave(path){
 const bytes=readFileSync(path);const {gvas}=await decompressSav(bytes,ooz);const g=GvasFile.read(gvas,PALWORLD_TYPE_HINTS,LEVEL_CUSTOM_PROPERTIES);
 return{world:g.properties.worldSaveData.value,path:resolve(path),file_sha256:sha(bytes),bytes:bytes.length,mtime_utc:statSync(path).mtime.toISOString(),parser_warning_count:(g.warnings??[]).length,parser_warnings:[...new Set(g.warnings??[])]};
}
function checkChest(w,e){
 const models=arr(w.MapObjectSaveData.value).filter(x=>uuid(rd(raw(x.Model.value.RawData.value.values),16).guid())===e.model_id);
 const m=decodeMap(one(models,'chest model'));
 for(const k of ['model_id','container_id','base_id','guild_id','build_player_uid'])if(e[k]!==undefined)uuid(e[k]);
 assert.equal(m.id,e.model_id);assert.equal(m.type,e.type??'ItemChest');assert.equal(m.base_id,e.base_id);assert.equal(m.guild_id,e.guild_id);
 assert.equal(m.concrete_id,m.concrete_id_reverse);assert.equal(m.model_id_reverse,m.id);
 if(e.concrete_id)assert.equal(m.concrete_id,e.concrete_id);
 if(e.build_player_uid)assert.equal(m.build_player_uid,e.build_player_uid);
 assert.equal(m.modules.ItemContainer,e.container_id,'Chest module points at another container');assert(m.completed,'Chest still under construction');
 const box=one(arr(w.ItemContainerSaveData.value).filter(x=>uuid(x.key.ID.value)===e.container_id),'chest container');
 const slots=arr(box.value.Slots.value),capacity=box.value.SlotNum?.value;assert.equal(capacity,e.capacity,'Saved capacity differs');assert(slots.length<=capacity,'More saved slots than capacity');
 const indexes=new Set();let occupied=0;const contents=[];
 for(const s of slots){const b=raw(s.RawData.value.values),r=rd(b,12),index=r.i32(),count=r.i32();assert(Number.isInteger(index)&&index>=0&&index<e.capacity&&!indexes.has(index),'Duplicate or invalid slot');indexes.add(index);assert(count>=0,'Negative count');
  if(count>0){const item=r.fstring();assert(r.pos+32<=b.length,'Truncated occupied slot');contents.push({index,count,item,world_id:uuid(r.guid()),dynamic_id:uuid(r.guid())});occupied++;}}
 return{ok:true,saved:true,model:m,container_id:e.container_id,capacity,container_belong_group_id:uuid(box.value.BelongInfo.value.GroupId.value),saved_slot_records:slots.length,sparse_slots:true,occupied,contents,contents_are_snapshot_only:true};
}
function checkWorker(w,e){
 const c=one(arr(w.CharacterSaveParameterMap.value).filter(x=>uuid(x.key.InstanceId.value)===e.individual_id&&uuid(x.key.PlayerUId.value)===(e.player_uid??ZERO)),'worker character');
 const cv=c.value.RawData.value;assert(cv.object?.SaveParameter?.value,'Character raw decoder unavailable');assert.equal(uuid(cv.group_id),e.guild_id,'Character guild differs');
 const sp=cv.object.SaveParameter.value,slot=sp.SlotId?.value;assert(slot,'Worker character slot missing');
 const container=uuid(slot.ContainerId.value.ID.value),slot_index=slot.SlotIndex?.value??0;
 const base=one(arr(w.BaseCampSaveData.value).filter(x=>uuid(x.key)===e.base_id),'base');
 const wb=raw(base.value.WorkerDirector.value.RawData.value.values),wr=rd(wb,114);const director_id=uuid(wr.guid());wr.skip(82);const director_container=uuid(wr.guid());
 assert.equal(director_id,e.base_id,'Director base differs');
 assert.equal(director_container,container,'Worker not in expected base director container');
 const character_box=one(arr(w.CharacterContainerSaveData.value).filter(x=>uuid(x.key.ID.value)===container),'worker container');
 const character_slots=arr(character_box.value.Slots.value);
 const cs=one(character_slots.filter(s=>(s.SlotIndex?.value??0)===slot_index),'worker slot');
 assert.equal(uuid(cs.RawData.value.instance_id),e.individual_id);assert.equal(uuid(cs.RawData.value.player_uid),e.player_uid??ZERO);
 const record=one(arr(w.WorkSaveData.value).filter(x=>uuid(rd(raw(x.RawData.value.values),16).guid())===e.work_id),'target work');
 const work=decodeWork(record);assert.equal(work.base_id,e.base_id);assert.equal(work.model_id,e.model_id);
 const model=decodeMap(one(arr(w.MapObjectSaveData.value).filter(x=>uuid(rd(raw(x.Model.value.RawData.value.values),16).guid())===e.model_id),'work model'));
 assert.equal(model.base_id,e.base_id);assert.equal(model.guild_id,e.guild_id);assert.equal(model.modules.Workee,e.work_id);assert.equal(model.concrete_id,work.concrete_id);
 const matches=work.assignments.filter(a=>a.individual_id===e.individual_id&&a.player_uid===(e.player_uid??ZERO)&&a.fixed&&a.id===e.work_id&&a.assign_type===1&&a.location_index===a.map_key);
 const fields=Object.fromEntries(Object.entries(sp).filter(([k])=>/fixed|assign|work/i.test(k)).map(([k,v])=>[k,propSummary(v)]));
 return{ok:matches.length===1,fixedWorkSaved:matches.length===1,saved_fixed_matches:matches.length,individual_id:e.individual_id,guild_id:e.guild_id,
  character_id:sp.CharacterID?.value,nickname:sp.NickName?.value,worker_container:container,slot_index,director_id,
  director_trailing:{bytes:wb.length-wr.pos,hex:Buffer.from(wb.subarray(wr.pos)).toString('hex'),decoded:false},
  character_work_fields:fields,work,validation_basis:'Exact target WorkSaveData.WorkAssignMap fixed record, linked to registered model and base worker container.',
  restart_persistence_verified:false,note:'Saved assignment existence is not proof of behavior after restart; no restart was performed.'};
}
export function verifyWorld(w,expect){
 assert(expect.lab_only===true,'Explicit Lab scope required');assert(Array.isArray(expect.chests)&&Array.isArray(expect.workers),'Expected chests/workers arrays required');
 const report={lab_only:true,read_only:true,chests:[],workers:[],errors:[],scope:'Only specified object and worker identity chains; no whole-world invariance claim.',restart_persistence_verified:false};
 for(const e of expect.chests){try{report.chests.push(checkChest(w,e));}catch(err){report.chests.push({ok:false,model_id:e.model_id,error:err.message});report.errors.push('Chest '+e.model_id+': '+err.message);}}
 for(const e of expect.workers){try{const r=checkWorker(w,e);report.workers.push(r);if(!r.ok)report.errors.push('Worker '+e.individual_id+': expected fixed assignment absent or duplicated');}catch(err){report.workers.push({ok:false,individual_id:e.individual_id,error:err.message});report.errors.push('Worker '+e.individual_id+': '+err.message);}}
 report.ok=report.errors.length===0;return report;
}
async function cli(){
 const argv=process.argv.slice(2),a={};for(let i=0;i<argv.length;i+=2){assert(['--after','--before','--expect','--output'].includes(argv[i])&&argv[i+1],'Usage: --after Level.sav --expect expectations.json [--before Level.sav] [--output report.json]');assert(!a[argv[i]],'Duplicate option');a[argv[i]]=argv[i+1];}
 assert(a['--after']&&a['--expect'],'--after and --expect required');const expect=JSON.parse(readFileSync(a['--expect'],'utf8'));
 const after=await loadSave(a['--after']),report=verifyWorld(after.world,expect);
 report.input={path:after.path,sha256:after.file_sha256,bytes:after.bytes,mtime_utc:after.mtime_utc,parser_warning_count:after.parser_warning_count,parser_warnings:after.parser_warnings};
 if(a['--before']){const before=await loadSave(a['--before']);report.before={input:{path:before.path,sha256:before.file_sha256,bytes:before.bytes},...verifyWorld(before.world,expect)};}
 report.verified_utc=new Date().toISOString();const text=JSON.stringify(report,null,2)+'\n';
 if(a['--output']){assert(a['--output'].endsWith('.json'),'Report must be .json');for(const k of ['--before','--after','--expect'])if(a[k])assert.notEqual(resolve(a['--output']),resolve(a[k]),'Refusing to overwrite any input');writeFileSync(a['--output'],text,{flag:'wx'});}
 process.stdout.write(text);if(!report.ok)process.exitCode=2;
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url))cli().catch(e=>{console.error(e.stack);process.exitCode=1;});
