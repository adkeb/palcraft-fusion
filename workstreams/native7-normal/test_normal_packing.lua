local dir=assert(arg[1]);local A=dofile(dir..'/native_shader_attributes.lua')
local examples={
 {-1.399999976158142,-1},{-1,-1},{-.7071067690849304,-.7007874250411987},
 {-.3333333432674408,-.33070865273475647},{-.009999999776482582,-.007874015718698502},
 {0,0},{.009999999776482582,.007874015718698502},
 {.3333333432674408,.33070865273475647},{.7071067690849304,.7007874250411987},
 {1,1},{1.399999976158142,1}
}
local g={actual_renderer_capture=true}
for _,e in ipairs(examples)do
 local x,y,z=A.normal(g,{0,0,0,e[1],0,0,0,0})
 assert(x==e[2] and y==0 and z==0,'Original MC float32 packing sample mismatch')
end
local x,y,z=A.normal(g,{0,0,0,.5,-.3333333432674408,.7071067690849304,0,0})
assert(x==string.unpack('<f',string.pack('<f',63/127)))
assert(y==-string.unpack('<f',string.pack('<f',42/127)))
assert(z==string.unpack('<f',string.pack('<f',89/127)))
x,y,z=A.normal(g,{0,0,0,.001,.001,.001,0,0})
assert(x==0 and y==0 and z==0,'Original decoded zero normal is legal')
assert(not pcall(A.normal,g,{0,0,0,0/0,0,0,0,0}))
x,y,z=A.normal({}, {0,0,0,.5,.25,.125,0,0})
assert(x==.5 and y==.25 and z==.125,'Noncapture normal must retain its original path')
io.write('{"ok":true,"actual_bytecode_samples":11,"basis_zero_finite_and_legacy_cases":4,"MC_ENTITY_SNORM_pack_rule":true,"normal_unit_applied":false,"actual_GPU_verified":false}\n')
