#!/usr/bin/env bash
# 为按架构拆分的 DMG 生成带 EdDSA 签名的 appcast 和校验值，不自动发布到 GitHub。
# 输出：appcast-arm64.xml / appcast-x86_64.xml 供新版本按架构更新；
# appcast.xml 兼容 1.0.2 及更早的通用版本，Apple 芯片优先获得 arm64 包，Intel 获得 x86_64 包。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
if [[ $# -lt 2 ]]; then
  echo '用法: Scripts/prepare_release.sh <Sparkle bin 目录> <已公证的 TickKey-x.y.z-arm64.dmg> [TickKey-x.y.z-x86_64.dmg]'
  exit 1
fi
SPARKLE_BIN="$1"
shift
[[ -x "$SPARKLE_BIN/sign_update" ]] || { echo '找不到 Sparkle sign_update 工具' >&2; exit 1; }
OUT="$ROOT/build/appcast"
rm -rf "$OUT"
mkdir -p "$OUT"
VERSION=''
ITEMS=()
for DMG in "$@"; do
  NAME="$(basename "$DMG" .dmg)"
  [[ "$NAME" =~ ^TickKey-([0-9]+\.[0-9]+\.[0-9]+)-(arm64|x86_64)$ ]] || {
    echo "DMG 名称必须为 TickKey-x.y.z-<arm64|x86_64>.dmg: $DMG" >&2
    exit 1
  }
  if [[ -n "$VERSION" && "$VERSION" != "${BASH_REMATCH[1]}" ]]; then
    echo '所有 DMG 必须属于同一版本' >&2
    exit 1
  fi
  VERSION="${BASH_REMATCH[1]}"
  ARCH="${BASH_REMATCH[2]}"
  xcrun stapler validate "$DMG"
  cp "$DMG" "$OUT/"

  # 从 DMG 内的应用读取构建号和最低系统版本，确保 appcast 与实际安装包一致。
  MOUNT="$(mktemp -d)"
  hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT" "$DMG" >/dev/null
  PLIST="$MOUNT/TickKey.app/Contents/Info.plist"
  BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$PLIST")"
  MINIMUM="$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' "$PLIST")"
  BINARY_ARCH="$(lipo -archs "$MOUNT/TickKey.app/Contents/MacOS/TickKey")"
  hdiutil detach "$MOUNT" >/dev/null
  rmdir "$MOUNT"
  [[ "$BINARY_ARCH" == "$ARCH" ]] || { echo "$DMG 的主程序架构为 $BINARY_ARCH" >&2; exit 1; }

  # sign_update 从 Keychain 读取 Sparkle 私钥；切勿把私钥写入仓库。
  SIGNATURE="$("$SPARKLE_BIN/sign_update" --account cn.vanjay.TickKey.Sparkle "$DMG")"
  ITEMS+=("$ARCH|$BUILD|$MINIMUM|$(basename "$DMG")|$SIGNATURE")
done
NOTES="$ROOT/Docs/ReleaseNotes-$VERSION.md"
[[ -f "$NOTES" ]] || { echo "缺少发布说明: $NOTES" >&2; exit 1; }
cp "$NOTES" "$OUT/TickKey-$VERSION.md"
python3 - "$OUT" "$VERSION" "${ITEMS[@]}" <<'PY'
import email.utils
import sys
from pathlib import Path
from xml.sax.saxutils import quoteattr

out, version, raw_items = Path(sys.argv[1]), sys.argv[2], sys.argv[3:]
base = f'https://github.com/wangwanjie/TickKey/releases/download/v{version}/'
date = email.utils.formatdate(localtime=True)
items = {}
for raw in raw_items:
    arch, build, minimum, name, signature = raw.split('|', 4)
    items[arch] = (build, minimum, name, signature)


def item(arch, require_arm64):
    build, minimum, name, signature = items[arch]
    hardware = '\n            <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>' if require_arm64 else ''
    return f'''        <item>
            <title>{version}</title>
            <pubDate>{date}</pubDate>
            <sparkle:version>{build}</sparkle:version>
            <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>{minimum}</sparkle:minimumSystemVersion>{hardware}
            <sparkle:releaseNotesLink>{base}TickKey-{version}.md</sparkle:releaseNotesLink>
            <enclosure url={quoteattr(base + name)} type="application/octet-stream" {signature}/>
        </item>
'''


def write(name, body):
    (out / name).write_text(f'''<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
        <title>TickKey</title>
{body}    </channel>
</rss>
''')


for arch in items:
    write(f'appcast-{arch}.xml', item(arch, False))
# 旧通用版本只读取 appcast.xml：Intel 会过滤带 arm64 要求的条目，
# Apple 芯片两条都满足，Sparkle 在同版本中保留先出现的 arm64 条目。
legacy = ''
if 'arm64' in items:
    legacy += item('arm64', 'x86_64' in items)
if 'x86_64' in items:
    legacy += item('x86_64', False)
write('appcast.xml', legacy)
PY
(cd "$OUT" && shasum -a 256 ./*.dmg | sed 's| \./| |' > SHA256SUMS)
echo "待发布文件: $OUT"
ls -1 "$OUT"
