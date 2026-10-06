-- Install only as BridgeLab PalLiveBridge/Scripts/main.lua after separate diagnostic/review.
-- This candidate must replace the RPC main. Do not append it to another task loop.
-- Top-level execution is pure Lua plus ONE delayed-GT registration. No module/file/UE read.
local source=debug.getinfo(1,'S').source
assert(source:gsub('\\','/'):lower()=='@d:/palworldserver-lan/bridgelab/pal/binaries/win64/ue4ss/mods/pallivebridge/scripts/main.lua','Exact BridgeLab main.lua required')
local directory=assert(source:match('^@(.*[/\\])'))
local LOG='D:/PalworldServer-LAN/BridgeLab/rpc/hook-free-rebuild-v4-serial-scheduler.log'
local GUARD='__PalLiveBridgeSerialV4SingleRegistration'
if rawget(_G,GUARD)then return rawget(_G,GUARD)end
local state={scheduled=false,stopped=false,ticks=0,initial_delay_ms=5000,tick_delay_ms=1000,max_ticks=30,max_seconds=30}
rawset(_G,GUARD,state)
local runner
local function safe_text(value)
    local ok,s=pcall(tostring,value);if not ok then s='<error tostring failed>'end
    return s:sub(1,2048):gsub('[\r\n]',' ')
end
local function plain(line)
    local f=assert(io.open(LOG,'ab'),'scheduler text log unavailable')
    assert(f:write(tostring(os.time())..' '..line..'\n'));assert(f:flush());assert(f:close())
end
local function safe_plain(line)
    local ok,e=pcall(plain,line)
    pcall(print,'[HookFreeRebuildSerial] '..line..(ok and''or' LOG_WRITE_FAILED '..safe_text(e))..'\n')
end
local function stop(reason,error_value)
    if state.stopped then return end
    state.stopped=true;state.stop_reason=reason;state.error=error_value and safe_text(error_value)or nil
    -- Do not attempt JSON serialization in an exception handler. Last JSON may be incomplete;
    -- the durable v4 fence remains authoritative and must never be removed for an automatic retry.
    if runner and type(runner.report)=='table'and not runner.report.finished_unix then
        runner.report.status='indeterminate_no_retry';runner.report.finished_unix=os.time()
    end
    if runner and type(runner.report)=='table'and type(runner.report.errors)=='table'then
        for i=1,math.min(#runner.report.errors,3)do
            local prior=runner.report.errors[i]
            if type(prior)=='table'then safe_plain('FIRST_ERROR '..i..' stage='..safe_text(prior.stage)..' error='..safe_text(prior.error))end
        end
    end
    safe_plain('STOP '..reason..' ticks='..state.ticks..' last_json_may_be_incomplete=true no_retry=true'..(state.error and' error='..state.error or''))
end
local next_tick
local function after_step()
    assert(type(runner.report)=='table','runner report missing')
    if runner.report.finished_unix then
        plain('FINISHED status='..safe_text(runner.report.status)..' ticks='..state.ticks..' no_retry=true')
        state.stopped=true;state.stop_reason='runner_finished'
        return false
    end
    if state.ticks>=state.max_ticks or os.time()-state.started_unix>=state.max_seconds then
        stop('observation_bound');return false
    end
    return true
end
next_tick=function()
    if state.stopped then return end
    local ok,e=pcall(function()
        assert(type(IsInGameThread)=='function'and IsInGameThread(),'tick must run on game thread')
        if os.time()-state.started_unix>state.max_seconds then stop('late_callback');return end
        assert(state.ticks<state.max_ticks,'tick bound exceeded')
        state.ticks=state.ticks+1
        plain('TICK '..state.ticks)
        runner.tick()
        return after_step()
    end)
    if not ok then stop('tick_error',e);return end
    -- Last action in a successful callback: no Lua work after next registration.
    if e then return ExecuteInGameThreadWithDelay(1000,next_tick)end
end
local function first_callback()
    if state.stopped then return end
    local ok,e=pcall(function()
        assert(type(IsInGameThread)=='function'and IsInGameThread(),'start must run on game thread')
        state.started_unix=os.time()
        plain('START serial_gt_candidate v4_fence_namespace=true runtime_isolation_not_yet_verified=true')
        runner=dofile(directory..'hook-free-rebuild-serial.lua')
        if runner==nil then plain('NO_REPLAY existing_report');state.stopped=true;state.stop_reason='existing_report_no_replay';return end
        assert(type(runner)=='table'and type(runner.start)=='function'and type(runner.tick)=='function','invalid serial host runner')
        runner.start()
        return after_step()
    end)
    if not ok then stop('start_error',e);return end
    if e then return ExecuteInGameThreadWithDelay(1000,next_tick)end
end
assert(type(ExecuteInGameThreadWithDelay)=='function','delayed GT scheduling API unavailable')
state.scheduled=true
-- Final main action. The 5-second delay is a mitigation, not a proven VM start barrier.
return ExecuteInGameThreadWithDelay(5000,first_callback)
