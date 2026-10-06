local proposal,actual=assert(arg[1]),assert(arg[2])
local J=dofile(actual..'/PalCraft-Client/Pal/Binaries/Win64/ue4ss/Mods/PalCraftClient/Scripts/json.lua')
local function read(p)local f=assert(io.open(p,'rb'));local s=f:read('*a');f:close();return s end
local function part(s,a,b)local i=assert(s:find(a,1,true));return s:sub(i,assert(s:find(b,i, true))-1)end
local source=read(proposal..'/source/client/palcraft-collisions.lua')
local cache=part(source,'local accepted_view_session','M.models=models')
local world=part(source,'local World=dofile','local function boxes_for')
local ingest=part(source,"     if accepted==true and reason=='applied'",'     if not accepted then')
local abandon=part(source,'function M.abandon()','local tick')
local runtime=actual..'/PalCraft-Client/Pal/Binaries/Win64/ue4ss/Mods/PalCraftClient/Scripts/'
local api=assert(load('local M={running=true,items={},actors={},queue={},queued={}}\n'..cache..world..
 '\nlocal function accept(row)local accepted,reason=M.world:ingest(row)\n'..ingest..'\nreturn accepted,reason end\n'..abandon..
 '\nreturn{M=M,accept=accept}',nil,'t',{J=J,dir=runtime,dofile=dofile,ipairs=ipairs,pairs=pairs,type=type,assert=assert,
 observe=function()end,enqueue=function()error('Native effect forbidden in this data check')end,world_observers={},world_observer_order={}}))()
local MC='11111111-1111-1111-1111-111111111111';local UID='00000000-0000-0000-0000-000000000001'
local row={t='blocks',v=2,session='current-world',seq=281,dim='minecraft:overworld',ops={},lifecycle={{op='player_view',player=MC,
 reason='reconnect',to='minecraft:overworld',view=1,waiting_ack=true,pos={-8.073118,63.110739,-13.45403},yaw=-120.57704,pitch=0}}}
assert(api.accept(row));api.M.set_view(row.dim,MC);assert(not api.M.pending_view)
local saved=api.M.current_player_view_rows();assert(saved[MC].seq==281 and saved[MC].lifecycle[1].pos[1]==row.lifecycle[1].pos[1])
saved[MC].seq=999;assert(api.M.current_player_view_rows()[MC].seq==281)
local duplicate=J.decode(J.encode(row));duplicate.seq=280;duplicate.lifecycle[1].pos[1]=99
local ok,why=api.accept(duplicate);assert(ok and why=='duplicate'and api.M.current_player_view_rows()[MC].seq==281)
-- Start real feature composition after the accepted original event and scene activation.
local config=dofile(runtime..'travel/config.lua');local P=dofile(runtime..'travel/protocol.lua')
local pc={position=P.to_ue(P.registry(config):acquire('current-world',row.dim,row.lifecycle[1].pos,'fixture'),row.lifecycle[1].pos)}
function pc:GetAddress()return 1 end
local actor={valid=function()return true end,snapshot=function()return{position=pc.position,rotation={Yaw=0,Pitch=0,Roll=0},half_height=80,pawn_address=2,movement_mode=1}end,
 position=function()return pc.position end,hold=function()return{}end,release=function()end,safety=function()return true,{}end}
local sent={};local viewer={prepare_view=function(req)return{generation=1,request=req}end,
 readiness=function(ticket)return{ready=false,world_session=ticket.request.world_session,dim=ticket.request.dim,view=ticket.request.view,
 region_id=ticket.request.mapping.region_id,generation=1,revision=0,snapshots_pending=0,collision_pending=0,errors={}}end,release=function()return true end}
local old={mc_uuid=MC,pal_uid='22222222-0000-0000-0000-000000000000',session_id='00000000-0000-0000-0000-000000000003',generation=1,world_id='old',server_session_id='old',mc_epoch='old'}
local binding={v=2,legacy=false,mc_uuid=MC,pal_uid=UID,session_id='00000000-0000-0000-0000-000000000004',generation=1,
 world_id='world-id',server_session_id='standalone:actual',expires_at=200,mc_epoch='new-MC'}
local presence={v=2,authority=true,world_id=binding.world_id,server_session_id=binding.server_session_id,updated_unix=100,
 players={{pal_uid=UID,possessed=true,saved_account=true}}}
local sessions={v=2,world_id=binding.world_id,server_session_id=binding.server_session_id,mc_epoch=binding.mc_epoch,updated_unix=100,sessions={binding}}
api.M.context=function()return pc end;api.M.set_world_observer=function()end;api.M.status_json=function()return J.encode({running=true})end
local Core=dofile(actual..'/BridgeLab/Pal/Binaries/Win64/ue4ss/Mods/PalLiveBridge/Scripts/travel.lua')
local F=dofile(proposal..'/source/server/features.lua').new{json=J,readers={},runtime_dir=runtime..'runtime/',game_thread=function()return true end,
 now=function()return 100 end,entities_enabled=false,travel_enabled=true,companion=function()return api.M end,resolve_player=function(uid)if uid==UID then return pc end end,
 files={read=function(path)if path:find('authenticated%-sessions')then return sessions end end},
 load=function(name)if name=='session-auth'then return{new=function()return{tick=function()return presence end}end}elseif name=='travel'then return Core end;error(name)end,
 verify_travel_request=function()return false end,
 travel={protocol=P,config=config,actor=actor,view=viewer,journal={load=function()return{world_session='old-Win-world',players={},pending={},counter=5}end,
 save=function()return true end,ack=function()error('ACK forbidden in this check')end},send=function(r)sent[#sent+1]=r;return true end}}
F:tick(0);local worker=assert(F.composition.features.travel.instance)
assert(worker.stats.begun==1 and worker.world_session=='current-world'and worker.pending[UID].binding.pal_uid==UID)
assert(sent[1].phase=='prepare'and sent[1].pos[1]==row.lifecycle[1].pos[1]and sent[1].view==1)
F:tick(1);assert(worker.stats.begun==1)
api.accept{t='blocks',v=2,session='new-world',seq=1,dim=row.dim,ops={},lifecycle={}}
assert(next(api.M.current_player_view_rows())==nil)
api.M.abandon();assert(next(api.M.current_player_view_rows())==nil)
print(J.encode({schema=1,task='accepted_original_view_late_factory_seed',passed=true,real_reducer=true,real_feature_factory=true,
 real_travel_core=true,scene_effects_replayed=0,ack_issued=0,old_history_changed=false,runtime_operations=false,engine_validated=false}))
