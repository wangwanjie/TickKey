# TickKey 加密备份 v1

文件头为 10 个 UTF-8 字节 `TickKey/1\n`。其后为 JSON 对象：

- `version`：整数 1。
- `rounds`：整数 600000，导入严格校验，避免攻击者控制 KDF 消耗。
- `salt`：16 随机字节，标准 Base64。
- `sealed`：标准 Base64；12 字节 GCM nonce + 密文 + 16 字节认证 tag。

密码直接使用 UTF-8 字节，不做 Unicode 规范化。PBKDF2-HMAC-SHA256、600000 次迭代、上述 salt，派生 32 字节 AES 密钥。AES-256-GCM 的 AAD 是文件头字节加 salt 原始字节。每次导出随机生成 salt 和 nonce。

明文是 JSON 数组，每项为 `id`（UUID）、`issuer`、`account`、`secret`（Base32）、`algorithm`（SHA1 / SHA256 / SHA512）、`digits`、`period`。JSON 字段顺序无要求。导入时重新分配本地 UUID；去重忽略 UUID。

最大文件 16 MiB，最多 10000 项。未知版本、认证失败、密码错误、损坏数据或任一无效账户均拒绝整个导入。加密格式可由任何遵循此公开协议的软件实现；安全性由密码和标准密码算法提供，不依赖源码保密。

常规文本为 UTF-8，每行一条标准 otpauth URI，接受 CRLF、空行和 UTF-8 BOM，不接受只有裸密钥而没有账户元数据的行。
