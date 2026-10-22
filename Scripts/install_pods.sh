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

# CocoaPods 要求 UTF-8 终端；部分 Ruby / ActiveSupport 组合需预先加载 Logger，否则启动即报 NameError。
export LANG="${LANG:-en_US.UTF-8}"
export RUBYOPT="-rlogger ${RUBYOPT:-}"
pod install --project-directory="$ROOT" "$@"
