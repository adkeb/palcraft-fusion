-- Passive one-shot capture. This module NEVER invokes a game RPC or writes a param.
-- Host supplies fixed Lab-only I/O and the already verified real player context.
local M={}
M.REQUEST='/Script/Pal.PalNetworkPlayerComponent:RequestBuild_ToServer'
M.RESULT='/Script/Pal.PalPlayerState:ReceiveBuildResult_ToRequestClient'
local function finite(n)assert(type(n)=='number'and n==n and math.abs(n)<math.huge,'nonfinite parameter');return n end
local function integer(n,min,max)n=finite(n);assert(n%1==0 and n>=min and n<=max,'integer outside bound');return n end
local function unwrap(v)
    if type(v)=='userdata'then local ok,f=pcall(function()return v.get end);if ok and type(f)=='function'then return v:get()end end
    -- Table branch also permits mocks. Real structs returned as Lua tables have no get member.
    if type(v)=='table'and type(v.get)=='function'then return v:get()end
    return v
end
local function vector(v,quat)
    v=unwrap(v);local r={X=finite(unwrap(v.X)),Y=finite(unwrap(v.Y)),Z=finite(unwrap(v.Z))}
    if quat then r.W=finite(unwrap(v.W))end;return r
end
local function sequence(v,max)
    v=unwrap(v)
    if type(v)=='table'then assert(#v<=max,'array exceeds bound');return #v,function(i)return unwrap(v[i+1])end end
    local n=integer(v:GetArrayNum(),0,max);return n,function(i)return unwrap(v[i+1])end
end
function M.start(d)
    local J=assert(d.json);local now=assert(d.now);local cfg=assert(d.config)
    assert(type(cfg.observation_id)=='string'and #cfg.observation_id==36,'invalid observation id')
    assert(cfg.expires_unix>now()and cfg.expires_unix<=now()+900,'expiry must be within 900 seconds')
    assert(type(d.match_context)=='function'and type(d.emit)=='function','missing dependencies')
    local report={probe='manual_build_observer',version=1,lab_only=true,read_only=true,mutation_calls=0,
        observation_id=cfg.observation_id,target_player_uid=cfg.target_player_uid,created_unix=now(),expires_unix=cfg.expires_unix,
        status='initializing',errors=J.array(),unmatched_results=J.array(),extra_request_count=0,
        native_result_hook_on_server_verified=false,model_guid_correlated=false,
        material_scope='Selected player carried counts plus preconfigured ordinary chest subset; differences are observations, not proof of the complete engine consume set.'}
    local hooks={};local stopped=false;local pending_snapshot_at
    local function emit()local ok,e=pcall(d.emit,report);if not ok then print('[ManualBuildObserver] report write failed: '..tostring(e)..'\n')end end
    local function problem(stage,e)report.errors[#report.errors+1]={stage=stage,error=tostring(e)}end
    local function snapshot(label)
        if not d.snapshot then return end
        local ok,data=pcall(d.snapshot);if ok then report[label]=data else problem(label,data)end
    end
    local function unregister()
        for _,h in ipairs(hooks)do local ok,e=pcall(d.unregister,h.path,h.pre,h.post);if not ok then problem('unregister',e)end end
        hooks={}
    end
    local function stop(reason)
        if stopped then return end;stopped=true;unregister();report.stopped_unix=now()
        report.status=reason or'stopped';emit()
    end
    local function guarded(callback)
        return function(...)
            -- All callbacks intentionally return nil: no override of original execution.
            if stopped then return end
            if now()>=cfg.expires_unix then stop('expired');return end
            local ok,e=pcall(callback,...)
            if not ok then problem('hook',e);stop('capture_error')end
        end
    end
    local request=guarded(function(context,build,location,rotation,archives,debugparam)
        if not d.match_context('request',unwrap(context))then return end
        if report.request then report.extra_request_count=report.extra_request_count+1;report.correlation_ambiguous=true;emit();return end
        build=unwrap(build);local name=type(build)=='string'and build or build:ToString()
        if name~='ItemChest'then return end
        assert(d.is_game_thread(),'request hook did not execute on game thread')
        local copied={build_id=name,location=vector(location),rotation=vector(rotation,true),archives=J.array(),observed_unix=now()}
        -- Claim the one observation before reading variable-length data. Errors never rearm.
        report.request=copied;report.status='request_observed'
        local n,at=sequence(archives,32);local total=0
        for i=0,n-1 do
            local ar=at(i);local count,byte=sequence(ar.Bytes,65536);total=total+count;assert(total<=262144,'archive total exceeds bound')
            local hex={};for j=0,count-1 do hex[#hex+1]=string.format('%02x',integer(byte(j),0,255))end
            copied.archives[#copied.archives+1]={byte_count=count,hex=table.concat(hex)}
        end
        copied.archive_total_bytes=total;local dbg=unwrap(debugparam)
        local flag=unwrap(dbg.bNotConsumeMaterials);assert(type(flag)=='boolean','invalid debug flag')
        copied.debug={bNotConsumeMaterials=flag};copied.normal_consume_requested=flag==false
        snapshot('materials_before_request');pending_snapshot_at=now()+3;emit()
    end)
    local result=guarded(function(context,code,params)
        if not report.request or report.result or not d.match_context('result',unwrap(context))then return end
        assert(d.is_game_thread(),'result hook did not execute on game thread')
        code=integer(unwrap(code),0,255);params=unwrap(params)
        local row={code=code,install_location=vector(params.InstallLocation),current_building_num=integer(unwrap(params.CurrentBuildingNum),0,2147483647),observed_unix=now()}
        local a,b=row.install_location,report.request.location
        row.location_distance_cm=math.sqrt((a.X-b.X)^2+(a.Y-b.Y)^2+(a.Z-b.Z)^2)
        row.location_matches=row.location_distance_cm<=2
        if code==62 and not row.location_matches then
            if #report.unmatched_results<8 then report.unmatched_results[#report.unmatched_results+1]=row end
            report.correlation_ambiguous=true;emit();return
        end
        report.result=row;report.native_result_hook_on_server_verified=true
        report.correlation_basis=code==62 and 'same verified player state; sole captured request; matching install location; bounded window'
            or'same verified player state and bounded window only; failure location may be unset, no request ID'
        report.status='result_observed';pending_snapshot_at=now()+2;unregister();emit()
    end)
    local ok,e=pcall(function()
        local pre,post=d.register(M.RESULT,result);hooks[#hooks+1]={path=M.RESULT,pre=pre,post=post}
        pre,post=d.register(M.REQUEST,request);hooks[#hooks+1]={path=M.REQUEST,pre=pre,post=post}
    end)
    if not ok then problem('register',e);stop('registration_failed')else report.status='armed';emit()end
    local function tick()
        if stopped then return true end
        if pending_snapshot_at and now()>=pending_snapshot_at then
            assert(d.is_game_thread(),'snapshot tick must be on game thread');snapshot('materials_after_request')
            report.result_observation_available=report.result~=nil
            report.result_note='Normal success does not send this client result RPC; absence is not failure. Confirm construction using a unique new registered model and BuildProcess/material observations.'
            stop('complete');return true
        end
        if d.stop_requested and d.stop_requested()then stop('operator_stopped');return true end
        if now()>=cfg.expires_unix then
            if report.request then snapshot('materials_at_timeout')end
            stop(report.request and 'request_observed_result_not_seen'or'expired_without_request');return true
        end
        return false
    end
    return{tick=tick,stop=stop,report=report}
end
return M
