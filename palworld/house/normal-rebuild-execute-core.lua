-- Coordinator for ONE root-armed, normal-survival Lab request. No retry/recovery writes.
local M={}
function M.new(d,cfg)
    local J=d.json
    local report={probe='normal_rebuild_once',version=1,lab_only=true,nonce=cfg.nonce,mode=cfg.mode,
        status='created',native_call_attempts=0,own_rpc_events=0,other_rpc_events=0,errors=J.array(),
        model_events=J.array(),observations=J.array(),created_unix=d.now(),retry_permitted=false,
        material_refund_implemented=false,automatic_finish_implemented=false,
        replication_verified=false,persistence_verified=false}
    local stopped=false;local submitted_at;local own_dispatch=false;local context
    local function emit()return d.emit(report)end
    local function failure(stage,e)
        report.errors[#report.errors+1]={stage=stage,error=tostring(e)}
    end
    local function finish(status)
        stopped=true;report.status=status;report.finished_unix=d.now()
        local ok,e=pcall(d.cleanup);if not ok then failure('cleanup',e)end
        emit()
    end
    local self={report=report}
    function self.on_request(event)
        if stopped or not submitted_at then return end
        if own_dispatch and event.matches_fixed_request then report.own_rpc_events=report.own_rpc_events+1
        else report.other_rpc_events=report.other_rpc_events+1;report.correlation_ambiguous=true end
    end
    function self.on_model(event)
        if stopped or not submitted_at then return end
        if #report.model_events<16 then report.model_events[#report.model_events+1]=event
        else report.correlation_ambiguous=true end
    end
    function self.start()
        assert(report.status=='created','start is one-shot')
        assert(d.is_game_thread(),'game thread required')
        local ok,e=pcall(function()
            assert(cfg.mode=='preview'or cfg.mode=='execute','unknown mode')
            assert(cfg.expires_unix>d.now()and cfg.expires_unix<=d.now()+300,'expired/invalid arm')
            assert(not d.has_fence(),'persistent prior intent forbids every new request, including a new nonce')
            report.status='preflight';report.before,context=d.preflight()
            assert(report.before.old_manual_model_absent==true,'old manual model still registered')
            assert(report.before.live_context_verified and report.before.tech_guild_base_verified,'live permission checks failed')
            assert(report.before.materials_sufficient==true,'observed legal material scope insufficient')
            if cfg.mode=='preview'then finish('preview_ready');return end
            assert(cfg.operator_confirmed_normal_dismantle==true,'normal manual dismantle confirmation absent')
            assert(cfg.execute_exact_manual_request==true,'exact manual request execution arm absent')
            -- Immutable global intent is written/read back BEFORE any native call.
            report.status='intent_to_submit';report.intent_unix=d.now();assert(d.claim_intent(report)==true,'intent claim failed')
            assert(d.has_fence(),'intent was not persisted')
            -- Same game-thread callback: no yield, no fresh actor identity substitution.
            assert(cfg.expires_unix>d.now(),'arm expired before submission')
            assert(d.final_check(context)==true,'last-moment context/site check failed')
            submitted_at=d.now();report.submitted_unix=submitted_at
            report.native_call_attempts=1;report.status='native_call_started';own_dispatch=true
            local called,call_error=pcall(d.submit,context);own_dispatch=false
            report.native_call_returned=called
            if not called then failure('native_call',call_error)end
            -- Before returning to engine tick: observe synchronous normal consume.
            local read_ok,after=pcall(d.read_materials,context)
            if read_ok then report.materials_immediate_after=after;report.immediate_material_delta=d.material_diff(report.before.materials,after)
                if report.immediate_material_delta.exact_recipe_cost==true then report.recipe_debit_observed={elapsed_seconds=0,delta=report.immediate_material_delta}end
            else failure('materials_immediate_after',after)end
            report.status='observing';emit()
        end)
        if not ok then
            own_dispatch=false;failure(report.status,e)
            finish(report.native_call_attempts>0 and'indeterminate_no_retry'or'not_submitted')
        end
        return report
    end
    local last_second=-1
    function self.tick()
        if stopped then return true end
        if not submitted_at then return false end
        assert(d.is_game_thread(),'game thread required')
        local elapsed=d.now()-submitted_at
        if elapsed==last_second then return false end;last_second=elapsed
        local current_candidate_valid=false;local current_completed=false
        local ok,value=pcall(function()
            local observed=d.observe(report.before,context)
            observed.material_delta=d.material_diff(report.before.materials,observed.materials)
            return observed
        end)
        if ok then
            value.elapsed_seconds=elapsed;report.observations[#report.observations+1]=value
            if value.material_delta.exact_recipe_cost==true and not report.recipe_debit_observed then
                report.recipe_debit_observed={elapsed_seconds=elapsed,delta=value.material_delta}
            end
            if #value.new_models==1 and value.candidate and value.candidate.ok then
                if report.new_model and report.new_model.model_id~=value.candidate.model_id then report.correlation_ambiguous=true end
                report.new_model=value.candidate
                report.site_observed=value.candidate.distance_from_expected_cm<=2
                report.work_complete_observed=value.candidate.build_process.available and value.candidate.build_process.completed==true
                current_candidate_valid=report.site_observed
                current_completed=report.work_complete_observed and value.candidate.container and value.candidate.container.module_available==true and value.candidate.container.available==true and value.candidate.container.capacity==10
                for _,event in ipairs(report.model_events)do
                    if event.model_id==value.candidate.model_id and event.state==0 and event.required_work==1000
                        and event.work_binding_verified==true and event.current_work>=0 and event.current_work<1000 then report.normal_unfinished_work_observed=true end
                end
                if value.candidate.build_process.available and value.candidate.build_process.work.available then
                    local w=value.candidate.build_process.work
                    if value.candidate.build_process.state==0 and w.required_amount==1000 and w.current_amount>=0 and w.current_amount<1000
                        and w.owner_model_matches==true and w.owner_concrete_matches==true and w.base_matches==true and w.required_matches_recipe==true then report.normal_unfinished_work_observed=true end
                end
            elseif report.new_model then report.correlation_ambiguous=true
            end
            if #value.new_models>1 or #value.missing_models>0 or #(value.unavailable or{})>0 then report.correlation_ambiguous=true end
            report.last_materials=value.materials
        else failure('observation',value);report.correlation_ambiguous=true end
        if elapsed>=3 and report.native_call_returned==true and current_candidate_valid and current_completed
            and report.own_rpc_events==1 and report.other_rpc_events==0 and not report.correlation_ambiguous
            and report.recipe_debit_observed then
            finish(report.normal_unfinished_work_observed and'normal_construction_observed'or'placement_observed_initial_work_unverified');return true
        end
        if elapsed>=30 then finish('indeterminate_no_retry');return true end
        emit();return false
    end
    return self
end
return M
