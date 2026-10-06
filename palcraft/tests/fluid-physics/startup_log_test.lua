-- Only the 9.2 first-load failure: real io.lines, no UE, RPC, service or body matrix.
local base=assert(arg[1]);local root=assert(arg[2]):gsub('/?$','/')
local Core=dofile(base..'native/fluid_physics_core.lua')
local J=dofile(assert(arg[3],'Existing JSON adapter path required'))
local path=root..'UE4SS fixture.log';local f=assert(io.open(path,'wb'))
f:write('startup\nProcessEvent address 0x100000\nlast ProcessEvent address 0x123400\n');f:close()
local old,why=pcall(function()
 for line in io.lines(assert(path,'Current UE4SS log path required'))do end
end)
assert(not old and why:find('invalid format',1,true),'Exact assert multi-return failure must reproduce')
local calls={}
local function native_call()
 local request=assert(io.open(root..'fluid-physics-request.bin','rb'));local bytes=request:read('*a');request:close()
 local pointers={string.unpack('<c8'..string.rep('I8',19),bytes)}
 assert(pointers[1]=='PALFLD01'and pointers[20]==0x123400,'Real log ProcessEvent pointer must reach native wire')
 local x,y,z,revision,generation,action,boxes=string.unpack('<dddI8I8I4I4I4I4',bytes,161)
 assert(boxes==0,'This startup regression has no participants or query bodies')
 calls[#calls+1]=action
 local result=assert(io.open(root..'fluid-physics-result.json','wb'));result:write(J.encode{ok=true,generation=generation,revision=revision});result:close()
end
local function options()
 return{json=J,root=root,dll_path='not-loaded.dll',log_path=path,generation=7,
  resolve_address=function()return 0x110000 end,native_call=native_call}
end
local adapter=Core.Native.new(options());assert(adapter:replace(0x120000,{0,0,0},9,{}))
assert(#calls==3 and calls[1]==3 and calls[2]==4 and calls[3]==1,'Empty-participant startup must finish abandon/preflight/commit')
local missing=options();missing.log_path=nil;local count=#calls
local valid,error=pcall(function()Core.Native.new(missing):replace(0x120000,{0,0,0},9,{})end)
assert(not valid and error:find('Current UE4SS log path required',1,true)and #calls==count,'Missing log must stop before a native call with the original diagnostic')
print(J.encode{ok=true,suite='fluid_9_2_startup_log',checks=4,old_failure_reproduced=true,
 participants=0,real_log_read=true,native_pointer_forwarded=true,live_runtime_verified=false,
 full_body_matrix_rerun=false,power_mode='night_low_power'})
