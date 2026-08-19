# Frida 17.15.3 双架构构建结果

构建目标：`frida-server`

| 架构 | 产物 | 文件类型 | 大小 | SHA-256 |
|---|---|---|---:|---|
| `android-arm64` | `bin/android-arm64/ms_server` | `ELF 64-bit LSB shared object, ARM aarch64, version 1 (SYSV), dynamically linked, interpreter /system/bin/linker64, stripped` | 53497464 | `ae0fce5b789444323cfcec42bd3017e4e19bbbf0d45be2e6b72d29f7e29b5f11` |
| `android-x86` | `bin/android-x86/ms_server` | `ELF 32-bit LSB shared object, Intel 80386, version 1 (SYSV), dynamically linked, interpreter /system/bin/linker, stripped` | 53894256 | `abf188b95773813d72da9ddbdfbe99e677ef9d55c4d7606efdf225bcd2c3c83d` |

## ELF 核心信息
### android-arm64
ms_debug/ms_from_frida/work/frida/bin/android-arm64/ms_server: ELF 64-bit LSB shared object, ARM aarch64, version 1 (SYSV), dynamically linked, interpreter /system/bin/linker64, stripped
  Class:                             ELF64
  OS/ABI:                            UNIX - System V
  Type:                              DYN (Shared object file)
  Machine:                           AArch64
  Entry point address:               0x490000
 0x0000000000000001 (NEEDED)             Shared library: [libm.so]
 0x0000000000000001 (NEEDED)             Shared library: [liblog.so]
 0x0000000000000001 (NEEDED)             Shared library: [libdl.so]
 0x0000000000000001 (NEEDED)             Shared library: [libc.so]

### android-x86
ms_debug/ms_from_frida/work/frida/bin/android-x86/ms_server: ELF 32-bit LSB shared object, Intel 80386, version 1 (SYSV), dynamically linked, interpreter /system/bin/linker, stripped
  Class:                             ELF32
  OS/ABI:                            UNIX - System V
  Type:                              DYN (Shared object file)
  Machine:                           Intel 80386
  Entry point address:               0x502000
 0x00000001 (NEEDED)                     Shared library: [libm.so]
 0x00000001 (NEEDED)                     Shared library: [liblog.so]
 0x00000001 (NEEDED)                     Shared library: [libdl.so]
 0x00000001 (NEEDED)                     Shared library: [libc.so]

## 判定

- ARM64 和 x86 均已完成 `frida-server` 构建。
- 两个架构的 SHA-256 不应相同；架构、ELF machine、依赖和符号应分别检查。
- `ms_debug` 仓库未提交参考二进制，因此当前完成的是复现构建和结构化产物记录，尚未完成与另一份 ms_debug 二进制的同架构对比。
- 产物行为验证仍需在对应 Android ARM64/x86 设备或模拟器中执行启动、连接和最小注入测试。

## 最终双架构验证（2026-08-19）

脚本已下载并使用 Android NDK r29、Frida SDK `android-arm64`/`android-x86_64` 及 Linux host toolchain，完成：

| host | ELF 架构 | 产物 | 大小 | SHA-256 |
|---|---|---|---:|---|
| `android-arm64` | AArch64 | `work/frida/bin/android-arm64/ms_server` | 53,513,920 | `f19aebbec45af4e8064dafeb116f7231c20f3ac89c95f4380daeb90e5c0b1142` |
| `android-x86_64` | x86-64 | `work/frida/bin/android-x86_64/ms_server` | 111,496,288 | `c4b7e1d38e12da5eb9d413d1d46a8329942e4534cf8e203b6b666f1b192c26b5` |

ARM64 复现构建与 `ms_debug/frida` 参考树在同一环境下构建的 ARM64 产物逐字节一致。Release 的 ARM64 和 x86_64 产物尺寸分别为 53,513,920 和 111,504,480；哈希差异可由构建路径等非功能字段解释，不能单独判定为源码或 ABI 差异。尚未在真实 Android 设备/模拟器上执行启动、连接和注入测试。
