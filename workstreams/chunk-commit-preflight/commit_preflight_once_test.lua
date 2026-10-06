-- Narrow check: the ordinary Bridge delegate performs one native preflight,
-- with the exact packet fence, before collision commit. No world/DLL/game runs.
local root='/path/to/workspace/work/minecraft-fusion/'
local G=dofile(root..'palcraft/client/chunk_geometry.lua')
local J=dofile(root..'package/PalCraftClient/Scripts/json.lua')
local B=dofile(root..'palcraft/client/companion_chunk_bridge.lua')
local calls={};local fence={world_session='once',dim='minecraft:overworld',view=1,mapping='r'}
local collision={preflight=function(new,old,expected)
 calls[#calls+1]='preflight';assert(expected==fence and #new==1 and #old==0,'Packet fence and actual handles preserved')
end,commit=function(new,old,expected)
 calls[#calls+1]='collision';assert(expected==fence,'Final physics mutation retains exact fence')
end}
local models={prepare=function()end,commit_transaction=function(new,old,tx)
 calls[#calls+1]='models_validate';tx.adapter.preflight(tx.prepared,tx.previous);tx.adapter.commit(tx.prepared,tx.previous)
 calls[#calls+1]='reveal';return true
end}
local world={session='once',dimension='minecraft:overworld',ingest=function()end,get=function()return nil end}
local companion={world=world,actors={},origin={X=0,Y=0,Z=0},install_consumer=function()return true end,
 retire_legacy=function()return{ok=true}end,render_signature=G.stable,geometry_signature=G.stable}
local adapter={capabilities={collision_compound=true},discard=function()end,unload=function()end}
local views={adapter=adapter,regions={}}
local bridge=B.new({companion=companion,views=views,geometry={},models=models,json=J,collision=collision})
bridge.installed=true;views.generation=1;views.regions.r={refs=1,mapping={origin=companion.origin}}
local fresh={visual={},collision={{actor=1}},special={}}
local packet={fence=fence,dimension='minecraft:overworld',region_id='r',generation=1,at={0,64,0},revision=1}
local result=adapter.commit(fresh,nil,packet)
assert(result==fresh and table.concat(calls,',')=='models_validate,preflight,collision,reveal','One authoritative preflight precedes atomic mutation/reveal')
assert(bridge.stats.commits==1,'Normal scene publication still completes')
local test={status='passed',checks=4,preflight_roundtrips=1,exact_fence_preserved=true,atomic_order_preserved=true,
 new_game_or_DLL_calls=false,real_commit_ms_not_measured=true,power_mode='night_low_power'}
local f=assert(io.open(root..'chunk_scaling/commit-preflight-once-tests.json','wb'));f:write(J.encode(test));f:close();print(J.encode(test))
