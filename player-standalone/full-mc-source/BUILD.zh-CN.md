本候选补完整 MC 基础生产源构建，供 root 审查公开。原 `build_mc_10_6.py` 仍是两源增量 over10.5；它不能替代这个完整生产源入口。

`source/` 是 exact10.6 的 100 份生产 Java 与三份源资源。94 Java 与当前公开10.7相同，另外六份采用原真实10.6冻结源，必要 SHA 全列于 recipe。没有旧测试身份、wrapper JAR、作者目录、token、游戏 SDK 或 class 二进制。LICENSE 随源保留。

本机已完成 default 和 `-g` 两次完整100-source Javac，每次真正新生成168个生产class；classpath没有旧project mod JAR，仅有合法MC/Fabric及Java-WebSocket。历史基包并非统一debug策略，因此公开recipe明示选择155个fresh-g、10个fresh-default，以及3个fresh-g HostState内部record的LineNumberTable源行减1。那3类只差原10.5残留源行43/44/45和新10.6源行44/45/46；规范化严格仅改u16源行，不改Code、descriptor或其他字节，随后逐class SHA验收。不会从旧JAR回填class。

`packaged-resources/` 中的 mod/mixins 是既有自有源资源；MANIFEST保留历史Gradle/增量发布元数据，用于字节重现，不声称当前执行了那些Gradle版本。ZIP顺序与每entry元数据公开在recipe，所有168class都来自上述完整新编译。

真实装包已得到 exact10.6：

```text
401a4ae60eb428d106aba448d42ba3a74b28eb7d06624184bc247228b58a89af
554989 bytes
```

从本次完整源码基包，衔接此前已真正fresh六源生成的11class，用现公开10.7 builder的纯Python装包路径，得到 exact F35 /552361B。这最后一步没有再运行JVM，也没有使用旧冻结11class目录。

新用户从本候选目录调用完整source模式，路径均为用户自供的合法工具/依赖：

```sh
nice -n 19 python3 build_mc_full_10_6.py \
  --jdk-home '/自己的JDK/Contents/Home' \
  --runtime-root '/自己的MC缓存根' \
  --fabric-api '/自己的合法依赖/fabric-api-0.161.0+26.3.jar' \
  --websocket-jar '/自己的合法依赖/Java-WebSocket-1.6.0.jar' \
  --output '/新的输出/base10.6.jar'
```

JDK25.0.4.1和所有dependency逐SHA验证。runtime相对布局沿用现10.7 recipe，Fabric分包取自用户API发行JAR。Java-WebSocket从用户独立合法Maven依赖取得，完整source入口不要求project base JAR。小ASM声明helper先顺序执行，随后两个全100-source profile各javac512MiB、一CPU、SerialGC；不启动游戏/Gradle/网络/GUI。辅助overlay不会进入runtime。输出已有时拒绝覆盖。

若已有自己刚完成、全部raw SHA对应recipe的两套完整source class目录，可用 `--fresh-default-classes` 和 `--fresh-g-classes` 只核对装包；仍需要 `--websocket-jar`。回执会明确 `full_source_compiled_this_call=false`，不能把这个模式称为当前调用重新编译。

此前私有harness完整Javac与packing模式证据保留。新增一次直接CLI验证已真实运行本公共builder的完整compile模式：全新临时目录、helper128/128和两个100-source javac512 job顺序完成，4个JVM全部rc0，full_source_compiled_this_call=true，得到exact401a；随后衔接已真实fresh六源11class，再次得到exactF35。没有传已有profile目录、旧project class复用为0，builder/recipe无需修正。实际命令与路径日志私有冻结，公开summary不含个人路径。

这闭合当前MC生产源构建部分。没有执行全118-member Gradle测试，也未进行游戏、candidate9、SourceChecker、GUI、RPC或后端/world/Saved操作。整个D04和原42范围仍待完整实际验收；此候选由root统一发表，实际依赖由合法用户自供。
