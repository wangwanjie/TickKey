#!/usr/bin/env python3
"""列出自有 Swift 源码，供 Xcode 沙盒中的格式检查精确读取。"""
from pathlib import Path

root = Path(__file__).resolve().parent.parent
folders = ('Shared', 'TickKey', 'TickKeyMac', 'CoreTests', 'TickKeyTests', 'TickKeyUITests', 'Scripts')
inputs = ['.swiftformat', '.swiftlint.yml', 'Scripts/check_swift.sh', 'Configuration/SwiftLintInputs.xcfilelist']
inputs += sorted(str(path.relative_to(root)) for folder in folders for path in (root / folder).rglob('*.swift'))
(root / 'Configuration/SwiftLintInputs.xcfilelist').write_text(''.join('$(SRCROOT)/' + path + '\n' for path in inputs))
