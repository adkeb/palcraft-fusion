-- Reuses the complete mocked native owner chain and all 18 known targets.
dofile('work/palworld-live/research/test-readers-ownership.lua')
local scripts='work/palworld-live/bridge/PalLiveBridge/Scripts/'
package.path=scripts..'?.lua;'..package.path
local R=require('readers');local T=require('targets');local D=require('discovery');local J=require('json')
local native_find=FindAllOf
local mm=native_find('PalMapObjectManager')[1]
local concretes={}
for _,t in ipairs(T.chests)do
    local c=mm:FindModel(t.instance_guid):GetConcreteModel(false)
    function c:GetTransform()return {Translation={X=1,Y=2,Z=3}}end
    concretes[#concretes+1]=c
end
local function fake(kind)
    return {IsValid=function()return true end,GetFullName=function()return 'excluded '..kind end,
        GetModelInstanceId=function()return{A=0,B=0,C=0,D=0}end,
        TryGetMapObjectId=function()return kind end}
end
concretes[#concretes+1]=fake('PalFoodBox');concretes[#concretes+1]=fake('GuildChest');concretes[#concretes+1]=fake('Workbench')
function FindAllOf(class)if class=='PalMapObjectItemChestModel'then return concretes end;return native_find(class)end
if arg and arg[1]=='escrow'then
 local t=T.chests[1]
 for _,key in ipairs({'container','model'})do
  _G.PalCraftEscrowExclusions={is_reserved=function(cid,mid)return key=='container'and cid==t.container_id or key=='model'and mid==t.instance_id end}
  local report=D.discover();assert(report.ok and report.discovered_count==17)
  local found=false;for _,x in ipairs(report.excluded)do if x.reason=='exchange_escrow_reserved'then found=true end end
  assert(found,'Actual discovery must label the reserved '..key)
 end
 _G.PalCraftEscrowExclusions=nil;assert(D.discover().discovered_count==18)
 print('PASS actual discovery: CID/model escrow exclusion and ordinary restoration');return
end
local report=D.discover()
assert(report.ok and report.verified_live and report.discovered_count==18 and #report.excluded==3)
assert(report.targets.snapshot_sha256:match('^runtime%-') and not report.targets.snapshot_sha256_is_file_hash)
assert(report.targets.chests[1].world_position==nil)
local cmp=D.compare_known(report.targets,T);assert(cmp.exact_match and cmp.all_known_match and cmp.matched==18)
local decoded=J.decode(J.encode(report));assert(decoded.discovered_count==18 and #decoded.verification.chests==18)
local filtered=D.discover({group_id=T.chests[1].group_id});assert(filtered.ok and filtered.discovered_count==18)
filtered=D.discover({group_id='11111111-2222-3333-4444-555555555555'});assert(filtered.ok and filtered.discovered_count==0 and not filtered.verified_live)
concretes[#concretes+1]=concretes[1];assert(not D.discover().ok,'duplicate binding must fail closed');concretes[#concretes]=nil
local transform=concretes[1].GetTransform
concretes[1].GetTransform=function()error('FATAL: GetTransform must not be called')end
local no_pos=D.discover();assert(no_pos.ok and no_pos.verified_live and #no_pos.warnings==0)
concretes[1].GetTransform=transform
local copied=J.decode(J.encode(report.targets));copied.chests[1].expected_capacity=copied.chests[1].expected_capacity+1
cmp=D.compare_known(copied,T);assert(not cmp.exact_match and #cmp.mismatches==1)
copied=J.decode(J.encode(report.targets));table.remove(copied.chests,1)
cmp=D.compare_known(copied,T);assert(not cmp.all_known_match and #cmp.missing==1)
local none={chests={}};cmp=D.compare_known(report.targets,none);assert(cmp.all_known_match and not cmp.exact_match and #cmp.extra==18)
print('Discovery tests passed: exact 18 known bindings, strict owner recheck, no-force lookups, skipped invalid model IDs, guild filter, duplicate rejection, omitted coordinates and stable comparison.')
