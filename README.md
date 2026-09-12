# TickKey

免费开源的本地 TOTP 验证器，MIT 许可。iPhone / iPad 使用 UIKit，Mac 使用原生 AppKit；共用验证码、存储及备份实现。无账户注册、广告、分析 SDK 或服务端。

- 自适应账户卡片，搜索、单击复制、编辑、删除与圆饼倒计时。
- 手机相机扫描标准 `otpauth://totp` 二维码，扫码后核对账户再保存。
- 每行一条 otpauth URI 的文本导入导出；密码加密 `.tickkey` 备份，跨平台通用，按内容识别格式。
- 完全一致的发行方、账户、规范化密钥、算法、位数、周期才去重；不同密钥保留。
- 兼容浏览器 Authenticator 插件导出的 otpauth 文本，包括有发行方但未填写账户名称的条目。
- 单个账户二维码或全部账户二维码翻页，供其他验证器连续扫码。
- 简体中文、繁体中文、English，语言和外观热切换。
- macOS Sparkle 自动更新集成，通过 `SPARKLE_ENABLED` 隔离；已配置仓库更新源和专用公钥，首次发行后可实际检查更新。

## 构建

需要 Xcode 26.0 或更高版本（MMKV 的 SPM 清单要求 Swift 6.2）和 XcodeGen。最低部署版本为 iOS 15 / macOS 12，并保留 Catalyst 支持；Mac 推荐使用原生 `TickKeyMac` scheme。

```sh
xcodegen generate
open TickKey.xcodeproj
# 在 Xcode 中选择自己的签名团队，再运行 TickKey 或 TickKeyMac。
```

依赖版本固定在 `project.yml`，解析锁文件一并入库：SnapKit 5.7.1、GRDB 6.29.3、MMKV 2.4.2、Sparkle 2.9.0。自己的 Swift 源码不依赖 SwiftUI。轻量设置使用 MMKV，账户使用 GRDB。

```sh
xcodebuild -project TickKey.xcodeproj -scheme TickKeyMac -destination 'platform=macOS' test
xcodebuild -project TickKey.xcodeproj -scheme TickKey -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

最低 iOS 版本已确认更新到 15.0，无需额外覆盖构建参数。验证范围见 [验证记录](Docs/Validation.md)。

首次构建前安装 SwiftFormat 和 SwiftLint，并通过 `Scripts/check_swift.sh`。详细约定及配置兼容说明见 [Swift 代码规范](Docs/CodingStyle.md)。

## 数据与安全

账户整体使用 AES-256-GCM 加密后存入 SQLite；随机设备密钥保存在 Keychain，不同步到 iCloud。账户数据库排除系统文件备份，换设备请主动导出加密备份。软件不会保存备份密码，遗失密码无法恢复。正常系统时钟是正确验证码的前提。

剪贴板验证码 30 秒后清理；Mac 仅在剪贴板没有被其他内容覆盖时清理。iOS 禁止验证码通过通用剪贴板跨设备传播；失去活动状态时遮挡界面。文本和二维码包含真实密钥，应像密码一样保管。

当前只支持标准 TOTP URI（SHA-1 / SHA-256 / SHA-512，6–8 位，1–300 秒），不支持 HOTP、Google Authenticator migration 批量私有协议或图片识别。任何无效行都会使整个导入失败，不会悄悄丢弃条目。批量导出始终包含所有账户，搜索不会改变导出范围。

`.tickkey` 是公开的专用格式，而非不可被其他软件实现的封闭协议。文件算法见 [备份格式](Docs/BackupFormat.md)。目前未经过独立安全审计。

## 发布

GitHub：<https://github.com/wangwanjie/TickKey>。反馈入口直接打开 Issues。

参考 [发布说明](Docs/Release.md) 核对签名和发布配置，再执行 `Scripts/build_dmg.sh`。默认公证 profile 为 `vanjay_mac_stapler`。iOS 可用 `Scripts/build_ipa.sh`，安装或分发仍受 Apple 的签名规则约束。

项目维护者发布 TickKey 时承诺所有功能免费；MIT 许可证允许第三方再分发或销售派生作品。
