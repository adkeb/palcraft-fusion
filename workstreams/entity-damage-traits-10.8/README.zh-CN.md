MC10.8 damage traits 实验源

本目录只含两份 Java、三份 damage_type/tag 资源、两份配对服务器 Lua、补丁与源头收据。不含 Minecraft/Fabric/JDK 二进制、SDK dump、私有路径或玩家身份。

用 mc10_8-build-recipe.json 指定的合法 F35 Jar、原 133 依赖和 Oracle JDK 25.0.4.1，以 nice 19、单 CPU、SerialGC、heap 512 MiB 只编译列出的两源。classpath 为 F35 后接固定依赖；sourcepath 必须为空；不需要 Fabric 接口 overlay。输出目录只允许清单中的六个 class。保留 F35 的其它条目和 ZIP 元数据，替换这些生产 class 与 fabric.mod.json 的 version，再按 recipe 添加一新 class、三份资源和源头 JSON。

新 Jar 必须与本目录 server/entities.lua 和 server/entity_protocol.lua 成对更新，不能当 Lua-only 更新，不能同时安装两个 passthrough mod。F35 应保留备份。当前 candidate9 bootstrap 的原 slot 不由此目录改写。

这次仅验证源头编译和 Jar 装配。真实 OnDamage 上游 hook 覆盖、正常生存的完整 X05/X06 与原 42 范围仍待实机玩法验收；无 living 来源的 TNT/crystal nullable 引擎伤害仍未实现或证明。
