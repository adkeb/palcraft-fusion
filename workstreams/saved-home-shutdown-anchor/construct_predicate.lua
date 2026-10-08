-- Pure constructor only. It does not call a predicate, change an upvalue, or execute any Game operation.
return function(normal_saved_shutdown,main_source)
 assert(type(normal_saved_shutdown)=='function'and type(main_source)=='string','Original shutdown function and reviewed main source required')
 local gate_index,original
 for i=1,100 do
  local name,value=debug.getupvalue(normal_saved_shutdown,i);if not name then break end
  if name=='saved_home_cleanup_ready'then gate_index,original=i,value;break end
 end
 assert(gate_index and type(original)=='function','Original saved-home predicate upvalue not found')
 local values,environment={},nil
 for i=1,100 do
  local name,value=debug.getupvalue(original,i);if not name then break end
  if name=='_ENV'then environment=value else values[name]=value end
 end
 assert(type(values.view_state)=='table'and type(values.home_origin)=='table','Original predicate scope differs')
 setmetatable(values,{__index=assert(environment,'Original Lua environment required')})
 local begin=assert(main_source:find('local function saved_home_cleanup_ready(',1,true))
 local finish=assert(main_source:find('\nfunction client_control.normal_saved_shutdown',begin+1,true))
 local text=main_source:sub(begin,finish-1)..'\nreturn saved_home_cleanup_ready'
 local replacement=assert(load(text,'@reviewed-saved-home-anchor-predicate','t',values))()
 assert(type(replacement)=='function')
 -- Root/sole actor must separately authorize any debug.setupvalue call. This constructor returns data only.
 return{shutdown=normal_saved_shutdown,upvalue_index=gate_index,original_predicate=original,replacement_predicate=replacement}
end
