# 本轮验证记录

验证日期：2026-09-12。开发工具：Xcode 27.0。

- 原生 macOS Debug 编译成功；10 项 XCTest 通过。
- iOS 模拟器编译成功；11 项 XCTest 通过，包含 Core Image 反解生成二维码。
- iPhone 16 Pro / iOS 18.5：添加账户、单击复制、搜索过滤、打开编辑并核对账户的 UI 测试通过。
- iPad Pro 11-inch (M4) / iOS 18.5：同一 UI 流程通过，宽屏布局截图已导出检查。
- RFC 6238 三种算法共 18 个标准样例全部匹配。
- 使用独立 Python cryptography 实现生成的加密备份，可由 Swift 解密；错误密码、篡改、未知版本和无效文本行被拒绝。
- 数据库重开、错误设备密钥、完整字段去重、导入 UUID 冲突、编辑去重的持久化测试通过。
- 原生 Mac 实际界面检查采用 macOS accessibility / 截图，未接入 LookInside：添加、复制、加密文件内容识别与导入、二维码、设置和语言热切换已检查。
- Mac Release 包包含 x86_64 / arm64，Developer ID 签名验证通过；Apple 公证 Accepted，DMG staple / validate 通过。
- Sparkle appcast 的文件长度和 Ed25519 签名已用独立 Python 实现和配置中的公钥验证。
- Shell 语法、plist、图标资源引用和 git diff 空白检查通过。
- 保留并同步了工作期间新增的 Code Lint 构建阶段及格式配置；本机没有 SwiftLint / SwiftFormat，构建按该脚本的既有行为跳过这两项检查并提示警告。当前 SwiftLint 的 included 仍是作者配置的 Sources / Tests，正式启用前需映射到实际源码目录。

## 版本与尚未验证的范围

初始工程的最低 iOS 14 / macOS 12 设置仍然保留。由于本机 Xcode 27 要求 iOS 15 起，iOS 编译和测试命令临时添加了 `IPHONEOS_DEPLOYMENT_TARGET=15.0`，没有据此宣称验证过 iOS 14 设备。正式提升最低版本仍待项目作者确认。

相机扫码需 iPhone 真机确认。首次公开 Release 尚未发布，所以未验证 Sparkle 从已安装旧版本到新版本的完整下载、替换和重启过程。未进行独立安全审计。测试工具的 AppIntents 元数据提示和 XCTest SDK 最低系统版本链接提示仍存在，应用源码没有 MainActor 隔离警告。
