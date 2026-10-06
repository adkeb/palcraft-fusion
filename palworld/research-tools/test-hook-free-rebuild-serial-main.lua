-- Pure Lua scheduling contract mocks. No UE runtime or claim of multi-thread VM safety.
local P='work/palworld-live/'
local function read(p)local f=assert(io.open(p,'rb'));local s=f:read('*a');f:close();return s end
local source=read(P..'lab/hook-free-rebuild-serial-main.lua')
local DIR='D:/PalworldServer-LAN/BridgeLab/Pal/Binaries/Win64/ue4ss/Mods/PalLiveBridge/Scripts/'
local LOG='D:/PalworldServer-LAN/BridgeLab/rpc/hook-free-rebuild-v4-serial-scheduler.log'
local function setup(o)
    o=o or{};local now=0;local gt=false;local queue={};local regs={};local loads=0;local reads=0;local ue=0;local text={};local starts=0;local ticks=0
    local env=setmetatable({},{__index=_G});env._G=env
    local runner={report={status='created',errors={}}}
    local function ongt()assert(gt,'business outside GT')end
    runner.start=function()
        ongt();starts=starts+1
        if o.start_error then runner.report.errors={{stage='preflight',error='ORIGINAL_JSON_OR_REGISTRY_ERROR'}};error('SECONDARY_ENCODE_ERROR')end
        runner.report.status='observing'
        if o.preview then runner.report.status='preview_ready';runner.report.finished_unix=now/1000 end
    end
    runner.tick=function()
        ongt();ticks=ticks+1
        if o.tick_error then error('TICK_FAILURE')end
        if o.complete_at and ticks>=o.complete_at then runner.report.status='normal_construction_observed';runner.report.finished_unix=now/1000 end
    end
    env.os={time=function()return math.floor(now/1000)end}
    env.io={open=function(path,mode)
        reads=reads+1;ongt();assert(path==LOG and mode=='ab','non-Lab log access')
        if o.log_error then return nil end
        return{write=function(_,line)text[#text+1]=line;return true end,flush=function()return true end,close=function()return true end}
    end}
    env.print=function(line)text[#text+1]=line end
    env.dofile=function(path)
        ongt();loads=loads+1;assert(path==DIR..'hook-free-rebuild-serial.lua','unexpected module')
        if o.load_error then error('HOST_LOAD_ERROR')end
        if o.existing_report then return nil end
        return runner
    end
    env.IsInGameThread=function()ue=ue+1;return gt end
    for _,name in ipairs({'LoopAsync','ExecuteInGameThread','ExecuteWithDelay','RegisterHook','UnregisterHook','FindAllOf','StaticFindObject'})do env[name]=function()error('forbidden scheduler/world API '..name)end end
    env.ExecuteInGameThreadWithDelay=function(ms,fn)
        assert(#queue==0,'more than one pending callback')
        regs[#regs+1]={at=now,ms=ms}
        assert(ms==( #regs==1 and 5000 or 1000),'wrong delay')
        if o.immediate_first and #regs==1 then gt=true;fn();gt=false;return 1 end
        queue[#queue+1]={at=now+ms,fn=fn};return #regs
    end
    local e={runner=runner,regs=regs,queue=queue,env=env}
    function e.boot(path)return assert(load(source,'@'..(path or(DIR..'main.lua')),'t',env))()end
    function e.step(extra,wrong_thread)
        assert(#queue==1);local q=table.remove(queue,1);now=q.at+(extra or 0);gt=not wrong_thread;q.fn();gt=false
    end
    function e.stats()return{reads=reads,ue=ue,loads=loads,starts=starts,ticks=ticks,now=now,text=table.concat(text),state=env.__PalLiveBridgeSerialV4SingleRegistration}end
    return e
end
local n=0;local function test(name,f)local ok,e=pcall(f);assert(ok,name..': '..tostring(e));n=n+1;print('ok '..name)end
test('main_registers_once_with_zero_file_module_or_ue_reads',function()local e=setup();e.boot();local s=e.stats();assert(#e.regs==1 and #e.queue==1 and e.queue[1].at==5000);assert(s.reads==0 and s.loads==0 and s.ue==0 and s.starts==0)end)
test('duplicate_main_same_vm_does_not_register_again',function()local e=setup();e.boot();e.boot();assert(#e.regs==1)end)
test('production_and_wrong_filename_reject_before_io',function()for _,p in ipairs({'D:/steam/steamapps/common/PalServer/Pal/Binaries/Win64/ue4ss/Mods/PalLiveBridge/Scripts/main.lua',DIR..'wrong-main.lua'})do local e=setup();assert(not pcall(e.boot,p));local s=e.stats();assert(#e.regs==0 and s.reads==0 and s.loads==0 and s.ue==0)end end)
test('host_and_start_inside_first_gt_then_single_tick_chain',function()local e=setup{complete_at=3};e.boot();e.step();assert(e.stats().starts==1 and e.stats().loads==1 and #e.queue==1);for _=1,3 do e.step()end;local s=e.stats();assert(s.ticks==3 and s.state.stopped and #e.queue==0 and #e.regs==4 and s.now==8000)end)
test('preview_terminal_schedules_no_tick',function()local e=setup{preview=true};e.boot();e.step();assert(e.stats().starts==1 and e.stats().ticks==0 and #e.queue==0)end)
test('existing_report_no_replay_or_followup',function()local e=setup{existing_report=true};e.boot();e.step();assert(e.stats().starts==0 and #e.queue==0 and e.stats().state.stop_reason=='existing_report_no_replay')end)
test('original_error_logged_before_secondary_and_no_followup',function()local e=setup{start_error=true};e.boot();e.step();local s=e.stats();assert(s.state.stopped and #e.queue==0 and s.ticks==0);local a=s.text:find('ORIGINAL_JSON_OR_REGISTRY_ERROR',1,true);local b=s.text:find('SECONDARY_ENCODE_ERROR',1,true);assert(a and b and a<b)end)
test('tick_error_stops_no_second_start',function()local e=setup{tick_error=true};e.boot();e.step();e.step();local s=e.stats();assert(s.state.stop_reason=='tick_error'and s.starts==1 and s.ticks==1 and #e.queue==0 and s.text:find('TICK_FAILURE',1,true))end)
test('load_error_pure_text_and_stop',function()local e=setup{load_error=true};e.boot();e.step();local s=e.stats();assert(s.starts==0 and #e.queue==0 and s.state.stopped and s.text:find('HOST_LOAD_ERROR',1,true))end)
test('log_failure_stops_before_host_load',function()local e=setup{log_error=true};e.boot();e.step();local s=e.stats();assert(s.loads==0 and s.starts==0 and #e.queue==0 and s.state.stopped and s.text:find('LOG_WRITE_FAILED',1,true))end)
test('hard_observation_bound_30_ticks_and_30_seconds_after_start',function()local e=setup();e.boot();e.step();while #e.queue>0 do e.step()end;local s=e.stats();assert(s.ticks==30 and s.now==35000 and s.state.stop_reason=='observation_bound'and #e.regs==31)end)
test('late_callback_does_not_observe_past_window',function()local e=setup();e.boot();e.step();e.step(31000);local s=e.stats();assert(s.ticks==0 and s.state.stop_reason=='late_callback'and #e.queue==0)end)
test('wrong_thread_never_loads_host',function()local e=setup();e.boot();e.step(0,true);local s=e.stats();assert(s.loads==0 and s.starts==0 and s.state.stopped and #e.queue==0)end)
test('simulated_immediate_registration_reentry_has_no_post_registration_business',function()local e=setup{immediate_first=true,preview=true};e.boot();local s=e.stats();assert(s.loads==1 and s.starts==1 and s.state.stopped and #e.queue==0 and #e.regs==1)end)
print('PASS '..n..' serial main scheduling mocks; not a UE/runtime threading proof')
