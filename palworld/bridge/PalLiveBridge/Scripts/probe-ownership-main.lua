-- One-shot READ-ONLY BridgeLab ownership probe. Root deploys this as main.lua if desired.
-- No force-loading or object creation: readers calls GetConcreteModel(false) only.
local OUTPUT="D:/PalworldServer-LAN/BridgeLab/rpc/ownership-live.json"
local source=debug.getinfo(1,"S").source
assert(source:sub(1,1)=="@","script path unavailable")
local directory=assert(source:sub(2):match("^(.*[/\\])"),"script directory unavailable")
local Readers=dofile(directory.."readers.lua")
local Targets=dofile(directory.."targets.lua")
local Json=dofile(directory.."json.lua")
local ran=false
local function counts()
    local result={}
    for _,class in ipairs({"PalMapObjectItemChestModel","PalMapObjectItemContainerModule","PalItemContainer"})do
        local n=0
        for _,obj in ipairs(FindAllOf(class) or {})do
            if obj and obj:IsValid() and not obj:GetFullName():find("Default__",1,true)then n=n+1 end
        end
        result[class]=n
    end
    return result
end
local function run()
    if ran then return end
    ran=true
    local ok,result=pcall(function()
        local before=counts()
        local ownership=Readers.ownership(Targets,{require_snapshot_ownership=false})
        Json.array(ownership.chests);Json.array(ownership.errors)
        for _,row in ipairs(ownership.chests)do Json.array(row.slots)end
        local after=counts()
        local unchanged=true
        for k,v in pairs(before)do if after[k]~=v then unchanged=false end end
        return {probe="ordinary_chest_live_ownership_no_force",before_counts=before,after_counts=after,
            counts_unchanged=unchanged,force_concrete_requested=false,ownership=ownership,
            counts_note="Counts are diagnostic; unrelated game activity can also change them."}
    end)
    if not ok then result={ok=false,error=tostring(result),probe="ordinary_chest_live_ownership_no_force"}end
    local wrote,err=pcall(function()
        local temp=OUTPUT..".tmp"
        local f=assert(io.open(temp,"wb"))
        assert(f:write(Json.encode(result,{max_bytes=8388608})));assert(f:close())
        os.remove(OUTPUT);assert(os.rename(temp,OUTPUT))
    end)
    print("[PalLiveBridge ownership probe] written="..tostring(wrote).." verified_live="..
        tostring(result.ownership and result.ownership.verified_live).." error="..tostring(err).."\n")
end
ExecuteWithDelay(20000,function()ExecuteInGameThread(run)end)
