local root=assert(arg[1]);local directory=assert(arg[2],'task_scratch_dir_required')
local J=dofile(root..'/../package/PalCraftClient/Scripts/json.lua');local Journal=dofile(root..'/travel/journal.lua')
local path=directory..'/state.ndjson';local ack=directory..'/travel-acks.ndjson';local count=0
for _,p in ipairs({path,ack})do os.remove(p)end
local function write(p,text,mode)local f=assert(io.open(p,mode or'wb'));assert(f:write(text));f:close()end
local function journal()return Journal.new{json=J,path=path,ack_path=ack}end
local a=journal();assert(a.load()==nil);assert(a.save({phase='moving',tx='one'})==true);count=count+1
local f=assert(io.open(path,'ab'));f:write('{"v":1,"serial":2,"state":');f:close()
local b=journal();local recovered=b.load();assert(recovered.phase=='moving'and recovered.tx=='one');count=count+1
assert(b.save({phase='committed',tx='one'}));local c=journal();assert(c.load().phase=='committed');count=count+1
assert(c.load().phase=='committed');count=count+1
write(path,'{"serial":999','ab');assert(c.save({phase='complete',tx='one'}));assert(journal().load().phase=='complete');count=count+1
assert(not pcall(c.ack,{phase='complete',applied=false,authority_source='pal_server'}));count=count+1
assert(not pcall(c.ack,{phase='complete',applied=true,authority_source='client'}));count=count+1
assert(c.ack({phase='complete',applied=true,authority_source='pal_server',tx='one'}));count=count+1
write(path,'{"v":1,"serial":1,"state":{}}\nthis is corrupt\n')
assert(not pcall(journal().load));count=count+1
write(path,'{"v":1,"serial":3,"state":{}}\n{"v":1,"serial":2,"state":{}}\n')
assert(not pcall(journal().load));count=count+1
os.remove(path);os.remove(ack)
io.write('{"test":"dimension_travel_journal","passed":'..count..',"power_loss_durability_verified":false}\n')
