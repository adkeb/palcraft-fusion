local source=assert(arg[1])
local methods={ViewDistance='SetViewDistanceQuality',AntiAliasing='SetAntiAliasingQuality',Shadow='SetShadowQuality',GlobalIllumination='SetGlobalIlluminationQuality',Reflection='SetReflectionQuality',PostProcess='SetPostProcessingQuality',Texture='SetTextureQuality',Effects='SetVisualEffectQuality',Foliage='SetFoliageQuality',Shading='SetShadingQuality'}
local function scenario(mode,duplicate)
 local quality,commands={},{};local saved,scale=30,75;local cvars={['t.MaxFPS']=30,['r.ScreenPercentage']=75}
 local request={schema=1,id='synthetic-profile-check',mode=mode}
 local function reflected(fn)return setmetatable({},{__call=function(_,...)return fn(...)end,__tostring=function()return 'UFunction: synthetic' end})end
 local settings={IsValid=function()return true end,GetFullName=function()return 'GameUserSettings /Engine/Transient.Synthetic' end}
 for key,name in pairs(methods)do settings[name]=reflected(function(_,value)quality[key]=value;cvars['sg.'..key..'Quality']=value end)end
 settings.SetResolutionScaleValueEx=reflected(function(_,value)scale=value end)
 settings.SetFrameRateLimit=reflected(function(_,value)saved=value end)
 settings.GetFrameRateLimit=reflected(function()return saved end)
 settings.GetScreenResolution=reflected(function()return {X=1280,Y=720}end)
 for _,name in ipairs({'ApplyNonResolutionSettings','SaveSettings','SetScreenResolution','ApplyResolutionSettings','ConfirmVideoMode'})do settings[name]=reflected(function()end)end
 local pc={IsValid=function()return true end,GetFullName=function()return 'PalPlayerController /Engine/Transient.Synthetic' end,IsLocalController=function()return true end}
 local k={GetConsoleVariableFloatValue=function(_,name)return cvars[name]end,GetConsoleVariableIntValue=function(_,name)return cvars[name]end,ExecuteConsoleCommand=function(_,context,command,controller)assert(context==pc and controller==pc);commands[#commands+1]=command;local name,value=command:match('^(%S+) (%S+)$');cvars[name]=assert(tonumber(value))end}
 IsInGameThread=function()return true end
 FindAllOf=function(name)if name=='GameUserSettings'then return duplicate and {settings,settings}or {settings}end;assert(name=='PalPlayerController');return {pc}end
 StaticFindObject=function(name)assert(name=='/Script/Engine.Default__KismetSystemLibrary');return k end
 os.getenv=function(name)assert(name=='PALCRAFT_WINDOWS_ROOT');return 'Z:/synthetic' end
 dofile=function()return {decode=function()return request end,encode=function()return 'synthetic' end}end
 io.open=function(_,mode)return {read=function()return 'synthetic' end,write=function()end,close=function()end}end
 local ok,out=pcall(assert(loadfile(source)))
 if duplicate then assert(not ok and saved==30 and #commands==0);return end
 assert(ok,out);assert(out.complete and out.request_id==request.id and out.mode==mode)
 assert(saved==(mode=='night'and 15 or 60));assert(scale==(mode=='night'and 50 or 71));assert(cvars['t.MaxFPS']==saved and cvars['r.ScreenPercentage']==scale)
 assert(#commands==2);assert(quality.Effects==0);assert(settings.SetVisualEffectsQuality==nil)
end
scenario('day',false);scenario('night',false);scenario('day',true)
print('PASS day/night real-API shape, console priority and singleton preflight synthetic checks; no game operation')
