此候选修复 Mac CrossOver 单机启动时的 Windows 快捷方式创建，并采用玩家本机安装的原生 Menu Helper 启动路径。它保持现有世界、原 HOST 参数和监督流程；没有包含 vendor 程序或游戏资源。

原 WSH 调用返回 0 但没有文件。原生 COM 能保存链接，但实机 ACP1252 下中文目标被读成问号。修正后的唯一创建器通过 `GetShortPathNameW` 获取现有文件的 ASCII 别名，核对原目标、别名和加载后目标的真实卷号与文件索引，再验证原参数、工作目录和描述。它没有建立别名、复制文件、更改 ACP 或执行目标。

修正创建器已在隔离环境实际保存并读回 1968 字节的链接，返回 0，四字段及同文件校验均通过。原生应用注册、游戏启动、实际窗口与物理 F5 尚未通过验收。这份源码检查和文件验证不代表完整玩法已通过。

两个受管理的文件槽位为 `launcher/crossover_menu_helper.py` 与 `bin/PalCraftShellLink-v2.exe`。保持 requirement `windows-menu-helper-v1`，不需要改动其他运行模块。

编译自己的文件工具：

```sh
python3 native-short-target-v2/build_shelllink_writer.py \
  --zig /自己的/zig-0.15.2 --out /新的目录/PalCraftShellLink-v2.exe
```

构建器以 nice19 使用一个编译进程，不部署或执行产物。`probes/shelllink_path_probe_readonly.cpp` 是只加载链接、检查路径与文件信息的诊断源码，不调用 Save、Resolve 或目标启动。

源码检查使用本机合法 CrossOver 的模板；请设置 `PALCRAFT_CROSSOVER_APP` 后运行 `python3 verify_failure_boundary.py`。公共检查器只将原作者固定路径换成这个参数；生产源码和文件工具保持原冻结字节。它使用合成输入和 runner，不能代替实机验证。

[Windows Shell Links](https://learn.microsoft.com/en-us/windows/win32/shell/links)、[GetShortPathNameW](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-getshortpathnamew)、[GetFileInformationByHandle](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-getfileinformationbyhandle) 提供 API 依据；[Wine 源码](https://raw.githubusercontent.com/wine-mirror/wine/master/dlls/shell32/shelllink.c) 只作上游参考，实机诊断才证明当前瓶中的行为。
