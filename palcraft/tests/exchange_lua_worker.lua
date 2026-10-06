-- Isolated process fixture for the actual production exchange.lua; no UE process is touched.
local root,source,json_path,readers_path,crash=table.unpack(arg)
local J=dofile(json_path);local R=dofile(readers_path)
local function read(path)local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return J.decode(s)end
local function write(path,row)local f=assert(io.open(path..'.tmp','wb'));assert(f:write(J.encode(row)));assert(f:close());os.remove(path);assert(os.rename(path..'.tmp',path))end
local state=read(root..'fixture-inventory.json')
local function persist()write(root..'fixture-inventory.json',state)end
local zero=R.guid_from_string('00000000-0000-0000-0000-000000000000')
local containers={}
for _,data in ipairs(state.containers)do
 local c={}
 function c:IsValid()return true end
 function c:GetFullName()return 'Fixture.Container.'..data.id end
 function c:GetId()return{ID=R.guid_from_string(data.id)}end
 function c:Num()return #data.slots end
 function c:Get(index)
  local a=data.slots[index+1];local slot={}
  function slot:IsValid()return true end
  function slot:GetFullName()return 'Fixture.Slot' end
  function slot:GetSlotId()return{ContainerId=c:GetId(),SlotIndex=index}end
  function slot:GetStackCount()return a.count end
  function slot:GetMaxStack()return 999 end
  function slot:GetItemId()return{StaticId={ToString=function()return a.item end},DynamicId={CreatedWorldId=zero,LocalIdInCreatedWorld=zero}}end
  return slot
 end
 containers[#containers+1]=c
end
local im={}
function im:GetContainer(ref)local id=R.guid_to_string(ref.ID);for _,c in ipairs(containers)do if R.guid_to_string(c:GetId().ID)==id then return c end end end
local function changed(kind)
 state.calls[kind]=(state.calls[kind]or 0)+1;persist()
end
local item={}
function item:RequestDispose_ToServer(request,info)
 local id=R.guid_to_string(info.SlotId.ContainerId.ID)
 for _,c in ipairs(state.containers)do if c.id==id then local a=c.slots[info.SlotId.SlotIndex+1];a.count=a.count-info.Num;assert(a.count>=0);changed('debit');return end end
 error('Unknown fixture container')
end
local inv={}
function inv:AddItem_ServerInternal(item_id,n)
 local slots=state.containers[1].slots
 for _,s in ipairs(slots)do if s.item==item_id or s.count==0 then s.item=item_id;s.count=s.count+n;changed('credit');return true end end
 return false
end
function IsInGameThread()return true end
function FName(item)return item end
PALCRAFT_EXCHANGE_TEST={root=root,json_path=json_path,json=J,readers=R,epoch=state.epoch or('fixture-process:'..tostring({})),
 context=function()return inv,containers[1],{},im end,
 sources=function(bag,pc,manager,include_base)return include_base and{containers[1],containers[2]}or{containers[1]},state.candidate and state.candidate.source_base_id or'fixture-base' end,
 component=function()return item end,
 request_save=function(row)write(root..'fixture-saved.json',state)end,
 fault=function(point,row)if point==crash then os.exit(91,false)end end}
if state.candidate then
 local function ref(s)
  local cid=R.guid_to_string(s.container_id and R.guid_from_string(s.container_id)or s.ContainerId.ID)
  local index=s.slot or s.SlotIndex;local a
  for _,c in ipairs(state.containers)do if c.id==cid then a=c.slots[index+1];break end end
  assert(a);return a,cid,index
 end
 local function snapshot(s)
  local a,cid,index=ref(s);local out={container_id=cid,slot=index,count=a.count,item=a.count>0 and a.item or''}
  if a.count>0 then out.dynamic_world=R.guid_to_string(zero);out.dynamic_guid=R.guid_to_string(zero)end;return out
 end
 local backend={credit_candidate=true,slot=snapshot}
 function backend.chest(c)local slots={};for i=0,#state.containers[3].slots-1 do slots[#slots+1]=snapshot{container_id=c.container_id,slot=i}end;return{slots=slots,access={actor_name='Fixture.Escrow'}}end
 function backend.move(id,to,froms)
  local target=ref(to);local total=0
  for _,step in ipairs(froms)do local a=ref(step.before);assert(a.count>=step.n);a.count=a.count-step.n;total=total+step.n;target.item=step.before.item end
  target.count=target.count+total;changed('move');if crash=='native:move'then os.exit(91,false)end
 end
 function backend.dispose(id,s,n)local a=ref(s);assert(a.count==n);a.count=0;changed('dispose')end
 function backend.credit(lease,id,n)local a=ref{container_id=lease.container_id,slot=lease.slot};assert(a.count==0);a.count=n;a.item=lease.tx.item;changed('produce')end
 function backend.bag(owner,cid)
  assert(not state.offline,'Recipient disconnected');local out={};for i=0,#state.containers[1].slots-1 do out[#out+1]={before=snapshot{container_id=cid,slot=i},max_stack=999}end;return out
 end
 local guard={inspect=function(lease)return{runtime_verified=true,active=true,epoch=PALCRAFT_EXCHANGE_TEST.epoch,
  owner_tx=lease.owner_tx,generation=lease.generation,container_id=lease.container_id,
  player_open=true,pal_transport=true,craft_consume=true,ai_organize=true,restart=true}end,with_permit=function(lease,key,fn)return fn()end}
 PALCRAFT_EXCHANGE_TEST.v3={root=root,json=J,readers=R,epoch=PALCRAFT_EXCHANGE_TEST.epoch,backend=backend,guard=guard,
  boot_id=state.boot_id or'00000000-0000-0000-0000-000000000009',
  config={protocol=3,candidate=state.candidate,lab_candidate=true},
  authorize=function(kind,lease,value)
   if kind=='source'then return value.container_id~=lease.container_id end
   if kind=='terminal'then local mc=read(root..'mc-'..lease.owner_tx..'.json');return mc.state=='completed'and mc.escrow_empty_durable==true end
   if kind=='rehydrate'then return value.runtime_fixture==true end
   return value.durable==true
  end,
  commit=function(name,pending,current)
   local row=read(root..name)
   if state.fail_commit and row.status==state.fail_commit then return end
   if pending then write(root..current,read(root..pending))end
   write(root..name:gsub('%.json$','.durable.json'),row)
  end}
end
local M=dofile(source)
local q=read(root..'request.json')
local ok,out=pcall(M.handle,q)
if not ok then io.stderr:write(tostring(out)..'\n');os.exit(2)end
write(root..'fixture-result.json',out)
io.write(J.encode(out)..'\n')
