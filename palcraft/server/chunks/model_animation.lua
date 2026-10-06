-- Rigid motion of original MC model parts. Cached static geometry stays readonly.
local M={}
local function dot(a,b)return a[1]*b[1]+a[2]*b[2]+a[3]*b[3]end
local function rotate(v,axis,angle)
 local c,s=math.cos(angle),math.sin(angle);local d=dot(axis,v)*(1-c)
 return{v[1]*c+(axis[2]*v[3]-axis[3]*v[2])*s+axis[1]*d,
        v[2]*c+(axis[3]*v[1]-axis[1]*v[3])*s+axis[2]*d,
        v[3]*c+(axis[1]*v[2]-axis[2]*v[1])*s+axis[3]*d}
end
function M.apply(groups,clip,input,rotation)
 local value=math.max(0,math.min(1,input));local curved=clip.input_curve=='one_minus_cube'and(1-(1-value)^3)or value
 local output={}
 for i,g in ipairs(groups)do
  local motion=clip.parts[g.part];local copy={};for k,v in pairs(g)do copy[k]=v end
  output[i]=copy
  if motion and motion.moving then
   local pivot,axis,move=motion.pivot,motion.rotation_axis,motion.translation_per_input
   if rotation then pivot=rotation(pivot,true);axis=rotation(axis,false);move=rotation(move,false)end
   local length=math.sqrt(dot(axis,axis));axis={axis[1]/length,axis[2]/length,axis[3]/length}
   copy.vertices={}
   local angle=motion.radians_per_input*curved
   for j,v in ipairs(g.vertices)do
    local p={v[1]/100-pivot[1],v[3]/100-pivot[2],-v[2]/100-pivot[3]}
    p=rotate(p,axis,angle)
    p={p[1]+pivot[1]+move[1]*value,p[2]+pivot[2]+move[2]*value,p[3]+pivot[3]+move[3]*value}
    local n=rotate({v[4],v[6],-v[5]},axis,angle)
    copy.vertices[j]={p[1]*100,-p[3]*100,p[2]*100,n[1],-n[3],n[2],v[7],v[8]}
   end
  end
 end
 return output
end
return M
