#!/usr/bin/env bash
# 参考 ZiYa 的归档、公证、钉合流程；按架构分别归档，生成 Apple 芯片（arm64）与 Intel（x86_64）两个 DMG。
# 每个架构的安装包使用各自的 Sparkle 更新源，自动更新始终下载与本机架构一致的版本。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/network.sh"
PROFILE=vanjay_mac_stapler
NOTARIZE=true
ARCHES=(arm64 x86_64)
TEAM=X6B6C6U6QV
SIGN_IDENTITY='Developer ID Application: Wan Jie Wang (X6B6C6U6QV)'
FEED_PREFIX='https://github.com/wangwanjie/TickKey/releases/latest/download'
PRETTY_DMG="${PRETTY_DMG_SCRIPT:-$HOME/Documents/Career/Github/quick_shell/develop/app/create_pretty_dmg.sh}"
usage() {
  echo '用法: Scripts/build_dmg.sh [--arch arm64|x86_64|all] [--keychain-profile PROFILE] [--no-notarize]'
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --arch)
      case "${2:?缺少架构}" in
        arm64|x86_64) ARCHES=("$2") ;;
        all) ARCHES=(arm64 x86_64) ;;
        *) echo "不支持的架构: $2" >&2; exit 1 ;;
      esac
      shift 2 ;;
    --keychain-profile) PROFILE="${2:?缺少 profile 名称}"; shift 2 ;;
    --no-notarize) NOTARIZE=false; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "未知参数: $1" >&2; usage >&2; exit 1 ;;
  esac
done
bash "$SCRIPT_DIR/install_pods.sh" --deployment
OUT="$ROOT/build/release/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>method</key><string>developer-id</string><key>signingStyle</key><string>automatic</string><key>teamID</key><string>$TEAM</string></dict></plist>
PLIST

# 归档并导出单一架构的应用，检查可执行文件只包含目标架构，最后生成、签名并公证 DMG。
build_arch() {
  local arch="$1"
  local work="$OUT/$arch"
  mkdir -p "$work"
  xcodebuild -workspace "$ROOT/TickKey.xcworkspace" -scheme TickKeyMac -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$work/TickKey.xcarchive" \
    -derivedDataPath "$ROOT/build/ReleaseDerivedData-$arch" -clonedSourcePackagesDirPath "$ROOT/build/SourcePackages" \
    ARCHS="$arch" ONLY_ACTIVE_ARCH=NO SPARKLE_FEED_URL="$FEED_PREFIX/appcast-$arch.xml" \
    DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Manual 'CODE_SIGN_IDENTITY=Developer ID Application' archive
  xcodebuild -exportArchive -archivePath "$work/TickKey.xcarchive" -exportPath "$work/export" \
    -exportOptionsPlist "$OUT/ExportOptions.plist"
  local app="$work/export/TickKey.app"
  codesign --verify --deep --strict --verbose=2 "$app"

  local built
  built="$(lipo -archs "$app/Contents/MacOS/TickKey")"
  if [[ "$built" != "$arch" ]]; then
    echo "主程序架构为 $built，预期仅包含 $arch" >&2
    exit 1
  fi
  local feed
  feed="$(/usr/libexec/PlistBuddy -c 'Print SUFeedURL' "$app/Contents/Info.plist")"
  if [[ "$feed" != "$FEED_PREFIX/appcast-$arch.xml" ]]; then
    echo "更新源不匹配: $feed" >&2
    exit 1
  fi

  local version name dmg
  version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")"
  name="TickKey-$version-$arch"
  dmg="$OUT/$name.dmg"
  if [[ -x "$PRETTY_DMG" ]]; then
    "$PRETTY_DMG" --app-path "$app" --dmg-name "$name" --output-dir "$OUT"
  else
    local staging="$work/dmg-content"
    mkdir -p "$staging"
    ditto "$app" "$staging/TickKey.app"
    ln -s /Applications "$staging/Applications"
    hdiutil create -volname "TickKey $version" -srcfolder "$staging" -ov -format UDZO "$dmg"
  fi
  hdiutil verify "$dmg"
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$dmg"
  codesign --verify --verbose=2 "$dmg"
  if [[ "$NOTARIZE" == true ]]; then
    xcrun notarytool submit "$dmg" --keychain-profile "$PROFILE" --wait --output-format json > "$work/notary.json"
    python3 - "$work/notary.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    raise SystemExit('公证未通过：' + str(result.get('id')) + ' ' + str(result.get('status')))
PY
    xcrun stapler staple "$dmg"
    xcrun stapler validate "$dmg"
  fi
  echo "完成: $dmg"
}

for arch in "${ARCHES[@]}"; do
  build_arch "$arch"
done
echo "输出目录: $OUT"
