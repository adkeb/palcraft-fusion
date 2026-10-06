-- Pure Lua coordinator. No Unreal APIs, hooks, retry, refund or automatic work completion.
local M={}
function M.sha256(s)
    local K={0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2}
    local h={0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19}
    local function rr(v,n)return((v>>n)|(v<<(32-n)))&0xffffffff end
    local n=#s;s=s..'\128'..string.rep('\0',(55-n)%64)..string.pack('>I8',n*8)
    for p=1,#s,64 do
        local w={};for i=0,15 do w[i]=string.unpack('>I4',s,p+i*4)end
        for i=16,63 do local x,y=w[i-15],w[i-2];w[i]=(w[i-16]+(rr(x,7)~rr(x,18)~(x>>3))+w[i-7]+(rr(y,17)~rr(y,19)~(y>>10)))&0xffffffff end
        local a,b,c,d,e,f,g,z=table.unpack(h)
        for i=0,63 do local t1=(z+(rr(e,6)~rr(e,11)~rr(e,25))+((e&f)~((~e)&g))+K[i+1]+w[i])&0xffffffff
            local t2=((rr(a,2)~rr(a,13)~rr(a,22))+((a&b)~(a&c)~(b&c)))&0xffffffff
            z,g,f,e,d,c,b,a=g,f,e,(d+t1)&0xffffffff,c,b,a,(t1+t2)&0xffffffff
        end
        local v={a,b,c,d,e,f,g,z};for i=1,8 do h[i]=(h[i]+v[i])&0xffffffff end
    end
    local r={};for i=1,8 do r[i]=string.format('%08x',h[i])end;return table.concat(r)
end
function M.new(d,cfg)
    local J=d.json;local stopped=false;local submitted;local ctx;local last=-1
    local report={probe='hook_free_rebuild_v4',mode=cfg.mode,nonce=cfg.nonce,lab_only=true,status='created',
        supersedes_failed_operation=cfg.supersedes_failed_operation,created_unix=d.now(),hooks_registered=0,
        native_call_attempts=0,observations=J.array(),errors=J.array(),retry_permitted=false,
        automatic_finish_implemented=false,material_refund_implemented=false,persistence_verified=false,
        replication_verified=false,request_correlation='No hooks; fixed single invocation and bounded registered-model/material observations.'}
    local self={report=report}
    local function finish(status)stopped=true;report.status=status;report.finished_unix=d.now();d.emit(report)end
    local function fail(stage,e)report.errors[#report.errors+1]={stage=stage,error=type(e)=='table'and e.message or tostring(e)}end
    local function delta(before,after)
        local v=d.material_diff(before,after)
        return v
    end
    function self.start()
        assert(report.status=='created','one-shot start');assert(d.is_game_thread(),'game thread required')
        local ok,e=pcall(function()
            assert(cfg.mode=='preview'or cfg.mode=='execute','unknown mode')
            assert(cfg.expires_unix>d.now()and cfg.expires_unix<=d.now()+300,'expired or excessive arm window')
            assert(not d.has_fence(),'v4 intent already exists; no replay with any nonce')
            report.evidence=d.verify_evidence();report.status='preflight'
            report.before,ctx=d.preflight()
            assert(report.before.old_manual_model_absent and report.before.live_context_verified and report.before.tech_guild_base_verified,'preflight identity or permission failed')
            assert(report.before.materials_sufficient,'insufficient legal recipe materials')
            if cfg.mode=='preview'then finish('preview_ready');return end
            assert(cfg.execute_exact_manual_request==true and cfg.operator_confirmed_normal_dismantle==true,'execution authorization missing')
            assert(cfg.supersedes_failed_operation=='00000000-0000-4000-8000-000000000017','explicit failed-operation supersession required')
            report.status='intent_to_submit';report.intent_unix=d.now()
            assert(d.claim_intent(report)and d.has_fence(),'durable nonreplace intent failed')
            assert(cfg.expires_unix>d.now(),'arm expired before final checks')
            assert(d.final_check(ctx,report.before),'final context/site/material check failed')
            assert(cfg.expires_unix>d.now(),'arm expired before RPC')
            submitted=d.now();report.submitted_unix=submitted;report.native_call_attempts=1;report.status='native_call_started'
            -- Persist the attempted state before entering the single native call.
            d.emit(report)
            d.submit(ctx);report.native_call_returned=true
            report.materials_immediate_after=d.read_materials(ctx)
            report.immediate_material_delta=delta(report.before.materials,report.materials_immediate_after)
            if report.immediate_material_delta.exact_recipe_cost then report.recipe_debit_observed={elapsed_seconds=0,delta=report.immediate_material_delta}end
            report.status='observing';d.emit(report)
        end)
        if not ok then fail(report.status,e);finish(report.native_call_attempts>0 and'indeterminate_no_retry'or'not_submitted')end
        return report
    end
    function self.tick()
        if stopped then return true end;if not submitted then return false end
        assert(d.is_game_thread(),'game thread required')
        local elapsed=d.now()-submitted;if elapsed==last then return false end;last=elapsed
        local ok,v=pcall(function()
            local value=d.observe(report.before,ctx)
            value.elapsed_seconds=elapsed
            -- One material read per one-second game-thread observation, <=30 observations.
            value.materials=d.read_materials(ctx)
            value.material_delta=delta(report.before.materials,value.materials)
            report.observations[#report.observations+1]=value
            if value.material_delta.concurrent_or_unexplained_changes then report.later_inventory_activity_observed=true end
            assert(#value.new_models<=1 and #value.missing_models==0 and #value.unavailable==0,'registered building scope became ambiguous')
            if value.material_delta.exact_recipe_cost and not report.recipe_debit_observed then report.later_recipe_sized_delta_unattributed={elapsed_seconds=elapsed,delta=value.material_delta}end
            if #value.new_models==1 then
                local c=assert(value.candidate,'candidate details missing');assert(c.ok,'candidate identity/work/transform invalid')
                if report.new_model then assert(report.new_model.model_id==c.model_id,'candidate identity changed')end
                report.new_model=c
                if c.normal_unfinished_work_observed then report.normal_unfinished_work_observed=true end
            elseif report.new_model then error('previously observed candidate disappeared')end
            return value
        end)
        if not ok then fail('observation',v);finish('indeterminate_no_retry');return true end
        local c=v.candidate
        if c and c.completed_verified then report.structure_completion_verified=true end
        if elapsed>=3 and #v.new_models==1 and c and c.ok and c.completed_verified==true
            and report.native_call_returned and report.recipe_debit_observed and report.recipe_debit_observed.elapsed_seconds==0
            and report.immediate_material_delta.exact_recipe_cost==true then
            report.structure_completion_verified=true
            if report.later_inventory_activity_observed then finish('construction_observed_with_later_inventory_activity')
            else finish(report.normal_unfinished_work_observed and'normal_construction_observed'or'placement_observed_initial_work_unverified')end
            return true
        end
        if elapsed>=30 then finish('indeterminate_no_retry');return true end
        d.emit(report);return false
    end
    return self
end
return M
