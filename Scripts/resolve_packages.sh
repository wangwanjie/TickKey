#!/usr/bin/env bash
# 使用 Xcode 界面的默认缓存解析锁定版本，避免终端与 IDE 各用一份依赖。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/network.sh"

if [[ $# -gt 0 ]]; then
  echo '用法: bash Scripts/resolve_packages.sh' >&2
  exit 1
fi

bash "$SCRIPT_DIR/install_pods.sh" --deployment

# 两个平台共用同一个包依赖图，Mac scheme 包含 Sparkle 等全部依赖。
# 不指定 clonedSourcePackagesDirPath 或 derivedDataPath，让 Xcode 界面直接复用解析结果。
xcodebuild \
  -resolvePackageDependencies \
  -workspace "$ROOT/TickKey.xcworkspace" \
  -scheme TickKeyMac \
  -onlyUsePackageVersionsFromResolvedFile \
  -skipPackageUpdates

echo '依赖解析完成。重新打开 TickKey.xcworkspace 后即可构建。'
