-- PALCRAFT_WINDOWS_ROOT is a logical Windows path, including under CrossOver.
-- Lua strings contain UTF-8. The paired LuaRaw patch supplies Windows Unicode IO.
local M={contract='windows-root-v1',legacy_root='D:/PalworldServer-LAN'}
function M.normalize(value)
 assert(type(value)=='string','Windows runtime root required')
 local path=value:gsub('\\','/'):gsub('/+$','')
 assert(path:match('^%a:/[^/]'),'Expected absolute Windows runtime root')
 for part in(path:sub(4)..'/'):gmatch('(.-)/')do
  local device=(part:match('^([^.]+)')or''):upper()
  assert(device~='CON'and device~='PRN'and device~='AUX'and device~='NUL'and
   not device:match('^COM[1-9]$')and not device:match('^LPT[1-9]$'),'Reserved Windows path component')
  assert(part~=''and part~='.'and part~='..'and not part:find('[%c<>:"|?*]')and
   part:sub(-1)~=' 'and part:sub(-1)~='.','Invalid Windows path component')
 end
 return path:sub(1,1):upper()..path:sub(2)
end
local configured=os.getenv('PALCRAFT_WINDOWS_ROOT')
M.root=M.normalize(configured==nil and M.legacy_root or configured)
function M.join(relative)
 assert(type(relative)=='string'and relative~=''and not relative:find('[:\\%c]')and
  relative:sub(1,1)~='/','Expected installation-relative Windows path')
 for part in(relative..'/'):gmatch('(.-)/')do
  assert(part~=''and part~='.'and part~='..','Runtime path escapes installation')
 end
 return M.root..'/'..relative
end
M.bridge=M.join('PalCraft-Dev/bridge')..'/'
M.journal=M.join('BridgeLab/rpc')..'/'
function M.role(directory)
 local path=directory:gsub('\\','/'):lower()
 local client=(M.root..'/PalCraft-Client/'):lower();local server=(M.root..'/BridgeLab/'):lower()
 if path:sub(1,#client)==client then return'client'end
 if path:sub(1,#server)==server then return'server'end
end
function M.assert_role(directory,role)
 assert(M.role(directory)==role,'Use the configured '..role..' installation')
end
return M
