这个独立备选用 Python 标准库编码真正的 Windows `.lnk` 字节。它只替代原 helper 的 ShellLink 文件创建步骤，不创建 app、注册 Menu、启动 Wine/cscript/cxmenu 或执行 Target。主 WSH 诊断无需等待此备选。

格式依据 Microsoft 官方 [MS-SHLLINK 总结构](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-shllink/747629b3-b5be-452a-8101-b9a2ec49978c)。编码包含以下结构：

- [ShellLinkHeader](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-shllink/c3376b21-0931-45e4-b2fc-a48ac0e60d15)：固定 76 字节、标准 CLSID、普通窗口模式、零保留字段；FILETIMEs 明确未设置。
- [LinkFlags](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-shllink/ae350202-3ba9-4790-9e9e-98935f4ee5af)：`0xB6` 对应 LinkInfo、description、workdir、arguments、Unicode；没有虚构 PIDL、机器 GUID 或 tracking 数据。
- [LinkInfo](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-shllink/6813269d-0cc8-4be2-933f-e96e8e3412dc)：`0x24` 头，ANSI 和完整 UTF-16LE 目标路径，空 suffix；各 offset 都从对应结构开始计数。
- [VolumeID](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-shllink/b7b3eea7-dbff-4275-bd58-83ba3f12d87a)：Unicode label 与其真实长度/offset，所有卷属性来自调用者。
- [StringData](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-shllink/17b69472-0f34-4bcf-b290-eccdb8de224b)：UTF-16LE 的 description、工作目录、完整原参数，count 不包含终止 NUL。arguments 使用规范明确的 260 限制例外，以 16 位长度字段编码。
- [ExtraData](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-shllink/c41e062d-f764-4f13-bd4f-ea812ab9a4d1)：只有四字节 zero terminal，没有额外属性或凭据载荷。

UTF-16 count 按 Windows 的 16 位 code unit 计算，补充字符占两个单元，依据 [Windows 字符串说明](https://learn.microsoft.com/en-us/windows/desktop/learnwin32/working-with-strings)。`encode_menu_spec()` 使用与原 `shortcut_source()` 相同的标准库 `subprocess.list2cmdline()`，该调用只格式化文本，不创建进程；参数引用规则见 [Microsoft C 参数规则](https://learn.microsoft.com/en-us/cpp/c-language/parsing-c-command-line-arguments?view=msvc-170)。传入 raw argument string 的 `encode_shell_link()` 完全保留调用者的参数内容。

将来若评估合入，只在原 `guard(spec)`、bottle/namespace 检查和目录准备完成后调用：

```python
from launcher.windows_shell_link import encode_menu_spec, write_owned_link

data = encode_menu_spec(spec, metadata)
write_owned_link(spec['link'].parent, spec['link'].name, data)
```

`metadata` 必须明确给出 `ansi_encoding`、`volume_drive_type`、`volume_serial_number`、`volume_label`、`file_attributes`、`target_file_size`。不能将 fixture 值代入实机。现阶段未确定实机 Z: 卷属性和 Windows ANSI code page；源码不猜这些值，也不声称观察到它们。若 ANSI shadow 无法表示目标，严格拒绝，不静默替换中文为问号。完整 Unicode 目标和参数一直保留。只支持绝对 drive-letter 本地路径，不声称支持 UNC、Darwin 或任意 PIDL target。

raw host token 只来自调用者原 argv/arguments，无默认 token、作者身份或路径。生成 `.lnk` 按原 private namespace 写为 0600；CLI 只输出 bytes/hash 和 `source_only` 标记，不输出参数。调用者保持原 session/control/stop/ownership guards，随后正常的 vendor `Type=windows` 注册与启动流程仍归其所有。

以下命令仅在此独立目录生成和检查已公开占位的合成文件：

```sh
nice -n 19 python3 -B test_shell_link.py
nice -n 19 python3 -B windows_shell_link.py \
  --input fixtures/unicode-input.json --owned-directory fixtures \
  --name unicode-synthetic.lnk
nice -n 19 python3 -B inspect_shell_link.py \
  fixtures/unicode-synthetic.lnk --ansi-encoding cp936
```

本次这些检查已通过；reference helper 只调用纯 `shortcut_source()` 做引号对照，未执行它产生的 VBS。合成文件不含真实 session token，不可用于真实启动。原已安装 vendor `CXMenuWindows.pm::get_command()` 的源码确认 Windows menu 将 `.lnk` 交给既有 `wine --start`；未调用这个过程，也未运行 vendor parser。因此 `source_only=true`、`vendor_engine_verified=false`、`target_executed=false`。实际 vendor 解析及新的游戏启动只由唯一 runtime owner 在已授权的 setup-file-only/正常 boot 边界验证；这份结构检查不能替代它们。
