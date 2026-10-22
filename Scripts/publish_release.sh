#!/usr/bin/env bash
# 显式执行本脚本才创建 Release；默认只创建草稿，传入 --publish 才公开发布。
# 上传 build/appcast 中的按架构 DMG、全部 appcast、发布说明与校验值，可附带 IPA。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/network.sh"
PUBLISH=false
IPA=''
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --publish) PUBLISH=true; shift ;;
    --ipa) IPA="${2:?缺少 IPA 路径}"; shift 2 ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done
[[ ${#POSITIONAL[@]} -eq 2 ]] || {
  echo '用法: Scripts/publish_release.sh <v版本号> <发布说明文件> [--ipa 路径] [--publish]'
  exit 1
}
TAG="${POSITIONAL[0]}"
NOTES="${POSITIONAL[1]}"
VERSION="${TAG#v}"
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ && -f "$NOTES" ]] || { echo '版本号或发布说明无效' >&2; exit 1; }
git -C "$ROOT" rev-parse --verify "refs/tags/$TAG" >/dev/null
ASSETS=("$ROOT/build/appcast/"TickKey-"$VERSION"-*.dmg "$ROOT/build/appcast/"appcast*.xml \
  "$ROOT/build/appcast/TickKey-$VERSION.md" "$ROOT/build/appcast/SHA256SUMS")
for asset in "${ASSETS[@]}"; do
  [[ -f "$asset" ]] || { echo "缺少发布文件: $asset" >&2; exit 1; }
done
if [[ -n "$IPA" ]]; then
  [[ -f "$IPA" ]] || { echo "找不到 IPA: $IPA" >&2; exit 1; }
  ASSETS+=("$IPA")
fi
gh release create "$TAG" --repo wangwanjie/TickKey --verify-tag --draft --title "TickKey $TAG" \
  --notes-file "$NOTES" "${ASSETS[@]}"
if [[ "$PUBLISH" == true ]]; then
  gh release edit "$TAG" --repo wangwanjie/TickKey --draft=false --latest
fi
