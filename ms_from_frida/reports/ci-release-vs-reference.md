# 编译结果对比

| 项目 | 结果 |
|---|---|
| 文件清单 |  |

## 逐文件分析

| 文件 | 类型/架构 | ELF 动态依赖 | 符号差异 | 内容哈希 | 综合判断 |
|---|---|---|---|---|---|
| `frida-code-inject.android-arm64` | `ELF 64-bit LSB shared object, ARM aarch64, version 1 (SYSV), dynamically linked, interpreter /system/bin/linker64, stripped` / `ELF 64-bit LSB shared object, ARM aarch64, version 1 (SYSV), dynamically linked, interpreter /system/bin/linker64, stripped` | `libc.so,libdl.so,liblog.so,libm.so,` / `libc.so,libdl.so,liblog.so,libm.so,` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` / `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` | `b66c704cc965` / `b420ba3dea97` | 结构/ABI等价，内容不同 |
| `frida-code-inject.android-x86_64` | `ELF 64-bit LSB shared object, x86-64, version 1 (SYSV), dynamically linked, interpreter /system/bin/linker64, stripped` / `ELF 64-bit LSB shared object, x86-64, version 1 (SYSV), dynamically linked, interpreter /system/bin/linker64, stripped` | `libc.so,libdl.so,liblog.so,libm.so,` / `libc.so,libdl.so,liblog.so,libm.so,` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` / `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` | `63f44695b97f` / `f11d56db2d26` | 结构/ABI等价，内容不同 |
| `frida-so-inject.android-arm64` | `ELF 64-bit LSB shared object, ARM aarch64, version 1 (SYSV), dynamically linked, interpreter /system/bin/linker64, stripped` / `ELF 64-bit LSB shared object, ARM aarch64, version 1 (SYSV), dynamically linked, interpreter /system/bin/linker64, stripped` | `libc.so,libdl.so,liblog.so,libm.so,` / `libc.so,libdl.so,liblog.so,libm.so,` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` / `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` | `6706c679775c` / `454ae4a0f547` | 结构/ABI等价，内容不同 |
| `frida-so-inject.android-x86_64` | `ELF 64-bit LSB shared object, x86-64, version 1 (SYSV), dynamically linked, interpreter /system/bin/linker64, stripped` / `ELF 64-bit LSB shared object, x86-64, version 1 (SYSV), dynamically linked, interpreter /system/bin/linker64, stripped` | `libc.so,libdl.so,liblog.so,libm.so,` / `libc.so,libdl.so,liblog.so,libm.so,` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` / `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` | `210d1621c82f` / `847fdaaf8a15` | 结构/ABI等价，内容不同 |
| `gadget.so.android-arm64` | `ELF 64-bit LSB shared object, ARM aarch64, version 1 (SYSV), dynamically linked, stripped` / `ELF 64-bit LSB shared object, ARM aarch64, version 1 (SYSV), dynamically linked, stripped` | `libc.so,libdl.so,liblog.so,libm.so,` / `libc.so,libdl.so,liblog.so,libm.so,` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` / `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` | `dbd452644898` / `8e76347b897b` | 结构/ABI等价，内容不同 |
| `gadget.so.android-x86_64` | `ELF 64-bit LSB shared object, x86-64, version 1 (SYSV), dynamically linked, stripped` / `ELF 64-bit LSB shared object, x86-64, version 1 (SYSV), dynamically linked, stripped` | `libc.so,libdl.so,liblog.so,libm.so,` / `libc.so,libdl.so,liblog.so,libm.so,` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` / `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` | `fe531e4cf227` / `28a8aa5993a5` | 结构/ABI等价，内容不同 |
| `ms_server.android-arm64` | `ELF 64-bit LSB shared object, ARM aarch64, version 1 (SYSV), dynamically linked, interpreter /system/bin/linker64, stripped` / `ELF 64-bit LSB shared object, ARM aarch64, version 1 (SYSV), dynamically linked, interpreter /system/bin/linker64, stripped` | `libc.so,libdl.so,liblog.so,libm.so,` / `libc.so,libdl.so,liblog.so,libm.so,` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` / `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` | `3ff06f7d67f5` / `95dff77d6350` | 结构/ABI等价，内容不同 |
| `ms_server.android-x86_64` | `ELF 64-bit LSB shared object, x86-64, version 1 (SYSV), dynamically linked, interpreter /system/bin/linker64, stripped` / `ELF 64-bit LSB shared object, x86-64, version 1 (SYSV), dynamically linked, interpreter /system/bin/linker64, stripped` | `libc.so,libdl.so,liblog.so,libm.so,` / `libc.so,libdl.so,liblog.so,libm.so,` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` / `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` | `034af040e5a8` / `5dc78e8d3a4f` | 结构/ABI等价，内容不同 |

## 判定原则

- 哈希仅用于确认完全一致，不作为唯一判定。
- 优先比较文件清单、文件类型、架构、ELF 依赖和导出符号。
- 对 ABI/符号一致但哈希不同的产物，继续检查 Build ID、编译路径、时间戳、debug 信息等可变字段。
- 最终发布前还应执行 frida-server 启动、客户端连接和最小注入行为测试。
