#!/usr/bin/env bash
# 生成带 EdDSA 签名的 appcast 和本地校验值，不自动发布到 GitHub。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
if [[ $# -ne 2 ]]; then echo '用法: Scripts/prepare_release.sh <Sparkle bin 目录> <已公证 DMG>'; exit 1; fi
SPARKLE_BIN="$1"
DMG="$2"
VERSION="$(basename "$DMG" .dmg)"
VERSION="${VERSION#TickKey-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'DMG 名称必须为 TickKey-x.y.z.dmg' >&2; exit 1; }
[[ -x "$SPARKLE_BIN/generate_appcast" && -f "$DMG" ]] || { echo '找不到 Sparkle 工具或 DMG' >&2; exit 1; }
xcrun stapler validate "$DMG"
OUT="$ROOT/build/appcast"
mkdir -p "$OUT"
cp "$DMG" "$OUT/"
NOTES="$ROOT/Docs/ReleaseNotes-$VERSION.md"
if [[ -f "$NOTES" ]]; then
  cp "$NOTES" "$OUT/TickKey-$VERSION.md"
fi
# generate_appcast 从 Keychain 读取 Sparkle 私钥；切勿把私钥写入仓库。
"$SPARKLE_BIN/generate_appcast" --account cn.vanjay.TickKey.Sparkle --download-url-prefix "https://github.com/wangwanjie/TickKey/releases/download/v$VERSION/" "$OUT"
(cd "$OUT" && shasum -a 256 "$(basename "$DMG")" > SHA256SUMS)
echo "待发布文件: $OUT"
