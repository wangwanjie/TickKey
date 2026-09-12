#!/usr/bin/env bash
# 参考 ZiYa：归档后用独立 ExportOptions 导出，不在脚本中保存凭证。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/network.sh"
METHOD="${1:-release-testing}"
case "$METHOD" in
  --help|-h) echo '用法: Scripts/build_ipa.sh [release-testing|debugging|app-store-connect]'; exit 0 ;;
  release-testing|debugging|app-store-connect) ;;
  *) echo '不支持的导出类型' >&2; exit 1 ;;
esac
bash "$SCRIPT_DIR/install_pods.sh" --deployment
OUT="$ROOT/build/ipa/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
xcodebuild -workspace "$ROOT/TickKey.xcworkspace" -scheme TickKey -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$OUT/TickKey.xcarchive" -allowProvisioningUpdates archive
python3 - "$METHOD" "$OUT/ExportOptions.plist" <<'PY'
import plistlib,sys
with open(sys.argv[2],'wb') as f: plistlib.dump({'method':sys.argv[1],'teamID':'X6B6C6U6QV','signingStyle':'automatic','manageAppVersionAndBuildNumber':False},f)
PY
xcodebuild -exportArchive -archivePath "$OUT/TickKey.xcarchive" -exportPath "$OUT/export" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates
echo "完成: $OUT/export"
