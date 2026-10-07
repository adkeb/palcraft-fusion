-- Three source cases; synthetic native prepare callbacks, no engine/world changes.
local root=assert(arg[1]);local function read(path)local f=assert(io.open(path,'rb'));local x=f:read('*a');f:close();return x end
local function get(source)
 local a=assert(source:find('function M.prepare_block(',1,true));local b=assert(source:find('\nlocal function list',a,true));return source:sub(a,b-1)
end
local body=get(read(root..'/source/client/models.lua'));assert(body==get(read(root..'/source/server/models.lua')))
local original=get(read(root..'/base/client/models.lua'))
local function fixture(clip,which)
 local e={M={},Geometry={},block_animations={},block_targets={}};setmetatable(e,{__index=_G})
 e.Geometry.clip=function(id,state,x,y,z)return clip,{model='original-model'}end
 e.M.prepare=function(ctx,origin,batch)e.received=batch;return{actor=7,fence=batch.fence,state='prepared'}end
 assert(load(which or body,'actual-source-prepare_block','t',e))();return e
end
local packet={dimension='minecraft:overworld',revision=19,generation=1,fence={world_session='synthetic',dim='minecraft:overworld',view=2,mapping='original'}}
local names={};local function check(name,fn)fn();names[#names+1]=name;print('PASS '..name)end
check('furnace_metadata_no_clip_keeps_full_owned_per_block_geometry',function()
 local entry={id='minecraft:furnace',state='facing=north,lit=false',at={8,63,-16},groups={{texture='minecraft:block/furnace_front',light_emission=0}}}
 local e=fixture(nil);local h=e.M.prepare_block({}, {},entry,packet)
 assert(h.state=='prepared'and e.received.groups==entry.groups and e.received.fence==packet.fence and e.received.revision==19 and e.received.generation==1)
 assert(e.received.block_clip==nil and next(e.block_animations)==nil)
 local old=fixture(nil,original);assert(not pcall(old.M.prepare_block,{}, {},entry,packet))
end)
check('original_chest_clip_preserves_original_animation_registration',function()
 local clip={parts={['/lid']={}}};local entry={id='minecraft:chest',state='facing=west,type=single',at={6,63,-16},groups={{part='/lid',animation_clip='minecraft:block_entity/chest/single'}}}
 local e=fixture(clip);local h=e.M.prepare_block({}, {},entry,packet)
 local a=e.block_animations[h.actor];assert(a and a.clip==clip and a.groups==entry.groups and e.received.block_clip==clip and a.target==0)
end)
check('static_multipart_texture_timeline_and_light_metadata_remain_complete_without_dummy_clip',function()
 local timeline={frames={{index=0,time=2}}};local entry={id='minecraft:decorated_pot',state='',at={0,63,-16},groups={{part='/side',texture='minecraft:block/pot',light_emission=14,texture_meta={animation=timeline}}}}
 local e=fixture(nil);e.M.prepare_block({}, {},entry,packet)
 assert(e.received.groups==entry.groups and e.received.groups[1].texture_meta.animation==timeline and e.received.groups[1].light_emission==14)
 assert(next(e.block_animations)==nil and e.received.block_clip==nil)
end)
assert(#names==3);print('RESULT 3 PASS; exact source adapter contracts; no real native commit/ready/ACK acceptance')
