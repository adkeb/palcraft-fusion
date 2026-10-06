#!/usr/bin/env python3
"""Generate reviewable owner patches; never edits entrypoints or deploys anything."""
import difflib
import hashlib
import json
from pathlib import Path

PALCRAFT = Path(__file__).resolve().parents[2]
OUT = PALCRAFT / 'runtime/patches'


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise ValueError('Entrypoint changed; inspect this hook before generating it: ' + old[:100])
    return text.replace(old, new, 1)


def client(source):
    source = replace_once(source, "local form=dofile(dir..'form.lua');_G.PalCraftForm=form\n", """local form=dofile(dir..'form.lua');_G.PalCraftForm=form
local runtime_config={}
local runtime_file=open('runtime-config.json','rb')
if runtime_file then runtime_config=J.decode(runtime_file:read('*a'));runtime_file:close()end
local features=dofile(dir..'features.lua').new{json=J,bridge_root=ROOT,origin=O,identity=runtime_config.identity,
 entities_enabled=runtime_config.entities_enabled~=false,travel_enabled=false,fluid_enabled=false}
_G.PalCraftClientFeatures=features
""")
    source = replace_once(source, "_G.PalCraftReloadCollisions=function()\n", "_G.PalCraftReloadCollisions=function()\n features:reset('collision_replay',{context_alive=false})\n")
    source = replace_once(source, "local function reset(reason)\n", "local function reset(reason)\n features:reset(reason,{context_alive=false})\n")
    source = replace_once(source, " local before=form.active\n", " features:tick(now,{pc=pc,identity=identity,collisions=collisions,input=input})\n local before=form.active\n")
    source = replace_once(source, "enabled=enabled,grounded=grounded,form=form.status()})", "enabled=enabled,grounded=grounded,form=form.status(),features=features:status()})")
    return source


def server(source):
    anchor = "local function exchange_api()if not exchange then exchange=dofile(dir..'palcraft-exchange.lua')end;return exchange end\n"
    source = replace_once(source, anchor, anchor + """local SHARED='D:/PalworldServer-LAN/PalCraft-Dev/bridge/'
local features,next_runtime_status,next_control_tick
local clock_context,clock_lib
local function runtime_time_ms()
 if not live(clock_context)then
  clock_context=nil
  for _,g in ipairs(objects('PalGameStateInGame'))do
   if g:HasAuthority()then assert(not clock_context,'Ambiguous authority clock');clock_context=g end
  end
 end
 clock_lib=clock_lib or StaticFindObject('/Script/Engine.Default__GameplayStatics')
 return live(clock_context)and clock_lib:GetRealTimeSeconds(clock_context)*1000 or os.time()*1000
end
local function feature_api()
 if not features then
  local cfg=exists(SHARED..'runtime-config.json')and read(SHARED..'runtime-config.json')or{}
  local origin=exists(SHARED..'world-origin.json')and read(SHARED..'world-origin.json')or nil
  features=dofile(dir..'features.lua').new{json=J,readers=R,bridge_root=SHARED,origin=origin,
   companion=function()return palcraft end,exchange_factory=exchange_api,
   entities_enabled=cfg.entities_enabled~=false,exchange_enabled=false,travel_enabled=false,fluid_enabled=false}
  _G.PalCraftServerFeatures=features
 end
 return features
end
""")
    source = replace_once(source, " local p=req.params or {};local method=req.method\n", " local p=req.params or {};local method=req.method\n local handled,result=feature_api():dispatch(method,p,req);if handled then return result end\n")
    source = replace_once(source, " elseif method=='palcraft_exchange'then p.id=req.id;return exchange_api().handle(p)\n", "")
    start = source.index("tick=function()\n") + len("tick=function()\n")
    exchange_tick = source.index(" local exchange_ok,exchange_error=pcall(function()exchange_api().tick()end)\n", start)
    control = source[start:exchange_tick]
    tail = source.index(" return ExecuteInGameThreadWithDelay(500,tick)\n", exchange_tick)
    source = source[:start] + " local ms=runtime_time_ms()\n if not next_control_tick or ms>=next_control_tick then\n  next_control_tick=ms+500\n" + ''.join(' ' + line for line in control.splitlines(True)) + " end\n feature_api():tick(ms)\n if not next_runtime_status or ms>=next_runtime_status then\n  next_runtime_status=ms+1000;write(ROOT..'palcraft-features-status.json',feature_api():status())\n end\n" + source[tail:]
    return replace_once(source, " return ExecuteInGameThreadWithDelay(500,tick)\n", " return ExecuteInGameThreadWithDelay(250,tick)\n")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    records = []
    for relative, transform in [('client/main.lua', client), ('server/bridge-main.lua', server)]:
        path = PALCRAFT / relative
        before = path.read_text()
        after = transform(before)
        name = relative.replace('/', '.').replace('.lua', '.features.patch')
        patch = ''.join(difflib.unified_diff(before.splitlines(True), after.splitlines(True), fromfile='a/' + relative, tofile='b/' + relative))
        (OUT / name).write_text(patch)
        (OUT / (name + '.result.lua')).write_text(after)
        records.append({'entrypoint': relative, 'source_sha256': hashlib.sha256(before.encode()).hexdigest(),
                        'patch': 'runtime/patches/' + name, 'result_sha256': hashlib.sha256(after.encode()).hexdigest(),
                        'applied': False, 'deployed': False})
    (OUT / 'hooks.json').write_text(json.dumps(records, indent=2) + '\n')
    print(json.dumps({'generated': records, 'entrypoints_modified': False}))


if __name__ == '__main__':
    main()
