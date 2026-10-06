# CrossOver 普通游戏窗口启动候选

组件通过本机合法安装的 CrossOver 生成本安装的 Windows .lnk 与官方 Menu Helper app，保留原 job host、全部游戏参数和退出监督，然后走 cxmenu 正常启动路径。vendor 程序、游戏和个人配置不在公共包中。

发布清单须选择 launcher_crossover_native_menu 角色与 crossover_native_menu=windows-menu-helper-v1。runtime.py.patch 仅有三行接线，须合并到当前完整启动器；不要用旧 runtime 覆盖保存或重启功能。

十项定向源码检查及既有 profile 的只读计划检查通过，没有执行 Wine/cscript/cxmenu/lsregister 或启动另一游戏。公开 checker 用 PALCRAFT_CROSSOVER_APP 参数取得自己的合法安装。真实游戏 app 登记、CUA 绑定和物理 F5 仍需下一普通启动验收。
