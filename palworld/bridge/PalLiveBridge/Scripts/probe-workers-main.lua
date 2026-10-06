-- Independent READ-ONLY lab probe. Root deploys centrally; no native assignments.
local OUTPUT='D:/PalworldServer-LAN/BridgeLab/rpc/workers-live.json'
local source=debug.getinfo(1,'S').source
assert(source:sub(1,1)=='@','script path unavailable')
local directory=assert(source:sub(2):match('^(.*[/\\])'),'script directory unavailable')
package.path=directory..'?.lua;'..package.path
local Workers=require('workers')
local Json=require('json')
local ran=false
local function run()
    if ran then return end; ran=true
    local ok,result=pcall(function()
        local snapshot=Workers.list({include_suitabilities=true})
        local examples=Json.array({})
        if snapshot.ok then
            for _,base in ipairs(snapshot.bases) do
                examples[#examples+1]=Workers.plan(snapshot,{base_id=base.id,roles={
                    {suitability='Mining',count=1},{suitability='Handcraft',count=1},{suitability='Transport',count=1}}})
            end
        end
        return {probe='worker_native_getters_and_pure_plan',snapshot=snapshot,
            example_plans=examples,example_demand_note='Illustrative role counts only; no inferred facility needs.',
            native_assignment_called=false}
    end)
    if not ok then result={ok=false,error=tostring(result),probe='worker_native_getters_and_pure_plan'} end
    local wrote,err=pcall(function()
        local temp=OUTPUT..'.tmp';local f=assert(io.open(temp,'wb'))
        assert(f:write(Json.encode(result,{max_bytes=8388608})));assert(f:close())
        os.remove(OUTPUT);assert(os.rename(temp,OUTPUT))
    end)
    print('[PalLiveBridge workers probe] written='..tostring(wrote)..' count='..
        tostring(result.snapshot and result.snapshot.worker_count)..' error='..tostring(err)..'\n')
end
ExecuteWithDelay(20000,function()ExecuteInGameThread(run)end)
