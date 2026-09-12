# Swift 代码规范

所有自有 Swift 文件统一受根目录 `.swiftformat` 和 `.swiftlint.yml` 约束，包括应用、共享代码、测试和图标生成脚本。第三方依赖及构建产物排除在扫描范围之外。

```sh
brew install swiftformat swiftlint
swiftformat . --config .swiftformat
Scripts/check_swift.sh
```

`check_swift.sh` 同时执行 SwiftFormat `--lint` 和 SwiftLint `--strict`。任何格式偏差、警告或错误都会使检查失败；缺少工具同样失败。iOS 和 Mac 的 Xcode 构建均调用此脚本。

`Configuration/SwiftLintInputs.xcfilelist` 精确声明脚本沙盒可读取的文件，保留 `ENABLE_USER_SCRIPT_SANDBOXING=YES`。新增 Swift 文件后运行 `xcodegen generate`，其 preGenCommand 会更新此清单。单独更新时执行 `python3 Scripts/generate_swift_inputs.py`。

编译器分析需要实际编译日志：

```sh
swiftlint analyze --config .swiftlint.yml --strict --compiler-log-path /path/to/xcodebuild.log
```

分析时应分别使用 macOS 与 iOS 的构建日志，以覆盖条件编译中的两套界面和导入。

## 配置兼容性调整

基于 SwiftFormat 0.63.0 和 SwiftLint 0.65.1，保留原配置的规则和阈值，并修正以下兼容问题：

- SwiftLint 的 Sources / Tests 目录映射到实际的七个源码目录。
- YAML 中 `file_length.error` 写为数值 `1000`，避免 `1_000` 被当作字符串而回退默认规则。
- `unused_import` 仅保留在 `analyzer_rules`，避免重复配置；旧版不存在的 `unneeded_parentheses_in_condition` 对应检查由默认 `control_statement` 承担。
- 关闭 SwiftFormat 自动删除 `internal` 的默认转换，以满足 SwiftLint 的显式顶层访问控制要求。
- 关闭 SwiftFormat 默认的多行语句大括号换行转换，以满足 SwiftLint 的 `opening_brace` 同行规则。
- 启用 guard 分支换行、链式调用换行、switch 分支换行和每行单属性声明；保留两空格缩进、120 列、禁用分号等原有设置。

未添加行级规则豁免、违规基线或降低检查阈值。

## 注释和方法留白

- 用简体中文说明类型职责、业务方法的输入边界和失败行为。
- 在加密参数校验、认证数据绑定、事务写入、剪贴板清理、文件安全作用域等关键位置说明原因。
- 方法内按校验、数据准备、执行和界面反馈分段，独立步骤之间留空行。
- UI 元素初始化、布局约束、事件绑定分组书写；卡片和绘图组件独立成文件。
- 注释不重复显而易见的语句，不把机械地增加注释数量作为代码质量目标。
