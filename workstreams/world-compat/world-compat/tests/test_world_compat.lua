local World=dofile(arg[1]or'work/minecraft-fusion/palcraft/server/world_compat.lua')
local checks=0
local function check(v,msg)checks=checks+1;assert(v,msg)end
local function block(x,y,z,id,boxes,fluid)
 boxes=boxes or{{0,0,0,1,1,1}}
 return {op='upsert',at={x,y,z},id=id or'minecraft:oak_planks',state='test',properties={},boxes=boxes,
  solid=#boxes>0,non_solid=#boxes==0,visible=true,render_kind=#boxes>0 and'block'or'non_solid',
  fluid=fluid or{kind='none',empty=true,collision='ignore'}}
end
local up,removed,events={},{},{}
local world=World.new({dimension='minecraft:overworld',player='player',
 on_upsert=function(g)up[#up+1]=g end,on_remove=function(g)removed[#removed+1]=g end,on_lifecycle=function(e)events[#events+1]=e end})
local seq=0
local function ingest(dim,ops,life,session)
 seq=seq+1;local row={t='blocks',v=2,session=session or's1',seq=seq,tick=seq,dim=dim or'minecraft:overworld',ops=ops or{},lifecycle=life}
 local ok,why=world:ingest(row);check(ok,'ingest '..tostring(why));return row
end
ingest(nil,{block(1,64,1),block(17,64,1)})
check(#up==2,'active dimension visible')
ingest('minecraft:the_nether',{block(1,64,1,'minecraft:netherrack')})
check(#up==2 and world:get('minecraft:the_nether',1,64,1).id=='minecraft:netherrack','other dimension caches without projection')
check(world:get('minecraft:overworld',1,64,1).id=='minecraft:oak_planks','same coordinate dimensions independent')
local water=block(2,64,2,'minecraft:water',{}, {kind='water',height=8/9,amount=8,source=true,empty=false,collision='ignore'})
water.render_kind='fluid';ingest(nil,{water})
check(up[#up].solid==false and #up[#up].boxes==0,'water creates no cube collision')
check(world:fluid_at('minecraft:overworld',2.5,64.2,2.5).kind=='water','real water contact volume')
check(world:fluid_at('minecraft:overworld',2.5,64.99,2.5)==nil,'above water surface is dry')
check(world:fluid_at('minecraft:overworld',1.5,64.2,1.5)==nil,'ordinary wood is dry')
local button=block(3,64,3,'minecraft:oak_button',{});ingest(nil,{button})
check(up[#up].visible and #up[#up].boxes==0,'non-solid button projects')
local bounds={0,60,0,16,80,16}
ingest(nil,{},{{op='snapshot_begin',snapshot='snap1',at={0,0},bounds=bounds,replace=true,player='player'}})
local staged=block(4,64,4,'minecraft:stone');staged.snapshot='snap1';ingest(nil,{staged})
check(world:get('minecraft:overworld',4,64,4)==nil,'incomplete snapshot is not visible')
local live=block(1,64,1,'minecraft:diamond_block');ingest(nil,{live})
local before=#up;ingest(nil,{},{{op='snapshot_end',snapshot='snap1',at={0,0},bounds=bounds,replace=true,player='player'}})
check(world:get('minecraft:overworld',4,64,4).id=='minecraft:stone' and #up>before,'snapshot commit projects final region')
check(world:get('minecraft:overworld',1,64,1).id=='minecraft:diamond_block','newer delta wins over snapshot')
check(world:get('minecraft:overworld',2,64,2)==nil and world:get('minecraft:overworld',3,64,3)==nil,'snapshot removes stale non-solids in bounds')
check(world:get('minecraft:overworld',17,64,1)~=nil,'bounded replace preserves outside region')
local receipt=world:committed_snapshot('snap1')
check(receipt and receipt.committed and receipt.blocks==2 and receipt.newer_deltas==1,'snapshot receipt proves bounded commit and later delta preservation')
check(world:region_status('minecraft:overworld',{1,64,1,2,66,2},'player').ready,'committed region proof')
check(not world:region_status('minecraft:overworld',{16,64,1,20,66,2},'player').ready,'no readiness from queue empty outside committed bounds')
ingest(nil,{},{{op='snapshot_begin',snapshot='cancel',at={0,0},bounds=bounds,replace=true}})
local cancelled=block(6,64,6);cancelled.snapshot='cancel';ingest(nil,{cancelled})
ingest(nil,{},{{op='snapshot_cancel',snapshot='cancel',at={0,0},bounds=bounds,replace=true}})
check(world:get('minecraft:overworld',6,64,6)==nil and world:status().snapshots==0,'cancelled snapshot cannot leak partial cells')
ingest(nil,{block(-1,64,-1)})
ingest(nil,{},{{op='chunk_unload',at={-1,-1}}})
check(world:get('minecraft:overworld',-1,64,-1)==nil and world:get('minecraft:overworld',1,64,1)~=nil,'negative chunk unload exact')
local oldUp=#up;local oldRemoved=#removed
ingest('minecraft:the_nether',{},{{op='player_view',player='player',to='minecraft:the_nether',view=2,pos={8,65,8},waiting_ack=true}})
check(world.dimension=='minecraft:the_nether' and #removed>oldRemoved and #up>oldUp,'view switch removes previous projection and presents new one')
local duplicate={t='blocks',v=2,session='s1',seq=seq,dim='minecraft:overworld',ops={block(100,64,100)}}
local ok,why=world:ingest(duplicate);check(ok and why=='duplicate' and world:get('minecraft:overworld',100,64,100)==nil,'duplicate is harmless')
local malformed={t='blocks',v=2,session='s1',seq=seq+1,dim='minecraft:overworld',ops={block(100,64,100),block(101,64,101)}}
malformed.ops[2].boxes={{0,0,0,0,1,1}}
ok=world:ingest(malformed);check(not ok and world:get('minecraft:overworld',100,64,100)==nil,'malformed batch cannot partially mutate cache')
ingest('minecraft:the_nether',{},{{op='chunk_unload',at={0,0}}})
check(world:get('minecraft:the_nether',1,64,1)==nil,'unload clears projected Nether chunk')
seq=0;ingest(nil,{block(9,64,9)},nil,'s2')
check(world:get('minecraft:overworld',1,64,1)==nil and world:get('minecraft:overworld',9,64,9)~=nil,'new lifetime clears prior state')
ok,why=world:ingest(duplicate);check(ok and why=='retired_session','late old lifetime cannot reset world')
local legacy=World.new({on_upsert=function(g)check(g.fluid.kind=='none','legacy solid never inferred as water')end})
check(legacy:ingest({t='blocks',set={1,64,1},clear={},geometry={{at={1,64,1},id='minecraft:oak_planks',boxes={{0,0,0,1,1,1}}}}}),'legacy compatibility')
check(legacy:get('minecraft:overworld',1,64,1).id=='minecraft:oak_planks','legacy known geometry retained')
local Fluid=dofile('work/minecraft-fusion/palcraft/server/world_fluid.lua')
local wet=World.new({player='p',auto_view=false});local wetSeq=0
local function wetEvent(ops,life)
 wetSeq=wetSeq+1;local yes,why=wet:ingest({t='blocks',v=2,session='wet-session',seq=wetSeq,dim='minecraft:overworld',ops=ops or{},lifecycle=life})
 check(yes,'wet event '..tostring(why))
end
wetEvent({},{{op='player_view',player='p',to='minecraft:overworld',view=1}})
check(wet.view==nil and wet.pending_view.view==1,'manual projection never labels pending view as active')
wet:set_view('minecraft:overworld','p');check(wet.view==1 and wet.pending_view==nil,'explicit cutover sets active generation even in same dimension')
local enters,exits,swim,flows,unknown=0,0,{},0,0
local driver=Fluid.new({world=wet,on_enter=function()enters=enters+1 end,on_exit=function()exits=exits+1 end,
 on_swimming=function(c)swim[#swim+1]=c.swimming end,on_flow=function()flows=flows+1 end,on_unknown=function()unknown=unknown+1 end})
local pose={dim='minecraft:overworld',feet={1.5,64,1.5},height=1.8,eye_height=1.62,world_session='wet-session',view=1,player='p'}
check(driver:sample('pal',pose).known==false and unknown==1,'incomplete world produces unknown rather than false dry contact')
local f={kind='water',height=1,source=true,flow={1,0,0},empty=false,collision='ignore'}
local bottom=block(1,64,1,'minecraft:water',{},f);bottom.snapshot='wet'
local top=block(1,65,1,'minecraft:water',{}, {kind='water',height=8/9,source=true,flow={1,0,0},empty=false,collision='ignore'});top.snapshot='wet'
wetEvent({},{{op='snapshot_begin',snapshot='wet',at={0,0},bounds={0,60,0,16,80,16},player='p'}})
wetEvent({bottom,top})
wetEvent({},{{op='snapshot_end',snapshot='wet',at={0,0},bounds={0,60,0,16,80,16},player='p'}})
local contact=driver:sample('pal',pose)
check(contact.known and contact.wet and contact.swimming and contact.submerged and enters==1 and flows==1,'committed two-block water enters/swims/submerges with actual flow')
check(contact.native_damage==false and contact.world_session=='wet-session' and contact.view==1,'driver carries trusted world tuple and never creates native damage')
check(contact.surface_known and math.abs(contact.surface-(65+8/9))<1e-8,'connected vertical water finds actual top beyond waist cell')
check(not driver:status().authoritative_native_swimming_verified,'mock callback never claims verified Pal swimming')
local slab=block(3,64,3,'minecraft:oak_slab',{{0,0,0,1,.5,1}}, {kind='water',waterlogged=true,height=8/9,source=true,flow={0,0,0},empty=false,collision='ignore'})
wetEvent({slab})
check(wet:fluid_at('minecraft:overworld',3.5,64.25,3.5)==nil,'waterlogged solid body remains dry')
check(wet:fluid_at('minecraft:overworld',3.5,64.75,3.5).kind=='water','waterlogged open space contains real water')
check(#wet:fluid_volumes('minecraft:overworld',{0,60,0,16,80,16})==3,'volume index includes fluid and waterlogged states only')
local taller=block(1,65,1,'minecraft:water',{}, {kind='water',height=1,source=true,flow={1,0,0},empty=false,collision='ignore'})
local high=block(1,66,1,'minecraft:water',{}, {kind='water',height=8/9,source=true,flow={1,0,0},empty=false,collision='ignore'})
wetEvent({taller,high});contact=driver:sample('pal',pose)
check(contact.surface_known and math.abs(contact.surface-(66+8/9))<1e-8,'three-cell deep water does not pin surface at middle cell')
local tallDriver=Fluid.new({world=wet,max_surface_cells=1})
check(tallDriver:sample('pal',pose).surface_known==false,'column scan limit never invents an upper surface')
local dry=block(1,64,1,'minecraft:air',{});dry.op='remove';dry.visible=false
local dryTop=block(1,65,1,'minecraft:air',{});dryTop.op='remove';dryTop.visible=false
local dryHigh=block(1,66,1,'minecraft:air',{});dryHigh.op='remove';dryHigh.visible=false
wetEvent({dry,dryTop,dryHigh});contact=driver:sample('pal',pose)
check(contact.known and not contact.wet and not contact.swimming and exits==1 and swim[#swim]==false,'water removal exits and restores dry intent')
pose.world_session='old-session';check(driver:sample('pal',pose).known==false,'old epoch contact is rejected')
wetEvent({},{{op='chunk_unload',at={0,0}}})
check(not wet:region_status('minecraft:overworld',{1,64,1,2,66,2},'p').ready,'chunk unload invalidates committed proof')
local gapRow={t='blocks',v=2,session='wet-session',seq=wetSeq+2,dim='minecraft:overworld',ops={}}
check(wet:ingest(gapRow)and wet:status().gaps==1,'sequence gap is visible and requires new proof')
if arg[2]then
 local J=dofile('work/palworld-live/bridge/PalLiveBridge/Scripts/json.lua')
 local f=assert(io.open(arg[2],'rb'));local fixture=J.decode(f:read('*a'));f:close()
 local actual=World.new();local i=0
 for name,g in pairs(fixture.samples)do i=i+1;g.at={i,64,0}
  local yes,reason=actual:ingest({t='blocks',v=2,session='vanilla',seq=i,dim='minecraft:overworld',ops={g}})
  check(yes,'vanilla codec payload '..name..' '..tostring(reason))
 end
 check(i>=20,'real registered-state coverage')
end
print('WORLD_COMPAT_LUA_OK checks='..checks)
