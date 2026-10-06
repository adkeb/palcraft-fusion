-- Queue through the existing isolated client's game-thread client-op channel.
-- No timers, focus, mouse, character movement, items, server or hardware changes.
local WINROOT=assert(os.getenv('PALCRAFT_WINDOWS_ROOT'),'Configured installed Windows root required'):gsub('\\','/'):gsub('/+$','')
local ROOT=WINROOT..'/PalCraft-Dev/bridge/'
local J=dofile(WINROOT..'/PalCraft-Client/Pal/Binaries/Win64/ue4ss/Mods/PalCraftClient/Scripts/json.lua')
assert(type(IsInGameThread)=='function'and IsInGameThread(),'Power profile requires the game-thread RPC')
local function read(name)
 local f=io.open(ROOT..name,'rb');if not f then return end
 local raw=f:read('*a');f:close();return J.decode(raw)
end
local request=assert(read('power-profile-request.json'),'Power profile request missing')
assert(request.schema==1 and type(request.id)=='string'and #request.id>0 and #request.id<=128,'Power profile request ID invalid')
assert(request.mode=='day'or request.mode=='night','Expected day or night profile')
local methods={
 ViewDistance='SetViewDistanceQuality',AntiAliasing='SetAntiAliasingQuality',Shadow='SetShadowQuality',
 GlobalIllumination='SetGlobalIlluminationQuality',Reflection='SetReflectionQuality',PostProcess='SetPostProcessingQuality',
 Texture='SetTextureQuality',Effects='SetVisualEffectQuality',Foliage='SetFoliageQuality',Shading='SetShadingQuality'
}
local day={ViewDistance=1,AntiAliasing=0,Shadow=1,GlobalIllumination=0,Reflection=0,PostProcess=0,Texture=1,Effects=0,Foliage=1,Shading=1}
local qualities={};for key,value in pairs(day)do qualities[key]=request.mode=='night'and 0 or value end
local scale=request.mode=='night'and 50 or 71
local limit=request.mode=='night'and 15 or(request.frame_rate_limit or 60)
if limit~=nil then assert(type(limit)=='number'and limit>=0 and limit<=240,'Frame override must be0..240')end
local function require_function(object,method)
 local value=object[method]
 assert(tostring(value):match('^UFunction:'),'GameUserSettings API unavailable: '..method..' ('..tostring(value)..')')
 return value
end
local provider=StaticFindObject('/Script/Engine.Default__GameUserSettings')
assert(provider and provider:IsValid(),'GameUserSettings provider unavailable')
local settings=require_function(provider,'GetGameUserSettings')(provider)
assert(settings and settings:IsValid(),'Client GameUserSettings unavailable')
assert(not settings:GetFullName():find('Default__',1,true),'Expected actual GameUserSettings instance')
-- Validate the entire required setter surface before changing any setting.
for _,method in pairs(methods)do require_function(settings,method)end
for _,method in ipairs({'SetResolutionScaleValueEx','SetFrameRateLimit','ApplyNonResolutionSettings','SaveSettings','GetFrameRateLimit','SetScreenResolution','GetScreenResolution','ApplyResolutionSettings','ConfirmVideoMode'})do
 require_function(settings,method)
end
local k=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')
assert(k and k:IsValid(),'Console settings provider unavailable')
for _,method in ipairs({'GetConsoleVariableFloatValue','GetConsoleVariableIntValue','ExecuteConsoleCommand'})do require_function(k,method)end
for key,method in pairs(methods)do settings[method](settings,qualities[key])end
settings:SetResolutionScaleValueEx(scale)
if limit~=nil then settings:SetFrameRateLimit(limit)end
local current_size=settings:GetScreenResolution()
if current_size.X~=1280 or current_size.Y~=720 then
 settings:SetScreenResolution({X=1280,Y=720});settings:ApplyResolutionSettings(false);settings:ConfirmVideoMode()
end
settings:ApplyNonResolutionSettings()
-- A previous console override can outrank the saved scalability value.
-- Use the normal console route only when the effective scale still differs.
local console_scale_override=false
if math.abs(k:GetConsoleVariableFloatValue('r.ScreenPercentage')-scale)>=.5 then
 local pc
 for _,candidate in ipairs(FindAllOf('PalPlayerController')or{})do
  if candidate:IsValid()and candidate.Pawn:IsValid()and candidate.Player:IsValid()
   and candidate.Player:GetFullName():match('^PalLocalPlayer ')then
   assert(not pc,'More than one local controller for settings');pc=candidate
  end
 end
 assert(pc,'Local controller required for effective resolution scale')
 k:ExecuteConsoleCommand(pc,('r.ScreenPercentage %g'):format(scale),pc);console_scale_override=true
end
settings:SaveSettings()
local size=settings:GetScreenResolution()
local actual={resolution={size.X,size.Y},qualities={},max_fps=k:GetConsoleVariableFloatValue('t.MaxFPS'),
 screen_percentage=k:GetConsoleVariableFloatValue('r.ScreenPercentage'),
 scalability_resolution_quality=k:GetConsoleVariableFloatValue('sg.ResolutionQuality'),
 saved_frame_limit=settings:GetFrameRateLimit()}
for key in pairs(methods)do
 actual.qualities[key]=k:GetConsoleVariableIntValue('sg.'..key..'Quality')
 assert(actual.qualities[key]==qualities[key],'Quality did not apply: '..key)
end
assert(size.X==1280 and size.Y==720,'1280x720 did not apply')
assert(math.abs(actual.screen_percentage-scale)<.5,'Resolution scale did not apply')
assert(math.abs(actual.scalability_resolution_quality-scale)<.5,'Scalability resolution quality did not apply')
if limit~=nil then
 assert(math.abs(actual.saved_frame_limit-limit)<.01,'Saved frame limit did not apply')
 assert(math.abs(actual.max_fps-limit)<.01,'Runtime frame limit did not apply')
end
local out={schema=1,request_id=request.id,mode=request.mode,unix=os.time(),saved=true,actual=actual,
 console_scale_override=console_scale_override,
 frame_rate_source=request.mode=='night'and'verified_night15'or(request.frame_rate_limit~=nil and'explicit_day_override'or'leader_day60_policy'),
 complete=true,status='applied',
 original_saved_resolution={1280,720},original_fullscreen_mode=2,fullscreen_mode_unchanged=true,
 unknown_original_runtime_values={'GameUserSettings.FrameRateLimit','t.MaxFPS','r.ScreenPercentage'},
 hardware_or_fan_rpm_changed=false}
local f=assert(io.open(ROOT..'power-profile-result.json','wb'));f:write(J.encode(out));f:close()
return out
