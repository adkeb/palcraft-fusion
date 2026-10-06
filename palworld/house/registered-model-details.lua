-- Parent-controlled one-ID read-only probe. Lab only; never edits or enumerates models.
local source=debug.getinfo(1,'S').source
local directory=assert(source:match('^@(.*[/\\])'))
assert(directory:lower():gsub('\\','/')=='d:/palworldserver-lan/bridgelab/pal/binaries/win64/ue4ss/mods/pallivebridge/scripts/','BridgeLab only')
local ROOT='D:/PalworldServer-LAN/BridgeLab/rpc/'
local J=dofile(directory..'json.lua');local R=dofile(directory..'readers.lua');local Core=dofile(directory..'registered-model-details-core.lua')
local f=assert(io.open(ROOT..'registered-model-details-request.json','rb'));local raw=f:read(8193);f:close();assert(#raw<=8192,'input oversized');local cfg=J.decode(raw)
assert(type(cfg.observation_id)=='string'and cfg.observation_id:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$'),'invalid observation UUID')
local path=ROOT..'registered-model-details-'..cfg.observation_id..'.json'
local existing=io.open(path,'rb');if existing then existing:close();return end
ExecuteInGameThread(function()
    local ok,out=pcall(Core.read,{readers=R,json=J,is_game_thread=IsInGameThread,now=os.time,fname=FName,
        manager=function()
            -- Manager class only, never PalMapObjectModel or the world object list.
            local found={};for _,o in ipairs(FindAllOf('PalMapObjectManager')or{})do
                if o:IsValid()and not o:GetFullName():find('Default__',1,true)then found[#found+1]=o end
            end
            assert(#found==1,'expected one map-object manager');return found[1]
        end},cfg)
    if not ok then out={probe='registered_model_details',lab_only=true,read_only=true,ok=false,error=tostring(out)}end
    out.observation_id=cfg.observation_id
    local stream=assert(io.open(path..'.tmp','wb'));assert(stream:write(J.encode(out)));assert(stream:close());assert(os.rename(path..'.tmp',path))
    print('[RegisteredModelDetails] '..tostring(out.ok)..' '..cfg.model_id..'\n')
end)
