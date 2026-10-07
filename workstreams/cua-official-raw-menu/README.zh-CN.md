# 官方 raw 菜单启动

实际测试显示原生 Menu Helper 收到环境参数，但游戏进程仍缺 DLL override。Helper 生成的 Wine task 使用 CrossOver 主应用提供的环境；只改 Helper 的环境不足以加载 Mod。

这个增量改用 CrossOver 自带 `cxmenu` 支持的 raw 菜单与 Command，显式保留 `--dll dwmapi=n,b`、SteamAppId、原工作目录、等待子进程和原 Windows 快捷方式。原生 Menu Helper、COM 创建器、快捷方式四字段及原 Host 参数保持原值，只有本安装的菜单项通过官方工具更新。

18 项必要源码检查通过，包括官方参数解析、含空格和中文的原工作目录，以及官方注册表中唯一的菜单 Command 读回。没有在检查时启动 Wine 或游戏，没有改 vendor 文件或全局 CrossOver 环境。实际冷启动后的 Mod、世界、F5 和完整玩法仍待验收。
