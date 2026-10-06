local m=_G.PalCraftForm;local old=m.tick
for _,v in pairs(m.hidden_widgets)do v.opacity=1 end
m.tick=function(...)
 local was=m.active;local widgets=m.hidden_widgets;local result=old(...)
 if m.active then for _,v in pairs(m.hidden_widgets)do if v.object:IsValid()then if v.opacity==nil then v.opacity=v.object:GetRenderOpacity()end;v.object:SetRenderOpacity(0)end end
 elseif was then for _,v in pairs(widgets)do if v.object:IsValid()then v.object:SetRenderOpacity(v.opacity or 1)end end end
 return result
end
return{hud_opacity_restore=true}
