-- A single lifecycle for the existing feature modules. No timers, sockets or UObject discovery.
local M={version=1}
function M.new(options)
 options=options or{}
 local C={order={},features={},routes={},events={},stopped=false}
 local function thread()
  local check=options.game_thread or IsInGameThread
  assert(type(check)=='function'and check()==true,'runtime_requires_game_thread')
 end
 function C:register(name,d)
  assert(not self.features[name]and type(d.factory)=='function','Duplicate/invalid feature '..name)
  local f={name=name,definition=d,phase=d.enabled==false and'disabled'or'waiting',reason=d.disabled_reason,
   calls={start=0,tick=0,event=0,dispatch=0,stop=0},next_tick=0}
  self.features[name]=f;self.order[#self.order+1]=f
  for method,fn in pairs(d.routes or{})do
   assert(not self.routes[method],'Duplicate runtime operation '..method)
   self.routes[method]={feature=f,call=fn}
  end
  for kind,fn in pairs(d.events or{})do
   self.events[kind]=self.events[kind]or{};table.insert(self.events[kind],{feature=f,call=fn})
  end
  return self
 end
 local function stop(f,reason,ctx)
  if not f.instance then return end
  local instance=f.instance;f.instance=nil;f.calls.stop=f.calls.stop+1
  local fn=f.definition.stop
  if fn then
   local ok,err=pcall(fn,instance,reason,ctx)
   if not ok then f.error=tostring(err);f.phase='error';return false end
  end
  return true
 end
 local function fail(f,error,ctx)
  f.error=tostring(error);f.phase='error';stop(f,'feature_error',ctx);f.phase='error'
  if options.on_error then options.on_error(f.name,f.error)end
 end
 local function eligible(self,f,ctx)
  if f.definition.enabled==false then return false,f.reason or'feature_disabled'end
  for _,name in ipairs(f.definition.depends or{})do
   local parent=assert(self.features[name],'Unknown feature dependency '..name)
   if parent.phase~='running'then return false,'dependency_not_ready:'..name end
  end
  if f.definition.ready then return f.definition.ready(ctx)end
  return true
 end
 function C:tick(now,ctx)
  thread();assert(type(now)=='number','Elapsed milliseconds required')
  if self.stopped then return false end
  self.context=ctx
  if self.previous_time and now<self.previous_time then for _,f in ipairs(self.order)do f.next_tick=0 end end
  self.previous_time=now
  local all=true
  for _,f in ipairs(self.order)do
   if f.phase~='error'and f.definition.enabled~=false and now>=f.next_tick then
    f.next_tick=now+(f.definition.interval_ms or 250)
    local good,ready,reason=pcall(eligible,self,f,ctx)
    if not good then fail(f,ready,ctx)
    elseif ready~=true then
     stop(f,reason,ctx);if f.phase~='error'then f.phase='waiting';f.reason=reason or'feature_not_ready'end
    else
     if f.definition.key then
      local key=f.definition.key(ctx)
      if f.instance and f.key~=key then stop(f,'feature_session_changed',ctx)end
      f.key=key
     end
     if not f.instance and f.phase~='error'then
      f.calls.start=f.calls.start+1
      local ok,instance=pcall(f.definition.factory,ctx)
      if not ok or instance==nil then fail(f,ok and'Feature factory returned nil'or instance,ctx)
      else f.instance=instance;f.phase='running';f.reason=nil end
     end
     if f.instance and f.definition.tick then
      f.calls.tick=f.calls.tick+1
      local ok,err=pcall(f.definition.tick,f.instance,now,ctx)
      if not ok then fail(f,err,ctx)end
     end
    end
   end
   if f.definition.enabled~=false and f.phase~='running'then all=false end
  end
  return all
 end
 function C:dispatch(method,params,request)
  thread();local route=self.routes[method];if not route then return false end
  local f=route.feature
  if f.phase~='running'or not f.instance then
   return true,{ok=false,status='feature_not_ready',feature=f.name,reason=f.error or f.reason or f.phase}
  end
  f.calls.dispatch=f.calls.dispatch+1
  local ok,result=pcall(route.call,f.instance,params or{},request,self.context)
  if not ok then fail(f,result,self.context);return true,{ok=false,status='feature_error',feature=f.name,error=tostring(result)}end
  assert(result~=nil,'Runtime operation returned no result: '..method)
  return true,result
 end
 function C:emit(kind,row)
  thread();local accepted=true
  for _,route in ipairs(self.events[kind]or{})do
   local f=route.feature
   if f.instance and f.phase=='running'then
    f.calls.event=f.calls.event+1;local ok,err=pcall(route.call,f.instance,row,self.context)
    if not ok then fail(f,err,self.context);accepted=false end
   end
  end
  return accepted
 end
 function C:reset(reason,ctx)
  thread();local good=true
  for i=#self.order,1,-1 do local f=self.order[i]
   if stop(f,reason,ctx)==false then good=false end
   f.next_tick=0
   if f.definition.enabled~=false and not f.instance then
    if good then f.phase='waiting';f.reason=reason;f.error=nil;f.key=nil end
   end
  end
  self.context=nil;return good
 end
 function C:stop(reason,ctx)
  local good=self:reset(reason or'runtime_stopped',ctx);self.stopped=true;return good
 end
 function C:status()
  local rows={};local ready=not self.stopped;local started=not self.stopped
  for _,f in ipairs(self.order)do
   local value
   if f.instance and f.definition.status then
    local ok,result=pcall(f.definition.status,f.instance)
    if ok then value=result else value={ok=false,error=tostring(result)};ready=false end
   end
   local feature_ready=f.phase=='running'
   if feature_ready and f.definition.is_ready then
    local ok,result=pcall(f.definition.is_ready,value,f.instance,self.context)
    feature_ready=ok and result==true
    if not ok then value={ok=false,error=tostring(result)}end
   end
   rows[#rows+1]={name=f.name,phase=f.phase,ready=feature_ready,reason=f.reason,error=f.error,calls=f.calls,status=value}
   if f.definition.enabled~=false then
    if f.phase~='running'then started=false end
    if not feature_ready then ready=false end
   end
  end
  return{version=1,modules_started=started,ready=ready,stopped=self.stopped,features=rows}
 end
 return C
end
return M
