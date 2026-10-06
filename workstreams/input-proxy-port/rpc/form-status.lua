assert(IsInGameThread(),'Operator status requires the existing game-thread RPC')
return assert(_G.PalCraftOperator,'Operator module is not enabled').form_status()
