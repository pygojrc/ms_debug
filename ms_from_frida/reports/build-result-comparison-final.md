# 编译结果对比（最终）

| 架构 | 复现 | 参考源码 | GitHub Release | 结构/ABI/依赖/符号 |
|---|---:|---:|---:|---|
| `android-arm64` | 53,513,920 | 53,513,920 | 53,513,920 | 一致；复现与参考源码逐字节一致 |
| `android-x86_64` | 111,496,288 | 111,504,480 | 111,504,480 | 一致；差异来自绝对构建路径等可变内容 |

## SHA-256

| 架构 | 复现 | 参考源码 | Release |
|---|---|---|---|
| `android-arm64` | `f19aebbec45af4e8064dafeb116f7231c20f3ac89c95f4380daeb90e5c0b1142` | `f19aebbec45af4e8064dafeb116f7231c20f3ac89c95f4380daeb90e5c0b1142` | `3ff06f7d67f5f577ffd6bb6c574d3c4a37cd61f86937359e2dc4e215c7a39661` |
| `android-x86_64` | `c4b7e1d38e12da5eb9d413d1d46a8329942e4534cf8e203b6b666f1b192c26b5` | `8e5c446d7680ada2c54c856d691df13ae8fdd73b312ac075b76ff2dc5b6ac843` | `034af040e5a8b0ea5e69ef6cd8cdce02c421cd11da13f99c65d71e0852efa1b2` |

哈希只用于确认逐字节一致；同时检查 ELF 类型/架构、动态依赖、导出符号、静态库成员和关键字符串。x86_64 对象差异中已确认包含 `work/frida` 与 `reference/frida` 绝对路径。真实 Android 设备启动、连接和最小注入测试仍需执行。
