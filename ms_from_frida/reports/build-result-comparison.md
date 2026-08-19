# 复现版与 ms_debug 源码树构建结果对比

| 架构 | 复现版大小 | ms_debug版大小 | SHA-256 | ELF/ABI | 导出符号集合 | 结论 |
|---|---:|---:|---|---|---|---|
| `android-arm64` | 53497464 | 53513920 | ae0fce5b78944432 / f19aebbec45af4e8 | 相同 | 相同 | ABI/导出符号一致，内容存在差异 |
| `android-x86` | 53894256 | 53902448 | abf188b95773813d / 50cf33fa2cce0770 | 相同 | 相同 | ABI/导出符号一致，内容存在差异 |

## 详细文件
### android-arm64
```text
ms_debug/ms_from_frida/work/frida/bin/android-arm64/ms_server: ELF 64-bit LSB shared object, ARM aarch64, version 1 (SYSV), dynamically linked, interpreter /system/bin/linker64, stripped
ms_debug/ms_from_frida/reference/frida/bin/android-arm64/ms_server: ELF 64-bit LSB shared object, ARM aarch64, version 1 (SYSV), dynamically linked, interpreter /system/bin/linker64, stripped
  Class:                             ELF64
  Type:                              DYN (Shared object file)
  Machine:                           AArch64
  Entry point address:               0x490000
  Class:                             ELF64
  Type:                              DYN (Shared object file)
  Machine:                           AArch64
  Entry point address:               0x491000
```
### android-x86
```text
ms_debug/ms_from_frida/work/frida/bin/android-x86/ms_server: ELF 32-bit LSB shared object, Intel 80386, version 1 (SYSV), dynamically linked, interpreter /system/bin/linker, stripped
ms_debug/ms_from_frida/reference/frida/bin/android-x86/ms_server: ELF 32-bit LSB shared object, Intel 80386, version 1 (SYSV), dynamically linked, interpreter /system/bin/linker, stripped
  Class:                             ELF32
  Type:                              DYN (Shared object file)
  Machine:                           Intel 80386
  Entry point address:               0x502000
  Class:                             ELF32
  Type:                              DYN (Shared object file)
  Machine:                           Intel 80386
  Entry point address:               0x502000
```

## 说明
- 复现版来自官方 Frida 17.15.3 + 本目录 patch；参考版来自 `ms_debug/frida` vendored 源码树。
- 两边使用同一 Android NDK r29、同一 SDK bundle、同一 host toolchain 和同一构建目标。
- 哈希只用于判断完全一致；ABI、动态依赖和导出符号用于判断功能等价。
