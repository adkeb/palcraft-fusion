local probe=_G.PalCraftMaterialThreeProbe;local destroyed=0
if probe then
 for _,actor in ipairs(probe.actors or{})do if actor:IsValid()then actor:K2_DestroyActor();destroyed=destroyed+1 end end
end
_G.PalCraftMaterialThreeProbe=nil
return{temporary_render_cleanup=true,destroyed=destroyed,gameplay_unchanged=true}
