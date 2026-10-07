-- TEMPORARY observation only. Sole runtime actor must authorize/run this once
-- through the original client-op route. No scheduler, native/game writes,
-- permission/proof substitution, readiness change or cadence change.
assert(IsInGameThread(), 'Existing game thread required')
local SP = assert(rawget(_G, 'PalCraftStandaloneBootstrap'))
local realm = assert(SP.local_realm)
local client = assert(rawget(_G, 'PalCraftClientFeatures'))
local server = assert(rawget(_G, 'PalCraftServerFeatures'))
assert(client.running and server.running, 'Observe only the existing full callback')
assert(not rawget(_G, 'PalCraftCallbackObserver'), 'One observer at a time')
local J = require('json')
local started, frame_start = os.clock(), nil
local frames, rows, stack, restore = {}, {}, {}, {}
local active = true
local marker = {observation_only=true}
_G.PalCraftCallbackObserver = marker
local function invoke(label, fn, ...)
 local row = rows[label] or {calls=0, inclusive_ms=0, exclusive_ms=0, max_ms=0, failures=0}
 rows[label] = row
 local clock, nested = os.clock(), {child=0}
 stack[#stack+1] = nested
 local result = table.pack(pcall(fn, ...))
 local elapsed = (os.clock()-clock)*1000
 stack[#stack] = nil
 if stack[#stack] then stack[#stack].child = stack[#stack].child + elapsed end
 row.calls=row.calls+1; row.inclusive_ms=row.inclusive_ms+elapsed
 row.exclusive_ms=row.exclusive_ms+math.max(0,elapsed-nested.child)
 row.max_ms=math.max(row.max_ms,elapsed)
 if not result[1] then row.failures=row.failures+1; error(result[2],0) end
 return table.unpack(result,2,result.n)
end
local function wrap(object, key, label)
 local original = object and object[key]
 if type(original) ~= 'function' then return end
 local replacement = function(...) return invoke(label,original,...) end
 object[key] = replacement
 restore[#restore+1] = function()
  assert(object[key]==replacement,'Observer method changed by another owner')
  object[key]=original
 end
end
local function internal(object,key,names)
 local f=object[key]
 for index=1,100 do
  local name,value=debug.getupvalue(f,index)
  if not name then break end
  if names[name] and type(value)=='function' then
   local original,slot,label=value,index,'realm.'..name
   local replacement=function(...)return invoke(label,original,...)end
   debug.setupvalue(f,slot,replacement)
   restore[#restore+1]=function()
    local _,now=debug.getupvalue(f,slot)
    assert(now==replacement,'Observer upvalue changed by another owner')
    debug.setupvalue(f,slot,original)
   end
  end
 end
end
-- Existing closures only; no discovery, ownership calls or native methods added.
internal(realm,'current',{still_current=true,referenced_context=true,verify_owned=true,sample=true})
wrap(realm,'current','realm.current')
wrap(realm,'validate','realm.validate')
wrap(realm,'same_world','realm.same_world')
wrap(client,'tick','client.features.tick')
wrap(server,'tick','server.features.tick')
for _,key in ipairs({'companion','resolve_player','native_context'})do wrap(SP.world,key,'server.world.'..key)end
local begin,finish=realm.begin_frame,realm.end_frame
local function complete()
 if not active then return end
 active=false
 -- Restore in reverse, including all shared Lua upvalues, before publication.
 for i=#restore,1,-1 do restore[i]()end
 assert(realm.begin_frame==marker.begin and realm.end_frame==marker.finish,'Callback observer ownership changed')
 realm.begin_frame=begin;realm.end_frame=finish
 _G.PalCraftCallbackObserver=nil
 local output={schema=1,kind='temporary-current19-full-callback-timing-v1',
  observation_only=true,clock='os.clock (runtime CRT)',frames=frames,stages=rows,
  elapsed_ms=(os.clock()-started)*1000,wrapper_overhead_not_subtracted=true,
  native_GetFullName_individual_cost_not_measured=true,
  proof_gate_permission_750_UID_remote_world_save_physics_WAL_and_cadences_changed=false,
  wrapped_methods_and_shared_upvalues_restored=true,actual_60FPS_claimed=false}
 local path=assert(SP.bridge_root)..'current19-full-callback-observation.json'
 local file=assert(io.open(path..'.tmp','wb'))
 assert(file:write(J.encode(output)));assert(file:close())
 os.remove(path);assert(os.rename(path..'.tmp',path))
end
marker.begin=function(...)
 frame_start=os.clock()
 return begin(...)
end
marker.finish=function(...)
 local result=table.pack(finish(...))
 if frame_start then
  frames[#frames+1]=(os.clock()-frame_start)*1000
  frame_start=nil
 end
 if #frames>=24 or os.clock()-started>=3 then complete()end
 return table.unpack(result,1,result.n)
end
realm.begin_frame=marker.begin;realm.end_frame=marker.finish
-- No extra timer. The existing next callback closes/restores the observation.
return {observation_only=true,frames_max=24,seconds_max=3,restores_on_existing_callback_end=true,
 output='current19-full-callback-observation.json',native_or_game_state_changed=false}
