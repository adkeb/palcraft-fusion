-- Pure Lua model selection and geometry. No Unreal calls or process mutations.
-- configure({json=JSON, root='.../models-v2/'}) before first geometry() call.
local M={}
local config,assets,compiled={},{},{}
local order={}
local directions={down={0,-1,0},up={0,1,0},north={0,0,-1},south={0,0,1},west={-1,0,0},east={1,0,0}}
-- These are BlockMath.VANILLA_UV_TRANSFORM_LOCAL_TO_GLOBAL's first two
-- columns, not texture V's screen direction. Using -Y here reverses UV lock.
local basis={south={{1,0,0},{0,1,0}},east={{0,0,-1},{0,1,0}},north={{-1,0,0},{0,1,0}},
 west={{0,0,1},{0,1,0}},up={{1,0,0},{0,0,-1}},down={{1,0,0},{0,0,1}}}
local function dot(a,b)return a[1]*b[1]+a[2]*b[2]+a[3]*b[3]end
local function resource(s)return s:find(':',1,true) and s or 'minecraft:'..s end
local function nearest(v)
 local best,amount=nil,-math.huge
 for name,n in pairs(directions)do local value=dot(v,n);if value>amount then best,amount=name,value end end
 return best
end
local function signed32(n)n=n&0xffffffff;return n>=0x80000000 and n-0x100000000 or n end
function M.position_seed(x,y,z)
 -- Mth.getSeed has an int32 multiplication of X before promotion to long.
 local n=signed32(math.tointeger(x)*3129871)~(math.tointeger(z)*116129781)~math.tointeger(y)
 n=n*n*42317861+n*11
 return n<0 and ((n>>16)|(-1<<48))or(n>>16)
end
function M.random_source(seed)
 local rng={seed=(seed~0x5deece66d)&0xffffffffffff}
 function rng.reset(value)rng.seed=(value~0x5deece66d)&0xffffffffffff end
 function rng.bits(count)
  rng.seed=(rng.seed*0x5deece66d+11)&0xffffffffffff
  return rng.seed>>(48-count)
 end
 function rng.next_int(bound)
  assert(bound>0 and bound<=0x7fffffff,'Random bound')
  if(bound&(-bound))==bound then return (bound*rng.bits(31))>>31 end
  while true do local bits=rng.bits(31);local value=bits%bound
   if signed32(bits-value+bound-1)>=0 then return value end
  end
 end
 function rng.next_long()
  -- Java Random.nextLong adds two signed int32 results.
  return (signed32(rng.bits(32))<<32)+signed32(rng.bits(32))
 end
 return rng
end
function M.rotation(p,spec,point)
 local x,y,z=p[1],p[2],p[3];if point then x=x-.5;y=y-.5;z=z-.5 end
 local a=math.rad(-(spec.x or 0));y,z=math.cos(a)*y-math.sin(a)*z,math.sin(a)*y+math.cos(a)*z
 a=math.rad(-(spec.y or 0));x,z=math.cos(a)*x+math.sin(a)*z,-math.sin(a)*x+math.cos(a)*z
 a=math.rad(-(spec.z or 0));x,y=math.cos(a)*x-math.sin(a)*y,math.sin(a)*x+math.cos(a)*y
 if point then x=x+.5;y=y+.5;z=z+.5 end
 return{x,y,z}
end
function M.lock_uv(uv,direction,spec)
 if not spec.uvlock then return uv end
 local n=M.rotation(directions[direction],spec)
 local target=nearest(n)
 local u,v=M.rotation(basis[direction][1],spec),M.rotation(basis[direction][2],spec)
 local a,b=uv[1]-.5,uv[2]-.5
 return{.5+dot(u,basis[target][1])*a+dot(v,basis[target][1])*b,
        .5+dot(u,basis[target][2])*a+dot(v,basis[target][2])*b}
end
function M.matches(condition,props)
 if not condition then return true end
 if condition.OR then for _,v in ipairs(condition.OR)do if M.matches(v,props)then return true end end;return false end
 if condition.AND then for _,v in ipairs(condition.AND)do if not M.matches(v,props)then return false end end;return true end
 for k,v in pairs(condition)do
  local value=tostring(v);local invert=value:sub(1,1)=='!';if invert then value=value:sub(2)end
  local found=false;for option in value:gmatch('[^|]+')do if props[k]==option then found=true;break end end
  if found==invert then return false end
 end
 return true
end
function M.properties(state)
 if type(state)=='table'then local props={};for k,v in pairs(state)do props[k]=tostring(v)end;return props end
 local props={};for k,v in(state or''):gmatch('([%w_]+)=([^,%]%s}]+)')do props[k]=v end
 return props
end
local function asset(kind,id)
 local key=kind..'/'..resource(id):gsub(':','/')..'.json'
 if assets[key]~=nil then return assets[key]~=false and assets[key]or nil end
 local value
 if config.load_asset then value=config.load_asset(kind,resource(id))
 else
  local f=io.open(assert(config.root,'Configure model geometry root')..key,'rb')
  if f then value=assert(config.json,'Configure JSON decoder').decode(f:read('*a'));f:close()end
 end
 assets[key]=value or false;return value
end
local function choose(spec,rng)
 if not spec[1]then return spec end
 if #spec==1 then return spec[1]end
 local total=0;for _,v in ipairs(spec)do total=total+(v.weight or 1)end
 local n=rng.next_int(total)
 for _,v in ipairs(spec)do n=n-(v.weight or 1);if n<0 then return v end end
end
function M.select(block,props,x,y,z)
 local selected={};local rng=M.random_source(M.position_seed(x or 0,y or 0,z or 0))
 if block.variants then
  local keys={};for key in pairs(block.variants)do keys[#keys+1]=key end;table.sort(keys)
  for _,key in ipairs(keys)do
   local condition={};for k,v in key:gmatch('([^=,]+)=([^,]+)')do condition[k]=v end
   if M.matches(condition,props)then selected[1]=choose(block.variants[key],rng);break end
  end
 end
 if block.multipart then
  local partSeed=rng.next_long()
  for _,part in ipairs(block.multipart)do if M.matches(part.when,props)then
   rng.reset(partSeed);selected[#selected+1]=choose(part.apply,rng)
  end end
 end
 return selected
end
function M.configure(settings)
 config=settings;assets={};compiled={};order={}
 if config.root and config.root:sub(-1)~='/'then config.root=config.root..'/'end
end
function M.geometry(id,state,x,y,z,options)
 local block=asset('states',id);if not block then return nil,'missing_blockstate' end
 local selected=M.select(block,M.properties(state),x,y,z)
 if #selected==0 then return nil,'missing_variant' end
 local keys={resource(id)}
 for _,spec in ipairs(selected)do
  keys[#keys+1]=resource(spec.model)..':'..(spec.x or 0)..':'..(spec.y or 0)..':'..(spec.z or 0)..':'..tostring(spec.uvlock or false)
 end
 local key=table.concat(keys,';')
 if not options and compiled[key]then return compiled[key]end
 local groups={};local count=0;local unsupported={}
 for _,spec in ipairs(selected)do
  local model=asset('models',spec.model)
  if not model or(#(model.faces or{})==0 and model.empty~=true)then unsupported[#unsupported+1]=spec.model end
  for _,face in ipairs(model and model.faces or{})do
   local hidden=false
   if directions[face.cull] and options and options.occluded then
    local direction=nearest(M.rotation(directions[face.cull],spec))
    hidden=options.occluded(direction,directions[direction],face)
   end
   if not hidden then
    local mode=face.alpha_mode or(face.translucent and'translucent'or'opaque')
    local groupKey=face.texture..':'..mode..':'..(face.tint or-1)..':'..tostring(face.shade~=false)..':'..(face.light_emission or 0)..':'..(face.part or'')
    local g=groups[groupKey]
    if not g then
     local metadata=asset('textures',face.texture)
     g={texture=face.texture,alpha_mode=mode,tint=face.tint or-1,shade=face.shade~=false,
      light_emission=face.light_emission or 0,part=face.part,texture_meta=metadata,
      vertices={},indices={},face_ranges={}};groups[groupKey]=g
    end
    local first=#g.vertices;local n=M.rotation(face.normal,spec)
    local nLength=math.sqrt(dot(n,n));if nLength>0 then n={n[1]/nLength,n[2]/nLength,n[3]/nLength}end
    for i,p in ipairs(face.vertices)do
     local q=M.rotation(p,spec,true);local uv=M.lock_uv(face.uv[i],face.direction,spec)
     g.vertices[#g.vertices+1]={q[1]*100,-q[3]*100,q[2]*100,n[1],-n[3],n[2],uv[1],uv[2]}
    end
    for _,i in ipairs({0,2,1,0,3,2})do g.indices[#g.indices+1]=first+i end
    g.face_ranges[#g.face_ranges+1]={first_vertex=first,part=face.part,direction=nearest(M.rotation(directions[face.direction],spec)),
     cull=directions[face.cull] and nearest(M.rotation(directions[face.cull],spec))or nil}
    count=count+1
   end
  end
 end
 if #unsupported>0 then return nil,'special_model_required',unsupported end
 local result={};for _,g in pairs(groups)do result[#result+1]=g end
 table.sort(result,function(a,b)
  local ka=a.texture..a.alpha_mode..a.tint..tostring(a.shade)..a.light_emission..(a.part or'')
  local kb=b.texture..b.alpha_mode..b.tint..tostring(b.shade)..b.light_emission..(b.part or'')
  return ka<kb
 end)
 -- An occluded block is valid and has zero sections; callers can remove its visual.
 if not options then
  compiled[key]=result;order[#order+1]=key
  if #order>(config.cache_limit or 256)then compiled[table.remove(order,1)]=nil end
 end
 return result
end
function M.clear_cache()assets={};compiled={};order={}end
return M
