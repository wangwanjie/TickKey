# 发布 TickKey

## 一次性配置

1. Xcode 签名团队设为自己的 Apple Developer 团队。直接分发 Mac 需要 Developer ID Application 证书。
2. 当前发布机器已创建专用 EdDSA 密钥，Keychain account 为 `cn.vanjay.TickKey.Sparkle`。私钥留在 Keychain，不写入项目或 GitHub。新维护者首次分叉发行可用 `bin/generate_keys --account <自己的账户名>` 创建自己的密钥。
3. 公钥已填入 `Configuration/Release.xcconfig` 的 `SPARKLE_PUBLIC_KEY`。后续更新必须用同一私钥签名。
4. `SPARKLE_FEED_URL` 已设置为 `https:/$()/github.com/wangwanjie/TickKey/releases/latest/download/appcast.xml`。xcconfig 中的 `$()` 防止双斜杠被当作注释。
5. 确认 `xcrun notarytool history --keychain-profile vanjay_mac_stapler` 能访问公证历史。

仓库、更新源和公钥已配置；首次发行包含 appcast.xml 的公开 Release 后，更新源才会实际可用。Debug 构建不自动发起检查，手动检查仍可用。`SPARKLE_ENABLED` 只在 Mac target 中开启。Mac App Store 发行时须移除该宏、Sparkle 链接依赖和对应 mach-lookup entitlement，并使用商店签名配置。

## 打包与草稿 Release

```sh
Scripts/build_dmg.sh
# 可用 PRETTY_DMG_SCRIPT 指定 create_pretty_dmg.sh；没有该工具时用标准 DMG 布局。
Scripts/prepare_release.sh /path/to/Sparkle/bin build/release/<时间>/TickKey-1.0.0.dmg
Scripts/publish_release.sh v1.0.0 Docs/ReleaseNotes-1.0.0.md
```

先更新版本号和构建号，测试并提交源码，再创建并推送对应 Git tag。`publish_release.sh` 只创建草稿，检查 DMG、签名 appcast、版本和说明后，在 GitHub 上公开发行。脚本不会创建或覆盖 Git tag。发布前请自行编写对应 ReleaseNotes 文件。

`prepare_release.sh` 要求 DMG 已通过 staple 校验；Sparkle 自动更新包的签名与 Apple 公证相互独立，两者都必须成功。首次安装后，发布一个构建号更高的版本，验证检查更新、下载、验证签名、替换与重启的完整流程。

iOS 的 `Scripts/build_ipa.sh` 支持 `release-testing`、`debugging`、`app-store-connect`。免费软件不意味着可绕过 Apple 的签名和分发限制。

## 发布前实机检查

- iPhone 相机授权允许/拒绝、扫码、旋转、进入后台与回前台。
- iOS 导出加密文件 → Mac 导入，Mac 导出 → iOS 导入；核对账户和验证码。
- 用外部验证器扫描单个及翻页二维码，检查 SHA-1 / SHA-256 / SHA-512 兼容性。
- 用真实 Developer ID 签名验证 Keychain 持久化、公证及 Sparkle 更新。
