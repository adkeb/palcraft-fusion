return ExecuteInGameThreadWithDelay(1000,function()
 local ok,e=pcall(function()assert(type(DumpUSMAP)=='function','DumpUSMAP unavailable');DumpUSMAP(false)end)
 local f=assert(io.open('D:/PalworldServer-LAN/BridgeLab/rpc/mappings-dump-status.txt','wb'));f:write(ok and 'completed' or tostring(e));f:close()
end)
