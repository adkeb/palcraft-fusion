-- v2-compatible static geometry plus actual model-part clips and pot decorations.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local G=dofile(dir..'model_geometry_v2.lua')
local Animation=dofile(dir..'model_animation.lua')
local M={};local settings,cache={},{}
local function resource(s)return s:find(':',1,true)and s or'minecraft:'..s end
local function asset(kind,id)
 local key=kind..'/'..resource(id):gsub(':','/')..'.json'
 if cache[key]~=nil then return cache[key]~=false and cache[key]or nil end
 local data
 if settings.load_asset then data=settings.load_asset(kind,resource(id))
 else
  local f=io.open(settings.root..key,'rb')
  if f then data=settings.json.decode(f:read('*a'));f:close()end
 end
 cache[key]=data or false;return data
end
function M.configure(value)
 settings=value;cache={}
 if settings.root and settings.root:sub(-1)~='/'then settings.root=settings.root..'/'end
 G.configure(settings)
end
function M.geometry(id,state,x,y,z,options)
 local opts=options or{}
 local g,why,unsupported=G.geometry(id,state,x,y,z,opts.occluded and{occluded=opts.occluded}or nil)
 if not g then return nil,why,unsupported end
 local block=asset('states',id)
 local selected=G.select(block,G.properties(state),x,y,z)
 local model=#selected==1 and asset('models',selected[1].model)or nil
 if not model or not model.block_entity then return g end
 local clip=model.animation_clip and asset('animations',model.animation_clip)or nil
 local result={}
 for i,group in ipairs(g)do
  local copy={};for k,v in pairs(group)do copy[k]=v end
  copy.block_entity=model.block_entity;copy.model_id=selected[1].model
  if clip then copy.animation=clip.parts[copy.part];copy.animation_clip=model.animation_clip end
  if model.block_entity=='decorated_pot'and opts.decorations then
   local side=copy.part and copy.part:sub(2);local texture=opts.decorations[side]
   if texture then copy.texture=resource(texture);copy.texture_meta=asset('textures',copy.texture)end
  end
  result[i]=copy
 end
 if clip and type(opts.open_progress)=='number'then
  local spec=selected[1]
  result=Animation.apply(result,clip,opts.open_progress,function(value,point)return G.rotation(value,spec,point)end)
 end
 return result
end
function M.clip(id,state,x,y,z)
 local block=asset('states',id);if not block then return nil end
 local selected=G.select(block,G.properties(state),x,y,z)
 if #selected~=1 then return nil end
 local model=asset('models',selected[1].model)
 return model and model.animation_clip and asset('animations',model.animation_clip)or nil,selected[1]
end
function M.animate(groups,clip,input,spec)
 return Animation.apply(groups,clip,input,spec and function(value,point)return G.rotation(value,spec,point)end or nil)
end
function M.clear_cache()cache={};G.clear_cache()end
M.properties=G.properties;M.rotation=G.rotation;M.lock_uv=G.lock_uv
return M
