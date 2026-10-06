local REAL=dofile
local J=REAL('work/palworld-live/bridge/PalLiveBridge/Scripts/json.lua')
local probe=assert(loadfile('work/palworld-live/lab/production-build-preflight.lua'))
local source='@D:/steam/steamapps/common/PalServer/Pal/Binaries/Win64/ue4ss/Mods/PalLiveBridge/Scripts/prod-probe.lua'
local mode,files,previews='ok',{},0
local id='11111111-2222-3333-4444-555555555555'
local function object(t)
 t=t or{};t.IsValid=function()return true end;t.GetFullName=function()return 'live object'end;return t
end
local model=object{BuildObjectId='Wooden_foundation'}
function model:GetConcreteModel(force)
 assert(force==false)
 return object{GetModelInstanceId=function()return id end,GetBaseCampIdBelongTo=function()return id end,
 GetTransform=function()return{Translation={X=mode=='nan'and(0/0)or 0,Y=0,Z=0}}end}
end
local block=object{BuildObjectId='ItemChest'};block.GetConcreteModel=model.GetConcreteModel
local op=object{DataMap=object{GetById=function(_,n)assert(n=='ItemChest');return{MapObjectId='ItemChest',RequiredBuildWorkAmount=1000,Material1_Id='Wood',Material1_Count=15,Material2_Id='Stone',Material2_Count=5,Material3_Count=0,Material4_Count=0}end}}
function FindAllOf(c)
 if c=='PalMapObjectManager'then return{object{GetBuildOperator=function()return op end}}end
 if c=='PalMapObjectModel'then return mode=='blocked'and{model,block}or{model}end
 error(c)
end
function StaticFindObject()return object{NewGuid=function()return id end}end
function FName(s)return s end
function IsInGameThread()return true end
function ExecuteWithDelay(_,f)f()end
function ExecuteInGameThread(f)f()end
debug.getinfo=function()return{source=source}end
local R={guid_to_string=function(v)return v end}
function R.bases()return{ok=true,bases={{id=id,group_id=id,position={x=0,y=0,z=0},ok=true,available=true,range=3500}}}end
function R.chests(_,opts)
 assert(opts.include_items and opts.verify_ownership and opts.require_snapshot_ownership)
 return{ok=true,verified_live=true,chests={{ok=true,verified_live=true,id=id,base_id_live=id,group_id_live=id,slots={{empty=false,item='Wood',count=22},{empty=false,item='Stone',count=12}}}}}
end
local B={}
function B.new(opts)
 assert(opts.allow_apply==false)
 return{players=function()return{ok=true,players=mode=='no_players'and{}or{{player_uid=id,guild_id=id,position={x=0,y=0,z=100}}}}end,
 preview=function(p)previews=previews+1;assert(p.structures[1].build_id=='ItemChest');if mode=='insufficient'then error({code='insufficient_materials',message='carry Wood'})end;return{apply_enabled=false}end,
 apply=function()error('MUTATION FORBIDDEN')end}
end
dofile=function(p)
 if p:match('json.lua$')then return J elseif p:match('readers.lua$')then return R elseif p:match('build.lua$')then return B elseif p:match('targets.lua$')then return{}end;error(p)
end
io.open=function(p,m)assert(m=='wb');return{write=function(_,s)files[p]=s;return true end,close=function()return true end}end
os.remove=function(p)files[p]=nil;return true end
os.rename=function(a,b)files[b]=assert(files[a]);files[a]=nil;return true end
local function run(m)
 mode=m;files={};previews=0;probe();return J.decode(assert(files['D:/PalworldServer-LAN/LiveControl/rpc/production-build-preflight.json']))
end
local r=run('ok');assert(r.ok and previews==1 and r.players[1].preview_ok and r.base_materials[1].counts.Wood==22)
r=run('insufficient');assert(r.ok and previews==1 and r.players[1].preview_error.code=='insufficient_materials')
r=run('no_players');assert(r.ok and previews==0 and #r.players==0)
r=run('blocked');assert(r.ok and previews==0 and r.players[1].candidates[1].blocker_count==1)
r=run('nan');assert(not r.ok and previews==0 and #r.model_read_errors==1)
source='@D:/PalworldServer-LAN/BridgeLab/Scripts/main.lua';assert(not pcall(probe))
print('6 production readonly preflight mock checks passed; no gameplay mutator called')
