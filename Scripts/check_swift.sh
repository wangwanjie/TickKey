#!/usr/bin/env bash
# 两个平台使用同一组严格检查；缺少工具或出现警告时使构建失败。
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"
for tool in swiftformat swiftlint; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "error: 缺少 $tool，请先执行 brew install swiftformat swiftlint" >&2
    exit 1
  fi
done
SWIFT_FILES=()
while IFS= read -r entry; do
  case "$entry" in
    *.swift) SWIFT_FILES+=("$ROOT/${entry#'$(SRCROOT)/'}") ;;
  esac
done < Configuration/SwiftLintInputs.xcfilelist
swiftformat "${SWIFT_FILES[@]}" --config .swiftformat --lint --cache ignore
swiftlint lint --strict --no-cache --config .swiftlint.yml "${SWIFT_FILES[@]}"
