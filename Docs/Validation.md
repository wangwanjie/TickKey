# 验证记录

验证日期：2026-09-12。工具：Xcode 27.0、SwiftFormat 0.63.0、SwiftLint 0.65.1。

## iOS 紧凑账户列表

- 移除独立卡片外框和卡片间距，改为原生自适应高度列表；默认字号实测每行约 83pt，原布局为 160pt 卡片加 16pt 间距。
- 发行方和账户合为一行，处理重复发行方前缀、大小写、空白和中英文冒号；保留邮箱、相似名称和原始存储字段。
- 左滑展示编辑、二维码和删除操作，关闭完整滑动直接执行；删除继续使用确认框。
- 复制反馈改为居中毛玻璃 HUD，2 秒后自动消失；提示不参与列表布局、不拦截触摸，连续复制刷新计时且不叠加。
- HUD 的 iOS 26.5 UI 回归通过：出现和消失前后账户行 frame 完全一致，连续点击仅存在一个提示，随后自动移除。已检查截图；结果为 `build/Validation/Copy-HUD-Verified.xcresult`，截图为 `build/Validation/Copy-HUD-Screenshots/copy-hud.png`。
- 21 项单元测试通过，包含名称去重边界用例。UI 回归增加行高、合并名称、左滑编辑/二维码、取消删除和确认删除后的空态验证。
- XCTest 可能把 UITableView 复用缓存中的旧 cell 留在层级中；删除验证以实际空态及截图为准。
- iPhone 16 Pro / iOS 18.5 与 iPhone 17 Pro / iOS 26.5 的完整账户 UI 流程均通过，包含复制、搜索、左滑编辑/二维码、文件导出和删除确认。结果位于 `build/Validation/Compact-Accounts-Final.xcresult`，无运行时警告。
- 已检查普通行、左滑菜单和删除后空态截图；预览位于 `build/Validation/Compact-Accounts-Final-Screenshots/compact-accounts-preview.png`。严格 SwiftFormat / SwiftLint 和 `git diff --check` 通过。

## iOS 卡顿与二维码崩溃修复

第二轮真机日志跟进：

- 相机设备枚举、输入创建、会话配置与连接方向修改统一移至专用队列；退出页面时作废迟到的权限和配置回调。
- 二维码采用软件渲染，并显式立即生成位图；初次生成推迟到页面转场完成后。搜索补充输入焦点日志并关闭拼写修正、内联预测。
- 更新主队列心跳诊断，记录后台监测队列的检查间隔，以识别监测线程也长时间未获调度的情况。
- iOS 22 项回归通过（`build/Validation/Hangs-Final.xcresult`）。显式关闭二维码延迟渲染后，5 项二维码/图片回归再次通过（`build/Validation/Hangs-QR.xcresult`）；macOS 共享代码构建通过。
- LLDB 脚本 `Scripts/capture_hangs.py` 在本机阻塞探针中成功输出主线程的 semaphore 等待调用链并自动继续，重复启用只保留一个命名断点。在实际 iOS Debug 产物中精确匹配 1 个 `reportStall` 入口，不匹配日志插值闭包。
- 35 个自有 Swift 文件通过严格格式和 lint 检查。相机硬件、搜狗输入法、真机 Core Image 初始化和调试器影响仍需用新版自动抓栈工具复测，模拟器通过不能证明这些真机停顿已经全部消失。

- iPhone 16 Pro / iOS 18.5 模拟器：20 项单元测试及 2 项 UI 测试全部通过，xcresult 未报告运行时警告。
- 新增实际加载二维码页面、快速前后翻页后图像解码及横竖屏尺寸布局测试，覆盖原先仅测试编码器而遗漏的视图层级崩溃。
- 新增后台批量导入测试：500 个新账户及重复数据去重、导入期间拒绝交错写入、成功后磁盘与内存一致、无效记录整批失败及失败后重试。
- UI 回归覆盖添加、复制、搜索、编辑、批量/单账户二维码、明文/加密导出进入系统保存面板及关闭、设置抽屉和图片选择器取消。测试使用虚构数据，文件面板未执行保存。
- macOS：15 项共享核心测试通过；测试使用本地临时签名并关闭测试构建的 Hardened Runtime，工程发布配置未修改。
- 34 个自有 Swift 文件通过 SwiftFormat 和 SwiftLint 严格检查，0 违规；`git diff --check` 通过。Xcode 27 自带 XCTest 的最低运行版本链接提示及未使用 AppIntents 的元数据提示仍存在，无新增 Swift 并发诊断。
- 调试日志确认 `search.filter`、`qr.render`、`import.merge`、`import.persist`、`export.prepare` 在后台执行。真机上的偶发停顿、第三方键盘及文件提供器延迟仍需复测，操作说明见 [iOS 卡顿诊断](iOSPerformanceDiagnostics.md)。
- 本次结果：`build/Validation/Performance-Final.xcresult`（iOS）、`build/Validation/Performance-Mac-3.xcresult`（macOS）。

## 1.0.1 导入与代码规范修复

- 复现：浏览器 Authenticator 文本备份包含 50 条记录，其中 10 条账户名为空，旧版在第 1 行停止导入。
- 修复后，在本机内存中验证全部 50 条记录成功解析、生成验证码、文本往返及加密备份往返，空账户名原样保留。真实备份没有加入仓库、测试资源或构建产物。
- macOS：13 项核心测试通过，包含新增的空账户名导入、无效数据拒绝、去重与持久化回归测试。
- iOS：14 项核心/二维码测试通过，iPhone 16 Pro / iOS 18.5 的添加、复制、搜索和编辑 UI 流程通过。
- 30 个自有 Swift 文件通过 SwiftFormat `--lint` 和 SwiftLint `--strict`，0 违规；两个 Xcode target 均执行同一检查脚本。
- 移除强制解包、强制类型转换和隐式解包；拆分复杂备份解码和过长布局方法，卡片与绘图组件独立成文件。
- 补充类型职责、业务方法和关键安全边界的简体中文注释，方法内部按步骤分段留白。
- 最低 iOS 版本已按作者确认更新为 15.0，测试不再使用临时覆盖参数；macOS 最低版本仍为 12.0。
- Shell 语法、工程生成配置、资源引用及 git diff 空白检查通过。

## 编译器分析的限制

额外执行了配置中的 `unused_declaration` 和 `unused_import` 编译器分析：iOS 的 20 个编译单元达到 0 诊断。当前 SwiftLint / Xcode 27 组合对 macOS 的 `@main ApplicationMain.main()` 报告“未引用”；该方法由 Swift 生成的系统入口调用，不是可删除的死代码。分析共享测试文件时，还在非当前平台的条件导入分支报告模块不存在，而相同文件的两平台实际编译与测试均成功。

没有为这些诊断添加行级豁免、规则基线或公开无用 API 来避开检查。不能把这部分编译器分析报告为完整零诊断；常规严格 lint、格式检查和实际构建/测试均独立执行。

iOS 场景入口已在 AppDelegate 中直接绑定 `SceneDelegate.self`，增强程序化初始化的类型关系，并避免仅靠 plist 类名字符串识别场景。

## 已有功能验证

- RFC 6238 三种算法共 18 个标准样例全部匹配。
- 独立 Python cryptography 实现生成的备份可由 Swift 解密；错误密码、篡改、未知版本和无效文本行均被拒绝。
- 数据库重开、错误设备密钥、完整字段去重、UUID 冲突及编辑持久化测试通过。
- 1.0.0 时已检查 iPad Pro 11-inch (M4) / iOS 18.5 的宽屏布局及相同 UI 流程。
- 原生 Mac 实际界面采用 accessibility / 截图检查，未接入 LookInside：添加、复制、文件内容识别与加密导入、二维码、设置和语言热切换已验证。
- Mac 分发包包含 x86_64 / arm64，使用 Developer ID 签名及 `vanjay_mac_stapler` 公证；更新包的 Ed25519 签名可用项目公钥独立验证。

相机扫码仍需 iPhone 真机确认。尚未公开 GitHub Release，因此没有验证 Sparkle 从已安装旧版本到新版本的完整下载、替换与重启过程。项目尚未经过独立安全审计。
