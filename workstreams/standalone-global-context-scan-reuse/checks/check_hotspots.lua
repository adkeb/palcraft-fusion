-- Finite synthetic source contracts only; no Game, native library or file state.
local root=assert(arg[1])
local function object(name,address,world)
 local o={name=name,address=address,world=world,valid=true,authority=true}
 function o:IsValid()return self.valid end
 function o:GetFullName()return self.name end
 function o:GetAddress()return self.address end
 function o:GetWorld()return self.world end
 function o:HasAuthority()return self.authority end
 function o:GetPlayerUId()return {uid=self.uid}end
 return o
end
local world=object('World MainWorld',10)
local gs=object('PalGameStateInGame MainWorld',20,world)
local pawn=object('PalPlayerCharacter MainWorld',30,world)
local pc=object('PalPlayerController MainWorld',40,world);pc.Pawn=pawn;pc.uid='owned-uid'
local proof={mode='standalone',world=world,world_address=10,game_state=gs,pc=pc,pawn=pawn,host_uid=pc.uid}
local function env()
 local e={_G={},finds=0,currents=0,authority_calls=0,realm=true}
 e.live=function(o)return o and o:IsValid()and not o:GetFullName():find('Default__',1,true)end
 e.FindAllOf=function(kind)e.finds=e.finds+1;return kind=='GameStateBase'and{gs}or{pc}end
 e.guid=function(g)return g.uid end
 e.gs=gs
 e.current_authority=function(actual)assert(actual==gs);e.authority_calls=e.authority_calls+1;assert(not e.denied,'fixture permission denied');return e.proof or proof end
 setmetatable(e,{__index=_G})
 return e
end
local function context(label,e)return assert(loadfile(root..'/context-'..label..'.lua','t',e))()end
local function controllers(label,e)return assert(loadfile(root..'/controllers-'..label..'.lua','t',e))()end
local cases=0
local function pass()cases=cases+1 end
do -- The same native state, with fresh current() every shared consumer call.
 local e=env();e._G.PalCraftStandaloneBootstrap={local_realm={current=function()e.currents=e.currents+1;return proof end}}
 local c=context('source',e);for _=1,3 do assert(c()==gs)end;assert(e.currents==3 and e.finds==0)
 local old=context('base',e);for _=1,3 do assert(old()==gs)end;assert(e.finds==3);pass()
end
do -- Invalid permission is a rejection, never a legacy-scanning fallback.
 local e=env();e._G.PalCraftStandaloneBootstrap={local_realm={current=function()return nil,'permission denied'end}}
 assert(not pcall(context('source',e)));assert(e.finds==0);pass()
end
do -- A foreign native state world cannot satisfy a supplied proof.
 local foreign=object('PalGameStateInGame OtherWorld',21,object('World OtherWorld',11))
 local q={mode='standalone',world=world,world_address=10,game_state=foreign,pc=pc}
 local e=env();e._G.PalCraftStandaloneBootstrap={local_realm={current=function()return q end}}
 assert(not pcall(context('source',e)));assert(e.finds==0);pass()
end
do
 local e=env();local dead=object('PalGameStateInGame MainWorld',20,world);dead.valid=false
 e._G.PalCraftStandaloneBootstrap={local_realm={current=function()return{mode='standalone',world=world,world_address=10,game_state=dead,pc=pc}end}}
 assert(not pcall(context('source',e)));assert(e.finds==0);pass()
end
do -- Network mode preserves first-live selection and the original scan.
 local e=env();local default=object('GameStateBase Default__GameStateBase',1,world)
 e.FindAllOf=function(kind)assert(kind=='GameStateBase');e.finds=e.finds+1;return{default,gs}end
 assert(context('base',e)()==gs and context('source',e)()==gs and e.finds==2);pass()
end
do
 local e=env();e.FindAllOf=function()e.finds=e.finds+1;return{}end
 local ok1,why1=pcall(context('base',e));local ok2,why2=pcall(context('source',e))
 assert(not ok1 and not ok2 and why1:find('No game state',1,true)and why2:find('No game state',1,true)and e.finds==2);pass()
end
do
 local e=env();local fresh=controllers('source',e)();assert(#fresh==1 and fresh[1]==pc and e.authority_calls==1 and e.finds==0)
 local old=controllers('base',e)();assert(#old==1 and old[1]==fresh[1]and e.finds==1);pass()
end
do
 local e=env();e.proof={pc=pc,pawn=pawn,host_uid='foreign-uid'}
 assert(not pcall(controllers('source',e)));assert(e.finds==0);pass()
end
do
 local e=env();e.proof={pc=pc,pawn=object('PalPlayerCharacter OtherPawn',31,world),host_uid=pc.uid}
 assert(not pcall(controllers('source',e)));assert(e.finds==0);pass()
end
do -- Multiplayer keeps the full controller collection; no single-host narrowing.
 local e=env();e.realm=nil;local other=object('PalPlayerController Other',41,world)
 e.FindAllOf=function(kind)assert(kind=='PalPlayerController');e.finds=e.finds+1;return{pc,other}end
 local a,b=controllers('base',e)(),controllers('source',e)();assert(#a==2 and #b==2 and a[1]==b[1]and a[2]==b[2]and e.finds==2 and e.authority_calls==0);pass()
end
do -- Authenticated player tuple and expiry guards precede either resolver.
 local e=env();e.session='pal-session';e.now=function()return 100 end;e.P={uuid=function(v)return v=='owned-uid'end}
 local row={mc_uuid='mc',pal_uid=pc.uid,expires_at=101,session_id='auth-session',generation=2}
 local records={world_id='world',sessions={row}};e.authenticated_sessions=function()return records end
 e.player_controllers=controllers('source',e)
 local fn=assert(loadfile(root..'/authenticated-source.lua','t',e))()
 local q={mc_uuid='mc',pal_uid=pc.uid,world_id='world',server_session_id=e.session,session_id=row.session_id,generation=2}
 local a,r=fn('mc',q);assert(a==pawn and r==row and e.finds==0)
 local old=assert(loadfile(root..'/authenticated-base.lua','t',e))();assert(old('mc',q)==pawn and e.finds==1);pass()
 q.generation=3;e.finds=0;local a1,w1=old('mc',q);local a2,w2=fn('mc',q)
 assert(a1==nil and a2==nil and w1==w2 and e.finds==0);pass()
end
assert(cases==12)
print('PASS12 synthetic contracts: shared SP context/current and no fallback; stale/foreign/dead reject; network selection unchanged; owned controller UID/pawn proof; multiplayer collection unchanged; authenticated tuple guards unchanged. NPC scan/source tail unchanged separately.')
