/* TickKey 主页脚本：三语、三主题、实时 TOTP 演示、下载直链 */
(function () {
  "use strict";

  var root = document.documentElement;
  var reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  var REPO = "wangwanjie/TickKey";

  // ===== 文案 =====
  var I18N = {
    "zh-CN": {
      _title: "TickKey — 本地生成验证码的两步验证器",
      _desc: "TickKey 是免费的本地 TOTP 两步验证器，支持 Mac、iPhone 与 iPad。无账户注册、广告、分析 SDK 或服务端，验证码完全在本机生成。",
      skip: "跳到正文", iconAlt: "TickKey 图标", navAria: "主导航", langAria: "语言", themeAria: "主题",
      themeLight: "浅色", themeDark: "深色", themeSystem: "跟随系统", ghAria: "GitHub 仓库",
      navHow: "原理", navLocal: "安全", navFeatures: "功能", navDownload: "下载",
      eyebrow: "TOTP 两步验证器 · Mac / iPhone / iPad",
      h1a: "每 30 秒一组新验证码，", h1b: "只在你的设备上生成。",
      lead: "TickKey 是免费的本地两步验证器。无需注册账户，没有广告、分析 SDK 和服务端；账户密钥加密保存在本机。",
      btnArm: "下载 Mac 版 · Apple 芯片", btnArmSub: "arm64 DMG · macOS 12+",
      btnIntel: "Intel 版", btnIntelSub: "x86_64 DMG",
      meta: "Developer ID 签名 · Apple 公证 · Sparkle 自动更新",
      iosLink: "iPhone / iPad：Release 中提供 Ad Hoc 测试包 →",
      beatLabel: "距下次刷新", beatUnit: "秒",
      stageNote: "示例账户与密钥均为虚构；验证码由本页在浏览器中按 RFC 6238 实时计算。点按卡片可复制。",
      stageNoteFallback: "示例账户与验证码均为虚构，仅作演示。点按卡片可复制。",
      zerosAria: "隐私承诺", z1: "账户注册", z2: "服务端", z3: "广告与分析 SDK", z4: "本机加密存储",
      howTitle: "验证码由密钥和时间算出，全程离线。",
      howSub: "TOTP（RFC 6238）用共享密钥对当前时间片做 HMAC，再截取 6 位数字。网站和 TickKey 各自计算，结果一致即通过验证。",
      p1: "密钥", p1d: "添加账户时从二维码或链接读取，加密保存在本机。",
      p2: "时间片 T", p2d: "T = ⌊Unix 时间 ÷ 30⌋，每 30 秒加一。",
      p3d: "用密钥对 T 计算 20 字节消息认证码。",
      p4: "动态截断", p4d: "取出 31 位整数，对 10⁶ 取模得到 6 位验证码。",
      howFine: "TickKey 同样支持 SHA-256 / SHA-512、6–8 位与 1–300 秒周期。正确的系统时钟是验证码正确的前提。",
      localTitle: "账户数据留在设备里。",
      localSub: "验证码生成与账户存储都在本机完成，断网时照常可用。TickKey 没有同步服务，账户不会上传到任何云端。",
      dgDevice: "你的设备", dgOffline: "离线可用", dgKey: "密钥", dgTime: "时间", dgEnc: "AES-256-GCM · Keychain",
      dgCloud: "同步服务器", dgNone: "不存在",
      f1: "AES-256-GCM 加密", f1d: "账户整体加密后存入 SQLite；随机设备密钥保存在 Keychain，不同步到 iCloud。",
      f2: "排除系统备份", f2d: "账户数据库排除系统文件备份。换设备时，主动导出用密码加密的 .tickkey 备份；遗失备份密码无法恢复。",
      f3: "可选解锁保护", f3d: "启动、回到前台或锁屏后需通过面容 ID、触控 ID 或设备密码解锁，Mac 按 ⌘L 立即锁定。身份验证由系统完成，应用不保存生物特征或设备密码。",
      f4: "剪贴板 30 秒清理", f4d: "复制的验证码 30 秒后清理。Mac 将其标记为敏感临时内容，遵循约定的剪贴板管理工具不会记录；iOS 禁止验证码经通用剪贴板跨设备传播，失去活动状态时遮挡界面。",
      localFine: "TickKey 目前未经过独立安全审计。导出的文本和二维码包含真实密钥，请像密码一样保管。",
      shotTitle: "原生的 Mac 与 iPhone 应用。",
      shotSub: "Mac 使用 AppKit，iPhone / iPad 使用 UIKit，两端共用验证码、存储与备份实现。界面支持简体中文、繁体中文与 English，语言和外观可热切换。",
      altMac: "TickKey Mac 主界面", altIos: "TickKey iPhone 主界面",
      featTitle: "日常够用，迁移顺手。",
      ft1: "账户卡片", ft1d: "自适应卡片布局，搜索、单击复制、编辑与删除，圆饼倒计时一目了然。",
      ft2: "扫码与剪贴板导入", ft2d: "手机相机扫描 otpauth 与迁移二维码；两端都可从二维码图片、剪贴板链接或截图导入，Mac 可把文件直接拖进窗口。",
      ft3: "Google Authenticator 迁移", ft3d: "导入 Google Authenticator 迁移二维码与链接，也能导出分页的迁移二维码。",
      ft4: ".tickkey 加密备份", ft4d: "跨平台的密码加密备份。在访达中双击，或在「文件」、邮件、隔空投送中选择「用 TickKey 打开」即可导入。",
      ft5: "文本导入导出", ft5d: "逐行导入 otpauth URI 或迁移链接，兼容浏览器 Authenticator 插件导出的文本；可导出 otpauth 文本。",
      ft6: "精确去重", ft6d: "发行方、账户、规范化密钥、算法、位数、周期完全一致才视为重复，不同密钥都会保留。",
      ft7: "二维码导出", ft7d: "导出单个账户二维码、全部账户二维码，方便换到其他验证器。",
      ft8: "安全的批量删除", ft8d: "多选、全选与反选；超过 5 项或全选删除时提醒备份，并要求两次确认。",
      specTitle: "兼容性", sAlg: "算法", sDigits: "位数 / 周期", sDigitsV: "6–8 位 · 1–300 秒",
      sIn: "导入", sInV: "otpauth://totp · Google Authenticator 迁移 · 文本文件 · .tickkey",
      sOut: "导出", sOutV: "otpauth 文本 · .tickkey · 二维码 · 迁移二维码（30 秒周期的 6 / 8 位账户）",
      sHotpV: "暂不支持",
      dlTitle: "下载 TickKey",
      dlSub: "免费。Mac 版经 Developer ID 签名和 Apple 公证，安装后通过 Sparkle 获取与本机架构一致的更新。",
      dlArm: "Apple 芯片", dlArmD: "M1 及更新的 Mac · macOS 12 或更高",
      dlIntel: "Intel 芯片", dlIntelD: "Intel 处理器的 Mac · macOS 12 或更高",
      dlIos: "Ad Hoc 测试包", dlIosD: "iOS 15 或更高。尚未上架 App Store；IPA 只能安装到已加入描述文件的设备。",
      dlDmg: "下载 DMG", dlIpa: "下载 IPA",
      st1: "不确定芯片类型：打开「苹果菜单 › 关于本机」，查看「芯片」或「处理器」一栏。",
      st2: "打开 DMG，把 TickKey 拖进「应用程序」文件夹。",
      st3: "之后的新版本由内置的 Sparkle 自动获取，也可在设置中手动检查。",
      dlHistory: "历史版本与 SHA256SUMS 校验值 →",
      footAria: "页脚链接", fMore: "VanJay 的更多作品", fIssues: "反馈问题", fReleases: "版本历史",
      latest: "最新版本 {v} · {d}", copied: "已复制 {c}（演示验证码）", copiedTag: "已复制"
    },
    "zh-TW": {
      _title: "TickKey — 在本機產生驗證碼的兩步驟驗證器",
      _desc: "TickKey 是免費的本機 TOTP 兩步驟驗證器，支援 Mac、iPhone 與 iPad。無須註冊帳號，沒有廣告、分析 SDK 或伺服器，驗證碼完全在本機產生。",
      skip: "跳到內文", iconAlt: "TickKey 圖示", navAria: "主要導覽", langAria: "語言", themeAria: "主題",
      themeLight: "淺色", themeDark: "深色", themeSystem: "跟隨系統", ghAria: "GitHub 儲存庫",
      navHow: "原理", navLocal: "安全", navFeatures: "功能", navDownload: "下載",
      eyebrow: "TOTP 兩步驟驗證器 · Mac / iPhone / iPad",
      h1a: "每 30 秒一組新驗證碼，", h1b: "只在你的裝置上產生。",
      lead: "TickKey 是免費的本機兩步驟驗證器。無須註冊帳號，沒有廣告、分析 SDK 和伺服器；帳號金鑰加密儲存在本機。",
      btnArm: "下載 Mac 版 · Apple 晶片", btnArmSub: "arm64 DMG · macOS 12+",
      btnIntel: "Intel 版", btnIntelSub: "x86_64 DMG",
      meta: "Developer ID 簽署 · Apple 公證 · Sparkle 自動更新",
      iosLink: "iPhone / iPad：Release 中提供 Ad Hoc 測試套件 →",
      beatLabel: "距下次更新", beatUnit: "秒",
      stageNote: "範例帳號與金鑰皆為虛構；驗證碼由本頁在瀏覽器中依 RFC 6238 即時計算。點一下卡片即可拷貝。",
      stageNoteFallback: "範例帳號與驗證碼皆為虛構，僅供展示。點一下卡片即可拷貝。",
      zerosAria: "隱私承諾", z1: "帳號註冊", z2: "伺服器", z3: "廣告與分析 SDK", z4: "本機加密儲存",
      howTitle: "驗證碼由金鑰和時間算出，全程離線。",
      howSub: "TOTP（RFC 6238）以共用金鑰對目前的時間片段計算 HMAC，再擷取 6 位數字。網站和 TickKey 各自計算，結果一致即通過驗證。",
      p1: "金鑰", p1d: "新增帳號時從 QR Code 或連結讀取，加密儲存在本機。",
      p2: "時間片段 T", p2d: "T = ⌊Unix 時間 ÷ 30⌋，每 30 秒加一。",
      p3d: "以金鑰對 T 計算 20 位元組的訊息鑑別碼。",
      p4: "動態截斷", p4d: "取出 31 位元整數，對 10⁶ 取餘數得到 6 位驗證碼。",
      howFine: "TickKey 同樣支援 SHA-256 / SHA-512、6–8 位數與 1–300 秒週期。正確的系統時鐘是驗證碼正確的前提。",
      localTitle: "帳號資料留在裝置裡。",
      localSub: "驗證碼產生與帳號儲存都在本機完成，離線時照常可用。TickKey 沒有同步服務，帳號不會上傳到任何雲端。",
      dgDevice: "你的裝置", dgOffline: "離線可用", dgKey: "金鑰", dgTime: "時間", dgEnc: "AES-256-GCM · 鑰匙圈",
      dgCloud: "同步伺服器", dgNone: "不存在",
      f1: "AES-256-GCM 加密", f1d: "帳號整體加密後存入 SQLite；隨機裝置金鑰儲存在鑰匙圈（Keychain），不會同步到 iCloud。",
      f2: "排除系統備份", f2d: "帳號資料庫排除系統檔案備份。更換裝置時，請主動匯出以密碼加密的 .tickkey 備份；遺失備份密碼將無法復原。",
      f3: "可選的解鎖保護", f3d: "啟動、回到前景或鎖定螢幕後需透過 Face ID、Touch ID 或裝置密碼解鎖，Mac 按 ⌘L 立即鎖定。身分驗證由系統完成，App 不儲存生物特徵或裝置密碼。",
      f4: "剪貼簿 30 秒清除", f4d: "拷貝的驗證碼 30 秒後清除。Mac 將其標記為敏感暫時內容，遵循慣例的剪貼簿管理工具不會記錄；iOS 禁止驗證碼經「通用剪貼簿」跨裝置傳遞，失去作用中狀態時遮擋畫面。",
      localFine: "TickKey 目前尚未經過獨立安全稽核。匯出的文字和 QR Code 含有真實金鑰，請像密碼一樣妥善保管。",
      shotTitle: "原生的 Mac 與 iPhone App。",
      shotSub: "Mac 使用 AppKit，iPhone / iPad 使用 UIKit，兩端共用驗證碼、儲存與備份實作。介面支援簡體中文、繁體中文與 English，語言和外觀可即時切換。",
      altMac: "TickKey Mac 主畫面", altIos: "TickKey iPhone 主畫面",
      featTitle: "日常夠用，搬家順手。",
      ft1: "帳號卡片", ft1d: "自適應卡片版面，搜尋、按一下拷貝、編輯與刪除，圓餅倒數一目了然。",
      ft2: "掃描與剪貼簿匯入", ft2d: "以手機相機掃描 otpauth 與轉移 QR Code；兩端都能從 QR Code 圖片、剪貼簿連結或截圖匯入，Mac 可把檔案直接拖進視窗。",
      ft3: "Google Authenticator 轉移", ft3d: "匯入 Google Authenticator 轉移 QR Code 與連結，也能匯出分頁的轉移 QR Code。",
      ft4: ".tickkey 加密備份", ft4d: "跨平台的密碼加密備份。在 Finder 中按兩下，或在「檔案」、郵件、AirDrop 中選擇「以 TickKey 打開」即可匯入。",
      ft5: "文字匯入匯出", ft5d: "逐行匯入 otpauth URI 或轉移連結，相容瀏覽器 Authenticator 擴充功能匯出的文字；可匯出 otpauth 文字。",
      ft6: "精確去除重複", ft6d: "發行者、帳號、正規化金鑰、演算法、位數、週期完全一致才視為重複，不同金鑰都會保留。",
      ft7: "QR Code 匯出", ft7d: "匯出單一帳號 QR Code、全部帳號 QR Code，方便換到其他驗證器。",
      ft8: "安全的批次刪除", ft8d: "多選、全選與反向選取；刪除超過 5 項或全部刪除時提醒備份，並要求兩次確認。",
      specTitle: "相容性", sAlg: "演算法", sDigits: "位數 / 週期", sDigitsV: "6–8 位 · 1–300 秒",
      sIn: "匯入", sInV: "otpauth://totp · Google Authenticator 轉移 · 文字檔案 · .tickkey",
      sOut: "匯出", sOutV: "otpauth 文字 · .tickkey · QR Code · 轉移 QR Code（30 秒週期的 6 / 8 位帳號）",
      sHotpV: "暫不支援",
      dlTitle: "下載 TickKey",
      dlSub: "免費。Mac 版經 Developer ID 簽署與 Apple 公證，安裝後透過 Sparkle 取得與本機架構一致的更新。",
      dlArm: "Apple 晶片", dlArmD: "M1 及更新的 Mac · macOS 12 或以上版本",
      dlIntel: "Intel 晶片", dlIntelD: "Intel 處理器的 Mac · macOS 12 或以上版本",
      dlIos: "Ad Hoc 測試套件", dlIosD: "iOS 15 或以上版本。尚未上架 App Store；IPA 只能安裝到已加入描述檔的裝置。",
      dlDmg: "下載 DMG", dlIpa: "下載 IPA",
      st1: "不確定晶片類型：打開「蘋果選單 › 關於這台 Mac」，查看「晶片」或「處理器」一欄。",
      st2: "打開 DMG，把 TickKey 拖進「應用程式」檔案夾。",
      st3: "之後的新版本由內建的 Sparkle 自動取得，也可在設定中手動檢查。",
      dlHistory: "歷史版本與 SHA256SUMS 校驗值 →",
      footAria: "頁尾連結", fMore: "VanJay 的更多作品", fIssues: "回報問題", fReleases: "版本紀錄",
      latest: "最新版本 {v} · {d}", copied: "已拷貝 {c}（展示用驗證碼）", copiedTag: "已拷貝"
    },
    en: {
      _title: "TickKey — A two-factor authenticator that stays on your device",
      _desc: "TickKey is a free, local TOTP authenticator for Mac, iPhone and iPad. No sign-up, ads, analytics SDKs or servers — codes are generated entirely on your device.",
      skip: "Skip to content", iconAlt: "TickKey icon", navAria: "Main navigation", langAria: "Language", themeAria: "Theme",
      themeLight: "Light", themeDark: "Dark", themeSystem: "Match system", ghAria: "GitHub repository",
      navHow: "How it works", navLocal: "Security", navFeatures: "Features", navDownload: "Download",
      eyebrow: "TOTP authenticator · Mac / iPhone / iPad",
      h1a: "A fresh code every 30 seconds,", h1b: "made only on your device.",
      lead: "TickKey is a free, local two-factor authenticator. No sign-up, no ads, no analytics SDKs, no servers — your account secrets stay encrypted on your device.",
      btnArm: "Download for Mac · Apple silicon", btnArmSub: "arm64 DMG · macOS 12+",
      btnIntel: "Intel", btnIntelSub: "x86_64 DMG",
      meta: "Developer ID signed · Notarized by Apple · Sparkle updates",
      iosLink: "iPhone / iPad: an Ad Hoc test build is in each release →",
      beatLabel: "Next code in", beatUnit: "s",
      stageNote: "Sample accounts and secrets are fictional. Codes are computed live in your browser per RFC 6238. Tap a card to copy.",
      stageNoteFallback: "Sample accounts and codes are fictional, for illustration only. Tap a card to copy.",
      zerosAria: "Privacy commitments", z1: "accounts to sign up", z2: "servers", z3: "ads or analytics SDKs", z4: "on-device encryption",
      howTitle: "Codes come from a secret and the clock. Fully offline.",
      howSub: "TOTP (RFC 6238) runs an HMAC over the current time step with a shared secret, then extracts six digits. The website and TickKey compute independently; matching results pass.",
      p1: "Secret", p1d: "Read from a QR code or link when you add an account, then encrypted on your device.",
      p2: "Time step T", p2d: "T = ⌊Unix time ÷ 30⌋, advancing once every 30 seconds.",
      p3d: "A 20-byte message authentication code of T, keyed by the secret.",
      p4: "Dynamic truncation", p4d: "Take a 31-bit integer and reduce it mod 10⁶ to get six digits.",
      howFine: "TickKey also supports SHA-256 / SHA-512, 6–8 digits and 1–300 second periods. A correct system clock is required for correct codes.",
      localTitle: "Your accounts stay on your device.",
      localSub: "Code generation and account storage both happen locally, and work offline. TickKey has no sync service, so your accounts are never uploaded to any cloud.",
      dgDevice: "Your device", dgOffline: "Works offline", dgKey: "Secret", dgTime: "Time", dgEnc: "AES-256-GCM · Keychain",
      dgCloud: "Sync server", dgNone: "None",
      f1: "AES-256-GCM encryption", f1d: "Accounts are encrypted as a whole into SQLite. A random device key lives in the Keychain and never syncs to iCloud.",
      f2: "Excluded from system backups", f2d: "The account database is excluded from system file backups. When switching devices, export a password-encrypted .tickkey backup; a lost backup password cannot be recovered.",
      f3: "Optional app lock", f3d: "Require Face ID, Touch ID or the device passcode on launch, on return, or after the screen locks. Press ⌘L on Mac to lock instantly. The system handles authentication; the app stores no biometrics or passcodes.",
      f4: "Clipboard cleared after 30 s", f4d: "Copied codes are cleared after 30 seconds. On Mac they are marked as sensitive, transient content that well-behaved clipboard managers skip. On iOS codes stay off Universal Clipboard, and the screen is covered when the app goes inactive.",
      localFine: "TickKey has not had an independent security audit. Exported text and QR codes contain real secrets — treat them like passwords.",
      shotTitle: "Native apps for Mac and iPhone.",
      shotSub: "AppKit on Mac and UIKit on iPhone / iPad, sharing the same code generation, storage and backup engine. The interface comes in Simplified Chinese, Traditional Chinese and English, with live language and appearance switching.",
      altMac: "TickKey main window on Mac", altIos: "TickKey main screen on iPhone",
      featTitle: "Covers the everyday. Makes switching easy.",
      ft1: "Account cards", ft1d: "Adaptive cards with search, click-to-copy, edit and delete, plus a pie countdown you can read at a glance.",
      ft2: "Scan & clipboard import", ft2d: "Scan otpauth and migration QR codes with the iPhone camera. Both apps import from QR images, clipboard links or screenshots, and the Mac accepts dropped files.",
      ft3: "Google Authenticator migration", ft3d: "Import Google Authenticator migration QR codes and links, and export paged migration QR codes.",
      ft4: ".tickkey encrypted backups", ft4d: "Password-encrypted backups that work across platforms. Double-click in Finder, or choose “Open in TickKey” from Files, Mail or AirDrop to import.",
      ft5: "Text import & export", ft5d: "Import otpauth URIs or migration links line by line, including text exported by browser Authenticator extensions. Export as otpauth text.",
      ft6: "Precise de-duplication", ft6d: "Entries count as duplicates only when issuer, account, normalized secret, algorithm, digits and period all match; different secrets are kept.",
      ft7: "QR code export", ft7d: "Export a QR code for one account or for all of them, ready for another authenticator.",
      ft8: "Careful batch delete", ft8d: "Multi-select, select all and invert. Deleting more than five items or everything prompts a backup reminder and a double confirmation.",
      specTitle: "Compatibility", sAlg: "Algorithms", sDigits: "Digits / period", sDigitsV: "6–8 digits · 1–300 s",
      sIn: "Import", sInV: "otpauth://totp · Google Authenticator migration · text files · .tickkey",
      sOut: "Export", sOutV: "otpauth text · .tickkey · QR codes · migration QR (30 s period, 6 / 8 digits)",
      sHotpV: "Not supported yet",
      dlTitle: "Download TickKey",
      dlSub: "Free. The Mac app is Developer ID signed and notarized by Apple, and Sparkle delivers updates for your Mac's architecture.",
      dlArm: "Apple silicon", dlArmD: "Macs with M1 or later · macOS 12 or later",
      dlIntel: "Intel", dlIntelD: "Macs with Intel processors · macOS 12 or later",
      dlIos: "Ad Hoc test build", dlIosD: "iOS 15 or later. Not on the App Store yet; the IPA installs only on devices included in the provisioning profile.",
      dlDmg: "Download DMG", dlIpa: "Download IPA",
      st1: "Not sure which chip you have? Open  › About This Mac and check “Chip” or “Processor”.",
      st2: "Open the DMG and drag TickKey into the Applications folder.",
      st3: "New versions arrive through the built-in Sparkle updater, or check manually in Settings.",
      dlHistory: "Release history and SHA256SUMS →",
      footAria: "Footer links", fMore: "More by VanJay", fIssues: "Feedback", fReleases: "Releases",
      latest: "Latest {v} · {d}", copied: "Copied {c} (demo code)", copiedTag: "Copied"
    }
  };

  // ===== 语言 =====
  var lang = "zh-CN";
  var latest = null;

  function normalizeLang(value) {
    if (!value) {
      return null;
    }
    var v = String(value).toLowerCase();
    if (/^zh[-_](tw|hk|mo|hant)/.test(v) || v === "tw" || v === "hant" || v.indexOf("hant") >= 0) {
      return "zh-TW";
    }
    if (v.indexOf("zh") === 0 || v === "hans" || v === "cn") {
      return "zh-CN";
    }
    if (v.indexOf("en") === 0) {
      return "en";
    }
    return null;
  }

  function detectLang() {
    var q = null;
    try {
      q = normalizeLang(new URLSearchParams(location.search).get("lang"));
    } catch (e) {}
    if (q) {
      return q;
    }
    var saved = null;
    try {
      saved = normalizeLang(localStorage.getItem("tickkey.lang"));
    } catch (e) {}
    if (saved) {
      return saved;
    }
    var list = navigator.languages && navigator.languages.length ? navigator.languages : [navigator.language || "en"];
    for (var i = 0; i < list.length; i++) {
      var l = String(list[i]).toLowerCase();
      if (l.indexOf("zh") === 0) {
        return normalizeLang(l) === "zh-TW" ? "zh-TW" : "zh-CN";
      }
      if (l.indexOf("en") === 0) {
        return "en";
      }
    }
    return "en";
  }

  function t(key) {
    var dict = I18N[lang];
    if (dict[key] !== undefined) {
      return dict[key];
    }
    return I18N["zh-CN"][key];
  }

  function applyLang(next, save) {
    lang = next;
    root.lang = next;
    document.title = t("_title");
    var desc = document.querySelector('meta[name="description"]');
    if (desc) {
      desc.content = t("_desc");
    }
    var nodes = document.querySelectorAll("[data-i]");
    for (var i = 0; i < nodes.length; i++) {
      nodes[i].textContent = t(nodes[i].getAttribute("data-i"));
    }
    var htmlNodes = document.querySelectorAll("[data-i-html]");
    for (var j = 0; j < htmlNodes.length; j++) {
      htmlNodes[j].textContent = t(htmlNodes[j].getAttribute("data-i-html"));
    }
    var attrs = [["data-i-alt", "alt"], ["data-i-aria", "aria-label"], ["data-i-title", "title"]];
    attrs.forEach(function (pair) {
      var list = document.querySelectorAll("[" + pair[0] + "]");
      for (var k = 0; k < list.length; k++) {
        list[k].setAttribute(pair[1], t(list[k].getAttribute(pair[0])));
      }
    });
    var buttons = document.querySelectorAll("#lang-seg button");
    for (var b = 0; b < buttons.length; b++) {
      buttons[b].setAttribute("aria-pressed", String(buttons[b].dataset.lang === next));
    }
    if (!subtleOK) {
      document.getElementById("stage-note").textContent = t("stageNoteFallback");
    }
    renderVersion();
    if (save) {
      try {
        localStorage.setItem("tickkey.lang", next);
      } catch (e) {}
    }
  }

  document.getElementById("lang-seg").addEventListener("click", function (event) {
    var button = event.target.closest("button[data-lang]");
    if (button) {
      applyLang(button.dataset.lang, true);
    }
  });

  // ===== 主题 =====
  var darkQuery = window.matchMedia("(prefers-color-scheme: dark)");
  var themeMeta = document.querySelector('meta[name="theme-color"]');

  function applyTheme(pref, save) {
    var dark = pref === "dark" || (pref === "system" && darkQuery.matches);
    root.dataset.themePref = pref;
    root.dataset.theme = dark ? "dark" : "light";
    if (themeMeta) {
      themeMeta.content = dark ? "#060b16" : "#fbfcfe";
    }
    var buttons = document.querySelectorAll("#theme-seg button");
    for (var i = 0; i < buttons.length; i++) {
      buttons[i].setAttribute("aria-pressed", String(buttons[i].dataset.themeSet === pref));
    }
    if (save) {
      try {
        if (pref === "system") {
          localStorage.removeItem("tickkey.theme");
        } else {
          localStorage.setItem("tickkey.theme", pref);
        }
      } catch (e) {}
    }
  }

  document.getElementById("theme-seg").addEventListener("click", function (event) {
    var button = event.target.closest("button[data-theme-set]");
    if (button) {
      applyTheme(button.dataset.themeSet, true);
    }
  });
  var onSchemeChange = function () {
    if (root.dataset.themePref === "system") {
      applyTheme("system", false);
    }
  };
  if (darkQuery.addEventListener) {
    darkQuery.addEventListener("change", onSchemeChange);
  } else if (darkQuery.addListener) {
    darkQuery.addListener(onSchemeChange);
  }

  // ===== TOTP 演示 =====
  // 示例账户与密钥全部虚构（与应用截图中的演示账户同名）
  var ACCOUNTS = [
    ["GitHub", "octocat@example.com", "JBSWY3DPEHPK3PXP"],
    ["Google", "alice@example.com", "KRUGKIDROVUWG2ZA"],
    ["Apple", "alice@icloud.example", "MFRGGZDFMZTWQ2LK"],
    ["Cloudflare", "ops@example.com", "GEZDGNBVGY3TQOJQ"],
    ["Microsoft", "alice@outlook.example", "NBSWY3DPO5XXE3DE"],
    ["AWS", "root-account", "ORSXG5BAMJSWY3DP"]
  ];
  var PERIOD = 30;
  var subtleOK = !!(window.crypto && window.crypto.subtle && window.isSecureContext);
  var keyCache = {};

  function base32Decode(text) {
    var alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
    var bits = 0;
    var value = 0;
    var out = [];
    for (var i = 0; i < text.length; i++) {
      var idx = alphabet.indexOf(text.charAt(i));
      if (idx < 0) {
        continue;
      }
      value = (value << 5) | idx;
      bits += 5;
      if (bits >= 8) {
        out.push((value >>> (bits - 8)) & 255);
        bits -= 8;
      }
    }
    return new Uint8Array(out);
  }

  function importKey(secret) {
    if (!keyCache[secret]) {
      keyCache[secret] = crypto.subtle.importKey("raw", base32Decode(secret), { name: "HMAC", hash: "SHA-1" }, false, ["sign"]);
    }
    return keyCache[secret];
  }

  // 返回 { code, hmac }；不支持 WebCrypto 时退回伪随机演示数字
  function totp(secret, counter) {
    if (!subtleOK) {
      var seed = (counter * 2654435761 + secret.charCodeAt(0) * 97 + secret.charCodeAt(3) * 13) >>> 0;
      return Promise.resolve({ code: String(seed % 1000000).padStart(6, "0"), hmac: null });
    }
    var msg = new ArrayBuffer(8);
    var view = new DataView(msg);
    view.setUint32(0, Math.floor(counter / 4294967296));
    view.setUint32(4, counter >>> 0);
    return importKey(secret).then(function (key) {
      return crypto.subtle.sign("HMAC", key, msg);
    }).then(function (sig) {
      var h = new Uint8Array(sig);
      var o = h[h.length - 1] & 15;
      var bin = ((h[o] & 127) << 24) | (h[o + 1] << 16) | (h[o + 2] << 8) | h[o + 3];
      return { code: String(bin % 1000000).padStart(6, "0"), hmac: h };
    });
  }

  var codesEl = document.getElementById("codes");
  var cards = [];

  function buildDigit() {
    var d = document.createElement("span");
    d.className = "d";
    var u = document.createElement("span");
    u.className = "u";
    var l = document.createElement("span");
    l.className = "l";
    d.appendChild(u);
    d.appendChild(l);
    return { el: d, u: u, l: l, value: "" };
  }

  ACCOUNTS.forEach(function (acc) {
    var card = document.createElement("button");
    card.type = "button";
    card.className = "card";
    var id = document.createElement("span");
    id.className = "card-id";
    id.innerHTML = "<b></b><span></span>";
    id.firstChild.textContent = acc[0];
    id.lastChild.textContent = acc[1];
    var ring = document.createElement("span");
    ring.className = "ring";
    ring.setAttribute("aria-hidden", "true");
    ring.innerHTML = '<i class="trk"></i><i class="acc"></i><i class="half hr"><i class="arc"></i></i><i class="half hl"><i class="arc"></i></i>';
    var code = document.createElement("span");
    code.className = "code";
    var digits = [];
    for (var i = 0; i < 6; i++) {
      if (i === 3) {
        var gap = document.createElement("span");
        gap.className = "gap";
        code.appendChild(gap);
      }
      var dg = buildDigit();
      digits.push(dg);
      code.appendChild(dg.el);
    }
    var tag = document.createElement("span");
    tag.className = "copied-tag";
    card.appendChild(id);
    card.appendChild(ring);
    card.appendChild(code);
    card.appendChild(tag);
    codesEl.appendChild(card);
    var entry = { el: card, digits: digits, secret: acc[2], issuer: acc[0], code: "", ring: ring };
    card.addEventListener("click", function () {
      copyCode(entry);
    });
    cards.push(entry);
  });

  // 设置单个数字；animate 为真时播放翻牌
  function setDigit(dg, value, animate, delay) {
    if (dg.value === value) {
      return;
    }
    var old = dg.value;
    dg.value = value;
    if (!animate || !old || reduceMotion.matches) {
      dg.u.textContent = value;
      dg.l.textContent = value;
      return;
    }
    setTimeout(function () {
      var fu = document.createElement("span");
      fu.className = "fu";
      fu.textContent = old;
      var fl = document.createElement("span");
      fl.className = "fl";
      fl.textContent = value;
      dg.u.textContent = value;
      dg.l.textContent = old;
      dg.el.appendChild(fu);
      dg.el.appendChild(fl);
      setTimeout(function () {
        dg.l.textContent = dg.value;
        if (fu.parentNode) {
          fu.parentNode.removeChild(fu);
        }
        if (fl.parentNode) {
          fl.parentNode.removeChild(fl);
        }
      }, 460);
    }, delay);
  }

  var lastCounter = -1;
  var running = true;

  function refreshCodes(animate) {
    var counter = Math.floor(Date.now() / 1000 / PERIOD);
    if (counter === lastCounter) {
      return;
    }
    lastCounter = counter;
    Promise.all(cards.map(function (c) {
      return totp(c.secret, counter);
    })).then(function (results) {
      results.forEach(function (res, ci) {
        var c = cards[ci];
        c.code = res.code;
        c.el.setAttribute("aria-label", c.issuer + " " + res.code.slice(0, 3) + " " + res.code.slice(3));
        for (var i = 0; i < 6; i++) {
          setDigit(c.digits[i], res.code.charAt(i), animate, ci * 70 + i * 35);
        }
      });
      updatePipeline(counter, results[0]);
    });
  }

  // 原理区：展示第一个示例账户的实时计算过程
  var pvT = document.getElementById("pv-t");
  var pvH = document.getElementById("pv-h");
  var pvC = document.getElementById("pv-c");
  var dgCode = document.getElementById("dg-code");

  function bump(el) {
    el.classList.remove("bump");
    void el.offsetWidth;
    el.classList.add("bump");
  }

  function updatePipeline(counter, res) {
    pvT.textContent = String(counter);
    if (res.hmac) {
      var hex = "";
      for (var i = 0; i < 10; i++) {
        hex += (res.hmac[i] < 16 ? "0" : "") + res.hmac[i].toString(16);
      }
      pvH.textContent = hex.replace(/(.{4})/g, "$1 ").trim() + " …";
    } else {
      pvH.textContent = "—";
    }
    var pretty = res.code.slice(0, 3) + " " + res.code.slice(3);
    pvC.textContent = pretty;
    dgCode.textContent = pretty;
    [pvT, pvH, pvC].forEach(bump);
  }

  // 圆环用负的 animation-delay 对齐真实时钟
  function syncRings() {
    var elapsed = (Date.now() / 1000) % PERIOD;
    var arcs = codesEl.querySelectorAll(".arc");
    for (var i = 0; i < arcs.length; i++) {
      arcs[i].style.animation = "none";
    }
    void codesEl.offsetWidth;
    for (var j = 0; j < arcs.length; j++) {
      arcs[j].style.animation = "";
      arcs[j].style.animationDelay = (-elapsed).toFixed(3) + "s";
    }
  }

  // 节拍条
  var ticksEl = document.getElementById("ticks");
  var beatSec = document.getElementById("beat-sec");
  var ticks = [];
  for (var ti = 0; ti < PERIOD; ti++) {
    var tick = document.createElement("i");
    ticksEl.appendChild(tick);
    ticks.push(tick);
  }

  function updateBeat() {
    var sec = Math.floor(Date.now() / 1000) % PERIOD;
    var remain = PERIOD - sec;
    beatSec.textContent = String(remain);
    for (var i = 0; i < ticks.length; i++) {
      ticks[i].className = i < sec ? "past" : (i === sec ? "now" : "");
    }
    var warn = remain <= 5;
    for (var c = 0; c < cards.length; c++) {
      cards[c].el.classList.toggle("warn", warn);
    }
  }

  var tickTimer = 0;

  function loop() {
    clearTimeout(tickTimer);
    if (!running) {
      return;
    }
    refreshCodes(true);
    updateBeat();
    // 对齐到下一个整秒
    tickTimer = setTimeout(loop, 1000 - (Date.now() % 1000) + 15);
  }

  function resume() {
    if (running) {
      return;
    }
    running = true;
    document.getElementById("stage").classList.remove("paused");
    syncRings();
    refreshCodes(false);
    loop();
  }

  function pause() {
    running = false;
    clearTimeout(tickTimer);
    document.getElementById("stage").classList.add("paused");
  }

  var stageVisible = true;
  document.addEventListener("visibilitychange", function () {
    if (document.hidden) {
      pause();
    } else if (stageVisible) {
      resume();
    }
  });

  // 复制演示验证码
  var toast = document.getElementById("toast");
  var toastTimer = 0;

  function showToast(text) {
    toast.textContent = text;
    toast.classList.add("show");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () {
      toast.classList.remove("show");
    }, 1800);
  }

  function copyCode(entry) {
    if (!entry.code) {
      return;
    }
    var done = function () {
      entry.el.querySelector(".copied-tag").textContent = t("copiedTag");
      entry.el.classList.add("copied");
      setTimeout(function () {
        entry.el.classList.remove("copied");
      }, 1400);
      showToast(t("copied").replace("{c}", entry.code));
    };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(entry.code).then(done, done);
    } else {
      done();
    }
  }

  // ===== 下载直链与版本号 =====
  function renderVersion() {
    var text = "";
    if (latest) {
      text = t("latest").replace("{v}", latest.tag).replace("{d}", latest.date);
    }
    document.getElementById("ver-hero").textContent = text;
    document.getElementById("ver-dl").textContent = text;
  }

  function formatSize(bytes) {
    return (bytes / 1048576).toFixed(1) + " MB";
  }

  function loadRelease() {
    if (!window.fetch) {
      return;
    }
    fetch("https://api.github.com/repos/" + REPO + "/releases/latest", { headers: { Accept: "application/vnd.github+json" } })
      .then(function (r) {
        return r.ok ? r.json() : null;
      })
      .then(function (rel) {
        if (!rel || !rel.tag_name) {
          return;
        }
        latest = { tag: rel.tag_name, date: String(rel.published_at || "").slice(0, 10) };
        (rel.assets || []).forEach(function (a) {
          var url = a.browser_download_url;
          if (/-arm64\.dmg$/i.test(a.name)) {
            document.getElementById("dl-arm").href = url;
            document.getElementById("dl-arm-2").href = url;
            document.getElementById("sz-arm").textContent = "arm64 · " + formatSize(a.size);
          } else if (/-x86_64\.dmg$/i.test(a.name)) {
            document.getElementById("dl-intel").href = url;
            document.getElementById("dl-intel-2").href = url;
            document.getElementById("sz-intel").textContent = "x86_64 · " + formatSize(a.size);
          } else if (/\.ipa$/i.test(a.name)) {
            document.getElementById("dl-ipa").href = url;
            document.getElementById("sz-ipa").textContent = "Ad Hoc · " + formatSize(a.size);
          }
        });
        renderVersion();
      })
      .catch(function () {});
  }

  // Intel Mac 粗略识别：仅在 Mac 上用 WebGL 渲染器名判断，识别失败保持 Apple 芯片优先
  function preferIntel() {
    if (!/Macintosh/.test(navigator.userAgent) || navigator.maxTouchPoints > 1) {
      return;
    }
    try {
      var gl = document.createElement("canvas").getContext("webgl");
      var info = gl && gl.getExtension("WEBGL_debug_renderer_info");
      var renderer = info ? gl.getParameter(info.UNMASKED_RENDERER_WEBGL) : "";
      if (/Intel|AMD|Radeon/i.test(renderer) && !/Apple/i.test(renderer)) {
        var arm = document.getElementById("dl-arm");
        var intel = document.getElementById("dl-intel");
        arm.className = "btn btn-ghost";
        intel.className = "btn btn-primary";
        arm.parentNode.insertBefore(intel, arm);
      }
    } catch (e) {}
  }

  // ===== 滚动渐入与视口暂停 =====
  function setupObservers() {
    var reveals = document.querySelectorAll(".reveal");
    var diagram = document.getElementById("diagram");
    if (!("IntersectionObserver" in window)) {
      for (var i = 0; i < reveals.length; i++) {
        reveals[i].classList.add("in");
      }
      diagram.classList.add("run");
      return;
    }
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) {
          e.target.classList.add("in");
          io.unobserve(e.target);
        }
      });
    }, { rootMargin: "0px 0px -8% 0px", threshold: 0.08 });
    for (var j = 0; j < reveals.length; j++) {
      io.observe(reveals[j]);
    }
    // 示意图离开视口时停止数据点动画
    new IntersectionObserver(function (entries) {
      diagram.classList.toggle("run", entries[0].isIntersecting && !reduceMotion.matches);
    }).observe(diagram);
    // 首屏卡片离开视口时暂停计时
    new IntersectionObserver(function (entries) {
      stageVisible = entries[0].isIntersecting;
      if (stageVisible && !document.hidden) {
        resume();
      } else if (!stageVisible) {
        pause();
      }
    }).observe(document.getElementById("stage"));
  }

  // ===== 启动 =====
  var initialPref = root.dataset.themePref || "system";
  applyTheme(initialPref, false);
  applyLang(detectLang(), false);
  if (!subtleOK) {
    document.getElementById("stage-note").textContent = t("stageNoteFallback");
  }
  syncRings();
  refreshCodes(false);
  loop();
  setupObservers();
  preferIntel();
  loadRelease();
})();
