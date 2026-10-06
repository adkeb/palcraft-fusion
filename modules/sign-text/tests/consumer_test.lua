local root=assert(arg[1],'minecraft-fusion root required'):gsub('/?$','/')
local J=dofile(root..'../palworld-live/bridge/PalLiveBridge/Scripts/json.lua')
local G=dofile(root..'sign-text/lua/geometry.lua')
local C=dofile(root..'sign-text/lua/consumer.lua')
local Native=dofile(root..'sign-text/lua/native.lua')
local Materials=dofile(root..'sign-text/lua/materials.lua')
local Scene=dofile(root..'sign-text/lua/scene.lua')
local function copy(v)if type(v)~='table'then return v end;local q={};for k,x in pairs(v)do q[k]=copy(x)end;return q end
local f=assert(io.open(root..'model-compat/snapshots/models-v4-761ddea057ce/text_layouts/minecraft/signs.json','rb'))
local layouts=J.decode(f:read('*a'));f:close()
local shaA=string.rep('a',64);local shaB=string.rep('b',64)
local function side(matrix,hash)
 return{transform=copy(matrix),pixel_bounds={-53,-28,53,28},light_baked=true,alpha='straight',glowing=false,
  image={path='textures/'..hash..'.png',sha256=hash,width=424,height=224,scale=4,alpha_mode='cutout'}}
end
local function row(layout,hash)return{at={3,64,-2},id='minecraft:oak_sign',state_key='Block{minecraft:oak_sign}[rotation=0,waterlogged=false]',
 front=side(layout.front,hash or shaA),back=side(layout.back,hash or shaA)}end
for _,layout in ipairs(layouts.layouts)do
 local r=row(layout);local groups=G.groups(r,'minecraft:overworld','/private/')
 for _,group in ipairs(groups)do
  local a,b,c=group.vertices[1],group.vertices[2],group.vertices[3]
  local ux,uy,uz=b[1]-a[1],b[2]-a[2],b[3]-a[3];local vx,vy,vz=c[1]-a[1],c[2]-a[2],c[3]-a[3]
  local dot=(uy*vz-uz*vy)*a[4]+(uz*vx-ux*vz)*a[5]+(ux*vy-uy*vx)*a[6]
  assert(dot>0,'Incorrect winding: '..layout.family..'/'..layout.variant)
  local cx,cy,cz=0,0,0;for _,v in ipairs(group.vertices)do cx=cx+v[1]/4;cy=cy+v[2]/4;cz=cz+v[3]/4 end
  local m=r[group.side].transform
  assert(math.abs(cx-(m[13]+m[9]*.04)*100)<1e-5 and math.abs(cy+(m[15]+m[11]*.04)*100)<1e-5
   and math.abs(cz-(m[14]+m[10]*.04)*100)<1e-5,'World text centroid mismatch')
 end
end
local initial=row(layouts.layouts[1]);local blocks={['3,64,-2']={id=initial.id,state=initial.state_key,visible=true,mirror=true}}
local ready=true;local time=100000;local log={create=0,update=0,remove=0};local handle
local renderer={}
function renderer:create(ctx,origin,r,fence)log.create=log.create+1;handle={actor=17};return handle end
function renderer:update(h,r)assert(h==handle);log.update=log.update+1 end
function renderer:remove(h,alive)assert(h==handle);log.remove=log.remove+1 end
function renderer:set_visible(h,visible)assert(h==handle);h.visible=visible end
local worker=C.new{json=J,renderer=renderer,now_ms=function()return time end,
 block_at=function(dim,at)return blocks[table.concat(at,',')],ready end}
local fence={world_session='world-a',dim='minecraft:overworld',view=4,mapping='arena-0',mc_uuid='fixture-player'}
local bind=C.binding_request(fence,{-16,0,-16,16,256,16});assert(bind.t=='sign_text_view'and bind.bounds[4]==16 and bind.mapping=='arena-0')
worker:bind(fence,true)
local function snapshot(seq,r)
 local s=copy(fence);s.schema=1;s.t='sign_text';s.producer='producer-a';s.epoch=1;s.seq=seq;s.created_ms=time;s.complete=true;s.available=true;s.rows=r and{copy(r)}or{};return s
end
assert(worker:apply(snapshot(1,initial),{},{}));assert(log.create==1)
assert(worker:apply(snapshot(2,initial),{},{}));assert(log.create==1 and log.update==0)
local edited=copy(initial);edited.front.image=side(initial.front.transform,shaB).image
assert(worker:apply(snapshot(3,edited),{},{}));assert(log.create==1 and log.update==1,'Text edit rebuilt actor')
local bad=snapshot(4,edited);bad.view=3;assert(not worker:apply(bad,{},{}));assert(log.remove==0,'Wrong view destroyed live text')
bad=snapshot(4,edited);bad.rows[1].back.image.path='../../other.png';assert(not worker:apply(bad,{},{}));assert(log.update==1,'Bad PNG path partially applied')
bad=snapshot(4,edited);bad.rows={edited,edited};assert(not worker:apply(bad,{},{}))
assert(not worker:apply(snapshot(2,initial),{},{}),'Old sequence accepted')
blocks['3,64,-2']=nil;worker:prune(true);assert(log.remove==1,'Destroyed sign text persisted')
assert(worker:apply(snapshot(4,edited),{},{}));assert(log.create==1,'Missing geometry spawned floating text')
blocks['3,64,-2']={id=initial.id,state=initial.state_key};ready=false
assert(worker:apply(snapshot(5,edited),{},{}));assert(log.create==1,'Uncommitted sign geometry spawned text')
ready=true;assert(worker:apply(snapshot(6,edited),{},{}));assert(log.create==2)
worker:unload_chunk('minecraft:overworld',0,-1,true);assert(log.remove==2)
assert(worker:apply(snapshot(7,edited),{},{}));assert(log.create==3)
local advanced=snapshot(1,edited);advanced.epoch=2;assert(worker:apply(advanced,{},{}));assert(log.remove==3 and log.create==4)
assert(not worker:apply(snapshot(8,edited),{},{}),'Retired producer epoch replayed')
local oriented=copy(edited);oriented.state_key='Block{minecraft:oak_sign}[rotation=1,waterlogged=false]'
oriented.front.transform=copy(layouts.layouts[3].front);oriented.back.transform=copy(layouts.layouts[3].back)
blocks['3,64,-2'].state=oriented.state_key;ready=false;worker:prune(true)
assert(handle.visible==false and log.remove==3,'Pending orientation destroyed instead of hiding existing text')
local next=snapshot(2,oriented);next.epoch=2;assert(worker:apply(next,{},{}));assert(log.create==4)
ready=true;next=snapshot(3,oriented);next.epoch=2;assert(worker:apply(next,{},{}))
assert(handle.visible==true and log.create==4 and log.remove==3,'Committed orientation failed to reuse same text object')
time=time+6000;worker.o.read=function()return nil end;worker:poll({},{},true);assert(log.remove==4,'Producer timeout leaked text')

-- Exercise the actual adapter/material modules against a minimal native API
-- mock: ordinary edits retain the actor, component and two MID objects.
local ctx={};function ctx:IsValid()return true end;function ctx:GetAddress()return 42 end
local parent={MaterialDomain=0};function parent:IsValid()return true end;function parent:GetBlendMode()return 1 end;function parent:GetBaseMaterial()return self end
local textureSerial,midSerial=0,0
local function texture()textureSerial=textureSerial+1;local t={id=textureSerial};function t:IsValid()return true end;return t end
local inherited=texture()
local function mid()
 midSerial=midSerial+1;local m={id=midSerial};function m:IsValid()return true end
 function m:K2_GetTextureParameterValue()return inherited end;function m:SetTextureParameterValue(name,t)self.texture=t end;return m
end
local materials=Materials.new{root='/private/signs',allow_candidate=true,name=function(x)return x end,
 load_asset=function()return parent end,create_material=function()return mid()end,import_texture=function()return texture()end}
local models={version=5,spawned=0,updates=0,released=0}
function models.spawn_groups(c,o,groups,at,options)
 models.spawned=models.spawned+1
 for _,g in ipairs(groups)do assert(materials:resolve(c,g).material:IsValid())end
 assert(options.hidden==true);return 77,88,99
end
function models.update_groups(actor,groups)assert(actor==77 and #groups==2);models.updates=models.updates+1 end
function models.set_visible(actor,visible)assert(actor==77 and visible)end
function models.release_model(actor,destroy)assert(actor==77);models.released=models.released+1 end
local native=Native.new{models=models,materials=materials,set_section_material=function()error('MID changed during simple text edit')end}
local h=native:create(ctx,{X=0,Y=0,Z=0},initial,fence);local front=h.materials[1].material;local back=h.materials[2].material
for i=1,60 do native:update(h,i%2==0 and initial or edited)end
assert(models.spawned==1 and models.updates==0 and h.materials[1].material==front and h.materials[2].material==back,'Simple edits rebuilt native/MIDs')
assert(materials:status().instances==2 and materials:status().textures<=34,'Text material resources unbounded')
local rotated=copy(initial);rotated.front.transform=copy(layouts.layouts[3].front);rotated.back.transform=copy(layouts.layouts[3].back)
native:update(h,rotated);assert(models.updates==1 and models.spawned==1,'Orientation update rebuilt actor')
native:remove(h,true);native:remove(h,true);assert(models.released==1 and materials:status().instances==0,'Lifetime cleanup was not idempotent')
assert(materials:status().runtime_verified==false,'Mock tests promoted runtime evidence')
local g={id=initial.id,state=initial.state_key,at=initial.at,visible=true,properties={rotation='0'},boxes={},fluid={kind='none'}}
local world={session=fence.world_session,dimension=fence.dim,committed_snapshots={receipt={committed=true,
 session=fence.world_session,dim=fence.dim,player=fence.mc_uuid,bounds={0,0,-16,16,256,0}}}}
function world:get(dim,x,y,z)if dim==fence.dim and x==3 and y==64 and z==-2 then return g end end
local companion={running=true,world=world,origin={X=123,Y=456,Z=789,y_origin=64},actors={}}
local sig=J.encode({id=g.id,state=g.state,properties=g.properties,boxes=g.boxes,visible=g.visible,
 render_kind=g.render_kind,fluid=g.fluid,tint_colors=g.tint_colors})
companion.actors['3:64:-2']={id=g.id,model=100,model_component=101,model_status='rendered',visible=true,render_signature=sig}
local view=copy(fence);view.applied=true;view.mapping=nil
local scene=Scene.per_block{json=J,companion=function()return companion end,confirmed_view=function()return view end}
local block,committed=scene.block_at(fence.dim,initial.at);assert(block==g and committed==true)
local projection=scene.view_provider({});assert(projection.origin==companion.origin and projection.bounds[6]==0
 and projection.fence.mapping:match('^per%-block%-origin:'),'Normal OW source invented a mapping/required travel')
g.block_entity={user_text_revision=2};block,committed=scene.block_at(fence.dim,initial.at);assert(committed,'NBT-only edit invalidated unchanged native body')
g.state='rotation changed';block,committed=scene.block_at(fence.dim,initial.at);assert(not committed,'Uncommitted body state accepted')
companion.pending_view={};assert(scene.view_provider({})==nil,'Pending normal OW view accepted')
companion=nil;assert(scene.view_provider({})==nil,'Unloaded normal OW companion accepted')
print('PASS: 40 vanilla front/back transforms; update/lifetime/fence/timeout; committed geometry; MID reuse and bounded references')
