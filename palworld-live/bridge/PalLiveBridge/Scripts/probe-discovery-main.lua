-- One-shot READ-ONLY lab discovery + old 18-target comparison. Root deploys.
local OUTPUT='D:/PalworldServer-LAN/BridgeLab/rpc/discovery-live.json'
local source=debug.getinfo(1,'S').source
assert(source:sub(1,1)=='@','script path unavailable')
local dir=assert(source:sub(2):match('^(.*[/\\])'),'script directory unavailable')
package.path=dir..'?.lua;'..package.path
local D=require('discovery');local T=require('targets');local J=require('json')
local ran=false
local function count()
    local n=0
    for _,o in ipairs(FindAllOf('PalMapObjectItemChestModel')or{})do
        if o and o:IsValid()and not o:GetFullName():find('Default__',1,true)then n=n+1 end
    end
    return n
end
local function run()
    if ran then return end;ran=true
    local ok,result=pcall(function()
        local before=count();local discovery=D.discover();local after=count()
        return {probe='existing_ordinary_chest_discovery',discovery=discovery,
            comparison=D.compare_known(discovery.targets,T),before_count=before,after_count=after,
            count_unchanged=before==after,force_concrete_requested=false}
    end)
    if not ok then result={ok=false,error=tostring(result),probe='existing_ordinary_chest_discovery'}end
    local wrote,err=pcall(function()
        local temp=OUTPUT..'.tmp';local f=assert(io.open(temp,'wb'))
        assert(f:write(J.encode(result,{max_bytes=8388608})));assert(f:close())
        os.remove(OUTPUT);assert(os.rename(temp,OUTPUT))
    end)
    print('[PalLiveBridge discovery probe] written='..tostring(wrote)..' count='..
        tostring(result.discovery and result.discovery.discovered_count)..' error='..tostring(err)..'\n')
end
ExecuteWithDelay(20000,function()ExecuteInGameThread(run)end)
