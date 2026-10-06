local J=dofile('work/palworld-live/bridge/PalLiveBridge/Scripts/json.lua')
local Core=dofile('work/palworld-live/lab/normal-rebuild-once-core.lua')
local total=0
local function setup(mode)
    local clock=1000;local fenced=false;local calls=0;local stages={};local core
    local cfg={nonce='test',mode=mode or'execute',expires_unix=1200,operator_confirmed_normal_dismantle=true,execute_exact_manual_request=true}
    local before={old_manual_model_absent=true,live_context_verified=true,tech_guild_base_verified=true,materials_sufficient=true,materials={n=30}}
    local d={json=J,now=function()return clock end,is_game_thread=function()return true end,has_fence=function()return fenced end,
        emit=function(r)J.encode(r);stages[#stages+1]=r.status end,cleanup=function()end,
        preflight=function()return before,{}end,claim_intent=function()fenced=true;return true end,final_check=function()return true end,
        submit=function()assert(fenced);calls=calls+1;core.on_request{matches_fixed_request=true};core.on_model{model_id='new',state=0,required_work=1000,current_work=0}end,
        read_materials=function()return{n=15}end,material_diff=function(a,b)return{exact_recipe_cost=a.n-b.n==15}end,
        observe=function()return{materials={n=15},new_models={'new'},missing_models={},candidate={ok=true,model_id='new',distance_from_expected_cm=0,build_process={available=true,completed=true,work={available=false}}}}end}
    core=Core.new(d,cfg)
    return{core=core,d=d,cfg=cfg,before=before,advance=function(n)clock=clock+n end,calls=function()return calls end,fenced=function()return fenced end}
end
local function test(name,fn)local ok,e=pcall(fn);assert(ok,name..': '..tostring(e));total=total+1;print('ok '..name)end
test('preview_never_claims_or_calls',function()local e=setup('preview');e.core.start();assert(e.core.report.status=='preview_ready'and e.calls()==0 and not e.fenced())end)
test('old_box_present_blocks_call',function()local e=setup();e.before.old_manual_model_absent=false;e.core.start();assert(e.calls()==0 and e.core.report.status=='not_submitted')end)
test('insufficient_materials_blocks_call',function()local e=setup();e.before.materials_sufficient=false;e.core.start();assert(e.calls()==0 and not e.fenced())end)
test('no_confirmation_blocks_call',function()local e=setup();e.cfg.operator_confirmed_normal_dismantle=false;e.core.start();assert(e.calls()==0 and not e.fenced())end)
test('intent_failure_blocks_call',function()local e=setup();e.d.claim_intent=function()error('disk failure')end;e.core.start();assert(e.calls()==0)end)
test('post_intent_failure_stays_fenced',function()local e=setup();e.d.final_check=function()return false end;e.core.start();assert(e.calls()==0 and e.fenced())end)
test('native_error_never_retries',function()local e=setup();e.d.submit=function()error('native call binding unknown')end;e.core.start();e.advance(31);e.core.tick();assert(e.core.report.native_call_attempts==1 and e.core.report.status=='indeterminate_no_retry'and e.fenced())end)
test('one_native_call_then_verified_evidence',function()local e=setup();e.core.start();e.advance(3);e.core.tick();assert(e.calls()==1 and e.core.report.status=='normal_construction_observed'and e.fenced())end)
test('start_cannot_repeat',function()local e=setup();e.core.start();assert(not pcall(e.core.start));assert(e.calls()==1)end)
test('new_nonce_cannot_bypass_global_fence',function()local e=setup();e.core.start();local c=Core.new(e.d,{nonce='different',mode='execute',expires_unix=1200,operator_confirmed_normal_dismantle=true,execute_exact_manual_request=true});c.start();assert(e.calls()==1 and c.report.status=='not_submitted')end)
test('async_debit_is_observed_later',function()local e=setup();e.d.read_materials=function()return{n=30}end;e.core.start();assert(not e.core.report.recipe_debit_observed);e.advance(3);e.core.tick();assert(e.core.report.status=='normal_construction_observed'and e.core.report.recipe_debit_observed.elapsed_seconds==3)end)
test('material_diff_error_is_reported',function()local e=setup();e.core.start();e.d.material_diff=function()error('coverage changed')end;e.advance(31);assert(e.core.tick());assert(e.core.report.status=='indeterminate_no_retry'and #e.core.report.errors==1)end)
test('concurrent_rpc_forbids_success',function()local e=setup();e.core.start();e.core.on_request{matches_fixed_request=true};e.advance(31);e.core.tick();assert(e.core.report.status=='indeterminate_no_retry')end)
test('missing_early_work_is_not_claimed',function()local e=setup();e.d.submit=function()e.core.on_request{matches_fixed_request=true}end;e.core.start();e.advance(3);e.core.tick();assert(e.core.report.status=='placement_observed_initial_work_unverified')end)
test('observations_do_not_require_empty_chest',function()local e=setup();e.core.start();local original=e.d.observe;e.d.observe=function()local r=original();r.candidate.container={empty=false,occupied_slots=2};return r end;e.advance(3);e.core.tick();assert(e.core.report.status=='normal_construction_observed')end)
test('expiry_rechecked_after_preflight',function()local e=setup();e.d.claim_intent=function()e.advance(201);return true end;e.d.has_fence=function()return e.core.report.intent_unix~=nil end;e.core.start();assert(e.calls()==0)end)
print('PASS '..total..' normal rebuild coordinator cases')
