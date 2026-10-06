from pathlib import Path
source=Path('work/palworld-live/lab/lab-worker-active-preflight.lua').read_text()
head=source[source.index('local source='):source.index('local report=')]
helpers=source[source.index('local function live'):source.index('local function base_stage()')]
validation=source[source.index('local function registered_work'):source.index('local function finish(')]
validation=validation.replace(" budget()\nend\n", " budget()\n return {row=row,handle=handle,parameter=parameter,actor=actor,cp=cp,worker_action=found,work=work}\nend\n")
# The exact final worker-stage tail is the only budget/end occurrence in this block.
assert validation.count('return {row=row')==1
out='''-- BRIDGELAB ONLY. One existing worker -> one existing workbench. NO automatic undo/retry.
-- Root-reviewed explicit arm required. All game changes are one normal fixed-work call.
-- Intent + consumed nonce survive reload; existing evidence refuses execution forever.
'''+head+'''
local PLAYER='22222222-0000-0000-0000-000000000000'
local INDIVIDUAL='00000000-0000-4000-8000-00000000002e'
local PREFIX=ROOT..'lab-worker-assign-once'
local report={probe='lab_worker_assign_once',lab_only=true,read_only=false,apply_supported=false,
 base_id=BASE,guild_id=GUILD,model_id=MODEL,work_id=WORK,player_uid=PLAYER,individual_id=INDIVIDUAL,
 source_path=source,automatic_retry_allowed=false,automatic_undo_allowed=false,native_call_attempted=false,native_call_returned=false,
 native_queries=0,eligible_pairs=0,global_scans={},workers=J.array(),errors=J.array(),callbacks=J.array(),observations=J.array(),
 started_utc=os.date('!%Y-%m-%dT%H:%M:%SZ'),permission_enum=7,permission_name='BasePalOperation',
 native_method='PalAIActionCompositeWorker:RegisterFixedAssignWork(FGuid)',
 limitation='One Lab experiment only. Void return is not success. No save-persistence or production support claim.'}
local manager_refs={};local callback=0;local started=0;local done=false;local stage='base'
local candidate={array_index=2,slot_index=1,individual_id={instance_id=INDIVIDUAL,player_uid=ZERO}}
local player_ref,arm
'''+helpers+validation
out+='''
local function exists(path)local f=io.open(path,'rb');if f then f:close();return true end;return false end
local function read(path)
 local f=assert(io.open(path,'rb'),'missing '..path);local raw=f:read(1048577);assert(f:close())
 assert(type(raw)=='string'and #raw<=1048576,'oversized/invalid JSON');return J.decode(raw,{max_bytes=1048576,max_depth=40})
end
local function write_new(path,value)
 assert(not exists(path)and not exists(path..'.tmp'),'prior evidence exists; no overwrite/retry')
 local f=assert(io.open(path..'.tmp','wb'));assert(f:write(J.encode(value,{max_bytes=1048576,max_depth=40})))
 assert(f:flush());assert(f:close());assert(os.rename(path..'.tmp',path),'evidence commit failed')
end
local function evidence_exists()
 for _,suffix in ipairs({'.intent.json','.intent.json.tmp','.used-arm.json','.result.json','.result.json.tmp','.call-returned.json','.call-returned.json.tmp','.after-3s.json','.after-3s.json.tmp','.after-10s.json','.after-10s.json.tmp'})do
  if exists(PREFIX..suffix)then return true end
 end
 return false
end
local function check_arm()
 assert(arm.lab_only==true and arm.action=='assign-zoe-old-workbench-once','explicit Lab action missing')
 assert(arm.base_id==BASE and arm.work_id==WORK and arm.individual_id==INDIVIDUAL and arm.player_uid==PLAYER,'armed target mismatch')
 assert(type(arm.expires_unix)=='number'and arm.expires_unix%1==0 and arm.expires_unix>=os.time()+1 and arm.expires_unix<=os.time()+600,'arm expired or too far in future')
 assert(type(arm.nonce)=='string'and #arm.nonce==36 and id(R.guid_from_string(arm.nonce))==arm.nonce and arm.nonce~=ZERO,'canonical nonzero nonce required')
end
local function player_context()
 assert(player_ref,'player not discovered')
 local pc=typed(StaticFindObject(player_ref.path),'PalPlayerController')
 assert(pc:GetFullName()==player_ref.full_name and id(pc:GetPlayerUId())==PLAYER,'player identity changed')
 assert(pc:HasAuthority()and pc:IsPlayerController()and live(pc.NetConnection),'real authoritative connected player required')
 local state=typed(pc:GetPalPlayerState(),'PalPlayerState');assert(same(state:GetPlayerController(),pc),'PlayerState/controller mismatch')
 local pawn=typed(pc:GetDefaultPlayerCharacter(),'PalPlayerCharacter');assert(pawn:HasAuthority()and same(pawn:GetController(),pc),'player pawn/controller mismatch')
 local tx=typed(pc.Transmitter,'PalNetworkTransmitter');assert(same(tx:GetOwner(),pc),'player-owned transmitter missing')
 local guild=state.GuildBelongTo;assert(live(guild)and id(guild:GetId())==GUILD,'player guild mismatch')
 assert(guild:HasGuildPermission(R.guid_from_string(PLAYER),7)==true,'BasePalOperation guild permission denied')
 return {player_uid=PLAYER,guild_id=GUILD,permission=7,permission_name='BasePalOperation',permission_verified=true,
  player_controller=pc:GetFullName(),player_state=state:GetFullName(),pawn=pawn:GetFullName(),transmitter=tx:GetFullName()}
end
local function discover_player()
 trace('discover_exact_connected_player',PLAYER)
 local raw=FindAllOf('PalPlayerController')or{};assert(#raw<=16,'player scan limit exceeded')
 report.global_scans.PalPlayerController=1;local found={}
 for _,pc in ipairs(raw)do if live(pc)and id(pc:GetPlayerUId())==PLAYER then found[#found+1]=pc end end
 assert(#found==1,'exactly one selected player required')
 local pc=typed(found[1],'PalPlayerController');local full=pc:GetFullName()
 player_ref={full_name=full,path=assert(full:match('^[^ ]+ (.+)$'))};report.player=player_context();budget()
end
local function apply_once()
 trace('all_live_preconditions_before_intent',INDIVIDUAL);check_arm();assert(not evidence_exists(),'prior evidence prevents replay')
 report.player=player_context() -- Same game-thread callback as the intended mutation.
 local context=worker_stage(candidate)
 assert(context and context.row.eligible_for_lab_experiment and context.row.native_fixed_suitability,'worker is not healthy idle suitable or AI chain is not active')
 assert(context.parameter:GetPhysicalHealth()==0,'worker physical health is not normal')
 assert(context.parameter:GetWorkSuitabilityRankWithCharacterRank(5)>=1,'worker lacks handcraft')
 local assigned={};context.work:GetAssignedCharacters(assigned)
 assert(#assigned==0,'target work already has an assigned character; replacing workers is forbidden')
 context.row.work.assigned_characters_before=0
 budget();check_arm()
 local intent={lab_only=true,read_only=false,source_path=source,nonce=arm.nonce,action=arm.action,
  base_id=BASE,guild_id=GUILD,model_id=MODEL,work_id=WORK,individual_id=INDIVIDUAL,player_uid=PLAYER,
  stage='intent_before_native',written_unix=os.time(),all_preconditions_verified=true,player=report.player,before=context.row,
  native_method=report.native_method,automatic_retry_allowed=false,automatic_undo_allowed=false,
  recovery='An intent may mean native execution occurred even when no later result exists. Inspect; never replay.'}
 write_new(PREFIX..'.intent.json',intent)
 local back=read(PREFIX..'.intent.json');assert(back.nonce==arm.nonce and back.lab_only and back.source_path==source and back.all_preconditions_verified,'intent readback failed')
 assert(not exists(PREFIX..'.used-arm.json')and os.rename(PREFIX..'.arm.json',PREFIX..'.used-arm.json'),'arming nonce could not be consumed')
 local claimed=read(PREFIX..'.used-arm.json');assert(claimed.nonce==arm.nonce,'consumed nonce mismatch')
 budget();check_arm()
 report.nonce=arm.nonce;report.intent_committed=true;report.native_call_attempted=true;report.native_called_unix=os.time()
 -- The only gameplay mutation in this file. Existing validated WorkerComposite only.
 context.worker_action:RegisterFixedAssignWork(R.guid_from_string(WORK))
 report.native_call_returned=true
 write_new(PREFIX..'.call-returned.json',{nonce=arm.nonce,lab_only=true,native_call_attempted=true,native_call_returned=true,
  returned_unix=os.time(),void_return_is_not_success=true,automatic_retry_allowed=false})
 stage='observe3'
end
local function observe(seconds)
 trace('delayed_assignment_readback_'..seconds,INDIVIDUAL)
 local row={delay_seconds=seconds,observed_utc=os.date('!%Y-%m-%dT%H:%M:%SZ'),matches_target=false}
 report.observations[#report.observations+1]=row
 local base,director=registered_base(manager('PalBaseCampManager'));local slots=slots_of(director)
 local element=assert(slots[candidate.array_index],'target slot removed');local slot=element:get()
 assert(live(slot)and slot:GetSlotIndex()==1 and not slot:IsEmpty(),'target slot changed')
 local h=typed(slot:GetHandle(),'PalIndividualCharacterHandle');assert(iid_same(iid(h:GetIndividualID()),candidate.individual_id),'worker identity changed')
 local p=typed(h:TryGetIndividualParameter(),'PalIndividualCharacterParameter')
 assert(id(p:GetBaseCampId())==BASE and id(p:GetGroupId())==GUILD and iid_same(iid(p:GetPalId()),candidate.individual_id),'worker membership changed')
 local actor=typed(h:TryGetIndividualActor(),'PalCharacter');assert(actor:HasAuthority(),'worker lost authority')
 local cp=typed(actor:GetCharacterParameterComponent(),'PalCharacterParameterComponent');assert(same(cp:GetIndividualParameter(),p),'worker parameter changed')
 row.task={assigned=boolean(cp:IsAssignedToAnyWork()),fixed=boolean(cp:IsAssignedFixed()),work_id=id(cp:GetWorkId())}
 local expected_work=registered_work(base)
 row.task.work_recognizes_character=boolean(expected_work:IsAssignedCharacter(h))
 if row.task.assigned then
  local assignment=cp:GetWorkAssign();assert(live(assignment),'assignment object missing')
  assert(iid_same(iid(assignment:GetAssignedIndividualId()),candidate.individual_id),'assignment individual differs')
  local assigned_work=assignment:GetWork();assert(live(assigned_work)and id(assigned_work:GetWorkId())==row.task.work_id,'assignment work binding differs')
  row.task.working=boolean(assignment:IsWorking());row.task.workable=boolean(assignment:IsWorkable())
  row.task.state_enum=finite(assignment:GetState());row.task.working_state_enum=finite(assignment:GetWorkingState())
  row.task.name=text(assigned_work:GetWorkName());row.task.expected_work_object=same(assigned_work,expected_work)
 end
 row.matches_target=row.task.assigned and row.task.fixed and row.task.work_id==WORK and row.task.expected_work_object==true and row.task.work_recognizes_character==true
 budget();write_new(PREFIX..'.after-'..seconds..'s.json',{nonce=arm.nonce,lab_only=true,read_only=true,observation=row})
end
local function finish(complete,message)
 if done then return end;done=true;report.complete=complete;report.error=message
 report.ok=complete and report.native_call_returned and #report.observations==2 and report.observations[1].matches_target and report.observations[2].matches_target
 report.status=report.ok and 'observed_target_assignment_at_3s_and_10s' or(report.native_call_attempted and 'needs_inspection' or 'rejected_before_native')
 report.finished_utc=os.date('!%Y-%m-%dT%H:%M:%SZ')
 local ok,e=pcall(write_new,PREFIX..'.result.json',report)
 print('[PalLiveLabWorkerAssignOnce] '..(ok and('result saved; status='..report.status)or('REPORT NOT OVERWRITTEN '..tostring(e)))..'\\n')
end
local schedule
local function tick()
 if done then return end;callback=callback+1;started=os.clock();local entry=stage
 local ok,e=pcall(function()
  assert(IsInGameThread(),'game thread required');assert(callback<=6,'callback limit exceeded')
  if stage=='base'then
   assert(not evidence_exists(),'prior evidence prevents replay');arm=read(PREFIX..'.arm.json');check_arm()
   local base,director=registered_base(discover_manager('PalBaseCampManager'));stage='player'
  elseif stage=='player'then discover_player();stage='map'
  elseif stage=='map'then discover_manager('PalMapObjectManager');stage='apply'
  elseif stage=='apply'then apply_once()
  elseif stage=='observe3'then observe(3);stage='observe10'
  elseif stage=='observe10'then observe(10);stage='complete'end
  budget()
 end)
 local elapsed=(os.clock()-started)*1000;report.callbacks[#report.callbacks+1]={index=callback,stage=entry,cpu_ms=elapsed}
 report.max_callback_cpu_ms=math.max(report.max_callback_cpu_ms or 0,elapsed)
 if not ok or report.budget_exceeded then finish(false,tostring(e or'callback budget exceeded'));return end
 if stage=='complete'then finish(true);return end
 schedule(stage=='observe3'and 3000 or stage=='observe10'and 7000 or 50)
end
schedule=function(ms)ExecuteWithDelay(ms,function()ExecuteInGameThread(tick)end)end
-- Existing intent/result on reload is a hard stop. Never alter previous evidence.
if evidence_exists()then print('[PalLiveLabWorkerAssignOnce] existing evidence; refusing replay and preserving files.\\n');return end
schedule(50)
'''
# Trace path is independent from the read-only preflight.
out=out.replace("ROOT..'lab-worker-active-preflight.trace.jsonl'","PREFIX..'.trace.jsonl'")
Path('work/palworld-live/lab/lab-worker-assign-once.lua').write_text(out)
