-- Narrow regression for the reported retained-DLL/new-UWorld failure. Only the
-- already-existing PALCCOL1 action3 is used; it must not destroy any old UObject.
local root='/path/to/workspace/work/minecraft-fusion/'
local J=dofile(root..'package/PalCraftClient/Scripts/json.lua')
local C=dofile(root..'palcraft/client/chunk_collision.lua')
local G=dofile(root..'palcraft/client/chunk_geometry.lua')
local work=root..'chunk_scaling/world-rebind-test/'
_G.PalCraftChunkCollisionLifetimes=nil
local retained_context,retained_epoch,serial=nil,0,0x50000
local actions={};local checks=0
local function check(v,m)checks=checks+1;assert(v,m)end
local function native()
 local f=assert(io.open(work..'chunk-collision-request.bin','rb'));local bytes=f:read('*a');f:close()
 local context=string.unpack('<I8',bytes,9)
 local _,_,_,revision,epoch,action,boxes=string.unpack('<dddI8I8I4I4I4I4',bytes,161)
 actions[#actions+1]=action
 local result={ok=true,stage='prepared',generation=epoch,revision=revision,actor='0x0',components={}}
 if action==3 then
  check(epoch>retained_epoch,'Abandon has a strictly increasing native wire epoch')
  retained_context=context;retained_epoch=epoch;result.stage='abandoned'
 else
  if not retained_context then retained_context=context;retained_epoch=epoch end
  if context~=retained_context or epoch~=retained_epoch then result.ok=false;result.stage='stale_context'
  elseif action==0 then serial=serial+0x100;result.actor=string.format('0x%x',serial)
   for i=1,boxes do result.components[i]=string.format('0x%x',serial+0x1000+i*8)end
  elseif action==1 then result.stage='committed'
  elseif action==4 then result.stage='preflight'
  elseif action==2 then result.stage='unloaded'end
 end
 f=assert(io.open(work..'chunk-collision-result.json','wb'));f:write(J.encode(result));f:close()
end
local function make()
 return C.new({json=J,root=work,dll_path='retained-lab-v1.dll',native=native,process_event=0x30000,resolve_address=function()return 0x31000 end})
end
local origin={X=0,Y=0,Z=0};local payload={at={0,64,0},revision=1,boxes={{cm={0,-100,0,100,0,100},properties={policy=G.collision_policy}}}}
local old=make();local oldh=old.prepare(0x10000,origin,payload);old.commit({oldh},{})
local before=#actions;old.reset(2,false)
check(#actions==before+1 and actions[#actions]==3,'World-gone reset immediately clears DLL bookkeeping before adapter can be discarded')
local new=make();local h=new.prepare(0x20000,origin,payload)
check(retained_context==0x20000 and h.native_epoch==3 and h.generation==1,'Fresh adapter binds the actual new UWorld with independent native epoch')
check(actions[#actions-1]==3 and actions[#actions]==0,'Rebind precedes new box preparation')
check(not pcall(old.commit,{oldh},{}),'Old world handle remains invalid after reset')
local count=#actions
check(not pcall(new.rebind_context,0x21000,nil,false)and #actions==count,'Live-floor context cannot be abandoned without confirmed UWorld end')
-- Operator recovery of a pre-hotfix retained DLL: no constructor lifecycle cache
-- is assumed; caller supplies a higher actual native epoch after confirming travel.
_G.PalCraftChunkCollisionLifetimes=nil
local recovery=make()
check(not pcall(recovery.prepare,0x22000,origin,payload),'Retained old DLL fence rejects a new context without handshake')
recovery.rebind_context(0x22000,retained_epoch+1,true);local recovered=recovery.prepare(0x22000,origin,payload)
check(recovered.context==0x22000 and recovered.native_epoch==4,'Existing action3 recovers without rebuilding DLL or faking old context')
for _,action in ipairs(actions)do check(action~=2,'Confirmed ended-world recovery never invokes old actor destruction')end
local result={status='passed',checks=checks,abi='existing PALCCOL1/action3, ea2deb DLL compatible',native_rebuild=false,
 old_actors_destroyed=false,contexts_distinct=true,mc_session_id_irrelevant=true,power_mode='night_low_power',through_engine=false}
local f=assert(io.open(root..'chunk_scaling/world-rebind-tests.json','wb'));f:write(J.encode(result));f:close();print(J.encode(result))
