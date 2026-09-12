#!/usr/bin/env bash
# 显式执行本脚本才创建草稿 Release，默认不会公开发布。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/network.sh"
[[ $# -eq 2 ]] || { echo '用法: Scripts/publish_release.sh <v版本号> <发布说明文件>'; exit 1; }
TAG="$1"
NOTES="$2"
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ && -f "$NOTES" ]] || { echo '版本号或发布说明无效' >&2; exit 1; }
git -C "$ROOT" rev-parse --verify "refs/tags/$TAG" >/dev/null
gh release create "$TAG" --repo wangwanjie/TickKey --verify-tag --draft --title "TickKey $TAG" \
  --notes-file "$NOTES" "$ROOT/build/appcast/"*.dmg "$ROOT/build/appcast/appcast.xml" "$ROOT/build/appcast/SHA256SUMS"
