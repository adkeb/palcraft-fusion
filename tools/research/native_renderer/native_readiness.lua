-- Read-only readiness for the existing per-block native companion.
-- Load without side effects. Invoke the returned verifier only on the game thread.
-- Coverage/sequence/signature proof stays with runtime/companion_view.lua.
local M={version=1}
local BLOCK={0,1,2,4,5,6,15,16,20,21,22,24,26,27,28,29}
local WATER={14,19,25}
local function valid(o)return o and o:IsValid()end
local function close(a,b,tolerance)return type(a)=='number'and type(b)=='number'and math.abs(a-b)<=tolerance end
local function vector_matches(a,b,tolerance)
 return close(a.X,b.X,tolerance)and close(a.Y,b.Y,tolerance)and close(a.Z,b.Z,tolerance)
end
local function identity_rotation(r)
 for _,k in ipairs({'Pitch','Yaw','Roll'})do
  if type(r[k])~='number'or math.abs((r[k]+180)%360-180)>.01 then return false end
 end
 return true
end
local function present(v)return v~=nil and v~=false and not(type(v)=='table'and next(v)==nil)end
function M.new(options)
 local c=assert(options.companion,'Native companion required')
 local enumerate=options.find_all or FindAllOf
 local in_game_thread=options.in_game_thread or IsInGameThread
 local fname=options.fname or FName
 local now=options.now or os.time
 local accepted=options.accepted_renderers or{[3]=true}
 local caps=options.capabilities or{opaque=true}
 local maximum=options.max_blocks or 512
 local function query(root,center,scale)
  if options.query_shape then return options.query_shape(root,center,scale)end
  local half=50*scale.X
  local hit={}
  return root:K2_LineTraceComponent({X=center.X-half-2,Y=center.Y,Z=center.Z},
   {X=center.X+half+2,Y=center.Y,Z=center.Z},false,false,false,{},{},{},hit)==true
 end
 return function(ticket,expected,mode)
  local proof={collision_committed=false,collision_verified=false,visual_committed=false,visual_verified=false,
   evidence={verifier_version=M.version,observed_unix=now(),read_only=true,blocks=0,colliders=0,models=0,sections=0,
    body_queries=0,ordinary_water_policy='Ignore',renderer_version=c.models and c.models.version},errors={}}
  local function failure(key,reason)proof.error=reason;proof.errors[key]=reason;return proof end
  if not in_game_thread or not in_game_thread()then return failure('thread','native_probe_not_on_game_thread')end
  if #expected>maximum then return failure('budget','native_probe_region_exceeds_budget')end
  if mode~='client'and mode~='server'then return failure('mode','native_probe_mode_invalid')end
  if c.status().side~=mode then return failure('mode','native_probe_side_mismatch')end
  if mode=='client'and(not c.models or not accepted[c.models.version])then return failure('renderer','renderer_version_not_accepted')end
  local ok,result=pcall(function()
   local context=c.context();assert(valid(context),'Native context unavailable')
   assert(context:IsA('/Script/Pal.PalGameStateInGame'),'Native context is not an in-game Pal state')
   if mode=='server'then assert(context:HasAuthority(),'Native server context lacks authority')end
   local owner=context:GetAddress();proof.evidence.context=owner
   local wanted,objects={},{}
   for _,r in ipairs(expected)do
    assert(c.actors[r.key]==r.entry,'Native entry changed during readiness')
    assert(#r.entry.handles==#r.geometry.boxes,'Native shape count mismatch')
    for _,h in ipairs(r.entry.handles)do wanted[h]=true end
    if r.entry.model then wanted[r.entry.model]=true end
   end
   -- One enumeration for the bounded region, never one scan per block.
   for _,a in ipairs(enumerate('Actor')or{})do if valid(a)and wanted[a:GetAddress()]then objects[a:GetAddress()]=a end end
   local function checked_actor(handle)
    local a=objects[handle];assert(valid(a),'Native actor missing')
    local o=a:GetOwner();assert(valid(o)and o:GetAddress()==owner,'Native actor belongs to another world')
    local root=a.RootComponent;assert(valid(root),'Native actor root missing');return a,root
   end
   for _,record in ipairs(expected)do
    local g,e=record.geometry,record.entry;local x,y,z=table.unpack(g.at)
    local O=c.origin;local y_origin=O.y_origin or 64
    for i,b in ipairs(g.boxes)do
     local a,root=checked_actor(e.handles[i])
     assert(root:IsA(mode=='client'and'/Script/Engine.StaticMeshComponent'or'/Script/Engine.BoxComponent'),'Native collision component type mismatch')
     local at={X=O.X+(x+(b[1]+b[4])*.5)*100,Y=O.Y-(z+(b[3]+b[6])*.5)*100,Z=O.Z+(y-y_origin+(b[2]+b[5])*.5)*100}
     local scale={X=b[4]-b[1],Y=b[6]-b[3],Z=b[5]-b[2]}
     assert(vector_matches(a:K2_GetActorLocation(),at,.01),'Native collision position mismatch')
     assert(vector_matches(root:K2_GetComponentScale(),scale,.0001),'Native collision scale mismatch')
     assert(identity_rotation(root:K2_GetComponentRotation()),'Native collision rotation mismatch')
     if mode=='client'then
      local mesh=root.StaticMesh;assert(valid(mesh)and mesh:GetFullName():find('/Engine/BasicShapes/Cube.Cube',1,true),'Native collision cube asset changed')
     else assert(vector_matches(root:GetUnscaledBoxExtent(),{X=50,Y=50,Z=50},.001),'Native box extent mismatch')end
     assert(root:GetCollisionEnabled()==3,'Native collision is not QueryAndPhysics')
     assert(root:GetGenerateOverlapEvents()==false,'Native collision overlap events enabled')
     for _,channel in ipairs(WATER)do assert(root:GetCollisionResponseToChannel(channel)==0,'Ordinary solid responds as water')end
     for _,channel in ipairs(BLOCK)do assert(root:GetCollisionResponseToChannel(channel)==2,'Native physical channel missing')end
     assert(query(root,at,scale),'Native shape has no queryable physics body')
     proof.evidence.body_queries=proof.evidence.body_queries+1;proof.evidence.colliders=proof.evidence.colliders+1
    end
    if mode=='client'and g.visible~=false and g.render_kind~='none'then
     assert(e.model,'Native visible model missing: '..g.id)
     local a,root=checked_actor(e.model)
     assert(root:IsA('/Script/ProceduralMeshComponent.ProceduralMeshComponent'),'Visual is not a procedural model')
     if e.model_component then assert(root:GetAddress()==e.model_component,'Native model component changed')end
     assert(a.bHidden==false and root:IsVisible(),'Native model hidden')
     assert(identity_rotation(root:K2_GetComponentRotation()),'Native model rotation mismatch')
     assert(vector_matches(root:K2_GetComponentScale(),{X=1,Y=1,Z=1},.0001),'Native model scale mismatch')
     local at={X=O.X+x*100,Y=O.Y-z*100,Z=O.Z+(y-y_origin)*100}
     assert(vector_matches(a:K2_GetActorLocation(),at,.01),'Native model placement mismatch')
     assert(root:GetCollisionEnabled()==0,'Native visual has collision')
     for _,channel in ipairs(WATER)do assert(root:GetCollisionResponseToChannel(channel)==0,'Native visual responds as water')end
     local groups,why=c.models.geometry(g.id,g.state,x,y,z);assert(groups and #groups>0,why or'Native geometry missing')
     assert(root:GetNumSections()==#groups,'Native section count mismatch')
     for index,group in ipairs(groups)do
      local alpha=group.alpha_mode or'opaque'
      assert(caps[alpha],'Native alpha capability not accepted: '..alpha)
      assert((group.tint or-1)<0 or caps.tint,'Native tint capability not accepted')
      assert(not present(group.animation_clip)and not present(group.animation)or caps.animation,'Native animation capability not accepted')
      assert((group.light_emission or 0)==0 or caps.lighting,'Native light emission capability not accepted')
      local mat=root:GetMaterial(index-1);assert(valid(mat),'Native material missing')
      local expected_blend=alpha=='opaque'and 0 or(alpha=='cutout'and 1 or 2)
      assert(mat:GetBlendMode()==expected_blend,'Native material blend mode mismatch')
      local tex=mat:K2_GetTextureParameterValue(fname(options.texture_parameter or'Base Texture'))
      assert(valid(tex),'Native base texture binding missing')
      proof.evidence.sections=proof.evidence.sections+1
     end
     proof.evidence.models=proof.evidence.models+1
    end
    proof.evidence.blocks=proof.evidence.blocks+1
   end
   proof.collision_committed=true;proof.collision_verified=true
   proof.visual_committed=true;proof.visual_verified=true;proof.evidence.visual_required=mode=='client'
   return proof
  end)
  if not ok then return failure('native',tostring(result))end
  return result
 end
end
return M
