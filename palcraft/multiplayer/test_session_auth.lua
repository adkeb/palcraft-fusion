local root=assert(arg[1]);local outdir=assert(arg[2])
local J=dofile(root..'/../../palworld-live/bridge/PalLiveBridge/Scripts/json.lua');local R=dofile(root..'/../../palworld-live/bridge/PalLiveBridge/Scripts/readers.lua')
local function object(kind,fields)
 fields=fields or{};function fields:IsValid()return true end;function fields:GetFullName()return kind..' /Engine/Transient.Fixture' end;return fields
end
local ga={A=0x11111111,B=0x11111111,C=0x11111111,D=0x11111111};local gb={A=0x22222222,B=0x22222222,C=0x22222222,D=0x22222222}
local ua=R.guid_to_string(ga);local ub=R.guid_to_string(gb)
local function controller(g,authority,possessed)
 local pc=object('PalPlayerController',{Pawn=possessed and object('PalCharacter')or nil})
 function pc:HasAuthority()return authority end;function pc:GetPlayerUId()return g end;return pc
end
local function account(g)
 local h=object('PalIndividualHandle');function h:GetIndividualID()return{PlayerUId=g}end
 return object('PalPlayerAccount',{IndividualHandle=h})
end
local gs=object('PalGameStateInGame',{ServerSessionId='Pal-boot-fixture'});function gs:HasAuthority()return true end;function gs:GetWorldSaveDirectoryName()return'BridgeLab-fixture'end
local pa=controller(ga,true,true);local pb=controller(gb,true,true)
local objects={PalGameStateInGame={gs},PalPlayerAccount={account(ga),account(gb)},PalPlayerController={pa,pb}}
function FindAllOf(class)return objects[class]end
local api=dofile(root..'/server/session-auth.lua').new({root=outdir,json=J,readers=R});local tests=J.array()
local function test(name,f)f();tests[#tests+1]={name=name,ok=true}end
local function reject(f)local ok=pcall(f);assert(not ok,'expected authority/session rejection')end
test('authority_snapshot_two_distinct_possessed_saved_players',function()
 local p=api.snapshot();assert(p.authority and#p.players==2 and p.players[1].pal_uid==ua and p.players[2].pal_uid==ub)
end)
test('client_controllers_and_unpossessed_characters_not_authority',function()
 objects.PalPlayerController={controller(ga,false,true),controller(gb,true,false)};assert(#api.snapshot().players==0);objects.PalPlayerController={pa,pb}
end)
test('missing_saved_account_not_registered',function()
 objects.PalPlayerAccount={account(ga)};assert(#api.snapshot().players==1);objects.PalPlayerAccount={account(ga),account(gb)}
end)
test('duplicate_controller_uid_snapshot_rejected',function()
 objects.PalPlayerController={pa,controller(ga,true,true)};reject(api.snapshot);objects.PalPlayerController={pa,pb}
end)
test('presence_file_contains_only_observed_public_fields',function()
 api.tick();local f=assert(io.open(outdir..'/pal-presence.json','rb'));local s=f:read('*a');f:close();local p=J.decode(s)
 assert(p.v==2 and p.authority and#p.players==2 and not s:find('private')and not s:find('secret'))
end)
local mc='11111111-1111-1111-1111-111111111111'
local function sessions()
 return {v=2,world_id='BridgeLab-fixture',server_session_id='Pal-boot-fixture',mc_epoch='MC-epoch-fixture',updated_unix=os.time(),
 sessions={{pal_uid=ua,mc_uuid=mc,session_id='native-connection-a',generation=3,expires_at=os.time()+600,legacy=false}}}
end
test('mc_to_pal_resolver_returns_actual_binding_with_connection_tuple',function()
 local row=assert(api.resolve(mc,sessions()));assert(row.pal_uid==ua and row.generation==3 and row.mc_epoch=='MC-epoch-fixture'and row.world_id=='BridgeLab-fixture')
end)
test('old_world_pal_boot_mc_epoch_missing_and_stale_snapshot_rejected',function()
 for _,key in ipairs({'world_id','server_session_id'})do local s=sessions();s[key]='other';reject(function()api.resolve(mc,s)end)end
 local s=sessions();s.mc_epoch=nil;reject(function()api.resolve(mc,s)end)
 s=sessions();s.updated_unix=os.time()-6;reject(function()api.resolve(mc,s)end)
end)
test('offline_pal_player_expired_native_and_legacy_binding_not_resolved',function()
 local s=sessions();s.sessions[1].legacy=true;assert(api.resolve(mc,s)==nil)
 s=sessions();s.sessions[1].expires_at=os.time();assert(api.resolve(mc,s)==nil)
 objects.PalPlayerController={pb};assert(api.resolve(mc,sessions())==nil);objects.PalPlayerController={pa,pb}
end)
test('duplicate_authenticated_mc_avatar_rejected',function()
 local s=sessions();s.sessions[2]=s.sessions[1];reject(function()api.resolve(mc,s)end)
end)
print(J.encode({ok=true,suite='pal_authority_presence_and_resolver',tests=#tests,cases=tests,two_real_pal_clients_verified=false}))
