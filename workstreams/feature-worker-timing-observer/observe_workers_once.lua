-- Observation only, through the original client-op route under the sole actor.
-- No new callback/timer, worker invocation, native/game state write or cadence.
assert(IsInGameThread(), 'Existing game thread required')
local SP=assert(rawget(_G,'PalCraftStandaloneBootstrap'))
local realm=assert(SP.local_realm)
local client=assert(rawget(_G,'PalCraftClientFeatures'))
local server=assert(rawget(_G,'PalCraftServerFeatures'))
assert(client.running and server.running,'Existing running feature composition required')
assert(not rawget(_G,'PalCraftCallbackObserver') and not rawget(_G,'PalCraftWorkerObserver'),'One observer at a time')
local J=require('json')
local start,frame_start=os.clock(),nil
local rows,stack,restore,seen,targets,frames={},{},{},{},{},{}
local current_feature
local marker={observation_only=true};_G.PalCraftWorkerObserver=marker
local function invoke(label,feature,fn,...)
 local row=rows[label]or{calls=0,inclusive_ms=0,exclusive_ms=0,max_ms=0,failures=0}
 rows[label]=row
 local before,old_feature=os.clock(),current_feature
 current_feature=feature or old_feature
 local context={child=0};stack[#stack+1]=context
 local result=table.pack(pcall(fn,...))
 local elapsed=(os.clock()-before)*1000
 stack[#stack]=nil;current_feature=old_feature
 if stack[#stack]then stack[#stack].child=stack[#stack].child+elapsed end
 row.calls=row.calls+1;row.inclusive_ms=row.inclusive_ms+elapsed
 row.exclusive_ms=row.exclusive_ms+math.max(0,elapsed-context.child);row.max_ms=math.max(row.max_ms,elapsed)
 if not result[1]then row.failures=row.failures+1;error(result[2],0)end
 return table.unpack(result,2,result.n)
end
local function describe(label,fn)
 local info=debug.getinfo(fn,'S')
 targets[#targets+1]={label=label,source=info and info.source,first_line=info and info.linedefined}
end
local function wrap(object,key,label,feature)
 if type(object)~='table'or type(object[key])~='function'then return end
 seen[object]=seen[object]or{};if seen[object][key]then return end;seen[object][key]=true
 local original,raw=object[key],rawget(object,key)
 local replacement=function(...)return invoke(label,feature,original,...)end
 describe(label,original);rawset(object,key,replacement)
 restore[#restore+1]=function()
  assert(rawget(object,key)==replacement,'Worker observer method ownership changed')
  rawset(object,key,raw) -- Restore inherited methods to their exact original absence.
 end
end
local known_files={['mc-state.json']=true,['pal-state.json']=true,['authenticated-sessions.json']=true,
 ['mc-hits.json']=true,['mc-foods.json']=true,['pal-status.json']=true,['binding-meta.json']=true}
local function internal_tick(worker,label,feature)
 if type(worker)~='table'or type(worker.tick)~='function'then return end
 local original=worker.tick
 for slot=1,100 do
  local name,value=debug.getupvalue(original,slot);if not name then break end
  if ({scan=true,read=true,write=true,current_authority=true})[name]and type(value)=='function'then
   local index,fn,kind=slot,value,name
   local replacement=function(...)
    local suffix=''
    if kind=='read'or kind=='write'then
     local file=select(1,...)
     local basename=type(file)=='string'and file:match('[^/\\]+$')or''
     suffix='.'..(known_files[basename]and basename or'other-item')
    end
    return invoke(label..'.private.'..kind..suffix,feature,fn,...)
   end
   describe(label..'.private.'..kind,fn)
   debug.setupvalue(original,index,replacement)
   restore[#restore+1]=function()
    local _,now=debug.getupvalue(original,index)
    assert(now==replacement,'Worker observer private closure ownership changed')
    debug.setupvalue(original,index,fn)
   end
  end
 end
end
for _,side in ipairs({'server','client'})do
 local api=side=='server'and server or client
 local C=assert(api.composition)
 for _,slot in ipairs(C.order)do
  local feature=side..'.'..slot.name
  local worker=slot.instance
  if slot.name=='entities'then internal_tick(worker,feature..'.instance',feature)end
  for _,method in ipairs({'tick','status','vitals','ready'})do wrap(worker,method,feature..'.instance.'..method,feature)end
  for _,method in ipairs({'ready','key','factory','tick','status','is_ready'})do wrap(slot.definition,method,feature..'.definition.'..method,feature)end
  targets[#targets+1]={feature=feature,phase=slot.phase,interval_ms=slot.definition.interval_ms or 250,enabled=slot.definition.enabled~=false,existing_instance=worker~=nil}
  if side=='client'and slot.name=='client_world'and worker then
   local c=worker.companion
   for _,method in ipairs({'context','status','status_json'})do wrap(c,method,'shared.companion.'..method,feature)end
  end
 end
 wrap(C,'tick',side..'.composition.tick')
 wrap(C,'status',side..'.composition.status')
 wrap(api,'tick',side..'.features.tick')
 wrap(api,'status',side..'.features.status')
end
-- Only calls naturally made inside a measured feature are timed. No scan is added.
local find=assert(FindAllOf)
local find_observer=function(kind,...)
 if not current_feature then return find(kind,...)end
 local label=current_feature..'.FindAllOf.'..(type(kind)=='string'and kind or'other')
 local result=table.pack(invoke(label,nil,find,kind,...))
 if type(result[1])=='table'then
  local row=rows[label];row.returned_count_sum=(row.returned_count_sum or 0)+#result[1]
  row.returned_count_max=math.max(row.returned_count_max or 0,#result[1])
 end
 return table.unpack(result,1,result.n)
end
_G.FindAllOf=find_observer
restore[#restore+1]=function()assert(FindAllOf==find_observer,'FindAll observer ownership changed');_G.FindAllOf=find end
local begin,finish=realm.begin_frame,realm.end_frame
local done=false
local function complete()
 if done then return end;done=true
 for i=#restore,1,-1 do restore[i]()end
 assert(realm.begin_frame==marker.begin and realm.end_frame==marker.finish,'Worker callback observer ownership changed')
 realm.begin_frame=begin;realm.end_frame=finish;_G.PalCraftWorkerObserver=nil
 local output={schema=1,kind='original-composition-worker-timing-v1',observation_only=true,
  clock='os.clock (runtime CRT)',elapsed_ms=(os.clock()-start)*1000,frames=frames,stages=rows,targets=targets,
  all_wrapped_methods_globals_and_shared_upvalues_restored=true,wrapper_overhead_included=true,
  native_calls_or_worker_invocations_added=false,cadences_full_geometry_750_UID_permissions_and_authority_changed=false,
  individual_native_Getter_cost_or_60FPS_not_claimed=true}
 local path=assert(SP.bridge_root)..'current19-feature-worker-observation.json'
 local f=assert(io.open(path..'.tmp','wb'));assert(f:write(J.encode(output)));assert(f:close())
 os.remove(path);assert(os.rename(path..'.tmp',path))
end
marker.begin=function(...)frame_start=os.clock();return begin(...)end
marker.finish=function(...)
 local result=table.pack(finish(...))
 if frame_start then frames[#frames+1]=(os.clock()-frame_start)*1000;frame_start=nil end
 if #frames>=24 or os.clock()-start>=3 then complete()end
 return table.unpack(result,1,result.n)
end
realm.begin_frame=marker.begin;realm.end_frame=marker.finish
return{observation_only=true,max_callbacks=24,max_runtime_CRT_seconds=3,
 automatic_restore_on_original_callback_end=true,output='current19-feature-worker-observation.json'}
