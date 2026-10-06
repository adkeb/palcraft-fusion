local root=assert(os.getenv('PALCRAFT_WINDOWS_ROOT')):gsub('\\','/')
assert(PALCRAFT_EARLY_SCRIPT,'first script did not load during module attach')
assert(package.path:gsub('\\','/'):find(root,1,true),'initial package exe path lost UTF-8')
local file=assert(io.open(root..'/最初 加载.txt','rb'))
assert(file:read('*a')=='early script reached wide IO');file:close()
assert(os.remove(root..'/最初 加载.txt'))
local pending=root..'/文本 待完成.txt';local committed=root..'/文本 完成.txt'
file=assert(io.open(pending,'wb'));assert(file:write('UTF8 🌱\n'));assert(file:close())
local lines=io.lines(pending);assert(lines()=='UTF8 🌱');assert(lines()==nil)
assert(os.rename(pending,committed))
file=assert(io.open(committed,'rb'));assert(file:read('*a')=='UTF8 🌱\n');assert(file:close())
local source=root..'/额外 脚本.lua'
file=assert(io.open(source,'wb'));assert(file:write('return 11'));assert(file:close())
assert(dofile(source)==11)
local binary=root..'/字节码 文件.luac'
file=assert(io.open(binary,'wb'));assert(file:write(string.dump(function()return 17 end)));assert(file:close())
assert(dofile(binary)==17)
local required=root..'/模块 文件.lua'
file=assert(io.open(required,'wb'));assert(file:write('return {value=23}'));assert(file:close())
package.path=root..'/?.lua;'..package.path
assert(require('模块 文件').value==23)
assert(package.loadlib(root..'/模块 空格.dll','palcraft_unicode_module'))()
local command_file=root..'/命令 文件.txt'
file=assert(io.open(command_file,'wb'));assert(file:write('COMMAND_OK'));assert(file:close())
local pipe=assert(io.popen('cmd /d /c type "'..command_file:gsub('/','\\')..'"','r'))
assert(pipe:read('*a')=='COMMAND_OK');assert(pipe:close())
local ok,kind,code=os.execute('cmd /d /c type "'..command_file:gsub('/','\\')..'" > nul')
assert(ok and kind=='exit'and code==0)
local temp=os.tmpname();assert(type(temp)=='string'and utf8.len(temp))
local anonymous=assert(io.tmpfile());assert(anonymous:write('stream'));assert(anonymous:seek('set',0));assert(anonymous:read('*a')=='stream');assert(anonymous:close())
for _,path in ipairs{committed,source,binary,required,command_file}do assert(os.remove(path))end
