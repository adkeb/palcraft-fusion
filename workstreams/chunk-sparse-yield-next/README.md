# 稀疏区段调度候选

两份源文件须成对使用，基线与哈希见 MANIFEST.json。该候选尚未通过实际游戏中的停滞修复验收。

几何生成只在非空方块处暂停，调度器在每个 tile 完成后暂停；默认空 tile 每次恢复最多查询 64 个格子。原 2ms/128 步限制、碰撞和模型事务、旧版本取消以及全部就绪与 ACK 门槛保留。原 proof 最多报告四个待处理区段的真实任务状态，这些字段不授予就绪。

已有 11 项稀疏调度和 8 项状态证明检查采用合成数据、适配器和时钟。两方块样本的调度步数由 143 降为 19，不代表实际帧耗时或当前运行问题已经解决。公开测试仅将 JSON 模块路径改为参数：

```sh
lua workstreams/chunk-sparse-yield-next/sparse_yield_test.lua workstreams/chunk-sparse-yield-next palcraft/client/json.lua
lua workstreams/chunk-sparse-yield-next/pending_progress_test.lua workstreams/chunk-sparse-yield-next workstreams/chunk-sparse-yield-next/baseline palcraft/client/json.lua
```
