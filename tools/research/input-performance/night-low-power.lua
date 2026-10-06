local pc
for _,p in ipairs(FindAllOf('PalPlayerController')or{})do
 if p:IsValid()and p.Pawn:IsValid()and p.Player:IsValid()and p.Player:GetFullName():match('^PalLocalPlayer ')then pc=p;break end
end
assert(pc,'No owned local PalPlayerController')
local k=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')
local settings={'t.MaxFPS 15','sg.ViewDistanceQuality 0','sg.AntiAliasingQuality 0','sg.ShadowQuality 0','sg.GlobalIlluminationQuality 0','sg.ReflectionQuality 0','sg.PostProcessQuality 0','sg.TextureQuality 0','sg.EffectsQuality 0','sg.FoliageQuality 0','sg.ShadingQuality 0','r.ScreenPercentage 50'}
for _,command in ipairs(settings)do k:ExecuteConsoleCommand(pc,command,pc)end
return{night_low_power=true,commands=settings,controller=pc:GetFullName(),world_delta_ms=StaticFindObject('/Script/Engine.Default__GameplayStatics'):GetWorldDeltaSeconds(pc)*1000,form=_G.PalCraftForm.status(),unix=os.time()}
