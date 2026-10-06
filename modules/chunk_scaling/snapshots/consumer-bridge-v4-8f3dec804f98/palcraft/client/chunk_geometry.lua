-- Pure data preparation for native chunk rendering. Minecraft remains authoritative.
-- No Unreal, network, journal writes, or process lifecycle calls occur here.
local M={version=1}
local directions={down={0,-1,0},up={0,1,0},north={0,0,-1},south={0,0,1},west={-1,0,0},east={1,0,0}}
local opposite={down='up',up='down',north='south',south='north',west='east',east='west'}
M.directions=directions
M.collision_policy={enabled=3,overlaps=false,default_response=0,
 block_channels={0,1,2,4,5,6,15,16,20,21,22,24,26,27,28,29},
 ignore_channels={14,19,25},water_semantics='solid_boxes_are_not_water',replicated=false}
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<math.huge end
local function is_null(v)return type(v)=='table'and getmetatable(v)~=nil and tostring(v)=='json.null'end
M.is_null=is_null
local function clone(v,seen)
 if type(v)~='table'then return v end
 if is_null(v)then return v end -- Preserve the decoder's sentinel identity on copies.
 seen=seen or{};assert(not seen[v],'Cyclic block metadata');seen[v]=true
 local result={};for k,x in pairs(v)do result[k]=clone(x,seen)end;seen[v]=nil;return result
end
M.clone=clone
local function keys(t)local r={};for k in pairs(t)do r[#r+1]=k end;table.sort(r);return r end
M.sorted_keys=keys
-- Stable, unambiguous metadata keys: tint values and animation/lighting must not alias.
function M.stable(v)
 if is_null(v)then return'n'end
 local kind=type(v)
 if kind=='nil'then return'n'end
 if kind=='boolean'then return v and't'or'f'end
 if kind=='number'then assert(finite(v),'Non-finite metadata');return'd'..string.format('%.17g',v)..';'end
 if kind=='string'then return's'..#v..':'..v end
 assert(kind=='table','Unsupported metadata type '..kind)
 local list={};for k in pairs(v)do list[#list+1]=k end
 table.sort(list,function(a,b)return type(a)==type(b)and a<b or type(a)<type(b)end)
 local out={'{'};for _,k in ipairs(list)do out[#out+1]=M.stable(k);out[#out+1]=M.stable(v[k])end
 out[#out+1]='}';return table.concat(out)
end
function M.normalize(block)
 assert(type(block)=='table'and type(block.id)=='string','Block id required')
 assert(type(block.at)=='table'and #block.at==3,'Block at={x,y,z} required')
 for _,n in ipairs(block.at)do assert(math.tointeger(n),'Integral block coordinate required')end
 local b=clone(block)
 if is_null(b.boxes)then b.boxes=nil end
 if b.boxes then
  assert(type(b.boxes)=='table','Collision boxes array required')
  for _,box in ipairs(b.boxes)do
   assert(type(box)=='table'and #box==6,'Six-coordinate collision AABB required')
   for _,n in ipairs(box)do assert(finite(n),'Finite collision AABB required')end
   for i=1,3 do assert(box[i]<box[i+3],'Positive collision AABB extent required')end
  end
 end
 -- Absent boxes is unknown; an explicit empty array means non-solid. Never invent a cube.
 local semantic=clone(block)
 for _,k in ipairs({'signature','op','snapshot','seq','tick','causes','flags','revision','session'})do semantic[k]=nil end
 if block.chunk_visual=='static'then semantic.block_entity=nil end
 b.signature=M.stable(semantic);return b
end
function M.chunk_coords(x,y,z,size)return math.floor(x/size),math.floor(y/size),math.floor(z/size)end
function M.local_index(x,y,z,size)return(x%size)+size*((z%size)+size*(y%size))end
function M.tile_index(x,y,z,size,tile)
 local n=size//tile;return(x%size)//tile+n*((z%size)//tile+n*((y%size)//tile))
end
function M.tile_origin(index,size,tile)
 local n=size//tile;return(index%n)*tile,(index//(n*n))*tile,((index//n)%n)*tile
end
local function rects(shape)
 if shape==true or shape=='full'then return{{0,0,1,1}}end
 if type(shape)=='table'then return shape.rects or shape end
 return{}
end
-- Exact union coverage of axis-aligned Minecraft face-shape rectangles, with no grid
-- rasterization. These are render-occlusion shapes supplied by MC, never physics boxes.
function M.covered(source,cover)
 source,cover=rects(source),rects(cover);if #source==0 or #cover==0 then return false end
 for _,s in ipairs(source)do
  if #s~=4 or s[1]>=s[3]or s[2]>=s[4]then return false end
  local cuts={s[1],s[3]}
  for _,r in ipairs(cover)do if #r~=4 then return false end
   if r[1]>s[1]and r[1]<s[3]then cuts[#cuts+1]=r[1]end
   if r[3]>s[1]and r[3]<s[3]then cuts[#cuts+1]=r[3]end
  end
  table.sort(cuts)
  for i=1,#cuts-1 do if cuts[i]<cuts[i+1]then
   local mid=(cuts[i]+cuts[i+1])*.5;local intervals={}
   for _,r in ipairs(cover)do if r[1]<=mid and r[3]>=mid and r[2]<r[4]then intervals[#intervals+1]={r[2],r[4]}end end
   table.sort(intervals,function(a,b)return a[1]<b[1]end)
   local last=s[2];for _,r in ipairs(intervals)do
    if r[1]>last+1e-9 then break end
    if r[2]>last then last=r[2]end
    if last>=s[4]-1e-9 then break end
   end
   if last<s[4]-1e-9 then return false end
  end end
 end
 return true
end
local function hidden(block,neighbor,direction)
 if not direction then return false end
 -- Authoritative shouldRenderFace/skipRendering from MC takes precedence.
 if block.face_visibility and block.face_visibility[direction]~=nil then return block.face_visibility[direction]==false end
 if block.skip_rendering and block.skip_rendering[direction]==true then return true end
 if not neighbor then return false end
 local a,b=block.occlusion,neighbor.occlusion
 if not a or not b or not a.can_occlude or not b.can_occlude then return false end
 local af,bf=a.faces or a,b.faces or b
 return M.covered(af[direction],bf[opposite[direction]])
end
M.face_hidden=hidden
local function metadata(group,block)
 local index=group.tint or-1
 local rgb=group.tint_rgb
 if is_null(rgb)then rgb=nil end
 if rgb==nil and block.tint_colors and not is_null(block.tint_colors)then rgb=block.tint_colors[index]or block.tint_colors[tostring(index)]end
 if is_null(rgb)then rgb=nil end
 local m={texture=group.texture,alpha_mode=group.alpha_mode or'opaque',tint=group.tint or-1,
  shade=group.shade~=false,light_emission=group.light_emission or 0,part=group.part,
  texture_meta=group.texture_meta,animation=group.animation,
  tint_rgb=rgb,
  tint_value=(block.tint_values and(block.tint_values[group.tint]or block.tint_values[tostring(group.tint)]))or group.tint_value or group.tint_color,
  lighting=block.lighting,render_layer=block.render_layer}
 return m
end
local function add_quad(target,source,first,dx,dy,dz)
 local base=#target.vertices
 for i=1,4 do local v=assert(source.vertices[first+i],'Geometry quad range')
  assert(#v==8,'Unsupported model vertex attributes must use an explicit fallback')
  target.vertices[base+i]={v[1]+dx,v[2]+dy,v[3]+dz,v[4],v[5],v[6],v[7],v[8]}
 end
 -- Preserve the oracle's winding and all six zero-based indices, even if extended.
 local offset=(first//4)*6
 for i=1,6 do target.indices[#target.indices+1]=base+assert(source.indices[offset+i])-first end
end
local function new_group(meta,key)
 local g={};for k,v in pairs(meta)do g[k]=v end
 g.key=key;g.vertices={};g.indices={};return g
end
local function collision_record(box,x,y,z,at,block)
 local b={box[1]+x-at[1],box[2]+y-at[2],box[3]+z-at[3],box[4]+x-at[1],box[5]+y-at[2],box[6]+z-at[3]}
 return{bounds=b,properties={policy=block.collision_policy or M.collision_policy,
  material=block.physics_material,friction=block.friction,fluid_contact=block.fluid_contact}}
end
-- The builder coroutine yields after each block. Asset lookup is performed through
-- geometry_v2's own weighted-variant cache, with original world positions as the seed.
function M.build_tile(options,chunk,tile,lookup)
 local size,step=options.chunk_size or 16,options.tile_size or 4
 local tx,ty,tz=M.tile_origin(tile,size,step);local at=chunk.at
 local result={groups={},collision={},fluids={},fallbacks={},dynamic={},stats={blocks=0,input_faces=0,faces=0,culled_faces=0}}
 for ly=ty,ty+step-1 do for lz=tz,tz+step-1 do for lx=tx,tx+step-1 do
  local x,y,z=at[1]+lx,at[2]+ly,at[3]+lz;local block=lookup(chunk.dimension,x,y,z)
  if block then
   result.stats.blocks=result.stats.blocks+1
   if block.boxes==nil then result.fallbacks[#result.fallbacks+1]={at=block.at,id=block.id,state=block.state,reason='missing_collision_shape',block=block}
   else for _,box in ipairs(block.boxes)do result.collision[#result.collision+1]=collision_record(box,x,y,z,at,block)end end
   if options.visuals~=false and block.fluid and block.fluid~=false and not is_null(block.fluid)and block.fluid.empty~=true and block.fluid.kind~='none'then
    result.fluids[#result.fluids+1]={at=block.at,fluid=block.fluid,block=block}
   end
   local groups,why,detail
   if options.visuals==false then groups={}else groups,why,detail=options.geometry.geometry(block.id,block.state,x,y,z)end
   if not groups then
    result.fallbacks[#result.fallbacks+1]={at=block.at,id=block.id,state=block.state,reason=why or'missing_geometry',detail=detail,block=block}
   else
    local dynamic=options.visuals~=false and block.chunk_visual~='static'and((block.dynamic and not is_null(block.dynamic))or(block.block_entity and not is_null(block.block_entity)))
    for _,g in ipairs(groups)do
     if g.animation_clip and not is_null(g.animation_clip)then dynamic=true end
     if not block.chunk_rigid_model then
      for _,v in pairs({part=g.part,block_entity=g.block_entity})do if v and not is_null(v)then dynamic=true end end
     end
    end
    if dynamic then
     result.dynamic[#result.dynamic+1]={at=block.at,id=block.id,state=block.state,groups=groups,block=block,
      reason='requires_per_block_dynamic_transform'}
     for _,g in ipairs(groups)do result.stats.input_faces=result.stats.input_faces+#g.indices//6;result.stats.faces=result.stats.faces+#g.indices//6 end
    else
     for _,source in ipairs(groups)do
      local meta=metadata(source,block);local key=M.stable(meta);local target=result.groups[key]
      local ranges=source.face_ranges
      -- Unknown future topology is retained as a fallback, never coerced to a cube.
      if #source.vertices%4~=0 or #source.indices~=#source.vertices//4*6 or not ranges or #ranges~=#source.vertices//4 then
       result.fallbacks[#result.fallbacks+1]={at=block.at,id=block.id,state=block.state,reason='unsupported_quad_topology',groups={source},block=block}
      else
       for _,face in ipairs(ranges)do
        result.stats.input_faces=result.stats.input_faces+1
        local d=directions[face.cull];local neighbor=d and lookup(chunk.dimension,x+d[1],y+d[2],z+d[3])
        if hidden(block,neighbor,face.cull)then result.stats.culled_faces=result.stats.culled_faces+1
        else
         if not target then target=new_group(meta,key);result.groups[key]=target end
         if block.chunk_model_lookup then
          target.model_members=target.model_members or{}
          target.model_members[#target.vertices//4+1]={at=block.at,id=block.id,state=block.state}
         end
         add_quad(target,source,face.first_vertex,lx*100,-lz*100,ly*100);result.stats.faces=result.stats.faces+1
        end
       end
      end
     end
    end
   end
  end
  coroutine.yield('block')
 end end end
 return result
end
-- Merge only adjacent rectangular boxes with identical physical policy/properties.
-- No hull expansion and no staircase/fence holes are filled. Proven union is exact.
function M.merge_boxes(records,yield_every)
 local buckets={}
 for _,r in ipairs(records)do local k=M.stable(r.properties);buckets[k]=buckets[k]or{properties=r.properties,boxes={}}
  buckets[k].boxes[#buckets[k].boxes+1]=clone(r.bounds)
 end
 local result={};local work=0
 for _,k in ipairs(keys(buckets))do local bucket=buckets[k];local boxes=bucket.boxes
  -- One pass per axis is conservative. Further coalescing is an optional optimization.
  for axis=1,3 do
   local other={};for i=1,3 do if i~=axis then other[#other+1]=i end end
   table.sort(boxes,function(a,b)
    for _,i in ipairs(other)do if a[i]~=b[i]then return a[i]<b[i]end;if a[i+3]~=b[i+3]then return a[i+3]<b[i+3]end end
    if a[axis]~=b[axis]then return a[axis]<b[axis]end;return a[axis+3]<b[axis+3]
   end)
   local merged={}
   for _,b in ipairs(boxes)do
    local p=merged[#merged];local match=p~=nil
    if match then for _,i in ipairs(other)do if p[i]~=b[i]or p[i+3]~=b[i+3]then match=false;break end end end
    if match and b[axis]<=p[axis+3]and b[axis+3]>=p[axis]then p[axis+3]=math.max(p[axis+3],b[axis+3])
    else merged[#merged+1]=b end
    work=work+1;if yield_every and work%yield_every==0 then coroutine.yield('collision')end
   end
   boxes=merged
  end
  for _,b in ipairs(boxes)do
   result[#result+1]={bounds=b,cm={b[1]*100,-b[6]*100,b[2]*100,b[4]*100,-b[3]*100,b[5]*100},properties=bucket.properties}
  end
 end
 return result
end
function M.assemble(options,chunk,tiles,previous)
 local packet={schema=1,dimension=chunk.dimension,at=clone(chunk.at),revision=chunk.revision,
  generation=chunk.generation,visual_pages={},collision_pages={},fluids={},fallbacks={},dynamic={},static_model_blocks={},
  stats={blocks=0,input_faces=0,faces=0,culled_faces=0,vertices=0,indices=0,wire_bytes=0,input_boxes=0,boxes=0,rebuilt_tiles=0}}
 local raw,all={},{ }
 for _,index in ipairs(keys(tiles))do local tile=tiles[index]
  for k,n in pairs(tile.stats)do packet.stats[k]=(packet.stats[k]or 0)+n end
  for _,r in ipairs(tile.collision)do raw[#raw+1]=r end
  for _,name in ipairs({'fluids','fallbacks','dynamic'})do for _,r in ipairs(tile[name])do packet[name][#packet[name]+1]=r end end
  for k,g in pairs(tile.groups)do all[k]=all[k]or{};all[k][#all[k]+1]=g end
  if not previous or previous[index]~=tile then packet.stats.rebuilt_tiles=packet.stats.rebuilt_tiles+1 end
  coroutine.yield('tile')
 end
 local maxv=options.page_vertices or 8192;local maxi=options.page_indices or 24576
 assert(maxv>=4 and maxv<=65536 and maxi>=6 and maxi<=262144,'Native page limits')
 -- Every page fits one existing PALCPRC3 request. Equal material metadata is combined
 -- across ALL tiles in a section; stable tile keys are only a CPU geometry cache.
 local page
 for _,key in ipairs(keys(all))do local group
  for _,source in ipairs(all[key])do for first=0,#source.vertices-1,4 do
   if not page or page.vertices+4>maxv or page.indices+6>maxi or(not group and #page.groups>=(options.page_sections or 256))then
    page={groups={},at=packet.at,revision=packet.revision,vertices=0,indices=0};packet.visual_pages[#packet.visual_pages+1]=page;group=nil
   end
   if not group then group=new_group(metadata(source,{}),key)
    -- Source metadata includes resolved biome tint and lighting; copy it losslessly.
    for k,v in pairs(source)do if k~='vertices'and k~='indices'and k~='model_members'then group[k]=v end end
    page.groups[#page.groups+1]=group
   end
   add_quad(group,source,first,0,0,0);page.vertices=page.vertices+4;page.indices=page.indices+6
   local member=source.model_members and source.model_members[first//4+1]
   if member then
    local id=('%d:%d:%d'):format(table.unpack(member.at));local record=packet.static_model_blocks[id]
    if not record then record={at=clone(member.at),id=member.id,state=member.state,pages={},faces=0};packet.static_model_blocks[id]=record end
    record.pages[#packet.visual_pages]=true;record.faces=record.faces+1
   end
   packet.stats.vertices=packet.stats.vertices+4;packet.stats.indices=packet.stats.indices+6
   if first%512==0 then coroutine.yield('pack')end
  end end
  group=nil
 end
 packet.stats.input_boxes=#raw
 local boxes=M.merge_boxes(raw,128);packet.stats.boxes=#boxes
 local count=options.collision_page_boxes or 256;assert(count>=1,'Collision page size')
 for i=1,#boxes,count do local p={boxes={},at=packet.at,revision=packet.revision,policy=M.collision_policy}
  for j=i,math.min(i+count-1,#boxes)do p.boxes[#p.boxes+1]=boxes[j]end
  packet.collision_pages[#packet.collision_pages+1]=p;coroutine.yield('collision_page')
 end
 for _,p in ipairs(packet.visual_pages)do packet.stats.wire_bytes=packet.stats.wire_bytes+(options.wire_header_bytes or 184)+#p.groups*16+p.vertices*64+p.indices*4 end
 packet.requirements={atomic_commit=true,collision_compound=#boxes>0,fluids=#packet.fluids>0,
  dynamic=#packet.dynamic>0,fallbacks=#packet.fallbacks>0,alpha_modes={},tint=false,animation=false,lighting=false}
 for _,p in ipairs(packet.visual_pages)do for _,g in ipairs(p.groups)do
  packet.requirements.alpha_modes[g.alpha_mode]=true
  packet.requirements.tint=packet.requirements.tint or g.tint>=0
  packet.requirements.animation=packet.requirements.animation or(g.animation and not is_null(g.animation))or(g.texture_meta and g.texture_meta.animation~=nil and g.texture_meta.animation~=false and not is_null(g.texture_meta.animation))or false
  packet.requirements.lighting=packet.requirements.lighting or g.lighting~=nil
 end end
 return packet
end
return M
