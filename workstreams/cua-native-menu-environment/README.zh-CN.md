# CrossOver 原生菜单环境传递修正

Windows 菜单的真实 Command 只调用官方生成的菜单脚本。额外的 `CrossOverHelperCommand` 字段没有被当前原生 Menu Helper 使用，因此原来的 `--dll dwmapi=n,b` 没有进入实际启动。游戏使用 builtin dwmapi 时，UE4SS 和 AI Mod 没有加载。

此增量通过官方 `CX_ENV` 传递 `SteamAppId=1623730` 与 `WINEDLLOVERRIDES=dwmapi=n,b`，并设置 `CX_DEBUGMSG=-all`。未知的已有环境赋值继续保留。真实 Menu Helper、原 Host 参数、Windows 快捷方式四字段和工作目录都保持原值。没有修改 vendor 文件、bottle 配置或 readiness 标志。

源码检查共 16 项通过，包括读取用户已安装 CrossOver 的纯环境解析函数，验证其先删除 DLL override、再应用 CX_ENV 的行为。没有启动 Wine、游戏或 native helper。这不能替代实际 DLL 加载、世界加载或物理 F5 验收。

`source/launcher/crossover_menu_helper.py` 是候选生产源码，基线和 patch 用于复核。需要 Python 3.10+、Perl 和用户合法安装的 CrossOver；在 macOS 上可运行：

```sh
PALCRAFT_CROSSOVER_APP=/Applications/CrossOver.app python3 verify_native_environment.py
```

检查读取自己的 CrossOver 安装，不打包其实现。此目录不包含存档、账号、凭据、实际会话或 vendor 二进制。
