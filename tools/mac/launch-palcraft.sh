#!/bin/zsh
set -e
CX='/Users/PLAYER/Documents/Codex/2026-10-04/new-chat/work/apps/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine'
exec "$CX" --bottle PalCraftLab --debugmsg '-all' --dll 'dwmapi=n,b' --env 'SteamAppId=1623730' --workdir 'D:\PalworldServer-LAN\PalCraft-Client' 'D:\PalworldServer-LAN\PalCraft-Client\Palworld.exe' -windowed -ResX=1280 -ResY=720 -ForceRes -nosound -NoVSync '-UserDir=D:/PalworldServer-LAN/PalCraft-Client-User/' '-ExecCmds=t.MaxFPS 60'
