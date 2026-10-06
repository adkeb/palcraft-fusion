-- PalLiveBridge live RPC core, protocol 1. Deploy only after version-matched Lab tests.
-- Target runtime: Palworld 1.0.5 Windows + Okaetsu/RE-UE4SS 2281fa31.
-- readers.lua was exercised in BridgeLab: all 18 allowlisted containers and 3 bases.
-- Storage writes use reviewed, expiring plans and append-only native-move journals. No eval.
-- All UE access happens inside ExecuteInGameThread. UUID paths are strictly validated.
-- Each mod reload gets a fresh server_instance_id; plans from old instances are invalid.
local RPC = "D:/PalworldServer-LAN/BridgeLab/rpc/"
local EXPECTED_VERSION = "1.0.5.102999"
local BRIDGE_VERSION = "lua-live-0.3.0"
local MAX_REQUEST = 1048576
local MAX_RESPONSE = 8388608
local POLL_MS, HEARTBEAT_SECONDS, STARTUP_GRACE_SECONDS = 250, 2, 15
local source = debug.getinfo(1, "S").source
assert(source:sub(1,1)=="@", "script path unavailable")
local directory = assert(source:sub(2):match("^(.*[/\\])"), "script directory unavailable")
package.path=directory.."?.lua;"..package.path
local Readers = dofile(directory .. "readers.lua")
local Targets = dofile(directory .. "targets.lua")
local Json = dofile(directory .. "json.lua")
-- All modules must share the same encoder's private array metatable.
package.loaded["json"]=Json
package.loaded["readers"]=Readers
local Organize = dofile(directory .. "organize.lua")
local Merge = dofile(directory .. "merge.lua")
local Discovery = dofile(directory .. "discovery.lua")
local Workers = dofile(directory .. "workers.lua")
local StorageRuntime = dofile(directory .. "storage-runtime.lua")
local storage_runtime
local started = os.time()
local instance_id, display_version, startup_error
local bases_verified, storage_verified = false, false
local workers_verified=false
local last_heartbeat, last_probe = 0, 0
local tick_queued, completion = false, nil
local last_log_error = nil

local function log_error(message)
    message = tostring(message)
    if message ~= last_log_error then
        print("[PalLiveBridge RPC] " .. message .. "\n")
        last_log_error = message
    end
end
local function utc() return os.date("!%Y-%m-%dT%H:%M:%SZ", os.time()) end
local function uuid(s)
    return type(s)=="string" and #s==36 and
        s:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$")~=nil
end
local function fail(code, message) error({code=code, message=message}, 0) end
local function fields(t, allowed, required)
    if type(t)~="table" or getmetatable(t)~=nil then fail("invalid_request", "Expected a JSON object") end
    for k in pairs(t) do if not allowed[k] then fail("invalid_request", "Unknown request field") end end
    for _, k in ipairs(required or {}) do if t[k]==nil then fail("invalid_request", "Missing required request field") end end
end
local function require_uuid(v)
    if not uuid(v) then fail("invalid_request", "Expected a canonical UUID") end
end
local function leap(y) return y%4==0 and (y%100~=0 or y%400==0) end
local function days_before_year(y)
    y=y-1
    return 365*y + math.floor(y/4)-math.floor(y/100)+math.floor(y/400)
end
local function deadline_epoch(s)
    if type(s)~="string" or #s>64 then fail("invalid_request", "Expected UTC ISO timestamp") end
    local y,mo,d,h,mi,se=s:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)Z$")
    local fraction
    if not y then y,mo,d,h,mi,se,fraction=s:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)%.(%d+)Z$") end
    if not y or (fraction and #fraction>9) then fail("invalid_request", "Invalid UTC timestamp") end
    y,mo,d,h,mi,se=tonumber(y),tonumber(mo),tonumber(d),tonumber(h),tonumber(mi),tonumber(se)
    local months={31,leap(y) and 29 or 28,31,30,31,30,31,31,30,31,30,31}
    if y<1970 or mo<1 or mo>12 or d<1 or d>months[mo] or h>23 or mi>59 or se>59 then
        fail("invalid_request", "Invalid UTC timestamp")
    end
    local days=days_before_year(y)-days_before_year(1970)+d-1
    for i=1,mo-1 do days=days+months[i] end
    return days*86400+h*3600+mi*60+se+(fraction and tonumber("0."..fraction) or 0)
end
local function before_deadline(epoch)
    -- Lua os.time has one-second precision. Conservatively reject the final second,
    -- so no queued request starts after its deadline because of truncation.
    if epoch<=os.time()+1 then fail("timeout", "Request expired or less than one second remains") end
end
local function read_file(path, maximum)
    local f=io.open(path,"rb")
    if not f then return nil end
    local data=f:read(maximum+1) or ""
    f:close()
    if #data>maximum then return data,"file_too_large" end
    return data
end
local function exists(path)
    local f=io.open(path,"rb")
    if not f then return false end
    f:close(); return true
end
local function atomic_json(path, value, replace)
    local encoded=Json.encode(value,{max_bytes=MAX_RESPONSE,max_depth=64})
    local temporary=path..".tmp"
    local f,err=io.open(temporary,"wb")
    assert(f,err)
    local written,write_error=f:write(encoded)
    local closed,close_error=f:close()
    assert(written,write_error); assert(closed,close_error)
    -- Responses have unique UUID names and are never replaced. On Windows the
    -- manifest replacement has a brief absent-file window, but is never partial.
    if replace then os.remove(path) end
    local renamed,rename_error=os.rename(temporary,path)
    assert(renamed,rename_error)
end
local function array(t) return Json.array(t or {}) end
local function mark_bases(report)
    array(report.bases); array(report.errors)
    return report
end
local function mark_storage(report)
    array(report.chests); array(report.errors)
    for _,chest in ipairs(report.chests) do array(chest.slots) end
    return report
end
local function live(o) return o~=nil and o:IsValid() end
local function capabilities()
    return {
        protocol_version=1, bridge_version=BRIDGE_VERSION,
        game_version=display_version or Json.null, server_instance_id=instance_id or Json.null,
        heartbeat_utc=utc(), instance_scope="new UUID on each UE4SS mod load or server start",
        capabilities={
            ["bases.list"]={supported=bases_verified,verified=bases_verified,read_only=true},
            ["storage.list"]={supported=storage_verified,verified=storage_verified,read_only=true},
            ["storage.plan"]={supported=storage_verified,verified=storage_verified,read_only=true},
            ["storage.apply"]={supported=storage_verified,verified=storage_verified,read_only=false},
            ["build.preview"]={supported=false,verified=false,read_only=true},
            ["build.apply"]={supported=false,verified=false,read_only=false},
            ["workers.list"]={supported=workers_verified,verified=workers_verified,read_only=true},
            ["workers.plan"]={supported=false,verified=false,read_only=true},
            ["workers.assign"]={supported=false,verified=false,read_only=false},
            ["operations.get"]={supported=storage_runtime~=nil,verified=storage_runtime~=nil,read_only=true}
        },
        storage_coverage={automatic_discovery=true,source="existing live ordinary chest models",
            snapshot_identifier=Targets.snapshot_sha256,snapshot_identifier_is_file_hash=false,
            known_container_count=#Targets.chests},
        startup_error=startup_error or Json.null
    }
end
local function new_uuid()
    return Readers.guid_to_string(StaticFindObject("/Script/Engine.Default__KismetGuidLibrary"):NewGuid())
end
local function refresh_targets()
    local found=Discovery.discover()
    if not found.ok or (#found.targets.chests>0 and not found.verified_live) then
        fail("backend_unavailable","Live chest discovery or ownership verification failed")
    end
    Targets=found.targets
    for _,t in ipairs(Targets.chests) do
        if t.world_position then
            t.world=t.world_position
            t.map={x=(t.world.y-158000)/459,y=(t.world.x+123888)/459}
        end
    end
end
local function storage_report(base_id,container_ids)
    refresh_targets()
    base_id=base_id:lower()
    local live_bases=Readers.bases()
    if not live_bases.ok then fail("backend_unavailable","Cannot check base existence") end
    local base_found=false
    for _,b in ipairs(live_bases.bases) do if b.id==base_id then base_found=true end end
    if not base_found then fail("not_found","Requested base is not present in the live world") end
    local ids
    if container_ids then ids={};for _,id in ipairs(container_ids) do ids[id:lower()]=true end end
    local selected={snapshot_sha256=Targets.snapshot_sha256,chests={}}
    for _,t in ipairs(Targets.chests) do
        if t.base_id==base_id and (not ids or ids[t.container_id]) then
            selected.chests[#selected.chests+1]=t
            if ids then ids[t.container_id]=nil end
        end
    end
    if ids and next(ids) then fail("not_found","Selected container is outside this base's ordinary-chest allowlist") end
    local report
    if #selected.chests==0 then report={ok=true,includes_items=true,chests=array(),errors=array(),source="runtime_read_only"}
    else report=mark_storage(Readers.chests(selected,{include_items=true,lookup="manager",require_snapshot_ownership=true})) end
    if not report.ok then fail("backend_unavailable","A live container or its base/guild ownership could not be verified") end
    report.base_id=base_id;report.server_instance_id=instance_id;report.observed_utc=utc()
    report.coverage={automatic_discovery=true,source="existing live ordinary chest models",
        snapshot_identifier=Targets.snapshot_sha256,snapshot_identifier_is_file_hash=false,total_known_containers=#Targets.chests,
        selected_known_containers=#selected.chests,current_container_base_membership_verified=true}
    report.reader_verified=true;report.candidate_unvalidated=false
    return report
end
local function initialize_runtime()
    if not instance_id then
        -- Calling a declared STATIC function on a Blueprint function library CDO is
        -- appropriate; instance methods and server RPCs are never called on a CDO.
        local library=StaticFindObject("/Script/Engine.Default__KismetGuidLibrary")
        assert(live(library),"KismetGuidLibrary unavailable")
        instance_id=Readers.guid_to_string(library:NewGuid())
        assert(uuid(instance_id),"invalid instance GUID")
        storage_runtime=StorageRuntime.new({root=RPC,json=Json,readers=Readers,targets=Targets,organize=Organize,merge=Merge,
            utc=utc,new_uuid=new_uuid,instance_id=function() return instance_id end,read_storage=storage_report,
            get_targets=function() return Targets end})
    end
    if os.time()-started<STARTUP_GRACE_SECONDS then return end
    if bases_verified and storage_verified and workers_verified then return end
    if os.time()-last_probe<HEARTBEAT_SECONDS then return end
    last_probe=os.time()
    local manager=FindFirstOf("PalItemContainerManager")
    if not live(manager) then startup_error="World item manager is not ready"; return end
    local utility=StaticFindObject("/Script/Pal.Default__PalUtility")
    assert(live(utility),"PalUtility unavailable")
    local version=utility:GetDisplayVersion(manager)
    display_version=type(version)=="string" and version or version:ToString()
    assert(type(display_version)=="string","version getter returned no string")
    if display_version:match("%d+%.%d+%.%d+%.%d+")~=EXPECTED_VERSION then
        startup_error="Game build differs from the validated 1.0.5.102999 reader build"
        bases_verified=false; storage_verified=false; return
    end
    local b=Readers.bases()
    bases_verified=b.ok==true and #b.bases>0
    refresh_targets()
    if #Targets.chests==0 then storage_verified=true
    else
        local s=Readers.chests(Targets,{include_items=true,lookup="manager",require_snapshot_ownership=true})
        storage_verified=s.ok==true and #s.chests==#Targets.chests
    end
    local wok,workers=pcall(Workers.list)
    workers_verified=wok and workers.ok==true
    if bases_verified and storage_verified then startup_error=nil
    else startup_error="Waiting for the validated base/container readers to succeed" end
end
local function validate(request)
    fields(request,{protocol_version=true,request_id=true,method=true,params=true,deadline_utc=true},
        {"protocol_version","request_id","method","params","deadline_utc"})
    if request.protocol_version~=1 then fail("invalid_request","Unsupported protocol version") end
    require_uuid(request.request_id)
    if type(request.method)~="string" then fail("invalid_request","Method must be a string") end
    local epoch=deadline_epoch(request.deadline_utc)
    before_deadline(epoch)
    if epoch>os.time()+60 then fail("invalid_request","Request deadline exceeds the local 60-second limit") end
    if request.method=="bases.list" then
        fields(request.params,{guild_id=true})
        if request.params.guild_id~=nil then require_uuid(request.params.guild_id) end
    elseif request.method=="storage.list" then
        fields(request.params,{base_id=true,include_empty=true},{"base_id"})
        require_uuid(request.params.base_id)
        if request.params.include_empty~=nil and type(request.params.include_empty)~="boolean" then
            fail("invalid_request","include_empty must be boolean")
        end
    elseif request.method=="storage.plan" then
        fields(request.params,{base_id=true,policy=true,container_ids=true,include_shared=true},{"base_id","policy"})
        require_uuid(request.params.base_id)
        if request.params.policy~="category" and request.params.policy~="item_type" then fail("invalid_request","Unsupported storage policy") end
        if request.params.include_shared~=nil and request.params.include_shared~=false then fail("unsupported","Only ordinary base chests are supported") end
        if request.params.container_ids then
            if type(request.params.container_ids)~="table" or #request.params.container_ids<1 or #request.params.container_ids>100 then fail("invalid_request","Invalid container list") end
            for _,id in ipairs(request.params.container_ids) do require_uuid(id) end
        end
    elseif request.method=="storage.apply" then
        fields(request.params,{plan_id=true,expected_revision=true,idempotency_key=true},{"plan_id","expected_revision","idempotency_key"})
        for _,name in ipairs({"plan_id","expected_revision","idempotency_key"}) do require_uuid(request.params[name]) end
    elseif request.method=="operations.get" then
        fields(request.params,{request_id=true},{"request_id"});require_uuid(request.params.request_id)
    elseif request.method=="workers.list" then
        fields(request.params,{base_id=true},{"base_id"});require_uuid(request.params.base_id)
    else fail("unsupported","This runtime method is not enabled") end
    return epoch
end
local function dispatch(request, epoch)
    before_deadline(epoch)
    if request.method=="bases.list" then
        if not bases_verified then fail("backend_unavailable","Base reader is not ready for this server instance") end
        local report=mark_bases(Readers.bases())
        if not report.ok then fail("backend_unavailable","Live base reader failed") end
        if request.params.guild_id then
            local wanted=request.params.guild_id:lower()
            local filtered=array()
            for _,b in ipairs(report.bases) do if b.group_id==wanted then filtered[#filtered+1]=b end end
            report.bases=filtered
        end
        report.server_instance_id=instance_id; report.observed_utc=utc()
        report.reader_verified=true; report.candidate_unvalidated=false
        return report
    end
    if request.method=="workers.list" then
        if not workers_verified then fail("backend_unavailable","Worker reader is not ready") end
        local report=Workers.list({base_id=request.params.base_id:lower()})
        if not report.ok then fail("backend_unavailable","Live worker reader failed") end
        report.server_instance_id=instance_id;report.observed_utc=utc()
        report.reader_verified=true;report.candidate_unvalidated=false
        return report
    end
    if request.method=="operations.get" then
        if not storage_runtime then fail("backend_unavailable","Operation journal is not ready") end
        return storage_runtime.get(request.params)
    end
    if not storage_verified then fail("backend_unavailable","Storage reader is not ready for this server instance") end
    if request.method=="storage.plan" then return storage_runtime.plan(request.params) end
    if request.method=="storage.apply" then return storage_runtime.apply(request.params,request.request_id) end
    local base_id=request.params.base_id:lower()
    local report=storage_report(base_id)
    local include_empty=request.params.include_empty~=false
    if not include_empty then
        local filtered=array()
        for _,c in ipairs(report.chests) do
            if not c.ok or (c.occupied or 0)>0 then filtered[#filtered+1]=c end
        end
        report.chests=filtered
    end
    report.base_id=base_id; report.server_instance_id=instance_id; report.observed_utc=utc()
    report.include_empty_containers=include_empty
    report.slot_coverage="All slots are retained inside each returned container"
    report.reader_verified=true; report.candidate_unvalidated=false
    return report
end
local function reject_invalid_queue(code, raw)
    atomic_json(RPC.."last-rejected.json",{protocol_version=1,rejected_utc=utc(),
        error={code="invalid_request",message=code}},true)
    -- Compare the observed bytes before cleanup, including the bounded oversize prefix.
    -- A valid new request cannot equal an oversize prefix (MAX_REQUEST+1 bytes).
    if read_file(RPC.."request.json",MAX_REQUEST)==raw then os.remove(RPC.."request.json") end
end
local function finish_completion()
    if not completion then return end
    local path=RPC.."responses/"..completion.request_id..".json"
    if not exists(path) then atomic_json(path,completion.response,false) end
    -- Never delete a different request that appeared while this response was pending.
    local current=read_file(RPC.."request.json",MAX_REQUEST)
    if current==completion.raw then os.remove(RPC.."request.json") end
    completion=nil
end
local function service_request()
    if completion then finish_completion(); return end
    local raw,read_error=read_file(RPC.."request.json",MAX_REQUEST)
    if read_error then reject_invalid_queue("Request exceeds size limit",raw); return end
    if not raw then return end
    local decoded,request=pcall(Json.decode,raw,{max_bytes=MAX_REQUEST,max_depth=32})
    if not decoded or type(request)~="table" or not uuid(request.request_id) then
        reject_invalid_queue("Malformed JSON request or missing canonical request UUID",raw); return
    end
    local response_path=RPC.."responses/"..request.request_id..".json"
    if exists(response_path) then
        -- A response with this id was already committed. Read-only requests are not repeated.
        if read_file(RPC.."request.json",MAX_REQUEST)==raw then os.remove(RPC.."request.json") end
        return
    end
    local ok,value=pcall(function() local epoch=validate(request); return dispatch(request,epoch) end)
    local response={protocol_version=1,request_id=request.request_id,ok=ok}
    if ok then response.result=value
    elseif type(value)=="table" and type(value.code)=="string" and type(value.message)=="string" then response.error=value
    else response.error={code="backend_unavailable",message="Runtime handler failed"}; log_error(value) end
    completion={request_id=request.request_id,raw=raw,response=response}
    finish_completion()
end
local function tick()
    local ready,ready_error=pcall(initialize_runtime)
    if not ready then startup_error="Runtime initialization failed"; log_error(ready_error) end
    if instance_id and os.time()-last_heartbeat>=HEARTBEAT_SECONDS then
        atomic_json(RPC.."capabilities.json",capabilities(),true)
        last_heartbeat=os.time()
    end
    service_request()
    if storage_runtime then storage_runtime.tick() end
end

assert(type(LoopAsync)=="function" and type(ExecuteInGameThread)=="function", "UE4SS scheduling APIs unavailable")
print("[PalLiveBridge RPC] Live core loaded; waiting for runtime validation.\n")
LoopAsync(POLL_MS,function()
    if tick_queued then return false end
    tick_queued=true
    ExecuteInGameThread(function()
        local ok,err=pcall(tick)
        tick_queued=false
        if not ok then log_error(err) end
    end)
    return false
end)

local directory = debug.getinfo(1,'S').source:match('^@(.*[/\\])')
dofile(directory .. 'normal-rebuild-execute.lua')
