# TickKey

免费开源的本地 TOTP 验证器，MIT 许可。iPhone / iPad 使用 UIKit，Mac 使用原生 AppKit；共用验证码、存储及备份实现。无账户注册、广告、分析 SDK 或服务端。

- 自适应账户卡片，搜索、单击复制、编辑、删除与圆饼倒计时。
- iOS 和 Mac 均支持多选、全选和反选，批量操作仅限删除；选择范围为当前搜索结果。超过 5 项或全选删除时，提醒不可恢复及提前备份，并要求两次确认。
- 手机相机扫描标准 `otpauth://totp` 与 Google Authenticator 迁移二维码；图片导入同样支持这两种格式。
- 文本文件支持逐行导入 otpauth URI 或 Google Authenticator 迁移链接；支持 otpauth 文本导出和跨平台密码加密 `.tickkey` 备份。
- 完全一致的发行方、账户、规范化密钥、算法、位数、周期才去重；不同密钥保留。
- 兼容浏览器 Authenticator 插件导出的 otpauth 文本，包括有发行方但未填写账户名称的条目。
- 单个账户二维码、全部账户二维码和分页的 Google Authenticator 迁移二维码导出。
- 简体中文、繁体中文、English，语言和外观热切换。
- macOS Sparkle 自动更新集成，通过 `SPARKLE_ENABLED` 隔离；已配置仓库更新源和专用公钥，首次发行后可实际检查更新。

## 构建

需要 Xcode 26.0 或更高版本（MMKV 的 SPM 清单要求 Swift 6.2）、XcodeGen 和 CocoaPods。最低部署版本为 iOS 15 / macOS 12，并保留 Catalyst 支持；Mac 推荐使用原生 `TickKeyMac` scheme。

```sh
xcodegen generate
open TickKey.xcworkspace
# 在 Xcode 中选择自己的签名团队，再运行 TickKey 或 TickKeyMac。
```

SPM 依赖版本固定在 `project.yml`，workspace 下的解析锁文件一并入库：SnapKit 5.7.1、GRDB 6.29.3、MMKV 2.4.2、Sparkle 2.9.0。Debug UI 调试使用 CocoaPods 的 LookinServer，提交固定在 `Podfile` 和 `Podfile.lock`。`xcodegen generate` 会自动执行 `Scripts/install_pods.sh`，重新生成工程后可直接打开 workspace。自己的 Swift 源码不依赖 SwiftUI。轻量设置使用 MMKV，账户使用 GRDB。

```sh
xcodebuild -workspace TickKey.xcworkspace -scheme TickKeyMac -destination 'platform=macOS' test
xcodebuild -workspace TickKey.xcworkspace -scheme TickKey -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

最低 iOS 版本已确认更新到 15.0，无需额外覆盖构建参数。验证范围见 [验证记录](Docs/Validation.md)。

如果 Xcode 提示 `Missing package product`，先关闭本工程窗口，再在项目目录执行：

```sh
bash Scripts/resolve_packages.sh
open TickKey.xcworkspace
```

脚本优先使用本机 `127.0.0.1:7890` 代理，按 `Package.resolved` 解析依赖，并写入 Xcode 界面使用的默认缓存。不要在这条修复命令中追加 `-clonedSourcePackagesDirPath build/SourcePackages`，否则只会修好另一份命令行缓存。

首次构建前安装 SwiftFormat 和 SwiftLint，并通过 `Scripts/check_swift.sh`。详细约定及配置兼容说明见 [Swift 代码规范](Docs/CodingStyle.md)。

## LookInside UI 调试

从 `TickKey.xcworkspace` 以 Debug 运行 `TickKey` 或 `TickKeyMac`，LookinServer 会自动启动，再使用 LookInside 连接应用。Release 链接中排除 LookinServer；Mac 的本地监听权限仅配置在 `Mac-Debug.entitlements`。

默认从 GitHub 的维护者 fork 获取固定提交。需要联调本地 LookInside 源码时，可使用与 ZiYa 相同的 checkout：

```sh
kUse_Local_Lookin=1 bash Scripts/install_pods.sh
# 默认路径为 ../LookInsideWorkspace/LookInside，可通过 LOOKIN_LOCAL_PATH 覆盖。
# 切回固定远端版本：
bash Scripts/install_pods.sh
```

本地模式会改变 `Podfile.lock` 的来源；切回远端后再提交锁文件。MCP 调试时使用 `LOOKIN_MCP_TARGET_BUNDLE_ID=cn.vanjay.TickKey`（iOS）或 `cn.vanjay.TickKey.mac`（原生 Mac），并先断开 LookInside GUI 与同一应用的连接。

构建、连接及 Release 隔离结果见 [接入验证](Docs/LookInside.md)。

## 数据与安全

账户整体使用 AES-256-GCM 加密后存入 SQLite；随机设备密钥保存在 Keychain，不同步到 iCloud。账户数据库排除系统文件备份，换设备请主动导出加密备份。软件不会保存备份密码，遗失密码无法恢复。正常系统时钟是正确验证码的前提。

剪贴板验证码 30 秒后清理；Mac 仅在剪贴板没有被其他内容覆盖时清理。iOS 禁止验证码通过通用剪贴板跨设备传播；失去活动状态时遮挡界面。文本和二维码包含真实密钥，应像密码一样保管。

支持标准 TOTP URI（SHA-1 / SHA-256 / SHA-512，6–8 位，1–300 秒）和 Google Authenticator migration 批量二维码；不支持 HOTP。Google 格式仅能导出 30 秒周期的 6 位或 8 位账户，遇到无法表示的账户会明确报错。文本文件中的任何无效行都会使整个导入失败。批量导出始终包含所有账户，搜索不会改变导出范围。

`.tickkey` 是公开的专用格式，而非不可被其他软件实现的封闭协议。文件算法见 [备份格式](Docs/BackupFormat.md)。目前未经过独立安全审计。

## 发布

GitHub：<https://github.com/wangwanjie/TickKey>。反馈入口直接打开 Issues。

参考 [发布说明](Docs/Release.md) 核对签名和发布配置，再执行 `Scripts/build_dmg.sh`。默认公证 profile 为 `vanjay_mac_stapler`。iOS 可用 `Scripts/build_ipa.sh`，安装或分发仍受 Apple 的签名规则约束。

项目维护者发布 TickKey 时承诺所有功能免费；MIT 许可证允许第三方再分发或销售派生作品。
