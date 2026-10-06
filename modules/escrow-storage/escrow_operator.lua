-- Explicit calls by the existing BridgeLab game-thread operator only.
-- Loading this file does not build, move, schedule or create a transaction.
local source=assert(debug.getinfo(1,'S').source):gsub('\\','/')
local dir=assert(source:match('^@(.*[/])'))
local M={}
local function guid(value,label)
 assert(type(value)=='string'and #value==36 and value:match('^[%x%-]+$'),label..' must be an actual GUID')
 return value:lower()
end
function M.run(action,args)
 assert(IsInGameThread(),'Existing server game thread required')
 assert(source:lower():find('@d:/palworldserver-lan/bridgelab/',1,true)==1,'Existing BridgeLab only')
 args=args or{};action=action or'survey'
 if action=='survey'then
  return dofile(dir..'escrow_lab_probe.lua').survey(dofile(dir..'readers.lua'),args.guild_id and guid(args.guild_id,'guild_id'))
 end
 assert(action=='preview'or action=='take_stock'or action=='submit'or action=='start_work'or action=='observe','Unknown existing paid-setup operation')
 local root=assert(os.getenv('PALCRAFT_EXCHANGE_ROOT'),'Existing trusted exchange root is missing')
 assert(root:gsub('\\','/'):gsub('/+$',''):lower()=='d:/palworldserver-lan/palcraft-dev/bridge/exchange','Use the existing shared Lab exchange root')
 local api=rawget(_G,'PalCraftEscrowSetup')
 if not api then
  api=dofile(dir..'escrow_setup.lua').new{
   json=dofile(dir..'json.lua'),readers=dofile(dir..'readers.lua'),root=root,
   durable_dll=dir..'PalCraftExchangeDurable-v3.dll',allow_build=true
  }
  _G.PalCraftEscrowSetup=api
 end
 if action=='preview'or action=='take_stock'then return api[action](guid(args.pal_uid,'pal_uid'))end
 return api[action](guid(args.setup_id,'setup_id'))
end
return M
