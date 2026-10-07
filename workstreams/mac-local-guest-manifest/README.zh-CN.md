# Mac 本地 guest 公开清单

原工具只生成 Windows guest 路径。新增显式 `--platform mac-local`，通过实际签发的 credential 读取玩家身份、服务器会话、过期时间和玩家权限；Mac role 文件只提供既有路径、UUID、端口、FPS 和原参数的配置见证。

保留原 Windows 默认输出与 allocations 行为。Mac 增加 POSIX backend/data 路径、实际 frame file 和本机共享端口、文件的冲突检查。工具只准备 JSON，不能启动进程或签发权限。凭据检查不是签名验证；实际登录仍由原 MC authority 校验。

需要 Python 3.10+。在原 SessionEnrollment 正常签发当前 credential 后运行 `source/multiplayer/prepare_guest.py --help` 查看参数。必须提供自己的 credential、output、allocations、Mac backend/data/launch 根路径、分配的 MC/HUD 端口以及实际 FPS。输出交给原 `enrollment-profile` 和后续同步流程。

12 项有界 synthetic 检查包括 Windows 原行为相等、Mac 元数据和路径/端口/身份冲突、原 credentials 消费函数的 schema 匹配。这不代表完整 validate_profile、实际注册、登录、同步或游戏验收通过。此公开目录不提供真实 credential、role 启动描述、个人配置或运行存档。
