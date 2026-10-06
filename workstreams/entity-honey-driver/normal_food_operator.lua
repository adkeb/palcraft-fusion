-- Standalone preparation for the existing trusted game-thread RPC. No timer/socket/production changes.
local M={}
local WINROOT=assert(os.getenv('PALCRAFT_WINDOWS_ROOT'),'Configured installed Windows root required'):gsub('\\','/'):gsub('/+$','')
local ROOT=WINROOT..'/PalCraft-Dev/bridge/'
local UID='22222222-0000-0000-0000-000000000000'
local UUID='11111111-1111-1111-1111-111111111111'
local WORLD='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
local FOOD={['minecraft:bread']=true,['minecraft:apple']=true,['minecraft:carrot']=true,
 ['minecraft:cooked_beef']=true,['minecraft:cooked_porkchop']=true,['minecraft:cooked_chicken']=true,
 ['minecraft:cooked_mutton']=true,['minecraft:baked_potato']=true,['minecraft:sweet_berries']=true}
local function uuid(s)return type(s)=='string'and s:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$')end
-- A freshly loaded JSON module's private array marker/metatable must not cross the main RPC encoder.
local function plain(v)
 if type(v)~='table'then return v end
 local out={};for k,x in pairs(v)do if type(k)=='string'or type(k)=='number'then out[k]=plain(x)end end
 return out
end
function M.new(o)
 o=o or{}
 local J=o.json or dofile(WINROOT..'/PalCraft-Client/Pal/Binaries/Win64/ue4ss/Mods/PalCraftClient/Scripts/json.lua');local api={}
 local function read(name)
  local f=io.open(ROOT..name,'rb');if not f then return nil end
  local n=f:seek('end');assert(n and n<=1048576,'Bounded authority file required');f:seek('set');local raw=f:read('*a');f:close()
  return J.decode(raw)
 end
 local function thread()assert(IsInGameThread(),'Use the existing trusted game-thread RPC')end
 local function fresh(t,max_age)
  return t and type(t.unix)=='number'and os.time()-t.unix>=-5 and os.time()-t.unix<=max_age
 end
 local function observe(event_id)
  thread();local identity=assert(read('lab-identity.json'),'Lab identity unavailable')
  assert(identity.world_directory==WORLD,'Different Lab world')
  local pal,mc=assert(read('entities/pal-state.json')),assert(read('entities/mc-state.json'))
  assert(fresh(pal,3)and fresh(mc,3),'Fresh actual authority required')
  assert(pal.authority=='pal_server'and mc.authority=='mc_server'and pal.session==mc.session
   and pal.session==identity.server_session_id,'Authority session mismatch')
  local p,v
  for _,row in ipairs(pal.entities or{})do if row.player and row.player_uid==UID then assert(not p,'Ambiguous native player');p=row end end
  for _,row in ipairs(mc.player_vitals or{})do if row.mc_uuid==UUID and row.pal_uid==UID then assert(not v,'Ambiguous MC player');v=row end end
  assert(p and v,'Exact same-UID pair not present')
  local expected=(p.alive and not p.dying and p.max_hp>0)and 20*p.hp/p.max_hp or 0
  local out={read_only=true,observed_unix=os.time(),world_id=WORLD,server_session_id=pal.session,
   pal_epoch=pal.epoch,mc_epoch=mc.epoch,pal_revision=pal.revision,mc_revision=mc.revision,
   pal=p,mc=v,food=pal.food,expected_mc_health=expected,
   shared_vitals_match=type(v.hearts)=='number'and math.abs(v.hearts-expected)<.0001
    and math.abs(v.hp-p.hp)<.01 and math.abs(v.shield-p.shield)<.01,
   damage_death_multiplayer_verified=false,items_granted=0,hp_writes=0}
  local authority=_G.PalCraftEntityAuthority
  if authority then
   out.entity_food_ledger=authority.status().food_ledger
   out.latest_food_event_id=authority.last_food_result and authority.last_food_result.id or nil
  end
  local f=_G.PalCraftClientFeatures
  if f and f.binding and f.mc_binding then
   assert(f.binding.server_session_id==pal.session,'Current client Pal boot differs')
   out.connection={host_session_id=f.binding.session_id,host_generation=f.binding.generation,
    mc_session_id=f.mc_binding.session_id,mc_generation=f.mc_binding.generation,native_mc_epoch=f.mc_binding.mc_epoch}
  end
  if event_id then
   assert(uuid(event_id),'Exact completed food event UUID required')
   local q,r=read('entities/mc-food-'..event_id..'.json'),read('entities/pal-food-result-'..event_id..'.json')
   out.food_event=q;out.food_result=r
   local scoped=q and r and q.id==event_id and r.id==event_id and q.session==pal.session
    and r.session==pal.session and q.source_epoch==mc.epoch and q.target_epoch==pal.epoch
    and q.source=='mc:'..UUID and q.target==p.id and q.player_session and q.player_session.pal_uid==UID
    and q.player_session.mc_uuid==UUID and q.player_session.world_id==WORLD
   out.food_receipt_scoped=scoped==true
   out.food_paid_once=scoped and q.phase=='consumed'and q.vanilla_completed==true
    and q.creative~=true and q.consumed_count==1 and q.before_count-q.after_count==1 or false
   out.native_food_effect_observed=out.food_paid_once and r.ok==true and r.native_items_credited==0
    and r.native_route=='PalItemUseProcessor:UseItemToCharacter_ServerInternal'
    and(r.after_full_stomach>r.before_full_stomach or r.after_hp>r.before_hp)or false
  end
  return plain(out)
 end
 local function bus()
  thread();local features=assert(_G.PalCraftClientFeatures,'Client RPC required for normal input')
  local b=assert(features.binding,'Current authenticated host required')
  assert(b.world_id==WORLD and b.pal_uid==UID and b.mc_uuid==UUID and b.expires_at>os.time(),'Current exact host lease required')
  local feature=assert(features.composition.features.commands,'Existing command bus unavailable')
  assert(feature.phase=='running'and feature.instance,'Existing command bus not running')
  return feature.instance,b
 end
 local function same_scope(prepared,state)
  local a,b=prepared.scope,state
  if a.server_session_id~=b.server_session_id or a.mc_epoch~=b.mc_epoch or a.pal_epoch~=b.pal_epoch then return false end
  if not a.connection or not b.connection then return false end
  for _,k in ipairs({'host_session_id','host_generation','mc_session_id','mc_generation','native_mc_epoch'})do if a.connection[k]~=b.connection[k]then return false end end
  return true
 end
 function api.observe(event_id)return observe(event_id)end
 function api.request_inspection()
  local sender=bus();assert(sender.send({t='inspect'})==true)
  return {submitted=true,effect='wait_for_actual_authenticated_HostLink_inspection',read_only_request=true}
 end
 function api.release()
  -- Release does not require food readiness or a live pawn. Disconnect/mode changes also release normal keys.
  local sender=bus();assert(sender.send({t='key',k='use',down=false})==true)
  return {submitted=true,effect='normal_key_release_queued_verify_actual_key_state'}
 end
 function api.prepare(inspection,received_unix)
  local state=observe();bus()
  assert(type(received_unix)=='number'and os.time()-received_unix>=-1 and os.time()-received_unix<=2,'Fresh response from the existing authenticated connection required')
  assert(inspection.t=='inspection'and inspection.uuid==UUID and inspection.creative==false,'Actual survival guest inspection required')
  assert(inspection.screen=='none','Close GUI through normal input before use')
  local server
  for _,v in ipairs((inspection.server or{}).players or{})do if v.uuid==UUID then server=v;break end end
  assert(server,'Actual authoritative inventory response required')
  local candidates={}
  for _,s in ipairs(server.inventory or{})do
   if FOOD[s.item]and math.tointeger(s.slot)and s.slot>=0 and s.slot<=8 and math.tointeger(s.count)and s.count>0 then
    for _,c in ipairs(inspection.inventory or{})do if c.slot==s.slot and c.item==s.item and c.count==s.count then
     candidates[#candidates+1]={slot=s.slot,item=s.item,count=s.count};break
    end end
   end
  end
  return {observed_unix=received_unix,scope=state,candidates=candidates,
   status=#candidates>0 and'existing_plain_food_in_hotbar'or'no_confirmed_existing_plain_food_in_hotbar',selected_item=inspection.selected_item,aim=inspection.aim}
 end
 function api.select(prepared,index)
  local state=observe();local sender=bus();local c=assert(prepared.candidates[index or 1],'No verified existing food candidate')
  assert(os.time()-prepared.observed_unix<=2 and same_scope(prepared,state),'Prepared inventory/connection scope expired')
  assert(sender.send({t='slot',n=c.slot})==true)
  return {submitted=true,candidate=c,effect='reinspect_actual_selected_item_and_current_counts_before_begin'}
 end
 function api.begin(prepared,index)
  local state=observe();local sender=bus();local c=assert(prepared.candidates[index or 1],'No verified existing food candidate')
  assert(os.time()-prepared.observed_unix<=2 and same_scope(prepared,state),'Prepared inventory/connection scope expired')
  assert(prepared.selected_item==c.item,'Actual selected food not confirmed')
  assert(prepared.aim and prepared.aim.type=='MISS','Reinspect an actual empty-space aim; do not interact/place/feed instead of eating')
  assert(state.pal.alive and not state.pal.dying and state.pal.full_stomach<state.pal.max_full_stomach,'Normal live hungry consumer required')
  local ready=false;for _,id in ipairs((state.food or{}).ready_players or{})do if id==state.pal.id then ready=true end end
  assert(ready,'Existing native food provider not available')
  assert(_G.PalCraftForm and _G.PalCraftForm.status().active==true,'Actual MC form required')
  local input=assert(read('input-state.json'),'Existing input publisher required')
  assert(fresh(input,2)and input.build==true and input.menu~=true,'Fresh MC mode outside the inventory menu required')
  assert(sender.status().queued==0,'Wait for the existing command queue to drain')
  assert(sender.send({t='key',k='use',down=true})==true)
  return {submitted=true,candidate=c,before=state,effect='normal_vanilla_use_pending',
   physical_focus=input.focus,physical_focus_is_gate=false,
   release_required=true,release_after_ms=1800,hard_release_deadline_ms=2000,
   normal_use_ticks=32,one_paid_consume_required=true,food_effect_verified=false}
 end
 return api
end
return M
