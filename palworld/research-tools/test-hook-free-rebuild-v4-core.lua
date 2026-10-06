local P='work/palworld-live/'
local C=dofile(P..'lab/hook-free-rebuild-v4-core.lua');local J=dofile(P..'bridge/PalLiveBridge/Scripts/json.lua')
local n=0;local function test(name,fn)local ok,e=pcall(fn);assert(ok,name..': '..tostring(e));n=n+1;print('ok '..name)end
local function setup(o)
 o=o or{};local now=1000;local calls=0;local fence=o.fence;local seq=0;local evidence=0
 local cfg={nonce='11111111-2222-3333-4444-555555555555',mode=o.preview and'preview'or'execute',expires_unix=1300,
 supersedes_failed_operation='00000000-0000-4000-8000-000000000017',execute_exact_manual_request=true,operator_confirmed_normal_dismantle=true}
 local function material()return{cost=(calls>0 and not o.deferred)or seq>=1,activity=o.activity and seq>=2}end
 local dep={json=J,now=function()return now end,is_game_thread=function()return true end,has_fence=function()return fence end,
 emit=function()end,verify_evidence=function()evidence=evidence+1;assert(not o.bad_evidence,'evidence');return{}end,
 preflight=function()return{old_manual_model_absent=not o.old_present,live_context_verified=true,tech_guild_base_verified=not o.bad_tech,materials_sufficient=not o.no_materials,materials={}},{}end,
 claim_intent=function()fence=true;return true end,final_check=function()if o.expire then now=1301 end;return not o.final_changed end,
 submit=function()assert(fence);calls=calls+1;if o.native_error then error('native throw')end end,
 read_materials=function()if o.material_error then error('material failure')end;return material()end,
 material_diff=function(_,a)return{exact_recipe_cost=a.cost and not a.activity,concurrent_or_unexplained_changes=a.activity==true}end,
 observe=function()
  seq=seq+1;if o.read_error and seq==3 then error('read failure')end
  local id=o.changed_id and seq>=2 and'B'or'A'
  local removed=o.removed and seq>=3
  local new=removed and{}or{id};if o.multi then new={'A','B'}end
  return{new_models=new,missing_models=o.missing and{'old'}or{},unavailable=o.unavailable and{'id'}or{},
   candidate=not removed and{ok=not o.bad_candidate,model_id=id,completed_verified=seq>=2,normal_unfinished_work_observed=seq==1 and not o.no_early_work}or nil}
 end}
 local r=C.new(dep,cfg)
 return{r=r,start=function()return r.start()end,tick=function()now=now+1;return r.tick()end,calls=function()return calls end,cfg=cfg,evidence=function()return evidence end}
end
test('sha256_vectors',function()
 assert(C.sha256('')=='e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855')
 assert(C.sha256('abc')=='ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad')
 assert(C.sha256(string.rep('a',1000000))=='cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0')
end)
test('preview_zero_mutation',function()local e=setup{preview=true};assert(e.start().status=='preview_ready'and e.calls()==0)end)
for _,name in ipairs({'fence','bad_evidence','old_present','bad_tech','no_materials','final_changed','expire'})do
 test(name..'_blocks_request',function()local e=setup{[name]=true};assert(e.start().status=='not_submitted'and e.calls()==0)end)
end
test('normal_single_request',function()local e=setup();e.start();e.tick();e.tick();e.tick();assert(e.r.report.status=='normal_construction_observed'and e.calls()==1);e.tick();assert(e.calls()==1)end)
test('deferred_debit_no_repeat',function()local e=setup{deferred=true};e.start();assert(not e.r.report.recipe_debit_observed);for _=1,30 do e.tick()end;assert(e.r.report.status=='indeterminate_no_retry'and e.r.report.structure_completion_verified and e.calls()==1)end)
test('initial_work_missed_not_claimed',function()local e=setup{no_early_work=true};e.start();e.tick();e.tick();e.tick();assert(e.r.report.status=='placement_observed_initial_work_unverified')end)
test('later_activity_preserves_immediate_recipe_and_structure_evidence',function()local e=setup{activity=true};e.start();e.tick();e.tick();e.tick();assert(e.r.report.status=='construction_observed_with_later_inventory_activity'and e.r.report.immediate_material_delta.exact_recipe_cost and e.r.report.structure_completion_verified)end)
for _,name in ipairs({'changed_id','removed','read_error','multi','missing','unavailable','bad_candidate'})do
 test(name..'_never_uses_stale_success',function()local e=setup{[name]=true};e.start();e.tick();e.tick();e.tick();assert(e.r.report.status=='indeterminate_no_retry'and e.calls()==1)end)
end
for _,name in ipairs({'native_error','material_error'})do test(name..'_no_retry',function()local e=setup{[name]=true};e.start();e.tick();assert(e.r.report.status=='indeterminate_no_retry'and e.calls()==1)end)end
test('wrong_supersession_blocks',function()local e=setup();e.cfg.supersedes_failed_operation='other';assert(e.start().status=='not_submitted'and e.calls()==0)end)
test('double_start_rejected',function()local e=setup();e.start();assert(not pcall(e.start));assert(e.calls()==1)end)
print('PASS '..n..' core cases (no engine)')
