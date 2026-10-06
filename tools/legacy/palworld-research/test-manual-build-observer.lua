local root='work/palworld-live/'
local J=dofile(root..'bridge/PalLiveBridge/Scripts/json.lua')
local Core=dofile(root..'lab/manual-build-observer-core.lua')
local passed=0
local function wrap(value)return{get=function()return value end,set=function()error('MUTATION FORBIDDEN')end}end
local function env(expiry)
    local t=1000;local callbacks={};local emits={};local removed={};local snapshots=0;local stopping=false
    local config={observation_id='00000000-0000-4000-8000-000000000001',target_player_uid='host',expires_unix=expiry or 1200}
    local o=Core.start{json=J,config=config,now=function()return t end,is_game_thread=function()return true end,
        match_context=function(kind,c)return c==(kind=='request'and'component'or'state')end,
        register=function(path,fn)callbacks[path]=fn;return 11,12 end,
        unregister=function(path,a,b)assert(a==11 and b==12);removed[#removed+1]=path end,
        emit=function(r)emits[#emits+1]=J.decode(J.encode(r))end,
        snapshot=function()snapshots=snapshots+1;return{Wood=snapshots==1 and 30 or 15,Stone=snapshots==1 and 10 or 5}end,
        stop_requested=function()return stopping end}
    local function req(build,archives,debug,context)
        return callbacks[Core.REQUEST](wrap(context or'component'),wrap(build or'ItemChest'),wrap{X=1,Y=2,Z=3},wrap{X=0,Y=0,Z=0,W=1},wrap(archives or{}),wrap{bNotConsumeMaterials=debug==true})
    end
    local function result(code,loc,context)
        return callbacks[Core.RESULT](wrap(context or'state'),wrap(code or 62),wrap{InstallLocation=loc or{X=1,Y=2,Z=3},CurrentBuildingNum=7})
    end
    return{o=o,req=req,result=result,callbacks=callbacks,removed=removed,emits=emits,advance=function(n)t=t+n end,
        stop=function()stopping=true end,snapshots=function()return snapshots end}
end
local function case(name,fn)local ok,e=pcall(fn);assert(ok,name..': '..tostring(e));passed=passed+1;print('ok '..name)end
case('armed_and_no_mutation',function()local e=env();assert(e.o.report.status=='armed'and e.snapshots()==0 and e.o.report.mutation_calls==0)end)
case('ignores_other_player',function()local e=env();assert(e.req(nil,nil,nil,'other')==nil);assert(not e.o.report.request)end)
case('ignores_other_build',function()local e=env();assert(e.req('MetalChest')==nil);assert(not e.o.report.request)end)
case('copies_bytes_and_does_not_retain_remote',function()
    local e=env();local data={wrap(0),wrap(255),wrap(128),wrap(65)};local ar={wrap{Bytes=data}}
    assert(e.req(nil,ar)==nil);data[1]=wrap(12);ar[1]=nil
    assert(e.o.report.request.archives[1].hex=='00ff8041'and e.o.report.request.archive_total_bytes==4)
    assert(e.o.report.request.debug.bNotConsumeMaterials==false)
end)
case('normal_success_needs_no_result',function()
    local e=env();e.req();e.advance(3);assert(e.o.tick()==true)
    assert(e.o.report.status=='complete'and e.snapshots()==2 and e.o.report.result_observation_available==false and #e.removed==2)
end)
case('copies_result_and_returns_nil',function()
    local e=env();e.req();assert(e.result()==nil);assert(e.o.report.result.code==62);e.advance(2);e.o.tick();assert(e.o.report.status=='complete')
end)
case('result_before_request_ignored',function()local e=env();e.result();assert(not e.o.report.result)end)
case('other_state_result_ignored',function()local e=env();e.req();e.result(nil,nil,'other');assert(not e.o.report.result)end)
case('mismatched_success_not_correlated',function()local e=env();e.req();e.result(62,{X=999,Y=0,Z=0});assert(not e.o.report.result and e.o.report.correlation_ambiguous)end)
case('failure_location_can_be_unset',function()local e=env();e.req();e.result(28,{X=0,Y=0,Z=0});assert(e.o.report.result.code==28 and e.o.report.result.location_matches==false)end)
case('second_request_never_replaces_first',function()local e=env();e.req();e.req();assert(e.o.report.extra_request_count==1 and e.snapshots()==1 and e.o.report.correlation_ambiguous)end)
case('archive_limit_stops_observing',function()local e=env();local ars={};for i=1,33 do ars[i]=wrap{Bytes={}}end;e.req(nil,ars);assert(e.o.report.status=='capture_error'and #e.removed==2)end)
case('invalid_byte_stops_observing',function()local e=env();e.req(nil,{wrap{Bytes={wrap(256)}}});assert(e.o.report.status=='capture_error')end)
case('expired_request_is_not_captured',function()local e=env();e.advance(201);e.req();assert(e.o.report.status=='expired'and not e.o.report.request)end)
case('operator_stop_and_idempotent_cleanup',function()local e=env();e.stop();e.o.tick();e.o.stop();e.req();assert(e.o.report.status=='operator_stopped'and #e.removed==2 and not e.o.report.request)end)
case('report_is_pure_json',function()local e=env();e.req(nil,{wrap{Bytes={wrap(0)}}});e.advance(3);e.o.tick();local r=J.decode(J.encode(e.o.report));assert(r.request.archives[1].hex=='00')end)
case('allows_15_minute_wait',function()local e=env(1900);e.advance(899);e.req();assert(e.o.report.request~=nil)end)
case('rejects_more_than_15_minutes',function()assert(not pcall(env,1901))end)
print('PASS '..passed..' passive observer cases')
