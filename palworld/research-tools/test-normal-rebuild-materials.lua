local prefix='work/palworld-live/'
local J=dofile(prefix..'bridge/PalLiveBridge/Scripts/json.lua')
local R0=dofile(prefix..'bridge/PalLiveBridge/Scripts/readers.lua')
local M=dofile(prefix..'lab/normal-rebuild-materials.lua')
local Z='00000000-0000-0000-0000-000000000000'
local function gid(n)return string.format('%08x-0000-0000-0000-000000000000',n)end
local function guid(s)return R0.guid_from_string(s)end
local function clone(t)return J.decode(J.encode(t))end
local function object(n,t)
    t=t or {};t.IsValid=function()return true end;t.GetFullName=function()return n end;return t
end
local passed=0
local function test(n,f)
    local ok,e=pcall(f);assert(ok,n..': '..tostring(e));passed=passed+1;print('ok '..n)
end
local function reject(f,needle)
    local ok,e=pcall(f);assert(not ok,'expected rejection');if needle then assert(tostring(e):find(needle,1,true),tostring(e))end
end
local function slot(id,i,item,n,localid)
    return {index=i,slot_id_index=i,container_id=id,item=item,count=n,empty=n==0,dynamicGuid=localid or Z,dynamicWorldGuid=Z}
end
local function fixture()
    local T={snapshot_sha256='fixed',chests={}}
    local report={ok=true,verified_live=true,chests={}}
    for i=1,13 do
        local id=gid(i)
        T.chests[i]={container_id=id,base_id=gid(40),group_id=gid(41),expected_capacity=2,type='ItemChest'}
        report.chests[i]={id=id,actual_id=id,ok=true,verified_live=true,eligible_for_snapshot_plan=true,
            base_id_live=gid(40),group_id_live=gid(41),capacity=2,slots={slot(id,0,'None',0),slot(id,1,'None',0)}}
    end
    report.chests[1].slots[1]=slot(gid(1),0,'Wood',15)
    report.chests[1].slots[2]=slot(gid(1),1,'Stone',5)
    report.chests[2].slots[1]=slot(gid(2),0,'Weapon',1,gid(999))
    local carry={slot(gid(100),0,'Wood',15),slot(gid(100),1,'Stone',5),slot(gid(100),2,'None',0)}
    local inv=object('Inventory',{OwnerPlayerUId=guid(gid(200)),MyInventoryInfo={CommonContainerId={ID=guid(gid(100))}}})
    inv.CountItemNum64=function(_,item)
        local n=0;for _,s in ipairs(carry)do if s.item==item then n=n+s.count end end;return n
    end
    local container=object('Common',{
        GetId=function()return{ID=guid(gid(100))}end,Num=function()return #carry end,
        Get=function(_,index)
            assert(index>=0 and index<#carry,'OUT OF BOUNDS');local s=carry[index+1]
            return object('Slot'..index,{
                GetSlotId=function()return{ContainerId={ID=guid(s.container_id)},SlotIndex=s.slot_id_index}end,
                GetItemId=function()return{StaticId=s.item,DynamicId={LocalIdInCreatedWorld=guid(s.dynamicGuid),CreatedWorldId=guid(s.dynamicWorldGuid)}}end,
                GetStackCount=function()return s.count end,IsEmpty=function()return s.empty end})
        end})
    local mgr=object('ItemManager',{GetContainer=function(_,id)assert(R0.guid_to_string(id.ID)==gid(100));return container end})
    local R={guid_to_string=R0.guid_to_string,guid_from_string=R0.guid_from_string,
        chests=function(t,o)
            assert(t==T and o.include_items and o.verify_ownership and o.require_snapshot_ownership and o.manager_name=='ItemManager')
            return report
        end}
    local d={json=J,readers=R,targets=T,inventory=inv,item_manager=mgr,player_uid=gid(200),fname=function(s)return s end}
    d.state=object('PlayerState',{GetInventoryData=function()return inv end})
    return d,report,carry,container
end
test('full common+13 and nonzero carried allowed',function()
    local d=fixture();local s=M.read(d)
    assert(#s.containers==14 and s.totals.Wood==30 and s.totals.Stone==10 and s.carried.Wood==15)
    assert(#J.encode(s)>2000)
end)
test('exact recipe normal decrements into empty',function()
    local d,r=fixture();local before=M.read(d)
    r.chests[1].slots={slot(gid(1),0,'None',0),slot(gid(1),1,'None',0)}
    local diff=M.diff(before,M.read(d));assert(diff.exact_recipe_cost and #diff.changed_slots==2)
    assert(J.encode(diff):find('"illegal_material_changes":[]',1,true))
end)
test('split carried+chests and partial reductions',function()
    local d,r,c=fixture();local before=M.read(d)
    r.chests[1].slots[1].count=8;c[1].count=7;c[2].count=0;c[2].empty=true;c[2].item='None'
    local diff=M.diff(before,M.read(d));assert(diff.exact_recipe_cost and #diff.changed_slots==3)
end)
test('same source unchanged is not cost',function()
    local d=fixture();local s=M.read(d);assert(not M.diff(s,M.read(d)).exact_recipe_cost)
end)
test('offsetting material movement never exact',function()
    local d,r,c=fixture();local before=M.read(d)
    r.chests[1].slots={slot(gid(1),0,'None',0),slot(gid(1),1,'None',0)}
    c[1].count=14;r.chests[3].slots[1]=slot(gid(3),0,'Wood',1)
    local diff=M.diff(before,M.read(d));assert(diff.recipe_totals_match and not diff.exact_recipe_cost and #diff.illegal_material_changes==1)
end)
test('unrelated item changes invalidate exact',function()
    local d,r=fixture();local before=M.read(d)
    r.chests[1].slots={slot(gid(1),0,'None',0),slot(gid(1),1,'None',0)}
    r.chests[2].slots[1]=slot(gid(2),0,'None',0)
    local diff=M.diff(before,M.read(d));assert(diff.recipe_totals_match and not diff.exact_recipe_cost and #diff.unrelated_changes==1)
end)
test('dynamic identity swap is unexplained',function()
    local d,r=fixture();local before=M.read(d);r.chests[2].slots[1].dynamicGuid=gid(888)
    assert(not M.diff(before,M.read(d)).unrelated_slots_unchanged)
end)
test('dynamic material cannot authorize exact',function()
    local d,r=fixture();r.chests[1].slots[1].dynamicGuid=gid(22);local before=M.read(d)
    r.chests[1].slots={slot(gid(1),0,'None',0),slot(gid(1),1,'None',0)}
    assert(not M.diff(before,M.read(d)).exact_recipe_cost)
end)
test('inventory owner mismatch rejects',function()
    local d=fixture();d.inventory.OwnerPlayerUId=guid(gid(201));reject(function()M.read(d)end,'inventory owner mismatch')
end)
test('inventory material outside common rejects',function()
    local d=fixture();d.inventory.CountItemNum64=function()return 100 end;reject(function()M.read(d)end,'does not cover')
end)
test('slot container and index binding rejects',function()
    local d,r,c=fixture();c[1].slot_id_index=2;reject(function()M.read(d)end,'slot identity mismatch')
    c[1].slot_id_index=0;c[1].container_id=gid(99);reject(function()M.read(d)end,'slot identity mismatch')
end)
test('cross-base ownership, duplicate target, partial read reject',function()
    local d,r=fixture();d.targets.chests[2].base_id=gid(99);reject(function()M.read(d)end,'cross-base')
    d,r=fixture();d.targets.chests[2].container_id=gid(1);reject(function()M.read(d)end,'duplicate target')
    d,r=fixture();r.ok=false;reject(function()M.read(d)end,'ownership/read failed')
    d,r=fixture();r.chests[2].eligible_for_snapshot_plan=false;reject(function()M.read(d)end,'chest verification failed')
end)
test('coverage changed between snapshots rejects',function()
    local d=fixture();local before=M.read(d);local after=clone(before);after.common_container_id=gid(101)
    reject(function()M.diff(before,after)end,'snapshot context changed')
end)
test('zero count must match IsEmpty',function()
    local d,r,c=fixture();c[3].empty=false;reject(function()M.read(d)end,'empty/count mismatch')
end)
test('common capacity bounded before Get',function()
    local d,r,c,container=fixture();container.Num=function()return 1001 end
    container.Get=function()error('FATAL GET')end;reject(function()M.read(d)end,'invalid common capacity')
end)
test('common container not an ordinary chest',function()
    local d=fixture();d.inventory.MyInventoryInfo.CommonContainerId.ID=guid(gid(1));reject(function()M.read(d)end,'aliased')
end)
print(passed..' material snapshot/diff tests passed; native inventory slot path still requires Lab validation')
