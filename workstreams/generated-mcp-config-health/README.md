此修正解决正常安装后启动检查拒绝 `ai-transport.json` 的问题。安装器按玩家的本机配置生成并登记了正确文件，原检查却将它与发布包通用模板的摘要比较。

现在仅对原生成器明确生成的 `ai-transport.json`、`mc-transport.json` 重新计算本 profile 与当前 manifest 的字节摘要，并要求生成器摘要、受管理记录和实际文件三者相同。示例模板、代码、DLL、JAR、HUD 与其他资源仍按原 manifest 精确校验。

实机拒绝已定位：生成器、受管理记录与实际配置摘要相同，发布模板摘要不同。修正后的定向临时 fixture 覆盖正常配置、模板回写、登记值更改、生成 extra 被修改和代码文件变化，均得到预期结果。修正还未在实际游戏启动中验收。

`check.py` 参数为 `--base`（原安装工具源）、`--fixture`（原 SingleplayerBootstrapTests 文件）与 `--mod`（合法现有独立 mod JAR）。它只操作 fixture 的临时根，不启动游戏。旧版本与补丁保留以供追溯；实际用户配置、存档和身份未发布。
