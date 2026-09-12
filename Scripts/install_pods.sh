#!/usr/bin/env bash
# 生成工程、修复依赖和打包共用同一 CocoaPods 安装入口。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/network.sh"

if ! command -v pod >/dev/null 2>&1; then
  echo 'error: 缺少 CocoaPods，请先安装后重新执行。' >&2
  exit 1
fi

pod install --project-directory="$ROOT" "$@"
