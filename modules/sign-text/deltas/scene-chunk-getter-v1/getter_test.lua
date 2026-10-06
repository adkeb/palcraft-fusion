-- One focused check of the new getter/encoder contract; no matrix-suite rerun.
local directory=assert(arg[1]):gsub('/?$','/')
local Scene=dofile(directory..'scene.lua')
local dim='minecraft:overworld';local at={2,64,3}
local g={id='minecraft:oak_sign',state='rotation=0',visible=true}
local world={session='world-one',dimension=dim,committed_snapshots={receipt={committed=true,
 session='world-one',dim=dim,player='mc-one',bounds={0,0,0,16,256,16}}}}
function world:get(d,x,y,z)assert(d==dim and x==2 and y==64 and z==3);return g end
local entry={dim=dim,id=g.id,model=101,model_component=102,model_status='rendered',visible=true,render_signature='owned:rotation=0'}
local legacy={dim=dim,id=g.id,model=201,model_component=202,model_status='rendered',visible=true,render_signature='owned:rotation=0'}
local getter_calls,encoder_calls,seen=0,0,nil
local c={running=true,world=world,origin={X=1,Y=2,Z=3},actors={['2:64:3']=legacy}}
function c.block_render_entry(d,p)assert(d==dim and p==at);getter_calls=getter_calls+1;return entry end
function c.render_signature(value)assert(value==g);encoder_calls=encoder_calls+1;return'owned:'..value.state end
local scene=Scene.per_block{json={encode=function()error('Local encoder used despite companion encoder')end},
 companion=c,confirmed_view=function()return{applied=true,world_session='world-one',dim=dim,view=7,mapping='committed-map',mc_uuid='mc-one'}end,
 model_live=function(actor,component)seen={actor,component};return true end}
local block,ready=scene.block_at(dim,at)
assert(block==g and ready==true and seen[1]==101 and seen[2]==102 and getter_calls==1 and encoder_calls==1,
 'Chunk getter/companion encoder did not take precedence over legacy actor')
entry.model_status='prepared';block,ready=scene.block_at(dim,at);assert(not ready,'Prepared entry fell back to older committed legacy actor')
entry.model_status='rendered';g.state='rotation=1';block,ready=scene.block_at(dim,at);assert(not ready,'Orientation change accepted before commit')
entry.render_signature='owned:rotation=1';block,ready=scene.block_at(dim,at);assert(ready and seen[1]==101,'Committed orientation failed same-handle proof')
entry.dim='minecraft:the_nether';block,ready=scene.block_at(dim,at);assert(not ready,'Foreign-dimension entry accepted')
entry=nil;legacy.render_signature='owned:rotation=1';block,ready=scene.block_at(dim,at);assert(ready and seen[1]==201,'Legacy fallback unavailable when getter returns nil')
assert(scene.view_provider({}).fence.mapping=='committed-map','Existing confirmed-view fence changed')
c.pending_view={};assert(scene.view_provider({})==nil,'Pending view fence relaxed')
print('PASS: committed chunk getter + companion signature precedence; orientation/dimension rejection; legacy fallback; confirmed-view fence')
