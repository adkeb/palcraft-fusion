-- New body-edge behavior only. Does not rerun the frozen 90 earlier checks.
local base=arg[1]or'work/minecraft-fusion/palcraft/'
local Core=dofile(base..'native/fluid_physics_core.lua');local Shape=dofile(base..'native/fluid_physics_contact.lua')
local World=dofile(base..'server/world_compat.lua');local Column=dofile(base..'server/world_fluid.lua')
local checks,cases=0,{}
local function check(v,name)checks=checks+1;assert(v,name);cases[#cases+1]=name end
local function close(a,b,tol)return math.abs(a-b)<(tol or 1e-7)end
local function world()
 local w=World.new{dimension='minecraft:overworld'};local seq=0
 local function ingest(ops,life)
  seq=seq+1;assert(w:ingest{t='blocks',v=2,session='body_edges',seq=seq,tick=seq,dim=w.dimension,ops=ops or{},lifecycle=life})
 end
 return w,ingest
end
local function water(x,y,z,h,solid,kind)
 return{op='upsert',at={x,y,z},id='minecraft:'..(kind or'water'),boxes=solid or{},solid=solid and #solid>0 or false,visible=true,
  fluid={kind=kind or'water',family='minecraft:'..(kind or'water'),height=h or 8/9,flow={1,0,0},waterlogged=solid and #solid>0 or false}}
end
local function commit(ingest,id,bounds,at)
 local event={op='snapshot_begin',snapshot=id,at=at or{0,0},bounds=bounds,replace=false};ingest({}, {event})
 event={op='snapshot_end',snapshot=id,at=at or{0,0},bounds=bounds,replace=false};ingest({}, {event})
end
local function collector(w,extra)
 local o={world=w,column_driver=Column,volume_boxes=Core.fluid_boxes};for k,v in pairs(extra or{})do o[k]=v end
 return Shape.new(o)
end
local function pose(x,y,z,r,h)return{dim='minecraft:overworld',feet={x,y,z},radius=r or .3,height=h or 1.8,eye_height=(h or 1.8)*.9}end
local W,ingest=world();ingest{water(1,64,0),water(1,64,1),water(3,64,0,.03),
 water(5,64,0,8/9,{{.25,0,0,1,1,1}}),water(7,64,0,.8,{{.1,0,0,.6,1,1},{.4,0,0,.9,1,1}}),water(9,64,0,.005)}
commit(ingest,'full',{-4,60,-4,16,100,16})
local C=collector(W)
local edge=C:sample('edge',pose(.85,64,.5))
check(W:fluid_at(W.dimension,.85,64.4,.5)==nil and edge.known and edge.wet,'dry centre with a real lateral capsule overlap enters water')
check(edge.immersion>0 and edge.immersion<.2 and not edge.swimming,'small lateral contact has partial immersed volume rather than full swimming')
check(edge.flow_weight>0 and edge.flow_weight<.5,'partial contact scales water-flow force')
local tangent=C:sample('tangent',pose(.7,64,.5))
check(not tangent.wet,'exact capsule tangency has zero wet volume')
local DW,di=world();di{water(1,64,1)};commit(di,'corner',{-4,60,-4,16,100,16})
local diagonal=collector(DW):sample('corner',pose(.75,64,.75))
check(not diagonal.wet,'fluid in an AABB corner outside the true circular capsule is dry')
local tip=C:sample('rounded_tip',pose(2.8,64,.5))
check(not tip.wet,'rounded capsule foot excludes a shallow corner reached only by a cylindrical approximation')
local gap=C:sample('waterlogged_gap',pose(4.9,64,.5))
check(gap.wet and gap.waterlogged and W:fluid_at(W.dimension,4.9,64.4,.5)==nil,'body reaches a waterlogged free side gap while its centre stays outside the cell')
local solid=C:sample('solid_face',pose(6.1,64,.5,.15))
check(not solid.wet,'brushing only the solid face of a waterlogged block stays dry')
local aabb={dim=W.dimension,shape='aabb',feet={7.5,64,.5},height=.8,eye_height=.7,bounds={7,64,0,8,64.8,1}}
local carved=C:sample('overlapping_solids',aabb)
check(close(carved.immersion,.2),'overlapping waterlogged solid boxes are subtracted as a union without double counting')
local film=C:sample('thin_film',pose(9.5,64,.5))
check(film.wet and not film.swimming and film.immersion<.001,'thin source film contacts the real rounded foot without forcing swimming')
check(close(film.flow_depth_factor,.0125)and film.flow_weight<.02,'a thin film does not apply the full-body flow impulse')
local half=Shape.body(pose(0,0,0,.5,1))
local half_volume,error=Shape.volume(half,{-1,0,-1,0,1,1})
check(close(half_volume,half.volume*.5,1e-8)and error<1e-8,'hemisphere volume weighting matches an independent exact half-sphere result')
check(close(Shape.circle_rectangle(1,0,0,1,1),math.pi/4),'disc rectangle area matches the exact quarter-circle')
-- Adjacent independently committed chunks jointly prove the whole body.
local CW,ci=world();ci{water(16,64,0)}
commit(ci,'left',{0,60,-16,16,80,16},{0,0});commit(ci,'right',{16,60,-16,32,80,16},{1,0})
local CC=collector(CW);local cross=CC:sample('cross',pose(15.9,64,.5))
check(cross.known and cross.wet,'complete capsule proof spans two adjacent committed chunk receipts')
ci({},{{op='chunk_unload',at={1,0}}});local lost=CC:sample('cross',pose(15.9,64,.5))
check(lost.known==false and CC.contacts.cross.wet,'missing edge chunk preserves prior wet state instead of inventing a dry exit')
-- Multiple actual body columns participate in surface proof; centre is dry.
local blocks={};for y=64,75 do blocks[#blocks+1]=water(11,y,0,1)end;blocks[#blocks+1]=water(11,76,0)
ingest(blocks);local deep=C:sample('deep_side',pose(10.85,64,.5))
check(deep.wet and deep.surface_known and close(deep.surface,76+8/9),'an off-centre deep-water body contact obtains the real connected column top')
C.column.options.max_surface_cells=1;local unknown=C:sample('deep_side',pose(10.85,64,.5))
check(unknown.known and unknown.wet and not unknown.surface_known and unknown.surface==nil,'deep edge contact retains wet volume while an unproved surface stays unknown')
C.column.options.max_surface_cells=64
ingest{water(13,64,0,8/9,{{0,.5,0,1,.6,1}}),water(14,64,0,1),water(14,65,0,1,{{0,.5,0,1,1,1}}),water(14,66,0)}
local roof=C:sample('current_ceiling',{dim=W.dimension,shape='aabb',feet={13.5,64,.5},height=.4,eye_height=.3,bounds={13,64,0,14,64.4,1}})
check(roof.surface_known and close(roof.surface,64.5),'current-cell waterlogged collision ceiling bounds the actual free contact column')
local upper=C:sample('above_current_ceiling',{dim=W.dimension,shape='aabb',feet={13.5,64.65,.5},height=.15,eye_height=.1,bounds={13,64.65,0,14,64.8,1}})
check(upper.surface_known and close(upper.surface,64+8/9),'water above a collision shelf retains its own higher surface')
local next_roof=C:sample('upper_cell_ceiling',{dim=W.dimension,shape='aabb',feet={14.5,64,.5},height=.4,eye_height=.3,bounds={14,64,0,15,64.4,1}})
check(next_roof.surface_known and close(next_roof.surface,65.5),'deep column stops at a proved waterlogged ceiling in an upper cell')
-- Actual Engine adapter: radius and centre are read from the capsule component.
local m={MovementMode=1,CustomMovementMode=0,GravityScale=1,WaterPlaneZ=-10000,WaterPlaneZPrev=-10000,InWaterRate=0,enter=0,exit=0,velocity={X=0,Y=0,Z=0}}
function m:IsValid()return true end;function m:IsA()return true end;function m:IsSwimming()return self.MovementMode==4 end
function m:OnEnterWater()self.enter=self.enter+1 end;function m:OnExitWater()self.exit=self.exit+1 end
function m:IsEnteredWater()return self.enter>self.exit end;function m:GetInWaterRate()return self.InWaterRate end
function m:SetMovementMode(mode,custom)self.MovementMode=mode;self.CustomMovementMode=custom end
function m:GetGravityZ()return-980*self.GravityScale end;function m:GetVelocity()return self.velocity end
function m:AddImpulse(v,change)assert(change);self.impulse=v end
local capsule={IsValid=function()return true end,GetScaledCapsuleHalfHeight=function()return 90 end,
 GetScaledCapsuleRadius=function()return 30 end,K2_GetComponentLocation=function()return{X=1085,Y=1950,Z=3090}end}
local actor={CharacterMovement=m,CapsuleComponent=capsule,IsValid=function()return true end,HasAuthority=function()return true end}
local Engine=Core.Engine.new{side='server',origin={X=1000,Y=2000,Z=3000}}
local p={actor=actor,dim=W.dimension};local actual=Engine:pose(p)
check(close(actual.radius,.3)and close(actual.feet[1],.85)and close(actual.height,1.8),'scaled radius, height and component world centre define the actual Pal capsule')
local state=Engine:attach(p);local observation=Engine:apply(state,p,edge,actual,.05)
check(m.enter==1 and m.MovementMode==1 and m.GravityScale==1,'lateral wading invokes native water entry without cancelling full-body gravity')
check(m.impulse.X>0 and m.impulse.X<14 and observation.flow_weight<.5,'physical native AddImpulse receives the reduced edge-flow force')
Engine:release(state)
-- Half of a deeply submerged body can swim, but cannot gain full-body buoyancy.
local HW,hi=world();hi{water(1,64,0,1),water(1,65,0,1),water(1,66,0)}
commit(hi,'half_deep',{-4,60,-4,16,100,16});local HC=collector(HW)
local hp={dim=HW.dimension,shape='aabb',feet={1,64,.5},height=1,eye_height=.9,bounds={.5,64,0,1.5,65,1}}
local hcontact=HC:sample('half_deep',hp)
check(close(hcontact.immersion,.5)and hcontact.swimming,'half-submerged AABB has exactly half the body volume in water')
m.MovementMode=1;m.GravityScale=1;m.impulse=nil;state=Engine:attach(p)
Engine:apply(state,p,hcontact,hp,.05)
check(m.MovementMode==4 and m.impulse.Z<0,'half-body water support does not fabricate full buoyancy or lift the dry half')
Engine:release(state)
-- Mixed water/lava contact is retained even when water is the dominant medium.
local MW,mi=world();mi{water(0,64,0,1),water(1,64,0,1,nil,'lava')};commit(mi,'mixed',{-4,60,-4,16,100,16})
local MC=collector(MW);local mixed=MC:sample('mixed',{dim=MW.dimension,shape='aabb',feet={.6,64,.5},height=1,eye_height=.9,bounds={.2,64,0,1.1,65,1}})
check(mixed.kind=='water'and mixed.lava and mixed.kinds.lava.fraction>0,'minority lava contact survives dominant-water selection without creating a damage timer')
-- New shape sampler is the actual Core lifecycle, not a disconnected helper.
local native={commits=0,boxes={}}
function native:replace(ctx,origin,revision,boxes)self.commits=self.commits+1;self.boxes=boxes;return true end
function native:reset()self.boxes={}end;function native:status()return{boxes=#self.boxes,commits=self.commits}end
function actor:GetAddress()return 0x50100 end
local ctx={IsValid=function()return true end,GetAddress=function()return 0x50200 end}
local participant={id='pal:integrated',actor=actor,dim=W.dimension}
m.GravityScale=1;m.MovementMode=1;m.enter=0;m.exit=0
local adapter=Core.new{side='server',world=W,contact_driver=Column,native=native,origin={X=1000,Y=2000,Z=3000},
 game_thread=function()return true end,resolve_context=function()return ctx end,resolve_participants=function()return{participant}end}
adapter:tick(1000,{});adapter:tick(1050,{})
check(adapter.contacts['pal:integrated'].wet and adapter.contacts['pal:integrated'].shape=='capsule'and m.MovementMode==1,'Core runtime now uses full physical capsule contact for a centre-dry actual Actor')
check(adapter:status().contact_sampling=='physical_capsule_or_aabb'and m.impulse.X>0 and m.impulse.X<14,'physical edge contact reaches the composed native movement/flow path')
adapter:stop('edge_test_done',{context_alive=true})
check(m.GravityScale==1 and #native.boxes==0,'new full-body lifecycle cleans up query bodies and restores native gravity')
local guard=Core.environment_contact{world=MW,origin={X=1000,Y=2000,Z=3000},contact_driver=Column,game_thread=function()return true end}
local before_enter,before_mode,before_gravity=m.enter,m.MovementMode,m.GravityScale
local guarded,proof=guard({kind='minecraft:lava',target='pal:guard',dim=MW.dimension},{actor=actor})
check(guarded and proof.lava and proof.kind=='water','pure server damage guard finds an actual minority lava capsule contact')
check(m.enter==before_enter and m.MovementMode==before_mode and m.GravityScale==before_gravity,'pure environment proof creates no native movement or damage side effects')
local unsupported=guard({kind='minecraft:on_fire',target='pal:guard'},{actor=actor})
check(not unsupported,'fluid guard does not fabricate a proof for vanilla residual fire ticks')
print('{"ok":true,"suite":"physical_body_edges","checks":'..checks..',"shape_overlap":"analytic","live_physics_verified":false,"old_checks_rerun":false,"power_mode":"night_low_power"}')
