local function context()for _,a in ipairs(FindAllOf('GameStateBase')or{})do if live(a)then return a end end;error('No game state')end
return context
