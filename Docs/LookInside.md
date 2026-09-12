# LookInside 接入验证

验证日期：2026-09-12。环境：Xcode 27.0（27A266a）、macOS 27.0、CocoaPods 1.16.2。

## 接入方式

- `TickKey` 与 `TickKeyMac` 使用静态 CocoaPods `LookinServer`，仅 Debug 链接。
- 使用维护者 GitHub fork 的固定提交 `026e36f9b51202aac51e82c213c1cc4f86fc844a`，与本机 LookInside checkout 一致。`Server` subspec 包含 Base、Core 和 Shared。
- 通过 Objective-C `+load` 自动启动；应用业务代码无需手动初始化。
- Mac Debug entitlement 增加 `com.apple.security.network.server`，Release 使用原有 entitlement。
- XcodeGen 的生成后脚本自动安装 Pods；IPA/DMG 脚本先执行 `pod install --deployment`，再通过 workspace 归档。

## 构建与运行

| 验证项 | 结果 |
| --- | --- |
| iOS Simulator Debug 构建 | 通过，iPhone 17 Pro / iOS 26.5 |
| 原生 macOS Debug 构建及开发签名 | 通过，arm64 |
| Mac Catalyst Debug 构建 | 通过，arm64 |
| iOS Release 无签名归档 | 通过 |
| macOS Release 无签名归档 | 通过，arm64 / x86_64 |
| Debug 二进制符号检查 | 两端均包含 `LKS_ConnectionManager` |
| Release 二进制与包内文件检查 | 两端均无 LookinServer 类符号及文件 |
| CocoaPods 锁文件部署模式、Ruby/Shell/entitlement 语法检查 | 通过 |

使用本机 `lookinside-mcp`，逐一设置 `LOOKIN_MCP_TARGET_BUNDLE_ID` 后调用 `current_screen`，两次调用均成功。验证期间 LookInside GUI 没有占用目标连接。

| 应用 | 监听端口 | 根节点 | 层级节点数 |
| --- | --- | --- | --- |
| `cn.vanjay.TickKey` | 47164 | `UIWindowScene` | 246 |
| `cn.vanjay.TickKey.mac` | 47170 | `NSWindow` | 844 |

服务返回的 `hierarchyDepth` 字段实际统计节点数，表中按节点数记录。验证仅覆盖调试接入和归档隔离；签名 IPA 导出、DMG 制作与公证沿用现有发布流程，本次未执行。LookinServer 上游源码在 Xcode 27 下仍有废弃 API 和跨平台空目标文件警告，构建通过。
