local k=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')
local s=StaticFindObject('/Script/Engine.Default__GameUserSettings'):GetGameUserSettings()
s:SetOverallScalabilityLevel(0);s:SetResolutionScaleValueEx(50);s:SetFrameRateLimit(15);s:ApplyNonResolutionSettings();s:SaveSettings()
local q={settings_object=s:GetFullName(),saved_frame_limit=s:GetFrameRateLimit(),max_fps=k:GetConsoleVariableFloatValue('t.MaxFPS'),screen_percentage=k:GetConsoleVariableFloatValue('r.ScreenPercentage'),qualities={},unix=os.time()}
for _,n in ipairs({'ViewDistance','AntiAliasing','Shadow','GlobalIllumination','Reflection','PostProcess','Texture','Effects','Foliage','Shading'})do q.qualities[n]=k:GetConsoleVariableIntValue('sg.'..n..'Quality')end
return q
