#!/usr/bin/env bash
# 参考 ZiYa 的归档、公证、钉合流程；原生 macOS 由 Xcode 导出 Developer ID 签名包。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/network.sh"
PROFILE=vanjay_mac_stapler
NOTARIZE=true
PRETTY_DMG="${PRETTY_DMG_SCRIPT:-$HOME/Documents/Career/Github/quick_shell/develop/app/create_pretty_dmg.sh}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --keychain-profile) PROFILE="${2:?缺少 profile 名称}"; shift 2 ;;
    --no-notarize) NOTARIZE=false; shift ;;
    --help|-h) echo '用法: Scripts/build_dmg.sh [--keychain-profile PROFILE] [--no-notarize]'; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 1 ;;
  esac
done
OUT="$ROOT/build/release/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
xcodebuild -project "$ROOT/TickKey.xcodeproj" -scheme TickKeyMac -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$OUT/TickKey.xcarchive" \
  -derivedDataPath "$ROOT/build/ReleaseDerivedData" -clonedSourcePackagesDirPath "$ROOT/build/SourcePackages" \
  DEVELOPMENT_TEAM=X6B6C6U6QV CODE_SIGN_STYLE=Manual 'CODE_SIGN_IDENTITY=Developer ID Application' archive
cat > "$OUT/ExportOptions.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>method</key><string>developer-id</string><key>signingStyle</key><string>automatic</string><key>teamID</key><string>X6B6C6U6QV</string></dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$OUT/TickKey.xcarchive" -exportPath "$OUT/export" -exportOptionsPlist "$OUT/ExportOptions.plist"
APP="$OUT/export/TickKey.app"
codesign --verify --deep --strict --verbose=2 "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
DMG="$OUT/TickKey-$VERSION.dmg"
if [[ -x "$PRETTY_DMG" ]]; then
  "$PRETTY_DMG" --app-path "$APP" --dmg-name "TickKey-$VERSION" --output-dir "$OUT"
else
  STAGING="$OUT/dmg-content"
  mkdir -p "$STAGING"
  ditto "$APP" "$STAGING/TickKey.app"
  ln -s /Applications "$STAGING/Applications"
  hdiutil create -volname "TickKey $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
fi
hdiutil verify "$DMG"
if [[ "$NOTARIZE" == true ]]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait --output-format json > "$OUT/notary.json"
  python3 - "$OUT/notary.json" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]))
if r.get('status') != 'Accepted': raise SystemExit('公证未通过：'+str(r.get('id'))+' '+str(r.get('status')))
PY
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
fi
echo "完成: $DMG"
