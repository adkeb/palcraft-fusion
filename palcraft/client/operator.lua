-- Called only through the existing trusted client-op game-thread route.
-- This module submits a native request; the regular publisher/form tick owns effects.
local M={}
function M.new(o)
 local request,thread,gate=assert(o.request),assert(o.thread),assert(o.gate)
 local input,form_status=assert(o.input),assert(o.form_status)
 local api={}
 function api.form_status()
  thread()
  local i=input()or{}
  return {input={build=i.build==true,focus=i.focus==true,generation=i.generation,
   sequence=i.sequence,unix=i.unix,stale=i.stale},form=form_status()}
 end
 function api.form_set(mode)
  thread();assert(type(mode)=='boolean','form_set requires an explicit boolean')
  if mode then gate()end
  request(mode)
  local status=api.form_status()
  status.requested_mode=mode;status.submission='native_request_submitted'
  status.effect='observe_next_normal_input_and_form_tick'
  return status
 end
 return api
end
return M
