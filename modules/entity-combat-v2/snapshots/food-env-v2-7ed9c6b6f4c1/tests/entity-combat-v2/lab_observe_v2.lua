-- Read-only receipt collector for one scheduled real eat/contact. No inventory, HP, game input or actor mutations.
local Q={}
function Q.run(o)
 assert(IsInGameThread(),'Read actual authority on game thread')
 local J=assert(o.json);local root=assert(o.root):gsub('\\','/'):gsub('/?$','/')
 local function read(name)local f=io.open(root..name,'rb');if not f then return end;local s=f:read('*a');f:close();return J.decode(s)end
 local pal=read('pal-state.json');local mc=read('mc-state.json');local out={observed_unix=os.time(),read_only=true,items_granted=0,actual_native=true}
 if not pal or not mc then out.ok=false;out.status='authority_snapshot_missing';return out end
 out.session=pal.session;out.pal_epoch=pal.epoch;out.mc_epoch=mc.epoch;out.food_capabilities=pal.food
 out.pal_players={};out.mc_players=mc.player_vitals
 for _,r in ipairs(pal.entities)do if r.player then out.pal_players[#out.pal_players+1]=r end end
 if o.food_event_id then
  assert(o.food_event_id:match('^[%x%-]+$')and #o.food_event_id==36,'Food event UUID required')
  out.food_event=read('mc-food-'..o.food_event_id..'.json');out.food_result=read('pal-food-result-'..o.food_event_id..'.json')
  local q,r=out.food_event,out.food_result
  out.food_paid_once=q and q.vanilla_completed and q.before_count-q.after_count==1 or false
  out.food_native_observed=r and r.ok and r.native_route=='PalItemUseProcessor:UseItemToCharacter_ServerInternal'and(r.after_full_stomach>r.before_full_stomach or r.after_hp>r.before_hp)or false
 end
 if o.environment_event_id then
  assert(o.environment_event_id:match('^[%x%-]+$')and #o.environment_event_id==36,'Environment event UUID required')
  out.environment_event=read('mc-hit-'..o.environment_event_id..'.json');out.environment_result=read('pal-result-'..o.environment_event_id..'.json')
  local q,r=out.environment_event,out.environment_result
  out.proxy_environment_observed=q and q.source_proxy==true and q.environment==true and r and r.ok and r.native_route=='SlipDamage'and r.after_hp<r.before_hp or false
 end
 out.ok=true;out.status='real_snapshots_read';return out
end
return Q
