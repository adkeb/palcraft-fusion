local root=assert(os.getenv('PALCRAFT_WINDOWS_ROOT')):gsub('\\','/')
assert(root:find('玩家',1,true)and root:find('🌱',1,true),'environment was not UTF-8 before first script')
local f=assert(io.open(root..'/最初 加载.txt','wb'))
assert(f:write('early script reached wide IO'));assert(f:close())
_G.PALCRAFT_EARLY_SCRIPT=true
