-- Exact MC font-pixel -> block-local -> UE centimetre transform. No text layout
-- or font guessing in Lua; the live vanilla renderer supplies both matrices.
local M={version=1}
local function finite(v)return type(v)=='number'and v==v and math.abs(v)<math.huge end
local function integer(v)return finite(v)and math.tointeger(v)end
local function str(v)return type(v)=='string'and #v>0 and #v<=1024 end
local function sha(v)return type(v)=='string'and #v==64 and not v:find('[^a-f0-9]')end
function M.key(dim,at)return dim..':'..table.concat(at,',')end
function M.fence(value)
 assert(type(value)=='table'and str(value.world_session)and str(value.dim)and str(value.mapping)
  and str(value.mc_uuid)and integer(value.view)and value.view>=0,'Trusted sign world/view fence required')
 local parts={value.world_session,value.dim,tostring(value.view),value.mapping,value.mc_uuid}
 for i,v in ipairs(parts)do parts[i]=#v..':'..v end
 return table.concat(parts,'|')
end
local function side(s)
 assert(type(s)=='table'and type(s.transform)=='table'and #s.transform==16,'Vanilla sign text matrix required')
 for _,v in ipairs(s.transform)do assert(finite(v)and math.abs(v)<1e6,'Invalid text matrix')end
 local m=s.transform
 assert(math.abs(m[4])+math.abs(m[8])+math.abs(m[12])<1e-5 and math.abs(m[16]-1)<1e-5,'Affine MC text matrix required')
 local b=assert(s.pixel_bounds);assert(#b==4,'Four font-pixel bounds required')
 for _,v in ipairs(b)do assert(integer(v),'Integral text canvas required')end
 assert(b[1]<b[3]and b[2]<b[4]and b[3]-b[1]<=512 and b[4]-b[2]<=256,'Text canvas exceeds limits')
 local image=assert(s.image);assert(sha(image.sha256)and image.path=='textures/'..image.sha256..'.png','Content-addressed private text PNG required')
 assert(integer(image.scale)and image.scale>=1 and image.scale<=8,'Text image scale required')
 assert(image.width==(b[3]-b[1])*image.scale and image.height==(b[4]-b[2])*image.scale,'Text image/canvas size mismatch')
 assert(s.light_baked==true and s.alpha=='straight','Vanilla light/straight alpha required')
 assert(image.alpha_mode==nil or image.alpha_mode=='cutout'or image.alpha_mode=='translucent','Text alpha mode invalid')
 return true
end
function M.validate_row(row)
 assert(type(row)=='table'and type(row.at)=='table'and #row.at==3 and str(row.id)and str(row.state_key),'Sign block row required')
 for _,v in ipairs(row.at)do assert(integer(v)and math.abs(v)<30000000,'Invalid sign block position')end
 assert(row.id:match('_sign$'),'Only actual sign block IDs may have text planes')
 side(row.front);side(row.back);return true
end
local function position(m,x,y,z)
 return{(m[1]*x+m[5]*y+m[9]*z+m[13])*100,
  -(m[3]*x+m[7]*y+m[11]*z+m[15])*100,
  (m[2]*x+m[6]*y+m[10]*z+m[14])*100}
end
local function face(row,name,dim,root,bias)
 local s=row[name];local m=s.transform;local b=s.pixel_bounds
 local nx,ny,nz=m[9],-m[11],m[10];local length=math.sqrt(nx*nx+ny*ny+nz*nz)
 assert(length>1e-12,'Degenerate text plane');nx,ny,nz=nx/length,ny/length,nz/length
 local corners={{b[1],b[2],0,0},{b[1],b[4],0,1},{b[3],b[4],1,1},{b[3],b[2],1,0}}
 local vertices={}
 for i,p in ipairs(corners)do local v=position(m,p[1],p[2],bias);vertices[i]={v[1],v[2],v[3],nx,ny,nz,p[3],p[4]}end
 -- The negative font-Y scale is already in the vanilla transform. Winding is
 -- fixed across all40 original layouts, including opposite-facing back text.
 return{texture='palcraft:sign/'..s.image.sha256,material_root=root,text_plane=true,
  sign_key=M.key(dim,row.at),side=name,image=s.image,vertices=vertices,indices={0,1,2,0,2,3},
  alpha_mode=s.image.alpha_mode or'cutout',shade=false,tint=-1,light_emission=0,
  texture_meta={baked_diffuse_tint=true,light_baked=true},minecraft_glowing=s.glowing,
  minecraft_color=s.minecraft_color,minecraft_light_coords=s.light_coords}
end
function M.groups(row,dim,root,options)
 M.validate_row(row);options=options or{}
 local bias=options.depth_bias_pixels or .04
 assert(finite(bias)and bias>=0 and bias<=.25,'Text depth bias limit')
 return{face(row,'front',dim,root,bias),face(row,'back',dim,root,bias)}
end
function M.same_geometry(a,b)
 for i=1,2 do
  for j=1,16 do if a[i==1 and'front'or'back'].transform[j]~=b[i==1 and'front'or'back'].transform[j]then return false end end
  for j=1,4 do if a[i==1 and'front'or'back'].pixel_bounds[j]~=b[i==1 and'front'or'back'].pixel_bounds[j]then return false end end
 end
 return true
end
return M
