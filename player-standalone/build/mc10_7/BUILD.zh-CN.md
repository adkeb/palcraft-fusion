# 当前 MC10.7 F35 的重建

目标是 `0.2.0-integration.10.7-respawn`，552361 字节，SHA256：

```text
f35ebc90cfa2f77c81b7f9f02d7ea721bffc21166bc63ff36159825bd0170b55
```

历史 `build_mc_10_6.py` 只复现 10.6。当前入口为 `launcher/build_mc_10_7.py`；两者应并存。

本目录保存冻结的 118 个公开源码成员、相对 recipe 和编译辅助源。历史本机 raw freeze 有 119 项；公开 kit 移除了 javac 路径不使用的 `gradle/wrapper/gradle-wrapper.jar`，并将三个非生产编译成员中的本机身份字段替换为公开占位。六个实际编译源和 11 个生产 class 的 pin 保持原样。运行 mod 继承合法 exact10.6 base 的 173 个 ZIP entry/168 个 class，只替换 11 个真正生产 class 和 `fabric.mod.json` 的版本。118 是公开源码成员数量，不是运行 JAR 的 class 数量。

## 输入由使用者提供

- 自己的合法 exact10.6 mod，SHA256 `401a4ae60eb428d106aba448d42ba3a74b28eb7d06624184bc247228b58a89af`。推荐先按 [完整 100 生产源构建指南](../../full-mc-source/BUILD.zh-CN.md) 从源码生成基础包。此目录不附作者安装目录或 base 缓存。
- 官方 JDK25.0.4.1；原记录为 Oracle `25.0.4.1+1-LTS-5`、Mac arm64。builder 读取 JDK `release` 文件确认版本，11 个 class 的最终字节 pin 仍是验收条件。
- 自己通过正常合法 Minecraft 安装取得的 26.3 runtime 与其依赖。`--runtime-root` 是使用者任意目录；按 recipe 的 `runtime` 相对布局放置 `client/versions/26.3/26.3.jar` 和 `client/libraries/...`。
- 官方 Fabric API `0.161.0+26.3` 发行 JAR，SHA256 `86f16178a3cecc887a85a4cfe9a79d92fa7341d8f39b5951a4d6ad800ab657a6`。builder 从其 `META-INF/jars` 提取 recipe 所列的原分包依赖。合法 Java-WebSocket 依赖从 exact base 自己的 `META-INF/jars/Java-WebSocket-1.6.0.jar` 取得。
- Python3。原装包版本与 zlib 版本记在 recipe；不同压缩实现可能产生不同 ZIP 字节，因此最终整包 SHA 必须匹配。

recipe 列出 133 个原 classpath 依赖的相对来源与 SHA。工具不下载游戏、依赖或账户资料，不启动 Minecraft、GUI、网络或 Gradle；使用者保留其自己的输入和工具链目录。公开源码不提供 Gradle wrapper 依赖 JAR；本入口直接使用指定 JDK 的 javac。

## 从六份改动源码生成生产 class

从 `player-standalone` 目录运行，所有路径都是使用者自己的路径：

```sh
nice -n 19 python3 launcher/build_mc_10_7.py \
  --base-mod '/自己的合法模组/exact10.6.jar' \
  --jdk-home '/自己的 JDK/Contents/Home' \
  --runtime-root '/自己的 Minecraft 软件目录' \
  --fabric-api '/自己的依赖/fabric-api-0.161.0+26.3.jar' \
  --output '/新的输出/10.7-respawn.jar'
```

可先附加 `--dry-run` 查看模式、输入 pin 与输出路径；dry-run 不运行编译器，也不声称依赖或编译已经验证。

源码冻结先按 recipe 的允许名单及实际计数逐文件验证 118 成员，实际 javac 只编译这次六个改动源，继承 exact10.6 中其余既有实现。三项小 JVM 步骤顺序执行：编译辅助源、生成 compile-only 接口声明、编译六个生产源。最大 heap 为128/128/512MiB，并发为1，不编译或执行游戏本体。

`compile-support/FabricCompileInterfaces.java` 的用途必须保留可见：当前标准 vanilla JAR 在 javac 阶段没有 Fabric networking 实际混入的 `PacketContextProvider` 接口。辅助源只给 `ServerCommonPacketListenerImpl` 和 `ServerLoginPacketListenerImpl` 增加编译期接口声明，原方法字节码保持；实际运行依赖官方 Fabric 原 mixin 提供接口实现。辅助 class、两份 Minecraft 声明与临时 overlay JAR全部留在临时编译目录，禁止进入运行 mod。

生产输出只能是 recipe 中 11 个 class，逐 SHA 校验后才允许装包。每个 entry 都替换 base 已有成员；不会把目录中的多余 class、编译 stub 或商业游戏库装入 mod。ZIP 沿用 exact base 的原顺序与元数据，输出已有时拒绝覆盖。成功写出相邻 `.build.json`；字节不符时留下 receipt 并报错，不自动升格为当前发布物。

## 只核对装包

如果使用者已有自己合法生成、逐 pin 对应的 11 个生产 class，可执行短装包检查：

```sh
nice -n 19 python3 launcher/build_mc_10_7.py \
  --base-mod '/自己的合法模组/exact10.6.jar' \
  --compiled-production '/自己的输出/仅11个生产class' \
  --output '/新的输出/10.7-assembly-check.jar'
```

此模式不启动 JVM。它能证明生产 class 与 ZIP 装包字节一致，不能证明该使用者的新环境曾从源码编译成功。

初次公开修订仅以原冻结 11 个 class 执行 Python 装包，重现 F35/552361B。随后已真实运行同一公开入口的六源编译模式：三个 JVM 步骤均退出 0，重新生成 11 个生产 class，未使用此前 class 目录，产物仍为相同 F35/552361B。见 [后续六源编译回执](../../../docs/evidence/MC10.7-fresh-six-source-compile.json)。原装包 receipt 的历史范围保留，不能将其自身解释为重新编译。

完整 100 生产源基础包也已由 [公开整合入口](../../full-mc-source/BUILD.zh-CN.md) 在本机新编译并重现 exact10.6，衔接上述六源结果得到相同 10.7 产物。其他用户全新环境、完整项目 Gradle 构建或测试、完整 Mixin 与游戏验收仍未完成。三个净化成员中的开发身份和历史测试断言采用公开占位，不作为生产编译输入。

源码与相对 recipe 可公开。官方 JDK、Minecraft runtime/商业库、Fabric 输入、用户凭据、Saved、作者缓存与编译 overlay 不随本源码交付发布。
