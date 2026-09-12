# iOS 卡顿与二维码导出诊断

## 已确认的问题

用户提供的日志末尾是 `NSGenericException`：`UIImageView.width` 和 `UIStackView.width` 没有共同父视图。`QRViewController` 在 `addArrangedSubview` 之前激活了两者的约束，进入单账户二维码或批量二维码页面都会触发。现已调整为先加入视图层级，再建立约束，并增加实际加载页面、快速翻页、横竖屏尺寸的回归测试。

代码检查还发现以下主线程开销，已调整：

- `AccountsViewController.viewDidLayoutSubviews` 无条件让列表布局失效，改为仅宽度或字体尺寸变化时刷新。列表改为铺满父视图，由滚动视图自动处理安全区内边距，避开日志中搜索转场时安全区高度异常导致的约束冲突。
- 搜索逐次输入在主线程全表筛选，改为 Combine 120 ms 防抖及后台筛选，使用请求编号防止旧结果覆盖新结果。
- 倒计时原来每秒 30 次重复设置验证码文字、辅助功能文案和边框颜色，改为在需要时更新；打开覆盖页面时暂停列表倒计时刷新。
- 文件读取、明文编码和导出文件写入改为后台任务；导入文件流读取受备份大小上限约束。
- 文件和图片导入的去重、校验、整库加密与事务写入移至后台，写入成功后才更新主线程模型。去重使用结构化身份集合，避免逐条扫描不断增长的账户数组。后台导入期间拒绝交错账户写入，避免旧快照覆盖新状态。
- 二维码图片在后台生成，复用 `CIContext`，翻页后不展示过期任务的图片。

这些代码问题具有明确的性能风险，但现有日志没有卡顿时的主线程调用栈，不能断言每次卡住都由同一个问题造成。输入法、LaunchServices 和 UIKit 内部约束信息需要结合复测进一步判断。

## 真机复测与回传

### 第二轮日志的结论与新增采样

第二轮日志只有 1 个账户，`search.filter` 为 0～1 ms，初次 `accounts.reload` 为 7 ms，其余为 0～1 ms。四次主队列心跳恢复延迟约为 878 ms、10464 ms、1518 ms 和 3936 ms。

- 878 ms 出现在扫码的 FigCapture 日志附近：上一版仍在主线程枚举相机并创建输入，现改为专用队列完成整个会话配置。预览图层仍在主线程安装，连接方向调整也在会话队列完成。
- 10464 ms 出现在搜狗输入法候选词超时之后、`search.changed` 之前。说明这次等待不能归因于后台搜索筛选，具体是否卡在输入法、UIKit 或调试器仍需线程栈。搜索关闭拼写修正和内联预测，保留多语言输入。
- 二维码 `qr.render` 为 3939 ms，同时主队列心跳延迟约 3936 ms。仅凭接近的耗时不能证明 GPU 阻塞主线程：后台渲染等待、共享资源锁、进程整体暂停均可能造成这种现象。改用软件渲染并延迟到二维码页面转场完成后初始化，同时细分 `qr.filter.create`、`qr.filter.output`、`qr.bitmap.render` 日志。

新版 `main-thread-stall` 额外记录 `monitor-gap-ms`（后台监测队列两次检查的间隔，正常约 100 ms）。如果它也达到数秒，说明后台监测队列同样没有及时运行，可能涉及调试器暂停、系统调度或整机负载，不能把全部延迟算成某个主线程函数的执行时间。

**推荐自动抓栈：**在 Xcode 启动新版 Debug 应用，点暂停，在 LLDB 控制台执行下列一行，然后继续运行并复现：

```lldb
command script import /Users/VanJay/Documents/Work/Private/TickKey/Scripts/capture_hangs.py
```

控制台应显示已匹配的断点位置。脚本在后台监测发现停顿时抓取当下的符号栈（最多 32 个线程，优先保留主线程），输出 `[TickKeyHang]` 后自动继续。回传完整 `[TickKeyHang]` 块及前后 `[TickKeyPerf]` 日志即可；无须手动赶在短暂卡顿时暂停。

每次启用最多抓取 8 次，间隔至少 3 秒；需要继续采集时执行 `tickkey-hangs`。断点可在 Xcode 断点列表中按名称 `TickKeyHangCapture` 禁用或删除。脚本不读取函数参数、局部变量或输入内容，不执行目标进程内的求值表达式，也不更改全局 LLDB 配置。调试器采样本身会暂停进程，采样期间的延迟不应作为正常性能结果。

另请对比从手机桌面直接打开应用与连接 Xcode 调试时的表现；输入相关场景可临时切换系统键盘作对照。这两组结果用于区分应用、输入扩展和调试环境的影响。

### 手动日志与暂停抓栈

1. 在 Xcode 用 **Debug** 配置运行新代码，清空控制台，搜索 `TickKeyPerf`。
2. 分别复现搜索、打开分享菜单、文件/图片导入、加密/明文导出、二维码导出。保留操作前后完整的 `[TickKeyPerf]` 行，并说明点了哪个入口以及是否使用第三方键盘。
3. 前台主队列心跳延迟至少约 750 ms 时，后台会输出 `main-thread-stall`；恢复后输出 `main-thread-recovered` 和本次延迟。手动断点暂停、调试器停顿也可能触发，不应计入正常运行结果。
4. 如果长时间不能恢复，在 Xcode 点 **Debug → Pause**，在调试控制台执行 `thread backtrace all`，提供调用栈及暂停前的性能日志。无需打印变量值或账户数据。

| 日志阶段 | 说明 |
| --- | --- |
| `import.menu` / `export.menu` / `photos.open` / `qr.open` | 用户操作已到达对应入口 |
| `search.changed` / `search.filter` | 搜索输入回调与后台筛选；不记录关键词 |
| `search.focus.requested` / `search.focus.began` / `editor.focus` | 搜索和编辑框开始接收输入的边界 |
| `keyboard.willShow` / `keyboard.didShow` / `keyboard.willHide` / `keyboard.didHide` | 键盘转场通知；不读取输入内容 |
| `accounts.reload` | 主线程提交列表刷新，不包含后续 UIKit 布局的全部时间 |
| `import.picker.create` / `export.picker.create` | 系统文件选择器初始化耗时 |
| `transfer.progress.requested` / `transfer.progress.visible` | 进度界面请求展示与展示完成 |
| `import.file.read` / `import.decode` | 文件读取与备份解码 |
| `photos.decode` | 单张图片二维码识别 |
| `import.merge` / `import.persist` | 批量去重和加密事务写入 |
| `export.prepare` | 备份编码/加密与临时文件写入 |
| `qr.render` / `qr.displayed` | 二维码后台生成及图片更新 |
| `qr.visible` / `qr.filter.create` / `qr.filter.output` / `qr.bitmap.render` | 二维码页面展示、滤镜初始化、生成及立即栅格化 |
| `camera.visible` / `camera.configure` / `camera.input.create` | 扫码页面可见、后台会话配置和输入创建 |
| `camera.preview.attach` / `camera.start` / `camera.stop` | 主线程预览绑定与后台启停 |
| `vault.persist` | 单账户编辑等同步存储耗时 |

`begin` / `end` 使用同一随机 `id` 配对；`ms` 为毫秒，`main=false` 表示在后台执行。计时阶段抛错也会输出 `end`，因此 `end` 本身不代表业务成功。心跳用于判断响应延迟，不能替代调用栈采样。

日志仅在 Debug 启用，内容限静态阶段名、随机关联编号、数量、线程标记和耗时，不记录账户名称、密钥、密码、验证码、文件路径、备份内容或搜索内容。
